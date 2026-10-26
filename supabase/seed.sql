-- Local/CI data only: `supabase db reset` and `supabase start` load this file;
-- `supabase db push` (production) never does. Sites, roles and permissions
-- come from migration 0001.
--
-- Test users (password for all: Passw0rd!)
--   admin@bravura.test       Admin, all sites
--   supervisor@bravura.test  Supervisor, Kamativi
--   tech@bravura.test        Technician, Kamativi + Selous
--   store@bravura.test       Storekeeper, Kamativi

insert into public.areas (site_id, name)
select s.id, a.name
from public.sites s
join (values
  ('KAM', 'Plant – MCC room'),
  ('KAM', 'Plant – Crusher'),
  ('KAM', 'Camp – Block C'),
  ('KAM', 'Workshop'),
  ('SEL', 'Main substation'),
  ('SEL', 'Offices'),
  ('MAN', 'Pump station'),
  ('HRE', 'Head office')
) as a (site_code, name) on a.site_code = s.code;

with users (id, email, full_name, home) as (
  values
    ('10000000-0000-0000-0000-000000000001'::uuid, 'admin@bravura.test', 'Test Admin', 'HRE'),
    ('10000000-0000-0000-0000-000000000002'::uuid, 'supervisor@bravura.test', 'Test Supervisor', 'KAM'),
    ('10000000-0000-0000-0000-000000000003'::uuid, 'tech@bravura.test', 'Test Technician', 'KAM'),
    ('10000000-0000-0000-0000-000000000004'::uuid, 'store@bravura.test', 'Test Storekeeper', 'KAM')
), inserted as (
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  )
  select
    '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated',
    u.email, extensions.crypt('Passw0rd!', extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}',
    jsonb_build_object('full_name', u.full_name), now(), now(), '', '', '', ''
  from users u
  returning id, email
)
insert into auth.identities (
  id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at
)
select gen_random_uuid(), i.id, i.id::text, 'email',
  jsonb_build_object('sub', i.id::text, 'email', i.email, 'email_verified', true),
  now(), now(), now()
from inserted i;

update public.profiles p
set home_site_id = s.id
from (values
  ('10000000-0000-0000-0000-000000000001'::uuid, 'HRE'),
  ('10000000-0000-0000-0000-000000000002'::uuid, 'KAM'),
  ('10000000-0000-0000-0000-000000000003'::uuid, 'KAM'),
  ('10000000-0000-0000-0000-000000000004'::uuid, 'KAM')
) as h (user_id, site_code)
join public.sites s on s.code = h.site_code
where p.id = h.user_id;

insert into public.user_roles (user_id, role_id, site_id)
select g.user_id, r.id, s.id
from (values
  ('10000000-0000-0000-0000-000000000001'::uuid, 'Admin', null),
  ('10000000-0000-0000-0000-000000000002'::uuid, 'Supervisor', 'KAM'),
  ('10000000-0000-0000-0000-000000000003'::uuid, 'Technician', 'KAM'),
  ('10000000-0000-0000-0000-000000000003'::uuid, 'Technician', 'SEL'),
  ('10000000-0000-0000-0000-000000000004'::uuid, 'Storekeeper', 'KAM')
) as g (user_id, role_name, site_code)
join public.roles r on r.name = g.role_name
left join public.sites s on s.code = g.site_code;

select public.fn_notify(
  '10000000-0000-0000-0000-000000000003', s.id, 'general',
  'Welcome to Bravura Electrical', 'This is a test notification from seed.sql.', null
)
from public.sites s where s.code = 'KAM';

-- Sample jobs at Kamativi in different states.
insert into public.jobs (site_id, area_id, code, title, description, priority, status,
  waiting_reason, due_at, created_by, assignee_id, taken_at, created_at)
select s.id, a.id, public.next_code(s.id, 'J'), j.title, j.descr, j.priority, j.status,
  j.waiting, now() + j.due, '10000000-0000-0000-0000-000000000002'::uuid,
  j.assignee, case when j.assignee is null then null else now() end, now() - j.age
