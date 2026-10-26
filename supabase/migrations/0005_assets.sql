-- 0005_assets: a simple asset register (API.md section 10) and two optional
-- job fields, adopted in a light form from Tafara's CMMS branch.
--
-- An asset is a piece of plant we look after (a motor, a panel, a
-- transformer). Jobs can point at one, so each asset has a job history.
-- Planned maintenance is a recurring job that names an asset: the jobs it
-- creates are marked preventive. Jobs can also say isolation (lock-out,
-- tag-out) is required before work starts.

create table public.assets (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id),
  area_id uuid references public.areas (id),
  tag text not null check (length(trim(tag)) between 1 and 40),
  name text not null check (length(trim(name)) between 2 and 120),
  kind text check (length(kind) <= 40),
  make_model text check (length(make_model) <= 120),
  serial_no text check (length(serial_no) <= 80),
  notes text check (length(notes) <= 2000),
  created_by uuid references public.profiles (id) default auth.uid(),
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- One live asset per tag at a site; an archived tag can be reused.
create unique index assets_site_tag on public.assets (site_id, lower(tag)) where not is_archived;
create index assets_site on public.assets (site_id) where not is_archived;

create trigger assets_touch before update on public.assets
  for each row execute function public.fn_touch_updated_at();
create trigger assets_activity after insert or update on public.assets
  for each row execute function public.fn_log_activity();

alter table public.jobs
  add column asset_id uuid references public.assets (id),
  add column maintenance_type text not null default 'corrective'
    check (maintenance_type in ('corrective', 'preventive')),
  add column isolation_required boolean not null default false;
create index jobs_asset on public.jobs (asset_id) where asset_id is not null;

alter table public.job_recurrences
  add column asset_id uuid references public.assets (id),
  add column isolation_required boolean not null default false;

