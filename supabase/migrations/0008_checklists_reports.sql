-- 0008_checklists_reports: daily checklists and the daily report
-- (API.md section 13).
--
-- Checklists: supervisors build templates (generator round, DB board
-- inspection) with items to tick, readings with limits, notes and
-- required photos. A round is submitted in one go; every failed item
-- raises a job. Rounds still due late in the day remind the person, then
-- tell supervisors they were missed.
--
-- Daily report (R-): one per site per day, summarising jobs, checklists
-- and tools, plus each person's update with photos. A supervisor approves
-- it. Photos use the job-photos bucket under <site_id>/checklist/... and
-- <site_id>/report/...

create table public.checklist_templates (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id),
  area_id uuid references public.areas (id),
  name text not null check (length(trim(name)) between 3 and 120),
  description text check (length(description) <= 1000),
  frequency text not null default 'daily' check (frequency in ('daily', 'weekly', 'monthly')),
  assignee_id uuid references public.profiles (id),
  created_by uuid references public.profiles (id) default auth.uid(),
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.checklist_items (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.checklist_templates (id),
  position integer not null,
  label text not null check (length(trim(label)) between 2 and 200),
  kind text not null default 'check' check (kind in ('check', 'number', 'text')),
  unit text check (length(unit) <= 20),
  min_value numeric,
  max_value numeric,
  photo_required boolean not null default false,
  is_archived boolean not null default false
);
create index checklist_items_template on public.checklist_items (template_id, position);

create table public.checklist_runs (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.checklist_templates (id),
  site_id uuid not null references public.sites (id),
  run_date date not null,
  done_by uuid references public.profiles (id) default auth.uid(),
  done_at timestamptz not null default now(),
  notes text check (length(notes) <= 2000),
  failed_count integer not null default 0
);
create index checklist_runs_template on public.checklist_runs (template_id, run_date desc);
create index checklist_runs_site_date on public.checklist_runs (site_id, run_date);

create table public.checklist_answers (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.checklist_runs (id),
  item_id uuid not null references public.checklist_items (id),
  ok boolean,
  value numeric,
  text_value text check (length(text_value) <= 1000),
  photo_path text,
  comment text check (length(comment) <= 1000),
  failed boolean not null default false,
  job_id uuid references public.jobs (id),
  unique (run_id, item_id)
);

-- Reminders sent per template per period, so each goes out once.
create table public.checklist_alerts (
  template_id uuid not null references public.checklist_templates (id),
  period_start date not null,
  stage text not null check (stage in ('reminder', 'missed')),
  sent_at timestamptz not null default now(),
  primary key (template_id, period_start, stage)
);

create table public.daily_reports (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id),
  report_date date not null,
  code text not null,
  summary jsonb not null default '{}'::jsonb,
  built_at timestamptz,
  status text not null default 'open' check (status in ('open', 'approved')),
  supervisor_comment text check (length(supervisor_comment) <= 2000),
  approved_by uuid references public.profiles (id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (site_id, report_date)
);

create table public.report_updates (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.daily_reports (id),
  user_id uuid not null references public.profiles (id) default auth.uid(),
  body text not null check (length(trim(body)) between 1 and 4000),
  photo_paths text[] not null default '{}',
  created_at timestamptz not null default now(),
  is_archived boolean not null default false
);
create index report_updates_report on public.report_updates (report_id, created_at);

create trigger checklist_templates_touch before update on public.checklist_templates
  for each row execute function public.fn_touch_updated_at();
create trigger daily_reports_touch before update on public.daily_reports
  for each row execute function public.fn_touch_updated_at();
create trigger checklist_templates_activity after insert or update on public.checklist_templates
  for each row execute function public.fn_log_activity();
create trigger daily_reports_activity after insert or update on public.daily_reports
  for each row execute function public.fn_log_activity();

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create function public._harare_today()
returns date
language sql
stable
set search_path = ''
as $$
  select (now() at time zone 'Africa/Harare')::date;
$$;

-- First day of the period a date falls in.
create function public._period_start(p_frequency text, p_date date)
returns date
language sql
immutable
set search_path = ''
as $$
  select case p_frequency
    when 'weekly' then date_trunc('week', p_date)::date
    when 'monthly' then date_trunc('month', p_date)::date
    else p_date
  end;
$$;

-- Last day of that period.
create function public._period_end(p_frequency text, p_date date)
returns date
language sql
immutable
set search_path = ''
as $$
  select case p_frequency
    when 'weekly' then (date_trunc('week', p_date) + interval '6 days')::date
    when 'monthly' then (date_trunc('month', p_date) + interval '1 month - 1 day')::date
    else p_date
  end;
