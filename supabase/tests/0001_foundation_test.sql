-- Behaviour checks for 0001_foundation. Runs in a transaction and rolls back.
-- psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/0001_foundation_test.sql
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

-- Users: tech at KAM, admin everywhere, inactive tech, no-role user
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000001', 'tech@test', '{"full_name":"Tech One"}'),
  ('00000000-0000-0000-0000-000000000002', 'admin@test', '{"full_name":"Admin"}'),
  ('00000000-0000-0000-0000-000000000003', 'gone@test', '{}'),
  ('00000000-0000-0000-0000-000000000004', 'none@test', '{}');

select pg_temp.check((select count(*) from public.profiles where id in ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000004')) = 4, 'sign-up trigger creates profiles');
select pg_temp.check((select full_name from public.profiles where id = '00000000-0000-0000-0000-000000000001') = 'Tech One', 'full_name copied from metadata');

insert into public.user_roles (user_id, role_id, site_id)
select '00000000-0000-0000-0000-000000000001', r.id, s.id from public.roles r, public.sites s where r.name = 'Electrician' and s.code = 'KAM';
insert into public.user_roles (user_id, role_id, site_id)
select '00000000-0000-0000-0000-000000000002', r.id, null from public.roles r where r.name = 'System Administrator';
insert into public.user_roles (user_id, role_id, site_id)
select '00000000-0000-0000-0000-000000000003', r.id, null from public.roles r where r.name = 'Electrician';
update public.profiles set active = false where id = '00000000-0000-0000-0000-000000000003';

create temp table ids as select
  (select id from public.sites where code = 'KAM') kam,
  (select id from public.sites where code = 'SEL') sel;
grant select on ids to authenticated;

-- Electrician at KAM
select pg_temp.act_as('00000000-0000-0000-0000-000000000001');
select pg_temp.check(public._can('jc.register', (select kam from ids)), 'electrician can jc.register at KAM');
select pg_temp.check(not public._can('jc.register', (select sel from ids)), 'electrician cannot jc.register at SEL');
select pg_temp.check(not public._can('jc.assign', (select kam from ids)), 'electrician cannot jc.assign');
select pg_temp.check(not public._can('jobs.create', (select kam from ids)), 'retired jobs.* codes grant nothing');
select pg_temp.check((select count(*) from public.my_permissions()) = 11, 'electrician my_permissions has 11 codes');
select pg_temp.check((select count(*) from public.sites) = 4, 'tech reads sites');
select pg_temp.check((select count(*) from public.profiles where id in ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000004')) = 4, 'tech reads profiles');
select pg_temp.check((select count(*) from public.user_roles) = 1, 'tech sees only own roles');
select pg_temp.check((select count(*) from public.roles) = 1, 'tech sees only own role');
select pg_temp.check((select count(*) from public.activity) = 0, 'tech cannot read activity');
update public.profiles set phone = '0771' where id = '00000000-0000-0000-0000-000000000001';
select pg_temp.check((select phone from public.profiles where id = '00000000-0000-0000-0000-000000000001') = '0771', 'tech edits own phone');
update public.profiles set phone = 'x' where id = '00000000-0000-0000-0000-000000000002';
select pg_temp.check((select phone from public.profiles where id = '00000000-0000-0000-0000-000000000002') is null, 'tech cannot edit others');
do $$ begin
  update public.profiles set active = false where id = '00000000-0000-0000-0000-000000000001';
  raise exception 'FAILED: tech deactivated self';
exception when others then
  if sqlerrm not like 'NOT_ALLOWED:%' then raise; end if;
  raise notice 'ok - tech cannot change own active flag';
end $$;
update public.sites set name = 'x' where code = 'KAM';
select pg_temp.check((select name from public.sites where code = 'KAM') = 'Kamativi', 'tech cannot edit sites');
do $$ begin
  perform public.next_code((select kam from ids), 'J');
  raise exception 'FAILED: next_code callable';
exception when insufficient_privilege then raise notice 'ok - next_code is internal';
end $$;
do $$ begin
  perform public.fn_notify('00000000-0000-0000-0000-000000000001', null, 'general', 't', null, null);
  raise exception 'FAILED: fn_notify callable';
exception when insufficient_privilege then raise notice 'ok - fn_notify is internal';
end $$;
select public.fn_register_device('tok-1', 'web');
select pg_temp.check((select count(*) from public.device_tokens) = 1, 'register device');
select public.fn_register_device('tok-1', 'web');
select pg_temp.check((select count(*) from public.device_tokens) = 1, 'register device is idempotent');
reset role;

-- Codes and notifications (as the database owner)
insert into public.sites (code, name) values ('TST', 'Test site');
select pg_temp.check(public.next_code((select id from public.sites where code = 'TST'), 'J') = 'J-0001', 'first code J-0001');
select pg_temp.check(public.next_code((select id from public.sites where code = 'TST'), 'J') = 'J-0002', 'second code J-0002');
select pg_temp.check(public.next_code((select id from public.sites where code = 'TST'), 'T') = 'T-0001', 'codes are per prefix');
select pg_temp.check(public.next_code((select kam from ids), 'J') ~ '^J-[0-9]{4}$', 'codes are per site');
select public.fn_notify_permission((select kam from ids), 'jc.assign', 'general', 'Assign', null, null);
select pg_temp.check(exists (select 1 from public.notifications where title = 'Assign' and user_id = '00000000-0000-0000-0000-000000000002'), 'notify jc.assign at KAM reaches admin');
select pg_temp.check(not exists (select 1 from public.notifications where title = 'Assign' and user_id = '00000000-0000-0000-0000-000000000001'), 'notify jc.assign skips electrician');
select public.fn_notify_permission((select kam from ids), 'jc.view', 'general', 'View', null, null);
select pg_temp.check(exists (select 1 from public.notifications where title = 'View' and user_id = '00000000-0000-0000-0000-000000000001'), 'notify jc.view at KAM reaches electrician');
select pg_temp.check(not exists (select 1 from public.notifications where title = 'View' and user_id = '00000000-0000-0000-0000-000000000003'), 'notify jc.view skips inactive user');
select public.fn_notify('00000000-0000-0000-0000-000000000001', null, 'assigned', 'Job', 'body', 'job:x');

select pg_temp.act_as('00000000-0000-0000-0000-000000000001');
select pg_temp.check((select count(*) from public.notifications) = 2, 'tech sees own notifications');
do $$ begin
  update public.notifications set title = 'hacked';
  raise exception 'FAILED: title editable';
exception when insufficient_privilege then raise notice 'ok - only read_at is editable';
end $$;
select pg_temp.check(public.fn_mark_read(null) = 2, 'mark all read');
select pg_temp.check(public.fn_mark_read(null) = 0, 'mark read again is a no-op');
reset role;

-- Inactive user sees nothing
select pg_temp.act_as('00000000-0000-0000-0000-000000000003');
select pg_temp.check(not public._can('jc.view', (select kam from ids)), 'inactive user has no permissions');
select pg_temp.check((select count(*) from public.my_permissions()) = 0, 'inactive my_permissions empty');
select pg_temp.check((select count(*) from public.sites) = 0, 'inactive user reads no sites');
reset role;

-- Admin
select pg_temp.act_as('00000000-0000-0000-0000-000000000002');
select pg_temp.check(public._can('admin.users', null), 'admin has admin.users');
select pg_temp.check((select count(*) from public.user_roles where user_id in ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000004')) = 3, 'admin sees all user roles');
select pg_temp.check((select count(*) from public.activity) > 0, 'admin reads activity');
update public.sites set name = 'Kamativi Mine' where code = 'KAM';
select pg_temp.check((select name from public.sites where code = 'KAM') = 'Kamativi Mine', 'admin edits sites');
update public.profiles set active = true where id = '00000000-0000-0000-0000-000000000003';
select pg_temp.check((select active from public.profiles where id = '00000000-0000-0000-0000-000000000003'), 'admin reactivates user');
update public.user_roles set is_archived = true where user_id = '00000000-0000-0000-0000-000000000001';
select pg_temp.check((select action from public.activity where table_name = 'user_roles' order by at desc, action limit 1) = 'archive', 'archive logged as archive');
reset role;

select pg_temp.act_as('00000000-0000-0000-0000-000000000001');
select pg_temp.check(not public._can('jc.view', (select kam from ids)), 'archived role grants nothing');
reset role;

-- Signed-out visitor
set local role anon;
do $$ begin
  perform count(*) from public.sites;
  raise exception 'FAILED: anon read sites';
exception when insufficient_privilege then raise notice 'ok - anon cannot read sites';
end $$;
reset role;

-- Storage paths
select pg_temp.check(public._path_site('11111111-2222-3333-4444-555555555555/job/x/a.jpg') = '11111111-2222-3333-4444-555555555555', 'path site parsed');
select pg_temp.check(public._path_site('nope/job/x/a.jpg') is null, 'bad path gives null');
select pg_temp.check((select count(*) from storage.buckets where not public) = 5, 'five private buckets');
select pg_temp.check(exists (select 1 from public.schema_migrations where filename = '0001_foundation.sql'), 'migration logged');

rollback;