-- True when p_asset is null or a live asset at p_site.
create function public._asset_at(p_asset uuid, p_site uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_asset is null or exists (
    select 1 from public.assets where id = p_asset and site_id = p_site and not is_archived
  );
$$;

-- ---------------------------------------------------------------------------
-- Assets: supervisors (jobs.assign) keep the register
-- ---------------------------------------------------------------------------
create function public.fn_save_asset(
  p_client_ref uuid,
  p_site uuid,
  p_area uuid,
  p_tag text,
  p_name text,
  p_kind text,
  p_make_model text,
  p_serial_no text,
  p_notes text,
  p_archived boolean
)
returns public.assets
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.assets;
begin
  if not public._can('jobs.assign', p_site) then
    raise exception 'NOT_ALLOWED: Only a supervisor can change the asset register';
  end if;
  if length(trim(coalesce(p_tag, ''))) not between 1 and 40 then
    raise exception 'INVALID: Give the asset a tag, e.g. MCC-03';
  end if;
  if length(trim(coalesce(p_name, ''))) not between 2 and 120 then
    raise exception 'INVALID: The name needs 2 to 120 characters';
  end if;
  if p_area is not null and not exists (
    select 1 from public.areas where id = p_area and site_id = p_site and not is_archived
  ) then
    raise exception 'INVALID: That area is not at this site';
  end if;
  if not coalesce(p_archived, false) and exists (
    select 1 from public.assets
    where site_id = p_site and lower(tag) = lower(trim(p_tag)) and not is_archived and id <> p_client_ref
  ) then
    raise exception 'CONFLICT: Another asset at this site already has the tag %', upper(trim(p_tag));
  end if;

  insert into public.assets as a (
    id, site_id, area_id, tag, name, kind, make_model, serial_no, notes, is_archived
  ) values (
    p_client_ref, p_site, p_area, upper(trim(p_tag)), trim(p_name),
    nullif(trim(coalesce(p_kind, '')), ''), nullif(trim(coalesce(p_make_model, '')), ''),
    nullif(trim(coalesce(p_serial_no, '')), ''), nullif(trim(coalesce(p_notes, '')), ''),
    coalesce(p_archived, false)
  )
  on conflict (id) do update set
    area_id = excluded.area_id, tag = excluded.tag, name = excluded.name, kind = excluded.kind,
    make_model = excluded.make_model, serial_no = excluded.serial_no, notes = excluded.notes,
    is_archived = excluded.is_archived
  where a.site_id = excluded.site_id
  returning * into v;
  if v.id is null then
    raise exception 'INVALID: Asset belongs to another site';
  end if;
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- Jobs and recurrences take the new fields. Same names, new trailing
-- parameters with defaults, so calls queued by older app versions still work.
-- ---------------------------------------------------------------------------
drop function public.fn_create_job(uuid, uuid, uuid, text, text, text, timestamptz, double precision, double precision);
create function public.fn_create_job(
  p_client_ref uuid,
  p_site uuid,
  p_area uuid,
  p_title text,
  p_description text,
  p_priority text,
  p_due_at timestamptz,
  p_lat double precision,
  p_lng double precision,
  p_asset uuid default null,
  p_maintenance_type text default 'corrective',
  p_isolation_required boolean default false
)
returns public.jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.jobs;
begin
  select * into v from public.jobs where id = p_client_ref;
  if found then
    return v;
  end if;
  if not public._can('jobs.create', p_site) then
    raise exception 'NOT_ALLOWED: You cannot post jobs at this site';
  end if;
  if length(trim(coalesce(p_title, ''))) not between 3 and 120 then
    raise exception 'INVALID: The title needs 3 to 120 characters';
  end if;
  if p_area is not null and not exists (
    select 1 from public.areas where id = p_area and site_id = p_site and not is_archived
  ) then
    raise exception 'INVALID: That area is not at this site';
  end if;
  if not public._asset_at(p_asset, p_site) then
    raise exception 'INVALID: That asset is not at this site';
  end if;
  if coalesce(p_maintenance_type, 'corrective') not in ('corrective', 'preventive') then
    raise exception 'INVALID: Unknown maintenance type';
  end if;

  insert into public.jobs (
    id, site_id, area_id, code, title, description, priority, due_at, lat, lng, created_by,
    asset_id, maintenance_type, isolation_required
  ) values (
    p_client_ref, p_site, p_area, public.next_code(p_site, 'J'), trim(p_title),
    nullif(trim(coalesce(p_description, '')), ''), coalesce(p_priority, 'normal'),
    p_due_at, p_lat, p_lng, auth.uid(),
    p_asset, coalesce(p_maintenance_type, 'corrective'), coalesce(p_isolation_required, false)
  )
  returning * into v;

  if v.priority = 'urgent' then
    perform public.fn_notify_permission(
      v.site_id, 'jobs.assign', 'general',
      'Urgent job ' || v.code, v.title, 'job:' || v.id
    );
  end if;
  return v;
end;
$$;

drop function public.fn_edit_job(uuid, text, text, uuid, text, timestamptz);
create function public.fn_edit_job(
  p_job uuid,
  p_title text,
  p_description text,
  p_area uuid,
  p_priority text,
  p_due_at timestamptz,
  p_asset uuid default null,
  p_maintenance_type text default null,
  p_isolation_required boolean default null
)
returns public.jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.jobs := public._job_for_write(p_job);
begin
  if not (v.created_by = auth.uid() or public._can('jobs.assign', v.site_id)) then
    raise exception 'NOT_ALLOWED: Only the poster or a supervisor can edit this job';
  end if;
  if v.status in ('done', 'cancelled') then
    raise exception 'INVALID: Closed jobs cannot be edited';
  end if;
  if length(trim(coalesce(p_title, ''))) not between 3 and 120 then
    raise exception 'INVALID: The title needs 3 to 120 characters';
  end if;
  if p_area is not null and not exists (
    select 1 from public.areas where id = p_area and site_id = v.site_id and not is_archived
  ) then
    raise exception 'INVALID: That area is not at this site';
  end if;
  if not public._asset_at(p_asset, v.site_id) then
    raise exception 'INVALID: That asset is not at this site';
  end if;
  if p_maintenance_type is not null and p_maintenance_type not in ('corrective', 'preventive') then
    raise exception 'INVALID: Unknown maintenance type';
  end if;

  -- A null maintenance type or isolation flag means "leave as is" (older
  -- app versions do not send them); the asset is always what was sent.
  update public.jobs set
    title = trim(p_title),
    description = nullif(trim(coalesce(p_description, '')), ''),
    area_id = p_area,
    priority = p_priority,
    due_at = p_due_at,
    asset_id = case when p_maintenance_type is null then asset_id else p_asset end,
    maintenance_type = coalesce(p_maintenance_type, maintenance_type),
    isolation_required = coalesce(p_isolation_required, isolation_required),
    overdue_notified_at = case when p_due_at is distinct from due_at then null else overdue_notified_at end
  where id = v.id
  returning * into v;
  return v;
end;
$$;

drop function public.fn_save_recurrence(uuid, uuid, uuid, text, text, text, text, date, integer, uuid, boolean);
create function public.fn_save_recurrence(
  p_client_ref uuid,
  p_site uuid,
  p_area uuid,
  p_title text,
  p_description text,
  p_priority text,
  p_every text,
  p_next_run date,
  p_due_days integer,
  p_assignee uuid,
  p_archived boolean,
  p_asset uuid default null,
  p_isolation_required boolean default false
)
returns public.job_recurrences
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_recurrences;
begin
  if not public._can('jobs.assign', p_site) then
    raise exception 'NOT_ALLOWED: Only a supervisor can set up recurring jobs';
  end if;
  if length(trim(coalesce(p_title, ''))) not between 3 and 120 then
    raise exception 'INVALID: The title needs 3 to 120 characters';
  end if;
  if p_assignee is not null and not public._user_can(p_assignee, 'jobs.close', p_site) then
    raise exception 'INVALID: That person cannot work jobs at this site';
  end if;
  if not public._asset_at(p_asset, p_site) then
    raise exception 'INVALID: That asset is not at this site';
  end if;
  insert into public.job_recurrences as r (
    id, site_id, area_id, title, description, priority, every, next_run, due_days, assignee_id,
    is_archived, asset_id, isolation_required
  ) values (
    p_client_ref, p_site, p_area, trim(p_title), nullif(trim(coalesce(p_description, '')), ''),
    p_priority, p_every, p_next_run, p_due_days, p_assignee, coalesce(p_archived, false),
    p_asset, coalesce(p_isolation_required, false)
  )
  on conflict (id) do update set
    area_id = excluded.area_id, title = excluded.title, description = excluded.description,
    priority = excluded.priority, every = excluded.every, next_run = excluded.next_run,
    due_days = excluded.due_days, assignee_id = excluded.assignee_id,
    is_archived = excluded.is_archived, asset_id = excluded.asset_id,
    isolation_required = excluded.isolation_required
  where r.site_id = excluded.site_id
  returning * into v;
  if v.id is null then
    raise exception 'INVALID: Recurring job belongs to another site';
  end if;
  return v;
end;
$$;

-- Recurring jobs that name an asset are planned (preventive) maintenance.
create or replace function public.fn_run_recurrences()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.job_recurrences;
  v_today date := (now() at time zone 'Africa/Harare')::date;
  v_job public.jobs;
  v_count integer := 0;
begin
  for r in
    select * from public.job_recurrences
    where not is_archived and next_run <= v_today
    for update skip locked
  loop
    insert into public.jobs (
      site_id, area_id, code, title, description, priority, due_at,
      created_by, assignee_id, status, taken_at, recurrence_id,
      asset_id, maintenance_type, isolation_required
    ) values (
      r.site_id, r.area_id, public.next_code(r.site_id, 'J'), r.title, r.description,
      r.priority,
      ((v_today + r.due_days)::timestamp + time '17:00') at time zone 'Africa/Harare',
      r.created_by, r.assignee_id,
      case when r.assignee_id is null then 'open' else 'taken' end,
      case when r.assignee_id is null then null else now() end,
      r.id,
      r.asset_id,
      case when r.asset_id is null then 'corrective' else 'preventive' end,
      r.isolation_required
    )
    returning * into v_job;

    if r.assignee_id is not null then
      perform public.fn_notify(r.assignee_id, r.site_id, 'assigned',
        v_job.code || ' assigned to you', v_job.title, 'job:' || v_job.id);
    end if;

    update public.job_recurrences set next_run = case r.every
        when 'daily' then v_today + 1
        when 'weekly' then v_today + 7
        else (v_today + interval '1 month')::date
      end
    where id = r.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke execute on function
  public._asset_at(uuid, uuid),
  public.fn_save_asset(uuid, uuid, uuid, text, text, text, text, text, text, boolean),
  public.fn_create_job(uuid, uuid, uuid, text, text, text, timestamptz, double precision, double precision, uuid, text, boolean),
  public.fn_edit_job(uuid, text, text, uuid, text, timestamptz, uuid, text, boolean),
  public.fn_save_recurrence(uuid, uuid, uuid, text, text, text, text, date, integer, uuid, boolean, uuid, boolean)
from public, anon, authenticated;

grant execute on function
  public.fn_save_asset(uuid, uuid, uuid, text, text, text, text, text, text, boolean),
  public.fn_create_job(uuid, uuid, uuid, text, text, text, timestamptz, double precision, double precision, uuid, text, boolean),
  public.fn_edit_job(uuid, text, text, uuid, text, timestamptz, uuid, text, boolean),
  public.fn_save_recurrence(uuid, uuid, uuid, text, text, text, text, date, integer, uuid, boolean, uuid, boolean)
to authenticated;

-- ---------------------------------------------------------------------------
-- RLS: anyone who sees jobs at the site sees its assets; writes via functions
-- ---------------------------------------------------------------------------
alter table public.assets enable row level security;
create policy assets_select on public.assets for select to authenticated
  using (public._can('jobs.view', site_id));
revoke all on public.assets from anon;
revoke insert, update, delete on public.assets from authenticated;

insert into public.schema_migrations (filename) values ('0005_assets.sql')
on conflict do nothing;
