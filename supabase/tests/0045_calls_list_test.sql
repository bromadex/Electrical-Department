-- Behaviour checks for 0045_calls_list. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('fe450000-0000-0000-0000-0000000000a1', 'CLL', 'Calls site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('fe450000-0000-0000-0000-000000000001', 'call-a@test', '{"full_name":"Call Anna"}'),
  ('fe450000-0000-0000-0000-000000000002', 'call-b@test', '{"full_name":"Call Ben"}'),
  ('fe450000-0000-0000-0000-000000000003', 'call-c@test', '{"full_name":"Call Cara"}');
insert into public.user_roles (user_id, role_id, site_id)
select u, r.id, 'fe450000-0000-0000-0000-0000000000a1'::uuid
from public.roles r, unnest(array['fe450000-0000-0000-0000-000000000001'::uuid,
  'fe450000-0000-0000-0000-000000000002'::uuid, 'fe450000-0000-0000-0000-000000000003'::uuid]) u
where r.name = 'Technician';
insert into public.user_roles (user_id, role_id, site_id)
select 'fe450000-0000-0000-0000-000000000001'::uuid, id, 'fe450000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Supervisor';

select pg_temp.act_as('fe450000-0000-0000-0000-000000000001');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
insert into ids values ('group', (public.fn_create_group(gen_random_uuid(), 'Call group',
  'fe450000-0000-0000-0000-0000000000a1', array['fe450000-0000-0000-0000-000000000002'::uuid,
  'fe450000-0000-0000-0000-000000000003'::uuid])).id);
insert into ids values ('direct', public.fn_open_direct(gen_random_uuid(), 'fe450000-0000-0000-0000-000000000002'));
select pg_temp.as_owner();
update public.conversation_members set joined_at = now() - interval '1 hour';
select pg_temp.act_as('fe450000-0000-0000-0000-000000000001');

-- Anna calls the group; Ben joins, Cara does not.
insert into ids values ('gcall', ((public.fn_start_call((select v from ids where k = 'group'), false))->>'call_id')::uuid);
select pg_temp.act_as('fe450000-0000-0000-0000-000000000002');
select public.fn_start_call((select v from ids where k = 'group'), false);

select pg_temp.check((select live and direction = 'incoming' and title = 'Call group' and not is_direct
  from public.fn_my_calls() where call_id = (select v from ids where k = 'gcall')),
  'Ben joined: incoming, live');
select pg_temp.act_as('fe450000-0000-0000-0000-000000000001');
select pg_temp.check((select direction = 'outgoing' from public.fn_my_calls()
  where call_id = (select v from ids where k = 'gcall')), 'Anna started it: outgoing');
select pg_temp.act_as('fe450000-0000-0000-0000-000000000003');
select pg_temp.check((select direction = 'missed' from public.fn_my_calls()
  where call_id = (select v from ids where k = 'gcall')), 'Cara did not join: missed');
select pg_temp.check(public.fn_missed_call_count() = 0, 'a live call is not counted as missed yet');

-- Everyone leaves; the call lasted.
select pg_temp.as_owner();
update public.calls set answered_at = now() - interval '3 minutes' where id = (select v from ids where k = 'gcall');
update public.call_participants set left_at = now() where call_id = (select v from ids where k = 'gcall');
update public.calls set ended_at = now() where id = (select v from ids where k = 'gcall');
select pg_temp.act_as('fe450000-0000-0000-0000-000000000003');
select pg_temp.check((select not live and seconds between 170 and 190 from public.fn_my_calls()
  where call_id = (select v from ids where k = 'gcall')), 'an ended call shows how long it lasted');
select pg_temp.check(public.fn_missed_call_count() = 1, 'one missed call on Cara''s badge');
select public.fn_calls_seen();
select pg_temp.check(public.fn_missed_call_count() = 0, 'opening the calls list clears the badge');
select pg_temp.check((select count(*) = 1 from public.call_log_seen), 'she sees her own seen time');
select pg_temp.fails($$insert into public.call_log_seen (user_id) values ('fe450000-0000-0000-0000-000000000003')$$,
  '', 'the seen time cannot be written directly');

-- A direct call is named after the other person; others' chats are not listed.
select pg_temp.act_as('fe450000-0000-0000-0000-000000000001');
insert into ids values ('dcall', ((public.fn_start_call((select v from ids where k = 'direct'), true))->>'call_id')::uuid);
select pg_temp.check((select is_direct and video and title = 'Call Ben' and seconds = 0
  and other_user_id = 'fe450000-0000-0000-0000-000000000002'
  from public.fn_my_calls() where call_id = (select v from ids where k = 'dcall')),
  'a direct video call is named after the other person, not answered yet');
select pg_temp.act_as('fe450000-0000-0000-0000-000000000003');
select pg_temp.check((select count(*) = 0 from public.fn_my_calls()
  where call_id = (select v from ids where k = 'dcall')), 'Cara does not see a call in a chat she is not in');
select pg_temp.as_owner();

rollback;
