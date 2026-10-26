-- 0012_v2_execution (Job Cards Version 2): phase 2 of the job card system (API.md section 15).
-- Work execution and time tracking, the safety checklist, closure
-- submissions and engineering reviews, closure metrics, configurable
-- escalation rules and the audit log.
--
-- Time is measured from records, never typed in:
--   * work sessions: one per person while they work (start, pause, resume);
--   * waits: opened and closed by the hold statuses, optionally excluded
--     from the completion deadline;
--   * active time merges overlapping sessions; labour time adds them up.

-- ---------------------------------------------------------------------------
-- Settings and notification types
-- ---------------------------------------------------------------------------
-- Site policy for the safety checklist before work starts (and after it
-- ends): off (the default, so nothing changes until an administrator
-- chooses), when_required (when the assessment calls for isolation, a
-- permit or lockout) or always.
alter table public.system_settings
  add column safety_before_start text not null default 'off'
    check (safety_before_start in ('off', 'when_required', 'always'));

alter table public.notifications drop constraint notifications_type_check;
alter table public.notifications add constraint notifications_type_check check (type in (
  'assigned', 'mentioned', 'overdue', 'reminder', 'approval', 'low_stock', 'meeting', 'general',
  'registered', 'critical', 'reassigned', 'on_hold', 'review', 'returned', 'closed', 'request',
  'escalation'
));

-- ---------------------------------------------------------------------------
-- Work sessions and waits
-- ---------------------------------------------------------------------------
create table public.job_work_sessions (
  id uuid primary key default gen_random_uuid(),
  job_card_id uuid not null references public.job_cards (id),
  user_id uuid not null references public.profiles (id),
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  -- pause: the person stopped; hold/submitted/cancelled/stopped: the job's
  -- status ended everyone's sessions; reassigned: they came off the job;
  -- corrected: an engineer entered or fixed the times.
  end_reason text check (end_reason in (
    'pause', 'hold', 'submitted', 'cancelled', 'stopped', 'reassigned', 'corrected'
  )),
  pause_reason text check (pause_reason in ('break', 'end_of_shift', 'other_job', 'other')),
  pause_note text,
  corrected boolean not null default false,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  check (ended_at is null or ended_at >= started_at)
);
-- One running session per person per job card.
create unique index job_work_sessions_open_idx on public.job_work_sessions (job_card_id, user_id)
  where ended_at is null and not is_archived;
create index job_work_sessions_job_idx on public.job_work_sessions (job_card_id, started_at);
create index job_work_sessions_user_idx on public.job_work_sessions (user_id, started_at);

create table public.job_waits (
  id uuid primary key default gen_random_uuid(),
  job_card_id uuid not null references public.job_cards (id),
  hold_status text not null check (hold_status in (
    'on_hold', 'awaiting_materials', 'awaiting_isolation', 'awaiting_specialist',
    'awaiting_production_clearance'
  )),
  note text,
  -- false: this wait moves the completion deadline (shown, never hidden)
  counts_toward_sla boolean not null default true,
  sla_reason text,
  sla_changed_by uuid references public.profiles (id),
  sla_changed_at timestamptz,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  started_by uuid references public.profiles (id),
  ended_by uuid references public.profiles (id),
  is_archived boolean not null default false,
  check (ended_at is null or ended_at >= started_at)
);
create unique index job_waits_open_idx on public.job_waits (job_card_id) where ended_at is null;
create index job_waits_job_idx on public.job_waits (job_card_id, started_at);

-- Every correction to recorded work time, with the reason.
create table public.job_time_corrections (
  id uuid primary key default gen_random_uuid(),
  job_card_id uuid not null references public.job_cards (id),
  session_id uuid not null references public.job_work_sessions (id),
  user_id uuid not null references public.profiles (id),
  old_started_at timestamptz,
  old_ended_at timestamptz,
  new_started_at timestamptz not null,
  new_ended_at timestamptz,
  reason text not null check (length(trim(reason)) between 5 and 2000),
  corrected_by uuid references public.profiles (id),
  corrected_at timestamptz not null default now()
);
create index job_time_corrections_job_idx on public.job_time_corrections (job_card_id);

-- ---------------------------------------------------------------------------
-- Work log: what was found and done, append-only
-- ---------------------------------------------------------------------------
create table public.job_work_records (
  id uuid primary key default gen_random_uuid(),
  job_card_id uuid not null references public.job_cards (id),
  kind text not null check (kind in (
    'work_performed', 'symptoms', 'diagnosis', 'root_cause', 'corrective_action', 'components',
    'spares_used', 'readings', 'test_results', 'safety_observation', 'recommendation',
    'follow_up', 'delay_reason'
  )),
  body text check (length(body) <= 4000),
  -- [{"name": "L1-N voltage", "value": "231", "unit": "V"}]
  readings jsonb not null default '[]'::jsonb check (jsonb_typeof(readings) = 'array'),
  author_id uuid references public.profiles (id),
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  check (nullif(trim(coalesce(body, '')), '') is not null or jsonb_array_length(readings) > 0)
);
create index job_work_records_job_idx on public.job_work_records (job_card_id, created_at);

-- ---------------------------------------------------------------------------
-- Safety checklist (a record, never a control: see the app's wording)
-- ---------------------------------------------------------------------------
create table public.safety_checklist_items (
  id uuid primary key default gen_random_uuid(),
  category_id uuid references public.job_categories (id), -- null = every category
  phase text not null check (phase in ('before', 'after')),
  label text not null check (length(trim(label)) between 3 and 120),
  -- which job cards need it: always, or only when the assessment asks for
  -- isolation, a permit or lockout/tagout
  applies_when text not null default 'always'
    check (applies_when in ('always', 'isolation', 'permit', 'loto')),
  needs_reference boolean not null default false,
  sort_order integer not null default 100,
  is_archived boolean not null default false,
  created_at timestamptz not null default now()
);

insert into public.safety_checklist_items (phase, label, applies_when, needs_reference, sort_order) values
  ('before', 'Hazards identified', 'always', false, 10),
  ('before', 'Risk assessment reference', 'always', true, 20),
  ('before', 'Electrical work authorisation held', 'always', false, 30),
  ('before', 'Correct PPE worn', 'always', false, 40),
  ('before', 'Work area safety checks done', 'always', false, 50),
  ('before', 'Pre-work briefing held', 'always', false, 60),
  ('before', 'Isolation points identified and agreed', 'isolation', false, 70),
  ('before', 'Lockout/tagout applied', 'loto', true, 80),
  ('before', 'Permit to work issued', 'permit', true, 90),
  ('before', 'Isolation verified', 'isolation', false, 100),
  ('before', 'Tested before touch', 'isolation', false, 110),
  ('after', 'Post-work inspection done', 'always', false, 210),
  ('after', 'Equipment safely reinstated', 'isolation', false, 220),
  ('after', 'Permit to work closed', 'permit', true, 230);

create table public.job_safety_records (
  id uuid primary key default gen_random_uuid(),
  job_card_id uuid not null references public.job_cards (id),
  item_id uuid not null references public.safety_checklist_items (id),
  label text not null,
  phase text not null check (phase in ('before', 'after')),
  confirmed boolean not null,
  reference text check (length(reference) <= 120),
  note text check (length(note) <= 1000),
  recorded_by uuid references public.profiles (id),
  recorded_at timestamptz not null default now(),
  is_archived boolean not null default false
);
create index job_safety_records_job_idx on public.job_safety_records (job_card_id, item_id, recorded_at desc);

-- ---------------------------------------------------------------------------
-- Closure submissions and engineering reviews (every round is kept)
-- ---------------------------------------------------------------------------
create table public.job_submissions (
  id uuid primary key default gen_random_uuid(),
  job_card_id uuid not null references public.job_cards (id),
  submitted_by uuid references public.profiles (id),
  submitted_at timestamptz not null default now(),
  completion_summary text not null,
  findings text not null,
  corrective_action text not null,
  equipment_state_after text not null
    check (equipment_state_after in ('operational', 'degraded', 'out_of_service')),
  functional_tests text,
  electrical_tests text,
  materials_used text,
  -- hours the technician reports; recorded_labour_minutes is what the
  -- sessions measured at the time, so the two can be compared
  labour_hours numeric(8, 2) check (labour_hours >= 0 and labour_hours <= 2000),
  recorded_labour_minutes integer not null default 0,
  outstanding_defects text,
  recommendations text,
  checks_confirmed boolean not null check (checks_confirmed),
  safety_confirmed boolean not null check (safety_confirmed),
  is_archived boolean not null default false
);
create index job_submissions_job_idx on public.job_submissions (job_card_id, submitted_at);

create table public.job_reviews (
  id uuid primary key default gen_random_uuid(),
  job_card_id uuid not null references public.job_cards (id),
  submission_id uuid references public.job_submissions (id),
  reviewer_id uuid references public.profiles (id),
  decision text not null check (decision in ('approve', 'reject', 'request_info')),
  notes text,
  follow_up_job_id uuid references public.job_cards (id),
  self_approved boolean not null default false,
  answer text,
  answered_by uuid references public.profiles (id),
  answered_at timestamptz,
  created_at timestamptz not null default now()
);
create index job_reviews_job_idx on public.job_reviews (job_card_id, created_at);

-- Closure metrics, frozen when closure is approved.
alter table public.job_closures
  add column submission_id uuid references public.job_submissions (id),
  add column received_at timestamptz,
  add column elapsed_minutes integer,
  add column active_minutes integer,
  add column labour_minutes integer,
  add column wait_minutes integer,
  add column sla_excluded_minutes integer,
  add column pause_count integer,
  add column response_minutes integer,
  add column assignment_minutes integer,
  add column start_minutes integer,
  add column response_target_met boolean,
  add column completion_target_met boolean,
  add column labour_hours_reported numeric(8, 2);

-- ---------------------------------------------------------------------------
-- Escalation rules (replace the single hourly overdue notice)
-- ---------------------------------------------------------------------------
create table public.escalation_rules (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 3 and 120),
  kind text not null check (kind in (
    'not_acknowledged', 'approaching_deadline', 'overdue', 'on_hold_too_long', 'review_waiting'
  )),
  priority_code text references public.priority_levels (code), -- null = every priority
  -- minutes after the trigger point; null uses the default for the kind
  -- (at-risk share for deadlines, hold_alert_hours for holds, 24 h for reviews)
  after_minutes integer check (after_minutes between 0 and 525600),
  notify_responsible boolean not null default false,
  notify_assigner boolean not null default false,
  notify_engineers boolean not null default false,
  notify_contacts boolean not null default false,
  notify_managers boolean not null default false,
  is_active boolean not null default true,
  sort_order integer not null default 100,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (notify_responsible or notify_assigner or notify_engineers or notify_contacts or notify_managers)
);

