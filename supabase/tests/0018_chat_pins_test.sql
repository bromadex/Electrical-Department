-- Behaviour checks for 0018_chat_pins. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('f4000000-0000-0000-0000-0000000000a1', 'PIN', 'Pin site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('f4000000-0000-0000-0000-000000000001', 'pin-sup@test', '{"full_name":"Pin Sup"}'),
  ('f4000000-0000-0000-0000-000000000002', 'pin-tech@test', '{"full_name":"Pin Tech"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'f4000000-0000-0000-0000-000000000001'::uuid, id, 'f4000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Supervisor'
union all
select 'f4000000-0000-0000-0000-000000000002'::uuid, id, 'f4000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Technician';

create temp table pin_chat as
  select id from public.conversations where is_default and site_id = 'f4000000-0000-0000-0000-0000000000a1';
grant select on pin_chat to authenticated;

select pg_temp.act_as('f4000000-0000-0000-0000-000000000002');
select public.fn_open_direct(gen_random_uuid(), 'f4000000-0000-0000-0000-000000000001');
select public.fn_send_message(gen_random_uuid(),
  (select id from public.fn_my_conversations() where kind = 'direct' limit 1),
  'text', 'newest', null, null, null, null, null, null, null);
select public.fn_pin_conversation((select id from pin_chat), true);
select pg_temp.check((select id = (select id from pin_chat) and pinned from public.fn_my_conversations() limit 1),
  'a pinned chat goes to the top');
select pg_temp.check((select last_read_at is not null from public.fn_my_conversations() limit 1),
  'the list says where you stopped reading');
select public.fn_pin_conversation((select id from pin_chat), false);
select public.fn_pin_conversation((select id from public.fn_my_conversations() where kind = 'direct'), true);
select pg_temp.check((select kind = 'direct' and pinned from public.fn_my_conversations() limit 1),
  'unpin and pin another: it goes to the top instead');

select pg_temp.act_as('f4000000-0000-0000-0000-000000000001');
select pg_temp.check((select not pinned from public.fn_my_conversations() where id = (select id from pin_chat)),
  'pins are personal');
select pg_temp.as_owner();

insert into auth.users (id, email, raw_user_meta_data) values
  ('f4000000-0000-0000-0000-000000000003', 'pin-out@test', '{"full_name":"Pin Out"}');
select pg_temp.act_as('f4000000-0000-0000-0000-000000000003');
select pg_temp.fails($$select public.fn_pin_conversation((select id from pin_chat), true)$$,
  'NOT_FOUND', 'cannot pin a chat you are not in');
select pg_temp.as_owner();

rollback;
