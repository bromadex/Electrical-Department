-- 0004_cmms_core: job cards, incoming requests, assets and configuration for
-- the job card & maintenance management system (API.md section 7). Tables are
-- read-only for the app; every write goes through the fn_* functions in 0005.

create extension if not exists pg_trgm with schema extensions;

-- ---------------------------------------------------------------------------
-- Roles and permissions
-- ---------------------------------------------------------------------------
update public.roles set name = 'Electrician' where name = 'Technician';
update public.roles set name = 'Electrical Engineer' where name = 'Supervisor';
update public.roles set name = 'System Administrator' where name = 'Admin';
insert into public.roles (name) values ('Department Manager'), ('Requester')
on conflict (name) do nothing;

insert into public.permissions (code, description) values
  ('jc.view', 'See job cards at the site'),
  ('jc.register', 'Receive and register job cards'),
  ('jc.assess', 'Assess job cards and return them for clarification'),
  ('jc.assign', 'Assign and reassign job cards'),
  ('jc.execute', 'Work on job cards assigned to them'),
  ('jc.review', 'Verify work and approve or reject closure'),
  ('jc.cancel', 'Cancel job cards'),
  ('jc.reopen', 'Reopen closed job cards'),
  ('jc.escalate', 'Escalate job cards to critical'),
  ('jc.self_approve', 'Approve closure of their own work (audited exception)'),
  ('req.submit', 'Submit electrical maintenance requests'),
  ('req.triage', 'Review incoming requests and register them'),
  ('assets.view', 'See the asset register'),
  ('assets.manage', 'Add and edit assets'),
  ('settings.manage', 'Manage settings, priorities and reference lists'),
  ('audit.view', 'See audit logs'),
  ('reports.view', 'See reports and analytics');

insert into public.role_permissions (role_id, permission_code)
select r.id, x.code
from (values
  ('Electrician', 'jc.view'), ('Electrician', 'jc.register'), ('Electrician', 'jc.execute'),
  ('Electrician', 'req.submit'), ('Electrician', 'req.triage'), ('Electrician', 'assets.view'),

  ('Electrical Engineer', 'jc.view'), ('Electrical Engineer', 'jc.register'),
  ('Electrical Engineer', 'jc.assess'), ('Electrical Engineer', 'jc.assign'),
  ('Electrical Engineer', 'jc.execute'), ('Electrical Engineer', 'jc.review'),
  ('Electrical Engineer', 'jc.cancel'), ('Electrical Engineer', 'jc.reopen'),
  ('Electrical Engineer', 'jc.escalate'), ('Electrical Engineer', 'req.submit'),
  ('Electrical Engineer', 'req.triage'), ('Electrical Engineer', 'assets.view'),
  ('Electrical Engineer', 'assets.manage'), ('Electrical Engineer', 'reports.view'),

  ('Department Manager', 'jc.view'), ('Department Manager', 'jc.reopen'),
  ('Department Manager', 'jc.escalate'), ('Department Manager', 'req.submit'),
  ('Department Manager', 'assets.view'), ('Department Manager', 'reports.view'),
  ('Department Manager', 'stats.view'), ('Department Manager', 'audit.view'),

  ('Requester', 'req.submit'),

  ('Storekeeper', 'jc.view'), ('Storekeeper', 'req.submit'), ('Storekeeper', 'assets.view')
) as x (role_name, code)
join public.roles r on r.name = x.role_name
on conflict do nothing;

-- System Administrator holds every permission except approving closure of
-- their own work, which stays an explicit, audited exception.
insert into public.role_permissions (role_id, permission_code)
select r.id, p.code
from public.roles r
cross join public.permissions p
where r.name = 'System Administrator' and p.code <> 'jc.self_approve'
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Departments (who requests work) and profile link
-- ---------------------------------------------------------------------------
create table public.departments (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z0-9]{2,10}$'),
  name text not null unique check (length(trim(name)) between 2 and 80),
  is_electrical boolean not null default false,
  is_archived boolean not null default false,
  created_at timestamptz not null default now()
);

insert into public.departments (code, name, is_electrical) values
  ('ELEC', 'Electrical', true),
  ('PROD', 'Production', false),
  ('PROC', 'Processing', false),
  ('MECH', 'Mechanical', false),
  ('INST', 'Instrumentation', false),
  ('MINE', 'Mining', false),
  ('ENG', 'Engineering', false),
  ('SHEQ', 'SHEQ', false),
  ('CAMP', 'Camp Services', false),
  ('ADMIN', 'Administration', false);

alter table public.profiles add column department_id uuid references public.departments (id);

