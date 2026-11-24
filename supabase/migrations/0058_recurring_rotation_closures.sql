-- 0058_recurring_rotation_closures: everyday planned jobs, technicians
-- taking turns, and shutdowns (API.md section 9b).
--
-- * Planned jobs (job_recurrences) can run every day, on weekdays (Monday
--   to Friday), weekly, monthly, every three months or yearly.
-- * A plan can name technicians who take turns (rotation): each job goes
--   to the next one, skipping anyone the site's roster has off or on leave
--   that day. A plan with one person assigns that person. Either way the
--   job card is now really assigned (before, the person was only told).
-- * work_closures: days the department is closed (Christmas shutdown,
--   public holidays), for every site or one. Nothing is raised on those
--   days: everyday plans skip them, the others move to the day work
--   reopens. Checklist alerts and the evening daily reports also pause
--   while every site is closed.

-- Frequencies ------------------------------------------------------------
alter table public.job_recurrences drop constraint job_recurrences_every_check;
alter table public.job_recurrences add constraint job_recurrences_every_check
  check (every in ('daily', 'weekdays', 'weekly', 'monthly', 'quarterly', 'yearly'));

-- Taking turns -------------------------------------------------------------
alter table public.job_recurrences
  add column rotation uuid[] not null default '{}',
  add column rotation_next integer not null default 0;

-- Closed days ----------------------------------------------------------------
create table public.work_closures (
  id uuid primary key default gen_random_uuid(),
  -- Null: every site.
  site_id uuid references public.sites (id),
  starts_on date not null,
  ends_on date not null,
  reason text not null check (length(reason) between 2 and 80),
  is_archived boolean not null default false,
  created_by uuid references public.profiles (id) default auth.uid(),
  created_at timestamptz not null default now(),
  check (ends_on >= starts_on),
  check (ends_on - starts_on <= 366)
);
create index work_closures_site_id_fk on public.work_closures (site_id);
create index work_closures_created_by_fk on public.work_closures (created_by);
create index work_closures_dates on public.work_closures (starts_on, ends_on) where not is_archived;

alter table public.work_closures enable row level security;
create policy work_closures_select on public.work_closures
  for select to authenticated using (public._active());
revoke all on public.work_closures from anon;
revoke insert, update, delete on public.work_closures from authenticated;
grant select on public.work_closures to authenticated;

-- The department's Christmas shutdown: the last working day is Friday
-- 18 December and work starts again on Monday 4 January.
insert into public.work_closures (site_id, starts_on, ends_on, reason)
values (null, date '2026-12-19', date '2027-01-03', 'Christmas and New Year shutdown');

-- Whether work is closed at the site (null: every site closed) that day.
create function public._closed_on(p_site uuid, p_day date)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.work_closures c
    where not c.is_archived
      and p_day between c.starts_on and c.ends_on
      and (c.site_id is null or (p_site is not null and c.site_id = p_site))
  );
$$;

-- The first day on or after p_day that the site is open.
create function public._next_open_day(p_site uuid, p_day date)
returns date
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  d date := p_day;
begin
  -- A closure lasts at most a year; stop well after that.
  for i in 1..400 loop
    exit when not public._closed_on(p_site, d);
    d := d + 1;
  end loop;
  return d;
end;
$$;

-- Adds, changes or removes (p_archived) a closure. Everyone sees them;
-- people who set up planned jobs (jobs.assign) manage them, for all sites
-- only with a role at every site.
create function public.fn_save_closure(
  p_id uuid,
  p_site uuid,
  p_starts date,
  p_ends date,
  p_reason text,
  p_archived boolean default false
)
returns public.work_closures
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.work_closures;
begin
  if not public._can('jobs.assign', p_site) then
    raise exception 'NOT_ALLOWED: Only a supervisor can set closed days%',
      case when p_site is null then ' for every site' else '' end;
  end if;
  if p_starts is null or p_ends is null or p_ends < p_starts then
    raise exception 'INVALID: The last day must be on or after the first';
  end if;
  if p_ends - p_starts > 366 then
    raise exception 'INVALID: A closure can last a year at most';
  end if;
  if length(trim(coalesce(p_reason, ''))) not between 2 and 80 then
    raise exception 'INVALID: Say why work is closed, e.g. Christmas shutdown';
  end if;
  insert into public.work_closures as c (id, site_id, starts_on, ends_on, reason, is_archived)
  values (coalesce(p_id, gen_random_uuid()), p_site, p_starts, p_ends, trim(p_reason),
          coalesce(p_archived, false))
  on conflict (id) do update set
    site_id = excluded.site_id, starts_on = excluded.starts_on, ends_on = excluded.ends_on,
    reason = excluded.reason, is_archived = excluded.is_archived
  returning * into v;
  return v;
end;
$$;