insert into public.escalation_rules (
  name, kind, priority_code, after_minutes, notify_responsible, notify_assigner,
  notify_engineers, notify_contacts, notify_managers, sort_order
) values
  ('P1 not acknowledged within its response target', 'not_acknowledged', 'P1', 0, false, false, true, true, true, 10),
  ('P2 not acknowledged within its response target', 'not_acknowledged', 'P2', 0, false, false, true, true, false, 20),
  ('Deadline approaching', 'approaching_deadline', null, null, true, true, false, false, false, 30),
  ('Overdue', 'overdue', null, 0, true, true, false, false, false, 40),
  ('P1 overdue by an hour', 'overdue', 'P1', 60, false, false, true, true, true, 50),
  ('P2 overdue by four hours', 'overdue', 'P2', 240, false, false, true, true, true, 60),
  ('Overdue by a day', 'overdue', null, 1440, false, false, true, false, true, 70),
  ('On hold too long', 'on_hold_too_long', null, null, false, true, true, false, false, 80),
  ('Waiting for engineering review', 'review_waiting', null, 1440, false, false, true, false, false, 90);

-- One notice per job card, rule and trigger point (a new deadline re-arms it).
create table public.job_escalations (
  id uuid primary key default gen_random_uuid(),
  job_card_id uuid not null references public.job_cards (id),
  rule_id uuid not null references public.escalation_rules (id),
  anchor timestamptz not null,
  sent_at timestamptz not null default now(),
  unique (job_card_id, rule_id, anchor)
);

-- Jobs already told they are overdue by the old hourly check are not told again.
insert into public.job_escalations (job_card_id, rule_id, anchor, sent_at)
select j.id, r.id, j.target_completion_at, j.overdue_notified_at
from public.job_cards j
cross join public.escalation_rules r
where j.overdue_notified_at is not null and j.target_completion_at is not null
  and r.kind = 'overdue' and r.priority_code is null and r.after_minutes = 0;

-- ---------------------------------------------------------------------------
-- Row level security, privileges and audit
-- ---------------------------------------------------------------------------
alter table public.job_work_sessions enable row level security;
alter table public.job_waits enable row level security;
alter table public.job_time_corrections enable row level security;
alter table public.job_work_records enable row level security;
alter table public.safety_checklist_items enable row level security;
alter table public.job_safety_records enable row level security;
alter table public.job_submissions enable row level security;
alter table public.job_reviews enable row level security;
alter table public.escalation_rules enable row level security;
alter table public.job_escalations enable row level security;

create policy safety_checklist_items_select on public.safety_checklist_items
  for select to authenticated using (public._active());
create policy escalation_rules_select on public.escalation_rules
  for select to authenticated using (public._active());

do $$
declare
  t text;
begin
  foreach t in array array[
    'job_work_sessions', 'job_waits', 'job_time_corrections', 'job_work_records',
    'job_safety_records', 'job_submissions', 'job_reviews', 'job_escalations'
  ] loop
    execute format(
      'create policy %1$I on public.%2$I for select to authenticated using (exists ('
      'select 1 from public.job_cards j where j.id = %2$I.job_card_id and public._can(''jc.view'', j.site_id)))',
      t || '_select', t
    );
  end loop;
end $$;

revoke all on
  public.job_work_sessions, public.job_waits, public.job_time_corrections, public.job_work_records,
  public.safety_checklist_items, public.job_safety_records, public.job_submissions, public.job_reviews,
  public.escalation_rules, public.job_escalations
from anon, authenticated;

grant select on
  public.job_work_sessions, public.job_waits, public.job_time_corrections, public.job_work_records,
  public.safety_checklist_items, public.job_safety_records, public.job_submissions, public.job_reviews,
  public.escalation_rules, public.job_escalations
to authenticated;

create trigger job_work_sessions_activity after insert or update on public.job_work_sessions
  for each row execute function public.fn_log_activity();
create trigger job_waits_activity after insert or update on public.job_waits
  for each row execute function public.fn_log_activity();
create trigger job_time_corrections_activity after insert on public.job_time_corrections
  for each row execute function public.fn_log_activity();
create trigger job_work_records_activity after insert or update on public.job_work_records
  for each row execute function public.fn_log_activity();
create trigger safety_checklist_items_activity after insert or update on public.safety_checklist_items
  for each row execute function public.fn_log_activity();
create trigger job_safety_records_activity after insert on public.job_safety_records
  for each row execute function public.fn_log_activity();
create trigger job_submissions_activity after insert or update on public.job_submissions
  for each row execute function public.fn_log_activity();
create trigger job_reviews_activity after insert or update on public.job_reviews
  for each row execute function public.fn_log_activity();
create trigger escalation_rules_activity after insert or update on public.escalation_rules
  for each row execute function public.fn_log_activity();
create trigger escalation_rules_touch before update on public.escalation_rules
  for each row execute function public.fn_touch_updated_at();

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table
      public.job_work_sessions, public.job_waits, public.job_work_records,
      public.job_submissions, public.job_reviews;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Time tracking: sessions and waits follow the status, so none is missed
-- ---------------------------------------------------------------------------
create function public.fn_job_cards_time_tracking()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status is not distinct from old.status then
    return new;
  end if;
  -- Leaving a hold ends its wait; entering one starts a wait. Whether it
  -- counts toward the deadline comes from fn_pause_work (default: it does).
  if old.status = any (public._jc_holds()) then
    update public.job_waits set ended_at = now(), ended_by = auth.uid()
    where job_card_id = new.id and ended_at is null;
  end if;
  if new.status = any (public._jc_holds()) then
    insert into public.job_waits (job_card_id, hold_status, note, counts_toward_sla, started_by)
    values (
      new.id, new.status, new.status_reason,
      coalesce(nullif(current_setting('app.wait_counts_toward_sla', true), '')::boolean, true),
      auth.uid()
    );
  end if;
  -- Work sessions only run while the job card is in progress.
  if new.status <> 'in_progress' then
    update public.job_work_sessions set
      ended_at = now(),
      end_reason = case
        when new.status = any (public._jc_holds()) then 'hold'
        when new.status = 'awaiting_review' then 'submitted'
        when new.status = 'cancelled' then 'cancelled'
        else 'stopped'
      end
    where job_card_id = new.id and ended_at is null;
  end if;
  return new;
end;
$$;

create trigger job_cards_time_tracking after update of status on public.job_cards
  for each row execute function public.fn_job_cards_time_tracking();

-- Someone taken off a job card stops working on it.
create function public.fn_job_assignments_sessions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.ended_at is not null and old.ended_at is null then
    update public.job_work_sessions set ended_at = now(), end_reason = 'reassigned'
    where job_card_id = new.job_card_id and user_id = new.user_id and ended_at is null;
  end if;
  return new;
end;
$$;

create trigger job_assignments_sessions after update of ended_at on public.job_assignments
  for each row execute function public.fn_job_assignments_sessions();

-- Job cards already on hold (including migrated jobs) get their wait, from
-- when they went on hold, so wait time and hold escalations cover them too.
insert into public.job_waits (job_card_id, hold_status, note, started_at)
select j.id, j.status, j.status_reason, coalesce((
    select max(h.changed_at) from public.job_status_history h
    where h.job_card_id = j.id and h.to_status = j.status
  ), j.updated_at)
from public.job_cards j
where j.status = any (public._jc_holds()) and not j.is_archived;

-- How far waits excluded from the deadline move it.
create function public._jc_sla_extension(p_job uuid)
returns interval
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(coalesce(w.ended_at, now()) - w.started_at), interval '0')
  from public.job_waits w
  where w.job_card_id = p_job and not w.counts_toward_sla and not w.is_archived;
$$;

