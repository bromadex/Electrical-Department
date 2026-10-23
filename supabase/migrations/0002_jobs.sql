-- 0002_jobs: jobs board (API.md section 7).
-- Jobs move only through fn_* functions; the app reads tables under RLS.

create extension if not exists pg_cron;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Like _can, but for any user (used when notifying or assigning others).
create function public._user_can(p_user uuid, p_code text, p_site uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    join public.user_roles ur on ur.user_id = p.id and not ur.is_archived
    join public.roles r on r.id = ur.role_id and not r.is_archived
    join public.role_permissions rp
      on rp.role_id = ur.role_id and not rp.is_archived
    join public.permissions pm
      on pm.code = rp.permission_code and not pm.is_archived
    where p.id = p_user
      and p.active and not p.is_archived
      and rp.permission_code = p_code
      and (ur.site_id is null or ur.site_id = p_site)
  );
$$;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table public.job_recurrences (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id),
  area_id uuid references public.areas (id),
  title text not null check (length(trim(title)) between 3 and 120),
  description text,
  priority text not null default 'normal' check (priority in ('low', 'normal', 'urgent')),
  every text not null check (every in ('daily', 'weekly', 'monthly')),
  next_run date not null,
  due_days integer not null default 1 check (due_days between 0 and 60),
  assignee_id uuid references public.profiles (id),
  created_by uuid references public.profiles (id) default auth.uid(),
  is_archived boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.jobs (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id),
  area_id uuid references public.areas (id),
  code text not null,
  title text not null check (length(trim(title)) between 3 and 120),
  description text,
  priority text not null default 'normal' check (priority in ('low', 'normal', 'urgent')),
  status text not null default 'open'
    check (status in ('open', 'taken', 'in_progress', 'waiting', 'done', 'cancelled')),
  waiting_reason text,
  due_at timestamptz,
  lat double precision check (lat between -90 and 90),
  lng double precision check (lng between -180 and 180),
  created_by uuid references public.profiles (id),
  assignee_id uuid references public.profiles (id),
  taken_at timestamptz,
  closed_at timestamptz,
  closed_by uuid references public.profiles (id),
  close_note text,
  recurrence_id uuid references public.job_recurrences (id),
  overdue_notified_at timestamptz,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (site_id, code)
);
create index jobs_site_status_idx on public.jobs (site_id, status);
create index jobs_assignee_idx on public.jobs (assignee_id) where status not in ('done', 'cancelled');
create index jobs_due_idx on public.jobs (due_at) where status not in ('done', 'cancelled');
create index jobs_updated_idx on public.jobs (updated_at desc);

create table public.job_photos (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs (id),
  kind text not null check (kind in ('before', 'after')),
  path text not null,
  created_by uuid references public.profiles (id),
  is_archived boolean not null default false,
  created_at timestamptz not null default now()
);
create index job_photos_job_idx on public.job_photos (job_id);

create table public.job_comments (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs (id),
  author_id uuid references public.profiles (id),
  body text not null check (length(trim(body)) between 1 and 2000),
  is_archived boolean not null default false,
  created_at timestamptz not null default now()
);
create index job_comments_job_idx on public.job_comments (job_id, created_at);

-- ---------------------------------------------------------------------------
-- Triggers: updated_at and activity log
-- ---------------------------------------------------------------------------
create trigger jobs_touch before update on public.jobs
  for each row execute function public.fn_touch_updated_at();
create trigger jobs_activity after insert or update on public.jobs
  for each row execute function public.fn_log_activity();
create trigger job_photos_activity after insert or update on public.job_photos
  for each row execute function public.fn_log_activity();
create trigger job_comments_activity after insert or update on public.job_comments
  for each row execute function public.fn_log_activity();
create trigger job_recurrences_activity after insert or update on public.job_recurrences
  for each row execute function public.fn_log_activity();

