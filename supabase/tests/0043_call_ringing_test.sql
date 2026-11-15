-- Behaviour checks for 0043_call_ringing. Runs in a transaction and rolls back.
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

create function pg_temp.fails(p_sql text, p_label text) returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'FAILED: % (no error)', p_label;
exception when others then
  if sqlerrm like 'FAILED:%' then raise; end if;
  raise notice 'ok - %', p_label;
end $$;

insert into public.sites (id, code, name) values ('fe430000-0000-0000-0000-0000000000a1', 'RNG', 'Ring site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('fe430000-0000-0000-0000-000000000001', 'ring-a@test', '{"full_name":"Ring Caller"}'),
  ('fe430000-0000-0000-0000-000000000002', 'ring-b@test', '{"full_name":"Ring Callee"}');
insert into public.user_roles (user_id, role_id, site_id)
select u, r.id, 'fe430000-0000-0000-0000-0000000000a1'::uuid
from public.roles r, unnest(array['fe430000-0000-0000-0000-000000000001'::uuid,
  'fe430000-0000-0000-0000-000000000002'::uuid]) u
where r.name = 'Technician';

select pg_temp.act_as('fe430000-0000-0000-0000-000000000001');
create temp table d as
select public.fn_open_direct(gen_random_uuid(), 'fe430000-0000-0000-0000-000000000002') as conv;
grant select on d to authenticated;
select public.fn_start_call((select conv from d), false);
select pg_temp.as_owner();

select pg_temp.check((select rang_at is null from public.calls where conversation_id = (select conv from d)),
  'a new call is calling, not ringing');
select pg_temp.check((select public.fn_call_rang(gen_random_uuid())) = false,
  'an unknown alert rings nothing');
select pg_temp.check((select public.fn_call_rang(n.id) from public.notifications n
  where n.type = 'call' and n.user_id = 'fe430000-0000-0000-0000-000000000002' limit 1),
  'the callee''s phone reports the alert it got');
select pg_temp.check((select rang_at is not null from public.calls where conversation_id = (select conv from d)),
  'and the call shows as ringing');

select pg_temp.act_as('fe430000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_call_rang(gen_random_uuid())$$, 'the app cannot call it directly');
select pg_temp.as_owner();

rollback;
