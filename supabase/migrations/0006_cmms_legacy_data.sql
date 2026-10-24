-- 0006_cmms_legacy_data: copies jobs from the retired jobs board (legacy_*,
-- see 0003) into job cards, keeps their photos readable, and keeps recurring
-- templates producing work until preventive maintenance (phase 3) replaces them.

-- ---------------------------------------------------------------------------
-- Old photos stay in the job-photos bucket; job card viewers can read them.
-- (The 0001 policies used the jobs.* codes, which 0003 archived.)
-- ---------------------------------------------------------------------------
drop policy if exists job_photos_select on storage.objects;
drop policy if exists job_photos_insert on storage.objects;

create policy legacy_job_photos_select on storage.objects for select to authenticated
  using (bucket_id = 'job-photos' and public._can('jc.view', public._path_site(name)));

-- ---------------------------------------------------------------------------
-- Copy: one job card per legacy job, safe to run more than once
-- ---------------------------------------------------------------------------
create function public._migrate_legacy_jobs()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  j public.legacy_jobs;
  v public.job_cards;
  v_status text;
  v_reason text;
  v_reporter text;
  v_description text;
  v_count integer := 0;
begin
  for j in
    select * from public.legacy_jobs lj
    where not lj.is_archived
      and not exists (
        select 1 from public.job_cards jc where jc.site_id = lj.site_id and jc.legacy_code = lj.code
      )
    order by lj.created_at
  loop
    -- Open jobs were never assessed, so they start as registered.
    v_status := case j.status
      when 'open' then 'registered'
      when 'taken' then 'assigned'
      when 'in_progress' then 'in_progress'
      when 'waiting' then 'on_hold'
      when 'done' then 'closed'
      else 'cancelled'
    end;
    if v_status in ('assigned', 'in_progress', 'on_hold') and j.assignee_id is null then
      v_status := 'registered';
    end if;
    v_reason := case v_status
      when 'on_hold' then coalesce(nullif(trim(j.waiting_reason), ''), 'Waiting (reason not recorded)')
      when 'cancelled' then coalesce(nullif(trim(j.close_note), ''), 'Cancelled on the jobs board')
    end;
    select coalesce(nullif(trim(p.full_name), ''), 'Not recorded (migrated)') into v_reporter
    from public.profiles p where p.id = j.created_by;
    v_description := coalesce(nullif(trim(j.description), ''), j.title);
    if length(v_description) < 5 then
      v_description := v_description || ' (migrated)';
    end if;

    insert into public.job_cards (
      number, legacy_code, source, site_id, area_id, location,
      received_at, registered_at, reporter_name, registered_by, title, description, priority,
      maintenance_type, target_completion_at, status, status_reason,
      responsible_id, first_assigned_at, assigned_at, first_started_at,
      closed_at, closure_approved_at, cancelled_at,
      completion_summary, performed_by, verified_by, legacy_closure, created_at
    ) values (
      public._next_doc_no('jobcard', j.created_at), j.code, 'legacy', j.site_id, j.area_id,
      case when j.area_id is null then 'Not recorded (migrated from the jobs board)' end,
      j.created_at, j.created_at, coalesce(v_reporter, 'Not recorded (migrated)'), j.created_by,
      left(j.title, 120), left(v_description, 4000),
      case j.priority when 'urgent' then 'P2' when 'low' then 'P4' else 'P3' end,
      case when j.recurrence_id is not null then 'preventive' else 'reactive' end,
      j.due_at, v_status, v_reason,
      case when v_status in ('assigned', 'in_progress', 'on_hold', 'closed') then j.assignee_id end,
      case when v_status <> 'registered' then j.taken_at end,
      case when v_status <> 'registered' then j.taken_at end,
      case when v_status in ('in_progress', 'on_hold') then j.taken_at end,
      case when v_status = 'closed' then coalesce(j.closed_at, j.updated_at) end,
      case when v_status = 'closed' then coalesce(j.closed_at, j.updated_at) end,
      case when v_status = 'cancelled' then coalesce(j.closed_at, j.updated_at) end,
      case when v_status = 'closed' then j.close_note end,
      case when v_status = 'closed' then j.assignee_id end,
      case when v_status = 'closed' then j.closed_by end,
      v_status = 'closed',
      j.created_at
    )
    returning * into v;

    if v.responsible_id is not null then
      insert into public.job_assignments (job_card_id, user_id, role, assigned_at, acknowledged_at)
      values (v.id, v.responsible_id, 'responsible', coalesce(j.taken_at, j.created_at), j.taken_at);
    end if;

    insert into public.job_attachments (job_card_id, kind, bucket, path, uploaded_by, created_at)
    select v.id, case p.kind when 'after' then 'photo_after' else 'photo_before' end,
      'job-photos', p.path, p.created_by, p.created_at
    from public.legacy_job_photos p
    where p.job_id = j.id and not p.is_archived
    on conflict (bucket, path) do nothing;

    insert into public.job_comments (job_card_id, author_id, kind, visibility, body, created_at)
    select v.id, c.author_id, 'comment', 'internal', c.body, c.created_at
    from public.legacy_job_comments c
    where c.job_id = j.id and not c.is_archived;

    if v.status = 'closed' then
      insert into public.job_closures (
        job_card_id, closed_at, completion_summary, performed_by, verified_by, legacy, created_at
      ) values (
        v.id, v.closed_at, v.completion_summary, v.performed_by, v.verified_by, true, v.closed_at
      );
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

