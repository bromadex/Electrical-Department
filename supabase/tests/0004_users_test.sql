-- Behaviour checks for 0004_users. Runs in a transaction and rolls back.
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

-- An all-site admin, a site-only admin and a new person.
insert into public.sites (id, code, name) values ('80000000-0000-0000-0000-0000000000a1', 'USR', 'User test site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('80000000-0000-0000-0000-000000000001', 'usr-admin@test', '{"full_name":"Usr Admin"}'),
  ('80000000-0000-0000-0000-000000000002', 'usr-siteadmin@test', '{"full_name":"Usr Site Admin"}'),
  ('80000000-0000-0000-0000-000000000003', 'usr-new@test', '{"full_name":"Usr New"}');
insert into public.user_roles (user_id, role_id, site_id)
select '80000000-0000-0000-0000-000000000001', id, null from public.roles where name = 'Admin';
insert into public.user_roles (user_id, role_id, site_id)
select '80000000-0000-0000-0000-000000000002', id, '80000000-0000-0000-0000-0000000000a1' from public.roles where name = 'Admin';

-- Only all-site admins.
select pg_temp.act_as('80000000-0000-0000-0000-000000000002');
select pg_temp.fails('select * from public.fn_admin_users()', 'NOT_ALLOWED', 'a site admin cannot list users');
select pg_temp.fails($$select public.fn_set_user_roles('80000000-0000-0000-0000-000000000003', '[]')$$,
  'NOT_ALLOWED', 'a site admin cannot change roles');
select pg_temp.as_owner();
select pg_temp.act_as('80000000-0000-0000-0000-000000000003');
select pg_temp.fails('select * from public.fn_admin_users()', 'NOT_ALLOWED', 'others cannot list users');
select pg_temp.as_owner();

select pg_temp.act_as('80000000-0000-0000-0000-000000000001');
select pg_temp.check((select email = 'usr-new@test' and full_name = 'Usr New' and roles = '[]'::jsonb
  from public.fn_admin_users() where id = '80000000-0000-0000-0000-000000000003'),
  'admins see email, name and roles');

-- Profile.
select public.fn_set_user_profile('80000000-0000-0000-0000-000000000003', '  New Person ', ' 0771 ',
  '80000000-0000-0000-0000-0000000000a1', true);
select pg_temp.check((select full_name = 'New Person' and phone = '0771' and home_site_id = '80000000-0000-0000-0000-0000000000a1'
  from public.profiles where id = '80000000-0000-0000-0000-000000000003'), 'profile is saved and trimmed');
select pg_temp.fails($$select public.fn_set_user_profile('80000000-0000-0000-0000-000000000003', 'x', null, null, true)$$,
  'INVALID', 'a name is needed');
select pg_temp.fails($$select public.fn_set_user_profile('80000000-0000-0000-0000-000000000001', 'Usr Admin', null, null, false)$$,
  'INVALID', 'admins cannot switch themselves off');
select public.fn_set_user_profile('80000000-0000-0000-0000-000000000003', 'New Person', null, null, false);
select pg_temp.check((select not active from public.profiles where id = '80000000-0000-0000-0000-000000000003'),
  'admins can switch someone off');

-- Roles.
select public.fn_set_user_roles('80000000-0000-0000-0000-000000000003',
  '[{"role":"Technician","site_id":"80000000-0000-0000-0000-0000000000a1"},{"role":"Storekeeper","site_id":null}]');
select pg_temp.check((select jsonb_array_length(roles) = 2 from public.fn_admin_users()
  where id = '80000000-0000-0000-0000-000000000003'), 'roles are granted');
select public.fn_set_user_roles('80000000-0000-0000-0000-000000000003',
  '[{"role":"Technician","site_id":"80000000-0000-0000-0000-0000000000a1"}]');
select pg_temp.check((select roles = '[{"role":"Technician","site_id":"80000000-0000-0000-0000-0000000000a1"}]'::jsonb
  from public.fn_admin_users() where id = '80000000-0000-0000-0000-000000000003'), 'missing roles are removed');
select pg_temp.fails($$select public.fn_set_user_roles('80000000-0000-0000-0000-000000000003', '[{"role":"Wizard"}]')$$,
  'INVALID', 'unknown roles are refused');
select pg_temp.fails($$select public.fn_set_user_roles('80000000-0000-0000-0000-000000000001', '[]')$$,
  'INVALID', 'admins cannot remove their own admin rights');
select pg_temp.check(public._can('admin.users', null), 'and keep them after the refusal');
select pg_temp.as_owner();

rollback;
