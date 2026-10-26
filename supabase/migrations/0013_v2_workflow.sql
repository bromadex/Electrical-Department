-- 0013_v2_workflow (Job Cards Version 2): the job card and request workflow, dashboard, search and
-- administration functions (API.md section 17). Every write to the tables in
-- 0012 goes through a function here; each one checks permissions by code,
-- validates its input and raises 'CODE: message' errors the app can show.

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

-- Statuses where work has stopped for a recorded reason.
create function public._jc_holds()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['on_hold', 'awaiting_materials', 'awaiting_isolation',
               'awaiting_specialist', 'awaiting_production_clearance']::text[];
$$;

-- True when the caller submitted the request this job card came from.
create function public._jc_is_requester(p_job public.job_cards)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_job.request_id is not null and public._active() and exists (
    select 1 from public.service_requests r
    where r.id = p_job.request_id and r.requested_by = auth.uid()
  );
$$;

-- Loads a job card for a write, locked; the caller must be able to see it.
create function public._jc_for_write(p_job uuid)
returns public.job_cards
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_cards;
begin
  select * into v from public.job_cards where id = p_job and not is_archived for update;
  if not found or not (public._can('jc.view', v.site_id) or public._jc_is_requester(v)) then
    raise exception 'NOT_FOUND: Job card not found';
  end if;
  return v;
end;
$$;

