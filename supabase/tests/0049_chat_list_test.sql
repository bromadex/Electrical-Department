-- Behaviour checks for 0049_chat_list. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('fe490000-0000-0000-0000-0000000000a1', 'LST', 'List site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('fe490000-0000-0000-0000-000000000001', 'lst-a@test', '{"full_name":"LST Anna"}'),
  ('fe490000-0000-0000-0000-000000000002', 'lst-b@test', '{"full_name":"LST Ben"}'),
  ('fe490000-0000-0000-0000-000000000003', 'lst-c@test', '{"full_name":"LST Cara"}');
insert into public.user_roles (user_id, role_id, site_id)
select u, r.id, 'fe490000-0000-0000-0000-0000000000a1'::uuid
from public.roles r, unnest(array['fe490000-0000-0000-0000-000000000001'::uuid,
  'fe490000-0000-0000-0000-000000000002'::uuid, 'fe490000-0000-0000-0000-000000000003'::uuid]) u
where r.name = 'Technician';
-- Anna is a supervisor too (creates groups).
insert into public.user_roles (user_id, role_id, site_id)
select 'fe490000-0000-0000-0000-000000000001'::uuid, id, 'fe490000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Supervisor';

select pg_temp.act_as('fe490000-0000-0000-0000-000000000001');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
insert into ids values ('group', (public.fn_create_group(gen_random_uuid(), 'List site group',
  'fe490000-0000-0000-0000-0000000000a1', array['fe490000-0000-0000-0000-000000000002'::uuid,
  'fe490000-0000-0000-0000-000000000003'::uuid])).id);
insert into ids values ('direct', public.fn_open_direct(gen_random_uuid(), 'fe490000-0000-0000-0000-000000000002'));
select pg_temp.as_owner();
update public.conversation_members set joined_at = now() - interval '1 hour'
where conversation_id in (select v from ids);

select pg_temp.act_as('fe490000-0000-0000-0000-000000000002');
select public.fn_favourite_conversation((select v from ids where k = 'group'), true);
select pg_temp.check((select favourite from public.fn_my_conversations() where id = (select v from ids where k = 'group')), 'Ben adds the group to favourites');
select pg_temp.act_as('fe490000-0000-0000-0000-000000000003');
select pg_temp.check((select not favourite from public.fn_my_conversations() where id = (select v from ids where k = 'group')), 'favourites are per person');
select pg_temp.act_as('fe490000-0000-0000-0000-000000000002');
select public.fn_favourite_conversation((select v from ids where k = 'group'), false);
select pg_temp.check((select not favourite from public.fn_my_conversations() where id = (select v from ids where k = 'group')), 'and removes it');

-- The last message: author, kind and (for your own) its tick.
select pg_temp.act_as('fe490000-0000-0000-0000-000000000001');
select public.fn_send_message('fe490000-0000-0000-0000-0000000000e1', (select v from ids where k = 'group'), 'text', 'Hi @Ben', null, null, null, null,
  null, null, array['fe490000-0000-0000-0000-000000000002'::uuid]);
select pg_temp.check((select last_author_id = 'fe490000-0000-0000-0000-000000000001' and last_kind = 'text' and last_tick = 'sent'
  from public.fn_my_conversations() where id = (select v from ids where k = 'group')), 'Anna''s last message: one tick');
select pg_temp.act_as('fe490000-0000-0000-0000-000000000002');
select pg_temp.check((select mentions = 1 and last_tick is null from public.fn_my_conversations() where id = (select v from ids where k = 'group')),
  'Ben sees an @ mention and no tick on someone else''s message');
select public.fn_mark_delivered(null);
select pg_temp.act_as('fe490000-0000-0000-0000-000000000003');
select public.fn_mark_delivered(null);
select pg_temp.act_as('fe490000-0000-0000-0000-000000000001');
select pg_temp.check((select last_tick = 'delivered' from public.fn_my_conversations() where id = (select v from ids where k = 'group')),
  'on everyone''s phone: two grey ticks');
select pg_temp.act_as('fe490000-0000-0000-0000-000000000002');
select public.fn_mark_conversation_read((select v from ids where k = 'group'));
select pg_temp.check((select mentions = 0 from public.fn_my_conversations() where id = (select v from ids where k = 'group')), 'opening the chat clears the @');
select pg_temp.act_as('fe490000-0000-0000-0000-000000000003');
select public.fn_mark_conversation_read((select v from ids where k = 'group'));
select pg_temp.act_as('fe490000-0000-0000-0000-000000000001');
select pg_temp.check((select last_tick = 'read' from public.fn_my_conversations() where id = (select v from ids where k = 'group')),
  'read by everyone: blue ticks');
select pg_temp.fails($$select public.fn_favourite_conversation(gen_random_uuid(), true)$$, 'NOT_FOUND',
  'only your own chats can be favourites');
select pg_temp.as_owner();

rollback;
