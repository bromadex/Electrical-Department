-- 0059_holidays_and_duties: Zimbabwe's public holidays, and daily duties
-- (API.md section 10c).
--
-- * work_closures.kind: 'shutdown' or 'holiday', and message: a greeting
--   for the team shown on Home before and during it. The 2027 public
--   holidays are added for every site with their messages (the app adds
--   other years from Shutdowns and holidays). A site that works through
--   one removes it.
-- * Daily duties: everyday operations without job cards. A duty rota is a
--   site's list of tasks and the team who share them. Each day every task
--   goes to someone: a fixed person, or the team in turn, so if Geri reads
--   the meters today Nyasha does the generator check, and tomorrow they
--   swap. People off or on leave in the roster are left out that day, and
--   nothing is due on closed days (or weekends, for a weekdays rota).
--   People tick their duties done. No notifications: duties show on Home.

-- Holidays -------------------------------------------------------------------
alter table public.work_closures
  add column kind text not null default 'shutdown' check (kind in ('shutdown', 'holiday')),
  -- A greeting for the team, shown on Home before and during the closure.
  add column message text check (length(message) <= 400);

update public.work_closures set message =
  'Thank you, team, for a safe and hard-working year. Rest well over Christmas '
  'and the New Year, travel safely, and enjoy the time with your families. '
  'See you on Monday 4 January.'
where site_id is null and starts_on = date '2026-12-19' and ends_on = date '2027-01-03';

-- Zimbabwe, 2027. A holiday on a Sunday moves to the Monday; Heroes' Day is
-- the second Monday of August and Defence Forces Day the day after. New
-- Year's Day falls in the Christmas shutdown.
insert into public.work_closures (site_id, starts_on, ends_on, reason, kind, message) values
  (null, date '2027-02-22', date '2027-02-22', 'National Youth Day (from Sunday 21 February)', 'holiday',
   'Happy National Youth Day! Here''s to the young electricians and apprentices growing with us: '
   'keep learning, keep asking, keep it safe.'),
  (null, date '2027-03-26', date '2027-03-29', 'Easter: Good Friday to Easter Monday', 'holiday',
   'Happy Easter to you and your families. Enjoy the long weekend, rest well and travel safely. '
   'Back on Tuesday 30 March.'),
  (null, date '2027-04-19', date '2027-04-19', 'Independence Day (from Sunday 18 April)', 'holiday',
   'Happy Independence Day, Zimbabwe! Proud of the team that keeps the power on, every day.'),
  (null, date '2027-05-01', date '2027-05-01', 'Workers'' Day', 'holiday',
   'Happy Workers'' Day! Thank you for the skill, care and long hours you put in. '
   'Every job done safely is something to be proud of.'),
  (null, date '2027-05-25', date '2027-05-25', 'Africa Day', 'holiday',
   'Happy Africa Day! Celebrating the people and the work that power our continent.'),
  (null, date '2027-08-09', date '2027-08-10', 'Heroes'' Day and Defence Forces Day', 'holiday',
   'On Heroes'' Day and Defence Forces Day we remember those who served. Enjoy the two days '
   'with your families; back on Wednesday 11 August.'),
  (null, date '2027-12-22', date '2027-12-22', 'Unity Day', 'holiday',
   'Happy Unity Day! One team, every site: thank you for pulling together all year.'),
  (null, date '2027-12-25', date '2027-12-25', 'Christmas Day', 'holiday',
   'Merry Christmas from the Electrical Department! Thank you for a safe year. '
   'Enjoy the day with your loved ones.'),
  (null, date '2027-12-27', date '2027-12-27', 'Boxing Day (from Sunday 26 December)', 'holiday',
   'Happy Boxing Day! Rest, recharge and stay safe on the roads.');

