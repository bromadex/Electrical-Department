-- 0010_requests_targets: requests from other departments and response /
-- close-by targets per priority (API.md section 15). Adopted in a light
-- form from Tafara's CMMS phase 1 (PR #19), on top of the jobs board.
--
-- Requests: people outside the electrical team (the new Requester role, or
-- anyone with req.create) ask for work. A supervisor accepts a request,
-- which posts it as a job on the board, or declines it with a reason. The
-- requester is told each step and when the job is done.
--
-- Targets: each priority has a time to respond and a time to finish. A job
-- posted without a due time gets one from its priority's target, and the
-- urgent escalation uses the urgent response time.

insert into public.permissions (code, description) values
  ('req.create', 'Send work requests to the electrical department')
on conflict (code) do nothing;

insert into public.roles (name) values ('Requester') on conflict (name) do nothing;

insert into public.role_permissions (role_id, permission_code)
select r.id, x.code
from (values
  ('Requester', 'req.create'),
  ('Technician', 'req.create'),
  ('Storekeeper', 'req.create'),
  ('Supervisor', 'req.create'),
  ('Admin', 'req.create')
) as x (role_name, code)
join public.roles r on r.name = x.role_name
on conflict do nothing;

alter table public.code_counters drop constraint code_counters_prefix_check;
alter table public.code_counters add constraint code_counters_prefix_check
  check (prefix in ('J', 'T', 'S', 'M', 'R', 'MR', 'I', 'PO', 'P', 'RQ'));

create table public.job_requests (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id),
  area_id uuid references public.areas (id),
  code text not null,
  title text not null check (length(trim(title)) between 3 and 120),
  description text check (length(description) <= 2000),
  department text check (length(department) <= 80),
  priority text not null default 'normal' check (priority in ('low', 'normal', 'urgent')),
  status text not null default 'new' check (status in ('new', 'accepted', 'declined')),
  requested_by uuid not null references public.profiles (id) default auth.uid(),
  decided_by uuid references public.profiles (id),
  decided_at timestamptz,
  decline_reason text check (length(decline_reason) <= 500),
  job_id uuid references public.jobs (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (site_id, code)
);
create index job_requests_site on public.job_requests (site_id, status, created_at desc);
create index job_requests_requester on public.job_requests (requested_by, created_at desc);
create index job_requests_job on public.job_requests (job_id) where job_id is not null;

create trigger job_requests_touch before update on public.job_requests
  for each row execute function public.fn_touch_updated_at();
create trigger job_requests_activity after insert or update on public.job_requests
  for each row execute function public.fn_log_activity();

-- ---------------------------------------------------------------------------
-- Priority targets
-- ---------------------------------------------------------------------------
create table public.priority_targets (
  priority text primary key check (priority in ('low', 'normal', 'urgent')),
  respond_minutes integer not null check (respond_minutes between 5 and 10080),
  close_hours integer not null check (close_hours between 1 and 2160),
  updated_at timestamptz not null default now()
);
insert into public.priority_targets (priority, respond_minutes, close_hours) values
  ('urgent', 30, 24),
  ('normal', 240, 72),
  ('low', 1440, 168);

-- Jobs posted without a due time get one from their priority.
create function public.fn_jobs_default_due()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.due_at is null then
    select new.created_at + make_interval(hours => t.close_hours) into new.due_at
    from public.priority_targets t where t.priority = new.priority;
  end if;
  return new;
end;
$$;

create trigger jobs_default_due
  before insert on public.jobs
  for each row execute function public.fn_jobs_default_due();

