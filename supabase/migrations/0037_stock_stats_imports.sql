-- 0037_stock_stats_imports: stock and project statistics, and spreadsheet
-- imports for inventory items and tools (API.md section 20, issue #16).

-- Inventory and project numbers over a period, for one site or every site
-- the caller can see (p_site null). Read only; store.view.
create function public.fn_stock_stats(p_site uuid, p_from date, p_to date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_today date := public._harare_today();
  v_sites uuid[];
  v_out jsonb;
begin
  if p_from is null or p_to is null or p_from > p_to then
    raise exception 'INVALID: Pick a date range';
  end if;
  if p_site is null then
    select coalesce(array_agg(s.id), '{}') into v_sites
    from public.sites s where not s.is_archived and public._can('store.view', s.id);
  elsif public._can('store.view', p_site) then
    v_sites := array[p_site];
  else
    raise exception 'NOT_ALLOWED: You cannot see inventory at this site';
  end if;

  with moves as (
    select m.*, i.code as item_code, i.name as item_name, i.unit
    from public.stock_moves m
    join public.store_items i on i.id = m.item_id
    where m.site_id = any (v_sites)
      and (m.created_at at time zone 'Africa/Harare')::date between p_from and p_to
  ),
  items as (
    select * from public.store_items where site_id = any (v_sites) and not is_archived
  )
  select jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'totals', jsonb_build_object(
      'items', (select count(*) from items),
      'low', (select count(*) from items where min_level > 0 and on_hand < min_level),
      'empty', (select count(*) from items where on_hand <= 0),
      'receipts', (select count(*) from moves where kind = 'receive'),
      'issues', (select count(*) from moves where kind = 'issue'),
      'returns', (select count(*) from moves where kind = 'return'),
      'corrections', (select count(*) from moves where kind in ('adjust', 'count')),
      'requests_open', (select count(*) from public.material_requests r
        where r.site_id = any (v_sites) and r.status in ('pending', 'approved', 'part_issued')),
      'purchases_open', (select count(*) from public.purchase_orders o
        where o.site_id = any (v_sites) and o.status in ('requested', 'ordered')),
      'projects_open', (select count(*) from public.projects p
        where p.site_id = any (v_sites) and not p.is_archived and p.status in ('active', 'on_hold')),
      'projects_overdue', (select count(*) from public.projects p
        where p.site_id = any (v_sites) and not p.is_archived and p.status in ('active', 'on_hold')
          and p.target_date < v_today)
    ),
    -- What went out most, by item.
    'top_items', coalesce((select jsonb_agg(x order by (x ->> 'qty')::numeric desc) from (
      select jsonb_build_object('item_id', item_id, 'code', item_code, 'name', item_name, 'unit', unit,
        'qty', -sum(qty), 'issues', count(*)) as x
      from moves where kind = 'issue'
      group by item_id, item_code, item_name, unit
      order by -sum(qty) desc
      limit 15) t), '[]'),
    -- Stock used per project, item by item.
    'projects', coalesce((select jsonb_agg(x order by x ->> 'code') from (
      select jsonb_build_object(
        'project_id', p.id, 'code', p.code, 'name', p.name, 'status', p.status,
        'jobs_total', o.jobs_total, 'jobs_done', o.jobs_done, 'target_date', p.target_date,
        'items', coalesce((select jsonb_agg(jsonb_build_object('name', m.item_name, 'unit', m.unit, 'qty', m.qty)
            order by m.item_name)
          from (select item_name, unit, -sum(qty) as qty from moves
            where kind = 'issue' and project_id = p.id group by item_name, unit) m), '[]')) as x
      from public.projects p
      join public.project_overview o on o.id = p.id
      where p.site_id = any (v_sites) and not p.is_archived
        and (p.status in ('active', 'on_hold') or exists (select 1 from moves where project_id = p.id))) t), '[]'),
    -- Job cards that took the most stock moves.
    'jobs', coalesce((select jsonb_agg(x order by (x ->> 'issues')::int desc) from (
      select jsonb_build_object('job_card_id', j.id, 'number', j.number, 'title', j.title,
        'issues', count(*)) as x
      from moves m join public.job_cards j on j.id = m.job_card_id
      where m.kind = 'issue'
      group by j.id, j.number, j.title
      order by count(*) desc
      limit 10) t), '[]'),
    -- Corrections: adjustments and counts, with their reasons.
    'corrections', coalesce((select jsonb_agg(jsonb_build_object('item_id', item_id, 'code', item_code,
        'name', item_name, 'unit', unit, 'qty', qty, 'kind', kind, 'note', note, 'at', created_at)
        order by created_at desc)
      from (select * from moves where kind in ('adjust', 'count') order by created_at desc limit 50) c), '[]'),
    'low', coalesce((select jsonb_agg(jsonb_build_object('item_id', id, 'code', code, 'name', name,
        'unit', unit, 'on_hand', on_hand, 'min_level', min_level) order by on_hand / nullif(min_level, 0))
      from items where min_level > 0 and on_hand < min_level), '[]')
  ) into v_out;
  return v_out;
end;
$$;

-- Imports inventory items from a spreadsheet (store.adjust): p_rows is
-- [{name, unit, category, bin, min_level, on_hand}]. An item already there
-- (same name and unit) gets its category, bin and minimum updated; a new
-- one is created, and its on_hand is received as opening stock. Returns
-- {created, updated}.
create function public.fn_import_items(p_site uuid, p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  x jsonb;
  v_name text;
  v_unit text;
  v_cat text;
  v_id uuid;
  v_qty numeric;
  v_created integer := 0;
  v_updated integer := 0;
begin
  if not public._can('store.adjust', p_site) then
    raise exception 'NOT_ALLOWED: Only the store can import items';
  end if;
  if jsonb_typeof(coalesce(p_rows, '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_rows, '[]'::jsonb)) = 0 then
    raise exception 'INVALID: Nothing to import';
  end if;
  if jsonb_array_length(p_rows) > 2000 then
    raise exception 'INVALID: Import at most 2000 rows at a time';
  end if;
  for x in select * from jsonb_array_elements(p_rows) loop
    v_name := trim(coalesce(x ->> 'name', ''));
    if length(v_name) < 2 then
      continue;
    end if;
    v_unit := coalesce(nullif(lower(trim(coalesce(x ->> 'unit', ''))), ''), 'pcs');
    v_cat := lower(trim(coalesce(x ->> 'category', '')));
    if v_cat not in ('cable', 'breakers', 'lugs', 'glands', 'lamps', 'fittings', 'consumables', 'other') then
      v_cat := 'other';
    end if;
    select id into v_id from public.store_items
    where site_id = p_site and not is_archived and lower(name) = lower(v_name) and lower(unit) = v_unit;
    if found then
      update public.store_items
      set category = v_cat,
          bin = coalesce(nullif(trim(coalesce(x ->> 'bin', '')), ''), bin),
          min_level = coalesce(nullif(x ->> 'min_level', '')::numeric, min_level)
      where id = v_id;
      v_updated := v_updated + 1;
    else
      v_id := gen_random_uuid();
      perform public.fn_save_item(v_id, p_site, v_name, v_unit, v_cat, x ->> 'bin',
        coalesce(nullif(x ->> 'min_level', '')::numeric, 0), false);
      v_qty := nullif(x ->> 'on_hand', '')::numeric;
      if v_qty > 0 then
        perform public._stock_move(gen_random_uuid(), v_id, 'receive', v_qty, null, null, null, 'Opening stock');
      end if;
      v_created := v_created + 1;
    end if;
  end loop;
  return jsonb_build_object('created', v_created, 'updated', v_updated);
end;
$$;

-- Imports tools into the register (tools.issue): p_rows is [{name, kind,
-- serial_no, calibration_due}]. A row whose serial number is already in the
-- site's register is skipped. Returns {created, skipped}.
create function public.fn_import_tools(p_site uuid, p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  x jsonb;
  v_serial text;
  v_created integer := 0;
  v_skipped integer := 0;
begin
  if not public._can('tools.issue', p_site) then
    raise exception 'NOT_ALLOWED: Only the store or a supervisor can import tools';
  end if;
  if jsonb_typeof(coalesce(p_rows, '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_rows, '[]'::jsonb)) = 0 then
    raise exception 'INVALID: Nothing to import';
  end if;
  if jsonb_array_length(p_rows) > 2000 then
    raise exception 'INVALID: Import at most 2000 rows at a time';
  end if;
  for x in select * from jsonb_array_elements(p_rows) loop
    if length(trim(coalesce(x ->> 'name', ''))) < 2 then
      continue;
    end if;
    v_serial := nullif(trim(coalesce(x ->> 'serial_no', '')), '');
    if v_serial is not null and exists (
      select 1 from public.tools where site_id = p_site and not is_archived and lower(serial_no) = lower(v_serial)
    ) then
      v_skipped := v_skipped + 1;
      continue;
    end if;
    perform public.fn_save_tool(gen_random_uuid(), p_site, trim(x ->> 'name'),
      nullif(trim(coalesce(x ->> 'kind', '')), ''), v_serial,
      nullif(x ->> 'calibration_due', '')::date, null, 'good', false);
    v_created := v_created + 1;
  end loop;
  return jsonb_build_object('created', v_created, 'skipped', v_skipped);
end;
$$;

revoke execute on function
  public.fn_stock_stats(uuid, date, date),
  public.fn_import_items(uuid, jsonb),
  public.fn_import_tools(uuid, jsonb)
from public, anon;
grant execute on function
  public.fn_stock_stats(uuid, date, date),
  public.fn_import_items(uuid, jsonb),
  public.fn_import_tools(uuid, jsonb)
to authenticated;

insert into public.schema_migrations (filename) values ('0037_stock_stats_imports.sql')
on conflict do nothing;