drop function public.fn_save_closure(uuid, uuid, date, date, text, boolean);
create function public.fn_save_closure(
  p_id uuid,
  p_site uuid,
  p_starts date,
  p_ends date,
  p_reason text,
  p_archived boolean default false,
  p_kind text default null,
  p_message text default null
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
  if length(coalesce(p_message, '')) > 400 then
    raise exception 'INVALID: Keep the message to 400 characters';
  end if;
  if coalesce(p_kind, 'shutdown') not in ('shutdown', 'holiday') then
    raise exception 'INVALID: A closure is a shutdown or a holiday';
  end if;
  insert into public.work_closures as c (id, site_id, starts_on, ends_on, reason, is_archived, kind, message)
  values (coalesce(p_id, gen_random_uuid()), p_site, p_starts, p_ends, trim(p_reason),
          coalesce(p_archived, false), coalesce(p_kind, 'shutdown'),
          nullif(trim(coalesce(p_message, '')), ''))
  on conflict (id) do update set
    site_id = excluded.site_id, starts_on = excluded.starts_on, ends_on = excluded.ends_on,
    reason = excluded.reason, is_archived = excluded.is_archived,
    kind = coalesce(p_kind, c.kind),
    -- Null keeps the message (an old app saving the dates).
    message = case when p_message is null then c.message else excluded.message end
  returning * into v;
  return v;
end;
$$;

-- Daily duties ------------------------------------------------------------------
create table public.duty_rotas (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id),
  name text not null check (length(name) between 2 and 80),
  every text not null default 'daily' check (every in ('daily', 'weekdays')),
  -- The team, in order; tasks go round them a step a day.
  people uuid[] not null default '{}',
  -- Day the turns count from.
  starts_on date not null default (now() at time zone 'Africa/Harare')::date,
  is_archived boolean not null default false,
  created_by uuid references public.profiles (id) default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index duty_rotas_site_id_fk on public.duty_rotas (site_id);
create index duty_rotas_created_by_fk on public.duty_rotas (created_by);

create table public.duty_tasks (
  id uuid primary key default gen_random_uuid(),
  rota_id uuid not null references public.duty_rotas (id),
  title text not null check (length(title) between 2 and 120),
  position integer not null default 0,
  -- Always this person (when they are in); null: the team in turn.
  person_id uuid references public.profiles (id),
  is_archived boolean not null default false
);
create index duty_tasks_rota_id_fk on public.duty_tasks (rota_id);
create index duty_tasks_person_id_fk on public.duty_tasks (person_id);

create table public.duty_done (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.duty_tasks (id),
  day date not null,
  done_by uuid not null references public.profiles (id) default auth.uid(),
  done_at timestamptz not null default now(),
  note text check (length(note) <= 300),
  unique (task_id, day)
);
create index duty_done_done_by_fk on public.duty_done (done_by);

alter table public.duty_rotas enable row level security;
alter table public.duty_tasks enable row level security;
alter table public.duty_done enable row level security;
create policy duty_rotas_select on public.duty_rotas
  for select to authenticated using (public._can('jobs.view', site_id));
create policy duty_tasks_select on public.duty_tasks
  for select to authenticated using (exists (
    select 1 from public.duty_rotas r where r.id = rota_id and public._can('jobs.view', r.site_id)));
create policy duty_done_select on public.duty_done
  for select to authenticated using (exists (
    select 1 from public.duty_tasks t join public.duty_rotas r on r.id = t.rota_id
    where t.id = task_id and public._can('jobs.view', r.site_id)));
revoke all on public.duty_rotas, public.duty_tasks, public.duty_done from anon;
revoke insert, update, delete on public.duty_rotas, public.duty_tasks, public.duty_done from authenticated;
grant select on public.duty_rotas, public.duty_tasks, public.duty_done to authenticated;

-- Adds or changes a rota with its tasks in order. A task keeps its id (and
-- what was ticked) while its title stays; p_people_for gives each task's
-- fixed person (null: the team in turn).
create function public.fn_save_duty_rota(
  p_id uuid,
  p_site uuid,
  p_name text,
  p_every text,
  p_people uuid[],
  p_tasks text[],
  p_people_for uuid[] default null,
  p_archived boolean default false
)
returns public.duty_rotas
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.duty_rotas;
  v_people uuid[];
  u uuid;
  i integer;
  v_title text;
  v_task uuid;
  v_keep uuid[] := '{}';
begin
  if not public._can('jobs.assign', p_site) then
    raise exception 'NOT_ALLOWED: Only a supervisor can set up daily duties';
  end if;
  if length(trim(coalesce(p_name, ''))) not between 2 and 80 then
    raise exception 'INVALID: Name the duties, e.g. Morning duties';
  end if;
  if coalesce(p_every, 'daily') not in ('daily', 'weekdays') then
    raise exception 'INVALID: Duties are every day or on weekdays';
  end if;
  v_people := array(
    select x.u from unnest(coalesce(p_people, '{}'::uuid[])) with ordinality as x (u, n)
    where x.u is not null group by x.u order by min(x.n)
  );
  if cardinality(v_people) > 40 then
    raise exception 'INVALID: Up to 40 people can share duties';
  end if;
  foreach u in array v_people || coalesce(array(select p from unnest(p_people_for) p where p is not null), '{}') loop
    if not public._user_can(u, 'jobs.view', p_site) or not exists (
      select 1 from public.user_roles ur where ur.user_id = u and not ur.is_archived
        and (ur.site_id is null or ur.site_id = p_site)) then
      raise exception 'INVALID: Someone on the duties does not work at this site';
    end if;
  end loop;
  if not coalesce(p_archived, false)
     and coalesce(cardinality(array(select t from unnest(p_tasks) t where length(trim(coalesce(t, ''))) >= 2)), 0) = 0 then
    raise exception 'INVALID: Add at least one duty';
  end if;
  if cardinality(p_tasks) > 40 then
    raise exception 'INVALID: Up to 40 duties in one list';
  end if;

  insert into public.duty_rotas as r (id, site_id, name, every, people, is_archived)
  values (coalesce(p_id, gen_random_uuid()), p_site, trim(p_name), coalesce(p_every, 'daily'),
          v_people, coalesce(p_archived, false))
  on conflict (id) do update set
    name = excluded.name, every = excluded.every, people = excluded.people,
    is_archived = excluded.is_archived, updated_at = now()
  where r.site_id = excluded.site_id
  returning * into v;
  if v.id is null then
    raise exception 'INVALID: These duties belong to another site';
  end if;

  if not v.is_archived then
    for i in 1..coalesce(cardinality(p_tasks), 0) loop
      v_title := trim(coalesce(p_tasks[i], ''));
      continue when length(v_title) < 2;
      select id into v_task from public.duty_tasks
      where rota_id = v.id and title = v_title and not is_archived and not (id = any (v_keep))
      limit 1;
      if v_task is null then
        insert into public.duty_tasks (rota_id, title, position, person_id)
        values (v.id, v_title, i, p_people_for[i])
        returning id into v_task;
      else
        update public.duty_tasks set position = i, person_id = p_people_for[i] where id = v_task;
      end if;
      v_keep := v_keep || v_task;
    end loop;
    update public.duty_tasks set is_archived = true
    where rota_id = v.id and not is_archived and not (id = any (v_keep));
  end if;
  return v;
end;
$$;

-- Whether a rota has duties on the day (open, and a weekday for weekdays).
create function public._duty_day(r public.duty_rotas, p_day date)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_day >= r.starts_on
    and not public._closed_on(r.site_id, p_day)
    and (r.every = 'daily' or extract(isodow from p_day) < 6);
$$;

-- Each rota's duties on the day: who does each and whether it is done.
-- p_site null: every site.
create function public.fn_duties(p_site uuid, p_day date)
returns table (
  rota_id uuid, rota_name text, site_id uuid, task_id uuid, title text, "position" integer,
  person_id uuid, done_by uuid, done_at timestamptz, note text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  r public.duty_rotas;
  v_in uuid[];
  v_step integer;
  t public.duty_tasks;
  k integer;
  v_person uuid;
begin
  for r in
    select * from public.duty_rotas d
    where not d.is_archived and (p_site is null or d.site_id = p_site)
      and public._can('jobs.view', d.site_id)
    order by d.name
  loop
    continue when not public._duty_day(r, p_day);
    -- The team who are in today, in order.
    v_in := array(
      select x.u from unnest(r.people) with ordinality as x (u, n)
      where not exists (
        select 1 from public.roster_entries e
        where e.site_id = r.site_id and e.user_id = x.u and e.day = p_day
          and not e.is_archived and e.shift in ('off', 'leave'))
      order by x.n
    );
    -- Days with duties since the start: the step the turns have moved.
    select count(*)::int into v_step
    from generate_series(r.starts_on, p_day - 1, interval '1 day') g (d)
    where public._duty_day(r, g.d::date);
    k := 0;
    for t in
      select * from public.duty_tasks
      where duty_tasks.rota_id = r.id and not is_archived order by position, title
    loop
      if t.person_id is not null and not exists (
          select 1 from public.roster_entries e
          where e.site_id = r.site_id and e.user_id = t.person_id and e.day = p_day
            and not e.is_archived and e.shift in ('off', 'leave')) then
        -- Their own duty, when they are in.
        v_person := t.person_id;
      elsif cardinality(v_in) > 0 then
        -- The team in turn (also covers a fixed person who is away).
        v_person := v_in[((k + v_step) % cardinality(v_in)) + 1];
        k := k + 1;
      else
        v_person := t.person_id;
      end if;
      rota_id := r.id; rota_name := r.name; site_id := r.site_id;
      task_id := t.id; title := t.title; "position" := t.position; person_id := v_person;
      select dd.done_by, dd.done_at, dd.note into done_by, done_at, note
      from public.duty_done dd where dd.task_id = t.id and dd.day = p_day;
      if not found then
        done_by := null; done_at := null; note := null;
      end if;
      return next;
    end loop;
  end loop;
end;
$$;

-- Ticks a duty done for the day, or takes the tick back. Anyone who works
-- at the site can (someone may cover for a colleague).
create function public.fn_mark_duty(p_task uuid, p_day date, p_done boolean, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_site uuid;
begin
  select r.site_id into v_site
  from public.duty_tasks t join public.duty_rotas r on r.id = t.rota_id
  where t.id = p_task;
  if v_site is null then
    raise exception 'NOT_FOUND: That duty no longer exists';
  end if;
  if not public._works_at(v_site) then
    raise exception 'NOT_ALLOWED: Only people at the site tick its duties';
  end if;
  if p_day > (now() at time zone 'Africa/Harare')::date or p_day < (now() at time zone 'Africa/Harare')::date - 7 then
    raise exception 'INVALID: Duties are ticked on the day, or up to a week after';
  end if;
  if coalesce(p_done, true) then
    insert into public.duty_done (task_id, day, note)
    values (p_task, p_day, nullif(trim(coalesce(p_note, '')), ''))
    on conflict (task_id, day) do update set note = coalesce(excluded.note, duty_done.note);
  else
    delete from public.duty_done where task_id = p_task and day = p_day;
  end if;
end;
$$;

revoke execute on function
  public.fn_save_closure(uuid, uuid, date, date, text, boolean, text, text),
  public.fn_save_duty_rota(uuid, uuid, text, text, uuid[], text[], uuid[], boolean),
  public._duty_day(public.duty_rotas, date),
  public.fn_duties(uuid, date),
  public.fn_mark_duty(uuid, date, boolean, text)
from public, anon;
revoke execute on function public._duty_day(public.duty_rotas, date) from authenticated;
grant execute on function
  public.fn_save_closure(uuid, uuid, date, date, text, boolean, text, text),
  public.fn_save_duty_rota(uuid, uuid, text, text, uuid[], text[], uuid[], boolean),
  public.fn_duties(uuid, date),
  public.fn_mark_duty(uuid, date, boolean, text)
to authenticated;

insert into public.schema_migrations (filename) values ('0059_holidays_and_duties.sql')
on conflict do nothing;