$$;

-- ---------------------------------------------------------------------------
-- Checklists
-- ---------------------------------------------------------------------------
-- Create or edit a template and its items in one call. p_items:
-- [{"id": uuid|null, "label", "kind", "unit", "min", "max", "photo_required"}]
-- in order. Items left out are archived, so old answers keep their item.
create function public.fn_save_checklist_template(
  p_client_ref uuid,
  p_site uuid,
  p_area uuid,
  p_name text,
  p_description text,
  p_frequency text,
  p_assignee uuid,
  p_items jsonb,
  p_archived boolean
)
returns public.checklist_templates
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.checklist_templates;
  x jsonb;
  i integer := 0;
  v_ids uuid[] := '{}';
  v_id uuid;
begin
  if not public._can('checklists.manage', p_site) then
    raise exception 'NOT_ALLOWED: Only a supervisor can manage checklists';
  end if;
  if length(trim(coalesce(p_name, ''))) not between 3 and 120 then
    raise exception 'INVALID: The name needs 3 to 120 characters';
  end if;
  if coalesce(p_frequency, 'daily') not in ('daily', 'weekly', 'monthly') then
    raise exception 'INVALID: Unknown frequency';
  end if;
  if p_area is not null and not exists (
    select 1 from public.areas where id = p_area and site_id = p_site and not is_archived
  ) then
    raise exception 'INVALID: That area is not at this site';
  end if;
  if p_assignee is not null and not public._user_can(p_assignee, 'jobs.close', p_site) then
    raise exception 'INVALID: That person cannot do rounds at this site';
  end if;
  if not coalesce(p_archived, false)
     and jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 then
    raise exception 'INVALID: Add at least one item';
  end if;

  insert into public.checklist_templates as t (
    id, site_id, area_id, name, description, frequency, assignee_id, is_archived
  ) values (
    p_client_ref, p_site, p_area, trim(p_name), nullif(trim(coalesce(p_description, '')), ''),
    coalesce(p_frequency, 'daily'), p_assignee, coalesce(p_archived, false)
  )
  on conflict (id) do update set
    area_id = excluded.area_id, name = excluded.name, description = excluded.description,
    frequency = excluded.frequency, assignee_id = excluded.assignee_id,
    is_archived = excluded.is_archived
  where t.site_id = excluded.site_id
  returning * into v;
  if v.id is null then
    raise exception 'INVALID: Checklist belongs to another site';
  end if;

  for x in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    i := i + 1;
    if length(trim(coalesce(x ->> 'label', ''))) < 2 then
      raise exception 'INVALID: Item % needs a label', i;
    end if;
    if coalesce(x ->> 'kind', 'check') not in ('check', 'number', 'text') then
      raise exception 'INVALID: Item % has an unknown kind', i;
    end if;
    v_id := coalesce(nullif(x ->> 'id', '')::uuid, gen_random_uuid());
    insert into public.checklist_items as it (
      id, template_id, position, label, kind, unit, min_value, max_value, photo_required, is_archived
    ) values (
      v_id, v.id, i, trim(x ->> 'label'), coalesce(x ->> 'kind', 'check'),
      nullif(trim(coalesce(x ->> 'unit', '')), ''), (x ->> 'min')::numeric, (x ->> 'max')::numeric,
      coalesce((x ->> 'photo_required')::boolean, false), false
    )
    on conflict (id) do update set
      position = excluded.position, label = excluded.label, kind = excluded.kind,
      unit = excluded.unit, min_value = excluded.min_value, max_value = excluded.max_value,
      photo_required = excluded.photo_required, is_archived = false
    where it.template_id = excluded.template_id;
    v_ids := v_ids || v_id;
  end loop;

  update public.checklist_items set is_archived = true
  where template_id = v.id and not (id = any (v_ids));
  return v;
end;
$$;

-- Submit a finished round. p_answers: [{"item_id", "ok", "value",
-- "text", "photo_path", "comment"}]. Failed ticks and readings outside
-- their limits each raise a job at the site.
create function public.fn_submit_checklist(
  p_client_ref uuid,
  p_template uuid,
  p_answers jsonb,
  p_notes text
)
returns public.checklist_runs
language plpgsql
security definer
set search_path = ''
as $$
declare
  t public.checklist_templates;
  r public.checklist_runs;
  it public.checklist_items;
  a jsonb;
  v_failed boolean;
  v_value numeric;
  v_job public.jobs;
  v_count integer := 0;
