-- Behaviour checks for Job Cards Version 2 (0012_v2_core, 0013_v2_workflow):
-- requests, the job card lifecycle, permissions, notifications, dashboard and
-- search, and that Version 1 is left as it was.
-- Runs in a transaction and rolls back.
begin;

create function pg_temp.act_as(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

-- Back to the database owner with nobody signed in.
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

-- Expects p_sql to fail with an error starting with p_code ('' = any error).
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

-- People
insert into auth.users (id, email, raw_user_meta_data) values
  ('40000000-0000-0000-0000-000000000001', 'jc-elec@test', '{"full_name":"Elec Kam"}'),
  ('40000000-0000-0000-0000-000000000002', 'jc-eng@test', '{"full_name":"Eng Kam"}'),
  ('40000000-0000-0000-0000-000000000003', 'jc-elec-sel@test', '{"full_name":"Elec Sel"}'),
  ('40000000-0000-0000-0000-000000000004', 'jc-req@test', '{"full_name":"Req Kam"}'),
  ('40000000-0000-0000-0000-000000000005', 'jc-mgr@test', '{"full_name":"Manager"}'),
  ('40000000-0000-0000-0000-000000000006', 'jc-elec2@test', '{"full_name":"Elec Kam Two"}'),
  ('40000000-0000-0000-0000-000000000007', 'jc-admin@test', '{"full_name":"Admin"}');

insert into public.user_roles (user_id, role_id, site_id)
select u.id, r.id, s.id
from (values
  ('40000000-0000-0000-0000-000000000001'::uuid, 'Technician', 'KAM'),
  ('40000000-0000-0000-0000-000000000002'::uuid, 'Supervisor', 'KAM'),
  ('40000000-0000-0000-0000-000000000003'::uuid, 'Technician', 'SEL'),
  ('40000000-0000-0000-0000-000000000004'::uuid, 'Requester', 'KAM'),
  ('40000000-0000-0000-0000-000000000005'::uuid, 'Department Manager', null),
  ('40000000-0000-0000-0000-000000000006'::uuid, 'Technician', 'KAM'),
  ('40000000-0000-0000-0000-000000000007'::uuid, 'Admin', null)
) as u (id, role, site)
join public.roles r on r.name = u.role
left join public.sites s on s.code = u.site;

create temp table t as select
  (select id from public.sites where code = 'KAM') kam,
  (select id from public.sites where code = 'SEL') sel,
  (select id from public.departments where code = 'PROD') prod,
  '40000000-0000-0000-0000-000000000001'::uuid elec,
  '40000000-0000-0000-0000-000000000002'::uuid eng,
  '40000000-0000-0000-0000-000000000003'::uuid elec_sel,
  '40000000-0000-0000-0000-000000000004'::uuid req,
  '40000000-0000-0000-0000-000000000005'::uuid mgr,
  '40000000-0000-0000-0000-000000000006'::uuid elec2,
  '40000000-0000-0000-0000-000000000007'::uuid admin,
  '50000000-0000-0000-0000-000000000001'::uuid req1,
  '50000000-0000-0000-0000-000000000002'::uuid req2,
  '51000000-0000-0000-0000-000000000001'::uuid job1,
  '51000000-0000-0000-0000-000000000002'::uuid job2,
  '51000000-0000-0000-0000-000000000003'::uuid job3,
  '51000000-0000-0000-0000-000000000004'::uuid job4;
grant select on t to authenticated;

-- Reference data
select pg_temp.check((select count(*) from public.roles where name in ('Technician', 'Supervisor',
  'Admin', 'Department Manager', 'Requester', 'Storekeeper')) = 6, 'v2 roles are added beside Version 1''s');
select pg_temp.check(public._user_can((select elec from t), 'jobs.view', (select kam from t))
  and public._user_can((select elec from t), 'jc.execute', (select kam from t)),
  'a technician keeps the jobs board and works job cards');
select pg_temp.check(to_regclass('public.jobs') is not null and to_regclass('public.job_card_comments') is not null
  and to_regclass('public.legacy_jobs') is null, 'Version 1 tables are untouched');
select pg_temp.check((select count(*) from public.priority_levels) = 4, 'four priority levels');
select pg_temp.check(not exists (
  select 1 from public.role_permissions rp join public.roles r on r.id = rp.role_id
  where r.name = 'Admin' and rp.permission_code = 'jc.self_approve'
), 'administrators do not approve their own work by default');

-- The administrator names the P1 escalation contact for Kamativi
select pg_temp.act_as((select admin from t));
select public.fn_save_escalation_contact(null, (select kam from t), 'P1', (select mgr from t), false);
select pg_temp.check((select count(*) from public.escalation_contacts where user_id = (select mgr from t)) = 1,
  'admin adds an escalation contact');
reset role;

-- ---------------------------------------------------------------------------
-- Requests from another department
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select req from t));
select public.fn_submit_request((select req1 from t), (select kam from t), null, 'Packing shed', (select prod from t),
  'Req Kam', '0771 000 000', null, 'Conveyor 3 motor', 'Conveyor 3 tripping',
  'Motor trips on start-up since this morning.', 'reduced_output');