from public.sites s
join (values
  ('Replace isolator on MCC panel 3', 'Isolator handle broken; panel is live.', 'urgent', 'open',
    null, interval '4 hours', null::uuid, 'Plant – MCC room', interval '2 hours'),
  ('Flickering lights in Block C corridor', null, 'normal', 'taken',
    null, interval '2 days', '10000000-0000-0000-0000-000000000003'::uuid, 'Camp – Block C', interval '1 day'),
  ('Crusher motor overheating', 'Trips after ~40 minutes under load.', 'urgent', 'in_progress',
    null, interval '-3 hours', '10000000-0000-0000-0000-000000000003'::uuid, 'Plant – Crusher', interval '6 hours'),
  ('Workshop socket outlets not working', null, 'low', 'waiting',
    'Waiting for 16A breakers from Harare', interval '5 days', '10000000-0000-0000-0000-000000000003'::uuid,
    'Workshop', interval '3 days'),
  ('Install floodlight at gate', null, 'normal', 'open',
    null, null, null::uuid, null, interval '30 minutes')
) as j (title, descr, priority, status, waiting, due, assignee, area, age) on true
left join public.areas a on a.site_id = s.id and a.name = j.area
where s.code = 'KAM';

-- A few assets at Kamativi; the crusher and MCC jobs point at theirs.
insert into public.assets (site_id, area_id, tag, name, kind, make_model)
select s.id, a.id, x.tag, x.name, x.kind, x.make
from public.sites s
join (values
  ('CR-M01', 'Primary crusher motor', 'Motor', 'WEG W22 75 kW', 'Plant – Crusher'),
  ('MCC-03', 'MCC panel 3', 'MCC / panel', null, 'Plant – MCC room'),
  ('TX-01', 'Plant transformer 1', 'Transformer', '1 MVA 11/0.4 kV', 'Plant – MCC room'),
  ('DB-C', 'Block C distribution board', 'Distribution board', null, 'Camp – Block C')
) as x (tag, name, kind, make, area) on true
left join public.areas a on a.site_id = s.id and a.name = x.area
where s.code = 'KAM';

update public.jobs j set asset_id = x.id, isolation_required = true
from public.assets x
where x.tag = 'CR-M01' and j.title = 'Crusher motor overheating';
update public.jobs j set asset_id = x.id, isolation_required = true
from public.assets x
where x.tag = 'MCC-03' and j.title = 'Replace isolator on MCC panel 3';

-- Tools at Kamativi: two in store, one out with the technician.
insert into public.tools (site_id, code, name, kind, serial_no, calibration_due)
select s.id, public.next_code(s.id, 'T'), x.name, x.kind, x.serial, x.cal
from public.sites s
join (values
  ('Megger MIT420 insulation tester', 'Tester', 'MIT420-1187', current_date + 5),
  ('Fluke 117 multimeter', 'Tester', 'FL117-2231', current_date + 200),
  ('Makita cordless drill', 'Power tool', null, null::date)
) as x (name, kind, serial, cal) on true
where s.code = 'KAM';

with t as (select id from public.tools where name = 'Fluke 117 multimeter')
insert into public.tool_issues (tool_id, issued_to, issued_by, issued_at, due_back)
select t.id, '10000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000004',
  now() - interval '2 days', current_date + 3
from t;
update public.tools set holder_id = '10000000-0000-0000-0000-000000000003',
  issued_at = now() - interval '2 days', due_back = current_date + 3
where name = 'Fluke 117 multimeter';

-- ===========================================================================
-- Job Cards Version 2 (migrations 0010-0012). The people above keep their
-- roles; v2 adds a second technician, a department manager and a requester.
--   tech2@bravura.test      Technician, Kamativi
--   manager@bravura.test    Department Manager, all sites (P1 escalation contact)
--   requester@bravura.test  Requester (Production), Kamativi
-- ===========================================================================
insert into public.areas (site_id, name)
select s.id, a.name
from public.sites s
join (values
  ('KAM', 'Plant – Conveyors'),
  ('KAM', 'Main substation'),
  ('KAM', 'Pump house'),
  ('KAM', 'Packing shed')
) as a (site_code, name) on a.site_code = s.code;