-- ---------------------------------------------------------------------------
-- Functions (all take p_client_ref where they create rows; repeats are no-ops)
-- ---------------------------------------------------------------------------

-- Loads a job for a write, locked, and checks the caller can see it.
create function public._job_for_write(p_job uuid)
returns public.jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.jobs;
begin
  select * into v from public.jobs where id = p_job and not is_archived for update;
  if not found or not public._can('jobs.view', v.site_id) then
    raise exception 'NOT_FOUND: Job not found';
  end if;
  return v;
end;
$$;

create function public.fn_create_job(
  p_client_ref uuid,
  p_site uuid,
  p_area uuid,
  p_title text,
  p_description text,
  p_priority text,
  p_due_at timestamptz,
  p_lat double precision,
  p_lng double precision
)
returns public.jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.jobs;
begin
  select * into v from public.jobs where id = p_client_ref;
  if found then
    return v;
  end if;
  if not public._can('jobs.create', p_site) then
    raise exception 'NOT_ALLOWED: You cannot post jobs at this site';
  end if;
  if length(trim(coalesce(p_title, ''))) not between 3 and 120 then
    raise exception 'INVALID: The title needs 3 to 120 characters';
  end if;
  if p_area is not null and not exists (
    select 1 from public.areas where id = p_area and site_id = p_site and not is_archived
  ) then
    raise exception 'INVALID: That area is not at this site';
  end if;

  insert into public.jobs (
    id, site_id, area_id, code, title, description, priority, due_at, lat, lng, created_by
  ) values (
    p_client_ref, p_site, p_area, public.next_code(p_site, 'J'), trim(p_title),
    nullif(trim(coalesce(p_description, '')), ''), coalesce(p_priority, 'normal'),
    p_due_at, p_lat, p_lng, auth.uid()
  )
  returning * into v;

  if v.priority = 'urgent' then
    perform public.fn_notify_permission(
      v.site_id, 'jobs.assign', 'general',
      'Urgent job ' || v.code, v.title, 'job:' || v.id
    );
  end if;
  return v;
end;
$$;

create function public.fn_edit_job(
  p_job uuid,
  p_title text,
  p_description text,
  p_area uuid,
  p_priority text,
  p_due_at timestamptz
)
returns public.jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.jobs := public._job_for_write(p_job);
begin
  if not (v.created_by = auth.uid() or public._can('jobs.assign', v.site_id)) then
    raise exception 'NOT_ALLOWED: Only the poster or a supervisor can edit this job';
  end if;
  if v.status in ('done', 'cancelled') then
    raise exception 'INVALID: Closed jobs cannot be edited';
  end if;
  if length(trim(coalesce(p_title, ''))) not between 3 and 120 then
    raise exception 'INVALID: The title needs 3 to 120 characters';
  end if;
  if p_area is not null and not exists (
    select 1 from public.areas where id = p_area and site_id = v.site_id and not is_archived
  ) then
    raise exception 'INVALID: That area is not at this site';
  end if;

  update public.jobs set
    title = trim(p_title),
    description = nullif(trim(coalesce(p_description, '')), ''),
    area_id = p_area,
    priority = p_priority,
    due_at = p_due_at,
    overdue_notified_at = case when p_due_at is distinct from due_at then null else overdue_notified_at end
  where id = v.id
  returning * into v;
  return v;
end;
$$;

create function public.fn_take_job(p_job uuid)
returns public.jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.jobs := public._job_for_write(p_job);
  v_name text;
begin
  if v.assignee_id = auth.uid() and v.status <> 'open' then
    return v;
  end if;
  if not public._can('jobs.close', v.site_id) then
    raise exception 'NOT_ALLOWED: You cannot take jobs at this site';
  end if;
  if v.status <> 'open' then
    select full_name into v_name from public.profiles where id = v.assignee_id;
    raise exception 'CONFLICT: % was already taken by %', v.code, coalesce(nullif(v_name, ''), 'someone else');
  end if;

  update public.jobs
  set status = 'taken', assignee_id = auth.uid(), taken_at = now()
  where id = v.id
  returning * into v;
  return v;
