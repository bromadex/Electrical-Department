-- DRAFT for issue #14, not a migration yet. Database part only, not
-- tested. To ship: renumber into supabase/migrations/, write its test in
-- supabase/tests/, then build the screens.

-- 0032_projects_roster_calendar: projects (P-), the weekly roster with
-- standby, and one calendar across features (API.md section 18, issue #14).
-- Projects and rosters are managed with projects.manage; everyone who sees
-- job cards (jc.view) sees them.

-- ---------------------------------------------------------------------------
-- Projects
-- ---------------------------------------------------------------------------
create table public.projects (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id),
  code text not null,
  name text not null check (length(trim(name)) between 3 and 120),
  description text check (length(description) <= 4000),
  target_date date,
  owner_id uuid references public.profiles (id),
  status text not null default 'active' check (status in ('active', 'on_hold', 'done', 'cancelled')),
  created_by uuid references public.profiles (id) default auth.uid(),
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (site_id, code)
);
create trigger projects_touch before update on public.projects
  for each row execute function public.fn_touch_updated_at();

create table public.project_members (
  project_id uuid not null references public.projects (id),
  user_id uuid not null references public.profiles (id),
  added_at timestamptz not null default now(),
  primary key (project_id, user_id)
);

alter table public.job_cards add column project_id uuid references public.projects (id);
create index job_cards_project on public.job_cards (project_id) where project_id is not null;

-- Projects with their progress: job cards closed out of those not cancelled.
create view public.project_overview with (security_invoker = true) as
select p.*,
  (select count(*) from public.job_cards j
    where j.project_id = p.id and not j.is_archived and j.status <> 'cancelled')::integer as jobs_total,
  (select count(*) from public.job_cards j
    where j.project_id = p.id and not j.is_archived and j.status = 'closed')::integer as jobs_done,
  (select coalesce(array_agg(m.user_id), '{}') from public.project_members m
    where m.project_id = p.id) as member_ids
from public.projects p
where not p.is_archived;

-- Creates or edits a project; p_members (when given) replaces the team.
create function public.fn_save_project(
  p_client_ref uuid,
  p_site uuid,
  p_name text,
  p_description text,
  p_target_date date,
  p_owner uuid,
  p_status text,
  p_members uuid[]
)
returns public.projects
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.projects;
  u uuid;
begin
  if not public._can('projects.manage', p_site) then
    raise exception 'NOT_ALLOWED: Only a supervisor can manage projects';
  end if;
  if length(trim(coalesce(p_name, ''))) not between 3 and 120 then
    raise exception 'INVALID: The project name needs 3 to 120 characters';
  end if;
  if coalesce(p_status, 'active') not in ('active', 'on_hold', 'done', 'cancelled') then
    raise exception 'INVALID: Unknown status %', p_status;
  end if;

  select * into v from public.projects where id = p_client_ref for update;
  if found then
    if v.site_id <> p_site then
      raise exception 'INVALID: Project belongs to another site';
    end if;
    update public.projects
    set name = trim(p_name), description = nullif(trim(coalesce(p_description, '')), ''),
        target_date = p_target_date, owner_id = p_owner, status = coalesce(p_status, 'active')
    where id = v.id
    returning * into v;
  else
    insert into public.projects (id, site_id, code, name, description, target_date, owner_id, status)
    values (p_client_ref, p_site, public.next_code(p_site, 'P'), trim(p_name),
      nullif(trim(coalesce(p_description, '')), ''), p_target_date, p_owner, coalesce(p_status, 'active'))
    returning * into v;
  end if;

  if p_members is not null then
    delete from public.project_members
    where project_id = v.id and user_id <> all (p_members);
    foreach u in array p_members loop
      insert into public.project_members (project_id, user_id) values (v.id, u)
      on conflict do nothing;
      if found and u is distinct from auth.uid() then
        perform public.fn_notify(u, v.site_id, 'assigned', 'You are on project ' || v.code,
          v.name, 'project:' || v.id);
      end if;
    end loop;
  end if;
  return v;
end;
$$;

-- Adds a job card to a project, or takes it off (p_project null).
create function public.fn_set_job_project(p_job_card uuid, p_project uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  j public.job_cards;
  p public.projects;
begin
  select * into j from public.job_cards where id = p_job_card and not is_archived;
  if not found or not public._can('jc.view', j.site_id) then
    raise exception 'NOT_FOUND: Job card not found';
  end if;
  if not (public._can('projects.manage', j.site_id) or public._can('jc.assign', j.site_id)) then
    raise exception 'NOT_ALLOWED: Only a supervisor can move job cards between projects';
  end if;
  if p_project is not null then
    select * into p from public.projects where id = p_project and not is_archived;
    if not found or p.site_id <> j.site_id then
      raise exception 'INVALID: That project is not at this job card''s site';
    end if;
  end if;
  update public.job_cards set project_id = p_project where id = j.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Roster and standby
-- ---------------------------------------------------------------------------
create table public.roster_entries (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id),
  user_id uuid not null references public.profiles (id),
  day date not null,
  shift text not null check (shift in ('day', 'night', 'off', 'leave')),
  standby boolean not null default false,
  note text check (length(note) <= 200),
  standby_reminded_at timestamptz,
  is_archived boolean not null default false,
  updated_by uuid references public.profiles (id) default auth.uid(),
  updated_at timestamptz not null default now(),
  unique (site_id, user_id, day)
);
create index roster_entries_day on public.roster_entries (site_id, day);
create trigger roster_entries_touch before update on public.roster_entries
  for each row execute function public.fn_touch_updated_at();