with users (id, email, full_name) as (
  values
    ('10000000-0000-0000-0000-000000000005'::uuid, 'tech2@bravura.test', 'Test Technician Two'),
    ('10000000-0000-0000-0000-000000000006'::uuid, 'manager@bravura.test', 'Test Manager'),
    ('10000000-0000-0000-0000-000000000007'::uuid, 'requester@bravura.test', 'Test Requester')
), inserted as (
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  )
  select
    '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated',
    u.email, extensions.crypt('Passw0rd!', extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}',
    jsonb_build_object('full_name', u.full_name), now(), now(), '', '', '', ''
  from users u
  returning id, email
)
insert into auth.identities (
  id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at
)
select gen_random_uuid(), i.id, i.id::text, 'email',
  jsonb_build_object('sub', i.id::text, 'email', i.email, 'email_verified', true),
  now(), now(), now()
from inserted i;

update public.profiles p
set home_site_id = s.id, department_id = d.id
from (values
  ('10000000-0000-0000-0000-000000000001'::uuid, 'HRE', 'ELEC'),
  ('10000000-0000-0000-0000-000000000002'::uuid, 'KAM', 'ELEC'),
  ('10000000-0000-0000-0000-000000000003'::uuid, 'KAM', 'ELEC'),
  ('10000000-0000-0000-0000-000000000004'::uuid, 'KAM', 'ELEC'),
  ('10000000-0000-0000-0000-000000000005'::uuid, 'KAM', 'ELEC'),
  ('10000000-0000-0000-0000-000000000006'::uuid, 'HRE', 'ELEC'),
  ('10000000-0000-0000-0000-000000000007'::uuid, 'KAM', 'PROD')
) as h (user_id, site_code, dept_code)
join public.sites s on s.code = h.site_code
join public.departments d on d.code = h.dept_code
where p.id = h.user_id;

insert into public.user_roles (user_id, role_id, site_id)
select g.user_id, r.id, s.id
from (values
  ('10000000-0000-0000-0000-000000000005'::uuid, 'Technician', 'KAM'),
  ('10000000-0000-0000-0000-000000000006'::uuid, 'Department Manager', null),
  ('10000000-0000-0000-0000-000000000007'::uuid, 'Requester', 'KAM')
) as g (user_id, role_name, site_code)
join public.roles r on r.name = g.role_name
left join public.sites s on s.code = g.site_code;

insert into public.escalation_contacts (site_id, priority_code, user_id)
values (null, 'P1', '10000000-0000-0000-0000-000000000006');

-- Equipment for v2's job cards, in the shared asset register.
insert into public.assets (
  tag, name, kind, make_model, category_id, site_id, area_id, location, manufacturer, model,
  electrical_rating, voltage_v, current_a, power_kw, installed_on, operational_status, criticality,
  department_id
)
select x.no, x.name, x.cat, nullif(concat_ws(' ', x.make, x.model), ''), c.id, s.id, a.id, x.loc,
  x.make, x.model, x.rating, x.v, x.i, x.kw, x.installed, x.status, x.crit, d.id
