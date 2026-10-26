-- Behaviour checks for 0014_v2_execution: work sessions and waits, the
-- safety checklist, the work log, submissions and reviews, closure metrics,
-- time corrections, escalation rules and the audit log.
-- Runs in a transaction and rolls back; now() is fixed for the whole run,
-- so measured times are checked on records written with known times.
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

insert into auth.users (id, email, raw_user_meta_data) values
  ('80000000-0000-0000-0000-000000000001', 'x-elec@test', '{"full_name":"Elec One"}'),
  ('80000000-0000-0000-0000-000000000002', 'x-eng@test', '{"full_name":"Eng One"}'),
  ('80000000-0000-0000-0000-000000000003', 'x-elec2@test', '{"full_name":"Elec Two"}'),
  ('80000000-0000-0000-0000-000000000004', 'x-mgr@test', '{"full_name":"Manager One"}'),
  ('80000000-0000-0000-0000-000000000005', 'x-admin@test', '{"full_name":"Admin One"}'),
  ('80000000-0000-0000-0000-000000000006', 'x-elec-sel@test', '{"full_name":"Elec Selous"}');

insert into public.user_roles (user_id, role_id, site_id)
select u.id, r.id, s.id
from (values
  ('80000000-0000-0000-0000-000000000001'::uuid, 'Technician', 'KAM'),
  ('80000000-0000-0000-0000-000000000002'::uuid, 'Supervisor', 'KAM'),
  ('80000000-0000-0000-0000-000000000003'::uuid, 'Technician', 'KAM'),
  ('80000000-0000-0000-0000-000000000004'::uuid, 'Department Manager', null),
  ('80000000-0000-0000-0000-000000000005'::uuid, 'Admin', null),
  ('80000000-0000-0000-0000-000000000006'::uuid, 'Technician', 'SEL')
) as u (id, role, site)
join public.roles r on r.name = u.role
left join public.sites s on s.code = u.site;

create temp table t as select
  (select id from public.sites where code = 'KAM') kam,
  '80000000-0000-0000-0000-000000000001'::uuid elec,
  '80000000-0000-0000-0000-000000000002'::uuid eng,
  '80000000-0000-0000-0000-000000000003'::uuid elec2,
  '80000000-0000-0000-0000-000000000004'::uuid mgr,
  '80000000-0000-0000-0000-000000000005'::uuid admin,
  '80000000-0000-0000-0000-000000000006'::uuid elec_sel,
  '81000000-0000-0000-0000-000000000001'::uuid job1,
  '81000000-0000-0000-0000-000000000002'::uuid job2,
  '81000000-0000-0000-0000-000000000003'::uuid job3;
grant select on t to authenticated;

-- ---------------------------------------------------------------------------
-- Set-up: job1 needs isolation, a permit and lockout; job2 and job3 do not
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select eng from t));
select public.fn_register_job_card((select job1 from t), null, (select kam from t), null, 'MCC-2 bay 4', null,
  'Shift foreman', null, null, 'MCC-2 feeder 4', null, null, null, 'Feeder 4 breaker tripping',
  'The feeder 4 breaker trips under load.', 'reduced_output', 'P2', null);
select public.fn_assess_job_card((select job1 from t), true, 'corrective', 'moderate', 'high', 'Live panel',
  'degraded', null, 2, null, true, true, true, 3, null, null, null, null);
select public.fn_assign_job_card((select job1 from t), (select elec from t), array[(select elec2 from t)],
  null, null, 3, null, null, null, null, null, null);
select public.fn_register_job_card((select job2 from t), null, (select kam from t), null, 'Workshop', null,
  'Shift foreman', null, null, 'Bench grinder', null, null, null, 'Bench grinder plug cracked',
  'The plug top of the bench grinder is cracked.', 'none', 'P4', null);
select public.fn_assess_job_card((select job2 from t), true, 'corrective', 'minor', 'low', null, 'operational',
  null, null, null, false, false, false, null, null, null, null, null);
select public.fn_assign_job_card((select job2 from t), (select elec from t), null, null, null, null, null, null,
  null, null, null, null);