-- The caller's current role on a job card: responsible, support or null.
create function public._jc_my_role(p_job uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select a.role
  from public.job_assignments a
  where a.job_card_id = p_job and a.user_id = auth.uid() and a.ended_at is null
  order by case a.role when 'responsible' then 0 else 1 end
  limit 1;
$$;

-- Work must be placed: a work area, a location or registered equipment.
create function public._jc_check_place(p_site uuid, p_area uuid, p_location text, p_asset uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_area is not null and not exists (
    select 1 from public.areas where id = p_area and site_id = p_site and not is_archived
  ) then
    raise exception 'INVALID: That work area is not at this site';
  end if;
  if p_asset is not null and not exists (
    select 1 from public.assets where id = p_asset and site_id = p_site and not is_archived
  ) then
    raise exception 'INVALID: That equipment is not registered at this site';
  end if;
  if p_area is null and p_asset is null and nullif(trim(coalesce(p_location, '')), '') is null then
    raise exception 'INVALID: Say where the work is: a work area, a location or the equipment';
  end if;
end;
$$;

-- Moves a job card to another status if job_status_transitions allows it,
-- with the reason the change needs, and stamps the matching server times.
create function public._jc_set_status(p_job public.job_cards, p_to text, p_reason text)
returns public.job_cards
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_cards;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if p_job.status = p_to then
    return p_job;
  end if;
  if not exists (
    select 1 from public.job_status_transitions
    where from_status = p_job.status and to_status = p_to
  ) then
    raise exception 'INVALID: % cannot go from % to %', p_job.number,
      replace(p_job.status, '_', ' '), replace(p_to, '_', ' ');
  end if;
  if v_reason is null and (
    p_to = any (public._jc_holds() || array['cancelled', 'reopened', 'awaiting_clarification'])
    or (p_job.status = 'awaiting_review' and p_to = 'accepted')
  ) then
    raise exception 'INVALID: Give a reason for this change';
  end if;

  update public.job_cards set
    status = p_to,
    status_reason = v_reason,
    first_assigned_at = case when p_to = 'assigned' then coalesce(first_assigned_at, now()) else first_assigned_at end,
    assigned_at = case when p_to = 'assigned' then now() else assigned_at end,
    accepted_at = case when p_to = 'accepted' then coalesce(accepted_at, now()) else accepted_at end,
    first_started_at = case when p_to = 'in_progress' then coalesce(first_started_at, now()) else first_started_at end,
    submitted_at = case when p_to = 'awaiting_review' then now() else submitted_at end,
    closed_at = case when p_to = 'closed' then now() when p_to = 'reopened' then null else closed_at end,
    closure_approved_at = case
      when p_to = 'closed' then now() when p_to = 'reopened' then null else closure_approved_at end,
    cancelled_at = case when p_to = 'cancelled' then now() else cancelled_at end,
    reopened_at = case when p_to = 'reopened' then now() else reopened_at end,
    verified_by = case when p_to = 'reopened' then null else verified_by end,
    self_approved = case when p_to = 'reopened' then false else self_approved end
  where id = p_job.id
  returning * into v;
  return v;
end;
$$;

-- Notifies one person about a job card (never the person who acted).
create function public._jc_notify(p_job public.job_cards, p_user uuid, p_type text, p_title text, p_body text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_user is null or p_user is not distinct from auth.uid() then
    return;
  end if;
  perform public.fn_notify(p_user, p_job.site_id, p_type, p_title, p_body, 'jobcard:' || p_job.id);
end;
$$;

-- Notifies every active holder of p_code at p_site, except the person who acted.
create function public._notify_holders(
  p_site uuid,
  p_code text,
  p_type text,
  p_title text,
  p_body text,
  p_link text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.notifications (user_id, site_id, type, title, body, link)
  select distinct ur.user_id, p_site, p_type, p_title, p_body, p_link
  from public.user_roles ur
  join public.profiles p on p.id = ur.user_id and p.active and not p.is_archived
  join public.roles r on r.id = ur.role_id and not r.is_archived
  join public.role_permissions rp on rp.role_id = ur.role_id and not rp.is_archived
  join public.permissions pm on pm.code = rp.permission_code and not pm.is_archived
  where not ur.is_archived
    and rp.permission_code = p_code
    and (ur.site_id is null or ur.site_id = p_site)
    and ur.user_id is distinct from auth.uid();
end;
$$;

-- Critical job: engineers at the site plus the escalation contacts for its priority.
create function public._jc_notify_critical(p_job public.job_cards)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.notifications (user_id, site_id, type, title, body, link)
  select distinct x.user_id, p_job.site_id, 'critical',
    'CRITICAL ' || p_job.number || ' (' || p_job.priority || ')',
    p_job.title || coalesce(' — ' || p_job.critical_reason, ''),
    'jobcard:' || p_job.id
  from (
    select ur.user_id
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id and not r.is_archived
    join public.role_permissions rp on rp.role_id = ur.role_id and not rp.is_archived
    join public.permissions pm on pm.code = rp.permission_code and not pm.is_archived
    where not ur.is_archived
      and rp.permission_code = 'jc.assess'
      and (ur.site_id is null or ur.site_id = p_job.site_id)
    union
    select ec.user_id
    from public.escalation_contacts ec
    where not ec.is_archived
      and ec.priority_code = p_job.priority
      and (ec.site_id is null or ec.site_id = p_job.site_id)
  ) x
  join public.profiles p on p.id = x.user_id and p.active and not p.is_archived
  where x.user_id is distinct from auth.uid();
end;
$$;

-- Tells the person who raised the original request (if any).
create function public._jc_notify_requester(p_job public.job_cards, p_title text, p_body text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid;
begin
  if p_job.request_id is null then
    return;
  end if;
  select requested_by into v_user from public.service_requests where id = p_job.request_id;
  if v_user is null or v_user is not distinct from auth.uid() then
    return;
  end if;
  perform public.fn_notify(v_user, p_job.site_id, 'request', p_title, p_body, 'servicerequest:' || p_job.request_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Incoming requests (other departments)
-- ---------------------------------------------------------------------------
create function public.fn_submit_request(
  p_client_ref uuid,
  p_site uuid,
  p_area uuid,
  p_location text,
  p_department uuid,
  p_reporter_name text,
  p_contact text,
  p_asset uuid,
  p_equipment text,
  p_title text,
  p_description text,
  p_impact text
)
returns public.service_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.service_requests;
  v_id uuid := coalesce(p_client_ref, gen_random_uuid());
begin
  select * into v from public.service_requests where id = v_id;
  if found then
    return v;
  end if;
  if not public._can('req.submit', p_site) then
    raise exception 'NOT_ALLOWED: You cannot submit requests at this site';
  end if;
  if length(trim(coalesce(p_title, ''))) not between 3 and 120 then
    raise exception 'INVALID: The title needs 3 to 120 characters';
  end if;
  if length(trim(coalesce(p_description, ''))) not between 5 and 4000 then
    raise exception 'INVALID: Describe the problem in 5 to 4000 characters';
  end if;
  if length(trim(coalesce(p_reporter_name, ''))) not between 2 and 120 then
    raise exception 'INVALID: Give the name of the person reporting the fault';
  end if;
  if p_impact is null
     or p_impact not in ('none', 'minor', 'reduced_output', 'production_stopped', 'safety_hazard') then
    raise exception 'INVALID: Choose the operational impact';
  end if;
  if p_department is not null and not exists (
    select 1 from public.departments where id = p_department and not is_archived
  ) then
    raise exception 'INVALID: Unknown department';
  end if;
  perform public._jc_check_place(p_site, p_area, p_location, p_asset);

  insert into public.service_requests (
    id, request_no, site_id, area_id, location, department_id, requested_by, reporter_name,
    contact, asset_id, equipment_text, title, description, operational_impact
  ) values (
    v_id, public._next_doc_no('request', now()), p_site, p_area,
    nullif(trim(coalesce(p_location, '')), ''), p_department, auth.uid(), trim(p_reporter_name),
    nullif(trim(coalesce(p_contact, '')), ''), p_asset, nullif(trim(coalesce(p_equipment, '')), ''),
    trim(p_title), trim(p_description), p_impact
  )
  returning * into v;

  perform public._notify_holders(
    v.site_id, 'req.triage', 'request',
    case when v.operational_impact in ('production_stopped', 'safety_hazard')
      then 'Urgent request ' else 'New request ' end || v.request_no,
    v.title, 'servicerequest:' || v.id
  );
  return v;
end;
$$;

-- Triage: return a request for more information, or reject it.
create function public.fn_triage_request(p_request uuid, p_action text, p_reason text)
returns public.service_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.service_requests;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  select * into v from public.service_requests where id = p_request and not is_archived for update;
  if not found or not public._can('req.triage', v.site_id) then
    raise exception 'NOT_FOUND: Request not found';
  end if;
  if p_action is null or p_action not in ('return', 'reject') then
    raise exception 'INVALID: Unknown action %', p_action;
  end if;
  if v.status <> 'submitted' then
    raise exception 'INVALID: % is %', v.request_no, v.status;
  end if;
  if v_reason is null then
    raise exception 'INVALID: Give the requester a reason';
  end if;

  update public.service_requests set
    status = case p_action when 'return' then 'returned' else 'rejected' end,
    status_reason = v_reason,
    reviewed_by = auth.uid(),
    reviewed_at = now()
  where id = v.id
  returning * into v;

  if v.requested_by is distinct from auth.uid() then
    perform public.fn_notify(
      v.requested_by, v.site_id, 'request',
      v.request_no || case p_action when 'return' then ' needs more information' else ' was not accepted' end,
      v_reason, 'servicerequest:' || v.id
    );
  end if;
  return v;
end;
$$;

-- The requester answers a returned request and sends it back to the queue.
create function public.fn_resubmit_request(
  p_request uuid,
  p_title text,
  p_description text,
  p_impact text,
  p_note text
)
returns public.service_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.service_requests;
begin
  select * into v from public.service_requests where id = p_request and not is_archived for update;
  if not found or v.requested_by <> auth.uid() or not public._active() then
    raise exception 'NOT_FOUND: Request not found';
  end if;
  if v.status <> 'returned' then
    raise exception 'INVALID: % is %', v.request_no, v.status;
  end if;
  if length(trim(coalesce(p_title, ''))) not between 3 and 120 then
    raise exception 'INVALID: The title needs 3 to 120 characters';
  end if;
  if length(trim(coalesce(p_description, ''))) not between 5 and 4000 then
    raise exception 'INVALID: Describe the problem in 5 to 4000 characters';
  end if;
  if p_impact is null
     or p_impact not in ('none', 'minor', 'reduced_output', 'production_stopped', 'safety_hazard') then
    raise exception 'INVALID: Choose the operational impact';
  end if;
  if length(trim(coalesce(p_note, ''))) not between 2 and 2000 then
    raise exception 'INVALID: Answer the question you were asked';
  end if;

  update public.service_requests set
    title = trim(p_title),
    description = trim(p_description),
    operational_impact = p_impact,
    clarification_note = trim(p_note),
    status = 'submitted',
    status_reason = null
  where id = v.id
  returning * into v;

  perform public._notify_holders(
    v.site_id, 'req.triage', 'request', v.request_no || ' was updated by the requester',
    trim(p_note), 'servicerequest:' || v.id
  );
  return v;
end;
$$;

create function public.fn_withdraw_request(p_request uuid, p_reason text)
returns public.service_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.service_requests;
begin
  select * into v from public.service_requests where id = p_request and not is_archived for update;
  if not found or v.requested_by <> auth.uid() or not public._active() then
    raise exception 'NOT_FOUND: Request not found';
  end if;
  if v.status not in ('submitted', 'returned') then
    raise exception 'INVALID: % is %', v.request_no, v.status;
  end if;
  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'INVALID: Say why you are withdrawing the request';
  end if;
  update public.service_requests set status = 'withdrawn', status_reason = trim(p_reason)
  where id = v.id
  returning * into v;
  return v;
end;
$$;

create function public.fn_add_request_attachment(
  p_client_ref uuid,
  p_request uuid,
  p_path text,
  p_file_name text,
  p_content_type text,
  p_size bigint
)
returns public.request_attachments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.request_attachments;
  r public.service_requests;
  v_id uuid := coalesce(p_client_ref, gen_random_uuid());
begin
  select * into v from public.request_attachments where id = v_id;
  if found then
    return v;
  end if;
  select * into r from public.service_requests where id = p_request and not is_archived;
  if not found or not (
    (r.requested_by = auth.uid() and public._active()) or public._can('req.triage', r.site_id)
  ) then
    raise exception 'NOT_FOUND: Request not found';
  end if;
  if r.status not in ('submitted', 'returned') then
    raise exception 'INVALID: Add files to the job card instead; % is %', r.request_no, r.status;
  end if;
  if split_part(p_path, '/', 1) <> r.site_id::text
     or split_part(p_path, '/', 2) <> 'request'
     or split_part(p_path, '/', 3) <> r.id::text
     or split_part(p_path, '/', 4) = '' then
    raise exception 'INVALID: File path must be <site>/request/<request>/<file>';
  end if;

  insert into public.request_attachments (id, request_id, path, file_name, content_type, size_bytes, uploaded_by)
  values (v_id, r.id, p_path, nullif(trim(coalesce(p_file_name, '')), ''), p_content_type, p_size, auth.uid())
  returning * into v;
  return v;
end;
$$;

-- What a requester may see of their request and the job card made from it.
create function public.fn_request_tracking(p_request uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  r public.service_requests;
begin
  select * into r from public.service_requests where id = p_request and not is_archived;
  if not found or not (
    (r.requested_by = auth.uid() and public._active())
    or public._can('req.triage', r.site_id)
    or public._can('jc.view', r.site_id)
  ) then
    raise exception 'NOT_FOUND: Request not found';
  end if;

  return jsonb_build_object(
    'request', to_jsonb(r),
    'site_name', (select s.name from public.sites s where s.id = r.site_id),
    'area_name', (select a.name from public.areas a where a.id = r.area_id),
    'department_name', (select d.name from public.departments d where d.id = r.department_id),
    'attachments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', f.id, 'path', f.path, 'file_name', f.file_name, 'content_type', f.content_type
      ) order by f.created_at)
      from public.request_attachments f
      where f.request_id = r.id and not f.is_archived
    ), '[]'::jsonb),
    'job', (
      select jsonb_build_object(
        'id', j.id, 'number', j.number, 'status', j.status, 'priority', j.priority,
        'received_at', j.received_at, 'accepted_at', j.accepted_at, 'closed_at', j.closed_at,
        'target_completion_at', j.target_completion_at, 'responsible_name', p.full_name
      )
      from public.job_cards j
      left join public.profiles p on p.id = j.responsible_id
      where j.id = r.job_card_id
    ),
    'updates', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id, 'body', c.body, 'created_at', c.created_at,
        'author', coalesce(nullif(p.full_name, ''), 'Electrical department')
      ) order by c.created_at)
      from public.job_card_comments c
      left join public.profiles p on p.id = c.author_id
      where c.job_card_id = r.job_card_id and c.visibility = 'requester' and not c.is_archived
    ), '[]'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Stage 1: register a job card (directly, or from a submitted request)
-- ---------------------------------------------------------------------------
create function public.fn_register_job_card(
  p_client_ref uuid,
  p_request uuid,
  p_site uuid,
  p_area uuid,
  p_location text,
  p_received_at timestamptz,
  p_reporter_name text,
  p_department uuid,
  p_asset uuid,
  p_equipment_name text,
  p_equipment_asset_no text,
  p_equipment_location text,
  p_category uuid,
  p_title text,
  p_description text,
  p_impact text,
  p_priority text,
  p_requested_completion_at timestamptz
)
returns public.job_cards
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_cards;
  r public.service_requests;
  a public.assets;
  pl public.priority_levels;
  v_id uuid := coalesce(p_client_ref, gen_random_uuid());
  v_site uuid := p_site;
  v_area uuid := p_area;
  v_location text := nullif(trim(coalesce(p_location, '')), '');
  v_reporter text := nullif(trim(coalesce(p_reporter_name, '')), '');
  v_department uuid := p_department;
  v_asset uuid := p_asset;
  v_equipment text := nullif(trim(coalesce(p_equipment_name, '')), '');
  v_title text := nullif(trim(coalesce(p_title, '')), '');
  v_description text := nullif(trim(coalesce(p_description, '')), '');
  v_impact text := p_impact;
  v_received timestamptz;
begin
  select * into v from public.job_cards where id = v_id;
  if found then
    return v;
  end if;

  if p_request is not null then
    select * into r from public.service_requests where id = p_request and not is_archived for update;
    if not found or not public._can('req.triage', r.site_id) then
      raise exception 'NOT_FOUND: Request not found';
    end if;
    if r.status <> 'submitted' then
      raise exception 'INVALID: % is %', r.request_no, r.status;
    end if;
    v_site := r.site_id;
    v_area := coalesce(p_area, r.area_id);
    v_location := coalesce(v_location, r.location);
    v_reporter := coalesce(v_reporter, r.reporter_name);
    v_department := coalesce(p_department, r.department_id);
    v_asset := coalesce(p_asset, r.asset_id);
    v_equipment := coalesce(v_equipment, r.equipment_text);
    v_title := coalesce(v_title, r.title);
    v_description := coalesce(v_description, r.description);
    v_impact := coalesce(p_impact, r.operational_impact);
    v_received := r.submitted_at;
  else
    v_received := coalesce(p_received_at, now());
    if v_received > now() + interval '5 minutes' then
      raise exception 'INVALID: The time received cannot be in the future';
    end if;
    if v_received < now() - interval '90 days' then
      raise exception 'INVALID: The time received is more than 90 days ago';
    end if;
  end if;

  if not public._can('jc.register', v_site) then
    raise exception 'NOT_ALLOWED: You cannot register job cards at this site';
  end if;
  if length(coalesce(v_title, '')) not between 3 and 120 then
    raise exception 'INVALID: The title needs 3 to 120 characters';
  end if;
  if length(coalesce(v_description, '')) not between 5 and 4000 then
    raise exception 'INVALID: Describe the fault or work in 5 to 4000 characters';
  end if;
  if length(coalesce(v_reporter, '')) not between 2 and 120 then
    raise exception 'INVALID: Give the name of the person reporting the fault';
  end if;
  if v_impact is null
     or v_impact not in ('none', 'minor', 'reduced_output', 'production_stopped', 'safety_hazard') then
    raise exception 'INVALID: Choose the operational impact';
  end if;
  select * into pl from public.priority_levels where code = p_priority;
  if not found then
    raise exception 'INVALID: Choose a priority from P1 to P4';
  end if;
  if p_category is not null and not exists (
    select 1 from public.job_categories where id = p_category and not is_archived
  ) then
    raise exception 'INVALID: Unknown job category';
  end if;
  if v_department is not null and not exists (
    select 1 from public.departments where id = v_department and not is_archived
  ) then
    raise exception 'INVALID: Unknown department';
  end if;
  perform public._jc_check_place(v_site, v_area, v_location, v_asset);
  if v_asset is not null then
    select * into a from public.assets where id = v_asset;
  end if;

  insert into public.job_cards (
    id, number, source, request_id, site_id, area_id, location,
    received_at, reporter_name, requesting_department_id, asset_id,
    equipment_name, equipment_asset_no, equipment_location, category_id,
    title, description, operational_impact, priority, requested_completion_at,
    registered_by, target_response_at, target_completion_at,
    is_critical, critical_reason, escalated_at
  ) values (
    v_id, public._next_doc_no('jobcard', now()),
    case when p_request is null then 'direct' else 'request' end,
    p_request, v_site, v_area, v_location,
    v_received, v_reporter, v_department, v_asset,
    coalesce(v_equipment, a.name),
    coalesce(nullif(trim(coalesce(p_equipment_asset_no, '')), ''), a.asset_no),
    coalesce(nullif(trim(coalesce(p_equipment_location, '')), ''), a.location),
    p_category, v_title, v_description, v_impact, pl.code, p_requested_completion_at,
    auth.uid(),
    v_received + make_interval(mins => pl.response_minutes),
    v_received + make_interval(mins => pl.completion_minutes),
    pl.code = 'P1',
    case when pl.code = 'P1' then 'P1 emergency' end,
    case when pl.code = 'P1' then now() end
  )
  returning * into v;

  if r.id is not null then
    update public.service_requests set
      status = 'registered', status_reason = null, job_card_id = v.id,
      reviewed_by = auth.uid(), reviewed_at = now()
    where id = r.id;

    insert into public.job_attachments (
      job_card_id, kind, bucket, path, file_name, content_type, size_bytes, uploaded_by, created_at
    )
    select v.id,
      case when coalesce(f.content_type, '') like 'image/%' then 'photo' else 'document' end,
      'job-files', f.path, f.file_name, f.content_type, f.size_bytes, f.uploaded_by, f.created_at
    from public.request_attachments f
    where f.request_id = r.id and not f.is_archived
    on conflict (bucket, path) do nothing;

    perform public._jc_notify_requester(v, r.request_no || ' registered as ' || v.number, v.title);
  end if;

  if v.is_critical then
    perform public._jc_notify_critical(v);
  else
    perform public._notify_holders(
      v.site_id, 'jc.assess', 'registered',
      'New job card ' || v.number || ' (' || v.priority || ')', v.title, 'jobcard:' || v.id
    );
  end if;
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- Stage 2: engineering assessment
-- ---------------------------------------------------------------------------
create function public.fn_assess_job_card(
  p_job uuid,
  p_valid boolean,
  p_maintenance_type text,
  p_severity text,
  p_safety_risk text,
  p_safety_notes text,
  p_equipment_state text,
  p_competencies text,
  p_personnel integer,
  p_resources text,
  p_isolation boolean,
  p_permit boolean,
  p_loto boolean,
  p_duration_hours numeric,
  p_priority text,
  p_target_response_at timestamptz,
  p_target_completion_at timestamptz,
  p_notes text
)
returns public.job_cards
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_cards := public._jc_for_write(p_job);
  pl public.priority_levels;
  v_was_critical boolean := v.is_critical;
  v_notes text := nullif(trim(coalesce(p_notes, '')), '');
  v_response timestamptz;
  v_completion timestamptz;
  v_reason text;
begin
  if not public._can('jc.assess', v.site_id) then
    raise exception 'NOT_ALLOWED: Only an electrical engineer can assess job cards';
  end if;
  if v.status in ('closed', 'cancelled') then
    raise exception 'INVALID: % is %', v.number, v.status;
  end if;

  if p_valid is false then
    if v_notes is null then
      raise exception 'INVALID: Say why the job card is not valid';
    end if;
    update public.job_cards set
      is_valid = false, assessment_notes = v_notes, assessed_by = auth.uid(), assessed_at = now()
    where id = v.id
    returning * into v;
    v := public._jc_set_status(v, 'cancelled', 'Not valid: ' || v_notes);
    perform public._jc_notify(v, v.registered_by, 'returned', v.number || ' was cancelled as not valid', v_notes);
    perform public._jc_notify_requester(v, 'Your request was not accepted (' || v.number || ')', v_notes);
    return v;
  end if;

  if p_maintenance_type is null or p_maintenance_type not in (
    'reactive', 'preventive', 'corrective', 'emergency', 'inspection', 'installation', 'improvement'
  ) then
    raise exception 'INVALID: Choose the type of work';
  end if;
  if p_severity is null or p_severity not in ('minor', 'moderate', 'major', 'critical') then
    raise exception 'INVALID: Choose the severity';
  end if;
  if p_safety_risk is null or p_safety_risk not in ('low', 'medium', 'high', 'extreme') then
    raise exception 'INVALID: Choose the safety risk';
  end if;
  if p_equipment_state is null or p_equipment_state not in ('operational', 'degraded', 'out_of_service') then
    raise exception 'INVALID: Say whether the equipment is operational';
  end if;
  if p_personnel is not null and p_personnel not between 1 and 50 then
    raise exception 'INVALID: Personnel needed must be between 1 and 50';
  end if;
  if p_duration_hours is not null and p_duration_hours <= 0 then
    raise exception 'INVALID: Expected duration must be more than zero';
  end if;
  select * into pl from public.priority_levels where code = coalesce(p_priority, v.priority);
  if not found then
    raise exception 'INVALID: Choose a priority from P1 to P4';
  end if;
  if p_target_completion_at is not null and p_target_completion_at <= v.received_at then
    raise exception 'INVALID: The target completion must be after the job was received';
  end if;
  if p_target_response_at is not null and p_target_response_at <= v.received_at then
    raise exception 'INVALID: The target response must be after the job was received';
  end if;

  -- A new priority brings its default targets unless the engineer set them.
  v_response := coalesce(p_target_response_at, case when pl.code <> v.priority
    then v.received_at + make_interval(mins => pl.response_minutes) else v.target_response_at end);
  v_completion := coalesce(p_target_completion_at, case when pl.code <> v.priority
    then v.received_at + make_interval(mins => pl.completion_minutes) else v.target_completion_at end);

  update public.job_cards set
    is_valid = true,
    maintenance_type = p_maintenance_type,
    severity = p_severity,
    safety_risk = p_safety_risk,
    safety_notes = nullif(trim(coalesce(p_safety_notes, '')), ''),
    equipment_state = p_equipment_state,
    required_competencies = nullif(trim(coalesce(p_competencies, '')), ''),
    required_personnel = p_personnel,
    resources_required = nullif(trim(coalesce(p_resources, '')), ''),
    isolation_required = p_isolation,
    permit_required = p_permit,
    loto_required = p_loto,
    expected_duration_hours = p_duration_hours,
    priority = pl.code,
    target_response_at = v_response,
    target_completion_at = v_completion,
    overdue_notified_at = case
      when v_completion is distinct from v.target_completion_at then null else overdue_notified_at end,
    assessment_notes = v_notes,
    assessed_by = auth.uid(),
    assessed_at = now()
  where id = v.id
  returning * into v;

  v_reason := case
    when pl.code = 'P1' then 'P1 emergency'
    when p_severity = 'critical' then 'Critical severity'
    when p_safety_risk = 'extreme' then 'Extreme safety risk'
  end;
  if v_reason is not null and not v.is_critical then
    update public.job_cards set
      is_critical = true, critical_reason = v_reason, escalated_by = auth.uid(), escalated_at = now()
    where id = v.id
    returning * into v;
  end if;

  if v.status = 'registered' then
    v := public._jc_set_status(v, 'awaiting_assignment', null);
  end if;
  if v.is_critical and not v_was_critical then
    perform public._jc_notify_critical(v);
  end if;
  return v;
end;
$$;

create function public.fn_return_for_clarification(p_job uuid, p_reason text)
returns public.job_cards
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_cards := public._jc_for_write(p_job);
begin
  if not public._can('jc.assess', v.site_id) then
    raise exception 'NOT_ALLOWED: Only an electrical engineer can return job cards';
  end if;
  if v.status not in ('registered', 'awaiting_assignment') then
    raise exception 'INVALID: % is %', v.number, replace(v.status, '_', ' ');
  end if;
  v := public._jc_set_status(v, 'awaiting_clarification', p_reason);
  perform public._jc_notify(v, v.registered_by, 'returned', v.number || ' needs clarification', v.status_reason);
  perform public._jc_notify_requester(v, 'More information needed for ' || v.number, v.status_reason);
  return v;
end;
$$;

create function public.fn_provide_clarification(p_job uuid, p_note text)
returns public.job_cards
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_cards := public._jc_for_write(p_job);
  v_requester boolean := public._jc_is_requester(v);
  v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
  if not (v.registered_by = auth.uid() or public._can('jc.register', v.site_id) or v_requester) then
    raise exception 'NOT_ALLOWED: You cannot answer for this job card';
  end if;
  if v.status <> 'awaiting_clarification' then
    raise exception 'INVALID: % is not waiting for clarification', v.number;
  end if;
  if v_note is null or length(v_note) > 4000 then
    raise exception 'INVALID: Write the clarification (up to 4000 characters)';
  end if;

  insert into public.job_card_comments (job_card_id, author_id, kind, visibility, body)
  values (v.id, auth.uid(), 'comment', case when v_requester then 'requester' else 'internal' end,
          'Clarification: ' || v_note);
  v := public._jc_set_status(v, 'registered', null);
  perform public._notify_holders(
    v.site_id, 'jc.assess', 'registered', v.number || ' was clarified', v_note, 'jobcard:' || v.id
  );
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- Stage 3: assignment
-- ---------------------------------------------------------------------------
create function public.fn_assign_job_card(
  p_job uuid,
  p_responsible uuid,
  p_support uuid[],
  p_planned_start_at timestamptz,
  p_target_completion_at timestamptz,
  p_estimated_hours numeric,
  p_materials text,
  p_tools text,
  p_safety text,
  p_procedure text,
  p_handover_note text,
  p_reason text
)
returns public.job_cards
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_cards := public._jc_for_write(p_job);
  s public.system_settings := public._settings();
  v_old uuid := v.responsible_id;
  v_changed boolean;
  v_support uuid[];
  v_user uuid;
  v_name text;
  v_handover text := nullif(trim(coalesce(p_handover_note, '')), '');
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if not public._can('jc.assign', v.site_id) then
    raise exception 'NOT_ALLOWED: Only an electrical engineer can assign job cards';
  end if;
  if not (v.status in ('awaiting_assignment', 'reopened', 'assigned', 'accepted', 'in_progress')
          or v.status = any (public._jc_holds())) then
    raise exception 'INVALID: % cannot be assigned while %', v.number, replace(v.status, '_', ' ');
  end if;
  if p_responsible is null then
    raise exception 'INVALID: Choose the responsible person';
  end if;
  if not public._user_can(p_responsible, 'jc.execute', v.site_id) then
    raise exception 'INVALID: That person cannot work job cards at this site';
  end if;
  v_support := array(
    select distinct u from unnest(coalesce(p_support, '{}'::uuid[])) u
    where u is not null and u <> p_responsible
  );
  foreach v_user in array v_support loop
    if not public._user_can(v_user, 'jc.execute', v.site_id) then
      raise exception 'INVALID: A supporting person cannot work job cards at this site';
    end if;
  end loop;
  if p_estimated_hours is not null and p_estimated_hours <= 0 then
    raise exception 'INVALID: Estimated labour hours must be more than zero';
  end if;
  if p_target_completion_at is not null and p_target_completion_at <= v.received_at then
    raise exception 'INVALID: The target completion must be after the job was received';
  end if;

  v_changed := v_old is distinct from p_responsible;

  -- Reassignment: the outgoing person hands over when work has begun.
  if v_changed and v_old is not null then
    if (v.status in ('accepted', 'in_progress') or v.status = any (public._jc_holds()))
       and s.handover_note_required and v_handover is null then
      raise exception 'INVALID: Add a handover note for the new responsible person';
    end if;
    update public.job_assignments set
      ended_at = now(), end_reason = coalesce(v_reason, 'Reassigned'), handover_note = v_handover
    where job_card_id = v.id and role = 'responsible' and ended_at is null;
  end if;

  -- Supporting people no longer listed (or now responsible) leave the team.
  update public.job_assignments set ended_at = now(), end_reason = 'Removed from the team'
  where job_card_id = v.id and role = 'support' and ended_at is null
    and (user_id <> all (v_support) or user_id = p_responsible);

  if v_changed then
    insert into public.job_assignments (job_card_id, user_id, role, assigned_by)
    values (v.id, p_responsible, 'responsible', auth.uid());
  end if;
  insert into public.job_assignments (job_card_id, user_id, role, assigned_by)
  select v.id, u, 'support', auth.uid()
  from unnest(v_support) u
  where not exists (
    select 1 from public.job_assignments a
    where a.job_card_id = v.id and a.user_id = u and a.ended_at is null
  );

  update public.job_cards set
    responsible_id = p_responsible,
    assigned_by = auth.uid(),
    planned_start_at = p_planned_start_at,
    target_completion_at = coalesce(p_target_completion_at, target_completion_at),
    overdue_notified_at = case
      when p_target_completion_at is not null and p_target_completion_at is distinct from target_completion_at
        then null else overdue_notified_at end,
    estimated_labour_hours = p_estimated_hours,
    required_materials = nullif(trim(coalesce(p_materials, '')), ''),
    required_tools = nullif(trim(coalesce(p_tools, '')), ''),
    safety_precautions = nullif(trim(coalesce(p_safety, '')), ''),
    procedure_notes = nullif(trim(coalesce(p_procedure, '')), '')
  where id = v.id
  returning * into v;

  if v.status in ('awaiting_assignment', 'reopened') then
    v := public._jc_set_status(v, 'assigned', v_reason);
  elsif v_changed and v.status = 'assigned' then
    update public.job_cards set assigned_at = now() where id = v.id returning * into v;
  elsif v_changed then
    v := public._jc_set_status(v, 'assigned', coalesce(v_reason, 'Reassigned'));
  end if;

  if v_changed then
    perform public._jc_notify(v, p_responsible, 'assigned',
      v.number || ' assigned to you (' || v.priority || ')', v.title);
    if v_old is not null then
      select full_name into v_name from public.profiles where id = p_responsible;
      perform public._jc_notify(v, v_old, 'reassigned',
        v.number || ' reassigned to ' || coalesce(nullif(v_name, ''), 'someone else'), v.title);
    end if;
  end if;
  for v_user in
    select a.user_id from public.job_assignments a
    where a.job_card_id = v.id and a.role = 'support' and a.ended_at is null and a.assigned_at = now()
  loop
    perform public._jc_notify(v, v_user, 'assigned', 'You are supporting ' || v.number, v.title);
  end loop;
  return v;
end;
$$;

-- Takes everyone off a job card and puts it back in the assignment queue.
create function public.fn_unassign_job_card(p_job uuid, p_reason text)
returns public.job_cards
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_cards := public._jc_for_write(p_job);
  v_old uuid := v.responsible_id;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if not public._can('jc.assign', v.site_id) then
    raise exception 'NOT_ALLOWED: Only an electrical engineer can unassign job cards';
  end if;
  if v.status not in ('assigned', 'accepted') then
    raise exception 'INVALID: Pause or reassign % instead', v.number;
  end if;
  if v_reason is null then
    raise exception 'INVALID: Give a reason for unassigning';
  end if;
  update public.job_assignments set ended_at = now(), end_reason = v_reason
  where job_card_id = v.id and ended_at is null;
  v := public._jc_set_status(v, 'awaiting_assignment', v_reason);
  update public.job_cards set responsible_id = null where id = v.id returning * into v;
  perform public._jc_notify(v, v_old, 'reassigned', v.number || ' was taken off you', v_reason);
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- Stage 4: execution
-- ---------------------------------------------------------------------------

-- The assignee accepts the job and acknowledges its priority.
create function public.fn_accept_job_card(p_job uuid)
returns public.job_cards
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_cards := public._jc_for_write(p_job);
  v_role text := public._jc_my_role(p_job);
  v_first boolean := v.accepted_at is null;
  v_name text;
begin
  if v_role is null or not public._can('jc.execute', v.site_id) then
    raise exception 'NOT_ALLOWED: Only the assigned team can accept %', v.number;
  end if;
  update public.job_assignments set acknowledged_at = coalesce(acknowledged_at, now())
  where job_card_id = v.id and user_id = auth.uid() and ended_at is null;

  if v_role = 'responsible' and v.status in ('assigned', 'reopened') then
    v := public._jc_set_status(v, 'accepted', null);
    select full_name into v_name from public.profiles where id = auth.uid();
    perform public._jc_notify(v, v.assigned_by, 'general',
      v.number || ' accepted by ' || coalesce(nullif(v_name, ''), 'the assignee'), v.title);
    if v_first then
      perform public._jc_notify_requester(v, 'Your request is being worked on (' || v.number || ')', v.title);
    end if;
  end if;
  return v;
end;
$$;

-- Work statuses: in progress, or stopped for a reason.
create function public.fn_set_job_card_status(p_job uuid, p_status text, p_reason text)
returns public.job_cards
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_cards := public._jc_for_write(p_job);
  v_role text := public._jc_my_role(p_job);
begin
  if p_status is null or not (p_status = 'in_progress' or p_status = any (public._jc_holds())) then
    raise exception 'INVALID: Use the matching action to move a job card to %', coalesce(p_status, 'that status');
  end if;
  if not ((v_role is not null and public._can('jc.execute', v.site_id)) or public._can('jc.assign', v.site_id)) then
    raise exception 'NOT_ALLOWED: Only the assigned team or an engineer can change %', v.number;
  end if;

  -- Starting work on an assigned job accepts it first.
  if p_status = 'in_progress' and v.status in ('assigned', 'reopened') and v_role = 'responsible' then
    update public.job_assignments set acknowledged_at = coalesce(acknowledged_at, now())
    where job_card_id = v.id and user_id = auth.uid() and ended_at is null;
    v := public._jc_set_status(v, 'accepted', null);
  end if;

  v := public._jc_set_status(v, p_status, p_reason);

  if p_status = any (public._jc_holds()) then
    if v.assigned_by is not null then
      perform public._jc_notify(v, v.assigned_by, 'on_hold',
        v.number || ': ' || replace(p_status, '_', ' '), v.status_reason);
    else
      perform public._notify_holders(v.site_id, 'jc.assign', 'on_hold',
        v.number || ': ' || replace(p_status, '_', ' '), v.status_reason, 'jobcard:' || v.id);
    end if;
  end if;
  return v;
end;
$$;

create function public.fn_escalate_job_card(p_job uuid, p_critical boolean, p_reason text)
returns public.job_cards
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_cards := public._jc_for_write(p_job);
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if not public._can('jc.escalate', v.site_id) then
    raise exception 'NOT_ALLOWED: You cannot escalate job cards';
  end if;
  if v.status in ('closed', 'cancelled') then
    raise exception 'INVALID: % is %', v.number, v.status;
  end if;
  if v_reason is null then
    raise exception 'INVALID: Give a reason';
  end if;

  if p_critical then
    if v.is_critical then
      return v;
    end if;
    update public.job_cards set
      is_critical = true, critical_reason = v_reason, escalated_by = auth.uid(), escalated_at = now()
    where id = v.id
    returning * into v;
    perform public._jc_notify_critical(v);
  else
    if v.priority = 'P1' then
      raise exception 'INVALID: P1 emergencies stay critical; lower the priority first';
    end if;
    if not v.is_critical then
      return v;
    end if;
    update public.job_cards set is_critical = false, critical_reason = 'De-escalated: ' || v_reason
    where id = v.id
    returning * into v;
  end if;
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- Stage 5: completion and verification
-- ---------------------------------------------------------------------------
create function public.fn_submit_job_card(
  p_job uuid,
  p_summary text,
  p_findings text,
  p_corrective_action text,
  p_equipment_state_after text,
  p_checks_confirmed boolean
)
returns public.job_cards
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_cards := public._jc_for_write(p_job);
  v_role text := public._jc_my_role(p_job);
begin
  if not ((v_role = 'responsible' and public._can('jc.execute', v.site_id)) or public._can('jc.assign', v.site_id)) then
    raise exception 'NOT_ALLOWED: Only the responsible person can submit %', v.number;
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
  if p_checks_confirmed is not true then
    raise exception 'INVALID: Confirm that the required checks and safety procedures were completed';
  end if;

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

-- Approve (closes) or reject (returns for more work). Nobody approves work
-- they did unless they hold jc.self_approve, and that approval is marked.
create function public.fn_review_job_card(p_job uuid, p_decision text, p_notes text)
returns public.job_cards
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_cards := public._jc_for_write(p_job);
  v_notes text := nullif(trim(coalesce(p_notes, '')), '');
  v_self boolean;
begin
  if not public._can('jc.review', v.site_id) then
    raise exception 'NOT_ALLOWED: Only an electrical engineer can verify work';
  end if;
  if v.status <> 'awaiting_review' then
    raise exception 'INVALID: % is not awaiting review', v.number;
  end if;
  v_self := coalesce(v.performed_by = auth.uid(), false) or public._jc_my_role(v.id) is not null;

  if p_decision = 'approve' then
    if v_self and not public._can('jc.self_approve', v.site_id) then
      raise exception 'NOT_ALLOWED: You cannot approve closure of work you did';
    end if;
    update public.job_cards set verified_by = auth.uid(), self_approved = v_self
    where id = v.id
    returning * into v;
    v := public._jc_set_status(v, 'closed',
      case when v_self then 'Self-approved' || coalesce(': ' || v_notes, '') else v_notes end);
    insert into public.job_closures (
      job_card_id, closed_at, completion_summary, findings, corrective_action,
      equipment_state_after, performed_by, verified_by, self_approved
    ) values (
      v.id, v.closed_at, v.completion_summary, v.findings, v.corrective_action,
      v.equipment_state_after, v.performed_by, v.verified_by, v.self_approved
    );
    perform public._jc_notify(v, v.responsible_id, 'closed', v.number || ' was closed', v.title);
    if v.registered_by is distinct from v.responsible_id then
      perform public._jc_notify(v, v.registered_by, 'closed', v.number || ' was closed', v.title);
    end if;
    perform public._jc_notify_requester(v, 'Your request is complete (' || v.number || ')', v.completion_summary);
  elsif p_decision = 'reject' then
    if v_notes is null then
      raise exception 'INVALID: Say what still needs to be done';
    end if;
    v := public._jc_set_status(v, 'accepted', v_notes);
    perform public._jc_notify(v, v.responsible_id, 'returned', v.number || ' was returned for more work', v_notes);
  else
    raise exception 'INVALID: Unknown decision %', coalesce(p_decision, '');
  end if;
  return v;
end;
$$;

create function public.fn_cancel_job_card(p_job uuid, p_reason text)
returns public.job_cards
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_cards := public._jc_for_write(p_job);
begin
  if not public._can('jc.cancel', v.site_id) then
    raise exception 'NOT_ALLOWED: You cannot cancel job cards';
  end if;
  v := public._jc_set_status(v, 'cancelled', p_reason);
  update public.job_assignments set ended_at = now(), end_reason = 'Job card cancelled'
  where job_card_id = v.id and ended_at is null;
  perform public._jc_notify(v, v.responsible_id, 'general', v.number || ' was cancelled', v.status_reason);
  if v.registered_by is distinct from v.responsible_id then
    perform public._jc_notify(v, v.registered_by, 'general', v.number || ' was cancelled', v.status_reason);
  end if;
  perform public._jc_notify_requester(v, 'Your request was cancelled (' || v.number || ')', v.status_reason);
  return v;
end;
$$;

-- Reopening keeps the earlier closure in job_closures and the status history.
create function public.fn_reopen_job_card(p_job uuid, p_reason text)
returns public.job_cards
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_cards := public._jc_for_write(p_job);
begin
  if not public._can('jc.reopen', v.site_id) then
    raise exception 'NOT_ALLOWED: You cannot reopen job cards';
  end if;
  if v.status <> 'closed' then
    raise exception 'INVALID: % is not closed', v.number;
  end if;
  v := public._jc_set_status(v, 'reopened', p_reason);
  perform public._jc_notify(v, v.responsible_id, 'returned', v.number || ' was reopened', v.status_reason);
  perform public._notify_holders(
    v.site_id, 'jc.assign', 'returned', v.number || ' was reopened', v.status_reason, 'jobcard:' || v.id
  );
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- Collaboration: comments (append-only) and files
-- ---------------------------------------------------------------------------
create function public.fn_comment_job_card(
  p_client_ref uuid,
  p_job uuid,
  p_body text,
  p_kind text,
  p_visibility text,
  p_mentions uuid[]
)
returns public.job_card_comments
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.job_card_comments;
  v public.job_cards;
  v_id uuid := coalesce(p_client_ref, gen_random_uuid());
  v_staff boolean;
  v_kind text := coalesce(p_kind, 'comment');
  v_visibility text := coalesce(p_visibility, 'internal');
  v_mentions uuid[] := '{}'::uuid[];
  v_author text;
  v_user uuid;
begin
  select * into c from public.job_card_comments where id = v_id;
  if found then
    return c;
  end if;
  v := public._jc_for_write(p_job);
  v_staff := public._can('jc.view', v.site_id);
  if length(trim(coalesce(p_body, ''))) not between 1 and 4000 then
    raise exception 'INVALID: Comments need 1 to 4000 characters';
  end if;

  if v_staff then
    if v_kind not in ('comment', 'finding', 'instruction', 'handover', 'assistance') then
      raise exception 'INVALID: Unknown comment kind %', v_kind;
    end if;
    if v_visibility not in ('internal', 'requester') then
      raise exception 'INVALID: Unknown visibility %', v_visibility;
    end if;
    v_mentions := array(
      select distinct m from unnest(coalesce(p_mentions, '{}'::uuid[])) m where m is not null
    );
    foreach v_user in array v_mentions loop
      if not public._user_can(v_user, 'jc.view', v.site_id) then
        raise exception 'INVALID: You can only mention people who can see this job card';
      end if;
    end loop;
  else
    -- The requester's comments are visible to them and to the department.
    v_kind := 'comment';
    v_visibility := 'requester';
  end if;

  insert into public.job_card_comments (id, job_card_id, author_id, kind, visibility, body, mentions)
  values (v_id, v.id, auth.uid(), v_kind, v_visibility, trim(p_body), v_mentions)
  returning * into c;

  select coalesce(nullif(full_name, ''), 'Someone') into v_author from public.profiles where id = auth.uid();
  foreach v_user in array v_mentions loop
    perform public._jc_notify(v, v_user, 'mentioned', v_author || ' mentioned you on ' || v.number, left(c.body, 140));
  end loop;
  for v_user in
    select distinct u from unnest(array[v.responsible_id, v.assigned_by]) u
    where u is not null and not (u = any (v_mentions))
  loop
    perform public._jc_notify(v, v_user, 'general',
      v_author || case v_kind when 'assistance' then ' asked for assistance on ' else ' commented on ' end || v.number,
      left(c.body, 140));
  end loop;
  if v_staff and v_visibility = 'requester' then
    perform public._jc_notify_requester(v, 'Update on your request (' || v.number || ')', left(c.body, 140));
  end if;
  return c;
end;
$$;

create function public.fn_add_job_attachment(
  p_client_ref uuid,
  p_job uuid,
  p_kind text,
  p_path text,
  p_file_name text,
  p_content_type text,
  p_size bigint,
  p_caption text
)
returns public.job_attachments
language plpgsql
security definer
set search_path = ''
as $$
declare
  f public.job_attachments;
  v public.job_cards;
  v_id uuid := coalesce(p_client_ref, gen_random_uuid());
begin
  select * into f from public.job_attachments where id = v_id;
  if found then
    return f;
  end if;
  v := public._jc_for_write(p_job);
  if not (public._can('jc.register', v.site_id) or public._can('jc.assess', v.site_id)
          or public._can('jc.execute', v.site_id)) then
    raise exception 'NOT_ALLOWED: You cannot add files to job cards at this site';
  end if;
  if v.status in ('closed', 'cancelled') then
    raise exception 'INVALID: Reopen % to add files', v.number;
  end if;
  if p_kind is null or p_kind not in ('photo_before', 'photo_after', 'photo', 'test_sheet', 'document', 'other') then
    raise exception 'INVALID: Unknown file kind';
  end if;
  if split_part(p_path, '/', 1) <> v.site_id::text
     or split_part(p_path, '/', 2) <> 'jobcard'
     or split_part(p_path, '/', 3) <> v.id::text
     or split_part(p_path, '/', 4) = '' then
    raise exception 'INVALID: File path must be <site>/jobcard/<job>/<file>';
  end if;

  insert into public.job_attachments (
    id, job_card_id, kind, bucket, path, file_name, content_type, size_bytes, caption, uploaded_by
  ) values (
    v_id, v.id, p_kind, 'job-files', p_path, nullif(trim(coalesce(p_file_name, '')), ''),
    p_content_type, p_size, nullif(trim(coalesce(p_caption, '')), ''), auth.uid()
  )
  returning * into f;
  return f;
end;
$$;

-- ---------------------------------------------------------------------------
-- Reads that join several tables
-- ---------------------------------------------------------------------------

-- Chronological timeline for one job card: status changes, assignments,
-- comments, files and field updates, each with who and when.
create function public.fn_job_card_timeline(p_job uuid)
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
  order by x.at;
$$;

-- People who can work job cards at a site, with their current load.
create function public.fn_workload(p_site uuid)
returns table (
  user_id uuid,
  full_name text,
  responsible_open integer,
  support_open integer,
  overdue integer,
  critical integer,
  estimated_hours numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.full_name,
    count(j.id) filter (where a.role = 'responsible')::integer,
    count(j.id) filter (where a.role = 'support')::integer,
    count(j.id) filter (where j.target_completion_at < now())::integer,
    count(j.id) filter (where j.is_critical)::integer,
    coalesce(sum(j.estimated_labour_hours) filter (where a.role = 'responsible'), 0)
  from public.profiles p
  left join public.job_assignments a on a.user_id = p.id and a.ended_at is null
  left join public.job_cards j
    on j.id = a.job_card_id and j.status not in ('closed', 'cancelled') and not j.is_archived
  where public._can('jc.view', p_site)
    and p.active and not p.is_archived
    and public._user_can(p.id, 'jc.execute', p_site)
  group by p.id, p.full_name
  order by p.full_name;
$$;

-- People who can see job cards at a site (for @mentions).
create function public.fn_jc_site_people(p_site uuid)
returns table (id uuid, full_name text)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.full_name
  from public.profiles p
  where public._can('jc.view', p_site)
    and p.active and not p.is_archived
    and public._user_can(p.id, 'jc.view', p_site)
  order by p.full_name;
$$;

-- Everything the dashboard shows, from the current records, in one call.
-- p_site null = every site the caller can see. Summary cards are current
-- state; the charts cover job cards received (or closed) in [p_from, p_to).
create function public.fn_dashboard(p_site uuid, p_from timestamptz, p_to timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  s public.system_settings := public._settings();
  v_sites uuid[];
  v_from timestamptz := coalesce(p_from, now() - interval '30 days');
  v_to timestamptz := coalesce(p_to, now());
  v_bucket text;
  v_result jsonb;
begin
  if p_site is not null then
    if not public._can('jc.view', p_site) then
      raise exception 'NOT_ALLOWED: You cannot see job cards at this site';
    end if;
    v_sites := array[p_site];
  else
    select coalesce(array_agg(st.id), '{}'::uuid[]) into v_sites
    from public.sites st
    where not st.is_archived and public._can('jc.view', st.id);
  end if;
  if v_to <= v_from then
    raise exception 'INVALID: The date range is empty';
  end if;
  v_bucket := case
    when v_to - v_from <= interval '62 days' then 'day'
    when v_to - v_from <= interval '366 days' then 'week'
    else 'month'
  end;

  with j as (
    select * from public.v_job_cards vj where vj.site_id = any (v_sites)
  ), r as (
    select * from j where j.received_at >= v_from and j.received_at < v_to
  ), c as (
    select * from j where j.status = 'closed' and j.closed_at >= v_from and j.closed_at < v_to
  )
  select jsonb_build_object(
    'range', jsonb_build_object('from', v_from, 'to', v_to, 'bucket', v_bucket, 'timezone', s.timezone),
    'cards', (
      select jsonb_build_object(
        'total', count(*),
        'new', count(*) filter (where j.is_new),
        'awaiting_clarification', count(*) filter (where j.status = 'awaiting_clarification'),
        'awaiting_assignment', count(*) filter (where j.is_awaiting_assignment),
        'active', count(*) filter (where j.is_active),
        'working', count(*) filter (where j.is_working),
        'waiting', count(*) filter (where j.is_waiting),
        'critical', count(*) filter (where j.is_critical_open),
        'overdue', count(*) filter (where j.is_overdue),
        'awaiting_review', count(*) filter (where j.is_awaiting_review),
        'closed', count(*) filter (where j.status = 'closed'),
        'closed_today', count(*) filter (where j.status = 'closed'
          and (j.closed_at at time zone s.timezone)::date = (now() at time zone s.timezone)::date),
        'cancelled', count(*) filter (where j.status = 'cancelled'),
        'equipment_out_of_service', count(distinct coalesce(j.asset_id::text, lower(j.equipment_name), j.id::text))
          filter (where j.equipment_state = 'out_of_service' and j.status not in ('closed', 'cancelled'))
      )
      from j
    ),
    'open_vs_closed', (
      select jsonb_build_object(
        'open', count(*) filter (where r.status not in ('closed', 'cancelled')),
        'closed', count(*) filter (where r.status = 'closed'),
        'cancelled', count(*) filter (where r.status = 'cancelled')
      )
      from r
    ),
    'by_priority', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'code', pl.code, 'name', pl.name,
        'open', (select count(*) from r where r.priority = pl.code and r.status not in ('closed', 'cancelled')),
        'closed', (select count(*) from r where r.priority = pl.code and r.status = 'closed')
      ) order by pl.sort_order), '[]'::jsonb)
      from public.priority_levels pl
    ),
    'by_area', (
      select coalesce(jsonb_agg(jsonb_build_object('label', x.label, 'count', x.n) order by x.n desc, x.label), '[]'::jsonb)
      from (
        select coalesce(r.area_name, 'No work area') as label, count(*) as n
        from r group by 1 order by 2 desc, 1 limit 10
      ) x
    ),
    'by_equipment', (
      select coalesce(jsonb_agg(jsonb_build_object('label', x.label, 'count', x.n) order by x.n desc, x.label), '[]'::jsonb)
      from (
        select coalesce(r.equipment_display, 'Not recorded') as label, count(*) as n
        from r group by 1 order by 2 desc, 1 limit 10
      ) x
    ),
    'by_technician', (
      select coalesce(jsonb_agg(jsonb_build_object('label', x.label, 'open', x.open_n, 'closed', x.closed_n)
        order by x.open_n + x.closed_n desc, x.label), '[]'::jsonb)
      from (
        select coalesce(nullif(r.responsible_name, ''), 'Unnamed') as label,
          count(*) filter (where r.status not in ('closed', 'cancelled')) as open_n,
          count(*) filter (where r.status = 'closed') as closed_n
        from r where r.responsible_id is not null group by 1
      ) x
    ),
    'by_type', (
      select coalesce(jsonb_agg(jsonb_build_object('label', x.label, 'count', x.n) order by x.n desc, x.label), '[]'::jsonb)
      from (
        select coalesce(r.maintenance_type, 'not_assessed') as label, count(*) as n from r group by 1
      ) x
    ),
    'trend', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'period', g.period, 'received', g.received, 'closed', g.closed
      ) order by g.period), '[]'::jsonb)
      from (
        select p.period::date as period,
          (select count(*) from j
            where date_trunc(v_bucket, j.received_at at time zone s.timezone) = p.period) as received,
          (select count(*) from j
            where j.closed_at is not null
              and date_trunc(v_bucket, j.closed_at at time zone s.timezone) = p.period) as closed
        from generate_series(
          date_trunc(v_bucket, v_from at time zone s.timezone),
          date_trunc(v_bucket, v_to at time zone s.timezone),
          ('1 ' || v_bucket)::interval
        ) as p (period)
      ) g
    ),
    'overdue_ageing', (
      select jsonb_build_array(
        jsonb_build_object('label', 'Under 24 h', 'count', count(*) filter (where j.overdue_minutes < 1440)),
        jsonb_build_object('label', '1–3 days', 'count',
          count(*) filter (where j.overdue_minutes >= 1440 and j.overdue_minutes < 4320)),
        jsonb_build_object('label', '4–7 days', 'count',
          count(*) filter (where j.overdue_minutes >= 4320 and j.overdue_minutes < 10080)),
        jsonb_build_object('label', '8–30 days', 'count',
          count(*) filter (where j.overdue_minutes >= 10080 and j.overdue_minutes < 43200)),
        jsonb_build_object('label', 'Over 30 days', 'count', count(*) filter (where j.overdue_minutes >= 43200))
      )
      from j where j.is_overdue
    ),
    'avg_response_minutes', (select round(avg(r.response_minutes)) from r where r.response_minutes is not null),
    'avg_closure_minutes', (select round(avg(c.elapsed_minutes)) from c),
    'response_target', (
      select jsonb_build_object(
        'met', count(*) filter (where r.response_target_met),
        'missed', count(*) filter (where r.response_target_met = false)
      )
      from r
    ),
    'completion_target', (
      select jsonb_build_object(
        'on_time', count(*) filter (where c.sla_state = 'completed_on_time'),
        'late', count(*) filter (where c.sla_state = 'completed_late')
      )
      from c
    ),
    'alerts', jsonb_build_object(
      'critical', (
        select coalesce(jsonb_agg(to_jsonb(x) order by x.priority_rank, x.received_at), '[]'::jsonb)
        from (
          select j.id, j.number, j.title, j.priority, j.priority_rank, j.status, j.responsible_name,
            j.site_code, j.equipment_display, j.received_at, j.target_completion_at,
            j.overdue_minutes, j.remaining_minutes, j.critical_reason
          from j where j.is_critical_open
          order by j.priority_rank, j.received_at limit 10
        ) x
      ),
      'overdue', (
        select coalesce(jsonb_agg(to_jsonb(x) order by x.overdue_minutes desc), '[]'::jsonb)
        from (
          select j.id, j.number, j.title, j.priority, j.status, j.responsible_name, j.site_code,
            j.equipment_display, j.target_completion_at, j.overdue_minutes
          from j where j.is_overdue
          order by j.overdue_minutes desc limit 10
        ) x
      ),
      'approaching', (
        select coalesce(jsonb_agg(to_jsonb(x) order by x.remaining_minutes), '[]'::jsonb)
        from (
          select j.id, j.number, j.title, j.priority, j.status, j.responsible_name, j.site_code,
            j.equipment_display, j.target_completion_at, j.remaining_minutes
          from j where j.sla_state = 'at_risk'
          order by j.remaining_minutes limit 10
        ) x
      ),
      'awaiting_review', (
        select coalesce(jsonb_agg(to_jsonb(x) order by x.submitted_at), '[]'::jsonb)
        from (
          select j.id, j.number, j.title, j.priority, j.status, j.responsible_name, j.site_code,
            j.equipment_display, j.submitted_at
          from j where j.is_awaiting_review
          order by j.submitted_at limit 10
        ) x
      ),
      'on_hold_long', (
        select coalesce(jsonb_agg(to_jsonb(x) order by x.status_changed_at), '[]'::jsonb)
        from (
          select j.id, j.number, j.title, j.priority, j.status, j.status_reason, j.responsible_name,
            j.site_code, j.equipment_display, j.status_changed_at
          from j
          where j.is_waiting and j.status_changed_at < now() - make_interval(hours => s.hold_alert_hours)
          order by j.status_changed_at limit 10
        ) x
      ),
      'production_impact', (
        select coalesce(jsonb_agg(to_jsonb(x) order by x.priority_rank, x.received_at), '[]'::jsonb)
        from (
          select j.id, j.number, j.title, j.priority, j.priority_rank, j.status, j.responsible_name,
            j.site_code, j.equipment_display, j.operational_impact, j.equipment_state, j.received_at
          from j
          where j.status not in ('closed', 'cancelled')
            and (j.operational_impact = 'production_stopped' or j.equipment_state = 'out_of_service')
          order by j.priority_rank, j.received_at limit 10
        ) x
      )
    )
  ) into v_result;

  return v_result;