from (values
  ('KAM-GEN-01', 'Standby generator G1', 'Generators', 'KAM', 'Main substation', 'Generator house',
    'Caterpillar', 'C18', '660 kVA', 400.0, 952.0, 528.0, date '2019-03-14', 'standby', 'high', 'ELEC'),
  ('KAM-GEN-02', 'Standby generator G2', 'Generators', 'KAM', 'Main substation', 'Generator house',
    'Caterpillar', 'C15', '500 kVA', 400, 722, 400, date '2019-03-14', 'standby', 'high', 'ELEC'),
  ('KAM-TX-01', 'Transformer T1 11/0.4 kV', 'Transformers', 'KAM', 'Main substation', 'Bay 1',
    'ABB', 'ONAN 1000', '1000 kVA, 11/0.4 kV', 11000, 52, 1000, date '2016-08-02', 'in_service', 'high', 'ELEC'),
  ('KAM-TX-02', 'Transformer T2 11/0.4 kV', 'Transformers', 'KAM', 'Main substation', 'Bay 2',
    'ABB', 'ONAN 1000', '1000 kVA, 11/0.4 kV', 11000, 52, 1000, date '2016-08-02', 'in_service', 'high', 'ELEC'),
  ('KAM-MCC-01', 'MCC-1 crusher', 'Motor control centres', 'KAM', 'Plant – MCC room', 'Row A',
    'Schneider', 'Okken', '1600 A', 400, 1600, null, date '2017-05-20', 'in_service', 'high', 'ELEC'),
  ('KAM-MCC-02', 'MCC-2 conveyors', 'Motor control centres', 'KAM', 'Plant – MCC room', 'Row B',
    'Schneider', 'Okken', '1250 A', 400, 1250, null, date '2017-05-20', 'in_service', 'high', 'ELEC'),
  ('KAM-MTR-CR1', 'Primary crusher motor', 'Motors', 'KAM', 'Plant – Crusher', 'Crusher drive',
    'WEG', 'W22 315', '250 kW', 400, 430, 250, date '2017-06-01', 'in_service', 'high', 'PROD'),
  ('KAM-VFD-CV3', 'Conveyor 3 VFD', 'Variable frequency drives', 'KAM', 'Plant – Conveyors', 'Conveyor 3 head end',
    'ABB', 'ACS880', '90 kW', 400, 165, 90, date '2020-02-11', 'in_service', 'high', 'PROD'),
  ('KAM-MTR-CV3', 'Conveyor 3 drive motor', 'Motors', 'KAM', 'Plant – Conveyors', 'Conveyor 3 head end',
    'WEG', 'W22 280', '90 kW', 400, 160, 90, date '2020-02-11', 'in_service', 'high', 'PROD'),
  ('KAM-PMP-01', 'Raw water pump 1', 'Pumps', 'KAM', 'Pump house', null,
    'Grundfos', 'NK 125', '75 kW', 400, 135, 75, date '2018-09-30', 'in_service', 'medium', 'PROD'),
  ('KAM-PMP-02', 'Raw water pump 2', 'Pumps', 'KAM', 'Pump house', null,
    'Grundfos', 'NK 125', '75 kW', 400, 135, 75, date '2018-09-30', 'standby', 'medium', 'PROD'),
  ('KAM-DB-03', 'DB-3 workshop board', 'Distribution boards', 'KAM', 'Workshop', 'Workshop east wall',
    'Hager', null, '250 A TP&N', 400, 250, null, date '2015-04-18', 'in_service', 'medium', 'ELEC'),
  ('KAM-DB-CB', 'Block C distribution board', 'Distribution boards', 'KAM', 'Camp – Block C', null,
    'Hager', null, '100 A TP&N', 400, 100, null, date '2015-04-18', 'in_service', 'low', 'CAMP'),
  ('KAM-UPS-01', 'Control room UPS', 'UPS and battery systems', 'KAM', 'Main substation', 'Control room',
    'APC', 'Galaxy VS', '40 kVA', 400, null, 40, date '2021-07-07', 'in_service', 'high', 'ELEC'),
  ('KAM-LT-GATE', 'Main gate floodlights', 'Lighting systems', 'KAM', null, 'Main gate',
    'Philips', null, '4 x 400 W', 230, null, null, date '2014-11-03', 'in_service', 'low', 'ELEC'),
  ('KAM-CBL-PH', 'Pump house feeder cable', 'Cables and terminations', 'KAM', 'Pump house',
    'Substation to pump house', null, null, '16 mm² 4-core SWA', 400, 73, null, date '2018-09-30',
    'in_service', 'medium', 'ELEC'),
  ('KAM-ERTH-SS', 'Main substation earth grid', 'Earthing and lightning protection', 'KAM', 'Main substation', null,
    null, null, null, null, null, null, date '2016-08-02', 'in_service', 'high', 'ELEC'),
  ('SEL-TX-01', 'Selous transformer T1', 'Transformers', 'SEL', 'Main substation', null,
    'ABB', null, '500 kVA, 11/0.4 kV', 11000, 26, 500, date '2018-01-15', 'in_service', 'high', 'ELEC'),
  ('SEL-PNL-01', 'Selous main LV panel', 'Switchgear', 'SEL', 'Main substation', null,
    'Schneider', null, '800 A', 400, 800, null, date '2018-01-15', 'in_service', 'high', 'ELEC'),
  ('MAN-PMP-01', 'Manhizi borehole pump', 'Pumps', 'MAN', 'Pump station', null,
    'Grundfos', 'SP 46', '15 kW', 400, 30, 15, date '2022-03-09', 'in_service', 'medium', 'PROD')
) as x (no, name, cat, site, area, loc, make, model, rating, v, i, kw, installed, status, crit, dept)
join public.sites s on s.code = x.site
join public.asset_categories c on c.name = x.cat
left join public.areas a on a.site_id = s.id and a.name = x.area
join public.departments d on d.code = x.dept;