select public.fn_register_job_card((select job3 from t), null, (select kam from t), null, 'Plant', null,
  'Shift foreman', null, null, 'Crusher motor', null, null, null, 'Crusher motor overheating',
  'The crusher motor runs hot after an hour.', 'reduced_output', 'P2', null);
select public.fn_assess_job_card((select job3 from t), true, 'reactive', 'major', 'medium', null, 'degraded',
  null, null, null, false, false, false, null, null, null, null, null);
select public.fn_assign_job_card((select job3 from t), (select elec from t), null, null, null, null, null, null,
  null, null, null, null);
select pg_temp.as_owner();

-- ---------------------------------------------------------------------------
-- Safety policy and the checklist gate
-- ---------------------------------------------------------------------------
select pg_temp.check((select safety_before_start from public.system_settings) = 'off',
  'safety checks are not required until an administrator chooses');
select pg_temp.act_as((select elec from t));
select pg_temp.fails($$select public.fn_save_safety_policy('off')$$, 'NOT_ALLOWED',
  'electricians cannot change the safety policy');
select pg_temp.as_owner();
select pg_temp.act_as((select admin from t));
select pg_temp.fails($$select public.fn_save_safety_policy('sometimes')$$, 'INVALID', 'unknown policy refused');
select public.fn_save_safety_policy('when_required');
select pg_temp.as_owner();

select pg_temp.act_as((select elec from t));
select pg_temp.fails($$select public.fn_start_work((select job1 from t))$$, 'INVALID',
  'work needing isolation cannot start before the safety checks are recorded');
select pg_temp.check((select status from public.job_cards where id = (select job1 from t)) = 'assigned',
  'a refused start changes nothing');
select public.fn_record_safety((select job1 from t), (
  select jsonb_agg(jsonb_build_object('item_id', i.id, 'confirmed', true,
    'reference', case when i.needs_reference then 'REF-1' end))
  from public.safety_checklist_items i where i.phase = 'before'
));
select public.fn_start_work((select job1 from t));
select pg_temp.check((select status = 'in_progress' and accepted_at is not null and first_started_at is not null
  from public.job_cards where id = (select job1 from t)), 'starting accepts the job and puts it in progress');
select public.fn_start_work((select job1 from t));
select pg_temp.check((select count(*) from public.job_work_sessions
  where job_card_id = (select job1 from t) and user_id = (select elec from t) and ended_at is null) = 1,
  'starting twice does not open a second session');
select pg_temp.as_owner();

select pg_temp.act_as((select elec2 from t));
select public.fn_start_work((select job1 from t));
select pg_temp.check((select count(*) from public.job_work_sessions
  where job_card_id = (select job1 from t) and ended_at is null) = 2, 'the supporting electrician joins');
select pg_temp.as_owner();

-- ---------------------------------------------------------------------------
-- Pause, hold and resume
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select elec from t));
select public.fn_pause_work((select job1 from t), 'break', 'Lunch', null);
select pg_temp.check((select pause_reason = 'break' and end_reason = 'pause' and ended_at is not null
  from public.job_work_sessions where job_card_id = (select job1 from t) and user_id = (select elec from t)),
  'a break stops only my timer');
select pg_temp.check((select status from public.job_cards where id = (select job1 from t)) = 'in_progress',
  'the job stays in progress during a break');
select pg_temp.fails($$select public.fn_pause_work((select job1 from t), 'break', null, null)$$, 'INVALID',
  'cannot pause work that is not running');
select pg_temp.fails($$select public.fn_pause_work((select job1 from t), 'nap', null, null)$$, 'INVALID',
  'unknown pause reason refused');
select pg_temp.fails($$select public.fn_pause_work((select job1 from t), 'awaiting_materials', '', false)$$,
  'INVALID', 'a hold needs a reason');
select public.fn_pause_work((select job1 from t), 'awaiting_materials', 'New 63 A breaker from stores', false);
select pg_temp.check((select status from public.job_cards where id = (select job1 from t)) = 'awaiting_materials',
  'waiting for materials');
select pg_temp.check(not exists (select 1 from public.job_work_sessions
  where job_card_id = (select job1 from t) and ended_at is null), 'a hold stops everyone''s timer');
select pg_temp.check((select end_reason from public.job_work_sessions
  where job_card_id = (select job1 from t) and user_id = (select elec2 from t)) = 'hold',
  'the supporting electrician''s session ended because of the hold');
