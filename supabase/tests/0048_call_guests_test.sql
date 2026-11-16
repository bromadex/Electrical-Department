-- Behaviour checks for 0048_call_guests. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('fe480000-0000-0000-0000-0000000000a1', 'GST', 'Guest site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('fe480000-0000-0000-0000-000000000001', 'gst-a@test', '{"full_name":"GST Anna"}'),
  ('fe480000-0000-0000-0000-000000000002', 'gst-b@test', '{"full_name":"GST Ben"}'),
  ('fe480000-0000-0000-0000-000000000003', 'gst-c@test', '{"full_name":"GST Cara"}');
insert into public.user_roles (user_id, role_id, site_id)
select u, r.id, 'fe480000-0000-0000-0000-0000000000a1'::uuid
from public.roles r, unnest(array['fe480000-0000-0000-0000-000000000001'::uuid,
  'fe480000-0000-0000-0000-000000000002'::uuid, 'fe480000-0000-0000-0000-000000000003'::uuid]) u
where r.name = 'Technician';
-- Anna is a supervisor too (creates groups).
insert into public.user_roles (user_id, role_id, site_id)
select 'fe480000-0000-0000-0000-000000000001'::uuid, id, 'fe480000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Supervisor';

select pg_temp.act_as('fe480000-0000-0000-0000-000000000001');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
insert into ids values ('group', (public.fn_create_group(gen_random_uuid(), 'Guest site group',
  'fe480000-0000-0000-0000-0000000000a1', array['fe480000-0000-0000-0000-000000000002'::uuid,
  'fe480000-0000-0000-0000-000000000003'::uuid])).id);
insert into ids values ('direct', public.fn_open_direct(gen_random_uuid(), 'fe480000-0000-0000-0000-000000000002'));
select pg_temp.as_owner();
update public.conversation_members set joined_at = now() - interval '1 hour'
where conversation_id in (select v from ids);

create temp table g (k text primary key, v text);
grant all on g to authenticated;

-- Who may invite: not a plain member, yes whoever runs the call.
select pg_temp.act_as('fe480000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_create_guest_link((select v from ids where k = 'group'), 4)$$,
  'NOT_ALLOWED', 'a plain member cannot invite guests');
select pg_temp.fails($$select public.fn_create_guest_link((select v from ids where k = 'direct'), 4)$$,
  'NOT_ALLOWED', 'direct chats have no guest links');
select pg_temp.act_as('fe480000-0000-0000-0000-000000000001');
insert into g select 'link', public.fn_create_guest_link((select v from ids where k = 'group'), 500)->>'token';
select pg_temp.check((select expires_at < now() + interval '73 hours' and expires_at > now() + interval '71 hours'
  from public.call_guest_links where token = (select v from g where k = 'link')),
  'the supervisor makes a link (at most 72 hours)');
select pg_temp.check((select length(v) = 64 from g where k = 'link'), 'the token is long and random');

-- The outsider asks to join (guest-join runs as the service role).
select pg_temp.as_owner();
insert into g select 'guest', public.fn_guest_request((select v from g where k = 'link'), ' Sam (ABB) ', 'hash1')->>'guest_id';
select pg_temp.check((select status = 'waiting' and name = 'Sam (ABB)' from public.call_guests
  where id = (select v from g where k = 'guest')::uuid), 'the guest waits');
select pg_temp.check((select count(*) = 1 from public.notifications where user_id = 'fe480000-0000-0000-0000-000000000001'
  and title like 'Sam (ABB) (guest) is waiting'), 'the link''s maker is told');
select pg_temp.check((select public.fn_guest_status((select v from g where k = 'guest')::uuid, 'hash1')->>'status') = 'waiting',
  'the guest''s page sees waiting');
select pg_temp.check(public.fn_guest_status((select v from g where k = 'guest')::uuid, 'wrong') is null,
  'the wrong secret sees nothing');
select pg_temp.fails($$select public.fn_guest_request('nope', 'X', 'h')$$, 'NOT_FOUND', 'an unknown link is refused');
select pg_temp.fails($$select public.fn_guest_request((select v from g where k = 'link'), '  ', 'h')$$, 'INVALID',
  'a guest must give a name');

-- Members see who waits; only whoever runs the call decides.
select pg_temp.act_as('fe480000-0000-0000-0000-000000000003');
select pg_temp.check((select count(*) = 1 from public.call_guests), 'members see the waiting guest');
select pg_temp.check((select count(*) = 0 from public.call_guests where secret_hash <> 'hash1'), 'only the hash is stored');
select pg_temp.fails($$select public.fn_decide_guest((select v from g where k = 'guest')::uuid, true)$$, 'NOT_FOUND',
  'a plain member cannot let a guest in');
select pg_temp.act_as('fe480000-0000-0000-0000-000000000001');
select public.fn_decide_guest((select v from g where k = 'guest')::uuid, true);
select pg_temp.as_owner();
select pg_temp.check((select public.fn_guest_status((select v from g where k = 'guest')::uuid, 'hash1')->>'status') = 'admitted',
  'once let in, the guest''s page gets admitted');

-- Ending the link ends it for the guest; strangers see nothing.
select pg_temp.act_as('fe480000-0000-0000-0000-000000000001');
select public.fn_revoke_guest_link((select id from public.call_guest_links where token = (select v from g where k = 'link')));
select pg_temp.as_owner();
select pg_temp.check((select public.fn_guest_status((select v from g where k = 'guest')::uuid, 'hash1')->>'status') = 'ended',
  'a revoked link ends the guest''s access');
select pg_temp.fails($$select public.fn_guest_request((select v from g where k = 'link'), 'Late', 'h')$$, 'NOT_FOUND',
  'nobody joins through a revoked link');
insert into auth.users (id, email) values ('fe480000-0000-0000-0000-000000000009', 'stranger@test');
select pg_temp.act_as('fe480000-0000-0000-0000-000000000009');
select pg_temp.check((select count(*) = 0 from public.call_guests) and (select count(*) = 0 from public.call_guest_links),
  'people outside the chat see no links or guests');
select pg_temp.fails($$select public.fn_guest_status(gen_random_uuid(), 'x')$$, '', 'the app cannot call the guest functions');
select pg_temp.as_owner();

rollback;