begin
  select * into r from public.checklist_runs where id = p_client_ref;
  if found then
    return r;
  end if;
  select * into t from public.checklist_templates where id = p_template and not is_archived;
  if not found or not public._can('jobs.view', t.site_id) then
    raise exception 'NOT_FOUND: Checklist not found';
  end if;
  if not public._can('jobs.close', t.site_id) then
    raise exception 'NOT_ALLOWED: You cannot do rounds at this site';
  end if;

  insert into public.checklist_runs (id, template_id, site_id, run_date, notes)
  values (p_client_ref, t.id, t.site_id, public._harare_today(), nullif(trim(coalesce(p_notes, '')), ''))
  returning * into r;

  for it in
    select * from public.checklist_items where template_id = t.id and not is_archived order by position
  loop
    a := (
      select x from jsonb_array_elements(coalesce(p_answers, '[]'::jsonb)) x
      where x ->> 'item_id' = it.id::text limit 1
    );
    if a is null then
      raise exception 'INVALID: Answer "%"', it.label;
    end if;
    if it.photo_required and coalesce(a ->> 'photo_path', '') = '' then
      raise exception 'INVALID: "%" needs a photo', it.label;
    end if;
    v_value := null;
    if it.kind = 'check' then
      if a -> 'ok' is null or jsonb_typeof(a -> 'ok') <> 'boolean' then
        raise exception 'INVALID: Mark "%" as OK or not', it.label;
      end if;
      v_failed := not (a ->> 'ok')::boolean;
    elsif it.kind = 'number' then
      begin
        v_value := (a ->> 'value')::numeric;
      exception when others then
        v_value := null;
      end;
      if v_value is null then
        raise exception 'INVALID: Enter the reading for "%"', it.label;
      end if;
      v_failed := (it.min_value is not null and v_value < it.min_value)
               or (it.max_value is not null and v_value > it.max_value);
    else
      if length(trim(coalesce(a ->> 'text', ''))) = 0 then
        raise exception 'INVALID: Fill in "%"', it.label;
      end if;
      v_failed := false;
    end if;

    v_job := null;
    if v_failed then
      v_count := v_count + 1;
      v_job := public.fn_create_job(
        gen_random_uuid(), t.site_id, t.area_id,
        left(t.name || ': ' || it.label, 120),
        concat_ws(E'\n',
          'Failed on the ' || t.name || ' round.',
          case when v_value is not null then 'Reading: ' || v_value || coalesce(' ' || it.unit, '')
            || coalesce(' (limits ' || coalesce(it.min_value::text, '…') || '–'
            || coalesce(it.max_value::text, '…') || ')', '') end,
          nullif(trim(coalesce(a ->> 'comment', '')), '')),
        'normal', null, null, null);
    end if;

    insert into public.checklist_answers (
      run_id, item_id, ok, value, text_value, photo_path, comment, failed, job_id
    ) values (
      r.id, it.id, case when it.kind = 'check' then (a ->> 'ok')::boolean end, v_value,
      nullif(trim(coalesce(a ->> 'text', '')), ''), nullif(a ->> 'photo_path', ''),
      nullif(trim(coalesce(a ->> 'comment', '')), ''), v_failed, v_job.id
    );
  end loop;

  update public.checklist_runs set failed_count = v_count where id = r.id returning * into r;
  return r;
end;
$$;