end;
$$;

-- Global search across job cards, equipment and requests the caller can see.
create function public.fn_search(p_query text)
returns table (kind text, id uuid, ref text, title text, subtitle text)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_q text := nullif(trim(coalesce(p_query, '')), '');
  v_pattern text;
begin
  if v_q is null or length(v_q) < 2 then
    return;
  end if;
  v_pattern := '%' || replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_') || '%';

  return query
    (select 'job_card'::text, j.id, j.number, j.title,
       concat_ws(' · ', j.equipment_display, j.area_name, replace(j.status, '_', ' '))
     from public.v_job_cards j
     where public._can('jc.view', j.site_id)
       and (j.number ilike v_pattern or j.title ilike v_pattern or j.description ilike v_pattern
            or j.equipment_display ilike v_pattern or j.asset_no_display ilike v_pattern
            or j.reporter_name ilike v_pattern or j.responsible_name ilike v_pattern
            or j.area_name ilike v_pattern or j.legacy_code ilike v_pattern
            or j.request_no ilike v_pattern)
     order by j.received_at desc
     limit 15)
    union all
    (select 'asset'::text, a.id, a.asset_no, a.name, coalesce(a.location, '')
     from public.assets a
     where not a.is_archived
       and (public._can('assets.view', a.site_id) or public._can('jc.view', a.site_id))
       and (a.asset_no ilike v_pattern or a.name ilike v_pattern or a.serial_no ilike v_pattern)
     order by a.asset_no
     limit 10)
    union all
    (select 'request'::text, sr.id, sr.request_no, sr.title, replace(sr.status, '_', ' ')
     from public.service_requests sr
     where not sr.is_archived
       and ((sr.requested_by = auth.uid() and public._active())
            or public._can('req.triage', sr.site_id) or public._can('jc.view', sr.site_id))
       and (sr.request_no ilike v_pattern or sr.title ilike v_pattern
            or sr.description ilike v_pattern or sr.reporter_name ilike v_pattern)
     order by sr.submitted_at desc
     limit 10);