select pg_temp.check((select request_no from public.service_requests where id = (select req1 from t)) ~ '^EL-SR-[0-9]{4}-[0-9]{4,}$',
  'request gets an EL-SR number');
select pg_temp.check((select status from public.service_requests where id = (select req1 from t)) = 'submitted',
  'request is submitted');
select pg_temp.check((select count(*) from public.job_cards) = 0, 'requester cannot see job cards');
select pg_temp.fails($$select public.fn_register_job_card(gen_random_uuid(), null, (select kam from t), null, 'Shed', null,
  'Someone', null, null, null, null, null, null, 'A title', 'A long description', 'minor', 'P3', null)$$,
  'NOT_ALLOWED', 'requester cannot register job cards');
select public.fn_submit_request((select req2 from t), (select kam from t), null, 'Office 4', null, 'Req Kam', null, null,
  null, 'Aircon isolator', 'The aircon isolator sparks when switched.', 'safety_hazard');
reset role;

select pg_temp.act_as((select elec from t));
select public.fn_triage_request((select req2 from t), 'return', 'Which office block?');
select pg_temp.check((select status from public.service_requests where id = (select req2 from t)) = 'returned',
  'triage returns a request for more information');
reset role;

select pg_temp.act_as((select req from t));
select public.fn_resubmit_request((select req2 from t), 'Aircon isolator',
  'The aircon isolator in block A office 4 sparks when switched.', 'safety_hazard', 'Block A, office 4');
select pg_temp.check((select status from public.service_requests where id = (select req2 from t)) = 'submitted',
  'requester answers and resubmits');
reset role;

-- ---------------------------------------------------------------------------
-- Stage 1: an electrician registers a job card directly (Test 1)
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select elec from t));
select public.fn_register_job_card((select job1 from t), null, (select kam from t), null, 'MCC room 2',
  now() - interval '10 minutes', 'Shift foreman', null, null, 'MCC-2 panel', 'MCC-02', null, null,
  'MCC panel 2 isolator damaged', 'Isolator handle broken; panel is still live.', 'minor', 'P3', null);
select pg_temp.check((select number from public.job_cards where id = (select job1 from t)) ~ '^EL-JC-[0-9]{4}-[0-9]{4,}$',
  'job card gets an EL-JC number');
select pg_temp.check((select status from public.job_cards where id = (select job1 from t)) = 'registered',
  'new job card is registered');
select pg_temp.check((select received_at from public.job_cards where id = (select job1 from t)) = now() - interval '10 minutes',
  'time received is recorded');
select pg_temp.check((select registered_by from public.job_cards where id = (select job1 from t)) = (select elec from t),
  'the person who registered it is recorded');
