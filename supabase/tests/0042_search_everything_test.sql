-- Behaviour checks for 0042_search_everything. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('fe420000-0000-0000-0000-0000000000a1', 'SRC', 'Search site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('fe420000-0000-0000-0000-000000000001', 'se-store@test', '{"full_name":"Se Store"}'),
  ('fe420000-0000-0000-0000-000000000002', 'se-nobody@test', '{"full_name":"Se Nobody"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'fe420000-0000-0000-0000-000000000001'::uuid, id, 'fe420000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name in ('Storekeeper', 'Technician');

select pg_temp.act_as('fe420000-0000-0000-0000-000000000001');
select public.fn_save_item('fe420000-0000-0000-0000-0000000000b1', 'fe420000-0000-0000-0000-0000000000a1',
  'Zebra-striped warning tape', 'roll', 'consumables', 'Z9', 0, false);

select pg_temp.check((select count(*) = 1 and bool_and(link like 'item:%' and status = 'inventory')
  from public.fn_search_records('zebra-striped')), 'inventory items are found by name');
select pg_temp.check((select link from public.fn_search_records(
  (select code from public.store_items where id = 'fe420000-0000-0000-0000-0000000000b1')) limit 1)
  = 'item:fe420000-0000-0000-0000-0000000000b1', 'an exact code comes first');

select pg_temp.act_as('fe420000-0000-0000-0000-000000000002');
select pg_temp.check((select count(*) = 0 from public.fn_search_records('zebra-striped')),
  'someone without a role finds nothing');
select pg_temp.as_owner();

rollback;