end;
$$;

-- ---------------------------------------------------------------------------
-- Administration
-- ---------------------------------------------------------------------------
create function public.fn_save_settings(
  p_timezone text,
  p_jobcard_prefix text,
  p_request_prefix text,
  p_number_digits integer,
  p_number_reset_yearly boolean,
  p_response_ends_at text,
  p_at_risk_percent integer,
  p_hold_alert_hours integer,
  p_handover_note_required boolean,
  p_company_name text,
  p_department_name text,
  p_logo_path text
)
returns public.system_settings
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.system_settings;
begin
  if not public._can('settings.manage', null) then
    raise exception 'NOT_ALLOWED: Only a system administrator can change settings';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = p_timezone) then
    raise exception 'INVALID: Unknown time zone %', coalesce(p_timezone, '');
  end if;
  if coalesce(p_jobcard_prefix, '') !~ '^[A-Z0-9][A-Z0-9-]{0,11}$'
     or coalesce(p_request_prefix, '') !~ '^[A-Z0-9][A-Z0-9-]{0,11}$' then
    raise exception 'INVALID: Prefixes use capital letters, digits and dashes (up to 12)';
  end if;
  if p_number_digits is null or p_number_digits not between 3 and 8 then
    raise exception 'INVALID: Number digits must be between 3 and 8';
  end if;
  if p_response_ends_at is null or p_response_ends_at not in ('acknowledged', 'assessed', 'assigned') then
    raise exception 'INVALID: Choose when the response time ends';
  end if;
  if p_at_risk_percent is null or p_at_risk_percent not between 1 and 90 then
    raise exception 'INVALID: The at-risk threshold must be between 1 and 90 percent';
  end if;
  if p_hold_alert_hours is null or p_hold_alert_hours not between 1 and 2160 then
    raise exception 'INVALID: The on-hold alert must be between 1 and 2160 hours';
  end if;
  if nullif(trim(coalesce(p_company_name, '')), '') is null
     or nullif(trim(coalesce(p_department_name, '')), '') is null then
    raise exception 'INVALID: Company and department names are required';
  end if;

  update public.system_settings set
    timezone = p_timezone,
    jobcard_prefix = p_jobcard_prefix,
    request_prefix = p_request_prefix,
    number_digits = p_number_digits,
    number_reset_yearly = coalesce(p_number_reset_yearly, true),
    response_ends_at = p_response_ends_at,
    at_risk_percent = p_at_risk_percent,
    hold_alert_hours = p_hold_alert_hours,
    handover_note_required = coalesce(p_handover_note_required, true),
    company_name = trim(p_company_name),
    department_name = trim(p_department_name),
    logo_path = nullif(trim(coalesce(p_logo_path, '')), ''),
    updated_by = auth.uid()
  where singleton
  returning * into v;
  return v;
