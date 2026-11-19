-- Behaviour checks for 0055_chat_alerts. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('fe550000-0000-0000-0000-0000000000a1', 'CAL', 'Alerts site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('fe550000-0000-0000-0000-000000000001', 'cal-a@test', '{"full_name":"CAL Anna"}'),
  ('fe550000-0000-0000-0000-000000000002', 'cal-b@test', '{"full_name":"CAL Ben"}'),
  ('fe550000-0000-0000-0000-000000000003', 'cal-c@test', '{"full_name":"CAL Cara"}');
insert into public.user_roles (user_id, role_id, site_id)
select u, r.id, 'fe550000-0000-0000-0000-0000000000a1'::uuid
from public.roles r, unnest(array['fe550000-0000-0000-0000-000000000001'::uuid,
  'fe550000-0000-0000-0000-000000000002'::uuid, 'fe550000-0000-0000-0000-000000000003'::uuid]) u
where r.name = 'Technician';
insert into public.user_roles (user_id, role_id, site_id)
select 'fe550000-0000-0000-0000-000000000001'::uuid, id, 'fe550000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Supervisor';

create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
select pg_temp.act_as('fe550000-0000-0000-0000-000000000001');
insert into ids values ('group', (public.fn_create_group(gen_random_uuid(), 'Alerts group',
  'fe550000-0000-0000-0000-0000000000a1', array['fe550000-0000-0000-0000-000000000002'::uuid,
  'fe550000-0000-0000-0000-000000000003'::uuid])).id);
select pg_temp.as_owner();
update public.conversation_members set joined_at = now() - interval '1 hour'
where conversation_id in (select v from ids);
-- Cara muted the group.
update public.conversation_members set muted_until = 'infinity'
where conversation_id = (select v from ids where k = 'group') and user_id = 'fe550000-0000-0000-0000-000000000003';
delete from public.notifications where user_id in ('fe550000-0000-0000-0000-000000000002', 'fe550000-0000-0000-0000-000000000003');

select pg_temp.act_as('fe550000-0000-0000-0000-000000000001');
select public.fn_send_message(gen_random_uuid(), (select v from ids where k = 'group'), 'text', 'First', null, null, null, null, null, null, null);
select public.fn_send_message(gen_random_uuid(), (select v from ids where k = 'group'), 'text', 'Second', null, null, null, null, null, null, null);
select pg_temp.as_owner();
select pg_temp.check((select count(*) = 1 and min(body) like '%Second' from public.notifications
  where user_id = 'fe550000-0000-0000-0000-000000000002' and type = 'chat' and read_at is null),
  'every message alerts again: one unread alert per chat, with the newest message');
select pg_temp.check((select count(*) = 0 from public.notifications
  where user_id = 'fe550000-0000-0000-0000-000000000003' and type = 'chat'),
  'a muted chat sends no alerts');

-- Swiping the alert away used to silence the chat; reading it in the app
-- or not, the next message alerts.
select pg_temp.act_as('fe550000-0000-0000-0000-000000000001');
select public.fn_send_message(gen_random_uuid(), (select v from ids where k = 'group'), 'text', 'Third', null, null, null, null, null, null,
  array['fe550000-0000-0000-0000-000000000003'::uuid]);
select pg_temp.as_owner();
select pg_temp.check((select min(body) like '%Third' from public.notifications
  where user_id = 'fe550000-0000-0000-0000-000000000002' and type = 'chat' and read_at is null),
  'the next message replaces it again');
select pg_temp.check((select count(*) = 1 from public.notifications
  where user_id = 'fe550000-0000-0000-0000-000000000003' and type = 'mentioned'),
  'an @mention still reaches someone who muted the chat');
select pg_temp.check((select count(*) = 0 from public.notifications
  where user_id = 'fe550000-0000-0000-0000-000000000001' and type in ('chat', 'mentioned')),
  'the sender gets no alert');

-- Opening the chat marks it read; read alerts are kept (history), unread replaced.
select pg_temp.act_as('fe550000-0000-0000-0000-000000000002');
select public.fn_mark_conversation_read((select v from ids where k = 'group'));
select pg_temp.act_as('fe550000-0000-0000-0000-000000000001');
select public.fn_send_message(gen_random_uuid(), (select v from ids where k = 'group'), 'text', 'Fourth', null, null, null, null, null, null, null);
select pg_temp.as_owner();
select pg_temp.check((select count(*) filter (where read_at is null) = 1 and count(*) filter (where read_at is not null) = 1
  from public.notifications where user_id = 'fe550000-0000-0000-0000-000000000002' and type = 'chat'),
  'after reading, a new message alerts; the read one stays');

rollback;