end;
$$;

create function public.fn_assign_job(p_job uuid, p_user uuid)
returns public.jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.jobs := public._job_for_write(p_job);
begin
  if not public._can('jobs.assign', v.site_id) then
    raise exception 'NOT_ALLOWED: Only a supervisor can assign jobs';
  end if;
  if v.status in ('done', 'cancelled') then
    raise exception 'INVALID: % is closed', v.code;
  end if;
  if p_user is null then
    update public.jobs set status = 'open', assignee_id = null, taken_at = null
    where id = v.id returning * into v;
    return v;
  end if;
  if v.assignee_id = p_user then
    return v;
  end if;
  if not public._user_can(p_user, 'jobs.close', v.site_id) then
    raise exception 'INVALID: That person cannot work jobs at this site';
  end if;

  update public.jobs
  set assignee_id = p_user,
      status = case when status = 'open' then 'taken' else status end,
      taken_at = now()
  where id = v.id
  returning * into v;

  if p_user <> auth.uid() then
    perform public.fn_notify(
      p_user, v.site_id, 'assigned',
      v.code || ' assigned to you', v.title, 'job:' || v.id
    );
  end if;
  return v;
end;
$$;

-- in_progress / waiting / open (hand back) / cancelled. Done goes through fn_close_job.
create function public.fn_set_job_status(p_job uuid, p_status text, p_reason text)
returns public.jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.jobs := public._job_for_write(p_job);
  v_super boolean := public._can('jobs.assign', v.site_id);
  v_mine boolean := v.assignee_id = auth.uid();
begin
  if v.status = p_status then
    return v;
  end if;
  if v.status in ('done', 'cancelled') then
    raise exception 'INVALID: % is closed', v.code;
  end if;

  if p_status = 'cancelled' then
    if not (v_super or v.created_by = auth.uid()) then
      raise exception 'NOT_ALLOWED: Only the poster or a supervisor can cancel a job';
    end if;
    update public.jobs set status = 'cancelled', closed_at = now(), closed_by = auth.uid(),
      close_note = nullif(trim(coalesce(p_reason, '')), '')
    where id = v.id returning * into v;

  elsif p_status = 'open' then
    if not (v_super or v_mine) then
      raise exception 'NOT_ALLOWED: Only the assignee or a supervisor can hand a job back';
    end if;
    update public.jobs set status = 'open', assignee_id = null, taken_at = null, waiting_reason = null
    where id = v.id returning * into v;

  elsif p_status in ('in_progress', 'waiting') then
    if not (v_super or v_mine) then
      raise exception 'NOT_ALLOWED: Only the assignee or a supervisor can change this job';
    end if;
    if v.assignee_id is null then
      raise exception 'INVALID: Take or assign % first', v.code;
    end if;
    if p_status = 'waiting' and nullif(trim(coalesce(p_reason, '')), '') is null then
      raise exception 'INVALID: Say what the job is waiting for';
    end if;
    update public.jobs set
      status = p_status,
      waiting_reason = case when p_status = 'waiting' then trim(p_reason) end
    where id = v.id returning * into v;

  else
    raise exception 'INVALID: Unknown status %', p_status;
  end if;

  if v.created_by is not null and v.created_by <> auth.uid() and p_status = 'cancelled' then
    perform public.fn_notify(v.created_by, v.site_id, 'general',
      v.code || ' was cancelled', v.title, 'job:' || v.id);
  end if;
  return v;
end;
$$;