end;
$$;

-- New targets apply to job cards registered from now on.
create function public.fn_save_priority(
  p_code text,
  p_name text,
  p_description text,
  p_response_minutes integer,
  p_completion_minutes integer
)
returns public.priority_levels
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.priority_levels;
begin
  if not public._can('settings.manage', null) then
    raise exception 'NOT_ALLOWED: Only a system administrator can change priorities';
  end if;
  if length(trim(coalesce(p_name, ''))) not between 2 and 40 then
    raise exception 'INVALID: The priority name needs 2 to 40 characters';
  end if;
  if p_response_minutes is null or p_response_minutes not between 1 and 525600
     or p_completion_minutes is null or p_completion_minutes not between 1 and 525600 then
    raise exception 'INVALID: Targets must be between 1 minute and 365 days';
  end if;
  if p_completion_minutes < p_response_minutes then
    raise exception 'INVALID: The completion target cannot be shorter than the response target';
  end if;

  update public.priority_levels set
    name = trim(p_name),
    description = nullif(trim(coalesce(p_description, '')), ''),
    response_minutes = p_response_minutes,
    completion_minutes = p_completion_minutes,
    targets_confirmed = true,
    updated_by = auth.uid()
  where code = p_code
  returning * into v;
  if v.id is null then
    raise exception 'INVALID: Unknown priority %', coalesce(p_code, '');
  end if;
  return v;
