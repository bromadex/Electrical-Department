-- 0041_equipment_history_reserved_stock: issues #33 and #34.
--
-- Equipment history (#33): fn_equipment_history(site, days) lists, per piece
-- of equipment, its faults (corrective, emergency and reactive job cards)
-- in the period and in the last 30 days, when it last failed, and how long
-- it was out of service: the time job cards that found it out of service
-- were open (received until closed or cancelled, or until now), overlaps
-- counted once and clipped to the period. Repeat faults are equipment with
-- several faults in 30 days.
--
-- Reserved stock (#34): stock asked for on approved material requests and
-- not yet issued is reserved. store_item_availability shows on hand,
-- reserved and available per item; nothing stores it, so approving reserves
-- and issuing or cancelling releases by themselves. A project's BOQ counts
-- as in stock only what is not reserved for someone else.

create function public.fn_equipment_history(p_site uuid, p_days integer default 90)
returns table (
  asset_id uuid,
  site_id uuid,
  tag text,
  name text,
  faults integer,
  faults_30 integer,
  last_fault_at timestamptz,
  down_hours numeric,
  down_now boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  with params as (
    select now() - make_interval(days => greatest(least(coalesce(p_days, 90), 3650), 1)) as since
  ),
  jobs as (
    select j.asset_id, j.received_at, j.equipment_state, j.status,
      j.maintenance_type in ('corrective', 'emergency', 'reactive') as is_fault,
      tstzrange(j.received_at, coalesce(j.closed_at, j.cancelled_at, now())) as span
    from public.job_cards j, params
    where j.asset_id is not null and not j.is_archived
      and coalesce(j.closed_at, j.cancelled_at, now()) >= params.since
  )
  select a.id, a.site_id, a.tag, a.name,
    (select count(*) from jobs, params where jobs.asset_id = a.id and jobs.is_fault
      and jobs.received_at >= params.since)::integer,
    (select count(*) from jobs where jobs.asset_id = a.id and jobs.is_fault
      and jobs.received_at >= now() - interval '30 days')::integer,
    (select max(received_at) from jobs where jobs.asset_id = a.id and jobs.is_fault),
    coalesce((
      select round((sum(extract(epoch from upper(r) - lower(r))) / 3600)::numeric, 1)
      from params,
        unnest((select range_agg(jobs.span * tstzrange(params.since, now()))
                from jobs where jobs.asset_id = a.id and jobs.equipment_state = 'out_of_service')) r
    ), 0),
    exists (select 1 from jobs where jobs.asset_id = a.id and jobs.equipment_state = 'out_of_service'
      and jobs.status not in ('closed', 'cancelled'))
  from public.assets a
  where not a.is_archived
    and (p_site is null or a.site_id = p_site)
    and public._can('assets.view', a.site_id)
    and exists (select 1 from jobs where jobs.asset_id = a.id)
  order by 6 desc, 5 desc, 8 desc;
$$;

-- On hand, reserved for approved requests not yet issued, and available.
create view public.store_item_availability with (security_invoker = true) as
select i.id as item_id, i.site_id, i.on_hand,
  coalesce(res.qty, 0)::numeric(12, 2) as reserved,
  greatest(i.on_hand - coalesce(res.qty, 0), 0)::numeric(12, 2) as available
from public.store_items i
left join lateral (
  select sum(greatest(ml.qty - ml.issued_qty, 0)) as qty
  from public.mr_lines ml join public.material_requests r on r.id = ml.mr_id
  where ml.item_id = i.id and r.status in ('approved', 'part_issued')
) res on true
where not i.is_archived;

create or replace view public.boq_status with (security_invoker = true) as
with lines as (
  select b.*, p.site_id from public.boq_lines b join public.projects p on p.id = b.project_id
  where not b.is_archived
)
select l.id, l.project_id, l.site_id, l.item_id, l.description, l.unit, l.qty,
  coalesce(iss.qty, 0)::numeric(12, 2) as issued,
  coalesce(req.qty, 0)::numeric(12, 2) as requested,
  coalesce(ord.qty, 0)::numeric(12, 2) as on_order,
  -- In stock and not reserved for another project's or job's request.
  greatest(coalesce(si.on_hand, 0) - coalesce(oth.qty, 0), 0)::numeric(12, 2) as in_stock,
  greatest(l.qty - coalesce(iss.qty, 0), 0)::numeric(12, 2) as still_needed,
  greatest(l.qty - coalesce(iss.qty, 0) - coalesce(req.qty, 0) - coalesce(ord.qty, 0), 0)::numeric(12, 2) as to_request
from lines l
left join public.store_items si on si.id = l.item_id
left join lateral (
  select -sum(m.qty) as qty from public.stock_moves m
  where m.project_id = l.project_id and m.item_id = l.item_id and m.kind = 'issue'
) iss on l.item_id is not null
left join lateral (
  select sum(ml.qty - ml.issued_qty) as qty from public.mr_lines ml
  join public.material_requests r on r.id = ml.mr_id
  where r.project_id = l.project_id and r.status in ('pending', 'approved', 'part_issued')
    and (ml.item_id = l.item_id or (l.item_id is null and lower(ml.description) = lower(l.description)))
) req on true
left join lateral (
  select sum(pl.qty - pl.received_qty) as qty from public.po_lines pl
  join public.purchase_orders o on o.id = pl.po_id
  left join public.mr_lines ml on ml.id = pl.mr_line_id
  left join public.material_requests r on r.id = ml.mr_id
  where o.status in ('requested', 'ordered') and r.project_id = l.project_id
    and (pl.item_id = l.item_id or (l.item_id is null and lower(pl.description) = lower(l.description)))
) ord on true
left join lateral (
  select sum(greatest(ml.qty - ml.issued_qty, 0)) as qty from public.mr_lines ml
  join public.material_requests r on r.id = ml.mr_id
  where ml.item_id = l.item_id and r.status in ('approved', 'part_issued')
    and r.project_id is distinct from l.project_id
) oth on l.item_id is not null;

revoke all on public.store_item_availability from anon;
revoke insert, update, delete on public.store_item_availability, public.boq_status from authenticated;
grant select on public.store_item_availability to authenticated;

revoke execute on function public.fn_equipment_history(uuid, integer) from public, anon;
grant execute on function public.fn_equipment_history(uuid, integer) to authenticated;

insert into public.schema_migrations (filename) values ('0041_equipment_history_reserved_stock.sql')
on conflict do nothing;