-- ---------------------------------------------------------------------------
-- Job cards in every state, written directly (the workflow functions need a
-- signed-in user). Times are relative to now, so there is always current work.
-- ---------------------------------------------------------------------------
create function pg_temp.seed_job(
  p_site text,
  p_area text,
  p_asset text,
  p_title text,
  p_description text,
  p_priority text,
  p_status text,
  p_age interval,
  p_responsible uuid default null,
  p_reason text default null,
  p_impact text default 'minor',
  p_type text default 'reactive'
)
returns uuid
language plpgsql
as $$
declare
  v_engineer constant uuid := '10000000-0000-0000-0000-000000000002';
  v_id uuid := gen_random_uuid();
  v_site uuid;
  v_area uuid;
  a public.assets;
  pl public.priority_levels;
  v_received timestamptz := now() - p_age;
  v_assessed boolean := p_status not in ('registered', 'awaiting_clarification');
  v_assigned boolean := p_responsible is not null;
  v_accepted boolean := p_status in ('accepted', 'in_progress', 'on_hold', 'awaiting_materials',
    'awaiting_isolation', 'awaiting_specialist', 'awaiting_production_clearance', 'awaiting_review', 'closed');
  v_started boolean := p_status in ('in_progress', 'on_hold', 'awaiting_materials', 'awaiting_isolation',
    'awaiting_specialist', 'awaiting_production_clearance', 'awaiting_review', 'closed');
  v_submitted boolean := p_status in ('awaiting_review', 'closed');
  v_submission uuid;