end;
$$;

create function public.fn_save_department(
  p_id uuid,
  p_code text,
  p_name text,
  p_is_electrical boolean,
  p_archived boolean
)
returns public.departments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.departments;
begin
  if not public._can('settings.manage', null) then
    raise exception 'NOT_ALLOWED: Only a system administrator can change departments';
  end if;
  if coalesce(p_code, '') !~ '^[A-Z0-9]{2,10}$' then
    raise exception 'INVALID: The code uses 2 to 10 capital letters or digits';
  end if;
  if length(trim(coalesce(p_name, ''))) not between 2 and 80 then
    raise exception 'INVALID: The name needs 2 to 80 characters';
  end if;
  begin
    insert into public.departments as d (id, code, name, is_electrical, is_archived)
    values (coalesce(p_id, gen_random_uuid()), p_code, trim(p_name),
            coalesce(p_is_electrical, false), coalesce(p_archived, false))
    on conflict (id) do update set
      code = excluded.code, name = excluded.name,
      is_electrical = excluded.is_electrical, is_archived = excluded.is_archived
    returning * into v;
  exception when unique_violation then
    raise exception 'INVALID: That department code or name is already used';
  end;
  return v;
end;
$$;

create function public.fn_save_job_category(
  p_id uuid,
  p_name text,
  p_description text,
  p_sort_order integer,
  p_archived boolean
)
returns public.job_categories
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_categories;
begin
  if not public._can('settings.manage', null) then
    raise exception 'NOT_ALLOWED: Only a system administrator can change job categories';
  end if;
  if length(trim(coalesce(p_name, ''))) not between 2 and 80 then
    raise exception 'INVALID: The name needs 2 to 80 characters';
  end if;
  begin
    insert into public.job_categories as c (id, name, description, sort_order, is_archived)
    values (coalesce(p_id, gen_random_uuid()), trim(p_name), nullif(trim(coalesce(p_description, '')), ''),
            coalesce(p_sort_order, 100), coalesce(p_archived, false))
    on conflict (id) do update set
      name = excluded.name, description = excluded.description,
      sort_order = excluded.sort_order, is_archived = excluded.is_archived
    returning * into v;
  exception when unique_violation then
    raise exception 'INVALID: That job category already exists';
  end;
  return v;