create function public.fn_set_priority_target(p_priority text, p_respond_minutes integer, p_close_hours integer)
returns public.priority_targets
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.priority_targets;
begin
  if not public._can('admin.users', null) then
    raise exception 'NOT_ALLOWED: Only a system administrator can change targets';
  end if;
  if p_respond_minutes is null or p_respond_minutes not between 5 and 10080 then
    raise exception 'INVALID: Response time must be 5 minutes to 7 days';
  end if;
  if p_close_hours is null or p_close_hours not between 1 and 2160 then
    raise exception 'INVALID: Finish time must be 1 hour to 90 days';
  end if;
  update public.priority_targets
  set respond_minutes = p_respond_minutes, close_hours = p_close_hours, updated_at = now()
  where priority = p_priority
  returning * into v;
  if v.priority is null then
    raise exception 'INVALID: Unknown priority %', p_priority;
  end if;
  return v;
end;
$$;

-- The urgent escalation now follows the urgent response target.
create or replace function public.fn_escalate_jobs()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  j public.jobs;
  v_respond integer := coalesce(
    (select respond_minutes from public.priority_targets where priority = 'urgent'), 30);
  v_count integer := 0;
begin
  for j in
    select * from public.jobs
    where not is_archived and status = 'open' and priority = 'urgent'
      and urgent_escalated_at is null
      and created_at < now() - make_interval(mins => v_respond)
    for update skip locked
  loop
    perform public.fn_notify_permission(j.site_id, 'jobs.assign', 'general',
      'Nobody has taken urgent ' || j.code, j.title, 'job:' || j.id);
    update public.jobs set urgent_escalated_at = now() where id = j.id;
    v_count := v_count + 1;
  end loop;

  for j in
    select * from public.jobs
    where not is_archived and status not in ('done', 'cancelled')
      and due_at < now() - interval '1 day' and overdue_escalated_at is null
    for update skip locked
  loop
    perform public.fn_notify_permission(j.site_id, 'checklists.manage', 'overdue',
      j.code || ' is more than a day overdue', j.title, 'job:' || j.id);
    update public.jobs set overdue_escalated_at = now() where id = j.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- Requests
-- ---------------------------------------------------------------------------
create function public.fn_create_request(
  p_client_ref uuid,
  p_site uuid,
  p_area uuid,
  p_title text,
  p_description text,
  p_department text,
  p_priority text
)
returns public.job_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_requests;
begin
  select * into v from public.job_requests where id = p_client_ref;
  if found then
    return v;
  end if;
  if not public._can('req.create', p_site) then
    raise exception 'NOT_ALLOWED: You cannot send requests to this site';
  end if;
  if length(trim(coalesce(p_title, ''))) not between 3 and 120 then
    raise exception 'INVALID: Describe what you need in 3 to 120 characters';
  end if;
  if coalesce(p_priority, 'normal') not in ('low', 'normal', 'urgent') then
    raise exception 'INVALID: Unknown priority';
  end if;
  if p_area is not null and not exists (
    select 1 from public.areas where id = p_area and site_id = p_site and not is_archived
  ) then
    raise exception 'INVALID: That area is not at this site';
  end if;
  insert into public.job_requests (id, site_id, area_id, code, title, description, department, priority)
  values (p_client_ref, p_site, p_area, public.next_code(p_site, 'RQ'), trim(p_title),
    nullif(trim(coalesce(p_description, '')), ''), nullif(trim(coalesce(p_department, '')), ''),
    coalesce(p_priority, 'normal'))
  returning * into v;
  perform public.fn_notify_permission(v.site_id, 'jobs.assign', 'approval',
    'New request ' || v.code || coalesce(' from ' || v.department, ''), v.title, 'request:' || v.id);
  return v;
end;
$$;

-- Accept: post the request as a job (optionally assigned) and link it.
create function public.fn_accept_request(p_request uuid, p_priority text, p_assignee uuid)
returns public.job_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_requests;
  j public.jobs;
  v_name text;