create function public.fn_close_job(p_job uuid, p_note text)
returns public.jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.jobs := public._job_for_write(p_job);
begin
  if v.status = 'done' then
    return v;
  end if;
  if v.status = 'cancelled' then
    raise exception 'INVALID: % was cancelled', v.code;
  end if;
  if not (
    (v.assignee_id = auth.uid() and public._can('jobs.close', v.site_id))
    or public._can('jobs.assign', v.site_id)
  ) then
    raise exception 'NOT_ALLOWED: Only the assignee or a supervisor can close this job';
  end if;
  if nullif(trim(coalesce(p_note, '')), '') is null then
    raise exception 'INVALID: Add a note saying what was done';
  end if;
  if not exists (
    select 1 from public.job_photos
    where job_id = v.id and kind = 'after' and not is_archived
  ) then
    raise exception 'INVALID: Add at least one after photo';
  end if;

  update public.jobs set
    status = 'done', closed_at = now(), closed_by = auth.uid(),
    close_note = trim(p_note), waiting_reason = null,
    assignee_id = coalesce(assignee_id, auth.uid())
  where id = v.id
  returning * into v;

  if v.created_by is not null and v.created_by <> auth.uid() then
    perform public.fn_notify(v.created_by, v.site_id, 'general',
      v.code || ' is done', v.title, 'job:' || v.id);
  end if;
  return v;
end;
$$;

create function public.fn_add_job_photo(p_client_ref uuid, p_job uuid, p_kind text, p_path text)
returns public.job_photos
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_photos;
  j public.jobs;
begin
  select * into v from public.job_photos where id = p_client_ref;
  if found then
    return v;
  end if;
  j := public._job_for_write(p_job);
  if not (public._can('jobs.create', j.site_id) or public._can('jobs.close', j.site_id)) then
    raise exception 'NOT_ALLOWED: You cannot add photos at this site';
  end if;
  if p_kind not in ('before', 'after') then
    raise exception 'INVALID: Photo kind must be before or after';
  end if;
  if split_part(p_path, '/', 1) <> j.site_id::text
     or split_part(p_path, '/', 2) <> 'job'
     or split_part(p_path, '/', 3) <> j.id::text then
    raise exception 'INVALID: Photo path must be <site>/job/<job>/<file>';
  end if;

  insert into public.job_photos (id, job_id, kind, path, created_by)
  values (p_client_ref, j.id, p_kind, p_path, auth.uid())
  returning * into v;
  return v;
end;
$$;

create function public.fn_comment_job(p_client_ref uuid, p_job uuid, p_body text)
returns public.job_comments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_comments;
  j public.jobs;
  v_author text;
  v_user uuid;
begin
  select * into v from public.job_comments where id = p_client_ref;
  if found then
    return v;
  end if;
  j := public._job_for_write(p_job);
  if length(trim(coalesce(p_body, ''))) not between 1 and 2000 then
    raise exception 'INVALID: Comments need 1 to 2000 characters';
  end if;

  insert into public.job_comments (id, job_id, author_id, body)
  values (p_client_ref, j.id, auth.uid(), trim(p_body))
  returning * into v;

  select coalesce(nullif(full_name, ''), 'Someone') into v_author
  from public.profiles where id = auth.uid();
  for v_user in
    select distinct u from unnest(array[j.created_by, j.assignee_id]) u
    where u is not null and u <> auth.uid()
  loop
    perform public.fn_notify(v_user, j.site_id, 'mentioned',
      v_author || ' commented on ' || j.code, left(v.body, 140), 'job:' || j.id);
  end loop;
  return v;
end;
$$;

-- People who can be assigned jobs at a site (for the assign picker).
create function public.fn_job_assignees(p_site uuid)
returns table (id uuid, full_name text, open_jobs integer)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.full_name,
    (select count(*)::int from public.jobs j
      where j.assignee_id = p.id and j.status in ('taken', 'in_progress', 'waiting'))
  from public.profiles p
  where public._can('jobs.view', p_site)
    and public._user_can(p.id, 'jobs.close', p_site)
  order by p.full_name;
$$;

