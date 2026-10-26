-- 0006_tools: tools register (API.md section 11).
--
-- Who holds which tool, when it is due back and when its calibration or
-- test is due. Storekeepers and supervisors (tools.issue) keep the register
-- and issue tools; the person receiving a tool signs on the screen.
-- The monthly count is a tick list: each tool seen gets last_counted_at.

create table public.tools (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id),
  code text not null,
  name text not null check (length(trim(name)) between 2 and 120),
  kind text check (length(kind) <= 40),
  serial_no text check (length(serial_no) <= 80),
  condition text not null default 'good'
    check (condition in ('good', 'needs_repair', 'damaged', 'lost')),
  calibration_due date,
  calibration_notified_on date,
  notes text check (length(notes) <= 2000),
  photo_path text,
  holder_id uuid references public.profiles (id),
  issued_at timestamptz,
  due_back date,
  last_counted_at timestamptz,
  created_by uuid references public.profiles (id) default auth.uid(),
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (site_id, code)
);
create index tools_site on public.tools (site_id) where not is_archived;
create index tools_holder on public.tools (holder_id) where holder_id is not null;

-- One row per time a tool goes out; closed when it comes back.
create table public.tool_issues (
  id uuid primary key default gen_random_uuid(),
  tool_id uuid not null references public.tools (id),
  issued_to uuid not null references public.profiles (id),
  issued_by uuid references public.profiles (id) default auth.uid(),
  issued_at timestamptz not null default now(),
  due_back date,
  signature_path text,
  returned_at timestamptz,
  returned_by uuid references public.profiles (id),
  return_condition text check (return_condition in ('good', 'needs_repair', 'damaged', 'lost')),
  return_note text,
  overdue_notified_at timestamptz,
  is_archived boolean not null default false
);
create index tool_issues_tool on public.tool_issues (tool_id, issued_at desc);
create unique index tool_issues_open on public.tool_issues (tool_id) where returned_at is null;

create trigger tools_touch before update on public.tools
  for each row execute function public.fn_touch_updated_at();
create trigger tools_activity after insert or update on public.tools
  for each row execute function public.fn_log_activity();

-- ---------------------------------------------------------------------------
-- Functions
-- ---------------------------------------------------------------------------
create function public._tool_for_write(p_tool uuid)
returns public.tools
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.tools;
begin
  select * into v from public.tools where id = p_tool and not is_archived for update;
  if not found or not public._can('tools.view', v.site_id) then
    raise exception 'NOT_FOUND: Tool not found';
  end if;
  if not public._can('tools.issue', v.site_id) then
    raise exception 'NOT_ALLOWED: Only the store or a supervisor can do this';
  end if;
  return v;
end;
$$;

-- Add or edit a tool. A new tool gets the next T- code at its site.
create function public.fn_save_tool(
  p_client_ref uuid,
  p_site uuid,
  p_name text,
  p_kind text,
  p_serial_no text,
  p_calibration_due date,
  p_notes text,
  p_condition text,
  p_archived boolean,
  p_photo_path text default null
)
returns public.tools
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.tools;
begin
  if not public._can('tools.issue', p_site) then
    raise exception 'NOT_ALLOWED: Only the store or a supervisor can change the tools register';
  end if;
  if length(trim(coalesce(p_name, ''))) not between 2 and 120 then
    raise exception 'INVALID: The name needs 2 to 120 characters';
  end if;
  if coalesce(p_condition, 'good') not in ('good', 'needs_repair', 'damaged', 'lost') then
    raise exception 'INVALID: Unknown condition';
  end if;

  select * into v from public.tools where id = p_client_ref for update;
  if found then
    if v.site_id <> p_site then
      raise exception 'INVALID: Tool belongs to another site';
    end if;
    if coalesce(p_archived, false) and v.holder_id is not null then
      raise exception 'CONFLICT: % is out with someone; take it back first', v.code;
    end if;
    update public.tools set
      name = trim(p_name),
      kind = nullif(trim(coalesce(p_kind, '')), ''),
      serial_no = nullif(trim(coalesce(p_serial_no, '')), ''),
      calibration_due = p_calibration_due,
      calibration_notified_on = case when p_calibration_due is distinct from calibration_due
        then null else calibration_notified_on end,
      notes = nullif(trim(coalesce(p_notes, '')), ''),
      condition = coalesce(p_condition, condition),
      photo_path = coalesce(p_photo_path, photo_path),
      is_archived = coalesce(p_archived, false)
    where id = v.id
    returning * into v;
    return v;
  end if;

  insert into public.tools (
    id, site_id, code, name, kind, serial_no, calibration_due, notes, condition, photo_path
  ) values (
    p_client_ref, p_site, public.next_code(p_site, 'T'), trim(p_name),
    nullif(trim(coalesce(p_kind, '')), ''), nullif(trim(coalesce(p_serial_no, '')), ''),
    p_calibration_due, nullif(trim(coalesce(p_notes, '')), ''), coalesce(p_condition, 'good'),
    p_photo_path
  )
  returning * into v;
  return v;
end;
$$;

