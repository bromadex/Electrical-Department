-- Behaviour checks for 0022_meetings. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('f8000000-0000-0000-0000-0000000000a1', 'MTG', 'Meeting site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('f8000000-0000-0000-0000-000000000001', 'mtg-sup@test', '{"full_name":"Mtg Sup"}'),
  ('f8000000-0000-0000-0000-000000000002', 'mtg-tech@test', '{"full_name":"Mtg Tech"}'),
  ('f8000000-0000-0000-0000-000000000003', 'mtg-out@test', '{"full_name":"Mtg Out"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'f8000000-0000-0000-0000-000000000001'::uuid, id, 'f8000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Supervisor'
union all
select 'f8000000-0000-0000-0000-000000000002'::uuid, id, 'f8000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Technician';

create temp table mchat as
  select id from public.conversations where is_default and site_id = 'f8000000-0000-0000-0000-0000000000a1';
grant select on mchat to authenticated;
create temp table mtg (id uuid);
grant select, insert on mtg to authenticated;

-- Technicians cannot schedule; supervisors can.
select pg_temp.act_as('f8000000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_create_meeting(gen_random_uuid(), (select id from mchat), null,
  'Weekly', null, now() + interval '1 day', 60)$$, 'NOT_ALLOWED', 'a technician cannot schedule');

select pg_temp.act_as('f8000000-0000-0000-0000-000000000001');
insert into mtg select (public.fn_create_meeting('f8000000-0000-0000-0000-00000000aaaa', (select id from mchat), null,
  'Weekly planning', 'Outages; spares', now() + interval '10 minutes', 45)).id;
select pg_temp.check((select code like 'M-%' and chair_id = 'f8000000-0000-0000-0000-000000000001'
  from public.meetings where id = (select id from mtg)), 'a supervisor schedules a meeting with an M- code');
select pg_temp.check((select (public.fn_create_meeting('f8000000-0000-0000-0000-00000000aaaa', (select id from mchat), null,
  'Again', null, now() + interval '1 day', 60)).title = 'Weekly planning'), 'sending it twice keeps one meeting');
select pg_temp.check(exists (select 1 from public.messages
  where conversation_id = (select id from mchat) and kind = 'system' and record_link = 'meeting:' || (select id from mtg)),
  'the meeting card is posted in the chat');
select pg_temp.as_owner();
select pg_temp.check(exists (select 1 from public.notifications
  where user_id = 'f8000000-0000-0000-0000-000000000002' and title = 'Meeting: Weekly planning'),
  'the chat hears about it');

-- Reminder 15 minutes before, once.
select public.fn_meeting_reminders();
select public.fn_meeting_reminders();
select pg_temp.check((select count(*) = 1 from public.notifications
  where user_id = 'f8000000-0000-0000-0000-000000000002' and title = 'Starting soon: Weekly planning'),
  'one reminder before it starts');

-- Members see it; outsiders do not.
select pg_temp.act_as('f8000000-0000-0000-0000-000000000002');
select pg_temp.check(exists (select 1 from public.meetings where id = (select id from mtg)), 'members see the meeting');
select pg_temp.fails($$select public.fn_save_minutes((select id from mtg), null, '{"summary":"x"}')$$,
  'NOT_ALLOWED', 'only the chair writes the minutes');
select pg_temp.act_as('f8000000-0000-0000-0000-000000000003');
select pg_temp.check(not exists (select 1 from public.meetings where id = (select id from mtg)), 'outsiders do not');

-- Minutes: draft, then approve; owners of actions are told.
select pg_temp.act_as('f8000000-0000-0000-0000-000000000001');
select pg_temp.fails($$select public.fn_approve_minutes((select id from mtg))$$, 'INVALID', 'no summary, no approval');
select public.fn_save_minutes((select id from mtg), 'We agreed to replace the breaker.',
  jsonb_build_object('summary', 'Breaker on DB-3 to be replaced.', 'decisions', jsonb_build_array('Replace it Friday'),
    'actions', jsonb_build_array(jsonb_build_object('text', 'Order a 63 A breaker',
      'owner_id', 'f8000000-0000-0000-0000-000000000002', 'due', '2026-11-01'))));
select pg_temp.check((select minutes_status = 'draft' and transcript like 'We agreed%'
  from public.meetings where id = (select id from mtg)), 'a draft with the transcript');
select public.fn_approve_minutes((select id from mtg));
select pg_temp.check((select minutes_status = 'approved' from public.meetings where id = (select id from mtg)), 'approved');
select pg_temp.fails($$select public.fn_save_minutes((select id from mtg), null, '{"summary":"changed"}')$$,
  'INVALID', 'approved minutes are final');
select pg_temp.as_owner();
select pg_temp.check(exists (select 1 from public.notifications
  where user_id = 'f8000000-0000-0000-0000-000000000002' and title = 'Action for you: Weekly planning'),
  'the action owner is told');

-- Recording state and cancelling.
select pg_temp.act_as('f8000000-0000-0000-0000-000000000001');
select public.fn_meeting_recording((select id from mtg), 'recording', 'EG_123', (select id from mtg)::text || '/audio.ogg', null);
select pg_temp.check((select recording_status = 'recording' and egress_id = 'EG_123' from public.meetings
  where id = (select id from mtg)), 'recording state is kept');
select public.fn_update_meeting((select id from mtg), null, null, null, null, true);
select pg_temp.check((select status = 'cancelled' from public.meetings where id = (select id from mtg)), 'the chair can cancel');
select pg_temp.as_owner();

rollback;