select public._migrate_legacy_jobs();

-- ---------------------------------------------------------------------------
-- Bridge: recurring templates from the jobs board create job cards (daily)
-- until phase 3 moves them into preventive maintenance plans.
-- ---------------------------------------------------------------------------
create function public.fn_run_legacy_recurrences()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.legacy_job_recurrences;
  s public.system_settings := public._settings();
  v_today date := (now() at time zone s.timezone)::date;
  v public.job_cards;
  pl public.priority_levels;
  v_reporter text;
  v_count integer := 0;
begin
  for r in
    select * from public.legacy_job_recurrences
    where not is_archived and next_run <= v_today
    for update skip locked
  loop
    select * into pl from public.priority_levels
    where code = case r.priority when 'urgent' then 'P2' when 'low' then 'P4' else 'P3' end;
    select coalesce(nullif(trim(p.full_name), ''), 'Scheduled maintenance') into v_reporter
    from public.profiles p where p.id = r.created_by;

    insert into public.job_cards (
      number, source, site_id, area_id, location, received_at, reporter_name, registered_by,
      title, description, operational_impact, priority, maintenance_type, is_valid,
      target_response_at, target_completion_at, status,
      responsible_id, assigned_by, first_assigned_at, assigned_at
    ) values (
      public._next_doc_no('jobcard', now()), 'preventive', r.site_id, r.area_id,
      case when r.area_id is null then 'As set in the recurring job template' end,
      now(), coalesce(v_reporter, 'Scheduled maintenance'), r.created_by,
      left(r.title, 120),
      case when length(trim(coalesce(r.description, ''))) >= 5 then trim(r.description)
        else r.title || ' (scheduled)' end,
      'none', pl.code, 'preventive', true,
      now() + make_interval(mins => pl.response_minutes),
      ((v_today + r.due_days)::timestamp + time '17:00') at time zone s.timezone,
      case when r.assignee_id is null then 'awaiting_assignment' else 'assigned' end,
      r.assignee_id,
      case when r.assignee_id is not null then r.created_by end,
      case when r.assignee_id is not null then now() end,
      case when r.assignee_id is not null then now() end
    )
    returning * into v;

    if r.assignee_id is not null then
      insert into public.job_assignments (job_card_id, user_id, role, assigned_by)
      values (v.id, r.assignee_id, 'responsible', r.created_by);
      perform public.fn_notify(r.assignee_id, r.site_id, 'assigned',
        v.number || ' assigned to you', v.title, 'jobcard:' || v.id);
    else
      perform public._notify_holders(r.site_id, 'jc.assign', 'registered',
        'Scheduled job card ' || v.number || ' needs assigning', v.title, 'jobcard:' || v.id);
    end if;

    update public.legacy_job_recurrences set next_run = case r.every
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

select cron.schedule('legacy-recurrences', '0 4 * * *', 'select public.fn_run_legacy_recurrences()');

revoke execute on function
  public._migrate_legacy_jobs(),
  public.fn_run_legacy_recurrences()
from public, anon, authenticated;

insert into public.schema_migrations (filename) values ('0006_cmms_legacy_data.sql')
on conflict do nothing;