-- ---------------------------------------------------------------------------
-- System settings (one row)
-- ---------------------------------------------------------------------------
create table public.system_settings (
  id uuid primary key default gen_random_uuid(),
  singleton boolean not null default true unique check (singleton),
  timezone text not null default 'Africa/Harare',
  jobcard_prefix text not null default 'EL-JC' check (jobcard_prefix ~ '^[A-Z0-9][A-Z0-9-]{0,11}$'),
  request_prefix text not null default 'EL-SR' check (request_prefix ~ '^[A-Z0-9][A-Z0-9-]{0,11}$'),
  number_digits integer not null default 4 check (number_digits between 3 and 8),
  number_reset_yearly boolean not null default true,
  -- Which event ends the response time: acknowledged = accepted by the assignee
  response_ends_at text not null default 'acknowledged'
    check (response_ends_at in ('acknowledged', 'assessed', 'assigned')),
  -- A job is "at risk" when this share of its allowed time or less remains
  at_risk_percent integer not null default 25 check (at_risk_percent between 1 and 90),
  -- Jobs on hold longer than this appear in the dashboard alerts
  hold_alert_hours integer not null default 48 check (hold_alert_hours between 1 and 2160),
  handover_note_required boolean not null default true,
  company_name text not null default 'Bravura',
  department_name text not null default 'Electrical Department',
  logo_path text,
  updated_by uuid references public.profiles (id),
  updated_at timestamptz not null default now()
);
insert into public.system_settings default values;

create function public._settings()
returns public.system_settings
language sql
stable
security definer
set search_path = ''
as $$
  select * from public.system_settings limit 1;
$$;

-- ---------------------------------------------------------------------------
-- Priority levels and their targets (admins confirm the defaults)
-- ---------------------------------------------------------------------------
create table public.priority_levels (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code in ('P1', 'P2', 'P3', 'P4')),
  name text not null,
  description text,
  response_minutes integer not null check (response_minutes between 1 and 525600),
  completion_minutes integer not null check (completion_minutes between 1 and 525600),
  targets_confirmed boolean not null default false,
  sort_order integer not null,
  updated_by uuid references public.profiles (id),
  updated_at timestamptz not null default now()
);

insert into public.priority_levels (code, name, description, response_minutes, completion_minutes, sort_order) values
  ('P1', 'Emergency', 'Immediate electrical safety hazard, major failure of critical operations, critical power supply failure, or a serious fault needing immediate intervention.', 15, 240, 1),
  ('P2', 'High', 'Significant equipment failure, a fault affecting production capacity, or important standby equipment unavailable.', 60, 1440, 2),
  ('P3', 'Medium', 'Non-critical electrical fault, an equipment defect with limited operational impact, or planned corrective maintenance.', 240, 4320, 3),
  ('P4', 'Low', 'Minor repairs, routine inspections, improvement work or non-urgent maintenance.', 1440, 20160, 4);

-- ---------------------------------------------------------------------------
-- Reference lists
-- ---------------------------------------------------------------------------
create table public.job_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (length(trim(name)) between 2 and 80),
  description text,
  sort_order integer not null default 100,
  is_archived boolean not null default false,
  created_at timestamptz not null default now()
);

insert into public.job_categories (name, sort_order) values
  ('Electrical fault', 10), ('Power supply failure', 20), ('Motors and drives', 30),
  ('Switchgear and protection', 40), ('Generators', 50), ('Transformers', 60),
  ('Distribution boards', 70), ('Cables and terminations', 80), ('Lighting', 90),
  ('Earthing and lightning protection', 100), ('UPS and batteries', 110),
  ('Instrumentation interface', 120), ('Installation', 130), ('Inspection', 140),
  ('Preventive maintenance', 150), ('Improvement', 160), ('Other', 999);

create table public.asset_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (length(trim(name)) between 2 and 80),
  sort_order integer not null default 100,
  is_archived boolean not null default false,
  created_at timestamptz not null default now()
);

insert into public.asset_categories (name, sort_order) values
  ('Generators', 10), ('Transformers', 20), ('Switchgear', 30), ('Circuit breakers', 40),
  ('Motors', 50), ('Pumps', 60), ('Variable frequency drives', 70),
  ('Motor control centres', 80), ('Distribution boards', 90), ('Cables and terminations', 100),
  ('Earthing and lightning protection', 110), ('Lighting systems', 120),
  ('UPS and battery systems', 130), ('Inverters', 140), ('Protection systems', 150),
  ('Other', 999);