end;
$$;

create function public.fn_save_asset_category(
  p_id uuid,
  p_name text,
  p_sort_order integer,
  p_archived boolean
)
returns public.asset_categories
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.asset_categories;
begin
  if not public._can('settings.manage', null) then
    raise exception 'NOT_ALLOWED: Only a system administrator can change asset categories';
  end if;
  if length(trim(coalesce(p_name, ''))) not between 2 and 80 then
    raise exception 'INVALID: The name needs 2 to 80 characters';
  end if;
  begin
    insert into public.asset_categories as c (id, name, sort_order, is_archived)
    values (coalesce(p_id, gen_random_uuid()), trim(p_name), coalesce(p_sort_order, 100),
            coalesce(p_archived, false))
    on conflict (id) do update set
      name = excluded.name, sort_order = excluded.sort_order, is_archived = excluded.is_archived
    returning * into v;
  exception when unique_violation then
    raise exception 'INVALID: That asset category already exists';
  end;
  return v;
end;
$$;

create function public.fn_save_escalation_contact(
  p_id uuid,
  p_site uuid,
  p_priority text,
  p_user uuid,
  p_archived boolean
)
returns public.escalation_contacts
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.escalation_contacts;
begin
  if not public._can('settings.manage', null) then
    raise exception 'NOT_ALLOWED: Only a system administrator can change escalation contacts';
  end if;
  if not exists (select 1 from public.priority_levels where code = p_priority) then
    raise exception 'INVALID: Choose a priority from P1 to P4';
  end if;
  if p_site is not null and not exists (select 1 from public.sites where id = p_site and not is_archived) then
    raise exception 'INVALID: Unknown site';
  end if;
  if not exists (select 1 from public.profiles where id = p_user and active and not is_archived) then
    raise exception 'INVALID: Choose an active user';
  end if;
  begin
    insert into public.escalation_contacts as e (id, site_id, priority_code, user_id, is_archived)
    values (coalesce(p_id, gen_random_uuid()), p_site, p_priority, p_user, coalesce(p_archived, false))
    on conflict (id) do update set
      site_id = excluded.site_id, priority_code = excluded.priority_code,
      user_id = excluded.user_id, is_archived = excluded.is_archived
    returning * into v;
  exception when unique_violation then
    raise exception 'INVALID: That person is already a contact for this priority and site';
  end;
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- Scheduled: overdue job cards (once per deadline)
-- ---------------------------------------------------------------------------
create function public.fn_notify_overdue_job_cards()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  j public.job_cards;
  v_count integer := 0;
