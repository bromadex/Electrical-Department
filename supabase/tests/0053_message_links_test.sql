-- Behaviour checks for 0053_message_links. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('fe530000-0000-0000-0000-0000000000a1', 'MLK', 'Links site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('fe530000-0000-0000-0000-000000000001', 'mlk-a@test', '{"full_name":"MLK Anna"}'),
  ('fe530000-0000-0000-0000-000000000002', 'mlk-b@test', '{"full_name":"MLK Ben"}'),
  ('fe530000-0000-0000-0000-000000000003', 'mlk-c@test', '{"full_name":"MLK Cara"}');
insert into public.user_roles (user_id, role_id, site_id)
select u, r.id, 'fe530000-0000-0000-0000-0000000000a1'::uuid
from public.roles r, unnest(array['fe530000-0000-0000-0000-000000000001'::uuid,
  'fe530000-0000-0000-0000-000000000002'::uuid, 'fe530000-0000-0000-0000-000000000003'::uuid]) u
where r.name = 'Technician';
insert into public.user_roles (user_id, role_id, site_id)
select 'fe530000-0000-0000-0000-000000000001'::uuid, id, 'fe530000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Supervisor';
insert into public.documents (id, site_id, code, title, category) values
  ('fe530000-0000-0000-0000-0000000000d1', 'fe530000-0000-0000-0000-0000000000a1', 'S-9001', 'LOTO procedure', 'sop');

create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
select pg_temp.act_as('fe530000-0000-0000-0000-000000000001');
-- A group with Ben only; Cara is not in it.
insert into ids values ('group', (public.fn_create_group(gen_random_uuid(), 'Links group',
  'fe530000-0000-0000-0000-0000000000a1', array['fe530000-0000-0000-0000-000000000002'::uuid])).id);
insert into ids values ('other', (public.fn_create_group(gen_random_uuid(), 'Other group',
  'fe530000-0000-0000-0000-0000000000a1', array['fe530000-0000-0000-0000-000000000003'::uuid])).id);
select pg_temp.as_owner();
update public.conversation_members set joined_at = now() - interval '1 hour'
where conversation_id in (select v from ids);

-- Tagging a file in a message.
select pg_temp.act_as('fe530000-0000-0000-0000-000000000001');
select public.fn_send_message('fe530000-0000-0000-0000-0000000000e1', (select v from ids where k = 'group'), 'text',
  'Read #LOTO procedure first', null, null, null, null, null, null, null,
  '[{"label":"#LOTO procedure","link":"doc:fe530000-0000-0000-0000-0000000000d1"},
    {"label":"#LOTO procedure","link":"doc:fe530000-0000-0000-0000-0000000000d1"}]');
select pg_temp.check((select links = '[{"label":"#LOTO procedure","link":"doc:fe530000-0000-0000-0000-0000000000d1"}]'::jsonb
  from public.messages where id = 'fe530000-0000-0000-0000-0000000000e1'), 'a message keeps its tags, each once');
select public.fn_send_message('fe530000-0000-0000-0000-0000000000e2', (select v from ids where k = 'group'), 'text',
  'No tags', null, null, null, null, null, null, null);
select pg_temp.check((select links = '[]'::jsonb from public.messages where id = 'fe530000-0000-0000-0000-0000000000e2'),
  'older apps that send no tags still work');
select pg_temp.fails($$select public.fn_send_message(gen_random_uuid(), (select v from ids where k = 'group'), 'text', 'x',
  null, null, null, null, null, null, null, '[{"label":"#bad","link":"http://evil"}]')$$, 'INVALID', 'a tag must be a record link');
select pg_temp.fails($$select public.fn_send_message(gen_random_uuid(), (select v from ids where k = 'group'), 'text', 'x',
  null, null, null, null, null, null, null, '[{"label":"","link":"doc:fe530000-0000-0000-0000-0000000000d1"}]')$$, 'INVALID',
  'a tag needs a name');
select pg_temp.fails(format($$select public.fn_send_message(gen_random_uuid(), (select v from ids where k = 'group'), 'text', 'x',
  null, null, null, null, null, null, null, %L)$$,
  (select jsonb_agg(jsonb_build_object('label', '#t' || g, 'link', 'doc:' || gen_random_uuid())) from generate_series(1, 11) g)),
  'INVALID', 'up to 10 tags');

-- Forwarding keeps the tags.
select public.fn_forward_message('fe530000-0000-0000-0000-0000000000e3', 'fe530000-0000-0000-0000-0000000000e1',
  (select v from ids where k = 'other'), null);
select pg_temp.check((select jsonb_array_length(links) = 1 and forwarded from public.messages
  where id = 'fe530000-0000-0000-0000-0000000000e3'), 'a forwarded message keeps its tags');

-- Where a document is tagged: only chats the caller is in.
select pg_temp.check((select count(*) = 2 from public.fn_document_mentions('fe530000-0000-0000-0000-0000000000d1')),
  'Anna sees both chats it is tagged in');
select pg_temp.act_as('fe530000-0000-0000-0000-000000000002');
select pg_temp.check((select count(*) = 1 and min(conversation_title) = 'Links group'
  from public.fn_document_mentions('fe530000-0000-0000-0000-0000000000d1')), 'Ben sees only his chat');
select pg_temp.act_as('fe530000-0000-0000-0000-000000000003');
select pg_temp.check((select count(*) = 1 and min(conversation_title) = 'Other group'
  from public.fn_document_mentions('fe530000-0000-0000-0000-0000000000d1')), 'Cara sees only hers');
do $$ begin
  update public.messages set links = '[]' where id = 'fe530000-0000-0000-0000-0000000000e3';
exception when others then null;
end $$;
select pg_temp.act_as('fe530000-0000-0000-0000-000000000001');
select pg_temp.check((select jsonb_array_length(links) = 1 from public.messages
  where id = 'fe530000-0000-0000-0000-0000000000e3'), 'tags cannot be changed directly');
select pg_temp.as_owner();

rollback;