select pg_temp.check((select target_completion_at - received_at from public.job_cards where id = (select job1 from t))
  = interval '4320 minutes', 'the deadline comes from the priority target');
select pg_temp.check(
  (public.fn_register_job_card((select job1 from t), null, (select kam from t), null, 'MCC room 2', null, 'Shift foreman',
    null, null, null, null, null, null, 'MCC panel 2 isolator damaged', 'Isolator handle broken; panel is still live.',
    'minor', 'P3', null)).number = (select number from public.job_cards where id = (select job1 from t)),
  'repeating a registration returns the first job card');
select pg_temp.fails($$select public.fn_register_job_card(gen_random_uuid(), null, (select kam from t), null, 'Shed', null,
  'Foreman', null, null, null, null, null, null, 'Title ok', '', 'minor', 'P3', null)$$, 'INVALID', 'description is required');
select pg_temp.fails($$select public.fn_register_job_card(gen_random_uuid(), null, (select kam from t), null, null, null,
  'Foreman', null, null, null, null, null, null, 'Title ok', 'Long enough description', 'minor', 'P3', null)$$,
  'INVALID', 'work location is required');
select pg_temp.fails($$select public.fn_register_job_card(gen_random_uuid(), null, (select kam from t), null, 'Shed', null,
  '', null, null, null, null, null, null, 'Title ok', 'Long enough description', 'minor', 'P3', null)$$,
  'INVALID', 'the reporting person is required');
select pg_temp.fails($$select public.fn_register_job_card(gen_random_uuid(), null, (select kam from t), null, 'Shed', null,
  'Foreman', null, null, null, null, null, null, 'Title ok', 'Long enough description', 'minor', 'P9', null)$$,
  'INVALID', 'unknown priority is rejected');
select pg_temp.fails($$select public.fn_register_job_card(gen_random_uuid(), null, (select sel from t), null, 'Shed', null,
  'Foreman', null, null, null, null, null, null, 'Title ok', 'Long enough description', 'minor', 'P3', null)$$,
  'NOT_ALLOWED', 'electrician cannot register at another site');
select pg_temp.fails($$select public.fn_return_for_clarification((select job1 from t), 'Which one?')$$,
  'NOT_ALLOWED', 'electrician cannot assess');
select pg_temp.fails($$select public.fn_assign_job_card((select job1 from t), (select elec from t), null, null, null, null,
  null, null, null, null, null, null)$$, 'NOT_ALLOWED', 'electrician cannot assign');
select pg_temp.fails($$insert into public.job_cards (number, source, site_id, location, received_at, reporter_name,
  title, description, priority) values ('X-1', 'direct', (select kam from t), 'x', now(), 'Someone', 'Title',
  'Description', 'P3')$$, '', 'the app cannot write job cards directly');
reset role;

-- A request becomes a job card only when registered, and is not auto-assigned
select pg_temp.act_as((select eng from t));
select public.fn_register_job_card((select job2 from t), (select req1 from t), null, null, null, null, null, null,
  null, null, null, null, null, null, null, null, 'P2', null);
select pg_temp.check((select source from public.job_cards where id = (select job2 from t)) = 'request',
  'request becomes a job card');
select pg_temp.check((select status = 'registered' and responsible_id is null from public.job_cards where id = (select job2 from t)),
  'registered request is not assigned automatically');
select pg_temp.check((select status = 'registered' and job_card_id = (select job2 from t)
  from public.service_requests where id = (select req1 from t)), 'request is marked registered and linked');
select pg_temp.check((select received_at from public.job_cards where id = (select job2 from t))
  = (select submitted_at from public.service_requests where id = (select req1 from t)),
  'time received is when the request was submitted');
reset role;
select pg_temp.check(exists (select 1 from public.notifications
  where user_id = (select req from t) and link = 'servicerequest:' || (select req1 from t)),
  'requester is told the request was registered');

