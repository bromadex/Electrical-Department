-- Behaviour checks for 0056_call_invites. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('fe560000-0000-0000-0000-0000000000a1', 'CIN', 'Invite site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('fe560000-0000-0000-0000-000000000001', 'cin-a@test', '{"full_name":"CIN Anna"}'),
  ('fe560000-0000-0000-0000-000000000002', 'cin-b@test', '{"full_name":"CIN Ben"}'),
  ('fe560000-0000-0000-0000-000000000003', 'cin-c@test', '{"full_name":"CIN Cara"}');
insert into public.user_roles (user_id, role_id, site_id)
select u, r.id, 'fe560000-0000-0000-0000-0000000000a1'::uuid
from public.roles r, unnest(array['fe560000-0000-0000-0000-000000000001'::uuid,
  'fe560000-0000-0000-0000-000000000002'::uuid, 'fe560000-0000-0000-0000-000000000003'::uuid]) u
where r.name = 'Technician';
insert into public.user_roles (user_id, role_id, site_id)
select 'fe560000-0000-0000-0000-000000000001'::uuid, id, 'fe560000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Supervisor';

create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
select pg_temp.act_as('fe560000-0000-0000-0000-000000000001');
insert into ids values ('direct', public.fn_open_direct(gen_random_uuid(), 'fe560000-0000-0000-0000-000000000002'));
insert into ids values ('group', (public.fn_create_group(gen_random_uuid(), 'Other group',
  'fe560000-0000-0000-0000-0000000000a1', array['fe560000-0000-0000-0000-000000000002'::uuid])).id);
select public.fn_send_message(gen_random_uuid(), (select v from ids where k = 'direct'), 'text', 'Private', null, null, null, null, null, null, null);
-- Anna calls Ben, and has another call in a group Cara is not in.
select public.fn_start_call((select v from ids where k = 'direct'), false);
select public.fn_start_call((select v from ids where k = 'group'), false);
select pg_temp.as_owner();

select pg_temp.act_as('fe560000-0000-0000-0000-000000000003');
select pg_temp.fails($$select public.fn_start_call((select v from ids where k = 'direct'), false)$$,
  'NOT_FOUND', 'someone not in the chat cannot join its call');

select pg_temp.act_as('fe560000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_call_invite((select v from ids where k = 'direct'), array['fe560000-0000-0000-0000-000000000003'::uuid])$$,
  'INVALID', 'only someone in the call can add people');

select pg_temp.act_as('fe560000-0000-0000-0000-000000000001');
select pg_temp.check(public.fn_call_invite((select v from ids where k = 'direct'),
  array['fe560000-0000-0000-0000-000000000003'::uuid, 'fe560000-0000-0000-0000-000000000001'::uuid]) = 1,
  'Anna adds Cara to her one-to-one call (not herself)');
select pg_temp.as_owner();
select pg_temp.check((select count(*) = 1 from public.notifications
  where user_id = 'fe560000-0000-0000-0000-000000000003' and type = 'call'
    and link = 'call:' || (select v from ids where k = 'direct')), 'Cara''s phone rings');

select pg_temp.act_as('fe560000-0000-0000-0000-000000000003');
select pg_temp.check((select count(*) = 1 from public.calls where conversation_id = (select v from ids where k = 'direct')),
  'Cara sees the call she was invited to');
select pg_temp.check((select (r ->> 'new_call')::boolean = false and r ->> 'title' = 'Call with CIN Anna'
  from (select public.fn_start_call((select v from ids where k = 'direct'), false) as r) x),
  'and joins it, named after who called');
select pg_temp.check((select count(*) = 0 from public.messages where conversation_id = (select v from ids where k = 'direct')),
  'but cannot read the chat''s messages');
select pg_temp.check((select count(distinct call_id) = 1 from public.call_participants),
  'and sees who is in that call only, not other calls');
select pg_temp.fails($$select public.fn_call_invite((select v from ids where k = 'direct'), array['fe560000-0000-0000-0000-000000000002'::uuid])$$,
  'NOT_FOUND', 'a guest of the call cannot add more people');

-- The invitation ends with the call.
select pg_temp.as_owner();
update public.calls set ended_at = now() where conversation_id = (select v from ids where k = 'direct');
select pg_temp.act_as('fe560000-0000-0000-0000-000000000003');
select pg_temp.fails($$select public.fn_start_call((select v from ids where k = 'direct'), false)$$,
  'NOT_FOUND', 'after the call, Cara cannot start a new one in that chat');
select pg_temp.fails($$insert into public.call_invites (call_id, user_id) select id, 'fe560000-0000-0000-0000-000000000003' from public.calls limit 1$$,
  '', 'invites are only made through the function');
select pg_temp.as_owner();

rollback;
