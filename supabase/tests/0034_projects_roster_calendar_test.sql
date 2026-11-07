-- Behaviour checks for 0034_projects_roster_calendar. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values
  ('fe000000-0000-0000-0000-0000000000a1', 'PJA', 'Project site'),
  ('fe000000-0000-0000-0000-0000000000a2', 'PJB', 'Other project site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('fe000000-0000-0000-0000-000000000001', 'pj-sup@test', '{"full_name":"Pj Sup"}'),
  ('fe000000-0000-0000-0000-000000000002', 'pj-tech@test', '{"full_name":"Pj Tech"}'),
  ('fe000000-0000-0000-0000-000000000003', 'pj-store@test', '{"full_name":"Pj Store"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'fe000000-0000-0000-0000-000000000001'::uuid, id, null::uuid from public.roles where name = 'Supervisor'
union all
select 'fe000000-0000-0000-0000-000000000002'::uuid, id, 'fe000000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Technician'
union all
select 'fe000000-0000-0000-0000-000000000003'::uuid, id, 'fe000000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Storekeeper';
insert into public.job_cards (id, number, source, site_id, location, received_at, reporter_name, title, description,
  priority, target_completion_at, status)
values
  ('fe000000-0000-0000-0000-0000000000c1', 'PJA-JC-0001', 'direct', 'fe000000-0000-0000-0000-0000000000a1', 'Plant',
    now(), 'Foreman', 'Pull new feeder', 'Pull the new feeder cable to substation 3',
    (select code from public.priority_levels order by 1 limit 1), now() + interval '2 days', 'registered'),
  ('fe000000-0000-0000-0000-0000000000c2', 'PJA-JC-0002', 'direct', 'fe000000-0000-0000-0000-0000000000a1', 'Plant',
    now(), 'Foreman', 'Terminate feeder', 'Terminate the feeder at both ends',
    (select code from public.priority_levels order by 1 limit 1), null, 'registered'),
  ('fe000000-0000-0000-0000-0000000000c3', 'PJB-JC-0001', 'direct', 'fe000000-0000-0000-0000-0000000000a2', 'Plant',
    now(), 'Foreman', 'Other site job', 'A job card at the other site',
    (select code from public.priority_levels order by 1 limit 1), null, 'registered');
create temp table w as select (public._harare_today() + 1) as tomorrow,
  (public._harare_today() + 1) - (extract(isodow from public._harare_today() + 1)::integer - 1) as monday;
grant select on w to authenticated;

-- Projects
select pg_temp.act_as('fe000000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_save_project('fe000000-0000-0000-0000-0000000000f1',
  'fe000000-0000-0000-0000-0000000000a1', 'Substation 3 upgrade', null, null, null, null, null)$$,
  'NOT_ALLOWED', 'technicians cannot make projects');
select pg_temp.as_owner();

select pg_temp.act_as('fe000000-0000-0000-0000-000000000001');
select pg_temp.check((select code = 'P-0001' and status = 'active' from public.fn_save_project(
  'fe000000-0000-0000-0000-0000000000f1', 'fe000000-0000-0000-0000-0000000000a1', 'Substation 3 upgrade',
  'New feeder and switchgear', current_date + 3, 'fe000000-0000-0000-0000-000000000001', null,
  array['fe000000-0000-0000-0000-000000000002']::uuid[])), 'a supervisor makes a project with a P- code');
select public.fn_set_job_project('fe000000-0000-0000-0000-0000000000c1', 'fe000000-0000-0000-0000-0000000000f1');
select public.fn_set_job_project('fe000000-0000-0000-0000-0000000000c2', 'fe000000-0000-0000-0000-0000000000f1');
select pg_temp.fails($$select public.fn_set_job_project('fe000000-0000-0000-0000-0000000000c3',
  'fe000000-0000-0000-0000-0000000000f1')$$, 'INVALID', 'only job cards at the project''s site');
select pg_temp.as_owner();
update public.job_cards set status = 'closed', closed_at = now() where id = 'fe000000-0000-0000-0000-0000000000c2';
select pg_temp.check((select count(*) = 1 from public.notifications
  where user_id = 'fe000000-0000-0000-0000-000000000002' and link = 'project:fe000000-0000-0000-0000-0000000000f1'),
  'team members are told they are on the project');

select pg_temp.act_as('fe000000-0000-0000-0000-000000000002');
select pg_temp.check((select jobs_total = 2 and jobs_done = 1
    and member_ids = array['fe000000-0000-0000-0000-000000000002']::uuid[]
  from public.project_overview where id = 'fe000000-0000-0000-0000-0000000000f1'),
  'progress counts its job cards, and the team shows');
select pg_temp.as_owner();

-- Store stock to a project
select pg_temp.act_as('fe000000-0000-0000-0000-000000000003');
select public.fn_save_item('fe000000-0000-0000-0000-0000000000b1', 'fe000000-0000-0000-0000-0000000000a1',
  '95mm 4-core cable', 'm', 'cable', null, 0, false);
select public.fn_receive_stock(gen_random_uuid(), 'fe000000-0000-0000-0000-0000000000b1', 300, null);
select pg_temp.check((select project_id = 'fe000000-0000-0000-0000-0000000000f1' and balance_after = 100
  from public.fn_issue_stock(gen_random_uuid(), 'fe000000-0000-0000-0000-0000000000b1', 200, null, null, null,
    null, 'fe000000-0000-0000-0000-0000000000f1')), 'store stock can be issued to a project');
select pg_temp.check((select balance_after = 90 from public.fn_issue_stock(gen_random_uuid(),
  'fe000000-0000-0000-0000-0000000000b1', 10, 'fe000000-0000-0000-0000-0000000000c1', null, null, null)),
  'issuing without a project still works as before');
select pg_temp.as_owner();

-- Roster
select pg_temp.act_as('fe000000-0000-0000-0000-000000000001');
select pg_temp.fails($$select public.fn_set_roster('fe000000-0000-0000-0000-0000000000a1',
  (select monday + 1 from w), '[]', false)$$, 'INVALID', 'a roster week starts on a Monday');
select pg_temp.check(public.fn_set_roster('fe000000-0000-0000-0000-0000000000a1', (select monday from w),
  jsonb_build_array(
    jsonb_build_object('user_id', 'fe000000-0000-0000-0000-000000000002', 'day', (select tomorrow from w),
      'shift', 'day', 'standby', true),
    jsonb_build_object('user_id', 'fe000000-0000-0000-0000-000000000003', 'day', (select tomorrow from w),
      'shift', 'off', 'standby', true)), false) = 2, 'a supervisor sets the week');
select pg_temp.check((select not standby from public.roster_entries
  where user_id = 'fe000000-0000-0000-0000-000000000003'), 'nobody is on standby on a day off');
select pg_temp.as_owner();
select pg_temp.check(public.fn_send_standby_reminders() = 0, 'no standby reminder before the roster is published');

select pg_temp.act_as('fe000000-0000-0000-0000-000000000001');
select public.fn_set_roster('fe000000-0000-0000-0000-0000000000a1', (select monday from w), '[]', true);
select pg_temp.as_owner();
select pg_temp.check((select count(*) = 1 from public.notifications
  where user_id = 'fe000000-0000-0000-0000-000000000002' and link like 'roster:%'),
  'publishing tells everyone on the week''s roster');
select pg_temp.check(public.fn_send_standby_reminders() = 1 and public.fn_send_standby_reminders() = 0,
  'tomorrow''s standby person is reminded once');

-- Calendar
insert into public.reminders (user_id, site_id, remind_at, note)
values ('fe000000-0000-0000-0000-000000000002', 'fe000000-0000-0000-0000-0000000000a1', now() + interval '1 day',
  'Collect the Megger');
select pg_temp.act_as('fe000000-0000-0000-0000-000000000002');
create temp table cal as
  select * from public.fn_calendar('fe000000-0000-0000-0000-0000000000a1', current_date, current_date + 7);
select pg_temp.check(exists (select 1 from cal where kind = 'job' and ref_id = 'fe000000-0000-0000-0000-0000000000c1')
  and exists (select 1 from cal where kind = 'project' and ref_id = 'fe000000-0000-0000-0000-0000000000f1')
  and exists (select 1 from cal where kind = 'standby')
  and exists (select 1 from cal where kind = 'reminder' and title = 'Collect the Megger'),
  'the calendar brings job cards, projects, my standby and my reminders together');
select pg_temp.check(not exists (select 1 from cal where kind in ('shift', 'standby')
  and ref_id in (select id from public.roster_entries where user_id <> 'fe000000-0000-0000-0000-000000000002')),
  'and shows only my own shifts');
select pg_temp.fails($$select public.fn_set_roster('fe000000-0000-0000-0000-0000000000a1', (select monday from w),
  '[]', true)$$, 'NOT_ALLOWED', 'technicians cannot set the roster');
select pg_temp.as_owner();

rollback;