begin
  select id into v_site from public.sites where code = p_site;
  select id into v_area from public.areas where site_id = v_site and name = p_area;
  select * into a from public.assets where asset_no = p_asset;
  select * into pl from public.priority_levels where code = p_priority;

  insert into public.job_cards (
    id, number, source, site_id, area_id, location, received_at, registered_at, reporter_name,
    requesting_department_id, asset_id, equipment_name, equipment_asset_no, equipment_location,
    category_id, title, description, operational_impact, priority, registered_by,
    target_response_at, target_completion_at, is_critical, critical_reason, escalated_at,
    is_valid, maintenance_type, severity, safety_risk, equipment_state, assessed_by, assessed_at,
    responsible_id, assigned_by, first_assigned_at, assigned_at, accepted_at, first_started_at,
    submitted_at, closed_at, closure_approved_at, cancelled_at,
    completion_summary, findings, corrective_action, equipment_state_after, performed_by, verified_by,
    status, status_reason, created_at
  ) values (
    v_id, public._next_doc_no('jobcard', now()),
    case when p_type = 'preventive' then 'preventive' else 'direct' end,
    v_site, v_area, case when v_area is null then coalesce(a.location, p_area) end,
    v_received, v_received + interval '5 minutes', 'Shift foreman',
    (select id from public.departments where code = 'PROD'),
    a.id, a.name, a.asset_no, a.location,
    (select id from public.job_categories where name = case
      when p_type = 'preventive' then 'Preventive maintenance' else 'Electrical fault' end),
    p_title, p_description, p_impact, pl.code, v_engineer,
    v_received + make_interval(mins => pl.response_minutes),
    v_received + make_interval(mins => pl.completion_minutes),
    pl.code = 'P1',
    case when pl.code = 'P1' then 'P1 emergency' end,
    case when pl.code = 'P1' then v_received end,
    case when v_assessed then true end,
    case when v_assessed then p_type end,
    case when v_assessed then case pl.code when 'P1' then 'critical' when 'P2' then 'major' else 'moderate' end end,
    case when v_assessed then case pl.code when 'P1' then 'high' else 'medium' end end,
    case when v_assessed then case when pl.code in ('P1', 'P2') then 'out_of_service' else 'degraded' end end,
    case when v_assessed then v_engineer end,
    case when v_assessed then v_received + interval '15 minutes' end,
    p_responsible,
    case when v_assigned then v_engineer end,
    case when v_assigned then v_received + interval '20 minutes' end,
    case when v_assigned then v_received + interval '20 minutes' end,
    case when v_accepted then v_received + interval '30 minutes' end,
    case when v_started then v_received + interval '45 minutes' end,
    case when v_submitted then v_received + p_age * 0.5 end,
    case when p_status = 'closed' then v_received + p_age * 0.6 end,
    case when p_status = 'closed' then v_received + p_age * 0.6 end,
    case when p_status = 'cancelled' then v_received + p_age * 0.5 end,
    case when v_submitted then 'Work completed and tested; equipment back in service.' end,
    case when v_submitted then 'Worn component found on inspection.' end,
    case when v_submitted then 'Replaced the worn component and tested operation.' end,
    case when v_submitted then 'operational' end,
    case when v_submitted then p_responsible end,
    case when p_status = 'closed' then v_engineer end,
    p_status, p_reason, v_received
  );

  if v_assigned then
    insert into public.job_assignments (job_card_id, user_id, role, assigned_by, assigned_at, acknowledged_at)
    values (v_id, p_responsible, 'responsible', v_engineer, v_received + interval '20 minutes',
            case when v_accepted then v_received + interval '30 minutes' end);
  end if;
  -- Work time: one session from the start of work, still running for jobs
  -- in progress; held jobs stopped when they went on hold.
  if v_started then
    insert into public.job_work_sessions (job_card_id, user_id, started_at, ended_at, end_reason)
    values (
      v_id, p_responsible, v_received + interval '45 minutes',
      case when p_status = 'in_progress' then null
        when v_submitted then v_received + p_age * 0.5
        else v_received + p_age * 0.4 end,
      case when p_status = 'in_progress' then null when v_submitted then 'submitted' else 'hold' end
    );
  end if;
  if p_status in ('on_hold', 'awaiting_materials', 'awaiting_isolation', 'awaiting_specialist',
                  'awaiting_production_clearance') then
    insert into public.job_waits (job_card_id, hold_status, note, started_at, started_by)
    values (v_id, p_status, p_reason, v_received + p_age * 0.4, p_responsible);
  end if;
  if v_submitted then
    insert into public.job_submissions (
      job_card_id, submitted_by, submitted_at, completion_summary, findings, corrective_action,
      equipment_state_after, functional_tests, labour_hours, recorded_labour_minutes,
      checks_confirmed, safety_confirmed
    )
    select id, p_responsible, submitted_at, completion_summary, findings, corrective_action,
      equipment_state_after, 'Functional test passed',
      round(extract(epoch from (submitted_at - received_at - interval '45 minutes')) / 3600, 2),
      round(extract(epoch from (submitted_at - received_at - interval '45 minutes')) / 60),
      true, true
    from public.job_cards where id = v_id
    returning id into v_submission;
  end if;
  if p_status = 'closed' then
    insert into public.job_closures (
      job_card_id, closed_at, completion_summary, findings, corrective_action,
      equipment_state_after, performed_by, verified_by, submission_id
    )
    select id, closed_at, completion_summary, findings, corrective_action,
      equipment_state_after, performed_by, verified_by, v_submission
    from public.job_cards where id = v_id;
    insert into public.job_reviews (job_card_id, submission_id, reviewer_id, decision, notes, created_at)
    values (v_id, v_submission, v_engineer, 'approve', 'Checked on site and approved', v_received + p_age * 0.6);
  end if;
  return v_id;
end;
$$;

