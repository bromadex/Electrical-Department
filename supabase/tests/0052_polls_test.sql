-- Behaviour checks for 0052_polls. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('fe520000-0000-0000-0000-0000000000a1', 'POL', 'Poll site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('fe520000-0000-0000-0000-000000000001', 'pol-a@test', '{"full_name":"POL Anna"}'),
  ('fe520000-0000-0000-0000-000000000002', 'pol-b@test', '{"full_name":"POL Ben"}'),
  ('fe520000-0000-0000-0000-000000000003', 'pol-c@test', '{"full_name":"POL Cara"}');
insert into public.user_roles (user_id, role_id, site_id)
select u, r.id, 'fe520000-0000-0000-0000-0000000000a1'::uuid
from public.roles r, unnest(array['fe520000-0000-0000-0000-000000000001'::uuid,
  'fe520000-0000-0000-0000-000000000002'::uuid, 'fe520000-0000-0000-0000-000000000003'::uuid]) u
where r.name = 'Technician';
-- Anna is a supervisor too (creates groups).
insert into public.user_roles (user_id, role_id, site_id)
select 'fe520000-0000-0000-0000-000000000001'::uuid, id, 'fe520000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Supervisor';

select pg_temp.act_as('fe520000-0000-0000-0000-000000000001');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
insert into ids values ('group', (public.fn_create_group(gen_random_uuid(), 'Poll site group',
  'fe520000-0000-0000-0000-0000000000a1', array['fe520000-0000-0000-0000-000000000002'::uuid,
  'fe520000-0000-0000-0000-000000000003'::uuid])).id);
insert into ids values ('direct', public.fn_open_direct(gen_random_uuid(), 'fe520000-0000-0000-0000-000000000002'));
select pg_temp.as_owner();
update public.conversation_members set joined_at = now() - interval '1 hour'
where conversation_id in (select v from ids);


create temp table pl (k text primary key, v uuid);
grant all on pl to authenticated;
select pg_temp.act_as('fe520000-0000-0000-0000-000000000001');
insert into pl values ('poll', public.fn_create_poll('fe520000-0000-0000-0000-0000000000e1', (select v from ids where k = 'group'),
  'Overtime on Saturday?', array['Yes', ' No ', '', 'Maybe'], false));
select pg_temp.check((select options = array['Yes','No','Maybe'] and not multiple from public.polls
  where id = (select v from pl where k = 'poll')), 'a poll keeps its non-empty options, trimmed');
select pg_temp.check((select body = '📊 Overtime on Saturday?' and record_link = 'poll:' || (select v from pl where k = 'poll')::text
  from public.messages where id = 'fe520000-0000-0000-0000-0000000000e1'), 'and posts it in the chat');
select pg_temp.check(public.fn_create_poll('fe520000-0000-0000-0000-0000000000e1', (select v from ids where k = 'group'), 'Again', array['a','b'], false)
  = (select v from pl where k = 'poll'), 'sending it twice (offline retry) makes one poll');
select pg_temp.fails($$select public.fn_create_poll(gen_random_uuid(), (select v from ids where k = 'group'), 'Q', array['only'], false)$$,
  'INVALID', 'a poll needs two options');

-- Voting.
select pg_temp.act_as('fe520000-0000-0000-0000-000000000002');
select public.fn_vote_poll((select v from pl where k = 'poll'), array[0]);
select public.fn_vote_poll((select v from pl where k = 'poll'), array[1]);
select pg_temp.check((select array_agg(option) = array[1] from public.poll_votes where user_id = 'fe520000-0000-0000-0000-000000000002'),
  'voting again replaces your vote');
select pg_temp.fails($$select public.fn_vote_poll((select v from pl where k = 'poll'), array[0, 2])$$, 'INVALID',
  'one option only, unless the poll allows several');
select pg_temp.fails($$select public.fn_vote_poll((select v from pl where k = 'poll'), array[7])$$, 'INVALID',
  'no such option');
select pg_temp.act_as('fe520000-0000-0000-0000-000000000003');
select public.fn_vote_poll((select v from pl where k = 'poll'), array[1]);
select pg_temp.check((select count(*) = 2 from public.poll_votes where option = 1), 'everyone in the chat sees the votes');
select public.fn_vote_poll((select v from pl where k = 'poll'), array[]::integer[]);
select pg_temp.check((select count(*) = 0 from public.poll_votes where user_id = 'fe520000-0000-0000-0000-000000000003'), 'an empty vote takes it back');
select pg_temp.fails($$insert into public.poll_votes (poll_id, user_id, option) values ((select v from pl where k = 'poll'), 'fe520000-0000-0000-0000-000000000003', 0)$$,
  '', 'votes cannot be written directly');

-- Several answers; outsiders see nothing.
select pg_temp.act_as('fe520000-0000-0000-0000-000000000001');
insert into pl values ('multi', public.fn_create_poll(gen_random_uuid(), (select v from ids where k = 'group'), 'Which days?', array['Mon','Tue','Wed'], true));
select pg_temp.act_as('fe520000-0000-0000-0000-000000000002');
select public.fn_vote_poll((select v from pl where k = 'multi'), array[0, 2, 2]);
select pg_temp.check((select count(*) = 2 from public.poll_votes where poll_id = (select v from pl where k = 'multi')),
  'a several-answer poll takes several (each once)');
select pg_temp.as_owner();
insert into auth.users (id, email) values ('fe520000-0000-0000-0000-000000000009', 'outsider-poll@test');
select pg_temp.act_as('fe520000-0000-0000-0000-000000000009');
select pg_temp.check((select count(*) = 0 from public.polls) and (select count(*) = 0 from public.poll_votes),
  'people outside the chat see no polls');
select pg_temp.fails($$select public.fn_vote_poll((select v from pl where k = 'poll'), array[0])$$, 'NOT_FOUND',
  'and cannot vote');
select pg_temp.as_owner();

rollback;
