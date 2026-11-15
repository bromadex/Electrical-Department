-- Behaviour checks for 0044_chat_receipts_forward. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('fe440000-0000-0000-0000-0000000000a1', 'TIK', 'Tick site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('fe440000-0000-0000-0000-000000000001', 'tick-a@test', '{"full_name":"Tick Anna"}'),
  ('fe440000-0000-0000-0000-000000000002', 'tick-b@test', '{"full_name":"Tick Ben"}'),
  ('fe440000-0000-0000-0000-000000000003', 'tick-c@test', '{"full_name":"Tick Cara"}');
insert into public.user_roles (user_id, role_id, site_id)
select u, r.id, 'fe440000-0000-0000-0000-0000000000a1'::uuid
from public.roles r, unnest(array['fe440000-0000-0000-0000-000000000001'::uuid,
  'fe440000-0000-0000-0000-000000000002'::uuid, 'fe440000-0000-0000-0000-000000000003'::uuid]) u
where r.name = 'Technician';
-- Anna is a supervisor too (creates the group).
insert into public.user_roles (user_id, role_id, site_id)
select 'fe440000-0000-0000-0000-000000000001'::uuid, id, 'fe440000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Supervisor';

-- A group of three, a direct chat between Anna and Cara.
select pg_temp.act_as('fe440000-0000-0000-0000-000000000001');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
insert into ids values ('group', (public.fn_create_group(gen_random_uuid(), 'Tick group',
  'fe440000-0000-0000-0000-0000000000a1', array['fe440000-0000-0000-0000-000000000002'::uuid,
  'fe440000-0000-0000-0000-000000000003'::uuid])).id);
insert into ids values ('direct', public.fn_open_direct(gen_random_uuid(), 'fe440000-0000-0000-0000-000000000003'));
select pg_temp.as_owner();
-- Joined a moment before the messages.
update public.conversation_members set joined_at = now() - interval '1 minute'
where conversation_id = (select v from ids where k = 'group');
select pg_temp.act_as('fe440000-0000-0000-0000-000000000001');
select public.fn_send_message('fe440000-0000-0000-0000-0000000000e1', (select v from ids where k = 'group'),
  'text', 'Isolator 3 is open', null, null, null, null, null, null, null);
select public.fn_send_message('fe440000-0000-0000-0000-0000000000e2', (select v from ids where k = 'group'),
  'photo', 'Breaker tag', (select v from ids where k = 'group')::text || '/fe440000-0000-0000-0000-0000000000e2/p.jpg',
  'p.jpg', 1000, null, null, null, null);

select pg_temp.check((select recipients = 2 and delivered = 0 and read = 0 from public.fn_message_ticks(
  (select v from ids where k = 'group')) where message_id = 'fe440000-0000-0000-0000-0000000000e1'),
  'a new group message: two people should get it, nobody has yet (one tick)');

-- Ben's phone gets it; Cara opens the chat.
select pg_temp.act_as('fe440000-0000-0000-0000-000000000002');
select pg_temp.check((select public.fn_mark_delivered(null)) = 2, 'Ben''s phone marks both messages delivered');
select pg_temp.check((select public.fn_mark_delivered(null)) = 0, 'and only once');
select pg_temp.act_as('fe440000-0000-0000-0000-000000000003');
select public.fn_mark_conversation_read((select v from ids where k = 'group'));

select pg_temp.act_as('fe440000-0000-0000-0000-000000000001');
select pg_temp.check((select delivered = 2 and read = 1 from public.fn_message_ticks(
  (select v from ids where k = 'group')) where message_id = 'fe440000-0000-0000-0000-0000000000e1'),
  'delivered to both (two grey ticks), read by one');
select pg_temp.check((select count(*) = 2 and count(read_at) = 1 from public.fn_message_info(
  'fe440000-0000-0000-0000-0000000000e1')), 'message info lists both people, one read');

select pg_temp.act_as('fe440000-0000-0000-0000-000000000002');
select public.fn_mark_conversation_read((select v from ids where k = 'group'));
select pg_temp.act_as('fe440000-0000-0000-0000-000000000001');
select pg_temp.check((select read = 2 from public.fn_message_ticks(
  (select v from ids where k = 'group')) where message_id = 'fe440000-0000-0000-0000-0000000000e1'),
  'read by everyone (blue ticks)');
select pg_temp.check((select count(*) = 0 from public.fn_message_ticks((select v from ids where k = 'group'))
  where message_id not in ('fe440000-0000-0000-0000-0000000000e1', 'fe440000-0000-0000-0000-0000000000e2')),
  'ticks cover only the caller''s own messages');

-- Nobody writes receipts directly.
select pg_temp.fails($$insert into public.message_receipts (message_id, conversation_id, user_id)
  values ('fe440000-0000-0000-0000-0000000000e1', (select v from ids where k = 'group'),
  'fe440000-0000-0000-0000-000000000003')$$, '', 'receipts cannot be written directly');

-- A push reaching Cara's phone marks the direct chat delivered.
select public.fn_send_message('fe440000-0000-0000-0000-0000000000e3', (select v from ids where k = 'direct'),
  'text', 'Call me', null, null, null, null, null, null, null);
select pg_temp.as_owner();
select pg_temp.check((select public.fn_push_received(n.id) from public.notifications n
  where n.user_id = 'fe440000-0000-0000-0000-000000000003' and n.type = 'chat'
    and n.link = 'chat:' || (select v from ids where k = 'direct') limit 1),
  'a chat push reaching the phone counts');
select pg_temp.check((select delivered_at is not null and read_at is null from public.message_receipts
  where message_id = 'fe440000-0000-0000-0000-0000000000e3'), 'as delivered, not read');
select pg_temp.act_as('fe440000-0000-0000-0000-000000000003');
select pg_temp.fails($$select public.fn_push_received(gen_random_uuid())$$, '', 'the app cannot call it directly');

-- Delete for me.
select pg_temp.check((select public.fn_hide_messages(array['fe440000-0000-0000-0000-0000000000e1'::uuid])) = 1,
  'Cara hides a message for herself');
select pg_temp.check((select count(*) = 1 from public.message_hidden), 'she sees her own hidden list');
select pg_temp.act_as('fe440000-0000-0000-0000-000000000002');
select pg_temp.check((select count(*) = 0 from public.message_hidden), 'others do not see it');
select pg_temp.check((select count(*) = 1 from public.messages where id = 'fe440000-0000-0000-0000-0000000000e1'),
  'and still see the message');

-- Forward.
select pg_temp.act_as('fe440000-0000-0000-0000-000000000001');
select public.fn_forward_message('fe440000-0000-0000-0000-0000000000f1', 'fe440000-0000-0000-0000-0000000000e2',
  (select v from ids where k = 'direct'),
  (select v from ids where k = 'direct')::text || '/fe440000-0000-0000-0000-0000000000f1/p.jpg');
select pg_temp.check((select forwarded and kind = 'photo' and body = 'Breaker tag'
  and attachment_path like (select v from ids where k = 'direct')::text || '/%'
  from public.messages where id = 'fe440000-0000-0000-0000-0000000000f1'),
  'a forwarded photo keeps its caption, uses the copied file and says forwarded');
select pg_temp.fails($$select public.fn_forward_message(gen_random_uuid(), 'fe440000-0000-0000-0000-0000000000e2',
  (select v from ids where k = 'direct'), 'elsewhere/x/p.jpg')$$, 'INVALID',
  'the copied file must be in the target chat''s folder');
select pg_temp.act_as('fe440000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_forward_message(gen_random_uuid(), 'fe440000-0000-0000-0000-0000000000e3',
  (select v from ids where k = 'group'), null)$$, 'NOT_FOUND',
  'a message from a chat you are not in cannot be forwarded');
select pg_temp.as_owner();

rollback;