-- ---------------------------------------------------------------------------
-- Stage 2: clarification and assessment
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select eng from t));
select pg_temp.fails($$select public.fn_return_for_clarification((select job1 from t), '')$$,
  'INVALID', 'returning for clarification needs a reason');
select public.fn_return_for_clarification((select job1 from t), 'Main incomer or feeder isolator?');
select pg_temp.check((select status from public.job_cards where id = (select job1 from t)) = 'awaiting_clarification',
  'returned for clarification');
reset role;

select pg_temp.act_as((select elec from t));
select public.fn_provide_clarification((select job1 from t), 'Main incomer isolator.');
select pg_temp.check((select status from public.job_cards where id = (select job1 from t)) = 'registered',
  'clarified job card is registered again');
reset role;

select pg_temp.act_as((select eng from t));
select public.fn_assess_job_card((select job1 from t), true, 'corrective', 'moderate', 'high', 'Panel live', 'degraded',
  'LV authorised', 1, null, true, true, true, 2.5, null, null, null, 'Replace isolator handle');
select pg_temp.check((select status from public.job_cards where id = (select job1 from t)) = 'awaiting_assignment',
  'assessed job card awaits assignment');
select pg_temp.check((select assessed_by = (select eng from t) and maintenance_type = 'corrective' and loto_required
  from public.job_cards where id = (select job1 from t)), 'assessment is recorded');

-- ---------------------------------------------------------------------------
-- Stage 3: assignment (Test 2)
-- ---------------------------------------------------------------------------
select pg_temp.fails($$select public.fn_assign_job_card((select job1 from t), (select req from t), null, null, null, null,
  null, null, null, null, null, null)$$, 'INVALID', 'a requester cannot be assigned');
select pg_temp.fails($$select public.fn_assign_job_card((select job1 from t), (select elec_sel from t), null, null, null,
  null, null, null, null, null, null, null)$$, 'INVALID', 'an electrician from another site cannot be assigned');
select public.fn_assign_job_card((select job1 from t), (select elec from t), array[(select elec2 from t)],
  now() + interval '1 hour', null, 3, 'Isolator handle', 'Insulated tools', 'Lock out the incomer', null, null, null);
select pg_temp.check((select status = 'assigned' and responsible_id = (select elec from t)
  from public.job_cards where id = (select job1 from t)), 'job card assigned to the electrician');
select pg_temp.check((select count(*) from public.job_assignments
  where job_card_id = (select job1 from t) and ended_at is null) = 2, 'responsible and supporting people recorded');
select pg_temp.check((select responsible_open from public.fn_workload((select kam from t))
  where user_id = (select elec from t)) = 1, 'workload shows the new assignment');
reset role;
select pg_temp.check(exists (select 1 from public.notifications where user_id = (select elec from t)
  and type = 'assigned' and link = 'jobcard:' || (select job1 from t)), 'electrician is notified of the assignment');

-- ---------------------------------------------------------------------------
-- Stage 4: the electrician accepts and works
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select elec from t));
select pg_temp.check(exists (select 1 from public.v_job_cards
  where id = (select job1 from t) and responsible_id = auth.uid()), 'the job card shows in the electrician''s jobs');
select public.fn_accept_job_card((select job1 from t));
select pg_temp.check((select status = 'accepted' and accepted_at is not null and responded_at is not null
  from public.job_cards where id = (select job1 from t)), 'acceptance is recorded and ends the response time');
select public.fn_set_job_card_status((select job1 from t), 'in_progress', null);
select pg_temp.check((select first_started_at is not null from public.job_cards where id = (select job1 from t)),
  'work start is recorded');
select pg_temp.fails($$select public.fn_set_job_card_status((select job1 from t), 'on_hold', null)$$,
  'INVALID', 'a hold needs a reason');
select public.fn_set_job_card_status((select job1 from t), 'awaiting_materials', 'Isolator handle from stores');
select pg_temp.check((select status = 'awaiting_materials' and status_reason = 'Isolator handle from stores'
  from public.job_cards where id = (select job1 from t)), 'waiting for materials with a reason');
