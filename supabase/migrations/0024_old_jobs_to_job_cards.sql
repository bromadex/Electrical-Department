-- 0024_old_jobs_to_job_cards: the jobs board's jobs become job cards, so
-- their history shows in the app again (API.md section 17). The board's
-- tables keep their data untouched; each job gets a new job card number and
-- keeps its old code in legacy_code. Safe to run more than once.

-- Old photos stay in the job-photos bucket; job card viewers can read them.
create policy job_photos_select_jc on storage.objects for select to authenticated
  using (bucket_id = 'job-photos' and public._can('jc.view', public._path_site(name)));

create function public._copy_old_jobs()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  j public.jobs;
  v public.job_cards;
  v_status text;
  v_reason text;
  v_reporter text;
  v_description text;
  v_count integer := 0;
begin
  for j in
    select * from public.jobs oj
    where not oj.is_archived
      and not exists (
        select 1 from public.job_cards jc where jc.site_id = oj.site_id and jc.legacy_code = oj.code
      )
    order by oj.created_at
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
    select coalesce(nullif(trim(p.full_name), ''), 'Not recorded (from the jobs board)') into v_reporter
    from public.profiles p where p.id = j.created_by;
    v_description := coalesce(nullif(trim(j.description), ''), j.title);
    if length(v_description) < 5 then
      v_description := v_description || ' (from the jobs board)';
    end if;

    insert into public.job_cards (
      number, legacy_code, source, site_id, area_id, location, asset_id,
      received_at, registered_at, reporter_name, registered_by, title, description, priority,
      maintenance_type, isolation_required, target_completion_at, status, status_reason,
      responsible_id, first_assigned_at, assigned_at, first_started_at,
      closed_at, closure_approved_at, cancelled_at,
      completion_summary, performed_by, verified_by, legacy_closure, created_at
    ) values (
      public._next_doc_no('jobcard', j.created_at), j.code, 'legacy', j.site_id, j.area_id,
      case when j.area_id is null and j.asset_id is null then 'Not recorded (from the jobs board)' end,
      j.asset_id,
      j.created_at, j.created_at, coalesce(v_reporter, 'Not recorded (from the jobs board)'), j.created_by,
      left(j.title, 120), left(v_description, 4000),
      case j.priority when 'urgent' then 'P2' when 'low' then 'P4' else 'P3' end,
      case when j.recurrence_id is not null then 'preventive' else 'reactive' end,
      case when j.isolation_required then true end,
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
    from public.job_photos p
    where p.job_id = j.id and not p.is_archived
    on conflict (bucket, path) do nothing;

    insert into public.job_card_comments (job_card_id, author_id, kind, visibility, body, created_at)
    select v.id, c.author_id, 'comment', 'internal', c.body, c.created_at
    from public.job_comments c
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

revoke execute on function public._copy_old_jobs() from public, anon, authenticated;

select public._copy_old_jobs();

insert into public.schema_migrations (filename) values ('0024_old_jobs_to_job_cards.sql')
on conflict do nothing;