select pg_temp.check((select count(*) = 1 and bool_and(not counts_toward_sla and ended_at is null)
  from public.job_waits where job_card_id = (select job1 from t)), 'the wait is recorded and excluded from the deadline');
select public.fn_start_work((select job1 from t));
select pg_temp.check((select status from public.job_cards where id = (select job1 from t)) = 'in_progress',
  'resuming puts the job back in progress');
select pg_temp.check((select ended_at is not null from public.job_waits where job_card_id = (select job1 from t)),
  'resuming ends the wait');
select pg_temp.as_owner();

-- ---------------------------------------------------------------------------
-- Measured times, on records with known times (owner rewrites them)
-- ---------------------------------------------------------------------------
update public.job_cards set received_at = now() - interval '10 hours', registered_at = now() - interval '10 hours'
where id = (select job1 from t);
delete from public.job_work_sessions where job_card_id = (select job1 from t);
delete from public.job_waits where job_card_id = (select job1 from t);
insert into public.job_work_sessions (job_card_id, user_id, started_at, ended_at, end_reason) values
  ((select job1 from t), (select elec from t), now() - interval '9 hours', now() - interval '6 hours', 'hold'),
  ((select job1 from t), (select elec2 from t), now() - interval '9 hours', now() - interval '6 hours', 'hold'),
  ((select job1 from t), (select elec from t), now() - interval '4 hours', now() - interval '3 hours', 'pause');
insert into public.job_waits (job_card_id, hold_status, note, counts_toward_sla, started_at, ended_at)
values ((select job1 from t), 'awaiting_materials', 'Breaker', false, now() - interval '6 hours', now() - interval '4 hours');

select pg_temp.check((public._jc_time_summary((select job1 from t)) ->> 'active_seconds')::bigint = 4 * 3600,
  'active time counts two people working at once only once (3 h + 1 h)');
select pg_temp.check((public._jc_time_summary((select job1 from t)) ->> 'labour_seconds')::bigint = 7 * 3600,
  'labour adds up everyone''s hours (3 h + 3 h + 1 h = 7 person-hours)');
select pg_temp.check((public._jc_time_summary((select job1 from t)) ->> 'wait_seconds')::bigint = 2 * 3600,
  'waiting time is measured separately');
select pg_temp.check((public._jc_time_summary((select job1 from t)) ->> 'elapsed_seconds')::bigint = 10 * 3600,
  'elapsed time runs from receipt and includes the waiting');
select pg_temp.check((public._jc_time_summary((select job1 from t)) ->> 'pause_count')::integer = 3,
  'pauses and holds are counted');
select pg_temp.check((select effective_deadline - target_completion_at from public.v_job_cards
  where id = (select job1 from t)) = interval '2 hours', 'an excluded wait moves the deadline by its length');

-- ---------------------------------------------------------------------------
-- Work log
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select elec from t));
select public.fn_add_work_record(null, (select job1 from t), 'readings', 'Insulation resistance after repair',
  '[{"name": "L1-E", "value": "500", "unit": "MOhm"}]'::jsonb);
select pg_temp.fails($$select public.fn_add_work_record(null, (select job1 from t), 'poem', 'Roses', null)$$,
  'INVALID', 'unknown work log type refused');
select pg_temp.fails($$select public.fn_add_work_record(null, (select job1 from t), 'diagnosis', '  ', null)$$,
  'INVALID', 'an empty entry is refused');
select pg_temp.check((select count(*) from public.job_work_records where job_card_id = (select job1 from t)) = 1,
  'the reading is in the work log');
select pg_temp.as_owner();
select pg_temp.act_as((select elec_sel from t));
select pg_temp.fails($$select public.fn_add_work_record(null, (select job1 from t), 'diagnosis', 'x', null)$$,
  'NOT_FOUND', 'another site''s electrician cannot write to this job card');
select pg_temp.fails($$select public.fn_job_work((select job1 from t))$$, 'NOT_FOUND',
  'another site''s electrician cannot read its work record');
select pg_temp.as_owner();

