-- Behaviour checks for 0006_cmms_legacy_data: legacy jobs become job cards and
-- recurring templates keep producing work. Runs in a transaction and rolls back.
begin;

create function pg_temp.check(p_ok boolean, p_label text) returns void language plpgsql as $$
begin
  if p_ok is not true then raise exception 'FAILED: %', p_label; end if;
  raise notice 'ok - %', p_label;
end $$;

insert into auth.users (id, email, raw_user_meta_data) values
  ('60000000-0000-0000-0000-000000000001', 'legacy-tech@test', '{"full_name":"Legacy Tech"}'),
  ('60000000-0000-0000-0000-000000000002', 'legacy-sup@test', '{"full_name":"Legacy Sup"}');

create temp table t as select
  (select id from public.sites where code = 'KAM') kam,
  '60000000-0000-0000-0000-000000000001'::uuid tech,
  '60000000-0000-0000-0000-000000000002'::uuid sup;

-- Jobs as the old board left them: open, waiting, done and cancelled
insert into public.legacy_jobs (
  id, site_id, code, title, description, priority, status, waiting_reason, due_at,
  created_by, assignee_id, taken_at, closed_at, closed_by, close_note, created_at
)
select x.id, t.kam, x.code, x.title, x.descr, x.priority, x.status, x.waiting, x.due, t.sup,
  case when x.assigned then t.tech end, x.taken, x.closed,
  case when x.closed is not null then t.tech end, x.note, x.created
from t, (values
  ('61000000-0000-0000-0000-000000000001'::uuid, 'J-9001', 'Open legacy job', null::text, 'urgent', 'open',
    null::text, now() + interval '1 day', false, null::timestamptz, null::timestamptz, null::text,
    now() - interval '2 days'),
  ('61000000-0000-0000-0000-000000000002'::uuid, 'J-9002', 'Waiting legacy job', 'Needs parts', 'normal', 'waiting',
    'Parts from Harare', null, true, now() - interval '1 day', null, null, now() - interval '1 day'),
  ('61000000-0000-0000-0000-000000000003'::uuid, 'J-9003', 'Done legacy job', 'Lamp out', 'low', 'done',
    null, null, true, now() - interval '3 days', now() - interval '1 day', 'Replaced lamp', now() - interval '4 days'),
  ('61000000-0000-0000-0000-000000000004'::uuid, 'J-9004', 'Cancelled legacy job', null, 'normal', 'cancelled',
    null, null, false, null, now() - interval '1 day', null, now() - interval '5 days')
) as x (id, code, title, descr, priority, status, waiting, due, assigned, taken, closed, note, created);

insert into public.legacy_job_photos (id, job_id, kind, path, created_by)
select '62000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000003', 'after',
  t.kam::text || '/job/61000000-0000-0000-0000-000000000003/after-1.jpg', t.tech
from t;

insert into public.legacy_job_comments (id, job_id, author_id, body)
select '63000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000002', t.sup, 'Ordered the parts'
from t;

select pg_temp.check(public._migrate_legacy_jobs() >= 4, 'legacy jobs are copied');
select pg_temp.check(public._migrate_legacy_jobs() = 0, 'copying again adds nothing');

create temp view jc as select * from public.job_cards where legacy_code like 'J-900%';

select pg_temp.check((select status = 'registered' and priority = 'P2' and reporter_name = 'Legacy Sup'
  from jc where legacy_code = 'J-9001'), 'an open job becomes a registered P2 job card');
select pg_temp.check((select number from jc where legacy_code = 'J-9001') ~ '^EL-JC-[0-9]{4}-[0-9]{4,}$',
  'migrated job cards get new numbers');
select pg_temp.check((select location like 'Not recorded%' from jc where legacy_code = 'J-9001'),
  'a missing location is labelled, not invented');
select pg_temp.check((select status = 'on_hold' and status_reason = 'Parts from Harare' and responsible_id = (select tech from t)
  from jc where legacy_code = 'J-9002'), 'a waiting job is on hold with its reason');
select pg_temp.check(exists (select 1 from public.job_assignments a join jc on jc.id = a.job_card_id
  where jc.legacy_code = 'J-9002' and a.role = 'responsible' and a.ended_at is null),
  'the assignee becomes the responsible person');
select pg_temp.check((select count(*) from public.job_comments c join jc on jc.id = c.job_card_id
  where jc.legacy_code = 'J-9002') = 1, 'comments are copied');
select pg_temp.check((select status = 'closed' and legacy_closure and completion_summary = 'Replaced lamp' and priority = 'P4'
  from jc where legacy_code = 'J-9003'), 'a done job becomes a closed legacy job card');
select pg_temp.check((select count(*) from public.job_closures c join jc on jc.id = c.job_card_id
  where jc.legacy_code = 'J-9003' and c.legacy) = 1, 'the legacy closure is recorded');
select pg_temp.check(exists (select 1 from public.job_attachments f join jc on jc.id = f.job_card_id
  where jc.legacy_code = 'J-9003' and f.kind = 'photo_after' and f.bucket = 'job-photos'),
  'photos stay in the old bucket');
select pg_temp.check((select status = 'cancelled' and status_reason = 'Cancelled on the jobs board'
  from jc where legacy_code = 'J-9004'), 'a cancelled job keeps a reason');
select pg_temp.check(exists (select 1 from pg_policies
  where schemaname = 'storage' and policyname = 'legacy_job_photos_select'), 'job card viewers can read old photos');
select pg_temp.check(not exists (select 1 from cron.job where jobname in ('jobs-overdue', 'jobs-recurrences')),
  'old schedules are removed');
-- 0008 replaced the hourly overdue notice with the escalation rules.
select pg_temp.check((select count(*) from cron.job where jobname in ('jobcards-escalations', 'legacy-recurrences')) = 2,
  'new schedules are set');
select pg_temp.check(not exists (select 1 from cron.job where jobname = 'jobcards-overdue'),
  'the hourly overdue notice is retired');

-- Recurring templates keep producing work until phase 3
insert into public.legacy_job_recurrences (id, site_id, title, priority, every, next_run, due_days, assignee_id, created_by)
select '64000000-0000-0000-0000-000000000001', t.kam, 'Weekly lighting check', 'normal', 'weekly',
  (now() at time zone 'Africa/Harare')::date - 1, 1, t.tech, t.sup
from t;
select pg_temp.check(public.fn_run_legacy_recurrences() >= 1, 'due templates create job cards');
select pg_temp.check(exists (select 1 from public.job_cards where source = 'preventive' and title = 'Weekly lighting check'
  and status = 'assigned' and responsible_id = (select tech from t)), 'the scheduled job card goes to the template''s person');
select pg_temp.check((select next_run from public.legacy_job_recurrences where id = '64000000-0000-0000-0000-000000000001')
  = (now() at time zone 'Africa/Harare')::date + 7, 'the template moves to its next run');

rollback;