select pg_temp.seed_job('KAM', 'Camp – Block C', 'KAM-DB-CB', 'Flickering lights in Block C corridor',
  'Corridor lights flicker and sometimes go off at night.', 'P3', 'registered', interval '40 minutes');
select pg_temp.seed_job('KAM', 'Workshop', 'KAM-DB-03', 'Add a 32 A socket in the workshop',
  'The welding bay needs a 32 A socket outlet.', 'P4', 'awaiting_clarification', interval '1 day',
  null, 'Which wall, and single or three phase?', 'none', 'installation');
select pg_temp.seed_job('KAM', 'Plant – Crusher', 'KAM-MTR-CR1', 'Crusher motor tripping on overload',
  'The primary crusher motor trips after about 40 minutes under load.', 'P2', 'awaiting_assignment',
  interval '2 hours', null, null, 'reduced_output', 'reactive');
select pg_temp.seed_job('KAM', 'Workshop', 'KAM-DB-03', 'Replace damaged 63 A MCB in DB-3',
  'Way 7 MCB on DB-3 is cracked and runs hot.', 'P3', 'assigned', interval '3 hours',
  '10000000-0000-0000-0000-000000000003', null, 'minor', 'corrective');
select pg_temp.seed_job('KAM', 'Main substation', 'KAM-ERTH-SS', 'Earth resistance test at main substation',
  'The annual earth grid resistance test is due.', 'P4', 'accepted', interval '1 day',
  '10000000-0000-0000-0000-000000000005', null, 'none', 'inspection');
select pg_temp.seed_job('KAM', 'Plant – Conveyors', 'KAM-VFD-CV3', 'Conveyor 3 VFD fault F0002',
  'The conveyor 3 drive stops with overvoltage fault F0002 on start.', 'P2', 'in_progress', interval '2 hours',
  '10000000-0000-0000-0000-000000000003', null, 'production_stopped', 'reactive');
select pg_temp.seed_job('KAM', 'Pump house', 'KAM-CBL-PH', 'Replace pump house feeder cable',
  'The feeder to the pump house has a damaged section near the culvert.', 'P3', 'awaiting_materials',
  interval '2 days', '10000000-0000-0000-0000-000000000003',
  'Waiting for 50 m of 16 mm² 4-core SWA cable from Harare stores', 'reduced_output', 'corrective');
select pg_temp.seed_job('KAM', 'Main substation', 'KAM-GEN-02', 'Generator G2 weekly inspection',
  'Weekly run test and inspection of standby generator G2.', 'P4', 'awaiting_review', interval '1 day',
  '10000000-0000-0000-0000-000000000005', null, 'none', 'preventive');
select pg_temp.seed_job('KAM', 'Main gate', 'KAM-LT-GATE', 'Repair floodlights at the main gate',
  'Two of the four gate floodlights are out.', 'P3', 'closed', interval '2 days',
  '10000000-0000-0000-0000-000000000003', null, 'minor', 'corrective');
select pg_temp.seed_job('KAM', 'Plant – MCC room', 'KAM-MCC-01', 'Replace MCC-1 crusher feed contactor',
  'The crusher feed contactor on MCC-1 is chattering.', 'P2', 'closed', interval '5 days',
  '10000000-0000-0000-0000-000000000005', null, 'reduced_output', 'reactive');
select pg_temp.seed_job('KAM', 'Main substation', 'KAM-TX-01', 'Transformer T1 Buchholz alarm',
  'Buchholz relay alarm on transformer T1; load transferred to T2.', 'P1', 'in_progress',
  interval '3 hours 15 minutes', '10000000-0000-0000-0000-000000000003', null, 'safety_hazard', 'emergency');
select pg_temp.seed_job('KAM', 'Main substation', 'KAM-UPS-01', 'Replace control room UPS batteries',
  'The UPS battery test failed; runtime is under 5 minutes.', 'P3', 'assigned', interval '6 days',
  '10000000-0000-0000-0000-000000000005', null, 'minor', 'corrective');
select pg_temp.seed_job('KAM', 'Camp – Block C', 'KAM-DB-CB', 'Block C lights (reported twice)',
  'The camp office reported the Block C lights twice.', 'P3', 'cancelled', interval '1 day',
  null, 'Duplicate of the Block C flickering lights job card', 'minor', 'reactive');
