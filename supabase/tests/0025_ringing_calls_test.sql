-- Behaviour checks for 0025_ringing_calls. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('fa000000-0000-0000-0000-0000000000a1', 'RNG', 'Ring site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('fa000000-0000-0000-0000-000000000001', 'rng-a@test', '{"full_name":"Ring Alpha"}'),
  ('fa000000-0000-0000-0000-000000000002', 'rng-b@test', '{"full_name":"Ring Bravo"}');
insert into public.user_roles (user_id, role_id, site_id)
select u, r.id, 'fa000000-0000-0000-0000-0000000000a1'::uuid
from public.roles r, (values ('fa000000-0000-0000-0000-000000000001'::uuid), ('fa000000-0000-0000-0000-000000000002'::uuid)) v(u)
where r.name = 'Technician';

create temp table rchat (id uuid, grp uuid);
grant select, insert on rchat to authenticated;

select pg_temp.act_as('fa000000-0000-0000-0000-000000000001');
insert into rchat select public.fn_open_direct(gen_random_uuid(), 'fa000000-0000-0000-0000-000000000002'),
  (select id from public.conversations where is_default and site_id = 'fa000000-0000-0000-0000-0000000000a1');
select public.fn_start_call((select id from rchat), true);
select public.fn_start_call((select grp from rchat));
select pg_temp.as_owner();

select pg_temp.check((select count(*) = 1 from public.notifications
  where user_id = 'fa000000-0000-0000-0000-000000000002' and type = 'call'
    and title = 'Ring Alpha' and body = 'Incoming video call' and link = 'call:' || (select id from rchat)),
  'a direct call rings: type call, the caller''s name, video or voice');
select pg_temp.check((select count(*) = 1 from public.notifications
  where user_id = 'fa000000-0000-0000-0000-000000000002' and type = 'meeting'
    and title = 'Ring Alpha started a call' and link = 'call:' || (select grp from rchat)),
  'a group call stays an ordinary alert');
select pg_temp.check(not exists (select 1 from public.notifications
  where user_id = 'fa000000-0000-0000-0000-000000000001' and type in ('call', 'meeting')),
  'the caller is not rung');

rollback;
