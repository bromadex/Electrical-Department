-- Behaviour checks for 0019_call_messages. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('f5000000-0000-0000-0000-0000000000a1', 'CMS', 'Call msg site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('f5000000-0000-0000-0000-000000000001', 'cm-sup@test', '{"full_name":"Cm Sup"}'),
  ('f5000000-0000-0000-0000-000000000002', 'cm-tech@test', '{"full_name":"Cm Tech"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'f5000000-0000-0000-0000-000000000001'::uuid, id, 'f5000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Supervisor'
union all
select 'f5000000-0000-0000-0000-000000000002'::uuid, id, 'f5000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Technician';

create temp table cm_chat as
  select id from public.conversations where is_default and site_id = 'f5000000-0000-0000-0000-0000000000a1';
grant select on cm_chat to authenticated;

update public.conversation_members set last_read_at = now() - interval '1 hour'
where conversation_id = (select id from cm_chat);
select pg_temp.act_as('f5000000-0000-0000-0000-000000000002');
select public.fn_start_call((select id from cm_chat));
select public.fn_start_call((select id from cm_chat));
select pg_temp.as_owner();
select pg_temp.check((select count(*) = 1 from public.messages
  where conversation_id = (select id from cm_chat) and kind = 'system'
    and body = 'Cm Tech started a call' and record_link = 'call:' || (select id from cm_chat)),
  'starting a call posts one row in the chat, not one per rejoin');

select pg_temp.act_as('f5000000-0000-0000-0000-000000000001');
select pg_temp.check((select unread = 1 and last_message_preview like '%started a call'
  from public.fn_my_conversations() where id = (select id from cm_chat)),
  'the others see it in their chat list as unread');
select pg_temp.act_as('f5000000-0000-0000-0000-000000000002');
select pg_temp.check((select unread = 0 from public.fn_my_conversations() where id = (select id from cm_chat)),
  'not unread for the caller');
select pg_temp.as_owner();

rollback;