-- ---------------------------------------------------------------------------
-- Submission and review: returned once, a question, then approved (Test 6)
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select elec from t));
select pg_temp.fails($$select public.fn_submit_for_review((select job1 from t), 'Replaced the breaker and tested.',
  'Worn contacts', 'New breaker fitted', 'operational', 'Load test OK', 'IR 500 MOhm', '1 x 63 A breaker',
  null, null, null, true, true)$$, 'INVALID', 'post-work safety checks are needed before submitting');
select public.fn_record_safety((select job1 from t), (
  select jsonb_agg(jsonb_build_object('item_id', i.id, 'confirmed', true,
    'reference', case when i.needs_reference then 'PTW-9' end))
  from public.safety_checklist_items i where i.phase = 'after'
));
select pg_temp.fails($$select public.fn_submit_for_review((select job1 from t), 'Replaced the breaker and tested.',
  'Worn contacts', 'New breaker fitted', 'operational', null, null, null, null, null, null, true, false)$$,
  'INVALID', 'the safety declaration is required');
select public.fn_submit_for_review((select job1 from t), 'Replaced the breaker and tested.', 'Worn contacts',
  'New breaker fitted', 'operational', 'Load test OK', 'IR 500 MOhm', '1 x 63 A breaker', null, null, null, true, true);
select pg_temp.check((select status from public.job_cards where id = (select job1 from t)) = 'awaiting_review',
  'submitted for engineering review');
select pg_temp.check((select labour_hours = 7 and recorded_labour_minutes = 420
  from public.job_submissions where job_card_id = (select job1 from t)),
  'labour hours default to what the sessions measured');
select pg_temp.as_owner();
-- now() is fixed in this run; space the rounds out as they would be in use.
update public.job_submissions set submitted_at = now() - interval '5 minutes' where job_card_id = (select job1 from t);

select pg_temp.act_as((select eng from t));
select pg_temp.fails($$select public.fn_verify_job_card((select job1 from t), 'reject', '', null, null, null)$$,
  'INVALID', 'returning for more work needs a reason');
select public.fn_verify_job_card((select job1 from t), 'reject', 'Add the load test current', null, null, null);
select pg_temp.check((select status from public.job_cards where id = (select job1 from t)) = 'accepted',
  'returned for more work');
select pg_temp.as_owner();
update public.job_reviews set created_at = now() - interval '4 minutes' where job_card_id = (select job1 from t);

select pg_temp.act_as((select elec from t));
select public.fn_start_work((select job1 from t));
select public.fn_submit_for_review((select job1 from t), 'Replaced the breaker; load test 48 A.', 'Worn contacts',
  'New breaker fitted', 'operational', 'Load test 48 A', 'IR 500 MOhm', '1 x 63 A breaker', 6.5, null,
  'Check feeder 5 next month', true, true);
select pg_temp.as_owner();

select pg_temp.act_as((select eng from t));
select public.fn_verify_job_card((select job1 from t), 'request_info', 'Which breaker model was fitted?', null, null, null);
select pg_temp.check((select status = 'awaiting_review' and review_question_open from public.v_job_cards
  where id = (select job1 from t)), 'a question keeps the job awaiting review');
select pg_temp.as_owner();
update public.job_reviews set created_at = now() - interval '2 minutes'
where job_card_id = (select job1 from t) and decision = 'request_info';
select pg_temp.act_as((select elec from t));
select public.fn_answer_review((select job1 from t), 'ABB S203-C63');
select pg_temp.fails($$select public.fn_answer_review((select job1 from t), 'Again')$$, 'INVALID',
  'nothing to answer once answered');
select pg_temp.as_owner();

select pg_temp.act_as((select eng from t));
select public.fn_verify_job_card((select job1 from t), 'approve', 'Good work', 'Inspect feeder 5 breaker',
  'Contacts on feeder 5 look worn', 'P3');
select pg_temp.check((select status from public.job_cards where id = (select job1 from t)) = 'closed',
  'closure approved');
select pg_temp.check((select string_agg(decision, ',' order by created_at) from public.job_reviews
  where job_card_id = (select job1 from t)) = 'reject,request_info,approve', 'every review decision is kept');
select pg_temp.check((select count(*) from public.job_submissions where job_card_id = (select job1 from t)) = 2,
  'both submissions are kept');