select pg_temp.seed_job('SEL', 'Main substation', 'SEL-PNL-01', 'Main LV panel heater not working',
  'The anti-condensation heater in the main LV panel is not working.', 'P3', 'registered', interval '5 hours');

-- ---------------------------------------------------------------------------
-- Requests from Production: one in the queue, one returned, one registered
-- ---------------------------------------------------------------------------
insert into public.service_requests (
  request_no, site_id, area_id, department_id, requested_by, reporter_name, equipment_text,
  title, description, operational_impact, status, status_reason, reviewed_by, reviewed_at, submitted_at
)
select public._next_doc_no('request', now()), s.id, a.id, d.id, '10000000-0000-0000-0000-000000000007',
  'Blessing Dube', x.equipment, x.title, x.descr, x.impact, x.status, x.reason,
  case when x.status <> 'submitted' then '10000000-0000-0000-0000-000000000002'::uuid end,
  case when x.status <> 'submitted' then now() - x.age + interval '30 minutes' end,
  now() - x.age
from (values
  ('Packing line 2 lighting', 'Packing line lights out', 'Half the lights over packing line 2 are out.',
    'reduced_output', 'submitted', null::text, interval '25 minutes'),
  ('Shift office aircon', 'Aircon isolator sparks', 'The aircon isolator in the shift office sparks when switched.',
    'safety_hazard', 'returned', 'Which office: shift office A or B?', interval '1 day')
) as x (equipment, title, descr, impact, status, reason, age)
join public.sites s on s.code = 'KAM'
left join public.areas a on a.site_id = s.id and a.name = 'Packing shed'
join public.departments d on d.code = 'PROD';

insert into public.service_requests (
  request_no, site_id, area_id, department_id, requested_by, reporter_name, asset_id,
  title, description, operational_impact, status, reviewed_by, reviewed_at, submitted_at
)
select public._next_doc_no('request', now()), s.id, a.id, d.id, '10000000-0000-0000-0000-000000000007',
  'Blessing Dube', ast.id, 'Conveyor 3 stopped', 'Conveyor 3 will not start; the drive shows a fault.',
  'production_stopped', 'registered', '10000000-0000-0000-0000-000000000002',
  now() - interval '2 hours', now() - interval '2 hours 10 minutes'
from public.sites s
join public.areas a on a.site_id = s.id and a.name = 'Plant – Conveyors'
join public.assets ast on ast.asset_no = 'KAM-VFD-CV3'
join public.departments d on d.code = 'PROD'
where s.code = 'KAM';

update public.job_cards j set source = 'request', request_id = sr.id, reporter_name = sr.reporter_name
from public.service_requests sr
where sr.title = 'Conveyor 3 stopped' and j.title = 'Conveyor 3 VFD fault F0002';

update public.service_requests sr set job_card_id = j.id
from public.job_cards j
where j.request_id = sr.id;

insert into public.job_card_comments (job_card_id, author_id, kind, visibility, body, created_at)
select j.id, x.author, x.kind, x.vis, x.body, now() - x.ago
from (values
  ('Conveyor 3 VFD fault F0002', '10000000-0000-0000-0000-000000000003'::uuid, 'finding', 'internal',
    'DC bus voltage spikes on start; checking the braking resistor.', interval '1 hour'),
  ('Conveyor 3 VFD fault F0002', '10000000-0000-0000-0000-000000000002'::uuid, 'instruction', 'internal',
    'Check the braking chopper wiring before replacing the resistor.', interval '50 minutes'),
  ('Conveyor 3 VFD fault F0002', '10000000-0000-0000-0000-000000000002'::uuid, 'comment', 'requester',
    'We are on it; expect the conveyor back within two hours.', interval '45 minutes'),
  ('Transformer T1 Buchholz alarm', '10000000-0000-0000-0000-000000000002'::uuid, 'instruction', 'internal',
    'Keep T1 isolated and take an oil sample for DGA before re-energising.', interval '2 hours')
) as x (title, author, kind, vis, body, ago)
join public.job_cards j on j.title = x.title;