select public.fn_set_job_card_status((select job1 from t), 'in_progress', null);
select pg_temp.fails($$select public.fn_submit_job_card((select job1 from t), 'Replaced the handle and tested it.',
  'Cracked handle', 'Fitted new handle', 'operational', false)$$, 'INVALID', 'submitting needs the checks confirmed');
select public.fn_submit_job_card((select job1 from t), 'Replaced the handle and tested it.', 'Cracked handle',
  'Fitted new handle', 'operational', true);
select pg_temp.check((select status = 'awaiting_review' and performed_by = (select elec from t)
  from public.job_cards where id = (select job1 from t)), 'submitted for engineering review');
select pg_temp.fails($$select public.fn_review_job_card((select job1 from t), 'approve', null)$$,
  'NOT_ALLOWED', 'electrician cannot approve closure');
reset role;

-- ---------------------------------------------------------------------------
-- Stage 5: reject once, then approve; reopen keeps the history (Test 6)
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select eng from t));
select pg_temp.fails($$select public.fn_review_job_card((select job1 from t), 'reject', '')$$,
  'INVALID', 'rejecting needs a reason');
select public.fn_review_job_card((select job1 from t), 'reject', 'Add the insulation test reading');
select pg_temp.check((select status from public.job_cards where id = (select job1 from t)) = 'accepted',
  'rejected work goes back to the electrician');
reset role;

select pg_temp.act_as((select elec from t));
select public.fn_set_job_card_status((select job1 from t), 'in_progress', null);
select public.fn_submit_job_card((select job1 from t), 'Replaced the handle; insulation test 500 MOhm.',
  'Cracked handle', 'Fitted new handle', 'operational', true);
reset role;

select pg_temp.act_as((select eng from t));
select public.fn_review_job_card((select job1 from t), 'approve', 'Good work');
select pg_temp.check((select status = 'closed' and closed_at is not null and verified_by = (select eng from t)
  from public.job_cards where id = (select job1 from t)), 'approved job card is closed');
select pg_temp.check((select count(*) from public.job_closures where job_card_id = (select job1 from t)) = 1,
  'the closure is recorded');
select pg_temp.check(exists (select 1 from public.job_status_history where job_card_id = (select job1 from t)
  and from_status = 'awaiting_review' and to_status = 'accepted' and reason = 'Add the insulation test reading'),
  'the rejection stays in the history');
select pg_temp.fails($$select public.fn_cancel_job_card((select job1 from t), 'No longer needed')$$,
  'INVALID', 'closed job cards cannot be cancelled');
select public.fn_reopen_job_card((select job1 from t), 'Handle failed again');
select pg_temp.check((select status = 'reopened' and closed_at is null from public.job_cards where id = (select job1 from t)),
  'job card reopened');
select pg_temp.check((select count(*) from public.job_closures where job_card_id = (select job1 from t)) = 1,
  'reopening keeps the earlier closure');
select pg_temp.check((select count(*) from public.fn_job_card_timeline((select job1 from t))) > 10,
  'the timeline shows the whole history');
reset role;

-- Nobody approves their own work (Test 10)
select pg_temp.act_as((select eng from t));
select public.fn_assess_job_card((select job2 from t), true, 'reactive', 'major', 'medium', null, 'degraded', null, null,
  null, false, false, false, null, null, null, null, null);
select public.fn_assign_job_card((select job2 from t), (select eng from t), null, null, null, null, null, null, null,
  null, null, null);
select public.fn_set_job_card_status((select job2 from t), 'in_progress', null);
select pg_temp.check((select accepted_at is not null from public.job_cards where id = (select job2 from t)),
  'starting work accepts the job card');
select public.fn_submit_job_card((select job2 from t), 'Reset the overload and tested the motor.', 'Overload tripped',
  'Reset and adjusted', 'operational', true);