select pg_temp.check((
  select c.active_minutes = 240 and c.labour_minutes = 420 and c.wait_minutes = 120 and c.sla_excluded_minutes = 120
    and c.pause_count = 3 and c.elapsed_minutes = 600 and c.labour_hours_reported = 6.5
    and c.completion_target_met and c.submission_id = (
      select id from public.job_submissions where job_card_id = (select job1 from t)
      order by submitted_at desc limit 1)
  from public.job_closures c where c.job_card_id = (select job1 from t)
), 'closure freezes active, labour, waiting and elapsed time separately');
select pg_temp.check(exists (select 1 from public.job_cards
  where parent_job_id = (select job1 from t) and source = 'follow_up' and title = 'Inspect feeder 5 breaker'
    and priority = 'P3' and status = 'registered'), 'approval can raise a follow-up job card');
select pg_temp.check(
  exists (select 1 from public.fn_job_card_timeline((select job1 from t)) where kind = 'work')
  and exists (select 1 from public.fn_job_card_timeline((select job1 from t)) where kind = 'review')
  and exists (select 1 from public.fn_job_card_timeline((select job1 from t)) where kind = 'safety'),
  'the timeline shows work, safety and review history');
select pg_temp.as_owner();

-- ---------------------------------------------------------------------------
-- Time corrections and waits
-- ---------------------------------------------------------------------------
update public.job_cards set received_at = now() - interval '5 hours' where id = (select job2 from t);
select pg_temp.act_as((select elec from t));
select public.fn_start_work((select job2 from t));
select public.fn_pause_work((select job2 from t), 'end_of_shift', null, null);
select pg_temp.as_owner();
create temp table s1 as select id from public.job_work_sessions where job_card_id = (select job2 from t);
grant select on s1 to authenticated;

select pg_temp.act_as((select elec from t));
select pg_temp.fails($$select public.fn_correct_work_session((select id from s1), now() - interval '2 hours',
  now() - interval '1 hour', 'Forgot to stop')$$, 'NOT_ALLOWED', 'electricians cannot correct times');
select pg_temp.as_owner();
select pg_temp.act_as((select eng from t));
select pg_temp.fails($$select public.fn_correct_work_session((select id from s1), now() - interval '2 hours',
  now() - interval '1 hour', 'oops')$$, 'INVALID', 'a correction needs a proper reason');
select pg_temp.fails($$select public.fn_correct_work_session((select id from s1), now() - interval '2 hours',
  now() + interval '1 hour', 'Forgot to stop')$$, 'INVALID', 'corrected times cannot be in the future');
select pg_temp.fails($$select public.fn_correct_work_session((select id from s1), now() - interval '6 hours',
  now() - interval '1 hour', 'Forgot to stop')$$, 'INVALID', 'work cannot start before the job was received');
select public.fn_correct_work_session((select id from s1), now() - interval '3 hours', now() - interval '1 hour',
  'Forgot to pause at lunch');
select pg_temp.check((select corrected and ended_at - started_at = interval '2 hours'
  from public.job_work_sessions where id = (select id from s1)), 'the session is corrected');
select pg_temp.check((select old_started_at = old_ended_at and new_ended_at - new_started_at = interval '2 hours'
  from public.job_time_corrections where session_id = (select id from s1)), 'the old times and reason are kept');
select public.fn_add_work_session((select job2 from t), (select elec from t), now() - interval '4 hours',
  now() - interval '210 minutes', 'Worked before lunch, forgot to start');
select pg_temp.fails($$select public.fn_add_work_session((select job2 from t), (select elec from t),
  now() - interval '150 minutes', now() - interval '2 hours', 'Overlapping entry')$$, 'INVALID',
  'entered times cannot overlap the same person''s sessions');
select pg_temp.fails($$select public.fn_add_work_session((select job2 from t), (select elec_sel from t),
  now() - interval '4 hours', now() - interval '3 hours', 'Never on this job')$$, 'INVALID',
  'time can only be entered for people on the job');
select pg_temp.check((select count(*) from public.job_time_corrections where job_card_id = (select job2 from t)) = 2,
  'both corrections are in the audit trail');
select public.fn_set_wait_sla((select id from public.job_waits where job_card_id = (select job1 from t)), true,
  'Breaker was in stock');
