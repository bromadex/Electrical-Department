-- Behaviour checks for 0017_calls. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('f3000000-0000-0000-0000-0000000000a1', 'CAL', 'Call site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('f3000000-0000-0000-0000-000000000001', 'cal-sup@test', '{"full_name":"Cal Sup"}'),
  ('f3000000-0000-0000-0000-000000000002', 'cal-tech@test', '{"full_name":"Cal Tech"}'),
  ('f3000000-0000-0000-0000-000000000003', 'cal-req@test', '{"full_name":"Cal Requester"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'f3000000-0000-0000-0000-000000000001'::uuid, id, 'f3000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Supervisor'
union all
select 'f3000000-0000-0000-0000-000000000002'::uuid, id, 'f3000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Technician'
union all
select 'f3000000-0000-0000-0000-000000000003'::uuid, id, 'f3000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Requester';

select pg_temp.act_as('f3000000-0000-0000-0000-000000000002');
select pg_temp.check((select public.fn_start_call(id) ->> 'room' = 'chat-' || id
  from public.conversations where is_default and site_id = 'f3000000-0000-0000-0000-0000000000a1'),
  'members get the chat''s room');
select public.fn_start_call(id)
from public.conversations where is_default and site_id = 'f3000000-0000-0000-0000-0000000000a1';
select pg_temp.as_owner();
select pg_temp.check((select count(*) = 1 from public.notifications
  where user_id = 'f3000000-0000-0000-0000-000000000001' and title = 'Cal Tech started a call'
    and link like 'call:%'), 'the others hear once, not on every rejoin');
select pg_temp.check(not exists (select 1 from public.notifications
  where user_id = 'f3000000-0000-0000-0000-000000000002' and type = 'meeting'), 'not the caller');

create temp table call_chat as
  select id from public.conversations where is_default and site_id = 'f3000000-0000-0000-0000-0000000000a1';
grant select on call_chat to authenticated;
select pg_temp.act_as('f3000000-0000-0000-0000-000000000003');
select pg_temp.fails($$select public.fn_start_call((select id from call_chat))$$,
  'NOT_FOUND', 'people outside the chat cannot join its call');
select pg_temp.as_owner();

rollback;
