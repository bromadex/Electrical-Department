-- Behaviour checks for 0015_jobcards_everywhere. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('f1000000-0000-0000-0000-0000000000a1', 'JCE', 'Job cards site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('f1000000-0000-0000-0000-000000000001', 'jce-sup@test', '{"full_name":"Jce Sup"}'),
  ('f1000000-0000-0000-0000-000000000002', 'jce-old@test', '{"full_name":"Jce Former"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'f1000000-0000-0000-0000-000000000001'::uuid, id, 'f1000000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Supervisor';

-- A plan whose author can no longer register job cards here: the site's
-- planners are told, and the other plans still run.
insert into public.job_recurrences (id, site_id, title, priority, every, next_run, due_days, created_by)
values
  ('f1000000-0000-0000-0000-0000000000c1', 'f1000000-0000-0000-0000-0000000000a1', 'Orphan plan', 'normal',
   'weekly', current_date, 1, 'f1000000-0000-0000-0000-000000000002'),
  ('f1000000-0000-0000-0000-0000000000c2', 'f1000000-0000-0000-0000-0000000000a1', 'Monthly earth test', 'urgent',
   'monthly', current_date, 3, 'f1000000-0000-0000-0000-000000000001');
select public.fn_run_recurrences();
select pg_temp.check(not exists (select 1 from public.job_cards where title = 'Orphan plan'),
  'no job card without permission');
select pg_temp.check(exists (select 1 from public.notifications
  where user_id = 'f1000000-0000-0000-0000-000000000001' and title = 'Planned job "Orphan plan" could not be raised'),
  'planners hear about it');
select pg_temp.check((select priority = 'P2' and source = 'preventive' and maintenance_type = 'inspection'
  and location = 'Planned maintenance' from public.job_cards where title = 'Monthly earth test'),
  'other plans still raise their job card');
select pg_temp.check(coalesce(current_setting('request.jwt.claims', true), '') = '',
  'the runner leaves no one signed in');

-- The daily report counts job cards.
select pg_temp.act_as('f1000000-0000-0000-0000-000000000001');
select pg_temp.check((select (summary ->> 'jobs_open_now')::int = 1
    and summary -> 'jobs_opened' -> 0 ->> 'code' like 'EL-JC-%'
  from public.fn_build_daily_report('f1000000-0000-0000-0000-0000000000a1', public._harare_today())),
  'the daily report lists job cards');
select pg_temp.as_owner();

rollback;