begin
  for j in
    select * from public.job_cards
    where not is_archived
      and status not in ('closed', 'cancelled')
      and target_completion_at < now()
      and overdue_notified_at is null
    for update skip locked
  loop
    if j.responsible_id is not null then
      perform public.fn_notify(j.responsible_id, j.site_id, 'overdue',
        j.number || ' is overdue', j.title, 'jobcard:' || j.id);
      if j.assigned_by is not null and j.assigned_by <> j.responsible_id then
        perform public.fn_notify(j.assigned_by, j.site_id, 'overdue',
          j.number || ' is overdue', j.title, 'jobcard:' || j.id);
      end if;
    else
      perform public._notify_holders(j.site_id, 'jc.assign', 'overdue',
        j.number || ' is overdue and not assigned', j.title, 'jobcard:' || j.id);
    end if;
    update public.job_cards set overdue_notified_at = now() where id = j.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

select cron.schedule('jobcards-overdue', '10 * * * *', 'select public.fn_notify_overdue_job_cards()');

-- ---------------------------------------------------------------------------
-- Privileges: helpers are internal; the app calls the fn_* functions below
-- ---------------------------------------------------------------------------
revoke execute on function
  public._jc_holds(),
  public._jc_is_requester(public.job_cards),
  public._jc_for_write(uuid),
  public._jc_my_role(uuid),
  public._jc_check_place(uuid, uuid, text, uuid),
  public._jc_set_status(public.job_cards, text, text),
  public._jc_notify(public.job_cards, uuid, text, text, text),
  public._notify_holders(uuid, text, text, text, text, text),
  public._jc_notify_critical(public.job_cards),
  public._jc_notify_requester(public.job_cards, text, text),
  public.fn_notify_overdue_job_cards(),
  public.fn_submit_request(uuid, uuid, uuid, text, uuid, text, text, uuid, text, text, text, text),
  public.fn_triage_request(uuid, text, text),
  public.fn_resubmit_request(uuid, text, text, text, text),
  public.fn_withdraw_request(uuid, text),
  public.fn_add_request_attachment(uuid, uuid, text, text, text, bigint),
  public.fn_request_tracking(uuid),
  public.fn_register_job_card(uuid, uuid, uuid, uuid, text, timestamptz, text, uuid, uuid, text, text, text, uuid, text, text, text, text, timestamptz),
  public.fn_assess_job_card(uuid, boolean, text, text, text, text, text, text, integer, text, boolean, boolean, boolean, numeric, text, timestamptz, timestamptz, text),
  public.fn_return_for_clarification(uuid, text),
  public.fn_provide_clarification(uuid, text),
  public.fn_assign_job_card(uuid, uuid, uuid[], timestamptz, timestamptz, numeric, text, text, text, text, text, text),
  public.fn_unassign_job_card(uuid, text),
  public.fn_accept_job_card(uuid),
  public.fn_set_job_card_status(uuid, text, text),
  public.fn_escalate_job_card(uuid, boolean, text),
  public.fn_submit_job_card(uuid, text, text, text, text, boolean),
  public.fn_review_job_card(uuid, text, text),
  public.fn_cancel_job_card(uuid, text),
  public.fn_reopen_job_card(uuid, text),
  public.fn_comment_job_card(uuid, uuid, text, text, text, uuid[]),
  public.fn_add_job_attachment(uuid, uuid, text, text, text, text, bigint, text),
  public.fn_job_card_timeline(uuid),
  public.fn_workload(uuid),
  public.fn_jc_site_people(uuid),
  public.fn_dashboard(uuid, timestamptz, timestamptz),
  public.fn_search(text),
  public.fn_save_settings(text, text, text, integer, boolean, text, integer, integer, boolean, text, text, text),
  public.fn_save_priority(text, text, text, integer, integer),
  public.fn_save_department(uuid, text, text, boolean, boolean),
  public.fn_save_job_category(uuid, text, text, integer, boolean),
  public.fn_save_asset_category(uuid, text, integer, boolean),
  public.fn_save_escalation_contact(uuid, uuid, text, uuid, boolean)
from public, anon, authenticated;

grant execute on function
  public.fn_submit_request(uuid, uuid, uuid, text, uuid, text, text, uuid, text, text, text, text),
  public.fn_triage_request(uuid, text, text),
  public.fn_resubmit_request(uuid, text, text, text, text),
  public.fn_withdraw_request(uuid, text),
  public.fn_add_request_attachment(uuid, uuid, text, text, text, bigint),
  public.fn_request_tracking(uuid),
  public.fn_register_job_card(uuid, uuid, uuid, uuid, text, timestamptz, text, uuid, uuid, text, text, text, uuid, text, text, text, text, timestamptz),
  public.fn_assess_job_card(uuid, boolean, text, text, text, text, text, text, integer, text, boolean, boolean, boolean, numeric, text, timestamptz, timestamptz, text),
  public.fn_return_for_clarification(uuid, text),
  public.fn_provide_clarification(uuid, text),
  public.fn_assign_job_card(uuid, uuid, uuid[], timestamptz, timestamptz, numeric, text, text, text, text, text, text),
  public.fn_unassign_job_card(uuid, text),
  public.fn_accept_job_card(uuid),
  public.fn_set_job_card_status(uuid, text, text),
  public.fn_escalate_job_card(uuid, boolean, text),
  public.fn_submit_job_card(uuid, text, text, text, text, boolean),
  public.fn_review_job_card(uuid, text, text),
  public.fn_cancel_job_card(uuid, text),
  public.fn_reopen_job_card(uuid, text),
  public.fn_comment_job_card(uuid, uuid, text, text, text, uuid[]),
  public.fn_add_job_attachment(uuid, uuid, text, text, text, text, bigint, text),
  public.fn_job_card_timeline(uuid),
  public.fn_workload(uuid),
  public.fn_jc_site_people(uuid),
  public.fn_dashboard(uuid, timestamptz, timestamptz),
  public.fn_search(text),
  public.fn_save_settings(text, text, text, integer, boolean, text, integer, integer, boolean, text, text, text),
  public.fn_save_priority(text, text, text, integer, integer),
  public.fn_save_department(uuid, text, text, boolean, boolean),
  public.fn_save_job_category(uuid, text, text, integer, boolean),
  public.fn_save_asset_category(uuid, text, integer, boolean),
  public.fn_save_escalation_contact(uuid, uuid, text, uuid, boolean)
to authenticated;

insert into public.schema_migrations (filename) values ('0013_v2_workflow.sql')
on conflict do nothing;
