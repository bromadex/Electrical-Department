-- Behaviour checks for 0021_settings. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('f7000000-0000-0000-0000-0000000000a1', 'SET', 'Settings site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('f7000000-0000-0000-0000-000000000001', 'set-admin@test', '{"full_name":"Set Admin"}'),
  ('f7000000-0000-0000-0000-000000000002', 'set-tech@test', '{"full_name":"Set Tech"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'f7000000-0000-0000-0000-000000000001'::uuid, id, null from public.roles where name = 'Admin'
union all
select 'f7000000-0000-0000-0000-000000000002'::uuid, id, 'f7000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Technician';

-- Your own profile.
select pg_temp.act_as('f7000000-0000-0000-0000-000000000002');
select public.fn_update_my_profile('  Set Technician ', ' 0771 000 000 ', 'f7000000-0000-0000-0000-0000000000a1');
select pg_temp.check((select full_name = 'Set Technician' and phone = '0771 000 000'
  and home_site_id = 'f7000000-0000-0000-0000-0000000000a1'
  from public.profiles where id = 'f7000000-0000-0000-0000-000000000002'), 'you can change your own name, phone and home site');
select pg_temp.fails($$select public.fn_update_my_profile('X', null, null)$$, 'INVALID', 'a name is needed');
select pg_temp.fails($$select public.fn_update_my_profile('Set Tech', null, gen_random_uuid())$$,
  'NOT_FOUND', 'the home site must exist');

-- Sites and areas: administrators only.
select pg_temp.fails($$select public.fn_save_site(null, 'NEW', 'New site', false)$$,
  'NOT_ALLOWED', 'a technician cannot add sites');
select pg_temp.fails($$select public.fn_save_area(null, 'f7000000-0000-0000-0000-0000000000a1', 'Workshop', false)$$,
  'NOT_ALLOWED', 'or areas');

select pg_temp.act_as('f7000000-0000-0000-0000-000000000001');
create temp table new_site as select (public.fn_save_site(null, ' tst ', 'Test site', false)).id;
grant select on new_site to authenticated;
select pg_temp.check((select code = 'TST' from public.sites where id = (select id from new_site)),
  'an admin adds a site; the code is upper-cased');
select pg_temp.check(exists (select 1 from public.conversations where site_id = (select id from new_site) and is_default),
  'a new site gets its chat');
select pg_temp.fails($$select public.fn_save_site(null, 'TST', 'Another', false)$$, 'INVALID', 'site codes are unique');
select pg_temp.fails($$select public.fn_save_site(null, 'T1', 'Bad code', false)$$, 'INVALID', 'codes are letters only');
select public.fn_save_site((select id from new_site), 'TST', 'Test site renamed', false);
select pg_temp.check((select name = 'Test site renamed' from public.sites where id = (select id from new_site)), 'rename a site');

create temp table new_area as select (public.fn_save_area(null, (select id from new_site), 'Workshop', false)).id;
grant select on new_area to authenticated;
select pg_temp.fails($$select public.fn_save_area(null, (select id from new_site), 'workshop', false)$$,
  'INVALID', 'area names are unique within a site');
select public.fn_save_area((select id from new_area), null, 'Main workshop', true);
select pg_temp.check((select name = 'Main workshop' and is_archived from public.areas where id = (select id from new_area)),
  'rename and archive an area');
select pg_temp.as_owner();

rollback;