-- Checklists at a site with their state this period, for the Today tab.
create function public.fn_site_checklists(p_site uuid)
returns table (
  id uuid,
  name text,
  frequency text,
  area_id uuid,
  assignee_id uuid,
  due_by date,
  done_at timestamptz,
  done_by uuid,
  failed_count integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_today date := public._harare_today();
begin
  if not public._can('jobs.view', p_site) then
    raise exception 'NOT_ALLOWED: You do not work at this site';
  end if;
  return query
  select t.id, t.name, t.frequency, t.area_id, t.assignee_id,
    public._period_end(t.frequency, v_today),
    last.done_at, last.done_by, last.failed_count
  from public.checklist_templates t
  left join lateral (
    select r.done_at, r.done_by, r.failed_count
    from public.checklist_runs r
    where r.template_id = t.id and r.run_date >= public._period_start(t.frequency, v_today)
    order by r.done_at desc limit 1
  ) last on true
  where t.site_id = p_site and not t.is_archived
  order by last.done_at nulls first, t.name;
end;
$$;

-- pg_cron, afternoon and evening Harare time: rounds whose period ends
-- today and are not done remind the assignee (stage reminder), then tell
-- supervisors they were missed (stage missed). Each once per period.
create function public.fn_checklist_alerts(p_stage text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := public._harare_today();
  t public.checklist_templates;
  v_start date;
  v_count integer := 0;
begin
  for t in
    select * from public.checklist_templates
    where not is_archived and public._period_end(frequency, v_today) = v_today
  loop
    v_start := public._period_start(t.frequency, v_today);
    continue when exists (
      select 1 from public.checklist_runs where template_id = t.id and run_date >= v_start
    );
    insert into public.checklist_alerts (template_id, period_start, stage)
    values (t.id, v_start, p_stage)
    on conflict do nothing;
    continue when not found;
    if p_stage = 'reminder' then
      if t.assignee_id is not null then
        perform public.fn_notify(t.assignee_id, t.site_id, 'reminder',
          t.name || ' is due today', 'Do the round before the end of the day.', 'checklist:' || t.id);
      else
        perform public.fn_notify_permission(t.site_id, 'jobs.close', 'reminder',
          t.name || ' is due today', 'Nobody has done this round yet.', 'checklist:' || t.id);
      end if;
    else
      perform public.fn_notify_permission(t.site_id, 'checklists.manage', 'overdue',
        t.name || ' was missed', 'No round was submitted for ' || to_char(v_today, 'DD Mon') || '.',
        'checklist:' || t.id);
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- Daily report
-- ---------------------------------------------------------------------------
create function public._report_for(p_site uuid, p_date date)
returns public.daily_reports
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.daily_reports;
begin
  select * into v from public.daily_reports where site_id = p_site and report_date = p_date;
  if not found then
    insert into public.daily_reports (site_id, report_date, code)
    values (p_site, p_date, public.next_code(p_site, 'R'))
    on conflict (site_id, report_date) do nothing
    returning * into v;
    if v.id is null then
      select * into v from public.daily_reports where site_id = p_site and report_date = p_date;
    end if;
  end if;
  return v;
end;
$$;

-- Builds (or rebuilds) the summary of a day at a site. Approved reports
-- keep the summary they were approved with.
create function public.fn_build_daily_report(p_site uuid, p_date date)
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
      select jsonb_agg(jsonb_build_object('id', j.id, 'code', j.code, 'title', j.title,
        'priority', j.priority, 'status', j.status) order by j.created_at)
      from public.jobs j
      where j.site_id = p_site and not j.is_archived and j.created_at >= v_from and j.created_at < v_to
    ), '[]'::jsonb),
    'jobs_closed', coalesce((
      select jsonb_agg(jsonb_build_object('id', j.id, 'code', j.code, 'title', j.title,
        'by', p.full_name, 'note', j.close_note) order by j.closed_at)
      from public.jobs j
      left join public.profiles p on p.id = j.closed_by
      where j.site_id = p_site and j.status = 'done' and j.closed_at >= v_from and j.closed_at < v_to
    ), '[]'::jsonb),
    'jobs_open_now', (
      select count(*) from public.jobs j
      where j.site_id = p_site and not j.is_archived and j.status not in ('done', 'cancelled')
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
      where t.site_id = p_site and not t.is_archived and t.holder_id is not null
    )
  )
  where id = v.id
  returning * into v;
  return v;
end;
$$;

-- "Today's update" from one person, with photo paths already uploaded.
create function public.fn_add_report_update(
  p_client_ref uuid,
  p_site uuid,
  p_date date,
  p_body text,
  p_photo_paths text[]
)
returns public.report_updates
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.daily_reports;
  u public.report_updates;
begin
  select * into u from public.report_updates where id = p_client_ref;
  if found then
    return u;
  end if;
  if not public._can('jobs.view', p_site) then
    raise exception 'NOT_ALLOWED: You do not work at this site';
  end if;
  if length(trim(coalesce(p_body, ''))) = 0 then
    raise exception 'INVALID: Write what you did today';
  end if;
  if p_date > public._harare_today() or p_date < public._harare_today() - 7 then
    raise exception 'INVALID: Updates are for today or the past week';
  end if;
  v := public._report_for(p_site, p_date);
  if v.status = 'approved' then
    raise exception 'CONFLICT: % is already approved', v.code;
  end if;
  insert into public.report_updates (id, report_id, body, photo_paths)
  values (p_client_ref, v.id, trim(p_body), coalesce(p_photo_paths, '{}'))
  returning * into u;
  return u;
end;
$$;