select pg_temp.check((select counts_toward_sla and sla_changed_by = (select eng from t)
  from public.job_waits where job_card_id = (select job1 from t)), 'an engineer can count a wait again, with a reason');
select pg_temp.as_owner();

-- ---------------------------------------------------------------------------
-- Escalation rules
-- ---------------------------------------------------------------------------
update public.job_cards set target_response_at = now() - interval '1 hour' where id = (select job3 from t);
select pg_temp.check(public.fn_run_escalations() >= 1, 'the escalation run finds work');
select pg_temp.check(exists (select 1 from public.notifications n join public.job_cards j on n.link = 'jobcard:' || j.id
  where j.id = (select job3 from t) and n.user_id = (select eng from t) and n.title like j.number || ' not acknowledged%'),
  'an unacknowledged P2 is escalated to the engineers');
create temp table n1 as select count(*) as n from public.notifications;
select public.fn_run_escalations();
select pg_temp.check((select count(*) from public.notifications) = (select n from n1),
  'an escalation is sent once, not on every run');
update public.job_cards set target_completion_at = now() - interval '30 minutes' where id = (select job3 from t);
select public.fn_run_escalations();
select pg_temp.check(exists (select 1 from public.notifications n join public.job_cards j on n.link = 'jobcard:' || j.id
  where j.id = (select job3 from t) and n.user_id = (select elec from t) and n.type = 'overdue'),
  'an overdue job card is escalated to the responsible person');

select pg_temp.act_as((select elec from t));
select public.fn_start_work((select job3 from t));
select public.fn_pause_work((select job3 from t), 'awaiting_specialist', 'Motor rewinder from Harare', null);
select pg_temp.as_owner();
update public.job_waits set started_at = now() - interval '3 days' where job_card_id = (select job3 from t);
select public.fn_run_escalations();
select pg_temp.check(exists (select 1 from public.notifications n join public.job_cards j on n.link = 'jobcard:' || j.id
  where j.id = (select job3 from t) and n.user_id = (select eng from t) and n.type = 'on_hold'
    and n.title like '%on hold too long'), 'a job on hold too long is escalated');

select pg_temp.act_as((select admin from t));
select public.fn_save_escalation_rule(null, 'P3 overdue by two days', 'overdue', 'P3', 2880,
  false, false, true, false, true, true, 75, false);
select pg_temp.fails($$select public.fn_save_escalation_rule(null, 'Tells nobody', 'overdue', null, 0,
  false, false, false, false, false, true, 1, false)$$, 'INVALID', 'a rule must tell someone');
select public.fn_save_safety_item(null, null, 'before', 'Fire extinguisher at hand', 'always', false, 120, false);
select pg_temp.as_owner();
select pg_temp.act_as((select eng from t));
select pg_temp.fails($$select public.fn_save_escalation_rule(null, 'Mine', 'overdue', null, 0,
  true, false, false, false, false, true, 1, false)$$, 'NOT_ALLOWED', 'only administrators change escalation rules');
select pg_temp.fails($$select public.fn_save_safety_item(null, null, 'before', 'Mine', 'always', false, 1, false)$$,
  'NOT_ALLOWED', 'only administrators change the safety checklist');
select pg_temp.as_owner();

-- ---------------------------------------------------------------------------
-- Audit log and the work record read
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select mgr from t));
select pg_temp.check((select count(*) from public.fn_audit_log(null, null, null, null, null, 200, 0)) > 0,
  'the manager can read the audit log');
select pg_temp.check(exists (select 1 from public.fn_audit_log(null, null, 'job_time_corrections', null, null, 50, 0)),
  'time corrections are in the audit log');
select pg_temp.as_owner();
select pg_temp.act_as((select elec from t));
select pg_temp.check((select count(*) from public.fn_audit_log(null, null, null, null, null, 50, 0)) = 0,
  'electricians cannot read the audit log');
select pg_temp.check((
  select jsonb_array_length(w -> 'reviews') = 3 and jsonb_array_length(w -> 'submissions') = 2
    and jsonb_array_length(w -> 'records') = 1 and w ? 'time' and w ? 'safety'
  from (select public.fn_job_work((select job1 from t)) as w) x
), 'the work record read returns time, safety, log, submissions and reviews');
select pg_temp.as_owner();

rollback;
