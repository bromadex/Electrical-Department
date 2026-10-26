-- Behaviour checks for 0020_call_history. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('f6000000-0000-0000-0000-0000000000a1', 'CHI', 'Call history site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('f6000000-0000-0000-0000-000000000001', 'ch-sup@test', '{"full_name":"Ch Sup"}'),
  ('f6000000-0000-0000-0000-000000000002', 'ch-tech@test', '{"full_name":"Ch Tech"}'),
  ('f6000000-0000-0000-0000-000000000003', 'ch-out@test', '{"full_name":"Ch Out"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'f6000000-0000-0000-0000-000000000001'::uuid, id, 'f6000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Supervisor'
union all
select 'f6000000-0000-0000-0000-000000000002'::uuid, id, 'f6000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Technician';

create temp table ch_chat as
  select id from public.conversations where is_default and site_id = 'f6000000-0000-0000-0000-0000000000a1';
grant select on ch_chat to authenticated;
create temp table ch_call (id uuid);
grant select, insert, delete on ch_call to authenticated;

-- Answered call: tech starts, sup joins, both leave.
select pg_temp.act_as('f6000000-0000-0000-0000-000000000002');
insert into ch_call select (public.fn_start_call((select id from ch_chat), true) ->> 'call_id')::uuid;
select pg_temp.check((select status = 'live' and video and in_call = 1
  from public.fn_conversation_calls((select id from ch_chat))), 'a started call is live');
select pg_temp.check((select call_live from public.fn_my_conversations() where id = (select id from ch_chat)),
  'the chat list shows the live call');
select pg_temp.act_as('f6000000-0000-0000-0000-000000000001');
select pg_temp.check((public.fn_start_call((select id from ch_chat)) ->> 'call_id')::uuid = (select id from ch_call),
  'the next person joins the same call');
select pg_temp.check((select answered_at is not null and in_call = 2
  from public.fn_conversation_calls((select id from ch_chat))), 'joining answers it');
select pg_temp.act_as('f6000000-0000-0000-0000-000000000002');
select public.fn_leave_call((select id from ch_call));
select pg_temp.check((select status = 'live' from public.fn_conversation_calls((select id from ch_chat))),
  'still live while someone is in it');
select pg_temp.act_as('f6000000-0000-0000-0000-000000000001');
select public.fn_leave_call((select id from ch_call));
select pg_temp.check((select status = 'ended' and ended_at is not null
  from public.fn_conversation_calls((select id from ch_chat))), 'the last one out ends it');
select pg_temp.as_owner();
select pg_temp.check(not exists (select 1 from public.notifications where title like 'Missed call%'
  and user_id in ('f6000000-0000-0000-0000-000000000001', 'f6000000-0000-0000-0000-000000000002')),
  'an answered call is not missed');

-- Unanswered call: tech starts and gives up.
delete from ch_call;
select pg_temp.act_as('f6000000-0000-0000-0000-000000000002');
insert into ch_call select (public.fn_start_call((select id from ch_chat)) ->> 'call_id')::uuid;
select public.fn_leave_call((select id from ch_call));
select pg_temp.check((select status = 'missed' from public.fn_conversation_calls((select id from ch_chat))
  where id = (select id from ch_call)), 'nobody answered: missed');
select pg_temp.as_owner();
select pg_temp.check((select count(*) = 1 from public.notifications
  where user_id = 'f6000000-0000-0000-0000-000000000001' and title = 'Missed call from Ch Tech'),
  'the others hear about the missed call');
select pg_temp.check(not exists (select 1 from public.notifications
  where user_id = 'f6000000-0000-0000-0000-000000000002' and title like 'Missed call%'), 'not the caller');
select pg_temp.check((select count(*) = 2 from public.messages
  where conversation_id = (select id from ch_chat) and kind = 'system'), 'each call is a row in the chat');

-- Everyone dropped out without leaving: the next start closes it and begins a new call.
delete from ch_call;
select pg_temp.act_as('f6000000-0000-0000-0000-000000000002');
insert into ch_call select (public.fn_start_call((select id from ch_chat)) ->> 'call_id')::uuid;
select pg_temp.as_owner();
update public.call_participants set last_seen_at = now() - interval '5 minutes' where call_id = (select id from ch_call);
select pg_temp.act_as('f6000000-0000-0000-0000-000000000001');
select pg_temp.check((public.fn_start_call((select id from ch_chat)) ->> 'new_call')::boolean,
  'a call everyone dropped out of is closed; a new one starts');
select pg_temp.check((select ended_at is not null from public.calls where id = (select id from ch_call)),
  'the dropped call has ended');

-- Outsiders see nothing and cannot keep a call alive.
select pg_temp.act_as('f6000000-0000-0000-0000-000000000003');
select pg_temp.check(not exists (select 1 from public.fn_conversation_calls((select id from ch_chat))),
  'outsiders cannot list a chat''s calls');
select pg_temp.check(not exists (select 1 from public.calls), 'or read them');
select pg_temp.as_owner();

rollback;
