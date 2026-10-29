-- Behaviour checks for 0002_jobs. Runs in a transaction and rolls back.
begin;

create function pg_temp.act_as(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.check(p_ok boolean, p_label text) returns void language plpgsql as $$
begin
  if p_ok is not true then raise exception 'FAILED: %', p_label; end if;
  raise notice 'ok - %', p_label;
end $$;

-- Expects p_sql to fail with an error starting with p_code.
create function pg_temp.fails(p_sql text, p_code text, p_label text) returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'FAILED: % (no error)', p_label;
exception when others then
  if p_code <> '' and sqlerrm not like p_code || ':%' then
    raise exception 'FAILED: % (got: %)', p_label, sqlerrm;
  end if;
  raise notice 'ok - %', p_label;
end $$;

-- People: tech + supervisor at KAM, tech at SEL, viewer with no role
insert into auth.users (id, email, raw_user_meta_data) values
  ('20000000-0000-0000-0000-000000000001', 'jt1@test', '{"full_name":"Tech Kam"}'),
  ('20000000-0000-0000-0000-000000000002', 'jt2@test', '{"full_name":"Super Kam"}'),
  ('20000000-0000-0000-0000-000000000003', 'jt3@test', '{"full_name":"Tech Sel"}'),
  ('20000000-0000-0000-0000-000000000004', 'jt4@test', '{"full_name":"Tech Kam Two"}');

insert into public.user_roles (user_id, role_id, site_id)
select u.id, r.id, s.id
from (values
  ('20000000-0000-0000-0000-000000000001'::uuid, 'Technician', 'KAM'),
  ('20000000-0000-0000-0000-000000000002'::uuid, 'Supervisor', 'KAM'),
  ('20000000-0000-0000-0000-000000000003'::uuid, 'Technician', 'SEL'),
  ('20000000-0000-0000-0000-000000000004'::uuid, 'Technician', 'KAM')
) as u (id, role, site)
join public.roles r on r.name = u.role
join public.sites s on s.code = u.site;

create temp table t as select
  (select id from public.sites where code = 'KAM') kam,
  (select id from public.sites where code = 'SEL') sel,
  '30000000-0000-0000-0000-000000000001'::uuid job1,
  '30000000-0000-0000-0000-000000000002'::uuid job2;
grant select on t to authenticated;

-- Technician posts a job
select pg_temp.act_as('20000000-0000-0000-0000-000000000001');
select public.fn_create_job((select job1 from t), (select kam from t), null,
  'Replace isolator', 'MCC room', 'normal', now() - interval '1 hour', -18.1, 26.9);
select pg_temp.check((select code from public.jobs where id = (select job1 from t)) like 'J-%', 'job gets a J- code');
select pg_temp.check((select status from public.jobs where id = (select job1 from t)) = 'open', 'new job is open');
select public.fn_create_job((select job1 from t), (select kam from t), null,
  'Replace isolator', 'MCC room', 'normal', null, null, null);
select pg_temp.check((select count(*) from public.jobs where title = 'Replace isolator') = 1, 'create is idempotent by client ref');
select pg_temp.fails($$select public.fn_create_job(gen_random_uuid(), (select sel from t), null, 'Elsewhere', null, 'normal', null, null, null)$$,
  'NOT_ALLOWED', 'cannot post at another site');
select pg_temp.fails($$select public.fn_create_job(gen_random_uuid(), (select kam from t), null, 'x', null, 'normal', null, null, null)$$,
  'INVALID', 'title must be at least 3 characters');
select pg_temp.fails($$update public.jobs set title = 'hacked'$$, '', 'no direct updates');
select pg_temp.fails($$select public.fn_assign_job((select job1 from t), '20000000-0000-0000-0000-000000000004')$$,
  'NOT_ALLOWED', 'technician cannot assign');

-- Take, conflict, progress
select public.fn_take_job((select job1 from t));
select pg_temp.check((select status from public.jobs where id = (select job1 from t)) = 'taken', 'take sets taken');
select public.fn_take_job((select job1 from t));
select pg_temp.check(true, 'taking your own job again is a no-op');
reset role;
select pg_temp.act_as('20000000-0000-0000-0000-000000000004');
select pg_temp.fails($$select public.fn_take_job((select job1 from t))$$, 'CONFLICT', 'second taker gets a conflict');
select pg_temp.fails($$select public.fn_set_job_status((select job1 from t), 'in_progress', null)$$,
  'NOT_ALLOWED', 'non-assignee cannot change status');
reset role;

select pg_temp.act_as('20000000-0000-0000-0000-000000000001');
select public.fn_set_job_status((select job1 from t), 'in_progress', null);
select pg_temp.fails($$select public.fn_set_job_status((select job1 from t), 'waiting', '  ')$$,
  'INVALID', 'waiting needs a reason');
select public.fn_set_job_status((select job1 from t), 'waiting', 'Breaker on order');
select pg_temp.check((select waiting_reason from public.jobs where id = (select job1 from t)) = 'Breaker on order', 'waiting reason saved');
select public.fn_set_job_status((select job1 from t), 'in_progress', null);
select pg_temp.check((select waiting_reason from public.jobs where id = (select job1 from t)) is null, 'resume clears reason');

-- Comments notify the other party
select public.fn_comment_job(gen_random_uuid(), (select job1 from t), 'Started on it');
select pg_temp.check((select count(*) from public.job_comments where job_id = (select job1 from t)) = 1, 'comment saved');

-- Close needs a note and an after photo
select pg_temp.fails($$select public.fn_close_job((select job1 from t), 'Done')$$, 'INVALID', 'close needs an after photo');
select pg_temp.fails(
  $$select public.fn_add_job_photo(gen_random_uuid(), (select job1 from t), 'after', 'wrong/path.jpg')$$,
  'INVALID', 'photo path must match the job');
select public.fn_add_job_photo(gen_random_uuid(), (select job1 from t), 'after',
  (select kam from t)::text || '/job/' || (select job1 from t)::text || '/after1.jpg');
select pg_temp.fails($$select public.fn_close_job((select job1 from t), ' ')$$, 'INVALID', 'close needs a note');
select public.fn_close_job((select job1 from t), 'Isolator replaced and tested');
select pg_temp.check((select status from public.jobs where id = (select job1 from t)) = 'done', 'job closed');
select public.fn_close_job((select job1 from t), 'again');
select pg_temp.check(true, 'closing twice is a no-op');
select pg_temp.fails($$select public.fn_set_job_status((select job1 from t), 'open', null)$$, 'INVALID', 'closed job cannot reopen');
select pg_temp.check((select count(*) from public.fn_job_history((select job1 from t))) >= 6, 'history has the steps');
reset role;

-- Other sites see it too (0030: every site is visible to everyone)
select pg_temp.act_as('20000000-0000-0000-0000-000000000003');
select pg_temp.check((select count(*) from public.jobs where id = (select job1 from t)) = 1, 'other sites can see the job');
select pg_temp.check((select count(*) from public.fn_job_history((select job1 from t))) > 0, 'and its history');
select pg_temp.fails($$select public.fn_comment_job(gen_random_uuid(), (select job1 from t), 'hi')$$, 'NOT_ALLOWED', 'other site cannot comment');
reset role;

-- Supervisor: urgent alert, assign, cancel
select pg_temp.act_as('20000000-0000-0000-0000-000000000001');
select public.fn_create_job((select job2 from t), (select kam from t), null,
  'Power out in workshop', null, 'urgent', null, null, null);
reset role;
select pg_temp.check(exists (
  select 1 from public.notifications
  where user_id = '20000000-0000-0000-0000-000000000002' and link = 'job:' || (select job2 from t)
), 'urgent job alerts the supervisor');

select pg_temp.act_as('20000000-0000-0000-0000-000000000002');
select pg_temp.check((select count(*) from public.fn_job_assignees((select kam from t))) >= 3, 'assignee list for the site');
select pg_temp.fails($$select public.fn_assign_job((select job2 from t), '20000000-0000-0000-0000-000000000003')$$,
  'INVALID', 'cannot assign someone from another site');
select public.fn_assign_job((select job2 from t), '20000000-0000-0000-0000-000000000004');
select pg_temp.check((select assignee_id from public.jobs where id = (select job2 from t)) = '20000000-0000-0000-0000-000000000004', 'supervisor assigns');
reset role;
select pg_temp.check(exists (
  select 1 from public.notifications
  where user_id = '20000000-0000-0000-0000-000000000004' and type = 'assigned'
), 'assignee notified');

-- Overdue job 1 is done, so only open overdue jobs count
update public.jobs set due_at = now() - interval '2 hours' where id = (select job2 from t);
select pg_temp.check(public.fn_notify_overdue() >= 1, 'overdue job notified');
select pg_temp.check(public.fn_notify_overdue() = 0, 'overdue notified once');

select pg_temp.act_as('20000000-0000-0000-0000-000000000002');
select public.fn_set_job_status((select job2 from t), 'cancelled', 'Duplicate');
select pg_temp.check((select status from public.jobs where id = (select job2 from t)) = 'cancelled', 'supervisor cancels');

-- Recurring jobs
select public.fn_save_recurrence(gen_random_uuid(), (select kam from t), null, 'Weekly lighting check',
  null, 'low', 'weekly', current_date, 2, '20000000-0000-0000-0000-000000000001', false);
reset role;
select pg_temp.check(public.fn_run_recurrences() >= 1, 'recurrence runs');
-- Since 0015 recurrences raise job cards, and the planned person is told.
select pg_temp.check(exists (
  select 1 from public.job_cards where title = 'Weekly lighting check' and source = 'preventive'
    and priority = 'P4'
), 'recurrence raises a preventive job card');
select pg_temp.check(exists (
  select 1 from public.notifications
  where user_id = '20000000-0000-0000-0000-000000000001' and link like 'jobcard:%'
    and title like '% is due (planned maintenance)'
), 'the planned person is told');
select pg_temp.check((select next_run from public.job_recurrences where title = 'Weekly lighting check')
  > current_date, 'next run moves forward');
select pg_temp.check(public.fn_run_recurrences() = 0, 'recurrence runs once per period');

select pg_temp.act_as('20000000-0000-0000-0000-000000000001');
select pg_temp.fails($$select public.fn_save_recurrence(gen_random_uuid(), (select kam from t), null, 'Nope',
  null, 'low', 'daily', current_date, 1, null, false)$$, 'NOT_ALLOWED', 'technician cannot set up recurring jobs');
reset role;

rollback;