-- Measured times of a job card, in seconds. Active time merges overlapping
-- sessions (two people working at once count once); labour adds them up.
create function public._jc_time_summary(p_job uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with j as (
    select * from public.job_cards where id = p_job
  ), s as (
    select ws.started_at, coalesce(ws.ended_at, now()) as ended_at, ws.end_reason
    from public.job_work_sessions ws
    where ws.job_card_id = p_job and not ws.is_archived
  ), o as (
    select started_at, ended_at,
      max(ended_at) over (order by started_at, ended_at rows between unbounded preceding and 1 preceding) as prev_end
    from s
  ), g as (
    select started_at, ended_at,
      sum(case when prev_end is null or started_at > prev_end then 1 else 0 end)
        over (order by started_at, ended_at) as grp
    from o
  ), merged as (
    select min(started_at) as a, max(ended_at) as b from g group by grp
  ), w as (
    select ww.started_at, coalesce(ww.ended_at, now()) as ended_at, ww.counts_toward_sla
    from public.job_waits ww
    where ww.job_card_id = p_job and not ww.is_archived
  )
  select jsonb_build_object(
    'active_seconds', coalesce((select sum(extract(epoch from (b - a))) from merged), 0)::bigint,
    'labour_seconds', coalesce((select sum(extract(epoch from (ended_at - started_at))) from s), 0)::bigint,
    'wait_seconds', coalesce((select sum(extract(epoch from (ended_at - started_at))) from w), 0)::bigint,
    'sla_excluded_seconds', coalesce((
      select sum(extract(epoch from (ended_at - started_at))) from w where not counts_toward_sla
    ), 0)::bigint,
    'pause_count', (select count(*) from s where end_reason in ('pause', 'hold')),
    'session_count', (select count(*) from s),
    'elapsed_seconds', (
      select extract(epoch from (coalesce(j.closed_at, j.cancelled_at, now()) - j.received_at))::bigint from j
    ),
    'response_seconds', (select extract(epoch from (j.responded_at - j.received_at))::bigint from j),
    'assignment_seconds', (select extract(epoch from (j.first_assigned_at - j.registered_at))::bigint from j),
    'start_seconds', (select extract(epoch from (j.first_started_at - j.first_assigned_at))::bigint from j)
  );
$$;

-- Required safety checks of a phase that are not yet recorded as done.
create function public._jc_safety_missing(p_job public.job_cards, p_phase text)
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_policy text := (select safety_before_start from public.system_settings limit 1);
  v_flagged boolean := coalesce(p_job.isolation_required, false)
    or coalesce(p_job.permit_required, false) or coalesce(p_job.loto_required, false);
begin
  if v_policy = 'off' or (v_policy = 'when_required' and not v_flagged) then
    return '{}'::text[];
  end if;
  return array(
    select i.label
    from public.safety_checklist_items i
    where not i.is_archived and i.phase = p_phase
      and (i.category_id is null or i.category_id = p_job.category_id)
      and (
        i.applies_when = 'always'
        or (i.applies_when = 'isolation' and coalesce(p_job.isolation_required, false))
        or (i.applies_when = 'permit' and coalesce(p_job.permit_required, false))
        or (i.applies_when = 'loto' and coalesce(p_job.loto_required, false))
      )
      and not exists (
        select 1
        from (
          select r.confirmed, r.reference
          from public.job_safety_records r
          where r.job_card_id = p_job.id and r.item_id = i.id and not r.is_archived
          order by r.recorded_at desc
          limit 1
        ) last
        where last.confirmed
          and (not i.needs_reference or nullif(trim(coalesce(last.reference, '')), '') is not null)
      )
    order by i.sort_order, i.label
  );
end;
$$;

-- People holding a permission at a site (or at all sites).
create function public._permission_holders(p_site uuid, p_code text)
returns table (user_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select distinct ur.user_id
  from public.user_roles ur
  join public.roles r on r.id = ur.role_id and not r.is_archived
  join public.role_permissions rp on rp.role_id = ur.role_id and not rp.is_archived
  join public.permissions pm on pm.code = rp.permission_code and not pm.is_archived
  join public.profiles p on p.id = ur.user_id and p.active and not p.is_archived
  where not ur.is_archived and rp.permission_code = p_code
    and (ur.site_id is null or ur.site_id = p_site);
$$;

-- ---------------------------------------------------------------------------
-- Work: start, pause and resume
-- ---------------------------------------------------------------------------
-- Start (or resume, or join as support): accepts an assigned job for the
-- responsible person, moves the job card to in progress, and opens a work
-- session for the caller. Site policy can require pre-work safety checks.
create function public.fn_start_work(p_job uuid)
returns public.job_cards
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_cards := public._jc_for_write(p_job);
  v_role text := public._jc_my_role(p_job);
  v_missing text[];
begin
  if v_role is null or not public._can('jc.execute', v.site_id) then
    raise exception 'NOT_ALLOWED: Only the assigned team can start work on %', v.number;
  end if;
  if v.status in ('assigned', 'reopened') then
    if v_role <> 'responsible' then
      raise exception 'INVALID: The responsible person accepts % first', v.number;
    end if;
    v := public._jc_set_status(v, 'accepted', null);
  end if;
  if v.status <> 'in_progress' then
    if not (v.status = 'accepted' or v.status = any (public._jc_holds())) then
      raise exception 'INVALID: Work cannot start while % is %', v.number, replace(v.status, '_', ' ');
    end if;
    v_missing := public._jc_safety_missing(v, 'before');
    if cardinality(v_missing) > 0 then
      raise exception 'INVALID: Record the safety checks before starting work: %',
        array_to_string(v_missing, ', ');
    end if;
    v := public._jc_set_status(v, 'in_progress', null);
  end if;
  update public.job_assignments set acknowledged_at = coalesce(acknowledged_at, now())
  where job_card_id = v.id and user_id = auth.uid() and ended_at is null;
  insert into public.job_work_sessions (job_card_id, user_id)
  values (v.id, auth.uid())
  on conflict (job_card_id, user_id) where ended_at is null and not is_archived do nothing;
  return v;
end;
$$;

-- Pause: a break, end of shift or other job stops only the caller's timer;
-- a hold reason (awaiting materials, isolation, ...) puts the job card on
-- hold, stops everyone's timer and starts a wait.
create function public.fn_pause_work(p_job uuid, p_reason text, p_note text, p_counts_toward_sla boolean)
returns public.job_cards
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_cards := public._jc_for_write(p_job);
  v_role text := public._jc_my_role(p_job);
  v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
  if not ((v_role is not null and public._can('jc.execute', v.site_id)) or public._can('jc.assign', v.site_id)) then
    raise exception 'NOT_ALLOWED: Only the assigned team or an engineer can pause %', v.number;
  end if;
  if length(coalesce(v_note, '')) > 1000 then
    raise exception 'INVALID: Keep the note under 1000 characters';
  end if;

  if p_reason = any (public._jc_holds()) then
    if v_note is null then
      raise exception 'INVALID: Say what the job is waiting for';
    end if;
    perform set_config('app.wait_counts_toward_sla',
      case when p_counts_toward_sla is false then 'false' else 'true' end, true);
    v := public._jc_set_status(v, p_reason, v_note);
    perform set_config('app.wait_counts_toward_sla', '', true);
    if v.assigned_by is not null then
      perform public._jc_notify(v, v.assigned_by, 'on_hold',
        v.number || ': ' || replace(p_reason, '_', ' '), v.status_reason);
    else
      perform public._notify_holders(v.site_id, 'jc.assign', 'on_hold',
        v.number || ': ' || replace(p_reason, '_', ' '), v.status_reason, 'jobcard:' || v.id);
    end if;
  elsif p_reason in ('break', 'end_of_shift', 'other_job', 'other') then
    update public.job_work_sessions set
      ended_at = now(), end_reason = 'pause', pause_reason = p_reason, pause_note = v_note
    where job_card_id = v.id and user_id = auth.uid() and ended_at is null;
    if not found then
      raise exception 'INVALID: You have no work running on %', v.number;
    end if;
  else
    raise exception 'INVALID: Choose why the work is pausing';
  end if;
  return v;
end;
$$;

-- The phase 1 status action now runs through start and pause.
create or replace function public.fn_set_job_card_status(p_job uuid, p_status text, p_reason text)
returns public.job_cards
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_cards := public._jc_for_write(p_job);
  v_role text := public._jc_my_role(p_job);
  v_missing text[];
begin
  if p_status = 'in_progress' then
    if v_role is not null and public._can('jc.execute', v.site_id) then
      return public.fn_start_work(p_job);
    end if;
    -- An engineer resuming a held job for the team: no session of their own.
    if not public._can('jc.assign', v.site_id) then
      raise exception 'NOT_ALLOWED: Only the assigned team or an engineer can change %', v.number;
    end if;
    if not (v.status = 'accepted' or v.status = any (public._jc_holds())) then
      raise exception 'INVALID: Work cannot start while % is %', v.number, replace(v.status, '_', ' ');
    end if;
    v_missing := public._jc_safety_missing(v, 'before');
    if cardinality(v_missing) > 0 then
      raise exception 'INVALID: Record the safety checks before starting work: %',
        array_to_string(v_missing, ', ');
    end if;
    return public._jc_set_status(v, 'in_progress', null);
  elsif p_status = any (public._jc_holds()) then
    return public.fn_pause_work(p_job, p_status, p_reason, true);
  end if;
  raise exception 'INVALID: Use the matching action to move a job card to %', coalesce(p_status, 'that status');
end;
$$;

-- ---------------------------------------------------------------------------
-- Work log and safety records
-- ---------------------------------------------------------------------------
create function public.fn_add_work_record(
  p_client_ref uuid,
  p_job uuid,
  p_kind text,
  p_body text,
  p_readings jsonb
)
returns public.job_work_records
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.job_work_records;
  v public.job_cards;
  v_id uuid := coalesce(p_client_ref, gen_random_uuid());
  v_readings jsonb := coalesce(p_readings, '[]'::jsonb);
  e jsonb;
begin
  select * into r from public.job_work_records where id = v_id;
  if found then
    return r;
  end if;
  v := public._jc_for_write(p_job);
  if not (
    (public._jc_my_role(p_job) is not null and public._can('jc.execute', v.site_id))
    or public._can('jc.assign', v.site_id) or public._can('jc.review', v.site_id)
  ) then
    raise exception 'NOT_ALLOWED: Only the assigned team or an engineer can add to the work log';
  end if;
  if v.status in ('closed', 'cancelled') then
    raise exception 'INVALID: Reopen % to add to its work log', v.number;
  end if;
  if p_kind is null or p_kind not in (
    'work_performed', 'symptoms', 'diagnosis', 'root_cause', 'corrective_action', 'components',
    'spares_used', 'readings', 'test_results', 'safety_observation', 'recommendation',
    'follow_up', 'delay_reason'
  ) then
    raise exception 'INVALID: Unknown work log entry type %', coalesce(p_kind, '');
  end if;
  if jsonb_typeof(v_readings) <> 'array' or jsonb_array_length(v_readings) > 50 then
    raise exception 'INVALID: Readings must be a list of up to 50 values';
  end if;
  for e in select * from jsonb_array_elements(v_readings) loop
    if length(trim(coalesce(e ->> 'name', ''))) not between 1 and 80
       or length(trim(coalesce(e ->> 'value', ''))) not between 1 and 40
       or length(coalesce(e ->> 'unit', '')) > 20 then
      raise exception 'INVALID: Each reading needs a name and a value';
    end if;
  end loop;
  if nullif(trim(coalesce(p_body, '')), '') is null and jsonb_array_length(v_readings) = 0 then
    raise exception 'INVALID: Write what was found or done, or add readings';
  end if;
  if length(coalesce(p_body, '')) > 4000 then
    raise exception 'INVALID: Keep the entry under 4000 characters';
  end if;

  insert into public.job_work_records (id, job_card_id, kind, body, readings, author_id)
  values (v_id, v.id, p_kind, nullif(trim(coalesce(p_body, '')), ''), v_readings, auth.uid())
  returning * into r;
  return r;
end;
$$;

-- p_items = [{"item_id": "...", "confirmed": true, "reference": "PTW-123", "note": "..."}]
create function public.fn_record_safety(p_job uuid, p_items jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_cards := public._jc_for_write(p_job);
  e jsonb;
  i public.safety_checklist_items;
  v_count integer := 0;
begin
  if not (
    (public._jc_my_role(p_job) is not null and public._can('jc.execute', v.site_id))
    or public._can('jc.assign', v.site_id) or public._can('jc.assess', v.site_id)
  ) then
    raise exception 'NOT_ALLOWED: Only the assigned team or an engineer can record safety checks';
  end if;
  if v.status in ('closed', 'cancelled') then
    raise exception 'INVALID: % is %', v.number, v.status;
  end if;
  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array' then
    raise exception 'INVALID: Safety checks must be a list';
  end if;
  for e in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    select * into i from public.safety_checklist_items
    where id::text = e ->> 'item_id' and not is_archived;
    if not found then
      raise exception 'INVALID: Unknown safety check';
    end if;
    if length(coalesce(e ->> 'reference', '')) > 120 or length(coalesce(e ->> 'note', '')) > 1000 then
      raise exception 'INVALID: Keep references under 120 and notes under 1000 characters';
    end if;
    insert into public.job_safety_records (job_card_id, item_id, label, phase, confirmed, reference, note, recorded_by)
    values (
      v.id, i.id, i.label, i.phase, coalesce((e ->> 'confirmed')::boolean, false),
      nullif(trim(coalesce(e ->> 'reference', '')), ''), nullif(trim(coalesce(e ->> 'note', '')), ''),
      auth.uid()
    );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- Stage 5: submit for engineering review (every submission is kept)
-- ---------------------------------------------------------------------------
create function public.fn_submit_for_review(
  p_job uuid,
  p_summary text,
  p_findings text,
  p_corrective_action text,
  p_equipment_state_after text,
  p_functional_tests text,
  p_electrical_tests text,
  p_materials_used text,
  p_labour_hours numeric,
  p_outstanding_defects text,
  p_recommendations text,
  p_checks_confirmed boolean,
  p_safety_confirmed boolean
)
returns public.job_cards
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_cards := public._jc_for_write(p_job);
  v_role text := public._jc_my_role(p_job);
  v_missing text[];
  v_labour_minutes integer;
  f text;
begin
  if not ((v_role = 'responsible' and public._can('jc.execute', v.site_id)) or public._can('jc.assign', v.site_id)) then
    raise exception 'NOT_ALLOWED: Only the responsible person can submit %', v.number;
  end if;
  if v.status <> 'in_progress' then
    raise exception 'INVALID: % must be in progress to submit it (it is %)', v.number, replace(v.status, '_', ' ');
  end if;
  if length(trim(coalesce(p_summary, ''))) not between 5 and 4000 then
    raise exception 'INVALID: Write a completion summary (5 to 4000 characters)';
  end if;
  if length(trim(coalesce(p_findings, ''))) not between 2 and 4000 then
    raise exception 'INVALID: Record the fault cause or findings';
  end if;
  if length(trim(coalesce(p_corrective_action, ''))) not between 2 and 4000 then
    raise exception 'INVALID: Record the corrective action taken';
  end if;
  if p_equipment_state_after is null
     or p_equipment_state_after not in ('operational', 'degraded', 'out_of_service') then
    raise exception 'INVALID: Record the equipment condition after the work';
  end if;
  foreach f in array array[p_functional_tests, p_electrical_tests, p_materials_used,
                           p_outstanding_defects, p_recommendations] loop
    if length(coalesce(f, '')) > 4000 then
      raise exception 'INVALID: Keep each field under 4000 characters';
    end if;
  end loop;
  if p_labour_hours is not null and (p_labour_hours < 0 or p_labour_hours > 2000) then
    raise exception 'INVALID: Labour hours must be between 0 and 2000';
  end if;
  if p_checks_confirmed is not true or p_safety_confirmed is not true then
    raise exception 'INVALID: Confirm that the required checks and safety procedures were completed';
  end if;
  v_missing := public._jc_safety_missing(v, 'after');
  if cardinality(v_missing) > 0 then
    raise exception 'INVALID: Record the post-work safety checks first: %', array_to_string(v_missing, ', ');
  end if;

  select coalesce(round(sum(extract(epoch from (coalesce(ended_at, now()) - started_at))) / 60), 0)
    into v_labour_minutes
  from public.job_work_sessions
  where job_card_id = v.id and not is_archived;

  insert into public.job_submissions (
    job_card_id, submitted_by, completion_summary, findings, corrective_action, equipment_state_after,
    functional_tests, electrical_tests, materials_used, labour_hours, recorded_labour_minutes,
    outstanding_defects, recommendations, checks_confirmed, safety_confirmed
  ) values (
    v.id, auth.uid(), trim(p_summary), trim(p_findings), trim(p_corrective_action), p_equipment_state_after,
    nullif(trim(coalesce(p_functional_tests, '')), ''), nullif(trim(coalesce(p_electrical_tests, '')), ''),
    nullif(trim(coalesce(p_materials_used, '')), ''),
    coalesce(p_labour_hours, round(v_labour_minutes / 60.0, 2)), v_labour_minutes,
    nullif(trim(coalesce(p_outstanding_defects, '')), ''), nullif(trim(coalesce(p_recommendations, '')), ''),
    true, true
  );

  update public.job_cards set
    completion_summary = trim(p_summary),
    findings = trim(p_findings),
    corrective_action = trim(p_corrective_action),
    equipment_state_after = p_equipment_state_after,
    performed_by = responsible_id
  where id = v.id
  returning * into v;
  v := public._jc_set_status(v, 'awaiting_review', null);

  perform public._notify_holders(
    v.site_id, 'jc.review', 'review', v.number || ' is ready for review', v.title, 'jobcard:' || v.id
  );
  return v;
end;
$$;

-- The phase 1 submit keeps working through the full submission.
create or replace function public.fn_submit_job_card(
  p_job uuid,
  p_summary text,
  p_findings text,
  p_corrective_action text,
  p_equipment_state_after text,
  p_checks_confirmed boolean
)
returns public.job_cards
language sql
security definer
set search_path = ''
as $$
  select public.fn_submit_for_review(
    p_job, p_summary, p_findings, p_corrective_action, p_equipment_state_after,
    null, null, null, null, null, null, p_checks_confirmed, p_checks_confirmed
  );
$$;

-- ---------------------------------------------------------------------------
-- Engineering review: approve (optionally with a follow-up job card), return
-- for more work, or ask a question. Approval freezes the closure metrics.
-- ---------------------------------------------------------------------------
create function public.fn_verify_job_card(
  p_job uuid,
  p_decision text,
  p_notes text,
  p_follow_up_title text,
  p_follow_up_description text,
  p_follow_up_priority text
)
returns public.job_cards
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_cards := public._jc_for_write(p_job);
  v_notes text := nullif(trim(coalesce(p_notes, '')), '');
  v_follow_title text := nullif(trim(coalesce(p_follow_up_title, '')), '');
  v_self boolean;
  v_submission uuid;
  v_follow public.job_cards;
  v_time jsonb;
  v_reviewer text;
  v_deadline timestamptz;
begin
  if not public._can('jc.review', v.site_id) then
    raise exception 'NOT_ALLOWED: Only an electrical engineer can verify work';
  end if;
  if v.status <> 'awaiting_review' then
    raise exception 'INVALID: % is not awaiting review', v.number;
  end if;
  v_self := coalesce(v.performed_by = auth.uid(), false) or public._jc_my_role(v.id) is not null;
  select id into v_submission from public.job_submissions
  where job_card_id = v.id and not is_archived
  order by submitted_at desc
  limit 1;

  if p_decision = 'approve' then
    if v_self and not public._can('jc.self_approve', v.site_id) then
      raise exception 'NOT_ALLOWED: You cannot approve closure of work you did';
    end if;
    if v_follow_title is not null and length(v_follow_title) not between 3 and 120 then
      raise exception 'INVALID: The follow-up job card needs a title of 3 to 120 characters';
    end if;
    update public.job_cards set verified_by = auth.uid(), self_approved = v_self
    where id = v.id
    returning * into v;
    v := public._jc_set_status(v, 'closed',
      case when v_self then 'Self-approved' || coalesce(': ' || v_notes, '') else v_notes end);

    v_time := public._jc_time_summary(v.id);
    v_deadline := v.target_completion_at + public._jc_sla_extension(v.id);
    insert into public.job_closures (
      job_card_id, closed_at, completion_summary, findings, corrective_action, equipment_state_after,
      performed_by, verified_by, self_approved, submission_id, received_at, elapsed_minutes,
      active_minutes, labour_minutes, wait_minutes, sla_excluded_minutes, pause_count,
      response_minutes, assignment_minutes, start_minutes, response_target_met,
      completion_target_met, labour_hours_reported
    ) values (
      v.id, v.closed_at, v.completion_summary, v.findings, v.corrective_action, v.equipment_state_after,
      v.performed_by, v.verified_by, v.self_approved, v_submission, v.received_at,
      round((v_time ->> 'elapsed_seconds')::numeric / 60),
      round((v_time ->> 'active_seconds')::numeric / 60),
      round((v_time ->> 'labour_seconds')::numeric / 60),
      round((v_time ->> 'wait_seconds')::numeric / 60),
      round((v_time ->> 'sla_excluded_seconds')::numeric / 60),
      (v_time ->> 'pause_count')::integer,
      round((v_time ->> 'response_seconds')::numeric / 60),
      round((v_time ->> 'assignment_seconds')::numeric / 60),
      round((v_time ->> 'start_seconds')::numeric / 60),
      case when v.target_response_at is null then null
        else v.responded_at is not null and v.responded_at <= v.target_response_at end,
      case when v_deadline is null then null else v.closed_at <= v_deadline end,
      (select labour_hours from public.job_submissions where id = v_submission)
    );

    if v_follow_title is not null then
      select coalesce(nullif(full_name, ''), 'Engineering review') into v_reviewer
      from public.profiles where id = auth.uid();
      v_follow := public.fn_register_job_card(
        null, null, v.site_id, v.area_id, v.location, null, coalesce(v_reviewer, 'Engineering review'),
        v.requesting_department_id, v.asset_id, v.equipment_name, v.equipment_asset_no,
        v.equipment_location, v.category_id, v_follow_title,
        coalesce(nullif(trim(coalesce(p_follow_up_description, '')), ''), 'Outstanding work from ' || v.number),
        v.operational_impact, coalesce(p_follow_up_priority, v.priority), null
      );
      update public.job_cards set source = 'follow_up', parent_job_id = v.id where id = v_follow.id;
    end if;

    insert into public.job_reviews (job_card_id, submission_id, reviewer_id, decision, notes, follow_up_job_id, self_approved)
    values (v.id, v_submission, auth.uid(), 'approve', v_notes, v_follow.id, v_self);

    perform public._jc_notify(v, v.responsible_id, 'closed', v.number || ' was closed', v.title);
    if v.registered_by is distinct from v.responsible_id then
      perform public._jc_notify(v, v.registered_by, 'closed', v.number || ' was closed', v.title);
    end if;
    perform public._jc_notify_requester(v, 'Your request is complete (' || v.number || ')', v.completion_summary);
  elsif p_decision = 'reject' then
    if v_notes is null then
      raise exception 'INVALID: Say what still needs to be done';
    end if;
    insert into public.job_reviews (job_card_id, submission_id, reviewer_id, decision, notes)
    values (v.id, v_submission, auth.uid(), 'reject', v_notes);
    v := public._jc_set_status(v, 'accepted', v_notes);
    perform public._jc_notify(v, v.responsible_id, 'returned', v.number || ' was returned for more work', v_notes);
  elsif p_decision = 'request_info' then
    if v_notes is null then
      raise exception 'INVALID: Write the question';
    end if;
    insert into public.job_reviews (job_card_id, submission_id, reviewer_id, decision, notes)
    values (v.id, v_submission, auth.uid(), 'request_info', v_notes);
    perform public._jc_notify(v, v.responsible_id, 'review', 'Question about ' || v.number, v_notes);
  else
    raise exception 'INVALID: Unknown decision %', coalesce(p_decision, '');
  end if;
  return v;
end;
$$;

create or replace function public.fn_review_job_card(p_job uuid, p_decision text, p_notes text)
returns public.job_cards
language sql
security definer
set search_path = ''
as $$
  select public.fn_verify_job_card(p_job, p_decision, p_notes, null, null, null);
$$;

-- The technician answers the reviewer's latest open question.
create function public.fn_answer_review(p_job uuid, p_answer text)
returns public.job_reviews
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_cards := public._jc_for_write(p_job);
  r public.job_reviews;
  v_answer text := nullif(trim(coalesce(p_answer, '')), '');
begin
  if not ((public._jc_my_role(p_job) is not null and public._can('jc.execute', v.site_id))
          or public._can('jc.assign', v.site_id)) then
    raise exception 'NOT_ALLOWED: Only the assigned team can answer for %', v.number;
  end if;
  if v_answer is null or length(v_answer) > 4000 then
    raise exception 'INVALID: Write the answer (up to 4000 characters)';
  end if;
  select * into r from public.job_reviews
  where job_card_id = v.id and decision = 'request_info' and answered_at is null
  order by created_at desc
  limit 1
  for update;
  if not found then
    raise exception 'INVALID: There is no open question on %', v.number;
  end if;
  update public.job_reviews set answer = v_answer, answered_by = auth.uid(), answered_at = now()
  where id = r.id
  returning * into r;
  perform public._jc_notify(v, r.reviewer_id, 'review', 'Answer about ' || v.number, v_answer);
  return r;
end;
$$;

-- ---------------------------------------------------------------------------
-- Time corrections (engineers; every change keeps the old values and reason)
-- ---------------------------------------------------------------------------
create function public._jc_check_session_times(
  p_job public.job_cards,
  p_user uuid,
  p_session uuid,
  p_started_at timestamptz,
  p_ended_at timestamptz,
  p_reason text
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public._can('jc.assign', p_job.site_id) then
    raise exception 'NOT_ALLOWED: Only an electrical engineer can correct work times';
  end if;
  if length(trim(coalesce(p_reason, ''))) not between 5 and 2000 then
    raise exception 'INVALID: Give a reason for the correction (at least 5 characters)';
  end if;
  if p_started_at is null then
    raise exception 'INVALID: Give the start time';
  end if;
  if p_started_at > now() or p_ended_at > now() then
    raise exception 'INVALID: Work times cannot be in the future';
  end if;
  if p_ended_at is not null and p_ended_at <= p_started_at then
    raise exception 'INVALID: The end must be after the start';
  end if;
  if p_started_at < p_job.received_at then
    raise exception 'INVALID: Work cannot start before % was received', p_job.number;
  end if;
  if exists (
    select 1 from public.job_work_sessions s
    where s.job_card_id = p_job.id and s.user_id = p_user and not s.is_archived
      and s.id is distinct from p_session
      and tstzrange(s.started_at, coalesce(s.ended_at, now()))
        && tstzrange(p_started_at, coalesce(p_ended_at, now()))
  ) then
    raise exception 'INVALID: That overlaps another work session of the same person';
  end if;
end;
$$;

create function public.fn_correct_work_session(
  p_session uuid,
  p_started_at timestamptz,
  p_ended_at timestamptz,
  p_reason text
)
returns public.job_work_sessions
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.job_work_sessions;
  v public.job_cards;
begin
  select * into s from public.job_work_sessions where id = p_session and not is_archived for update;
  if not found then
    raise exception 'NOT_FOUND: Work session not found';
  end if;
  v := public._jc_for_write(s.job_card_id);
  if p_ended_at is null and s.ended_at is not null then
    raise exception 'INVALID: A finished session needs an end time';
  end if;
  perform public._jc_check_session_times(v, s.user_id, s.id, p_started_at, p_ended_at, p_reason);

  insert into public.job_time_corrections (
    job_card_id, session_id, user_id, old_started_at, old_ended_at, new_started_at, new_ended_at,
    reason, corrected_by
  ) values (
    v.id, s.id, s.user_id, s.started_at, s.ended_at, p_started_at, p_ended_at, trim(p_reason), auth.uid()
  );
  update public.job_work_sessions set
    started_at = p_started_at,
    ended_at = p_ended_at,
    end_reason = case when p_ended_at is not null and s.ended_at is null then 'corrected' else end_reason end,
    corrected = true
  where id = s.id
  returning * into s;
  return s;
end;
$$;

-- A session someone forgot to start, entered afterwards.
create function public.fn_add_work_session(
  p_job uuid,
  p_user uuid,
  p_started_at timestamptz,
  p_ended_at timestamptz,
  p_reason text
)
returns public.job_work_sessions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_cards := public._jc_for_write(p_job);
  s public.job_work_sessions;
begin
  if p_ended_at is null then
    raise exception 'INVALID: Give the end time';
  end if;
  if not exists (select 1 from public.job_assignments where job_card_id = v.id and user_id = p_user) then
    raise exception 'INVALID: That person was never assigned to %', v.number;
  end if;
  perform public._jc_check_session_times(v, p_user, null, p_started_at, p_ended_at, p_reason);

  insert into public.job_work_sessions (job_card_id, user_id, started_at, ended_at, end_reason, corrected)
  values (v.id, p_user, p_started_at, p_ended_at, 'corrected', true)
  returning * into s;
  insert into public.job_time_corrections (
    job_card_id, session_id, user_id, new_started_at, new_ended_at, reason, corrected_by
  ) values (v.id, s.id, p_user, p_started_at, p_ended_at, trim(p_reason), auth.uid());
  return s;
end;
$$;

-- Whether a wait counts toward the completion deadline (engineers, audited).
create function public.fn_set_wait_sla(p_wait uuid, p_counts boolean, p_reason text)
returns public.job_waits
language plpgsql
security definer
set search_path = ''
as $$
declare
  w public.job_waits;
  v public.job_cards;
begin
  select * into w from public.job_waits where id = p_wait and not is_archived for update;
  if not found then
    raise exception 'NOT_FOUND: Wait not found';
  end if;
  v := public._jc_for_write(w.job_card_id);
  if not public._can('jc.assign', v.site_id) then
    raise exception 'NOT_ALLOWED: Only an electrical engineer can change this';
  end if;
  if length(trim(coalesce(p_reason, ''))) not between 5 and 1000 then
    raise exception 'INVALID: Give a reason (at least 5 characters)';
  end if;
  update public.job_waits set
    counts_toward_sla = coalesce(p_counts, true),
    sla_reason = trim(p_reason),
    sla_changed_by = auth.uid(),
    sla_changed_at = now()
  where id = w.id
  returning * into w;
  return w;
end;
$$;

-- ---------------------------------------------------------------------------
-- Everything the Work, Safety and Closure tabs show, in one call
-- ---------------------------------------------------------------------------
create function public.fn_job_work(p_job uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v public.job_cards;
  v_policy text := (select safety_before_start from public.system_settings limit 1);
  v_flagged boolean;
begin
  select * into v from public.job_cards where id = p_job and not is_archived;
  if not found or not public._can('jc.view', v.site_id) then
    raise exception 'NOT_FOUND: Job card not found';
  end if;
  v_flagged := coalesce(v.isolation_required, false) or coalesce(v.permit_required, false)
    or coalesce(v.loto_required, false);

  return jsonb_build_object(
    'now', now(),
    'time', public._jc_time_summary(v.id),
    'deadline', v.target_completion_at,
    'effective_deadline', v.target_completion_at + public._jc_sla_extension(v.id),
    'sessions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id, 'user_id', s.user_id, 'name', coalesce(nullif(p.full_name, ''), 'Someone'),
        'started_at', s.started_at, 'ended_at', s.ended_at, 'end_reason', s.end_reason,
        'pause_reason', s.pause_reason, 'pause_note', s.pause_note, 'corrected', s.corrected
      ) order by s.started_at)
      from public.job_work_sessions s
      left join public.profiles p on p.id = s.user_id
      where s.job_card_id = v.id and not s.is_archived
    ), '[]'::jsonb),
    'waits', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', w.id, 'hold_status', w.hold_status, 'note', w.note, 'started_at', w.started_at,
        'ended_at', w.ended_at, 'counts_toward_sla', w.counts_toward_sla, 'sla_reason', w.sla_reason
      ) order by w.started_at)
      from public.job_waits w
      where w.job_card_id = v.id and not w.is_archived
    ), '[]'::jsonb),
    'corrections', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id, 'session_id', c.session_id, 'person', coalesce(nullif(u.full_name, ''), 'Someone'),
        'old_started_at', c.old_started_at, 'old_ended_at', c.old_ended_at,
        'new_started_at', c.new_started_at, 'new_ended_at', c.new_ended_at, 'reason', c.reason,
        'by', coalesce(nullif(b.full_name, ''), 'Someone'), 'at', c.corrected_at
      ) order by c.corrected_at)
      from public.job_time_corrections c
      left join public.profiles u on u.id = c.user_id
      left join public.profiles b on b.id = c.corrected_by
      where c.job_card_id = v.id
    ), '[]'::jsonb),
    'records', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'kind', r.kind, 'body', r.body, 'readings', r.readings,
        'author', coalesce(nullif(p.full_name, ''), 'Someone'), 'created_at', r.created_at
      ) order by r.created_at)
      from public.job_work_records r
      left join public.profiles p on p.id = r.author_id
      where r.job_card_id = v.id and not r.is_archived
    ), '[]'::jsonb),
    'safety', jsonb_build_object(
      'policy', v_policy,
      'required', v_policy = 'always' or (v_policy = 'when_required' and v_flagged),
      'missing_before', to_jsonb(public._jc_safety_missing(v, 'before')),
      'missing_after', to_jsonb(public._jc_safety_missing(v, 'after')),
      'items', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', i.id, 'phase', i.phase, 'label', i.label, 'needs_reference', i.needs_reference,
          'applies', i.applies_when = 'always'
            or (i.applies_when = 'isolation' and coalesce(v.isolation_required, false))
            or (i.applies_when = 'permit' and coalesce(v.permit_required, false))
            or (i.applies_when = 'loto' and coalesce(v.loto_required, false)),
          'last', (
            select jsonb_build_object(
              'confirmed', r.confirmed, 'reference', r.reference, 'note', r.note,
              'by', coalesce(nullif(p.full_name, ''), 'Someone'), 'at', r.recorded_at
            )
            from public.job_safety_records r
            left join public.profiles p on p.id = r.recorded_by
            where r.job_card_id = v.id and r.item_id = i.id and not r.is_archived
            order by r.recorded_at desc
            limit 1
          )
        ) order by i.phase desc, i.sort_order, i.label)
        from public.safety_checklist_items i
        where not i.is_archived and (i.category_id is null or i.category_id = v.category_id)
      ), '[]'::jsonb)
    ),
    'submissions', coalesce((
      select jsonb_agg(to_jsonb(s) || jsonb_build_object(
        'submitted_by_name', coalesce(nullif(p.full_name, ''), 'Someone')
      ) order by s.submitted_at)
      from public.job_submissions s
      left join public.profiles p on p.id = s.submitted_by
      where s.job_card_id = v.id and not s.is_archived
    ), '[]'::jsonb),
    'reviews', coalesce((
      select jsonb_agg(to_jsonb(r) || jsonb_build_object(
        'reviewer_name', coalesce(nullif(p.full_name, ''), 'Someone'),
        'answered_by_name', nullif(a.full_name, ''),
        'follow_up_number', f.number
      ) order by r.created_at)
      from public.job_reviews r
      left join public.profiles p on p.id = r.reviewer_id
      left join public.profiles a on a.id = r.answered_by
      left join public.job_cards f on f.id = r.follow_up_job_id
      where r.job_card_id = v.id
    ), '[]'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Escalation rules: run every ten minutes by pg_cron
-- ---------------------------------------------------------------------------
create function public._jc_escalate(p_job public.job_cards, p_rule public.escalation_rules)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_title text;
  v_type text;
  v_count integer;
begin
  v_title := p_job.number || case p_rule.kind
    when 'not_acknowledged' then ' not acknowledged (' || p_job.priority || ')'
    when 'approaching_deadline' then ' deadline approaching'
    when 'overdue' then case when coalesce(p_rule.after_minutes, 0) = 0 then ' is overdue'
      else ' overdue by more than ' || case when p_rule.after_minutes % 1440 = 0
          then (p_rule.after_minutes / 1440)::text || ' d'
          when p_rule.after_minutes % 60 = 0 then (p_rule.after_minutes / 60)::text || ' h'
          else p_rule.after_minutes::text || ' min' end end
    when 'on_hold_too_long' then ' on hold too long'
    else ' waiting for engineering review'
  end;
  v_type := case p_rule.kind
    when 'approaching_deadline' then 'reminder'
    when 'overdue' then 'overdue'
    when 'on_hold_too_long' then 'on_hold'
    when 'review_waiting' then 'review'
    else 'escalation'
  end;

  insert into public.notifications (user_id, site_id, type, title, body, link)
  select distinct x.user_id, p_job.site_id, v_type, v_title, p_job.title, 'jobcard:' || p_job.id
  from (
    select p_job.responsible_id as user_id where p_rule.notify_responsible
    union select p_job.assigned_by where p_rule.notify_assigner
    union select h.user_id from public._permission_holders(p_job.site_id, 'jc.assign') h
      where p_rule.notify_engineers
        -- nobody responsible yet: the engineers hear instead
        or (p_rule.notify_responsible and p_job.responsible_id is null)
    union select ec.user_id from public.escalation_contacts ec
      where p_rule.notify_contacts and not ec.is_archived and ec.priority_code = p_job.priority
        and (ec.site_id is null or ec.site_id = p_job.site_id)
    union select h.user_id from public._permission_holders(p_job.site_id, 'stats.view') h
      where p_rule.notify_managers
  ) x
  join public.profiles p on p.id = x.user_id and p.active and not p.is_archived;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create function public.fn_run_escalations()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.system_settings := public._settings();
  r public.escalation_rules;
  j public.job_cards;
  v_deadline timestamptz;
  v_anchor timestamptz;
  v_wait timestamptz;
  v_new integer;
  v_count integer := 0;
begin
  for r in
    select * from public.escalation_rules where is_active and not is_archived order by sort_order
  loop
    for j in
      select * from public.job_cards
      where not is_archived and status not in ('closed', 'cancelled')
        and (r.priority_code is null or priority = r.priority_code)
    loop
      v_anchor := null;
      v_deadline := j.target_completion_at + public._jc_sla_extension(j.id);
      if r.kind = 'not_acknowledged' then
        if j.responded_at is null and j.target_response_at is not null
           and now() >= j.target_response_at + make_interval(mins => coalesce(r.after_minutes, 0)) then
          v_anchor := j.target_response_at;
        end if;
      elsif r.kind = 'approaching_deadline' then
        if v_deadline is not null and now() < v_deadline and (
          (r.after_minutes is not null and v_deadline - now() <= make_interval(mins => r.after_minutes))
          or (r.after_minutes is null
              and v_deadline - now() <= (v_deadline - j.received_at) * (s.at_risk_percent::double precision / 100))
        ) then
          v_anchor := v_deadline;
        end if;
      elsif r.kind = 'overdue' then
        if v_deadline is not null and now() >= v_deadline + make_interval(mins => coalesce(r.after_minutes, 0)) then
          v_anchor := v_deadline;
        end if;
      elsif r.kind = 'on_hold_too_long' then
        if j.status = any (public._jc_holds()) then
          select started_at into v_wait from public.job_waits
          where job_card_id = j.id and ended_at is null;
          if v_wait is not null
             and v_wait <= now() - make_interval(mins => coalesce(r.after_minutes, s.hold_alert_hours * 60)) then
            v_anchor := v_wait;
          end if;
        end if;
      elsif r.kind = 'review_waiting' then
        if j.status = 'awaiting_review' and j.submitted_at is not null
           and j.submitted_at <= now() - make_interval(mins => coalesce(r.after_minutes, 1440)) then
          v_anchor := j.submitted_at;
        end if;
      end if;

      if v_anchor is not null then
        insert into public.job_escalations (job_card_id, rule_id, anchor)
        values (j.id, r.id, v_anchor)
        on conflict (job_card_id, rule_id, anchor) do nothing;
        get diagnostics v_new = row_count;
        if v_new > 0 then
          perform public._jc_escalate(j, r);
          v_count := v_count + 1;
        end if;
      end if;
    end loop;
  end loop;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- Settings: escalation rules, the safety checklist and the safety policy
-- ---------------------------------------------------------------------------
create function public.fn_save_escalation_rule(
  p_id uuid,
  p_name text,
  p_kind text,
  p_priority text,
  p_after_minutes integer,
  p_notify_responsible boolean,
  p_notify_assigner boolean,
  p_notify_engineers boolean,
  p_notify_contacts boolean,
  p_notify_managers boolean,
  p_active boolean,
  p_sort_order integer,
  p_archived boolean
)
returns public.escalation_rules
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.escalation_rules;
begin
  if not public._can('settings.manage', null) then
    raise exception 'NOT_ALLOWED: Only a system administrator can change escalation rules';
  end if;
  if length(trim(coalesce(p_name, ''))) not between 3 and 120 then
    raise exception 'INVALID: The rule needs a name of 3 to 120 characters';
  end if;
  if p_kind is null or p_kind not in (
    'not_acknowledged', 'approaching_deadline', 'overdue', 'on_hold_too_long', 'review_waiting'
  ) then
    raise exception 'INVALID: Choose what the rule watches for';
  end if;
  if p_priority is not null and not exists (select 1 from public.priority_levels where code = p_priority) then
    raise exception 'INVALID: Choose a priority from P1 to P4, or all';
  end if;
  if p_after_minutes is not null and (p_after_minutes < 0 or p_after_minutes > 525600) then
    raise exception 'INVALID: The delay must be between 0 minutes and a year';
  end if;
  if not (coalesce(p_notify_responsible, false) or coalesce(p_notify_assigner, false)
          or coalesce(p_notify_engineers, false) or coalesce(p_notify_contacts, false)
          or coalesce(p_notify_managers, false)) then
    raise exception 'INVALID: Choose who the rule tells';
  end if;

  insert into public.escalation_rules as e (
    id, name, kind, priority_code, after_minutes, notify_responsible, notify_assigner,
    notify_engineers, notify_contacts, notify_managers, is_active, sort_order, is_archived
  ) values (
    coalesce(p_id, gen_random_uuid()), trim(p_name), p_kind, p_priority, p_after_minutes,
    coalesce(p_notify_responsible, false), coalesce(p_notify_assigner, false),
    coalesce(p_notify_engineers, false), coalesce(p_notify_contacts, false),
    coalesce(p_notify_managers, false), coalesce(p_active, true), coalesce(p_sort_order, 100),
    coalesce(p_archived, false)
  )
  on conflict (id) do update set
    name = excluded.name, kind = excluded.kind, priority_code = excluded.priority_code,
    after_minutes = excluded.after_minutes, notify_responsible = excluded.notify_responsible,
    notify_assigner = excluded.notify_assigner, notify_engineers = excluded.notify_engineers,
    notify_contacts = excluded.notify_contacts, notify_managers = excluded.notify_managers,
    is_active = excluded.is_active, sort_order = excluded.sort_order, is_archived = excluded.is_archived
  returning * into v;
  return v;
end;
$$;

create function public.fn_save_safety_item(
  p_id uuid,
  p_category uuid,
  p_phase text,
  p_label text,
  p_applies_when text,
  p_needs_reference boolean,
  p_sort_order integer,
  p_archived boolean
)
returns public.safety_checklist_items
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.safety_checklist_items;
begin
  if not public._can('settings.manage', null) then
    raise exception 'NOT_ALLOWED: Only a system administrator can change the safety checklist';
  end if;
  if length(trim(coalesce(p_label, ''))) not between 3 and 120 then
    raise exception 'INVALID: The check needs a label of 3 to 120 characters';
  end if;
  if p_phase is null or p_phase not in ('before', 'after') then
    raise exception 'INVALID: Choose before or after the work';
  end if;
  if coalesce(p_applies_when, 'always') not in ('always', 'isolation', 'permit', 'loto') then
    raise exception 'INVALID: Choose when the check applies';
  end if;
  if p_category is not null and not exists (
    select 1 from public.job_categories where id = p_category and not is_archived
  ) then
    raise exception 'INVALID: Unknown job category';
  end if;
  insert into public.safety_checklist_items as i (
    id, category_id, phase, label, applies_when, needs_reference, sort_order, is_archived
  ) values (
    coalesce(p_id, gen_random_uuid()), p_category, p_phase, trim(p_label), coalesce(p_applies_when, 'always'),
    coalesce(p_needs_reference, false), coalesce(p_sort_order, 100), coalesce(p_archived, false)
  )
  on conflict (id) do update set
    category_id = excluded.category_id, phase = excluded.phase, label = excluded.label,
    applies_when = excluded.applies_when, needs_reference = excluded.needs_reference,
    sort_order = excluded.sort_order, is_archived = excluded.is_archived
  returning * into v;
  return v;
end;
$$;

create function public.fn_save_safety_policy(p_policy text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public._can('settings.manage', null) then
    raise exception 'NOT_ALLOWED: Only a system administrator can change settings';
  end if;
  if p_policy is null or p_policy not in ('off', 'when_required', 'always') then
    raise exception 'INVALID: Choose when safety checks are required';
  end if;
  update public.system_settings set safety_before_start = p_policy, updated_by = auth.uid();
end;
$$;

-- ---------------------------------------------------------------------------
-- Audit log (audit.view at all sites)
-- ---------------------------------------------------------------------------
create function public.fn_audit_log(
  p_from timestamptz,
  p_to timestamptz,
  p_table text,
  p_user uuid,
  p_query text,
  p_limit integer,
  p_offset integer
)
returns table (
  id uuid,
  at timestamptz,
  user_id uuid,
  user_name text,
  table_name text,
  record_id uuid,
  record_label text,
  action text,
  details jsonb,
  total bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  with entries as (
    select a.id, a.at, a.user_id, coalesce(nullif(p.full_name, ''), 'System') as user_name,
      a.table_name, a.record_id,
      case a.table_name
        when 'job_cards' then (select x.number from public.job_cards x where x.id = a.record_id)
        when 'service_requests' then (select x.request_no from public.service_requests x where x.id = a.record_id)
        when 'assets' then (select x.asset_no || ' ' || x.name from public.assets x where x.id = a.record_id)
        when 'profiles' then (select x.full_name from public.profiles x where x.id = a.record_id)
        when 'sites' then (select x.name from public.sites x where x.id = a.record_id)
        when 'areas' then (select x.name from public.areas x where x.id = a.record_id)
        when 'escalation_rules' then (select x.name from public.escalation_rules x where x.id = a.record_id)
        when 'safety_checklist_items' then (select x.label from public.safety_checklist_items x where x.id = a.record_id)
        when 'job_assignments' then (select j.number from public.job_assignments x join public.job_cards j on j.id = x.job_card_id where x.id = a.record_id)
        when 'job_card_comments' then (select j.number from public.job_card_comments x join public.job_cards j on j.id = x.job_card_id where x.id = a.record_id)
        when 'job_attachments' then (select j.number from public.job_attachments x join public.job_cards j on j.id = x.job_card_id where x.id = a.record_id)
        when 'job_closures' then (select j.number from public.job_closures x join public.job_cards j on j.id = x.job_card_id where x.id = a.record_id)
        when 'job_work_sessions' then (select j.number from public.job_work_sessions x join public.job_cards j on j.id = x.job_card_id where x.id = a.record_id)
        when 'job_waits' then (select j.number from public.job_waits x join public.job_cards j on j.id = x.job_card_id where x.id = a.record_id)
        when 'job_time_corrections' then (select j.number from public.job_time_corrections x join public.job_cards j on j.id = x.job_card_id where x.id = a.record_id)
        when 'job_work_records' then (select j.number from public.job_work_records x join public.job_cards j on j.id = x.job_card_id where x.id = a.record_id)
        when 'job_safety_records' then (select j.number from public.job_safety_records x join public.job_cards j on j.id = x.job_card_id where x.id = a.record_id)
        when 'job_submissions' then (select j.number from public.job_submissions x join public.job_cards j on j.id = x.job_card_id where x.id = a.record_id)
        when 'job_reviews' then (select j.number from public.job_reviews x join public.job_cards j on j.id = x.job_card_id where x.id = a.record_id)
      end as record_label,
      a.action, a.details
    from public.activity a
    left join public.profiles p on p.id = a.user_id
    where public._can('audit.view', null)
      and not a.is_archived
      and (p_from is null or a.at >= p_from)
      and (p_to is null or a.at < p_to)
      and (p_table is null or a.table_name = p_table)
      and (p_user is null or a.user_id = p_user)
  )
  select r.id, r.at, r.user_id, r.user_name, r.table_name, r.record_id, r.record_label, r.action,
    r.details, count(*) over () as total
  from entries r
  where p_query is null or trim(p_query) = ''
    or r.record_label ilike '%' || trim(p_query) || '%'
    or r.user_name ilike '%' || trim(p_query) || '%'
    or r.details::text ilike '%' || trim(p_query) || '%'
  order by r.at desc
  limit least(greatest(coalesce(p_limit, 50), 1), 200)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

-- ---------------------------------------------------------------------------
-- Timeline: phase 1 events plus work sessions, waits, the work log, safety
-- checks, submissions, reviews, time corrections and escalations
-- ---------------------------------------------------------------------------
create or replace function public.fn_job_card_timeline(p_job uuid)
returns table (at timestamptz, actor text, kind text, title text, detail text)
language sql
stable
security definer
set search_path = ''
as $$
  with j as (
    select jc.id from public.job_cards jc
    where jc.id = p_job and public._can('jc.view', jc.site_id)
  )
  select x.at, x.actor, x.kind, x.title, x.detail
  from (
    select h.changed_at as at, coalesce(nullif(p.full_name, ''), 'System') as actor, 'status' as kind,
      case when h.from_status is null then 'Registered as ' || replace(h.to_status, '_', ' ')
        else replace(h.from_status, '_', ' ') || ' → ' || replace(h.to_status, '_', ' ') end as title,
      h.reason as detail
    from public.job_status_history h
    join j on j.id = h.job_card_id
    left join public.profiles p on p.id = h.changed_by

    union all
    select a.assigned_at, coalesce(nullif(p.full_name, ''), 'System'), 'assignment',
      coalesce(nullif(u.full_name, ''), 'Someone')
        || case a.role when 'responsible' then ' made responsible' else ' added as support' end,
      null
    from public.job_assignments a
    join j on j.id = a.job_card_id
    left join public.profiles p on p.id = a.assigned_by
    left join public.profiles u on u.id = a.user_id

    union all
    select a.acknowledged_at, coalesce(nullif(u.full_name, ''), 'Someone'), 'assignment',
      coalesce(nullif(u.full_name, ''), 'Someone') || ' acknowledged the job', null
    from public.job_assignments a
    join j on j.id = a.job_card_id
    left join public.profiles u on u.id = a.user_id
    where a.acknowledged_at is not null

    union all
    select a.ended_at, 'System', 'assignment',
      coalesce(nullif(u.full_name, ''), 'Someone') || ' came off the job (' || coalesce(a.end_reason, 'ended') || ')',
      a.handover_note
    from public.job_assignments a
    join j on j.id = a.job_card_id
    left join public.profiles u on u.id = a.user_id
    where a.ended_at is not null

    union all
    select s.started_at, coalesce(nullif(u.full_name, ''), 'Someone'), 'work',
      'Started work' || case when s.corrected then ' (entered by an engineer)' else '' end, null
    from public.job_work_sessions s
    join j on j.id = s.job_card_id
    left join public.profiles u on u.id = s.user_id
    where not s.is_archived

    union all
    select s.ended_at, coalesce(nullif(u.full_name, ''), 'Someone'), 'work',
      case s.end_reason
        when 'pause' then 'Paused (' || replace(coalesce(s.pause_reason, 'other'), '_', ' ') || ')'
        when 'hold' then 'Stopped: job on hold'
        when 'submitted' then 'Stopped: submitted for review'
        when 'reassigned' then 'Stopped: came off the job'
        when 'corrected' then 'Stopped (time entered by an engineer)'
        else 'Stopped work'
      end,
      s.pause_note
    from public.job_work_sessions s
    join j on j.id = s.job_card_id
    left join public.profiles u on u.id = s.user_id
    where not s.is_archived and s.ended_at is not null

    union all
    select w.sla_changed_at, coalesce(nullif(p.full_name, ''), 'Someone'), 'work',
      case when w.counts_toward_sla then 'Wait counts toward the deadline again'
        else 'Wait excluded from the deadline' end,
      w.sla_reason
    from public.job_waits w
    join j on j.id = w.job_card_id
    left join public.profiles p on p.id = w.sla_changed_by
    where w.sla_changed_at is not null

    union all
    select c.corrected_at, coalesce(nullif(p.full_name, ''), 'Someone'), 'correction',
      'Corrected work time of ' || coalesce(nullif(u.full_name, ''), 'someone'),
      c.reason
    from public.job_time_corrections c
    join j on j.id = c.job_card_id
    left join public.profiles p on p.id = c.corrected_by
    left join public.profiles u on u.id = c.user_id

    union all
    select r.created_at, coalesce(nullif(p.full_name, ''), 'Someone'), 'work',
      'Work log: ' || replace(r.kind, '_', ' '), r.body
    from public.job_work_records r
    join j on j.id = r.job_card_id
    left join public.profiles p on p.id = r.author_id
    where not r.is_archived

    union all
    select r.recorded_at, coalesce(nullif(p.full_name, ''), 'Someone'), 'safety',
      case when r.confirmed then 'Safety check done: ' else 'Safety check not done: ' end || r.label,
      concat_ws(' · ', r.reference, r.note)
    from public.job_safety_records r
    join j on j.id = r.job_card_id
    left join public.profiles p on p.id = r.recorded_by
    where not r.is_archived

    union all
    select s.submitted_at, coalesce(nullif(p.full_name, ''), 'Someone'), 'review',
      'Submitted for review', s.completion_summary
    from public.job_submissions s
    join j on j.id = s.job_card_id
    left join public.profiles p on p.id = s.submitted_by
    where not s.is_archived

    union all
    select r.created_at, coalesce(nullif(p.full_name, ''), 'Someone'), 'review',
      case r.decision
        when 'approve' then 'Closure approved' || case when r.self_approved then ' (self-approved)' else '' end
        when 'reject' then 'Returned for more work'
        else 'Asked a question'
      end,
      r.notes
    from public.job_reviews r
    join j on j.id = r.job_card_id
    left join public.profiles p on p.id = r.reviewer_id

    union all
    select r.answered_at, coalesce(nullif(p.full_name, ''), 'Someone'), 'review',
      'Answered the reviewer', r.answer
    from public.job_reviews r
    join j on j.id = r.job_card_id
    left join public.profiles p on p.id = r.answered_by
    where r.answered_at is not null

    union all
    select e.sent_at, 'System', 'escalation', 'Escalated: ' || er.name, null
    from public.job_escalations e
    join j on j.id = e.job_card_id
    join public.escalation_rules er on er.id = e.rule_id

    union all
    select c.created_at, coalesce(nullif(p.full_name, ''), 'Someone'), 'comment',
      case c.kind when 'comment' then 'Comment' else initcap(c.kind) end
        || case when c.visibility = 'requester' then ' (visible to requester)' else '' end,
      c.body
    from public.job_card_comments c
    join j on j.id = c.job_card_id
    left join public.profiles p on p.id = c.author_id
    where not c.is_archived

    union all
    select f.created_at, coalesce(nullif(p.full_name, ''), 'Someone'), 'attachment',
      'Added ' || replace(f.kind, '_', ' '), coalesce(f.file_name, f.caption)
    from public.job_attachments f
    join j on j.id = f.job_card_id
    left join public.profiles p on p.id = f.uploaded_by
    where not f.is_archived

    union all
    select ac.at, coalesce(nullif(p.full_name, ''), 'System'), 'update',
      'Updated ' || (
        select string_agg(replace(t.k, '_', ' '), ', ' order by t.k)
        from jsonb_object_keys(ac.details) as t (k)
        where t.k not in ('overdue_notified_at', 'responded_at')
      ),
      null
    from public.activity ac
    join j on ac.table_name = 'job_cards' and ac.record_id = j.id
    left join public.profiles p on p.id = ac.user_id
    where ac.action = 'update'
      and exists (
        select 1 from jsonb_object_keys(ac.details) as t (k)
        where t.k not in ('overdue_notified_at', 'responded_at')
      )
  ) x
  where x.at is not null
  order by x.at;
$$;

-- ---------------------------------------------------------------------------
-- v_job_cards: the deadline now moves by waits excluded from it, and the
-- view shows who is working and whether a reviewer is waiting for an answer
-- ---------------------------------------------------------------------------
drop view public.v_job_cards;

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
  j.status not in ('closed', 'cancelled') and dl.deadline < now() as is_overdue,
  j.status = 'awaiting_review' as is_awaiting_review,
  round(extract(epoch from (j.responded_at - j.received_at)) / 60) as response_minutes,
  round(extract(epoch from (coalesce(j.closed_at, j.cancelled_at, now()) - j.received_at)) / 60)
    as elapsed_minutes,
  case when j.status not in ('closed', 'cancelled') and dl.deadline is not null
    then round(extract(epoch from (dl.deadline - now())) / 60)
  end as remaining_minutes,
  case
    when j.status not in ('closed', 'cancelled') and dl.deadline < now()
      then round(extract(epoch from (now() - dl.deadline)) / 60)
    when j.status = 'closed' and j.closed_at > dl.deadline
      then round(extract(epoch from (j.closed_at - dl.deadline)) / 60)
  end as overdue_minutes,
  case
    when j.status = 'cancelled' then 'cancelled'
    when dl.deadline is null then 'no_target'
    when j.status = 'closed' then
      case when j.closed_at <= dl.deadline then 'completed_on_time' else 'completed_late' end
    when now() > dl.deadline then 'overdue'
    when dl.deadline - now()
      <= (dl.deadline - j.received_at) * (st.at_risk_percent::double precision / 100)
      then 'at_risk'
    else 'on_time'
  end as sla_state,
  case
    when j.target_response_at is null then null
    when j.responded_at is not null then j.responded_at <= j.target_response_at
    when now() > j.target_response_at then false
  end as response_target_met,
  dl.deadline as effective_deadline,
  round(extract(epoch from wx.ext) / 60) as sla_excluded_minutes,
  sx.open_sessions,
  rx.question_open as review_question_open
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
left join lateral (
  select coalesce(sum(coalesce(w.ended_at, now()) - w.started_at), interval '0') as ext
  from public.job_waits w
  where w.job_card_id = j.id and not w.counts_toward_sla and not w.is_archived
) wx on true
left join lateral (
  select j.target_completion_at + wx.ext as deadline
) dl on true
left join lateral (
  select count(*)::integer as open_sessions
  from public.job_work_sessions ws
  where ws.job_card_id = j.id and ws.ended_at is null and not ws.is_archived
) sx on true
left join lateral (
  select exists (
    select 1 from public.job_reviews r
    where r.job_card_id = j.id and r.decision = 'request_info' and r.answered_at is null
  ) as question_open
) rx on true
cross join (select at_risk_percent from public.system_settings limit 1) st
where not j.is_archived;

revoke all on public.v_job_cards from anon, authenticated;
grant select on public.v_job_cards to authenticated;

-- ---------------------------------------------------------------------------
-- Schedules: the rules replace the hourly overdue notice
-- ---------------------------------------------------------------------------
select cron.unschedule(jobid) from cron.job where jobname = 'jobcards-overdue';
drop function public.fn_notify_overdue_job_cards();
select cron.schedule('jobcards-escalations', '*/10 * * * *', 'select public.fn_run_escalations()');

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------
revoke execute on function
  public.fn_job_cards_time_tracking(),
  public.fn_job_assignments_sessions(),
  public._jc_sla_extension(uuid),
  public._jc_time_summary(uuid),
  public._jc_safety_missing(public.job_cards, text),
  public._permission_holders(uuid, text),
  public._jc_check_session_times(public.job_cards, uuid, uuid, timestamptz, timestamptz, text),
  public._jc_escalate(public.job_cards, public.escalation_rules),
  public.fn_run_escalations(),
  public.fn_start_work(uuid),
  public.fn_pause_work(uuid, text, text, boolean),
  public.fn_add_work_record(uuid, uuid, text, text, jsonb),
  public.fn_record_safety(uuid, jsonb),
  public.fn_submit_for_review(uuid, text, text, text, text, text, text, text, numeric, text, text, boolean, boolean),
  public.fn_verify_job_card(uuid, text, text, text, text, text),
  public.fn_answer_review(uuid, text),
  public.fn_correct_work_session(uuid, timestamptz, timestamptz, text),
  public.fn_add_work_session(uuid, uuid, timestamptz, timestamptz, text),
  public.fn_set_wait_sla(uuid, boolean, text),
  public.fn_job_work(uuid),
  public.fn_save_escalation_rule(uuid, text, text, text, integer, boolean, boolean, boolean, boolean, boolean, boolean, integer, boolean),
  public.fn_save_safety_item(uuid, uuid, text, text, text, boolean, integer, boolean),
  public.fn_save_safety_policy(text),
  public.fn_audit_log(timestamptz, timestamptz, text, uuid, text, integer, integer)
from public, anon, authenticated;

grant execute on function
  public.fn_start_work(uuid),
  public.fn_pause_work(uuid, text, text, boolean),
  public.fn_add_work_record(uuid, uuid, text, text, jsonb),
  public.fn_record_safety(uuid, jsonb),
  public.fn_submit_for_review(uuid, text, text, text, text, text, text, text, numeric, text, text, boolean, boolean),
  public.fn_verify_job_card(uuid, text, text, text, text, text),
  public.fn_answer_review(uuid, text),
  public.fn_correct_work_session(uuid, timestamptz, timestamptz, text),
  public.fn_add_work_session(uuid, uuid, timestamptz, timestamptz, text),
  public.fn_set_wait_sla(uuid, boolean, text),
  public.fn_job_work(uuid),
  public.fn_save_escalation_rule(uuid, text, text, text, integer, boolean, boolean, boolean, boolean, boolean, boolean, integer, boolean),
  public.fn_save_safety_item(uuid, uuid, text, text, text, boolean, integer, boolean),
  public.fn_save_safety_policy(text),
  public.fn_audit_log(timestamptz, timestamptz, text, uuid, text, integer, integer)
to authenticated;

insert into public.schema_migrations (filename) values ('0012_v2_execution.sql')
on conflict do nothing;