-- Hand a tool to someone. They sign on the screen; the signature image is
-- uploaded first to tool-files at p_signature_path.
create function public.fn_issue_tool(
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
  if v.holder_id is not null then
    raise exception 'CONFLICT: % is already out', v.code;
  end if;
  if v.condition in ('damaged', 'lost') then
    raise exception 'INVALID: % is marked %; it cannot be issued', v.code, v.condition;
  end if;
  if not public._user_can(p_to, 'tools.view', v.site_id) then
    raise exception 'INVALID: That person does not work at this site';
  end if;
  if p_due_back is not null and p_due_back < (now() at time zone 'Africa/Harare')::date then
    raise exception 'INVALID: The return date is in the past';
  end if;

  insert into public.tool_issues (id, tool_id, issued_to, due_back, signature_path)
  values (p_client_ref, v.id, p_to, p_due_back, p_signature_path);
  update public.tools
  set holder_id = p_to, issued_at = now(), due_back = p_due_back
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

-- Take a tool back in, with its condition. A lost tool stays on the register
-- marked lost.
create function public.fn_return_tool(p_tool uuid, p_condition text, p_note text)
returns public.tools
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.tools := public._tool_for_write(p_tool);
begin
  if v.holder_id is null then
    return v;
  end if;
  if coalesce(p_condition, '') not in ('good', 'needs_repair', 'damaged', 'lost') then
    raise exception 'INVALID: Say what condition it came back in';
  end if;
  if p_condition <> 'good' and length(trim(coalesce(p_note, ''))) = 0 then
    raise exception 'INVALID: Say what is wrong with it';
  end if;
  update public.tool_issues set
    returned_at = now(), returned_by = auth.uid(),
    return_condition = p_condition, return_note = nullif(trim(coalesce(p_note, '')), '')
  where tool_id = v.id and returned_at is null;
  update public.tools set
    holder_id = null, issued_at = null, due_back = null, condition = p_condition
  where id = v.id
  returning * into v;
  if p_condition <> 'good' then
    perform public.fn_notify_permission(v.site_id, 'jobs.assign', 'general',
      v.code || ' came back ' || replace(p_condition, '_', ' '), p_note, 'tool:' || v.id);
  end if;
  return v;
end;
$$;

-- Monthly count: mark the tools seen on the shelf (or confirmed with
-- their holder) as counted now.
create function public.fn_count_tools(p_site uuid, p_tools uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not public._can('tools.issue', p_site) then
    raise exception 'NOT_ALLOWED: Only the store or a supervisor can count tools';
  end if;
  update public.tools set last_counted_at = now()
  where site_id = p_site and id = any (coalesce(p_tools, '{}')) and not is_archived;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Daily (pg_cron): overdue returns and calibration due within a week.
create function public.fn_notify_tools()
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
    select i.id, i.issued_to, t.id as tool_id, t.site_id, t.code, t.name
    from public.tool_issues i
    join public.tools t on t.id = i.tool_id
    where i.returned_at is null and i.due_back < v_today and i.overdue_notified_at is null
      and not t.is_archived
    for update of i skip locked
  loop
    perform public.fn_notify(r.issued_to, r.site_id, 'overdue',
      r.code || ' is overdue for return', r.name, 'tool:' || r.tool_id);
    perform public.fn_notify_permission(r.site_id, 'tools.issue', 'overdue',
      r.code || ' is overdue for return', r.name, 'tool:' || r.tool_id);
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

-- People who hold p_code at p_site, for pickers (issue a tool to…). Any
-- active person working at the site may ask.
create function public.fn_site_people(p_site uuid, p_code text)
returns table (id uuid, full_name text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.my_permissions() m where m.site_id is null or m.site_id = p_site
  ) then
    raise exception 'NOT_ALLOWED: You do not work at this site';
  end if;
  return query
  select p.id, p.full_name
  from public.profiles p
  where p.active and not p.is_archived and public._user_can(p.id, p_code, p_site)
  order by lower(p.full_name);
end;
$$;

revoke execute on function
  public.fn_site_people(uuid, text),
  public._tool_for_write(uuid),
  public.fn_save_tool(uuid, uuid, text, text, text, date, text, text, boolean, text),
  public.fn_issue_tool(uuid, uuid, uuid, date, text),
  public.fn_return_tool(uuid, text, text),
  public.fn_count_tools(uuid, uuid[]),
  public.fn_notify_tools()
from public, anon, authenticated;

grant execute on function
  public.fn_site_people(uuid, text),
  public.fn_save_tool(uuid, uuid, text, text, text, date, text, text, boolean, text),
  public.fn_issue_tool(uuid, uuid, uuid, date, text),
  public.fn_return_tool(uuid, text, text),
  public.fn_count_tools(uuid, uuid[])
to authenticated;

-- ---------------------------------------------------------------------------
-- RLS: read with tools.view at the site; writes go through the functions
-- ---------------------------------------------------------------------------
alter table public.tools enable row level security;
alter table public.tool_issues enable row level security;

create policy tools_select on public.tools for select to authenticated
  using (public._can('tools.view', site_id));
create policy tool_issues_select on public.tool_issues for select to authenticated
  using (exists (
    select 1 from public.tools t
    where t.id = tool_issues.tool_id and public._can('tools.view', t.site_id)
  ));

revoke all on public.tools, public.tool_issues from anon;
revoke insert, update, delete on public.tools, public.tool_issues from authenticated;

-- Photos and signatures: <site_id>/tool/<tool_id>/<file>
insert into storage.buckets (id, name, public)
values ('tool-files', 'tool-files', false)
on conflict (id) do nothing;

create policy tool_files_select on storage.objects for select to authenticated
  using (bucket_id = 'tool-files' and public._can('tools.view', public._path_site(name)));
create policy tool_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'tool-files' and public._can('tools.issue', public._path_site(name)));

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.tools;
  end if;
end;
$$;

-- 05:15 UTC = 07:15 Harare
select cron.schedule('tools-reminders', '15 5 * * *', 'select public.fn_notify_tools()');

insert into public.schema_migrations (filename) values ('0006_tools.sql')
on conflict do nothing;
