-- 0026_tool_issue_forms: the paper tool issue form in the app (API.md
-- section 11b). One form hands several tools to one person, who may be
-- someone outside the app (a contractor's electrician): with their company,
-- the project team lead, the place, the expected return date, each tool's
-- condition going out and coming back, and three signatures each way.
--
-- A tool is now "out" while it has an open tool_issues row; holder_id stays
-- the app user holding it (null for someone outside the app) and the new
-- holder_name always says who has it. A tool whose calibration has
-- expired cannot go out.
--
-- A tool that comes back damaged or needing repair gets a repair job card
-- (registered by the system on the store's behalf, since storekeepers
-- cannot register job cards), so repairs queue with the rest of the work.
-- Calibration certificates (PDFs) are kept per tool; the newest one sets
-- the calibration due date.
--
-- Job cards list the tools the job needs (job_card_tools), so each tool's
-- page shows the jobs it was used on. A form issued for a job card links
-- its tools to that job card too.

-- TI- codes for the forms.
alter table public.code_counters drop constraint code_counters_prefix_check;
alter table public.code_counters add constraint code_counters_prefix_check
  check (prefix in ('J', 'T', 'S', 'M', 'R', 'MR', 'I', 'PO', 'P', 'RQ', 'TI'));

create table public.tool_issue_forms (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id),
  code text not null,
  issued_by uuid references public.profiles (id) default auth.uid(),
  issued_at timestamptz not null default now(),
  recipient_id uuid references public.profiles (id),
  recipient_name text not null check (length(trim(recipient_name)) between 2 and 120),
  recipient_role text check (length(recipient_role) <= 60),
  company text check (length(company) <= 120),
  team_lead text check (length(team_lead) <= 120),
  location text check (length(location) <= 120),
  job_card_id uuid references public.job_cards (id),
  due_back date,
  remarks text check (length(remarks) <= 2000),
  issuer_signature text,
  recipient_signature text,
  lead_signature text,
  status text not null default 'out' check (status in ('out', 'part_returned', 'returned')),
  returned_at timestamptz,
  received_back_by uuid references public.profiles (id),
  return_issuer_signature text,
  return_recipient_signature text,
  return_lead_signature text,
  return_remarks text check (length(return_remarks) <= 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (site_id, code)
);
create index tool_issue_forms_site on public.tool_issue_forms (site_id, issued_at desc);

create trigger tool_issue_forms_touch before update on public.tool_issue_forms
  for each row execute function public.fn_touch_updated_at();

alter table public.tool_issues
  alter column issued_to drop not null,
  add column form_id uuid references public.tool_issue_forms (id),
  add column qty integer not null default 1 check (qty between 1 and 999),
  add column issue_condition text check (issue_condition in ('good', 'needs_repair', 'damaged', 'lost'));
create index tool_issues_form on public.tool_issues (form_id) where form_id is not null;

alter table public.tools
  add column holder_name text,
  add column issue_form_id uuid references public.tool_issue_forms (id),
  add column repair_job_card_id uuid references public.job_cards (id);

create table public.tool_certificates (
  id uuid primary key default gen_random_uuid(),
  tool_id uuid not null references public.tools (id),
  path text not null,
  file_name text check (length(file_name) <= 200),
  issued_on date,
  valid_until date not null,
  uploaded_by uuid references public.profiles (id) default auth.uid(),
  uploaded_at timestamptz not null default now(),
  is_archived boolean not null default false
);
create index tool_certificates_tool on public.tool_certificates (tool_id, valid_until desc);

update public.tools t set holder_name = p.full_name
from public.profiles p
where p.id = t.holder_id;

-- Tools a job card needs or used.
create table public.job_card_tools (
  job_card_id uuid not null references public.job_cards (id),
  tool_id uuid not null references public.tools (id),
  linked_by uuid references public.profiles (id) default auth.uid(),
  linked_at timestamptz not null default now(),
  primary key (job_card_id, tool_id)
);
create index job_card_tools_tool on public.job_card_tools (tool_id);

-- Whether the tool has an open issue.
create function public._tool_out(p_tool uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.tool_issues where tool_id = p_tool and returned_at is null);
$$;

-- After tools on a form come back: part returned, or returned.
create function public._refresh_tool_form(p_form uuid)
returns public.tool_issue_forms
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.tool_issue_forms;
  v_open integer;
  v_back integer;
begin
  select count(*) filter (where returned_at is null), count(*) filter (where returned_at is not null)
  into v_open, v_back
  from public.tool_issues where form_id = p_form;
  update public.tool_issue_forms set
    status = case when v_open = 0 then 'returned' when v_back > 0 then 'part_returned' else 'out' end,
    returned_at = case when v_open = 0 then coalesce(returned_at, now()) end,
    received_back_by = case when v_open = 0 then coalesce(received_back_by, auth.uid()) end
  where id = p_form
  returning * into v;
  return v;
end;
$$;

-- A repair job card for a tool that came back damaged or needing repair,
-- unless one is still open. Registered on the store's behalf (P3, minor
-- impact) and sent to the people who assess job cards.
create function public._open_tool_repair(p_tool public.tools, p_condition text, p_note text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_cards;
  pl public.priority_levels;
  v_by text;
begin
  if p_tool.repair_job_card_id is not null and exists (
    select 1 from public.job_cards
    where id = p_tool.repair_job_card_id and not is_archived and status not in ('closed', 'cancelled')
  ) then
    return p_tool.repair_job_card_id;
  end if;
  select * into pl from public.priority_levels where code = 'P3';
  select nullif(trim(full_name), '') into v_by from public.profiles where id = auth.uid();
  insert into public.job_cards (
    number, source, site_id, location, received_at, reporter_name, equipment_name,
    equipment_asset_no, title, description, operational_impact, priority, registered_by,
    target_response_at, target_completion_at
  ) values (
    public._next_doc_no('jobcard', now()), 'direct', p_tool.site_id, 'Tool store', now(),
    coalesce(v_by, 'Tool store'), left(p_tool.name, 120), p_tool.code,
    left('Repair ' || p_tool.code || ' ' || p_tool.name, 120),
    left(p_tool.code || ' ' || p_tool.name || ' came back ' || replace(p_condition, '_', ' ')
      || coalesce(': ' || nullif(trim(coalesce(p_note, '')), ''), '')
      || '. Raised by the tool store when it was returned.', 4000),
    'minor', pl.code, auth.uid(),
    now() + make_interval(mins => pl.response_minutes),
    now() + make_interval(mins => pl.completion_minutes)
  )
  returning * into v;
  insert into public.job_card_tools (job_card_id, tool_id) values (v.id, p_tool.id)
  on conflict do nothing;
  update public.tools set repair_job_card_id = v.id where id = p_tool.id;
  perform public._notify_holders(v.site_id, 'jc.assess', 'registered',
    'New job card ' || v.number || ' (' || v.priority || '): repair ' || p_tool.code,
    v.title, 'jobcard:' || v.id);
  return v.id;
end;
$$;

-- Takes one tool back (the caller has checked permission).
create function public._take_tool_back(p_tool public.tools, p_condition text, p_note text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_form uuid;
begin
  if coalesce(p_condition, '') not in ('good', 'needs_repair', 'damaged', 'lost') then
    raise exception 'INVALID: Say what condition % came back in', p_tool.code;
  end if;
  if p_condition <> 'good' and length(trim(coalesce(p_note, ''))) = 0 then
    raise exception 'INVALID: Say what is wrong with %', p_tool.code;
  end if;
  update public.tool_issues set
    returned_at = now(), returned_by = auth.uid(),
    return_condition = p_condition, return_note = nullif(trim(coalesce(p_note, '')), '')
  where tool_id = p_tool.id and returned_at is null
  returning form_id into v_form;
  update public.tools set
    holder_id = null, holder_name = null, issue_form_id = null,
    issued_at = null, due_back = null, condition = p_condition
  where id = p_tool.id;
  if p_condition <> 'good' then
    perform public.fn_notify_permission(p_tool.site_id, 'jobs.assign', 'general',
      p_tool.code || ' came back ' || replace(p_condition, '_', ' '), p_note, 'tool:' || p_tool.id);
  end if;
  if p_condition in ('damaged', 'needs_repair') then
    perform public._open_tool_repair(p_tool, p_condition, p_note);
  end if;
  return v_form;
end;
$$;

-- The job card's team or a supervisor adds and removes its tools, until it
-- is closed or cancelled.
create function public.fn_link_job_card_tool(p_job_card uuid, p_tool uuid, p_linked boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  j public.job_cards;
  t public.tools;
begin
  select * into j from public.job_cards where id = p_job_card and not is_archived;
  if not found or not public._can('jc.view', j.site_id) then
    raise exception 'NOT_FOUND: Job card not found';
  end if;
  if not (
    coalesce(j.registered_by = auth.uid(), false)
    or coalesce(j.responsible_id = auth.uid(), false)
    or exists (
      select 1 from public.job_assignments a
      where a.job_card_id = j.id and a.user_id = auth.uid() and a.ended_at is null
    )
    or public._can('jc.assign', j.site_id)
    or public._can('jc.assess', j.site_id)
    or public._can('tools.issue', j.site_id)
  ) then
    raise exception 'NOT_ALLOWED: Only the team on this job card, the store or a supervisor can change its tools';
  end if;
  if j.status in ('closed', 'cancelled') then
    raise exception 'INVALID: % is %; its tools can no longer change', j.number, j.status;
  end if;
  select * into t from public.tools where id = p_tool and not is_archived;
  if not found or t.site_id <> j.site_id then
    raise exception 'INVALID: That tool is not in this job card''s site register';
  end if;
  if coalesce(p_linked, true) then
    insert into public.job_card_tools (job_card_id, tool_id) values (j.id, t.id)
    on conflict do nothing;
  else
    delete from public.job_card_tools where job_card_id = j.id and tool_id = t.id;
  end if;
end;
$$;

-- A calibration certificate (PDF or photo, uploaded to tool-files first).
-- The newest valid-until date becomes the tool's calibration due date.
create function public.fn_add_tool_certificate(
  p_client_ref uuid,
  p_tool uuid,
  p_path text,
  p_file_name text,
  p_issued_on date,
  p_valid_until date
)
returns public.tool_certificates
language plpgsql
security definer
set search_path = ''
as $$
declare
  t public.tools;
  v public.tool_certificates;
begin
  select * into v from public.tool_certificates where id = p_client_ref;
  if found then
    return v;
  end if;
  t := public._tool_for_write(p_tool);
  if p_path is null or p_path not like t.site_id || '/tool/' || t.id || '/%' then
    raise exception 'INVALID: The certificate file is not in this tool''s folder';
  end if;
  if p_valid_until is null then
    raise exception 'INVALID: Say until when the calibration is valid';
  end if;
  if p_issued_on is not null and p_issued_on > p_valid_until then
    raise exception 'INVALID: The certificate cannot expire before it was issued';
  end if;
  insert into public.tool_certificates (id, tool_id, path, file_name, issued_on, valid_until)
  values (p_client_ref, t.id, p_path, left(nullif(trim(coalesce(p_file_name, '')), ''), 200),
    p_issued_on, p_valid_until)
  returning * into v;
  update public.tools set calibration_due = p_valid_until, calibration_notified_on = null
  where id = t.id and (calibration_due is null or calibration_due <= p_valid_until);
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- Issue form: several tools to one person
-- ---------------------------------------------------------------------------
create function public.fn_issue_tools(
  p_client_ref uuid,
  p_site uuid,
  p_items jsonb,
  p_to uuid,
  p_name text,
  p_role text,
  p_company text,
  p_team_lead text,
  p_location text,
  p_due_back date,
  p_remarks text,
  p_signatures jsonb,
  p_job_card uuid default null
)
returns public.tool_issue_forms
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.tool_issue_forms;
  v_tool public.tools;
  v_item jsonb;
  v_name text;
  v_condition text;
  v_qty integer;
  v_count integer;
begin
  select * into v from public.tool_issue_forms where id = p_client_ref;
  if found then
    return v;
  end if;
  if not public._can('tools.issue', p_site) then
    raise exception 'NOT_ALLOWED: Only the store or a supervisor can issue tools';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'INVALID: Add at least one tool';
  end if;
  if jsonb_array_length(p_items) > 100 then
    raise exception 'INVALID: One form takes up to 100 tools';
  end if;
  select count(distinct e->>'tool_id'), count(*) into v_count, v_qty
  from jsonb_array_elements(p_items) e;
  if v_count <> v_qty then
    raise exception 'INVALID: A tool is on the form twice';
  end if;
  if p_to is not null then
    if not public._user_can(p_to, 'tools.view', p_site) then
      raise exception 'INVALID: That person does not work at this site';
    end if;
    select full_name into v_name from public.profiles where id = p_to;
  end if;
  v_name := coalesce(nullif(trim(coalesce(p_name, '')), ''), v_name);
  if length(coalesce(v_name, '')) not between 2 and 120 then
    raise exception 'INVALID: Say who is receiving the tools';
  end if;
  if p_due_back is not null and p_due_back < public._harare_today() then
    raise exception 'INVALID: The return date is in the past';
  end if;
  if p_job_card is not null and not exists (
    select 1 from public.job_cards where id = p_job_card and site_id = p_site and not is_archived
  ) then
    raise exception 'INVALID: That job card is not at this site';
  end if;
  if p_signatures is not null and jsonb_typeof(p_signatures) <> 'object' then
    raise exception 'INVALID: Signatures are not readable';
  end if;

  insert into public.tool_issue_forms (
    id, site_id, code, recipient_id, recipient_name, recipient_role, company, team_lead,
    location, job_card_id, due_back, remarks, issuer_signature, recipient_signature, lead_signature
  ) values (
    p_client_ref, p_site, public.next_code(p_site, 'TI'), p_to, v_name,
    nullif(trim(coalesce(p_role, '')), ''), nullif(trim(coalesce(p_company, '')), ''),
    nullif(trim(coalesce(p_team_lead, '')), ''), nullif(trim(coalesce(p_location, '')), ''),
    p_job_card, p_due_back, nullif(trim(coalesce(p_remarks, '')), ''),
    p_signatures->>'issuer', p_signatures->>'recipient', p_signatures->>'lead'
  )
  returning * into v;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select * into v_tool from public.tools
    where id = (v_item->>'tool_id')::uuid and not is_archived
    for update;
    if not found or v_tool.site_id <> p_site then
      raise exception 'NOT_FOUND: A tool on the form is not in this site''s register';
    end if;
    if public._tool_out(v_tool.id) then
      raise exception 'CONFLICT: % is already out', v_tool.code;
    end if;
    v_condition := coalesce(v_item->>'condition', v_tool.condition);
    if v_condition not in ('good', 'needs_repair') then
      raise exception 'INVALID: % is % and cannot be issued', v_tool.code, replace(v_condition, '_', ' ');
    end if;
    if v_tool.calibration_due < public._harare_today() then
      raise exception 'INVALID: % calibration expired on %; it cannot be issued',
        v_tool.code, to_char(v_tool.calibration_due, 'DD Mon YYYY');
    end if;
    v_qty := coalesce((v_item->>'qty')::integer, 1);
    if v_qty not between 1 and 999 then
      raise exception 'INVALID: The quantity for % must be 1 to 999', v_tool.code;
    end if;
    insert into public.tool_issues (tool_id, issued_to, due_back, signature_path, form_id, qty, issue_condition)
    values (v_tool.id, p_to, p_due_back, v.recipient_signature, v.id, v_qty, v_condition);
    update public.tools set
      holder_id = p_to, holder_name = v_name, issue_form_id = v.id,
      issued_at = now(), due_back = p_due_back, condition = v_condition
    where id = v_tool.id;
    if p_job_card is not null then
      insert into public.job_card_tools (job_card_id, tool_id) values (p_job_card, v_tool.id)
      on conflict do nothing;
    end if;
  end loop;

  if p_to is not null and p_to is distinct from auth.uid() then
    perform public.fn_notify(p_to, p_site, 'general',
      v.code || ': ' || jsonb_array_length(p_items) || ' tools issued to you',
      coalesce('Back by ' || to_char(p_due_back, 'DD Mon'), 'Tool issue form'),
      'toolform:' || v.id);
  end if;
  return v;
end;
$$;

-- Takes back some or all of a form's tools: p_items is
-- [{tool_id, condition, note}]. Signatures and remarks are kept for the
-- form's return section.
create function public.fn_return_tools(
  p_form uuid,
  p_items jsonb,
  p_signatures jsonb,
  p_remarks text
)
returns public.tool_issue_forms
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.tool_issue_forms;
  v_tool public.tools;
  v_item jsonb;
begin
  select * into v from public.tool_issue_forms where id = p_form for update;
  if not found or not public._can('tools.view', v.site_id) then
    raise exception 'NOT_FOUND: Form not found';
  end if;
  if not public._can('tools.issue', v.site_id) then
    raise exception 'NOT_ALLOWED: Only the store or a supervisor can take tools back';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'INVALID: Say which tools came back';
  end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select t.* into v_tool from public.tools t
    join public.tool_issues i on i.tool_id = t.id and i.form_id = v.id and i.returned_at is null
    where t.id = (v_item->>'tool_id')::uuid
    for update of t;
    -- Already back (a repeat from the outbox): nothing to do.
    continue when not found;
    perform public._take_tool_back(v_tool, v_item->>'condition', v_item->>'note');
  end loop;

  update public.tool_issue_forms set
    return_issuer_signature = coalesce(p_signatures->>'issuer', return_issuer_signature),
    return_recipient_signature = coalesce(p_signatures->>'recipient', return_recipient_signature),
    return_lead_signature = coalesce(p_signatures->>'lead', return_lead_signature),
    return_remarks = coalesce(nullif(trim(coalesce(p_remarks, '')), ''), return_remarks)
  where id = v.id;
  return public._refresh_tool_form(v.id);
end;
$$;

-- ---------------------------------------------------------------------------
-- The single-tool functions follow the open issue, not holder_id
-- ---------------------------------------------------------------------------
create or replace function public.fn_issue_tool(
  p_client_ref uuid,
  p_tool uuid,
  p_to uuid,
  p_due_back date,
  p_signature_path text
)
returns public.tools
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.tools;
begin
  if exists (select 1 from public.tool_issues where id = p_client_ref) then
    select * into v from public.tools where id = p_tool;
    return v;
  end if;
  v := public._tool_for_write(p_tool);
  if public._tool_out(v.id) then
    raise exception 'CONFLICT: % is already out', v.code;
  end if;
  if v.condition in ('damaged', 'lost') then
    raise exception 'INVALID: % is marked %; it cannot be issued', v.code, v.condition;
  end if;
  if v.calibration_due < public._harare_today() then
    raise exception 'INVALID: % calibration expired on %; it cannot be issued',
      v.code, to_char(v.calibration_due, 'DD Mon YYYY');
  end if;
  if not public._user_can(p_to, 'tools.view', v.site_id) then
    raise exception 'INVALID: That person does not work at this site';
  end if;
  if p_due_back is not null and p_due_back < (now() at time zone 'Africa/Harare')::date then
    raise exception 'INVALID: The return date is in the past';
  end if;

  insert into public.tool_issues (id, tool_id, issued_to, due_back, signature_path, issue_condition)
  values (p_client_ref, v.id, p_to, p_due_back, p_signature_path, v.condition);
  update public.tools
  set holder_id = p_to, issued_at = now(), due_back = p_due_back,
    holder_name = (select full_name from public.profiles where id = p_to), issue_form_id = null
  where id = v.id
  returning * into v;

  if p_to is distinct from auth.uid() then
    perform public.fn_notify(p_to, v.site_id, 'general',
      v.code || ' issued to you', v.name ||
        coalesce(' · back by ' || to_char(p_due_back, 'DD Mon'), ''), 'tool:' || v.id);
  end if;
  return v;
end;
$$;

create or replace function public.fn_return_tool(p_tool uuid, p_condition text, p_note text)
returns public.tools
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.tools := public._tool_for_write(p_tool);
  v_form uuid;
begin
  if not public._tool_out(v.id) then
    return v;
  end if;
  v_form := public._take_tool_back(v, p_condition, p_note);
  if v_form is not null then
    perform public._refresh_tool_form(v_form);
  end if;
  select * into v from public.tools where id = v.id;
  return v;
end;
$$;

-- Overdue reminders: someone outside the app has no inbox, so only the
-- store hears about their tools.
create or replace function public.fn_notify_tools()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'Africa/Harare')::date;
  r record;
  v_count integer := 0;
begin
  for r in
    select i.id, i.issued_to, t.id as tool_id, t.site_id, t.code, t.name, t.holder_name
    from public.tool_issues i
    join public.tools t on t.id = i.tool_id
    where i.returned_at is null and i.due_back < v_today and i.overdue_notified_at is null
      and not t.is_archived
    for update of i skip locked
  loop
    if r.issued_to is not null then
      perform public.fn_notify(r.issued_to, r.site_id, 'overdue',
        r.code || ' is overdue for return', r.name, 'tool:' || r.tool_id);
    end if;
    perform public.fn_notify_permission(r.site_id, 'tools.issue', 'overdue',
      r.code || ' is overdue for return',
      r.name || coalesce(' · with ' || r.holder_name, ''), 'tool:' || r.tool_id);
    update public.tool_issues set overdue_notified_at = now() where id = r.id;
    v_count := v_count + 1;
  end loop;

  for r in
    select t.id, t.site_id, t.code, t.name, t.calibration_due
    from public.tools t
    where not t.is_archived and t.condition <> 'lost'
      and t.calibration_due <= v_today + 7 and t.calibration_notified_on is null
    for update skip locked
  loop
    perform public.fn_notify_permission(r.site_id, 'tools.issue', 'reminder',
      r.code || case when r.calibration_due < v_today then ' calibration is overdue'
        else ' calibration due ' || to_char(r.calibration_due, 'DD Mon') end,
      r.name, 'tool:' || r.id);
    update public.tools set calibration_notified_on = v_today where id = r.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- The daily report counts tools out by their open issue.
create or replace function public.fn_build_daily_report(p_site uuid, p_date date)
returns public.daily_reports
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.daily_reports;
  v_from timestamptz := (p_date::timestamp at time zone 'Africa/Harare');
  v_to timestamptz := ((p_date + 1)::timestamp at time zone 'Africa/Harare');
begin
  if auth.uid() is not null and not public._can('jobs.view', p_site) then
    raise exception 'NOT_ALLOWED: You do not work at this site';
  end if;
  if p_date > public._harare_today() then
    raise exception 'INVALID: That day has not happened yet';
  end if;
  v := public._report_for(p_site, p_date);
  if v.status = 'approved' then
    return v;
  end if;

  update public.daily_reports set built_at = now(), summary = jsonb_build_object(
    'jobs_opened', coalesce((
      select jsonb_agg(jsonb_build_object('id', j.id, 'code', j.number, 'title', j.title,
        'priority', j.priority, 'status', j.status) order by j.received_at)
      from public.job_cards j
      where j.site_id = p_site and not j.is_archived and j.received_at >= v_from and j.received_at < v_to
    ), '[]'::jsonb),
    'jobs_closed', coalesce((
      select jsonb_agg(jsonb_build_object('id', j.id, 'code', j.number, 'title', j.title,
        'by', p.full_name, 'note', j.completion_summary) order by j.closed_at)
      from public.job_cards j
      left join public.profiles p on p.id = coalesce(j.performed_by, j.responsible_id)
      where j.site_id = p_site and j.status = 'closed' and j.closed_at >= v_from and j.closed_at < v_to
    ), '[]'::jsonb),
    'jobs_open_now', (
      select count(*) from public.job_cards j
      where j.site_id = p_site and not j.is_archived and j.status not in ('closed', 'cancelled')
    ),
    'checklists_done', coalesce((
      select jsonb_agg(jsonb_build_object('name', t.name, 'by', p.full_name,
        'failed', r.failed_count, 'at', r.done_at) order by r.done_at)
      from public.checklist_runs r
      join public.checklist_templates t on t.id = r.template_id
      left join public.profiles p on p.id = r.done_by
      where r.site_id = p_site and r.run_date = p_date
    ), '[]'::jsonb),
    'checklists_missed', coalesce((
      select jsonb_agg(t.name order by t.name)
      from public.checklist_templates t
      where t.site_id = p_site and not t.is_archived
        and public._period_end(t.frequency, p_date) = p_date
        and not exists (
          select 1 from public.checklist_runs r
          where r.template_id = t.id and r.run_date >= public._period_start(t.frequency, p_date)
            and r.run_date <= p_date
        )
    ), '[]'::jsonb),
    'tools_issued', (
      select count(*) from public.tool_issues i join public.tools t on t.id = i.tool_id
      where t.site_id = p_site and i.issued_at >= v_from and i.issued_at < v_to
    ),
    'tools_returned', (
      select count(*) from public.tool_issues i join public.tools t on t.id = i.tool_id
      where t.site_id = p_site and i.returned_at >= v_from and i.returned_at < v_to
    ),
    'tools_out', (
      select count(*) from public.tools t
      where t.site_id = p_site and not t.is_archived
        and exists (select 1 from public.tool_issues i where i.tool_id = t.id and i.returned_at is null)
    )
  )
  where id = v.id
  returning * into v;
  return v;
end;
$$;

revoke execute on function
  public._tool_out(uuid),
  public._refresh_tool_form(uuid),
  public._take_tool_back(public.tools, text, text),
  public._open_tool_repair(public.tools, text, text),
  public.fn_add_tool_certificate(uuid, uuid, text, text, date, date),
  public.fn_issue_tools(uuid, uuid, jsonb, uuid, text, text, text, text, text, date, text, jsonb, uuid),
  public.fn_return_tools(uuid, jsonb, jsonb, text),
  public.fn_link_job_card_tool(uuid, uuid, boolean)
from public, anon, authenticated;

grant execute on function
  public.fn_issue_tools(uuid, uuid, jsonb, uuid, text, text, text, text, text, date, text, jsonb, uuid),
  public.fn_return_tools(uuid, jsonb, jsonb, text),
  public.fn_link_job_card_tool(uuid, uuid, boolean),
  public.fn_add_tool_certificate(uuid, uuid, text, text, date, date)
to authenticated;

-- Read with tools.view at the site; writes go through the functions.
alter table public.tool_issue_forms enable row level security;
create policy tool_issue_forms_select on public.tool_issue_forms for select to authenticated
  using (public._can('tools.view', site_id));
revoke all on public.tool_issue_forms from anon;
revoke insert, update, delete on public.tool_issue_forms from authenticated;

alter table public.job_card_tools enable row level security;
create policy job_card_tools_select on public.job_card_tools for select to authenticated
  using (exists (
    select 1 from public.job_cards j
    where j.id = job_card_tools.job_card_id and public._can('jc.view', j.site_id)
  ));
revoke all on public.job_card_tools from anon;
revoke insert, update, delete on public.job_card_tools from authenticated;

alter table public.tool_certificates enable row level security;
create policy tool_certificates_select on public.tool_certificates for select to authenticated
  using (exists (
    select 1 from public.tools t
    where t.id = tool_certificates.tool_id and public._can('tools.view', t.site_id)
  ));
revoke all on public.tool_certificates from anon;
revoke insert, update, delete on public.tool_certificates from authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.tool_issue_forms;
  end if;
end;
$$;

insert into public.schema_migrations (filename) values ('0026_tool_issue_forms.sql')
on conflict do nothing;
