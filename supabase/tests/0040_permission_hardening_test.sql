-- Behaviour checks for 0040_permission_hardening (the permission audit,
-- issue #35). Runs in a transaction and rolls back.
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

-- Structure: holds for every table and function, including later ones.
select pg_temp.check(not exists (
  select 1 from information_schema.role_table_grants
  where table_schema = 'public' and grantee = 'anon'),
  'signed-out users hold no rights on any table');

select pg_temp.check(not exists (
  select 1
  from information_schema.role_table_grants g
  join pg_class c on c.relname = g.table_name
  join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
  where g.table_schema = 'public' and g.grantee = 'authenticated'
    and g.privilege_type in ('INSERT', 'UPDATE', 'DELETE')
    and not exists (
      select 1 from pg_policies p
      where p.schemaname = 'public' and p.tablename = g.table_name
        and p.cmd in (g.privilege_type, 'ALL') and 'authenticated' = any (p.roles))),
  'signed-in users write directly only where a policy allows it (revoke the rest on new tables)');

select pg_temp.check(not exists (
  select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  'every table has row-level security');

select pg_temp.check(not exists (
  select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef
    and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')),
  'every security definer function pins its search path');

select pg_temp.check(not exists (
  select 1 from cron.job j, pg_proc p
  where j.command like '%public.' || p.proname || '(%'
    and p.pronamespace = 'public'::regnamespace
    and (has_function_privilege('authenticated', p.oid, 'execute')
      or has_function_privilege('anon', p.oid, 'execute'))),
  'functions the scheduler runs cannot be called from the app');

select pg_temp.check(not exists (
  select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef and p.proname not like '\_%'
    and has_function_privilege('anon', p.oid, 'execute')),
  'signed-out users cannot run any fn_ function');

select pg_temp.check(not exists (
  select 1 from pg_policies where schemaname = 'storage' and cmd in ('UPDATE', 'DELETE', 'ALL')),
  'nobody can overwrite or delete stored files from the app');

-- People.
insert into public.sites (id, code, name) values ('fe400000-0000-0000-0000-0000000000a1', 'PRA', 'Audit site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('fe400000-0000-0000-0000-000000000001', 'pa-admin@test', '{"full_name":"Pa Admin"}'),
  ('fe400000-0000-0000-0000-000000000002', 'pa-tech@test', '{"full_name":"Pa Tech"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'fe400000-0000-0000-0000-000000000001'::uuid, id, null from public.roles where name = 'Admin'
union all
select 'fe400000-0000-0000-0000-000000000002'::uuid, id, 'fe400000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Technician';

-- Leave only this admin active, as on a new install.
update public.user_roles ur set is_archived = true
from public.roles r
where r.id = ur.role_id and r.name = 'Admin' and ur.user_id <> 'fe400000-0000-0000-0000-000000000001';

create temp table admin_role as select id from public.roles where name = 'Admin';
grant select on admin_role to authenticated;

select pg_temp.act_as('fe400000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_send_standby_reminders()$$, '', 'the app cannot send standby reminders');
select pg_temp.fails($$update public.job_cards set status = 'closed'$$, '',
  'a technician cannot change job cards directly');
select pg_temp.fails($$insert into public.stock_moves (id, item_id, site_id, kind, qty, balance_after)
  values (gen_random_uuid(), gen_random_uuid(), 'fe400000-0000-0000-0000-0000000000a1', 'receive', 5, 5)$$, '',
  'or write stock moves directly');
select pg_temp.fails($$insert into public.user_roles (user_id, role_id, site_id)
  select 'fe400000-0000-0000-0000-000000000002', id, null from admin_role$$, '',
  'a technician cannot make themselves admin');
select pg_temp.fails($$insert into public.role_permissions (role_id, permission_code)
  select r.id, 'admin.users' from public.user_roles ur join public.roles r on r.id = ur.role_id
  where ur.user_id = 'fe400000-0000-0000-0000-000000000002'
  union all select gen_random_uuid(), 'admin.users' limit 1$$, '',
  'or grant their role more');
update public.profiles set active = false where id = 'fe400000-0000-0000-0000-000000000001';
select pg_temp.as_owner();
select pg_temp.check((select active from public.profiles where id = 'fe400000-0000-0000-0000-000000000001'),
  'or deactivate someone else');

select pg_temp.act_as('fe400000-0000-0000-0000-000000000001');
select pg_temp.fails($$update public.user_roles ur set is_archived = true from public.roles r
  where r.id = ur.role_id and r.name = 'Admin' and ur.user_id = 'fe400000-0000-0000-0000-000000000001'$$,
  'INVALID', 'the last admin cannot lose the role');
select pg_temp.fails($$update public.profiles set active = false where id = 'fe400000-0000-0000-0000-000000000001'$$,
  'INVALID', 'or be deactivated');
select pg_temp.fails($$update public.role_permissions rp set is_archived = true from public.roles r
  where r.id = rp.role_id and r.name = 'Admin' and rp.permission_code = 'admin.users'$$,
  'INVALID', 'Admin keeps admin.users');

-- With a second admin, the first can step down.
insert into public.user_roles (user_id, role_id, site_id)
select 'fe400000-0000-0000-0000-000000000002', id, null from public.roles where name = 'Admin';
update public.user_roles ur set is_archived = true from public.roles r
where r.id = ur.role_id and r.name = 'Admin' and ur.user_id = 'fe400000-0000-0000-0000-000000000001';
select pg_temp.as_owner();
select pg_temp.check((select bool_and(ur.is_archived) from public.user_roles ur join public.roles r on r.id = ur.role_id
  where r.name = 'Admin' and ur.user_id = 'fe400000-0000-0000-0000-000000000001'),
  'with another admin, an admin can step down');

rollback;
