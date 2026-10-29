-- Behaviour checks for 0031_roles_at_every_site. Runs in a transaction and rolls back.
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
  ('fb000000-0000-0000-0000-0000000000a1', 'RAA', 'Role site A'),
  ('fb000000-0000-0000-0000-0000000000a2', 'RAB', 'Role site B');
insert into auth.users (id, email, raw_user_meta_data) values
  ('fb000000-0000-0000-0000-000000000001', 'ra-tech@test', '{"full_name":"Ra Tech"}'),
  ('fb000000-0000-0000-0000-000000000002', 'ra-sup@test', '{"full_name":"Ra Sup"}');
insert into public.user_roles (user_id, role_id, site_id, is_archived)
select 'fb000000-0000-0000-0000-000000000001'::uuid, id, 'fb000000-0000-0000-0000-0000000000a1'::uuid, false
from public.roles where name = 'Technician'
union all
select 'fb000000-0000-0000-0000-000000000001'::uuid, id, 'fb000000-0000-0000-0000-0000000000a2'::uuid, false
from public.roles where name = 'Technician'
union all
select 'fb000000-0000-0000-0000-000000000002'::uuid, id, 'fb000000-0000-0000-0000-0000000000a2'::uuid, false
from public.roles where name = 'Supervisor'
union all
select 'fb000000-0000-0000-0000-000000000002'::uuid, id, null, true
from public.roles where name = 'Supervisor';
insert into public.daily_reports (id, site_id, report_date, code)
values ('fb000000-0000-0000-0000-0000000000e1', 'fb000000-0000-0000-0000-0000000000a1', current_date, 'R-9311');

select pg_temp.check(public._roles_to_all_sites() >= 3, 'site-only roles are archived');
select pg_temp.check((select count(*) = 1 from public.user_roles
  where user_id = 'fb000000-0000-0000-0000-000000000001' and site_id is null and not is_archived),
  'two site roles become one role at all sites');
select pg_temp.check((select count(*) = 1 from public.user_roles
  where user_id = 'fb000000-0000-0000-0000-000000000002' and site_id is null and not is_archived),
  'an earlier all-sites role is brought back, not duplicated');
select pg_temp.check(not exists (select 1 from public.user_roles
  where user_id in ('fb000000-0000-0000-0000-000000000001', 'fb000000-0000-0000-0000-000000000002')
    and site_id is not null and not is_archived), 'no site-only roles are left');

select pg_temp.act_as('fb000000-0000-0000-0000-000000000002');
select pg_temp.check(public._works_at('fb000000-0000-0000-0000-0000000000a1')
  and public._can('jc.assign', 'fb000000-0000-0000-0000-0000000000a1'),
  'the supervisor from site B now works at site A too');
select public.fn_add_report_update(gen_random_uuid(), 'fb000000-0000-0000-0000-0000000000a1',
  current_date, 'Helped at site A today', null);
select pg_temp.check(true, 'and can add to its daily report');
select pg_temp.as_owner();

select pg_temp.check(not exists (select 1 from public.user_roles where site_id is not null and not is_archived),
  'the migration left no site-only roles in the database');

rollback;