begin
  select * into v from public.job_requests where id = p_request for update;
  if not found or not public._can('jobs.view', v.site_id) then
    raise exception 'NOT_FOUND: Request not found';
  end if;
  if not public._can('jobs.assign', v.site_id) then
    raise exception 'NOT_ALLOWED: Only a supervisor can accept requests';
  end if;
  if v.status <> 'new' then
    raise exception 'CONFLICT: % was already %', v.code, v.status;
  end if;
  select full_name into v_name from public.profiles where id = v.requested_by;

  j := public.fn_create_job(
    gen_random_uuid(), v.site_id, v.area_id, v.title,
    concat_ws(E'\n', v.description,
      'Requested by ' || coalesce(nullif(v_name, ''), 'someone')
        || coalesce(' (' || v.department || ')', '') || ' · ' || v.code),
    coalesce(p_priority, v.priority), null, null, null);
  if p_assignee is not null then
    j := public.fn_assign_job(j.id, p_assignee);
  end if;

  update public.job_requests set
    status = 'accepted', job_id = j.id, decided_by = auth.uid(), decided_at = now()
  where id = v.id
  returning * into v;
  perform public.fn_notify(v.requested_by, v.site_id, 'general',
    v.code || ' accepted as ' || j.code, v.title, 'job:' || j.id);
  return v;
end;
$$;

create function public.fn_decline_request(p_request uuid, p_reason text)
returns public.job_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_requests;
begin
  select * into v from public.job_requests where id = p_request for update;
  if not found or not public._can('jobs.view', v.site_id) then
    raise exception 'NOT_FOUND: Request not found';
  end if;
  if not public._can('jobs.assign', v.site_id) then
    raise exception 'NOT_ALLOWED: Only a supervisor can decline requests';
  end if;
  if v.status <> 'new' then
    raise exception 'CONFLICT: % was already %', v.code, v.status;
  end if;
  if length(trim(coalesce(p_reason, ''))) = 0 then
    raise exception 'INVALID: Say why it is declined';
  end if;
  update public.job_requests set
    status = 'declined', decline_reason = trim(p_reason), decided_by = auth.uid(), decided_at = now()
  where id = v.id
  returning * into v;
  perform public.fn_notify(v.requested_by, v.site_id, 'general',
    v.code || ' was declined', trim(p_reason), 'request:' || v.id);
  return v;
end;
$$;

-- The requester hears when the job from their request is done.
create function public.fn_jobs_tell_requester()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.job_requests;
begin
  if new.status = 'done' and old.status is distinct from 'done' then
    for r in select * from public.job_requests where job_id = new.id loop
      perform public.fn_notify(r.requested_by, new.site_id, 'general',
        r.code || ' is done', coalesce(new.close_note, new.title), 'request:' || r.id);
    end loop;
  end if;
  return new;
end;
$$;

create trigger jobs_tell_requester
  after update on public.jobs
  for each row execute function public.fn_jobs_tell_requester();

revoke execute on function
  public.fn_jobs_default_due(),
  public.fn_set_priority_target(text, integer, integer),
  public.fn_create_request(uuid, uuid, uuid, text, text, text, text),
  public.fn_accept_request(uuid, text, uuid),
  public.fn_decline_request(uuid, text),
  public.fn_jobs_tell_requester()
from public, anon, authenticated;
grant execute on function
  public.fn_set_priority_target(text, integer, integer),
  public.fn_create_request(uuid, uuid, uuid, text, text, text, text),
  public.fn_accept_request(uuid, text, uuid),
  public.fn_decline_request(uuid, text)
to authenticated;

alter table public.job_requests enable row level security;
alter table public.priority_targets enable row level security;
create policy job_requests_select on public.job_requests for select to authenticated
  using (requested_by = auth.uid() or public._can('jobs.assign', site_id));
create policy priority_targets_select on public.priority_targets for select to authenticated
  using (public._active());
revoke all on public.job_requests, public.priority_targets from anon;
revoke insert, update, delete on public.job_requests, public.priority_targets from authenticated;

insert into public.schema_migrations (filename) values ('0010_requests_targets.sql')
on conflict do nothing;