-- Timeline for one job: its activity plus its photos' and comments'.
create function public.fn_job_history(p_job uuid)
returns table (at timestamptz, user_name text, action text, table_name text, details jsonb)
language sql
stable
security definer
set search_path = ''
as $$
  select a.at, coalesce(nullif(p.full_name, ''), 'System'), a.action, a.table_name, a.details
  from public.activity a
  left join public.profiles p on p.id = a.user_id
  where exists (
      select 1 from public.jobs j
      where j.id = p_job and public._can('jobs.view', j.site_id)
    )
    and (
      (a.table_name = 'jobs' and a.record_id = p_job)
      or (a.table_name in ('job_photos', 'job_comments')
          and (a.details ->> 'job_id')::uuid = p_job)
    )
  order by a.at;
$$;

create function public.fn_save_recurrence(
  p_client_ref uuid,
  p_site uuid,
  p_area uuid,
  p_title text,
  p_description text,
  p_priority text,
  p_every text,
  p_next_run date,
  p_due_days integer,
  p_assignee uuid,
  p_archived boolean
)
returns public.job_recurrences
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_recurrences;
begin
  if not public._can('jobs.assign', p_site) then
    raise exception 'NOT_ALLOWED: Only a supervisor can set up recurring jobs';
  end if;
  if length(trim(coalesce(p_title, ''))) not between 3 and 120 then
    raise exception 'INVALID: The title needs 3 to 120 characters';
  end if;
  if p_assignee is not null and not public._user_can(p_assignee, 'jobs.close', p_site) then
    raise exception 'INVALID: That person cannot work jobs at this site';
  end if;
  insert into public.job_recurrences as r (
    id, site_id, area_id, title, description, priority, every, next_run, due_days, assignee_id, is_archived
  ) values (
    p_client_ref, p_site, p_area, trim(p_title), nullif(trim(coalesce(p_description, '')), ''),
    p_priority, p_every, p_next_run, p_due_days, p_assignee, coalesce(p_archived, false)
  )
  on conflict (id) do update set
    area_id = excluded.area_id, title = excluded.title, description = excluded.description,
    priority = excluded.priority, every = excluded.every, next_run = excluded.next_run,
    due_days = excluded.due_days, assignee_id = excluded.assignee_id,
    is_archived = excluded.is_archived
  where r.site_id = excluded.site_id
  returning * into v;
  if v.id is null then
    raise exception 'INVALID: Recurring job belongs to another site';
  end if;
  return v;
end;
$$;

-- Daily (pg_cron): create today's jobs from due recurrences.
create function public.fn_run_recurrences()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.job_recurrences;
  v_today date := (now() at time zone 'Africa/Harare')::date;
  v_job public.jobs;
  v_count integer := 0;
begin
  for r in
    select * from public.job_recurrences
    where not is_archived and next_run <= v_today
    for update skip locked
  loop
    insert into public.jobs (
      site_id, area_id, code, title, description, priority, due_at,
      created_by, assignee_id, status, taken_at, recurrence_id
    ) values (
      r.site_id, r.area_id, public.next_code(r.site_id, 'J'), r.title, r.description,
      r.priority,
      ((v_today + r.due_days)::timestamp + time '17:00') at time zone 'Africa/Harare',
      r.created_by, r.assignee_id,
      case when r.assignee_id is null then 'open' else 'taken' end,
      case when r.assignee_id is null then null else now() end,
      r.id
    )
    returning * into v_job;

    if r.assignee_id is not null then
      perform public.fn_notify(r.assignee_id, r.site_id, 'assigned',
        v_job.code || ' assigned to you', v_job.title, 'job:' || v_job.id);
    end if;

    update public.job_recurrences set next_run = case r.every
        when 'daily' then v_today + 1
        when 'weekly' then v_today + 7
        else (v_today + interval '1 month')::date
      end
    where id = r.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- Hourly (pg_cron): tell the assignee (or supervisors) about overdue jobs, once.