-- Saving a plan: the old arguments plus who takes turns ---------------------
drop function public.fn_save_recurrence(uuid, uuid, uuid, text, text, text, text, date, integer, uuid, boolean, uuid, boolean);
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
  p_isolation_required boolean default false,
  p_rotation uuid[] default null
)
returns public.job_recurrences
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_recurrences;
  v_rotation uuid[];
  u uuid;
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
  -- Each person once, in the order chosen.
  v_rotation := array(
    select x.u from unnest(coalesce(p_rotation, '{}'::uuid[])) with ordinality as x (u, n)
    where x.u is not null
    group by x.u order by min(x.n)
  );
  if cardinality(v_rotation) > 30 then
    raise exception 'INVALID: Up to 30 people can take turns';
  end if;
  foreach u in array v_rotation loop
    if not public._user_can(u, 'jc.execute', p_site) then
      raise exception 'INVALID: Someone taking turns cannot work job cards at this site';
    end if;
  end loop;
  insert into public.job_recurrences as r (
    id, site_id, area_id, title, description, priority, every, next_run, due_days, assignee_id,
    is_archived, asset_id, isolation_required, rotation
  ) values (
    p_client_ref, p_site, p_area, trim(p_title), nullif(trim(coalesce(p_description, '')), ''),
    p_priority, p_every, p_next_run, p_due_days,
    case when cardinality(v_rotation) > 0 then null else p_assignee end,
    coalesce(p_archived, false), p_asset, coalesce(p_isolation_required, false), v_rotation
  )
  on conflict (id) do update set
    area_id = excluded.area_id, title = excluded.title, description = excluded.description,
    priority = excluded.priority, every = excluded.every, next_run = excluded.next_run,
    due_days = excluded.due_days, assignee_id = excluded.assignee_id,
    is_archived = excluded.is_archived, asset_id = excluded.asset_id,
    isolation_required = excluded.isolation_required,
    rotation = excluded.rotation,
    -- A new list starts again at its first person.
    rotation_next = case when r.rotation = excluded.rotation then r.rotation_next else 0 end
  where r.site_id = excluded.site_id
  returning * into v;
  if v.id is null then
    raise exception 'INVALID: Recurring job belongs to another site';
  end if;
  return v;
end;
$$;

-- The day after p_day that a plan runs again.
create function public._recurrence_after(p_every text, p_day date)
returns date
language sql
immutable
set search_path = ''
as $$
  select case p_every
    when 'daily' then p_day + 1
    -- Friday, Saturday and Sunday go to Monday.
    when 'weekdays' then p_day + case extract(isodow from p_day)::int
      when 5 then 3 when 6 then 2 else 1 end
    when 'weekly' then p_day + 7
    when 'monthly' then (p_day + interval '1 month')::date
    when 'quarterly' then (p_day + interval '3 months')::date
    when 'yearly' then (p_day + interval '1 year')::date
  end;
$$;