create function public.fn_approve_report(p_report uuid, p_comment text)
returns public.daily_reports
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.daily_reports;
begin
  select * into v from public.daily_reports where id = p_report for update;
  if not found or not public._can('jobs.view', v.site_id) then
    raise exception 'NOT_FOUND: Report not found';
  end if;
  if not public._can('reports.approve', v.site_id) then
    raise exception 'NOT_ALLOWED: Only a supervisor can approve reports';
  end if;
  if v.status = 'approved' then
    return v;
  end if;
  v := public.fn_build_daily_report(v.site_id, v.report_date);
  update public.daily_reports set
    status = 'approved', approved_by = auth.uid(), approved_at = now(),
    supervisor_comment = nullif(trim(coalesce(p_comment, '')), '')
  where id = v.id
  returning * into v;
  return v;
end;
$$;

-- Evening (pg_cron): build today's report at every site.
create function public.fn_build_all_reports()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  s record;
  v_count integer := 0;
begin
  for s in select id from public.sites where not is_archived loop
    perform public.fn_build_daily_report(s.id, public._harare_today());
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke execute on function
  public._harare_today(),
  public._period_start(text, date),
  public._period_end(text, date),
  public._report_for(uuid, date),
  public.fn_save_checklist_template(uuid, uuid, uuid, text, text, text, uuid, jsonb, boolean),
  public.fn_submit_checklist(uuid, uuid, jsonb, text),
  public.fn_site_checklists(uuid),
  public.fn_checklist_alerts(text),
  public.fn_build_daily_report(uuid, date),
  public.fn_add_report_update(uuid, uuid, date, text, text[]),
  public.fn_approve_report(uuid, text),
  public.fn_build_all_reports()
from public, anon, authenticated;

grant execute on function
  public._harare_today(),
  public.fn_save_checklist_template(uuid, uuid, uuid, text, text, text, uuid, jsonb, boolean),
  public.fn_submit_checklist(uuid, uuid, jsonb, text),
  public.fn_site_checklists(uuid),
  public.fn_build_daily_report(uuid, date),
  public.fn_add_report_update(uuid, uuid, date, text, text[]),
  public.fn_approve_report(uuid, text)
to authenticated;

-- ---------------------------------------------------------------------------
-- RLS: read with jobs.view at the site; writes go through the functions
-- ---------------------------------------------------------------------------
alter table public.checklist_templates enable row level security;
alter table public.checklist_items enable row level security;
alter table public.checklist_runs enable row level security;
alter table public.checklist_answers enable row level security;
alter table public.checklist_alerts enable row level security;
alter table public.daily_reports enable row level security;
alter table public.report_updates enable row level security;

create policy checklist_templates_select on public.checklist_templates for select to authenticated
  using (public._can('jobs.view', site_id));
create policy checklist_items_select on public.checklist_items for select to authenticated
  using (exists (
    select 1 from public.checklist_templates t
    where t.id = checklist_items.template_id and public._can('jobs.view', t.site_id)
  ));
create policy checklist_runs_select on public.checklist_runs for select to authenticated
  using (public._can('jobs.view', site_id));
create policy checklist_answers_select on public.checklist_answers for select to authenticated
  using (exists (
    select 1 from public.checklist_runs r
    where r.id = checklist_answers.run_id and public._can('jobs.view', r.site_id)
  ));
create policy daily_reports_select on public.daily_reports for select to authenticated
  using (public._can('jobs.view', site_id));
create policy report_updates_select on public.report_updates for select to authenticated
  using (exists (
    select 1 from public.daily_reports d
    where d.id = report_updates.report_id and public._can('jobs.view', d.site_id)
  ));

revoke all on public.checklist_templates, public.checklist_items, public.checklist_runs,
  public.checklist_answers, public.checklist_alerts, public.daily_reports, public.report_updates
from anon;
revoke insert, update, delete on public.checklist_templates, public.checklist_items,
  public.checklist_runs, public.checklist_answers, public.checklist_alerts, public.daily_reports,
  public.report_updates
from authenticated;
revoke select on public.checklist_alerts from authenticated;

-- Harare is UTC+2: 13:00 UTC = 15:00 reminder, 17:00 UTC = 19:00 missed and
-- the day's report.
select cron.schedule('checklists-reminder', '0 13 * * *', $$select public.fn_checklist_alerts('reminder')$$);
select cron.schedule('checklists-missed', '0 17 * * *', $$select public.fn_checklist_alerts('missed')$$);
select cron.schedule('daily-reports', '10 17 * * *', 'select public.fn_build_all_reports()');

insert into public.schema_migrations (filename) values ('0008_checklists_reports.sql')
on conflict do nothing;
