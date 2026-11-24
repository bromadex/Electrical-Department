-- Behaviour checks for 0058_recurring_rotation_closures. Runs in a transaction and rolls back.
begin;

create function pg_temp.act_as(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.as_owner() returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
end $$;

create function pg_temp.check(p_ok boolean, p_label text) returns void language plpgsql as $$
begin
  if p_ok is not true then raise exception 'FAILED: %', p_label; end if;
  raise notice 'ok - %', p_label;
end $$;

create function pg_temp.fails(p_sql text, p_code text, p_label text) returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'FAILED: % (no error)', p_label;
exception when others then
  if sqlerrm like 'FAILED:%' then raise; end if;
  if p_code <> '' and sqlerrm not like p_code || ':%' then
    raise exception 'FAILED: % (got: %)', p_label, sqlerrm;
  end if;
  raise notice 'ok - %', p_label;
end $$;

-- Today as the server counts it; the tests do not depend on the date, so
-- the real shutdown (and any other closure) is set aside first.
create temp table t (today date);
insert into t values ((now() at time zone 'Africa/Harare')::date);
grant select on t to authenticated;
update public.work_closures set is_archived = true;

insert into public.sites (id, code, name) values
  ('f5800000-0000-0000-0000-0000000000a1', 'RRA', 'Rotation site'),
  ('f5800000-0000-0000-0000-0000000000a2', 'RRB', 'Closed site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('f5800000-0000-0000-0000-000000000001', 'rr-sup@test', '{"full_name":"RR Supervisor"}'),
  ('f5800000-0000-0000-0000-000000000002', 'rr-t1@test', '{"full_name":"RR Tech One"}'),
  ('f5800000-0000-0000-0000-000000000003', 'rr-t2@test', '{"full_name":"RR Tech Two"}'),
  ('f5800000-0000-0000-0000-000000000004', 'rr-t3@test', '{"full_name":"RR Tech Three"}'),
  ('f5800000-0000-0000-0000-000000000005', 'rr-out@test', '{"full_name":"RR Elsewhere"}');
insert into public.user_roles (user_id, role_id, site_id)
select u.id, r.id, u.site
from (values
  ('f5800000-0000-0000-0000-000000000001'::uuid, 'Supervisor', 'f5800000-0000-0000-0000-0000000000a1'::uuid),
  ('f5800000-0000-0000-0000-000000000001'::uuid, 'Supervisor', 'f5800000-0000-0000-0000-0000000000a2'::uuid),
  ('f5800000-0000-0000-0000-000000000002'::uuid, 'Technician', 'f5800000-0000-0000-0000-0000000000a1'::uuid),
  ('f5800000-0000-0000-0000-000000000003'::uuid, 'Technician', 'f5800000-0000-0000-0000-0000000000a1'::uuid),
  ('f5800000-0000-0000-0000-000000000004'::uuid, 'Technician', 'f5800000-0000-0000-0000-0000000000a1'::uuid),
  ('f5800000-0000-0000-0000-000000000005'::uuid, 'Technician', 'f5800000-0000-0000-0000-0000000000a2'::uuid)
) as u (id, role, site)
join public.roles r on r.name = u.role;

-- Weekdays and the other frequencies -------------------------------------
select pg_temp.check(public._recurrence_after('weekdays', date '2026-11-27') = date '2026-11-30'
  and public._recurrence_after('weekdays', date '2026-11-28') = date '2026-11-30'
  and public._recurrence_after('weekdays', date '2026-11-30') = date '2026-12-01',
  'weekdays: Friday and Saturday go to Monday, Monday to Tuesday');
select pg_temp.check(public._recurrence_after('daily', date '2026-11-27') = date '2026-11-28'
  and public._recurrence_after('quarterly', date '2026-11-27') = date '2027-02-27'
  and public._recurrence_after('yearly', date '2026-11-27') = date '2027-11-27',
  'every day, every three months and yearly');

-- Saving a plan with people taking turns -----------------------------------
select pg_temp.act_as('f5800000-0000-0000-0000-000000000001');
select public.fn_save_recurrence('f5800000-0000-0000-0000-0000000000c1', 'f5800000-0000-0000-0000-0000000000a1',
  null, 'Daily substation walk', null, 'normal', 'daily', (select today from t), 0, null, false, null, false,
  array['f5800000-0000-0000-0000-000000000002', 'f5800000-0000-0000-0000-000000000003',
        'f5800000-0000-0000-0000-000000000002', 'f5800000-0000-0000-0000-000000000004']::uuid[]);
select pg_temp.check((select rotation = array['f5800000-0000-0000-0000-000000000002',
    'f5800000-0000-0000-0000-000000000003', 'f5800000-0000-0000-0000-000000000004']::uuid[]
  from public.job_recurrences where id = 'f5800000-0000-0000-0000-0000000000c1'),
  'each person takes a turn once, in the order chosen');
select pg_temp.fails($$select public.fn_save_recurrence(gen_random_uuid(), 'f5800000-0000-0000-0000-0000000000a1',
  null, 'Bad rotation', null, 'normal', 'daily', current_date, 0, null, false, null, false,
  array['f5800000-0000-0000-0000-000000000005']::uuid[])$$,
  'INVALID', 'someone who cannot work job cards at the site cannot take turns');
select public.fn_save_recurrence('f5800000-0000-0000-0000-0000000000c2', 'f5800000-0000-0000-0000-0000000000a1',
  null, 'Weekly board check', null, 'normal', 'weekly', (select today from t), 1,
  'f5800000-0000-0000-0000-000000000004', false);
select pg_temp.act_as('f5800000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_save_closure(null, 'f5800000-0000-0000-0000-0000000000a1',
  current_date, current_date, 'Holiday')$$, 'NOT_ALLOWED', 'a technician cannot close the site');
select pg_temp.as_owner();

-- Tech Two is on leave today.
insert into public.roster_entries (site_id, user_id, day, shift)
values ('f5800000-0000-0000-0000-0000000000a1', 'f5800000-0000-0000-0000-000000000003', (select today from t), 'leave');

-- Running the plans ----------------------------------------------------------
select public.fn_run_recurrences();
select pg_temp.check((select j.responsible_id = 'f5800000-0000-0000-0000-000000000002' and j.status = 'assigned'
  from public.job_cards j where j.site_id = 'f5800000-0000-0000-0000-0000000000a1' and j.title = 'Daily substation walk'),
  'the first job goes to the first person, really assigned');
select pg_temp.check((select j.responsible_id = 'f5800000-0000-0000-0000-000000000004'
  from public.job_cards j where j.site_id = 'f5800000-0000-0000-0000-0000000000a1' and j.title = 'Weekly board check'),
  'a plan with one person assigns that person');
select pg_temp.check((select next_run = (select today from t) + 1 and rotation_next = 1
  from public.job_recurrences where id = 'f5800000-0000-0000-0000-0000000000c1'),
  'an everyday plan runs again tomorrow, with the next person in turn');

-- Run it again for today: Tech Two is on leave, so Tech Three goes.
update public.job_recurrences set next_run = (select today from t) where id = 'f5800000-0000-0000-0000-0000000000c1';
select public.fn_run_recurrences();
select pg_temp.check((select count(*) = 2 and bool_or(responsible_id = 'f5800000-0000-0000-0000-000000000004')
    and not bool_or(responsible_id = 'f5800000-0000-0000-0000-000000000003')
  from public.job_cards where site_id = 'f5800000-0000-0000-0000-0000000000a1' and title = 'Daily substation walk'),
  'someone off or on leave in the roster is skipped');
select pg_temp.check((select rotation_next = 0 from public.job_recurrences where id = 'f5800000-0000-0000-0000-0000000000c1'),
  'and the turn comes back round to the first person');

-- A closed site -----------------------------------------------------------------
select pg_temp.act_as('f5800000-0000-0000-0000-000000000001');
select public.fn_save_closure('f5800000-0000-0000-0000-0000000000d1', 'f5800000-0000-0000-0000-0000000000a2',
  (select today from t) - 1, (select today from t) + 5, 'Plant shutdown');
select pg_temp.fails($$select public.fn_save_closure(null, null, current_date, current_date, 'Everywhere')$$,
  'NOT_ALLOWED', 'closing every site needs a role at every site');
select pg_temp.fails($$select public.fn_save_closure(null, 'f5800000-0000-0000-0000-0000000000a2',
  current_date, current_date - 1, 'Backwards')$$, 'INVALID', 'the last day cannot come before the first');
select public.fn_save_recurrence('f5800000-0000-0000-0000-0000000000c3', 'f5800000-0000-0000-0000-0000000000a2',
  null, 'Daily pump check', null, 'normal', 'daily', (select today from t), 0, null, false);
select public.fn_save_recurrence('f5800000-0000-0000-0000-0000000000c4', 'f5800000-0000-0000-0000-0000000000a2',
  null, 'Monthly earth test', null, 'normal', 'monthly', (select today from t), 3, null, false);
select pg_temp.as_owner();
select public.fn_run_recurrences();
select pg_temp.check((select count(*) = 0 from public.job_cards where site_id = 'f5800000-0000-0000-0000-0000000000a2'),
  'nothing is raised while the site is closed');
select pg_temp.check((select next_run = (select today from t) + 6 from public.job_recurrences
  where id = 'f5800000-0000-0000-0000-0000000000c4'),
  'a monthly job moves to the day work reopens');
select pg_temp.check((select next_run = (select today from t) + 6 from public.job_recurrences
  where id = 'f5800000-0000-0000-0000-0000000000c3'),
  'an everyday job is skipped until work reopens');
select pg_temp.check(not public._closed_on('f5800000-0000-0000-0000-0000000000a1', (select today from t))
  and public._closed_on('f5800000-0000-0000-0000-0000000000a2', (select today from t)),
  'a closure at one site leaves the others open');

-- Weekdays plans on a weekend -----------------------------------------------------
insert into public.job_recurrences (id, site_id, title, priority, every, next_run, due_days, created_by)
values ('f5800000-0000-0000-0000-0000000000c5', 'f5800000-0000-0000-0000-0000000000a1', 'Weekday meter reading',
  'normal', 'weekdays', (select today from t), 0, 'f5800000-0000-0000-0000-000000000001');
select public.fn_run_recurrences();
select pg_temp.check((select case when extract(isodow from (select today from t)) >= 6
    then count(*) = 0 else count(*) = 1 end
  from public.job_cards where title = 'Weekday meter reading'),
  'a weekdays plan raises Monday to Friday only');
select pg_temp.check((select extract(isodow from next_run) between 1 and 5 and next_run > (select today from t)
  from public.job_recurrences where id = 'f5800000-0000-0000-0000-0000000000c5'),
  'and its next run is a weekday');

-- Everyone can see closures; only the function writes them.
select pg_temp.act_as('f5800000-0000-0000-0000-000000000005');
select pg_temp.check((select count(*) >= 1 from public.work_closures where reason = 'Plant shutdown'),
  'everyone sees the closed days');
select pg_temp.fails($$insert into public.work_closures (starts_on, ends_on, reason) values (current_date, current_date, 'x y')$$,
  '', 'closures are only written through the function');
select pg_temp.as_owner();

select pg_temp.check((select count(*) = 1 from public.work_closures
  where site_id is null and starts_on = date '2026-12-19' and ends_on = date '2027-01-03'),
  'the Christmas shutdown is in: 19 December to 3 January, every site');

rollback;