-- Who does this plan's job today: the next person in turn who is not off
-- or on leave in the site's roster and can still work job cards there,
-- else the plan's one person. Returns the person and where the turn moves.
create function public._recurrence_person(r public.job_recurrences, p_day date)
returns table (person uuid, next_turn integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  n integer := cardinality(r.rotation);
  k integer;
  idx integer;
  cand uuid;
begin
  if n > 0 then
    for k in 0..n - 1 loop
      idx := (r.rotation_next + k) % n;
      cand := r.rotation[idx + 1];
      continue when not public._user_can(cand, 'jc.execute', r.site_id);
      continue when exists (
        select 1 from public.roster_entries e
        where e.site_id = r.site_id and e.user_id = cand and e.day = p_day
          and not e.is_archived and e.shift in ('off', 'leave')
      );
      person := cand;
      next_turn := (idx + 1) % n;
      return next;
      return;
    end loop;
    -- Everyone in turn is away: leave it for the planner to assign.
    person := null;
    next_turn := r.rotation_next;
    return next;
    return;
  end if;
  person := r.assignee_id;
  next_turn := r.rotation_next;
  return next;
end;
$$;

create or replace function public.fn_run_recurrences()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.job_recurrences;
  v_today date := (now() at time zone 'Africa/Harare')::date;
  v_job public.job_cards;
  v_claims text := current_setting('request.jwt.claims', true);
  v_count integer := 0;
  v_person uuid;
  v_turn integer;
  v_raised boolean;
begin
  for r in
    select * from public.job_recurrences
    where not is_archived and next_run <= v_today
    for update skip locked
  loop
    -- Closed today (a shutdown, or a weekend for a weekdays plan).
    if public._closed_on(r.site_id, v_today)
       or (r.every = 'weekdays' and extract(isodow from v_today) >= 6) then
      update public.job_recurrences set next_run = case
          -- Everyday work is simply not done while closed.
          when r.every in ('daily', 'weekdays')
            then public._next_open_day(r.site_id, public._recurrence_after(r.every, v_today - 1))
          -- The rest waits for the day work reopens.
          else public._next_open_day(r.site_id, v_today + 1)
        end
      where id = r.id;
      continue;
    end if;

    v_raised := false;
    select p.person, p.next_turn into v_person, v_turn
    from public._recurrence_person(r, v_today) p;

    -- Registered as the person who set the plan up, so the job card
    -- records who asked for it and their permissions apply.
    perform set_config('request.jwt.claims',
      json_build_object('sub', r.created_by, 'role', 'authenticated')::text, true);
    begin
      v_job := public.fn_register_job_card(
        gen_random_uuid(), null, r.site_id, r.area_id,
        case when r.area_id is null and r.asset_id is null then 'Planned maintenance' end,
        now(), 'Planned maintenance', null, r.asset_id, null, null, null, null,
        r.title,
        coalesce(nullif(trim(coalesce(r.description, '')), ''), 'Planned maintenance: ' || r.title),
        'none',
        case r.priority when 'urgent' then 'P2' when 'low' then 'P4' else 'P3' end,
        ((v_today + r.due_days)::timestamp + time '17:00') at time zone 'Africa/Harare');
      update public.job_cards set
        source = 'preventive',
        maintenance_type = case when r.asset_id is null then 'inspection' else 'preventive' end,
        isolation_required = r.isolation_required
      where id = v_job.id;
      v_raised := true;
    exception when others then
      -- The person who set it up can no longer register job cards here:
      -- tell the site's planners instead of stopping every other plan.
      perform public.fn_notify_permission(r.site_id, 'jc.register', 'general',
        'Planned job "' || r.title || '" could not be raised', sqlerrm, null);
    end;

    if v_raised and v_person is not null then
      begin
        -- The plan is the assessment: routine work the planner set up, so
        -- it goes straight to assignment.
        select * into v_job from public.job_cards where id = v_job.id;
        if v_job.status = 'registered' then
          v_job := public._jc_set_status(v_job, 'awaiting_assignment', 'Planned maintenance');
        end if;
        -- Assigned as the planner; the person is told as for any assignment.
        perform public.fn_assign_job_card(v_job.id, v_person, '{}'::uuid[], null, null, null,
          null, null, null, null, null, 'Planned maintenance');
      exception when others then
        -- The planner cannot assign here: the job waits for assignment, and
        -- the person is still told it is theirs.
        perform public.fn_notify(v_person, r.site_id, 'assigned',
          v_job.number || ' is due (planned maintenance)', v_job.title, 'jobcard:' || v_job.id);
      end;
    end if;
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

    update public.job_recurrences set
      next_run = public._recurrence_after(r.every, v_today),
      rotation_next = case when v_raised then coalesce(v_turn, r.rotation_next) else r.rotation_next end
    where id = r.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke execute on function
  public._closed_on(uuid, date),
  public._next_open_day(uuid, date),
  public._recurrence_after(text, date),
  public._recurrence_person(public.job_recurrences, date),
  public.fn_save_closure(uuid, uuid, date, date, text, boolean),
  public.fn_save_recurrence(uuid, uuid, uuid, text, text, text, text, date, integer, uuid, boolean, uuid, boolean, uuid[])
from public, anon;
-- The scheduler calls _closed_on, so the app cannot (test 0040); the app
-- reads work_closures itself.
revoke execute on function
  public._closed_on(uuid, date),
  public._next_open_day(uuid, date),
  public._recurrence_person(public.job_recurrences, date)
from authenticated;
grant execute on function
  public._recurrence_after(text, date),
  public.fn_save_closure(uuid, uuid, date, date, text, boolean),
  public.fn_save_recurrence(uuid, uuid, uuid, text, text, text, text, date, integer, uuid, boolean, uuid, boolean, uuid[])
to authenticated;

-- Checklist alerts and the evening reports pause while every site is closed.
select cron.schedule('checklists-reminder', '0 13 * * *',
  $$select public.fn_checklist_alerts('reminder') where not public._closed_on(null, (now() at time zone 'Africa/Harare')::date)$$);
select cron.schedule('checklists-missed', '0 17 * * *',
  $$select public.fn_checklist_alerts('missed') where not public._closed_on(null, (now() at time zone 'Africa/Harare')::date)$$);
select cron.schedule('daily-reports', '10 17 * * *',
  $$select public.fn_build_all_reports() where not public._closed_on(null, (now() at time zone 'Africa/Harare')::date)$$);

-- 0057 left out its log line.
insert into public.schema_migrations (filename) values
  ('0057_direct_call_hangup.sql'),
  ('0058_recurring_rotation_closures.sql')
on conflict do nothing;
