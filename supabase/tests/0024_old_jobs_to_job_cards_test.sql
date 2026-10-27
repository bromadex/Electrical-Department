-- Behaviour checks for 0024_old_jobs_to_job_cards: the jobs board's jobs
-- become job cards with their photos and comments. Runs in a transaction and
-- rolls back.
begin;

create function pg_temp.check(p_ok boolean, p_label text) returns void language plpgsql as $$
begin
  if p_ok is not true then raise exception 'FAILED: %', p_label; end if;
  raise notice 'ok - %', p_label;
end $$;

insert into auth.users (id, email, raw_user_meta_data) values
  ('e0000000-0000-0000-0000-000000000001', 'old-tech@test', '{"full_name":"Old Tech"}'),
  ('e0000000-0000-0000-0000-000000000002', 'old-sup@test', '{"full_name":"Old Sup"}');

create temp table t as select
  (select id from public.sites where code = 'KAM') kam,
  'e0000000-0000-0000-0000-000000000001'::uuid tech,
  'e0000000-0000-0000-0000-000000000002'::uuid sup;

-- Jobs as the board left them: open, waiting, done and cancelled
insert into public.jobs (
  id, site_id, code, title, description, priority, status, waiting_reason, due_at,
  created_by, assignee_id, taken_at, closed_at, closed_by, close_note, created_at
)
select x.id, t.kam, x.code, x.title, x.descr, x.priority, x.status, x.waiting, x.due, t.sup,
  case when x.assigned then t.tech end, x.taken, x.closed,
  case when x.closed is not null then t.tech end, x.note, x.created
from t, (values
  ('e1000000-0000-0000-0000-000000000001'::uuid, 'J-9001', 'Open old job', null::text, 'urgent', 'open',
    null::text, now() + interval '1 day', false, null::timestamptz, null::timestamptz, null::text,
    now() - interval '2 days'),
  ('e1000000-0000-0000-0000-000000000002'::uuid, 'J-9002', 'Waiting old job', 'Needs parts', 'normal', 'waiting',
    'Parts from Harare', null, true, now() - interval '1 day', null, null, now() - interval '1 day'),
  ('e1000000-0000-0000-0000-000000000003'::uuid, 'J-9003', 'Done old job', 'Lamp out', 'low', 'done',
    null, null, true, now() - interval '3 days', now() - interval '1 day', 'Replaced lamp', now() - interval '4 days'),
  ('e1000000-0000-0000-0000-000000000004'::uuid, 'J-9004', 'Cancelled old job', null, 'normal', 'cancelled',
    null, null, false, null, now() - interval '1 day', null, now() - interval '5 days')
) as x (id, code, title, descr, priority, status, waiting, due, assigned, taken, closed, note, created);

insert into public.job_photos (id, job_id, kind, path, created_by)
select 'e2000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000003', 'after',
  t.kam::text || '/job/e1000000-0000-0000-0000-000000000003/after-1.jpg', t.tech
from t;
insert into public.job_comments (id, job_id, author_id, body)
select 'e3000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000002', t.sup, 'Ordered the parts'
from t;

select pg_temp.check(public._copy_old_jobs() >= 4, 'old jobs are copied');
select pg_temp.check(public._copy_old_jobs() = 0, 'copying again adds nothing');

create temp view jc as select * from public.job_cards where legacy_code like 'J-900%';

select pg_temp.check((select status = 'registered' and priority = 'P2' and reporter_name = 'Old Sup'
  from jc where legacy_code = 'J-9001'), 'an open job becomes a registered P2 job card');
select pg_temp.check((select number from jc where legacy_code = 'J-9001') ~ '^EL-JC-[0-9]{4}-[0-9]{4,}$',
  'copied job cards get job card numbers');
select pg_temp.check((select location like 'Not recorded%' from jc where legacy_code = 'J-9001'),
  'a missing location is labelled, not invented');
select pg_temp.check((select status = 'on_hold' and status_reason = 'Parts from Harare'
  and responsible_id = (select tech from t) from jc where legacy_code = 'J-9002'),
  'a waiting job is on hold with its reason');
select pg_temp.check(exists (select 1 from public.job_assignments a join jc on jc.id = a.job_card_id
  where jc.legacy_code = 'J-9002' and a.role = 'responsible' and a.ended_at is null),
  'the assignee becomes the responsible person');
select pg_temp.check((select count(*) from public.job_card_comments c join jc on jc.id = c.job_card_id
  where jc.legacy_code = 'J-9002') = 1, 'comments are copied');
select pg_temp.check((select status = 'closed' and legacy_closure and completion_summary = 'Replaced lamp'
  and priority = 'P4' from jc where legacy_code = 'J-9003'), 'a done job becomes a closed job card');
select pg_temp.check((select count(*) from public.job_closures c join jc on jc.id = c.job_card_id
  where jc.legacy_code = 'J-9003' and c.legacy) = 1, 'its closure is recorded');
select pg_temp.check(exists (select 1 from public.job_attachments f join jc on jc.id = f.job_card_id
  where jc.legacy_code = 'J-9003' and f.kind = 'photo_after' and f.bucket = 'job-photos'),
  'photos stay in the old bucket');
select pg_temp.check((select status = 'cancelled' and status_reason = 'Cancelled on the jobs board'
  from jc where legacy_code = 'J-9004'), 'a cancelled job keeps a reason');
select pg_temp.check((select count(*) from public.jobs where code like 'J-900%') = 4,
  'the old jobs stay where they were');
select pg_temp.check(exists (select 1 from pg_policies
  where schemaname = 'storage' and policyname = 'job_photos_select_jc'), 'job card viewers can read old photos');
select pg_temp.check(exists (select 1 from public.schema_migrations
  where filename = '0024_old_jobs_to_job_cards.sql'), 'migration is logged');

rollback;