select pg_temp.fails($$select public.fn_review_job_card((select job2 from t), 'approve', null)$$,
  'NOT_ALLOWED', 'nobody approves closure of their own work');
reset role;

select pg_temp.act_as((select admin from t));
select public.fn_review_job_card((select job2 from t), 'approve', null);
select pg_temp.check((select status = 'closed' and not self_approved from public.job_cards where id = (select job2 from t)),
  'someone else approves the closure');
reset role;
select pg_temp.check(exists (select 1 from public.notifications
  where user_id = (select req from t) and title like 'Your request is complete%'),
  'requester is told the work is complete');

-- ---------------------------------------------------------------------------
-- Overdue comes from the deadline; P1 is critical and escalates (Tests 4, 5)
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select elec from t));
select public.fn_register_job_card((select job4 from t), null, (select kam from t), null, 'Workshop',
  now() - interval '80 days', 'Workshop lead', null, null, 'Socket outlets', null, null, null,
  'Workshop sockets dead', 'Three socket outlets dead in the workshop.', 'minor', 'P4', null);
select pg_temp.check((select is_overdue and sla_state = 'overdue' from public.v_job_cards where id = (select job4 from t)),
  'a passed deadline makes a job card overdue');
reset role;

select pg_temp.act_as((select eng from t));
select public.fn_register_job_card((select job3 from t), null, (select kam from t), null, 'Main substation', null,
  'Control room', null, null, 'Transformer T1', null, null, null,
  'T1 Buchholz alarm', 'Buchholz relay alarm on transformer T1.', 'safety_hazard', 'P1', null);
select pg_temp.check((select is_critical_open and not is_overdue from public.v_job_cards where id = (select job3 from t)),
  'P1 is critical but not overdue before its deadline');
select pg_temp.check(((public.fn_dashboard((select kam from t), now() - interval '100 days', now() + interval '1 day'))
  -> 'cards' ->> 'critical')::int >= 1, 'the dashboard counts the critical job card');
select pg_temp.check(((public.fn_dashboard((select kam from t), now() - interval '100 days', now() + interval '1 day'))
  -> 'cards' ->> 'overdue')::int >= 1, 'the dashboard counts the overdue job card');
select pg_temp.check(jsonb_array_length(public.fn_dashboard((select kam from t), null, null) -> 'alerts' -> 'critical') >= 1,
  'the critical job card is in the alerts');
reset role;
select pg_temp.check(exists (select 1 from public.notifications where user_id = (select mgr from t)
  and type = 'critical' and link = 'jobcard:' || (select job3 from t)), 'the escalation contact is alerted at once');
select pg_temp.check(exists (select 1 from public.notifications where user_id = (select admin from t)
  and type = 'critical' and link = 'jobcard:' || (select job3 from t)), 'engineers for the site are alerted');
select pg_temp.check(not exists (select 1 from public.notifications where user_id = (select elec from t)
  and type = 'critical'), 'electricians are not sent escalation alerts');

-- ---------------------------------------------------------------------------
-- Permissions and administration (Test 10)
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select elec_sel from t));
select pg_temp.fails($$select public.fn_dashboard((select kam from t), null, null)$$,
  'NOT_ALLOWED', 'the dashboard is limited to the caller''s sites');
select pg_temp.check((select count(*) from public.job_cards where site_id = (select kam from t)) = 0,
  'job cards at other sites are hidden');
reset role;

select pg_temp.act_as((select elec from t));
select pg_temp.fails($$select public.fn_save_settings('Africa/Harare', 'EL-JC', 'EL-SR', 4, true, 'acknowledged', 25, 48,
  true, 'Bravura', 'Electrical Department', null)$$, 'NOT_ALLOWED', 'electrician cannot change settings');
select pg_temp.check((select count(*) from public.escalation_contacts) = 0, 'electrician cannot read escalation contacts');
reset role;