create function public.fn_notify_overdue()
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
    where not is_archived
      and status not in ('done', 'cancelled')
      and due_at < now()
      and overdue_notified_at is null
    for update skip locked
  loop
    if j.assignee_id is not null then
      perform public.fn_notify(j.assignee_id, j.site_id, 'overdue',
        j.code || ' is overdue', j.title, 'job:' || j.id);
    else
      perform public.fn_notify_permission(j.site_id, 'jobs.assign', 'overdue',
        j.code || ' is overdue and unassigned', j.title, 'job:' || j.id);
    end if;
    update public.jobs set overdue_notified_at = now() where id = j.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------
revoke execute on function
  public._user_can(uuid, text, uuid),
  public._job_for_write(uuid),
  public.fn_create_job(uuid, uuid, uuid, text, text, text, timestamptz, double precision, double precision),
  public.fn_edit_job(uuid, text, text, uuid, text, timestamptz),
  public.fn_take_job(uuid),
  public.fn_assign_job(uuid, uuid),
  public.fn_set_job_status(uuid, text, text),
  public.fn_close_job(uuid, text),
  public.fn_add_job_photo(uuid, uuid, text, text),
  public.fn_comment_job(uuid, uuid, text),
  public.fn_job_assignees(uuid),
  public.fn_job_history(uuid),
  public.fn_save_recurrence(uuid, uuid, uuid, text, text, text, text, date, integer, uuid, boolean),
  public.fn_run_recurrences(),
  public.fn_notify_overdue()
from public, anon, authenticated;

grant execute on function
  public.fn_create_job(uuid, uuid, uuid, text, text, text, timestamptz, double precision, double precision),
  public.fn_edit_job(uuid, text, text, uuid, text, timestamptz),
  public.fn_take_job(uuid),
  public.fn_assign_job(uuid, uuid),
  public.fn_set_job_status(uuid, text, text),
  public.fn_close_job(uuid, text),
  public.fn_add_job_photo(uuid, uuid, text, text),
  public.fn_comment_job(uuid, uuid, text),
  public.fn_job_assignees(uuid),
  public.fn_job_history(uuid),
  public.fn_save_recurrence(uuid, uuid, uuid, text, text, text, text, date, integer, uuid, boolean)
to authenticated;

-- ---------------------------------------------------------------------------
-- RLS: read only; writes go through the functions above
-- ---------------------------------------------------------------------------
alter table public.jobs enable row level security;
alter table public.job_photos enable row level security;
alter table public.job_comments enable row level security;
alter table public.job_recurrences enable row level security;

create policy jobs_select on public.jobs for select to authenticated
  using (public._can('jobs.view', site_id));

create policy job_photos_select on public.job_photos for select to authenticated
  using (exists (
    select 1 from public.jobs j
    where j.id = job_photos.job_id and public._can('jobs.view', j.site_id)
  ));

create policy job_comments_select on public.job_comments for select to authenticated
  using (exists (
    select 1 from public.jobs j
    where j.id = job_comments.job_id and public._can('jobs.view', j.site_id)
  ));

create policy job_recurrences_select on public.job_recurrences for select to authenticated
  using (public._can('jobs.view', site_id));

revoke all on public.jobs, public.job_photos, public.job_comments, public.job_recurrences from anon;
revoke insert, update, delete on public.jobs, public.job_photos, public.job_comments, public.job_recurrences
from authenticated;

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.jobs, public.job_comments, public.job_photos;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Schedules (Africa/Harare is UTC+2: 04:00 UTC = 06:00 Harare)
-- ---------------------------------------------------------------------------
select cron.schedule('jobs-recurrences', '0 4 * * *', 'select public.fn_run_recurrences()');
select cron.schedule('jobs-overdue', '5 * * * *', 'select public.fn_notify_overdue()');

insert into public.schema_migrations (filename) values ('0002_jobs.sql')
on conflict do nothing;
