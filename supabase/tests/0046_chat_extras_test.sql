-- Behaviour checks for 0046_chat_extras. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('fe460000-0000-0000-0000-0000000000a1', 'XTR', 'Extras site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('fe460000-0000-0000-0000-000000000001', 'xtr-a@test', '{"full_name":"XTR Anna"}'),
  ('fe460000-0000-0000-0000-000000000002', 'xtr-b@test', '{"full_name":"XTR Ben"}'),
  ('fe460000-0000-0000-0000-000000000003', 'xtr-c@test', '{"full_name":"XTR Cara"}');
insert into public.user_roles (user_id, role_id, site_id)
select u, r.id, 'fe460000-0000-0000-0000-0000000000a1'::uuid
from public.roles r, unnest(array['fe460000-0000-0000-0000-000000000001'::uuid,
  'fe460000-0000-0000-0000-000000000002'::uuid, 'fe460000-0000-0000-0000-000000000003'::uuid]) u
where r.name = 'Technician';
-- Anna is a supervisor too (creates groups).
insert into public.user_roles (user_id, role_id, site_id)
select 'fe460000-0000-0000-0000-000000000001'::uuid, id, 'fe460000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Supervisor';

select pg_temp.act_as('fe460000-0000-0000-0000-000000000001');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
insert into ids values ('group', (public.fn_create_group(gen_random_uuid(), 'Extras site group',
  'fe460000-0000-0000-0000-0000000000a1', array['fe460000-0000-0000-0000-000000000002'::uuid,
  'fe460000-0000-0000-0000-000000000003'::uuid])).id);
insert into ids values ('direct', public.fn_open_direct(gen_random_uuid(), 'fe460000-0000-0000-0000-000000000002'));
select pg_temp.as_owner();
update public.conversation_members set joined_at = now() - interval '1 hour'
where conversation_id in (select v from ids);

-- Video messages are a message kind, with the file in the chat's folder.
select pg_temp.act_as('fe460000-0000-0000-0000-000000000001');
select public.fn_send_message('fe460000-0000-0000-0000-0000000000e1', (select v from ids where k = 'group'), 'video', 'Panel walk-round',
  (select v from ids where k = 'group')::text || '/fe460000-0000-0000-0000-0000000000e1/v.mp4', 'v.mp4', 5000, 42000, null, null, null);
select pg_temp.check((select kind = 'video' and duration_ms = 42000 from public.messages
  where id = 'fe460000-0000-0000-0000-0000000000e1'), 'a video message is saved');
select pg_temp.check((select last_message_preview like '%🎥 Video%' from public.conversations where id = (select v from ids where k = 'group')),
  'the chat list says Video');
select pg_temp.fails($$select public.fn_send_message(gen_random_uuid(), (select v from ids where k = 'group'),
  'video', null, 'elsewhere/x/v.mp4', 'v.mp4', 1, 1, null, null, null)$$, 'INVALID',
  'a video must be in the chat''s folder');

-- Edit: your own text, within 15 minutes.
select public.fn_send_message('fe460000-0000-0000-0000-0000000000e2', (select v from ids where k = 'group'), 'text', 'Isolator 3 open',
  null, null, null, null, null, null, null);
select public.fn_edit_message('fe460000-0000-0000-0000-0000000000e2', 'Isolator 4 open');
select pg_temp.check((select body = 'Isolator 4 open' and edited_at is not null from public.messages
  where id = 'fe460000-0000-0000-0000-0000000000e2'), 'your own text message can be edited (shows edited)');
select pg_temp.check((select last_message_preview like '%Isolator 4 open' from public.conversations
  where id = (select v from ids where k = 'group')), 'the chat list shows the edited text');
select pg_temp.fails($$select public.fn_edit_message('fe460000-0000-0000-0000-0000000000e1', 'x')$$, 'INVALID',
  'only text messages can be edited');
select pg_temp.fails($$select public.fn_edit_message('fe460000-0000-0000-0000-0000000000e2', '  ')$$, 'INVALID',
  'an edit cannot be empty');
select pg_temp.act_as('fe460000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_edit_message('fe460000-0000-0000-0000-0000000000e2', 'mine now')$$,
  'NOT_FOUND', 'nobody edits someone else''s message');
select pg_temp.as_owner();
update public.messages set created_at = now() - interval '20 minutes'
where id = 'fe460000-0000-0000-0000-0000000000e2';
select pg_temp.act_as('fe460000-0000-0000-0000-000000000001');
select pg_temp.fails($$select public.fn_edit_message('fe460000-0000-0000-0000-0000000000e2', 'late')$$, 'INVALID',
  'after 15 minutes it cannot be edited');

-- Star: per person.
select pg_temp.act_as('fe460000-0000-0000-0000-000000000002');
select public.fn_star_message('fe460000-0000-0000-0000-0000000000e1', true);
select public.fn_star_message('fe460000-0000-0000-0000-0000000000e1', true);
select pg_temp.check((select count(*) = 1 from public.message_stars), 'Ben stars a message (once)');
select pg_temp.act_as('fe460000-0000-0000-0000-000000000003');
select pg_temp.check((select count(*) = 0 from public.message_stars), 'others do not see Ben''s stars');
select pg_temp.act_as('fe460000-0000-0000-0000-000000000002');
select public.fn_star_message('fe460000-0000-0000-0000-0000000000e1', false);
select pg_temp.check((select count(*) = 0 from public.message_stars), 'and unstars it');
select pg_temp.fails($$insert into public.message_stars (message_id, conversation_id, user_id)
  values ('fe460000-0000-0000-0000-0000000000e1', (select v from ids where k = 'group'), 'fe460000-0000-0000-0000-000000000002')$$,
  '', 'stars cannot be written directly');

-- Mute and archive.
select public.fn_mute_conversation((select v from ids where k = 'group'), now() + interval '8 hours');
select pg_temp.check((select muted_until > now() from public.fn_my_conversations() where id = (select v from ids where k = 'group')),
  'Ben mutes the group for 8 hours');
select public.fn_mute_conversation((select v from ids where k = 'group'), 'infinity');
select pg_temp.check((select muted_until = 'infinity' from public.fn_my_conversations() where id = (select v from ids where k = 'group')),
  'or always');
select public.fn_mute_conversation((select v from ids where k = 'group'), null);
select pg_temp.check((select muted_until is null from public.fn_my_conversations() where id = (select v from ids where k = 'group')),
  'and unmutes it');
select public.fn_archive_conversation((select v from ids where k = 'group'), true);
select pg_temp.check((select archived from public.fn_my_conversations() where id = (select v from ids where k = 'group')),
  'Ben archives the group');
-- (Archived a minute ago: inside one test transaction "now" never moves.)
select pg_temp.as_owner();
update public.conversation_members set archived_at = now() - interval '1 minute'
where user_id = 'fe460000-0000-0000-0000-000000000002' and conversation_id = (select v from ids where k = 'group');
select pg_temp.act_as('fe460000-0000-0000-0000-000000000001');
select public.fn_send_message(gen_random_uuid(), (select v from ids where k = 'group'), 'text', 'Shift change at 6', null, null, null, null,
  null, null, null);
select pg_temp.act_as('fe460000-0000-0000-0000-000000000002');
select pg_temp.check((select not archived from public.fn_my_conversations() where id = (select v from ids where k = 'group')),
  'a new message brings it back out of the archive');

-- Last seen.
select public.fn_seen();
select pg_temp.check((select last_seen_at > now() - interval '1 minute' from public.profiles where id = 'fe460000-0000-0000-0000-000000000002'),
  'leaving the app records last seen');

-- Group info: owners and supervisors only, picture in the chat's folder.
select pg_temp.fails($$select public.fn_update_group_info((select v from ids where k = 'group'), 'Hi', null)$$,
  'NOT_ALLOWED', 'a member cannot change the group''s info');
select pg_temp.act_as('fe460000-0000-0000-0000-000000000001');
select public.fn_update_group_info((select v from ids where k = 'group'), 'Kamativi shift team', (select v from ids where k = 'group')::text || '/group/p.jpg');
select pg_temp.check((select description = 'Kamativi shift team' and photo_path like '%/group/p.jpg'
  from public.fn_my_conversations() where id = (select v from ids where k = 'group')), 'the supervisor sets the description and picture');
select pg_temp.fails($$select public.fn_update_group_info((select v from ids where k = 'group'), null, 'x/p.jpg')$$,
  'INVALID', 'the picture must be in the chat''s folder');
select pg_temp.fails($$select public.fn_update_group_info((select v from ids where k = 'direct'), 'x', null)$$,
  'INVALID', 'direct chats have no group info');

-- Forwarding a video copies it as a video.
select public.fn_forward_message('fe460000-0000-0000-0000-0000000000f1', 'fe460000-0000-0000-0000-0000000000e1', (select v from ids where k = 'direct'),
  (select v from ids where k = 'direct')::text || '/fe460000-0000-0000-0000-0000000000f1/v.mp4');
select pg_temp.check((select kind = 'video' and forwarded from public.messages
  where id = 'fe460000-0000-0000-0000-0000000000f1'), 'a forwarded video stays a video');
select pg_temp.as_owner();

rollback;
