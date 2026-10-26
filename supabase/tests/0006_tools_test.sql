-- Behaviour checks for 0006_tools. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('a0000000-0000-0000-0000-0000000000a1', 'TLS', 'Tools test site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('a0000000-0000-0000-0000-000000000001', 'tl-store@test', '{"full_name":"Tl Store"}'),
  ('a0000000-0000-0000-0000-000000000002', 'tl-tech@test', '{"full_name":"Tl Tech"}'),
  ('a0000000-0000-0000-0000-000000000003', 'tl-out@test', '{"full_name":"Tl Outsider"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'a0000000-0000-0000-0000-000000000001'::uuid, id, 'a0000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Storekeeper'
union all
select 'a0000000-0000-0000-0000-000000000002'::uuid, id, 'a0000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Technician';

-- Register.
select pg_temp.act_as('a0000000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_save_tool('a0000000-0000-0000-0000-0000000000b1',
  'a0000000-0000-0000-0000-0000000000a1', 'Megger', null, null, null, null, 'good', false)$$,
  'NOT_ALLOWED', 'technicians cannot add tools');
select pg_temp.as_owner();
select pg_temp.act_as('a0000000-0000-0000-0000-000000000001');
select pg_temp.check((select code = 'T-0001' from public.fn_save_tool('a0000000-0000-0000-0000-0000000000b1',
  'a0000000-0000-0000-0000-0000000000a1', 'Megger 1kV', 'Insulation tester', 'MG-778', current_date + 3,
  null, 'good', false)), 'the store adds a tool with a T- code');
select pg_temp.check((select code = 'T-0001' and name = 'Megger 1 kV' from public.fn_save_tool('a0000000-0000-0000-0000-0000000000b1',
  'a0000000-0000-0000-0000-0000000000a1', 'Megger 1 kV', 'Insulation tester', 'MG-778', current_date + 3,
  null, 'good', false)), 'saving again edits it and keeps the code');

-- Issue and return.
select pg_temp.fails($$select public.fn_issue_tool('a0000000-0000-0000-0000-0000000000c1',
  'a0000000-0000-0000-0000-0000000000b1', 'a0000000-0000-0000-0000-000000000003', null, null)$$,
  'INVALID', 'tools go only to people at the site');
select public.fn_issue_tool('a0000000-0000-0000-0000-0000000000c1', 'a0000000-0000-0000-0000-0000000000b1',
  'a0000000-0000-0000-0000-000000000002', current_date + 1, 'x/tool/sig.png');
select public.fn_issue_tool('a0000000-0000-0000-0000-0000000000c1', 'a0000000-0000-0000-0000-0000000000b1',
  'a0000000-0000-0000-0000-000000000002', current_date + 1, 'x/tool/sig.png');
select pg_temp.check((select holder_id = 'a0000000-0000-0000-0000-000000000002' from public.tools
  where id = 'a0000000-0000-0000-0000-0000000000b1')
  and (select count(*) = 1 from public.tool_issues where tool_id = 'a0000000-0000-0000-0000-0000000000b1'),
  'issuing sets the holder, once even if sent twice');
select pg_temp.as_owner();
select pg_temp.check(exists (select 1 from public.notifications
  where user_id = 'a0000000-0000-0000-0000-000000000002' and title = 'T-0001 issued to you'),
  'the holder is told');
select pg_temp.act_as('a0000000-0000-0000-0000-000000000001');
select pg_temp.fails($$select public.fn_issue_tool('a0000000-0000-0000-0000-0000000000c2',
  'a0000000-0000-0000-0000-0000000000b1', 'a0000000-0000-0000-0000-000000000001', null, null)$$,
  'CONFLICT', 'a tool that is out cannot be issued again');
select pg_temp.fails($$select public.fn_save_tool('a0000000-0000-0000-0000-0000000000b1',
  'a0000000-0000-0000-0000-0000000000a1', 'Megger 1 kV', null, null, null, null, 'good', true)$$,
  'CONFLICT', 'a tool that is out cannot be removed');
select pg_temp.fails($$select public.fn_return_tool('a0000000-0000-0000-0000-0000000000b1', 'damaged', '')$$,
  'INVALID', 'a damaged return needs a note');
select public.fn_return_tool('a0000000-0000-0000-0000-0000000000b1', 'damaged', 'Cracked case');
select pg_temp.check((select holder_id is null and condition = 'damaged' from public.tools
  where id = 'a0000000-0000-0000-0000-0000000000b1'), 'returning clears the holder and records the condition');
select pg_temp.fails($$select public.fn_issue_tool('a0000000-0000-0000-0000-0000000000c3',
  'a0000000-0000-0000-0000-0000000000b1', 'a0000000-0000-0000-0000-000000000002', null, null)$$,
  'INVALID', 'damaged tools cannot be issued');

select pg_temp.check((select array_agg(full_name order by full_name) from public.fn_site_people(
  'a0000000-0000-0000-0000-0000000000a1', 'tools.view')) @> array['Tl Store', 'Tl Tech'],
  'pickers list the people at the site');

-- Count.
select pg_temp.check(public.fn_count_tools('a0000000-0000-0000-0000-0000000000a1',
  array['a0000000-0000-0000-0000-0000000000b1'::uuid]) = 1, 'the count marks tools seen');
select pg_temp.as_owner();
select pg_temp.act_as('a0000000-0000-0000-0000-000000000003');
select pg_temp.fails($$select * from public.fn_site_people('a0000000-0000-0000-0000-0000000000a1', 'tools.view')$$,
  'NOT_ALLOWED', 'outsiders cannot list a site''s people');
select pg_temp.as_owner();

-- Reminders.
update public.tools set condition = 'good' where id = 'a0000000-0000-0000-0000-0000000000b1';
insert into public.tool_issues (id, tool_id, issued_to, issued_at, due_back)
values ('a0000000-0000-0000-0000-0000000000c9', 'a0000000-0000-0000-0000-0000000000b1',
  'a0000000-0000-0000-0000-000000000002', now() - interval '3 days', current_date - 1);
update public.tools set holder_id = 'a0000000-0000-0000-0000-000000000002'
where id = 'a0000000-0000-0000-0000-0000000000b1';
select public.fn_notify_tools();
select pg_temp.check((select count(*) from public.notifications
  where title = 'T-0001 is overdue for return' and user_id in
    ('a0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002')) = 2,
  'overdue: holder and store are told');
select pg_temp.check((select count(*) from public.notifications
  where title like 'T-0001 calibration due%' and user_id = 'a0000000-0000-0000-0000-000000000001') = 1,
  'calibration due soon: the store is told');
-- Counts only this tool's reminders: scheduled jobs (escalations every ten
-- minutes) may notify seeded people while the test runs.
create temp table before_count as
  select count(*) as n from public.notifications where title like 'T-0001%';
select public.fn_notify_tools();
select pg_temp.check((select count(*) from public.notifications where title like 'T-0001%')
  = (select n from before_count), 'each reminder is sent once');

rollback;
