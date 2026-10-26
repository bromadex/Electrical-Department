-- Behaviour checks for 0011_chat. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('f0000000-0000-0000-0000-0000000000a1', 'CHT', 'Chat site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('f0000000-0000-0000-0000-000000000001', 'ch-sup@test', '{"full_name":"Ch Sup"}'),
  ('f0000000-0000-0000-0000-000000000002', 'ch-tech@test', '{"full_name":"Ch Tech"}'),
  ('f0000000-0000-0000-0000-000000000003', 'ch-req@test', '{"full_name":"Ch Requester"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'f0000000-0000-0000-0000-000000000001'::uuid, id, 'f0000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Supervisor'
union all
select 'f0000000-0000-0000-0000-000000000002'::uuid, id, 'f0000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Technician'
union all
select 'f0000000-0000-0000-0000-000000000003'::uuid, id, 'f0000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Requester';

-- Default groups follow roles.
select pg_temp.check(exists (select 1 from public.conversations where is_default and site_id = 'f0000000-0000-0000-0000-0000000000a1'),
  'a new site gets its own group');
select pg_temp.act_as('f0000000-0000-0000-0000-000000000002');
select pg_temp.check((select count(*) from public.fn_my_conversations() where is_default) = 2,
  'technicians are in the department group and their site group');
select pg_temp.act_as('f0000000-0000-0000-0000-000000000003');
select pg_temp.check(not exists (select 1 from public.fn_my_conversations()), 'requesters are not in chats');
select pg_temp.as_owner();

-- Sending, unread and the one-per-chat notification.
-- (All rows share one transaction time, so start the supervisor's read mark earlier.)
update public.conversation_members set last_read_at = now() - interval '1 hour'
where user_id = 'f0000000-0000-0000-0000-000000000001';
select pg_temp.act_as('f0000000-0000-0000-0000-000000000002');
select public.fn_send_message('f0000000-0000-0000-0000-0000000000c1',
  (select id from public.conversations where is_default and site_id = 'f0000000-0000-0000-0000-0000000000a1'),
  'text', 'Breaker on DB3 tripped again', null, null, null, null, null, null, null);
select public.fn_send_message('f0000000-0000-0000-0000-0000000000c1',
  (select id from public.conversations where is_default and site_id = 'f0000000-0000-0000-0000-0000000000a1'),
  'text', 'Breaker on DB3 tripped again', null, null, null, null, null, null, null);
select public.fn_send_message('f0000000-0000-0000-0000-0000000000c2',
  (select id from public.conversations where is_default and site_id = 'f0000000-0000-0000-0000-0000000000a1'),
  'text', 'Resetting it now', null, null, null, null, null, null, null);
select pg_temp.fails($$select public.fn_send_message(gen_random_uuid(),
  (select id from public.conversations where is_default and site_id = 'f0000000-0000-0000-0000-0000000000a1'),
  'text', '   ', null, null, null, null, null, null, null)$$, 'INVALID', 'empty messages are refused');
select pg_temp.as_owner();
select pg_temp.check((select count(*) from public.messages where conversation_id =
  (select id from public.conversations where is_default and site_id = 'f0000000-0000-0000-0000-0000000000a1')) = 2,
  'a resent message is stored once');
select pg_temp.check((select count(*) from public.notifications
  where user_id = 'f0000000-0000-0000-0000-000000000001' and type = 'chat') = 1,
  'the supervisor gets one chat notification for the burst');

select pg_temp.act_as('f0000000-0000-0000-0000-000000000001');
select pg_temp.check((select unread from public.fn_my_conversations()
  where site_id = 'f0000000-0000-0000-0000-0000000000a1') = 2, 'two unread for the supervisor');
select public.fn_mark_conversation_read((select id from public.conversations where is_default and site_id = 'f0000000-0000-0000-0000-0000000000a1'));
select pg_temp.check((select unread from public.fn_my_conversations()
  where site_id = 'f0000000-0000-0000-0000-0000000000a1') = 0, 'opening the chat clears unread');
select pg_temp.check(not exists (select 1 from public.notifications
  where user_id = 'f0000000-0000-0000-0000-000000000001' and type = 'chat' and read_at is null),
  'and its notification');
select pg_temp.check(public.fn_react('f0000000-0000-0000-0000-0000000000c1', '👍'), 'reaction added');
select pg_temp.check(not public.fn_react('f0000000-0000-0000-0000-0000000000c1', '👍'), 'reacting again removes it');

-- Direct chats and record tags.
select pg_temp.check(public.fn_open_direct('f0000000-0000-0000-0000-0000000000d1', 'f0000000-0000-0000-0000-000000000002')
  = public.fn_open_direct(gen_random_uuid(), 'f0000000-0000-0000-0000-000000000002'), 'one direct chat per pair');
select pg_temp.fails($$select public.fn_open_direct(gen_random_uuid(), 'f0000000-0000-0000-0000-000000000003')$$,
  'NOT_ALLOWED', 'no direct chat with people without chat');
select public.fn_register_job_card('f0000000-0000-0000-0000-0000000000e1', null,
  'f0000000-0000-0000-0000-0000000000a1', null, 'Workshop', now(), 'Ch Sup', null, null, null, null, null, null,
  'Replace DB3 breaker', 'Breaker on DB3 keeps tripping', 'minor', 'P3', null);
select pg_temp.check(exists (select 1 from public.fn_search_records('DB3')
  where link = 'jobcard:f0000000-0000-0000-0000-0000000000e1'), 'job cards can be tagged with #');
select public.fn_send_message(gen_random_uuid(), 'f0000000-0000-0000-0000-0000000000d1', 'record', 'Replace DB3 breaker',
  null, null, null, null, null, 'jobcard:f0000000-0000-0000-0000-0000000000e1', null);
select pg_temp.fails($$select public.fn_send_message(gen_random_uuid(), 'f0000000-0000-0000-0000-0000000000d1', 'record', 'x',
  null, null, null, null, null, 'evil:f0000000-0000-0000-0000-0000000000e1', null)$$, 'INVALID', 'unknown record links are refused');
select pg_temp.as_owner();

-- Outsiders.
select pg_temp.act_as('f0000000-0000-0000-0000-000000000003');
select pg_temp.check(not exists (select 1 from public.messages where conversation_id = 'f0000000-0000-0000-0000-0000000000d1'),
  'people outside a chat cannot read it');
select pg_temp.fails($$select public.fn_send_message(gen_random_uuid(), 'f0000000-0000-0000-0000-0000000000d1', 'text', 'hi',
  null, null, null, null, null, null, null)$$, 'NOT_FOUND', 'or write to it');
select pg_temp.as_owner();

rollback;
