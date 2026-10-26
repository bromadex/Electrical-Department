-- 0009_safety_escalation: safety check before isolated work, and
-- escalation of urgent and long-overdue jobs (API.md section 14).
-- Adopted in a light form from Tafara's CMMS phase 2.
--
-- Safety check: on jobs that need isolation, someone records the
-- pre-work checklist (hazards, PPE, isolation agreed, LOTO applied with its
-- lock or permit number, isolation verified, tested before touch) before
-- the job can be started. It is a record of what was confirmed, not a
-- substitute for the site's permit system.
--
-- Escalation (every 10 minutes): an urgent job nobody has taken 30 minutes
-- after it was posted tells supervisors; a job still open a day after its
-- due time tells everyone who manages users or checklists at the site.
-- Each once per job.

create table public.job_safety_checks (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs (id),
  user_id uuid not null references public.profiles (id) default auth.uid(),
  items text[] not null,
  reference text check (length(reference) <= 80),
  checked_at timestamptz not null default now()
);
create index job_safety_checks_job on public.job_safety_checks (job_id, checked_at desc);

alter table public.jobs
  add column urgent_escalated_at timestamptz,
  add column overdue_escalated_at timestamptz;

-- The checks the app shows, in order. Isolation items are always asked on
-- these jobs, because only jobs that need isolation are checked.
create function public._safety_items()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array[
    'Hazards identified',
    'Correct PPE worn',
    'Work area made safe',
    'Isolation points identified and agreed',
    'Lockout/tagout applied',
    'Isolation verified',
    'Tested before touch'
  ];
$$;

create function public.fn_record_safety_check(
  p_client_ref uuid,
  p_job uuid,
  p_items text[],
  p_reference text
)
returns public.job_safety_checks
language plpgsql
security definer
set search_path = ''
as $$
declare
  j public.jobs;
  v public.job_safety_checks;
  v_missing text;
begin
  select * into v from public.job_safety_checks where id = p_client_ref;
  if found then
    return v;
  end if;
  select * into j from public.jobs where id = p_job and not is_archived;
  if not found or not public._can('jobs.view', j.site_id) then
    raise exception 'NOT_FOUND: Job not found';
  end if;
  if not (j.assignee_id = auth.uid() or public._can('jobs.assign', j.site_id)) then
    raise exception 'NOT_ALLOWED: Only the person doing the job or a supervisor can record its safety check';
  end if;
  select i into v_missing from unnest(public._safety_items()) i
  where not (i = any (coalesce(p_items, '{}'))) limit 1;
  if v_missing is not null then
    raise exception 'INVALID: Confirm "%" first', v_missing;
  end if;
  if length(trim(coalesce(p_reference, ''))) = 0 then
    raise exception 'INVALID: Enter the lock or permit number';
  end if;
  insert into public.job_safety_checks (id, job_id, items, reference)
  values (p_client_ref, j.id, public._safety_items(), trim(p_reference))
  returning * into v;
  return v;
end;
$$;

-- Jobs that need isolation cannot start without a safety check recorded
-- since they were taken.
create function public.fn_jobs_safety_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'in_progress' and old.status is distinct from 'in_progress'
     and new.isolation_required
     and not exists (
       select 1 from public.job_safety_checks c
       where c.job_id = new.id and c.checked_at >= coalesce(new.taken_at, new.created_at)
     ) then
    raise exception 'INVALID: Record the safety check before starting %', new.code;
  end if;
  return new;
end;
$$;

create trigger jobs_safety_guard
  before update on public.jobs
  for each row execute function public.fn_jobs_safety_guard();

-- Every 10 minutes (pg_cron).
create function public.fn_escalate_jobs()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  j public.jobs;
  v_count integer := 0;
begin
  for j in
    select * from public.jobs
    where not is_archived and status = 'open' and priority = 'urgent'
      and urgent_escalated_at is null and created_at < now() - interval '30 minutes'
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

revoke execute on function
  public._safety_items(),
  public.fn_record_safety_check(uuid, uuid, text[], text),
  public.fn_jobs_safety_guard(),
  public.fn_escalate_jobs()
from public, anon, authenticated;
grant execute on function
  public._safety_items(),
  public.fn_record_safety_check(uuid, uuid, text[], text)
to authenticated;

alter table public.job_safety_checks enable row level security;
create policy job_safety_checks_select on public.job_safety_checks for select to authenticated
  using (exists (
    select 1 from public.jobs j
    where j.id = job_safety_checks.job_id and public._can('jobs.view', j.site_id)
  ));
revoke all on public.job_safety_checks from anon;
revoke insert, update, delete on public.job_safety_checks from authenticated;

-- Activity log for the admin audit screen: readable by system
-- administrators as well as stats.view.
drop policy activity_select on public.activity;
create policy activity_select on public.activity for select to authenticated
  using (public._can('stats.view', null) or public._can('admin.users', null));

-- People created in the Supabase dashboard have no name, so pickers showed
-- "Unnamed". Name them from their email until an admin sets a real name,
-- and do the same for new sign-ins.
create function public._name_from_email(p_email text)
returns text
language sql
immutable
set search_path = ''
as $$
  select initcap(replace(replace(split_part(coalesce(p_email, ''), '@', 1), '.', ' '), '_', ' '));
$$;

update public.profiles p set full_name = public._name_from_email(u.email)
from auth.users u
where u.id = p.id and trim(p.full_name) = '';

create or replace function public.fn_handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), public._name_from_email(new.email)),
    new.raw_user_meta_data ->> 'phone'
  );
  return new;
end;
$$;

select cron.schedule('jobs-escalation', '*/10 * * * *', 'select public.fn_escalate_jobs()');

insert into public.schema_migrations (filename) values ('0009_safety_escalation.sql')
on conflict do nothing;
