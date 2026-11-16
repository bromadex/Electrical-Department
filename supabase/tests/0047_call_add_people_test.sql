-- Behaviour checks for 0047_call_add_people. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('fe470000-0000-0000-0000-0000000000a1', 'RNG', 'Ring site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('fe470000-0000-0000-0000-000000000001', 'rng-a@test', '{"full_name":"RNG Anna"}'),
  ('fe470000-0000-0000-0000-000000000002', 'rng-b@test', '{"full_name":"RNG Ben"}'),
  ('fe470000-0000-0000-0000-000000000003', 'rng-c@test', '{"full_name":"RNG Cara"}');
insert into public.user_roles (user_id, role_id, site_id)
select u, r.id, 'fe470000-0000-0000-0000-0000000000a1'::uuid
from public.roles r, unnest(array['fe470000-0000-0000-0000-000000000001'::uuid,
  'fe470000-0000-0000-0000-000000000002'::uuid, 'fe470000-0000-0000-0000-000000000003'::uuid]) u
where r.name = 'Technician';
-- Anna is a supervisor too (creates groups).
insert into public.user_roles (user_id, role_id, site_id)
select 'fe470000-0000-0000-0000-000000000001'::uuid, id, 'fe470000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Supervisor';

select pg_temp.act_as('fe470000-0000-0000-0000-000000000001');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
insert into ids values ('group', (public.fn_create_group(gen_random_uuid(), 'Ring site group',
  'fe470000-0000-0000-0000-0000000000a1', array['fe470000-0000-0000-0000-000000000002'::uuid,
  'fe470000-0000-0000-0000-000000000003'::uuid])).id);
insert into ids values ('direct', public.fn_open_direct(gen_random_uuid(), 'fe470000-0000-0000-0000-000000000002'));
select pg_temp.as_owner();
update public.conversation_members set joined_at = now() - interval '1 hour'
where conversation_id in (select v from ids);

select pg_temp.act_as('fe470000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_call_ring((select v from ids where k = 'group'), array['fe470000-0000-0000-0000-000000000003'::uuid])$$,
  'INVALID', 'with no call going, nobody can be rung');
select pg_temp.act_as('fe470000-0000-0000-0000-000000000001');
select public.fn_start_call((select v from ids where k = 'group'), false);
select pg_temp.act_as('fe470000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_call_ring((select v from ids where k = 'group'), array['fe470000-0000-0000-0000-000000000003'::uuid])$$,
  'INVALID', 'only someone in the call can add people');
select pg_temp.act_as('fe470000-0000-0000-0000-000000000001');
select pg_temp.as_owner();
delete from public.notifications where user_id in ('fe470000-0000-0000-0000-000000000002', 'fe470000-0000-0000-0000-000000000003') and link = 'call:' || (select v from ids where k = 'group')::text;
select pg_temp.act_as('fe470000-0000-0000-0000-000000000001');
select pg_temp.check(public.fn_call_ring((select v from ids where k = 'group'), array['fe470000-0000-0000-0000-000000000003'::uuid, 'fe470000-0000-0000-0000-000000000001'::uuid, gen_random_uuid()]) = 1,
  'Anna rings Cara (not herself, not strangers)');
select pg_temp.as_owner();
select pg_temp.check((select count(*) = 1 from public.notifications where user_id = 'fe470000-0000-0000-0000-000000000003' and type = 'call'
  and link = 'call:' || (select v from ids where k = 'group')::text), 'Cara''s phone rings for the call');
select pg_temp.act_as('fe470000-0000-0000-0000-000000000003');
select public.fn_start_call((select v from ids where k = 'group'), false);
select pg_temp.act_as('fe470000-0000-0000-0000-000000000001');
select pg_temp.check(public.fn_call_ring((select v from ids where k = 'group'), array['fe470000-0000-0000-0000-000000000003'::uuid]) = 0, 'someone already in the call is not rung');
select pg_temp.as_owner();

rollback;