select pg_temp.act_as((select admin from t));
select public.fn_save_priority('P3', 'Medium', null, 120, 2880);
select pg_temp.check((select targets_confirmed and response_minutes = 120 from public.priority_levels where code = 'P3'),
  'admin confirms priority targets');
select pg_temp.fails($$select public.fn_save_priority('P3', 'Medium', null, 600, 60)$$,
  'INVALID', 'a completion target cannot be shorter than the response target');
select pg_temp.fails($$select public.fn_save_settings('Mars/Base', 'EL-JC', 'EL-SR', 4, true, 'acknowledged', 25, 48, true,
  'Bravura', 'Electrical Department', null)$$, 'INVALID', 'unknown time zones are rejected');
reset role;

-- Assets come from Version 1's register; v2 sees them as asset numbers
select pg_temp.as_owner();
insert into public.assets (site_id, tag, name) values ((select kam from t), 'gen-01x', 'Standby generator 1');
select pg_temp.check((select asset_no = 'GEN-01X' and operational_status = 'in_service' from public.assets
  where tag = 'gen-01x'), 'a register tag is the v2 asset number');
select pg_temp.act_as((select req from t));
select pg_temp.check(exists (select 1 from public.assets where tag = 'gen-01x'),
  'requesters see the equipment they can raise requests about');
reset role;

-- ---------------------------------------------------------------------------
-- Search, requester tracking and comments
-- ---------------------------------------------------------------------------
select pg_temp.act_as((select eng from t));
select pg_temp.check(exists (select 1 from public.fn_search('isolator') where kind = 'job_card' and id = (select job1 from t)),
  'search finds job cards by their text');
select pg_temp.check(exists (select 1 from public.fn_search('MCC-02') where kind = 'job_card'),
  'search finds job cards by asset number');
select pg_temp.check(exists (select 1 from public.fn_search(
  (select request_no from public.service_requests where id = (select req1 from t))) where kind = 'request'),
  'search finds requests by number');
select pg_temp.check(not exists (select 1 from public.fn_search('x')), 'one-letter searches return nothing');
reset role;

select pg_temp.act_as((select req from t));
select pg_temp.check((public.fn_request_tracking((select req1 from t)) -> 'job' ->> 'status') = 'closed',
  'the requester follows the job card status');
select public.fn_comment_job_card(gen_random_uuid(), (select job2 from t), 'Thanks, the conveyor runs fine.',
  'instruction', 'internal', null);
select pg_temp.check((select visibility from public.job_card_comments where body like 'Thanks, the conveyor%') is null,
  'the requester cannot read job card comments directly');
select pg_temp.check(jsonb_array_length(public.fn_request_tracking((select req1 from t)) -> 'updates') >= 1,
  'the requester sees requester-visible updates');
select pg_temp.fails($$select public.fn_request_tracking((select job1 from t))$$,
  'NOT_FOUND', 'requesters only see their own requests');
reset role;
select pg_temp.check((select visibility = 'requester' and kind = 'comment' from public.job_card_comments
  where body = 'Thanks, the conveyor runs fine.'), 'requester comments are plain, requester-visible comments');

select pg_temp.act_as((select elec from t));
select public.fn_comment_job_card(gen_random_uuid(), (select job1 from t), 'Please check the spare handle stock',
  'assistance', 'internal', array[(select eng from t)]);
select pg_temp.fails($$select public.fn_comment_job_card(gen_random_uuid(), (select job1 from t), 'Hi', 'comment',
  'internal', array[(select req from t)])$$, 'INVALID', 'only people who can see the job card can be mentioned');
reset role;
select pg_temp.check(exists (select 1 from public.notifications where user_id = (select eng from t) and type = 'mentioned'),
  'mentioned people are notified');

select pg_temp.check((select count(*) from public.schema_migrations where filename in ('0012_v2_core.sql',
  '0013_v2_workflow.sql')) = 2, 'migrations are logged');

rollback;