-- ---------------------------------------------------------------------------
-- Assets (the full register screens arrive in phase 3)
-- ---------------------------------------------------------------------------
create table public.assets (
  id uuid primary key default gen_random_uuid(),
  asset_no text not null unique check (length(trim(asset_no)) between 1 and 40),
  name text not null check (length(trim(name)) between 2 and 120),
  category_id uuid references public.asset_categories (id),
  site_id uuid not null references public.sites (id),
  area_id uuid references public.areas (id),
  location text,
  manufacturer text,
  model text,
  serial_no text,
  electrical_rating text,
  voltage_v numeric(10, 2) check (voltage_v > 0),
  current_a numeric(10, 2) check (current_a > 0),
  power_kw numeric(10, 2) check (power_kw > 0),
  installed_on date,
  operational_status text not null default 'in_service'
    check (operational_status in ('in_service', 'out_of_service', 'standby', 'decommissioned')),
  criticality text not null default 'medium' check (criticality in ('high', 'medium', 'low')),
  department_id uuid references public.departments (id),
  maintenance_frequency text,
  warranty_expires_on date,
  warranty_notes text,
  notes text,
  created_by uuid references public.profiles (id),
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index assets_site_idx on public.assets (site_id);
create index assets_category_idx on public.assets (category_id);
create index assets_name_trgm_idx on public.assets using gin (name extensions.gin_trgm_ops);
create index assets_no_trgm_idx on public.assets using gin (asset_no extensions.gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- Escalation contacts: who else hears about critical jobs of a priority
-- ---------------------------------------------------------------------------
create table public.escalation_contacts (
  id uuid primary key default gen_random_uuid(),
  site_id uuid references public.sites (id), -- null = all sites
  priority_code text not null references public.priority_levels (code),
  user_id uuid not null references public.profiles (id),
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  unique nulls not distinct (site_id, priority_code, user_id)
);

-- ---------------------------------------------------------------------------
-- Document numbers: EL-JC-2026-0001, EL-SR-2026-0001 (never reused)
-- ---------------------------------------------------------------------------
create table public.doc_sequences (
  kind text not null check (kind in ('jobcard', 'request')),
  year integer not null, -- 0 when numbering does not reset each year
  last_no integer not null default 0,
  primary key (kind, year)
);

create function public._next_doc_no(p_kind text, p_at timestamptz)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.system_settings := public._settings();
  v_year integer;
  v_no integer;
  v_digits text;
begin
  v_year := case when s.number_reset_yearly
    then extract(year from (p_at at time zone s.timezone))::integer else 0 end;

  insert into public.doc_sequences as d (kind, year, last_no)
  values (p_kind, v_year, 1)
  on conflict (kind, year) do update set last_no = d.last_no + 1
  returning d.last_no into v_no;

  -- Never truncate: 10000 stays 10000 even with four digits configured.
  v_digits := case when length(v_no::text) >= s.number_digits then v_no::text
    else lpad(v_no::text, s.number_digits, '0') end;

  return (case p_kind when 'jobcard' then s.jobcard_prefix else s.request_prefix end)
    || '-' || case when v_year > 0 then v_year::text || '-' else '' end || v_digits;
end;
$$;

-- ---------------------------------------------------------------------------
-- Incoming requests from other departments
-- ---------------------------------------------------------------------------
create table public.service_requests (
  id uuid primary key default gen_random_uuid(),
  request_no text not null unique,
  site_id uuid not null references public.sites (id),
  area_id uuid references public.areas (id),
  location text,
  department_id uuid references public.departments (id),
  requested_by uuid not null references public.profiles (id),
  reporter_name text not null check (length(trim(reporter_name)) between 2 and 120),
  contact text,
  asset_id uuid references public.assets (id),
  equipment_text text,
  title text not null check (length(trim(title)) between 3 and 120),
  description text not null check (length(trim(description)) between 5 and 4000),
  operational_impact text not null check (operational_impact in (
    'none', 'minor', 'reduced_output', 'production_stopped', 'safety_hazard'
  )),
  status text not null default 'submitted' check (status in (
    'submitted', 'returned', 'registered', 'rejected', 'withdrawn'
  )),
  status_reason text,
  clarification_note text,
  reviewed_by uuid references public.profiles (id),
  reviewed_at timestamptz,
  job_card_id uuid, -- foreign key added below, once job_cards exists
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_archived boolean not null default false,
  check (area_id is not null or nullif(trim(coalesce(location, '')), '') is not null or asset_id is not null),
  check (status not in ('returned', 'rejected', 'withdrawn') or status_reason is not null)
);
create index service_requests_site_status_idx on public.service_requests (site_id, status);
create index service_requests_requested_by_idx on public.service_requests (requested_by, submitted_at desc);

create table public.request_attachments (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.service_requests (id),
  path text not null unique,
  file_name text,
  content_type text,
  size_bytes bigint check (size_bytes >= 0),
  uploaded_by uuid references public.profiles (id),
  is_archived boolean not null default false,
  created_at timestamptz not null default now()
);
create index request_attachments_request_idx on public.request_attachments (request_id);

-- ---------------------------------------------------------------------------
-- Job cards
-- ---------------------------------------------------------------------------
create table public.job_cards (
  id uuid primary key default gen_random_uuid(),
  number text not null unique,
  legacy_code text,
  source text not null check (source in ('direct', 'request', 'preventive', 'follow_up', 'legacy')),
  request_id uuid references public.service_requests (id),
  parent_job_id uuid references public.job_cards (id),
  site_id uuid not null references public.sites (id),
  area_id uuid references public.areas (id),
  location text,

  -- Stage 1: reception
  received_at timestamptz not null,
  reporter_name text not null check (length(trim(reporter_name)) between 2 and 120),
  requesting_department_id uuid references public.departments (id),
  asset_id uuid references public.assets (id),
  equipment_name text,
  equipment_asset_no text,
  equipment_location text,
  category_id uuid references public.job_categories (id),
  title text not null check (length(trim(title)) between 3 and 120),
  description text not null check (length(trim(description)) between 5 and 4000),
  operational_impact text check (operational_impact in (
    'none', 'minor', 'reduced_output', 'production_stopped', 'safety_hazard'
  )),
  priority text not null references public.priority_levels (code),
  requested_completion_at timestamptz,
  registered_by uuid references public.profiles (id),
  registered_at timestamptz not null default now(),

  -- Stage 2: engineering assessment
  is_valid boolean,
  maintenance_type text check (maintenance_type in (
    'reactive', 'preventive', 'corrective', 'emergency', 'inspection', 'installation', 'improvement'
  )),
  severity text check (severity in ('minor', 'moderate', 'major', 'critical')),
  safety_risk text check (safety_risk in ('low', 'medium', 'high', 'extreme')),
  safety_notes text,
  equipment_state text check (equipment_state in ('operational', 'degraded', 'out_of_service')),
  required_competencies text,
  required_personnel integer check (required_personnel between 1 and 50),
  resources_required text,
  isolation_required boolean,
  permit_required boolean,
  loto_required boolean,
  expected_duration_hours numeric(8, 2) check (expected_duration_hours > 0),
  assessment_notes text,
  assessed_by uuid references public.profiles (id),
  assessed_at timestamptz,

  -- Targets: the completion target is the deadline that decides "overdue"
  target_response_at timestamptz,
  target_completion_at timestamptz,

  -- Critical classification (P1, or escalated by an authorised user)
  is_critical boolean not null default false,
  critical_reason text,
  escalated_by uuid references public.profiles (id),
  escalated_at timestamptz,

  -- Stage 3: current assignment plan (job_assignments keeps the history)
  responsible_id uuid references public.profiles (id),
  assigned_by uuid references public.profiles (id),
  planned_start_at timestamptz,
  estimated_labour_hours numeric(8, 2) check (estimated_labour_hours > 0),
  required_materials text,
  required_tools text,
  safety_precautions text,
  procedure_notes text,

  status text not null default 'registered' check (status in (
    'registered', 'awaiting_clarification', 'awaiting_assignment', 'assigned', 'accepted',
    'in_progress', 'on_hold', 'awaiting_materials', 'awaiting_isolation', 'awaiting_specialist',
    'awaiting_production_clearance', 'awaiting_review', 'reopened', 'closed', 'cancelled'
  )),
  status_reason text,

  -- Lifecycle timestamps, always set by the server
  first_assigned_at timestamptz,
  assigned_at timestamptz,
  accepted_at timestamptz,
  first_started_at timestamptz,
  submitted_at timestamptz,
  closed_at timestamptz,
  cancelled_at timestamptz,
  reopened_at timestamptz,
  responded_at timestamptz,

  -- Completion and verification (phase 2 adds the full submission records)
  completion_summary text,
  findings text,
  corrective_action text,
  equipment_state_after text check (equipment_state_after in ('operational', 'degraded', 'out_of_service')),
  performed_by uuid references public.profiles (id),
  verified_by uuid references public.profiles (id),
  closure_approved_at timestamptz,
  self_approved boolean not null default false,
  legacy_closure boolean not null default false,

  overdue_notified_at timestamptz,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  check (area_id is not null or nullif(trim(coalesce(location, '')), '') is not null or asset_id is not null),
  check (source <> 'request' or request_id is not null),
  check (status <> 'closed' or closed_at is not null),
  check (status <> 'cancelled' or (cancelled_at is not null and status_reason is not null)),
  check (status not in (
    'awaiting_clarification', 'on_hold', 'awaiting_materials', 'awaiting_isolation',
    'awaiting_specialist', 'awaiting_production_clearance'
  ) or status_reason is not null),
  check (status not in (
    'assigned', 'accepted', 'in_progress', 'on_hold', 'awaiting_materials', 'awaiting_isolation',
    'awaiting_specialist', 'awaiting_production_clearance', 'awaiting_review'
  ) or responsible_id is not null)
);
create index job_cards_site_status_idx on public.job_cards (site_id, status);
create index job_cards_responsible_idx on public.job_cards (responsible_id)
  where status not in ('closed', 'cancelled');
create index job_cards_deadline_idx on public.job_cards (target_completion_at)
  where status not in ('closed', 'cancelled');
create index job_cards_received_idx on public.job_cards (received_at desc);
create index job_cards_closed_idx on public.job_cards (closed_at desc) where closed_at is not null;
create index job_cards_asset_idx on public.job_cards (asset_id);
create index job_cards_request_idx on public.job_cards (request_id);
create index job_cards_title_trgm_idx on public.job_cards using gin (title extensions.gin_trgm_ops);
create index job_cards_description_trgm_idx on public.job_cards using gin (description extensions.gin_trgm_ops);
create index job_cards_number_trgm_idx on public.job_cards using gin (number extensions.gin_trgm_ops);

alter table public.service_requests
  add constraint service_requests_job_card_id_fkey
  foreign key (job_card_id) references public.job_cards (id);

-- Responsible and supporting people; rows are ended, never deleted.
create table public.job_assignments (
  id uuid primary key default gen_random_uuid(),
  job_card_id uuid not null references public.job_cards (id),
  user_id uuid not null references public.profiles (id),
  role text not null check (role in ('responsible', 'support')),
  assigned_by uuid references public.profiles (id),
  assigned_at timestamptz not null default now(),
  acknowledged_at timestamptz,
  ended_at timestamptz,
  end_reason text,
  handover_note text,
  is_archived boolean not null default false
);
create unique index job_assignments_one_responsible_idx on public.job_assignments (job_card_id)
  where role = 'responsible' and ended_at is null;
create unique index job_assignments_current_person_idx on public.job_assignments (job_card_id, user_id)
  where ended_at is null;
create index job_assignments_user_idx on public.job_assignments (user_id) where ended_at is null;

-- Every status change, written by trigger so none can be skipped.
create table public.job_status_history (
  id uuid primary key default gen_random_uuid(),
  job_card_id uuid not null references public.job_cards (id),
  from_status text,
  to_status text not null,
  reason text,
  changed_by uuid references public.profiles (id),
  changed_at timestamptz not null default now()
);
create index job_status_history_job_idx on public.job_status_history (job_card_id, changed_at);

-- Append-only: findings and instructions are never overwritten.
create table public.job_comments (
  id uuid primary key default gen_random_uuid(),
  job_card_id uuid not null references public.job_cards (id),
  author_id uuid references public.profiles (id),
  kind text not null default 'comment'
    check (kind in ('comment', 'finding', 'instruction', 'handover', 'assistance')),
  visibility text not null default 'internal' check (visibility in ('internal', 'requester')),
  body text not null check (length(trim(body)) between 1 and 4000),
  mentions uuid[] not null default '{}',
  is_archived boolean not null default false,
  created_at timestamptz not null default now()
);
create index job_comments_job_card_idx on public.job_comments (job_card_id, created_at);

create table public.job_attachments (
  id uuid primary key default gen_random_uuid(),
  job_card_id uuid not null references public.job_cards (id),
  kind text not null check (kind in (
    'photo_before', 'photo_after', 'photo', 'test_sheet', 'document', 'other'
  )),
  bucket text not null default 'job-files' check (bucket in ('job-files', 'job-photos')),
  path text not null,
  file_name text,
  content_type text,
  size_bytes bigint check (size_bytes >= 0),
  caption text,
  uploaded_by uuid references public.profiles (id),
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  unique (bucket, path)
);
create index job_attachments_job_card_idx on public.job_attachments (job_card_id);

-- One row per approved closure, so reopening never loses a closure record.
create table public.job_closures (
  id uuid primary key default gen_random_uuid(),
  job_card_id uuid not null references public.job_cards (id),
  closed_at timestamptz not null,
  completion_summary text,
  findings text,
  corrective_action text,
  equipment_state_after text,
  performed_by uuid references public.profiles (id),
  verified_by uuid references public.profiles (id),
  self_approved boolean not null default false,
  legacy boolean not null default false,
  created_at timestamptz not null default now()
);
create index job_closures_job_card_idx on public.job_closures (job_card_id);

-- Allowed status changes; the app reads this to offer only valid actions.
create table public.job_status_transitions (
  from_status text not null,
  to_status text not null,
  primary key (from_status, to_status)
);

insert into public.job_status_transitions (from_status, to_status) values
  ('registered', 'awaiting_clarification'), ('registered', 'awaiting_assignment'),
  ('registered', 'cancelled'),
  ('awaiting_clarification', 'registered'), ('awaiting_clarification', 'cancelled'),
  ('awaiting_assignment', 'assigned'), ('awaiting_assignment', 'awaiting_clarification'),
  ('awaiting_assignment', 'cancelled'),
  ('assigned', 'accepted'), ('assigned', 'awaiting_assignment'), ('assigned', 'cancelled'),
  ('accepted', 'in_progress'), ('accepted', 'assigned'), ('accepted', 'awaiting_assignment'),
  ('accepted', 'cancelled'),
  ('in_progress', 'awaiting_review'), ('in_progress', 'assigned'), ('in_progress', 'cancelled'),
  ('awaiting_review', 'closed'), ('awaiting_review', 'accepted'), ('awaiting_review', 'cancelled'),
  ('closed', 'reopened'),
  ('reopened', 'assigned'), ('reopened', 'accepted'), ('reopened', 'cancelled');

-- Work can stop for a reason, switch reason, and resume.
insert into public.job_status_transitions (from_status, to_status)
select f, t
from unnest(array['accepted', 'in_progress', 'on_hold', 'awaiting_materials', 'awaiting_isolation',
                  'awaiting_specialist', 'awaiting_production_clearance']) f
cross join unnest(array['on_hold', 'awaiting_materials', 'awaiting_isolation',
                        'awaiting_specialist', 'awaiting_production_clearance']) t
where f <> t;

insert into public.job_status_transitions (from_status, to_status)
select f, t
from unnest(array['on_hold', 'awaiting_materials', 'awaiting_isolation',
                  'awaiting_specialist', 'awaiting_production_clearance']) f
cross join unnest(array['in_progress', 'assigned', 'cancelled']) t;

-- ---------------------------------------------------------------------------
-- Notification types used by job cards and requests
-- ---------------------------------------------------------------------------
alter table public.notifications drop constraint notifications_type_check;
alter table public.notifications add constraint notifications_type_check check (type in (
  'assigned', 'mentioned', 'overdue', 'reminder', 'approval', 'low_stock', 'meeting', 'general',
  'registered', 'critical', 'reassigned', 'on_hold', 'review', 'returned', 'closed', 'request'
));

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

-- Response time ends at the event chosen in system_settings.
create function public.fn_job_cards_response()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_end text;
begin
  if new.responded_at is null then
    select response_ends_at into v_end from public.system_settings limit 1;
    new.responded_at := case v_end
      when 'acknowledged' then new.accepted_at
      when 'assessed' then new.assessed_at
      else new.first_assigned_at
    end;
  end if;
  return new;
end;
$$;

create trigger job_cards_response before insert or update on public.job_cards
  for each row execute function public.fn_job_cards_response();

create function public.fn_job_status_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.job_status_history (job_card_id, from_status, to_status, reason, changed_by)
    values (new.id, null, new.status, new.status_reason, auth.uid());
  elsif new.status is distinct from old.status then
    insert into public.job_status_history (job_card_id, from_status, to_status, reason, changed_by)
    values (new.id, old.status, new.status, new.status_reason, auth.uid());
  end if;
  return new;
end;
$$;

create trigger job_cards_status_history after insert or update on public.job_cards
  for each row execute function public.fn_job_status_history();

create trigger job_cards_touch before update on public.job_cards
  for each row execute function public.fn_touch_updated_at();
create trigger service_requests_touch before update on public.service_requests
  for each row execute function public.fn_touch_updated_at();
create trigger assets_touch before update on public.assets
  for each row execute function public.fn_touch_updated_at();
create trigger system_settings_touch before update on public.system_settings
  for each row execute function public.fn_touch_updated_at();
create trigger priority_levels_touch before update on public.priority_levels
  for each row execute function public.fn_touch_updated_at();

create trigger departments_activity after insert or update on public.departments
  for each row execute function public.fn_log_activity();
create trigger system_settings_activity after insert or update on public.system_settings
  for each row execute function public.fn_log_activity();
create trigger priority_levels_activity after insert or update on public.priority_levels
  for each row execute function public.fn_log_activity();
create trigger job_categories_activity after insert or update on public.job_categories
  for each row execute function public.fn_log_activity();
create trigger asset_categories_activity after insert or update on public.asset_categories
  for each row execute function public.fn_log_activity();
create trigger assets_activity after insert or update on public.assets
  for each row execute function public.fn_log_activity();
create trigger escalation_contacts_activity after insert or update on public.escalation_contacts
  for each row execute function public.fn_log_activity();
create trigger service_requests_activity after insert or update on public.service_requests
  for each row execute function public.fn_log_activity();
create trigger request_attachments_activity after insert or update on public.request_attachments
  for each row execute function public.fn_log_activity();
create trigger job_cards_activity after insert or update on public.job_cards
  for each row execute function public.fn_log_activity();
create trigger job_assignments_activity after insert or update on public.job_assignments
  for each row execute function public.fn_log_activity();
create trigger job_comments_activity after insert or update on public.job_comments
  for each row execute function public.fn_log_activity();
create trigger job_attachments_activity after insert or update on public.job_attachments
  for each row execute function public.fn_log_activity();
create trigger job_closures_activity after insert or update on public.job_closures
  for each row execute function public.fn_log_activity();

-- ---------------------------------------------------------------------------
-- v_job_cards: job cards with names and computed classification and timing.
-- security_invoker keeps the caller's row level security in force.
-- ---------------------------------------------------------------------------
create view public.v_job_cards
with (security_invoker = true)
as
select
  j.*,
  s.code as site_code,
  s.name as site_name,
  ar.name as area_name,
  dp.name as department_name,
  ct.name as category_name,
  pl.name as priority_name,
  pl.sort_order as priority_rank,
  sr.request_no,
  coalesce(a.name, j.equipment_name) as equipment_display,
  coalesce(a.asset_no, j.equipment_asset_no) as asset_no_display,
  rsp.full_name as responsible_name,
  asg.full_name as assigned_by_name,
  reg.full_name as registered_by_name,
  hist.last_change_at as status_changed_at,
  j.status = 'registered' as is_new,
  j.status = 'awaiting_assignment' as is_awaiting_assignment,
  j.status in (
    'assigned', 'accepted', 'in_progress', 'on_hold', 'awaiting_materials', 'awaiting_isolation',
    'awaiting_specialist', 'awaiting_production_clearance', 'reopened'
  ) as is_active,
  j.status = 'in_progress' as is_working,
  j.status in (
    'on_hold', 'awaiting_materials', 'awaiting_isolation', 'awaiting_specialist',
    'awaiting_production_clearance'
  ) as is_waiting,
  j.is_critical and j.status not in ('closed', 'cancelled') as is_critical_open,
  j.status not in ('closed', 'cancelled') and j.target_completion_at < now() as is_overdue,
  j.status = 'awaiting_review' as is_awaiting_review,
  round(extract(epoch from (j.responded_at - j.received_at)) / 60) as response_minutes,
  round(extract(epoch from (coalesce(j.closed_at, j.cancelled_at, now()) - j.received_at)) / 60)
    as elapsed_minutes,
  case when j.status not in ('closed', 'cancelled') and j.target_completion_at is not null
    then round(extract(epoch from (j.target_completion_at - now())) / 60)
  end as remaining_minutes,
  case
    when j.status not in ('closed', 'cancelled') and j.target_completion_at < now()
      then round(extract(epoch from (now() - j.target_completion_at)) / 60)
    when j.status = 'closed' and j.closed_at > j.target_completion_at
      then round(extract(epoch from (j.closed_at - j.target_completion_at)) / 60)
  end as overdue_minutes,
  case
    when j.status = 'cancelled' then 'cancelled'
    when j.target_completion_at is null then 'no_target'
    when j.status = 'closed' then
      case when j.closed_at <= j.target_completion_at then 'completed_on_time' else 'completed_late' end
    when now() > j.target_completion_at then 'overdue'
    when j.target_completion_at - now()
      <= (j.target_completion_at - j.received_at) * (st.at_risk_percent::double precision / 100)
      then 'at_risk'
    else 'on_time'
  end as sla_state,
  case
    when j.target_response_at is null then null
    when j.responded_at is not null then j.responded_at <= j.target_response_at
    when now() > j.target_response_at then false
  end as response_target_met
from public.job_cards j
join public.sites s on s.id = j.site_id
left join public.areas ar on ar.id = j.area_id
left join public.departments dp on dp.id = j.requesting_department_id
left join public.job_categories ct on ct.id = j.category_id
left join public.priority_levels pl on pl.code = j.priority
left join public.service_requests sr on sr.id = j.request_id
left join public.assets a on a.id = j.asset_id
left join public.profiles rsp on rsp.id = j.responsible_id
left join public.profiles asg on asg.id = j.assigned_by
left join public.profiles reg on reg.id = j.registered_by
left join lateral (
  select max(h.changed_at) as last_change_at
  from public.job_status_history h
  where h.job_card_id = j.id
) hist on true
cross join (select at_risk_percent from public.system_settings limit 1) st
where not j.is_archived;

-- ---------------------------------------------------------------------------
-- Row level security: read only; writes go through the functions in 0005
-- ---------------------------------------------------------------------------
alter table public.departments enable row level security;
alter table public.system_settings enable row level security;
alter table public.priority_levels enable row level security;
alter table public.job_categories enable row level security;
alter table public.asset_categories enable row level security;
alter table public.assets enable row level security;
alter table public.escalation_contacts enable row level security;
alter table public.doc_sequences enable row level security;
alter table public.service_requests enable row level security;
alter table public.request_attachments enable row level security;
alter table public.job_cards enable row level security;
alter table public.job_assignments enable row level security;
alter table public.job_status_history enable row level security;
alter table public.job_comments enable row level security;
alter table public.job_attachments enable row level security;
alter table public.job_closures enable row level security;
alter table public.job_status_transitions enable row level security;

-- Reference data: any active user
create policy departments_select on public.departments for select to authenticated
  using (public._active());
create policy system_settings_select on public.system_settings for select to authenticated
  using (public._active());
create policy priority_levels_select on public.priority_levels for select to authenticated
  using (public._active());
create policy job_categories_select on public.job_categories for select to authenticated
  using (public._active());
create policy asset_categories_select on public.asset_categories for select to authenticated
  using (public._active());
create policy job_status_transitions_select on public.job_status_transitions for select to authenticated
  using (public._active());

-- Escalation contacts: settings managers (doc_sequences has no policy: internal)
create policy escalation_contacts_select on public.escalation_contacts for select to authenticated
  using (public._can('settings.manage', null));

-- Assets: anyone who views assets or job cards, or raises requests, at the site
create policy assets_select on public.assets for select to authenticated
  using (
    public._can('assets.view', site_id)
    or public._can('jc.view', site_id)
    or public._can('req.submit', site_id)
  );

-- Requests: the requester, triage and job card viewers at the site
create policy service_requests_select on public.service_requests for select to authenticated
  using (
    (requested_by = auth.uid() and public._active())
    or public._can('req.triage', site_id)
    or public._can('jc.view', site_id)
  );
create policy request_attachments_select on public.request_attachments for select to authenticated
  using (exists (
    select 1 from public.service_requests r
    where r.id = request_attachments.request_id
      and (
        (r.requested_by = auth.uid() and public._active())
        or public._can('req.triage', r.site_id)
        or public._can('jc.view', r.site_id)
      )
  ));

-- Job cards and their records: jc.view at the site. Requesters follow their
-- request through fn_request_tracking (0005), never these tables.
create policy job_cards_select on public.job_cards for select to authenticated
  using (public._can('jc.view', site_id));
create policy job_assignments_select on public.job_assignments for select to authenticated
  using (exists (
    select 1 from public.job_cards j
    where j.id = job_assignments.job_card_id and public._can('jc.view', j.site_id)
  ));
create policy job_status_history_select on public.job_status_history for select to authenticated
  using (exists (
    select 1 from public.job_cards j
    where j.id = job_status_history.job_card_id and public._can('jc.view', j.site_id)
  ));
create policy job_comments_select on public.job_comments for select to authenticated
  using (exists (
    select 1 from public.job_cards j
    where j.id = job_comments.job_card_id and public._can('jc.view', j.site_id)
  ));
create policy job_attachments_select on public.job_attachments for select to authenticated
  using (exists (
    select 1 from public.job_cards j
    where j.id = job_attachments.job_card_id and public._can('jc.view', j.site_id)
  ));
create policy job_closures_select on public.job_closures for select to authenticated
  using (exists (
    select 1 from public.job_cards j
    where j.id = job_closures.job_card_id and public._can('jc.view', j.site_id)
  ));

revoke all on
  public.departments, public.system_settings, public.priority_levels, public.job_categories,
  public.asset_categories, public.assets, public.escalation_contacts, public.doc_sequences,
  public.service_requests, public.request_attachments, public.job_cards, public.job_assignments,
  public.job_status_history, public.job_comments, public.job_attachments, public.job_closures,
  public.job_status_transitions, public.v_job_cards
from anon, authenticated;

grant select on
  public.departments, public.system_settings, public.priority_levels, public.job_categories,
  public.asset_categories, public.assets, public.escalation_contacts, public.service_requests,
  public.request_attachments, public.job_cards, public.job_assignments, public.job_status_history,
  public.job_comments, public.job_attachments, public.job_closures, public.job_status_transitions,
  public.v_job_cards
to authenticated;

-- ---------------------------------------------------------------------------
-- Storage: job-files, path <site_id>/jobcard/<job_id>/<file> or
-- <site_id>/request/<request_id>/<file>
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'job-files', 'job-files', false, 26214400,
  array[
    'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'application/pdf', 'text/plain',
    'text/csv', 'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  ]
)
on conflict (id) do nothing;

-- True when the object belongs to a request the caller submitted.
create function public._request_owned(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.service_requests r
    where r.requested_by = auth.uid()
      and r.id = case
        when split_part(p_name, '/', 3)
          ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
          then split_part(p_name, '/', 3)::uuid
      end
  );
$$;

create policy job_files_select on storage.objects for select to authenticated
  using (
    bucket_id = 'job-files' and (
      (split_part(name, '/', 2) = 'jobcard' and public._can('jc.view', public._path_site(name)))
      or (split_part(name, '/', 2) = 'request' and (
        public._can('req.triage', public._path_site(name))
        or public._can('jc.view', public._path_site(name))
        or public._request_owned(name)
      ))
    )
  );

-- Files upload before the call that records them (see the app's outbox), so
-- uploads check the site permission and the fn_add_* functions check the rest.
create policy job_files_insert on storage.objects for insert to authenticated
  with check (
    bucket_id = 'job-files' and (
      (split_part(name, '/', 2) = 'jobcard' and (
        public._can('jc.register', public._path_site(name))
        or public._can('jc.assess', public._path_site(name))
        or public._can('jc.execute', public._path_site(name))
      ))
      or (split_part(name, '/', 2) = 'request' and (
        public._can('req.submit', public._path_site(name))
        or public._can('req.triage', public._path_site(name))
      ))
    )
  );

-- ---------------------------------------------------------------------------
-- Helper privileges
-- ---------------------------------------------------------------------------
revoke execute on function
  public._settings(),
  public._next_doc_no(text, timestamptz),
  public._request_owned(text),
  public.fn_job_cards_response(),
  public.fn_job_status_history()
from public, anon, authenticated;

-- Storage policies call this as the signed-in user.
grant execute on function public._request_owned(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table
      public.job_cards, public.job_assignments, public.job_comments,
      public.job_attachments, public.service_requests;
  end if;
end;
$$;

insert into public.schema_migrations (filename) values ('0004_cmms_core.sql')
on conflict do nothing;