create table public.roster_weeks (
  site_id uuid not null references public.sites (id),
  week_start date not null check (extract(isodow from week_start) = 1),
  published_at timestamptz,
  published_by uuid references public.profiles (id),
  primary key (site_id, week_start)
);

-- Saves a week's roster (Monday p_week_start). p_entries is
-- [{user_id, day, shift, standby, note}]; shift null clears that day.
-- p_publish tells everyone on the week's roster.
create function public.fn_set_roster(
  p_site uuid,
  p_week_start date,
  p_entries jsonb,
  p_publish boolean
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  e record;
  v_count integer := 0;
  u uuid;
begin
  if not public._can('projects.manage', p_site) then
    raise exception 'NOT_ALLOWED: Only a supervisor can set the roster';
  end if;
  if p_week_start is null or extract(isodow from p_week_start) <> 1 then
    raise exception 'INVALID: A roster week starts on a Monday';
  end if;
  if jsonb_typeof(coalesce(p_entries, '[]'::jsonb)) <> 'array' then
    raise exception 'INVALID: Entries must be a list';
  end if;

  for e in
    select (x ->> 'user_id')::uuid as user_id, (x ->> 'day')::date as day,
      nullif(x ->> 'shift', '') as shift, coalesce((x ->> 'standby')::boolean, false) as standby,
      nullif(trim(coalesce(x ->> 'note', '')), '') as note
    from jsonb_array_elements(coalesce(p_entries, '[]'::jsonb)) x
  loop
    if e.day not between p_week_start and p_week_start + 6 then
      raise exception 'INVALID: % is not in the week of %', e.day, p_week_start;
    end if;
    if not exists (select 1 from public.profiles where id = e.user_id and active and not is_archived) then
      raise exception 'NOT_FOUND: Person not found';
    end if;
    if e.shift is null then
      update public.roster_entries set is_archived = true
      where site_id = p_site and user_id = e.user_id and day = e.day and not is_archived;
    else
      if e.shift not in ('day', 'night', 'off', 'leave') then
        raise exception 'INVALID: Unknown shift %', e.shift;
      end if;
      insert into public.roster_entries (site_id, user_id, day, shift, standby, note)
      values (p_site, e.user_id, e.day, e.shift, e.standby and e.shift not in ('off', 'leave'), e.note)
      on conflict (site_id, user_id, day) do update
      set shift = excluded.shift, standby = excluded.standby, note = excluded.note,
          is_archived = false, updated_by = auth.uid(),
          standby_reminded_at = case when excluded.standby then public.roster_entries.standby_reminded_at end;
    end if;
    v_count := v_count + 1;
  end loop;

  if coalesce(p_publish, false) then
    insert into public.roster_weeks (site_id, week_start, published_at, published_by)
    values (p_site, p_week_start, now(), auth.uid())
    on conflict (site_id, week_start) do update
    set published_at = now(), published_by = auth.uid();
    for u in
      select distinct user_id from public.roster_entries
      where site_id = p_site and day between p_week_start and p_week_start + 6 and not is_archived
    loop
      perform public.fn_notify(u, p_site, 'general',
        'Roster for the week of ' || to_char(p_week_start, 'FMDD Mon'),
        'Your shifts and standby are out.', 'roster:' || p_week_start::text);
    end loop;
  end if;
  return v_count;
end;
$$;

-- Tells tomorrow's standby people (published weeks only), once.
create function public.fn_send_standby_reminders()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_count integer := 0;
  v_day date := public._harare_today() + 1;
begin
  for r in
    select e.id, e.user_id, e.site_id, s.name as site_name
    from public.roster_entries e
    join public.sites s on s.id = e.site_id
    join public.roster_weeks w
      on w.site_id = e.site_id and w.week_start = e.day - (extract(isodow from e.day)::integer - 1)
      and w.published_at is not null
    where e.day = v_day and e.standby and not e.is_archived and e.standby_reminded_at is null
  loop
    perform public.fn_notify(r.user_id, r.site_id, 'reminder', 'You are on standby tomorrow',
      r.site_name || ': keep your phone on.', 'roster:' || v_day::text);
    update public.roster_entries set standby_reminded_at = now() where id = r.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

select cron.schedule('standby-reminders', '0 14 * * *', 'select public.fn_send_standby_reminders()');

-- ---------------------------------------------------------------------------
-- Calendar: due dates across features, as the caller may see them (RLS)
-- ---------------------------------------------------------------------------
create function public.fn_calendar(p_site uuid, p_from date, p_to date)
returns table (kind text, ref_id uuid, title text, day date, at timestamptz, link text)
language sql
stable
security invoker
set search_path = ''
as $$
  select 'job', j.id, j.number || ' · ' || j.title,
    (j.target_completion_at at time zone 'Africa/Harare')::date, j.target_completion_at, 'jobcard:' || j.id
  from public.job_cards j
  where j.site_id = p_site and not j.is_archived and j.status not in ('closed', 'cancelled')
    and (j.target_completion_at at time zone 'Africa/Harare')::date between p_from and p_to
  union all
  select 'meeting', m.id, m.title,
    (m.starts_at at time zone 'Africa/Harare')::date, m.starts_at, 'meeting:' || m.id
  from public.meetings m
  where m.site_id = p_site and m.status = 'scheduled'
    and (m.starts_at at time zone 'Africa/Harare')::date between p_from and p_to
  union all
  select 'tool_return', t.id, coalesce(t.code || ' ', '') || t.name || ' back', t.due_back, null, 'tool:' || t.id
  from public.tools t
  where t.site_id = p_site and not t.is_archived and t.due_back between p_from and p_to
    and (t.holder_id is not null or t.holder_name is not null)
  union all
  select 'calibration', t.id, coalesce(t.code || ' ', '') || t.name || ' calibration', t.calibration_due, null,
    'tool:' || t.id
  from public.tools t
  where t.site_id = p_site and not t.is_archived and t.calibration_due between p_from and p_to
  union all
  select 'planned', r.id, r.title, r.next_run, null, null
  from public.job_recurrences r
  where r.site_id = p_site and not r.is_archived and r.next_run between p_from and p_to
  union all
  select 'project', p.id, p.code || ' · ' || p.name || ' due', p.target_date, null, 'project:' || p.id
  from public.projects p
  where p.site_id = p_site and not p.is_archived and p.status in ('active', 'on_hold')
    and p.target_date between p_from and p_to
  union all
  select case when e.standby then 'standby' else 'shift' end, e.id,
    initcap(e.shift) || case when e.standby then ' shift, on standby' else ' shift' end, e.day, null,
    'roster:' || e.day::text
  from public.roster_entries e
  where e.site_id = p_site and e.user_id = auth.uid() and not e.is_archived
    and e.shift not in ('off') and e.day between p_from and p_to
  union all
  select 'reminder', r.id, r.note, (r.remind_at at time zone 'Africa/Harare')::date, r.remind_at, r.link
  from public.reminders r
  where r.user_id = auth.uid() and not r.is_archived and (r.site_id is null or r.site_id = p_site)
    and (r.remind_at at time zone 'Africa/Harare')::date between p_from and p_to
  order by 4, 5 nulls last, 3;
$$;

-- ---------------------------------------------------------------------------
-- Access
-- ---------------------------------------------------------------------------
alter table public.projects enable row level security;
alter table public.project_members enable row level security;
alter table public.roster_entries enable row level security;
alter table public.roster_weeks enable row level security;

create policy projects_select on public.projects for select to authenticated
  using (public._can('jc.view', site_id));
create policy project_members_select on public.project_members for select to authenticated
  using (exists (select 1 from public.projects p
    where p.id = project_members.project_id and public._can('jc.view', p.site_id)));
create policy roster_entries_select on public.roster_entries for select to authenticated
  using (user_id = auth.uid() or public._can('jc.view', site_id));
create policy roster_weeks_select on public.roster_weeks for select to authenticated
  using (public._can('jc.view', site_id));

revoke all on public.projects, public.project_members, public.roster_entries, public.roster_weeks,
  public.project_overview from anon;
revoke insert, update, delete on public.projects, public.project_members, public.roster_entries,
  public.roster_weeks from authenticated;
grant select on public.project_overview to authenticated;

revoke execute on function
  public.fn_save_project(uuid, uuid, text, text, date, uuid, text, uuid[]),
  public.fn_set_job_project(uuid, uuid),
  public.fn_set_roster(uuid, date, jsonb, boolean),
  public.fn_calendar(uuid, date, date),
  public.fn_send_standby_reminders()
from public, anon;
grant execute on function
  public.fn_save_project(uuid, uuid, text, text, date, uuid, text, uuid[]),
  public.fn_set_job_project(uuid, uuid),
  public.fn_set_roster(uuid, date, jsonb, boolean),
  public.fn_calendar(uuid, date, date)
to authenticated;

insert into public.schema_migrations (filename) values ('0032_projects_roster_calendar.sql')
on conflict do nothing;
