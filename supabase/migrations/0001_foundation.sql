-- 0001_foundation: sites, areas, profiles, roles/permissions, activity,
-- notifications, device tokens, record codes and storage buckets.
-- See API.md sections 1-4.

-- ---------------------------------------------------------------------------
-- Migration log (every migration ends by inserting its filename here)
-- ---------------------------------------------------------------------------
create table public.schema_migrations (
  filename text primary key,
  applied_at timestamptz not null default now()
);
alter table public.schema_migrations enable row level security;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table public.sites (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z]{2,5}$'),
  name text not null,
  is_archived boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.areas (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id),
  name text not null,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  unique (site_id, name)
);
create index areas_site_id_idx on public.areas (site_id);

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null default '',
  phone text,
  home_site_id uuid references public.sites (id),
  avatar_url text,
  active boolean not null default true,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  is_archived boolean not null default false
);

create table public.permissions (
  code text primary key,
  description text not null,
  is_archived boolean not null default false
);

create table public.role_permissions (
  role_id uuid not null references public.roles (id),
  permission_code text not null references public.permissions (code),
  is_archived boolean not null default false,
  primary key (role_id, permission_code)
);

create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id),
  role_id uuid not null references public.roles (id),
  site_id uuid references public.sites (id), -- null = all sites
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  unique nulls not distinct (user_id, role_id, site_id)
);
create index user_roles_user_id_idx on public.user_roles (user_id);

create table public.activity (
  id uuid primary key default gen_random_uuid(),
  at timestamptz not null default now(),
  user_id uuid references public.profiles (id),
  table_name text not null,
  record_id uuid not null,
  action text not null check (action in ('insert', 'update', 'archive', 'status')),
  details jsonb not null default '{}'::jsonb,
  is_archived boolean not null default false
);
create index activity_record_idx on public.activity (table_name, record_id);
create index activity_at_idx on public.activity (at desc);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id),
  site_id uuid references public.sites (id),
  type text not null check (type in (
    'assigned', 'mentioned', 'overdue', 'reminder',
    'approval', 'low_stock', 'meeting', 'general'
  )),
  title text not null,
  body text,
  link text,
  read_at timestamptz,
  is_archived boolean not null default false,
  created_at timestamptz not null default now()
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);

create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id),
  token text not null unique,
  platform text not null check (platform in ('android', 'web')),
  is_archived boolean not null default false,
  updated_at timestamptz not null default now()
);
create index device_tokens_user_idx on public.device_tokens (user_id);

create table public.code_counters (
  site_id uuid not null references public.sites (id),
  prefix text not null check (prefix in ('J', 'T', 'S', 'M', 'R', 'MR', 'I', 'PO', 'P')),
  last_no integer not null default 0,
  is_archived boolean not null default false,
  primary key (site_id, prefix)
);

-- ---------------------------------------------------------------------------
-- Permission helpers
-- ---------------------------------------------------------------------------

-- True when the signed-in user has an active, unarchived profile.
create function public._active()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.active and not p.is_archived
  );
$$;

-- True when the signed-in user is active and holds a role granting p_code at
-- p_site or at all sites. With p_site null only all-site roles count.
create function public._can(p_code text, p_site uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public._active() and exists (
    select 1
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id and not r.is_archived
    join public.role_permissions rp
      on rp.role_id = ur.role_id and not rp.is_archived
    join public.permissions pm
      on pm.code = rp.permission_code and not pm.is_archived
    where ur.user_id = auth.uid()
      and not ur.is_archived
      and rp.permission_code = p_code
      and (ur.site_id is null or ur.site_id = p_site)
  );
$$;

-- Every permission the signed-in user holds; site_id null = all sites.
create function public.my_permissions()
returns table (code text, site_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select distinct rp.permission_code, ur.site_id
  from public.user_roles ur
  join public.roles r on r.id = ur.role_id and not r.is_archived
  join public.role_permissions rp
    on rp.role_id = ur.role_id and not rp.is_archived
  join public.permissions pm
    on pm.code = rp.permission_code and not pm.is_archived
  where ur.user_id = auth.uid()
    and not ur.is_archived
    and public._active();
$$;

-- ---------------------------------------------------------------------------
-- Record codes: J-0001 style, per site, never reused
-- ---------------------------------------------------------------------------
create function public.next_code(p_site uuid, p_prefix text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_no integer;
begin
  insert into public.code_counters as c (site_id, prefix, last_no)
  values (p_site, p_prefix, 1)
  on conflict (site_id, prefix)
    do update set last_no = c.last_no + 1
  returning c.last_no into v_no;

  return p_prefix || '-' || lpad(v_no::text, 4, '0');
end;
$$;

-- ---------------------------------------------------------------------------
-- Notifications
-- ---------------------------------------------------------------------------
create function public.fn_notify(
  p_user uuid,
  p_site uuid,
  p_type text,
  p_title text,
  p_body text,
  p_link text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  insert into public.notifications (user_id, site_id, type, title, body, link)
  values (p_user, p_site, p_type, p_title, p_body, p_link)
  returning id into v_id;
  return v_id;
end;
$$;

-- Notifies every active user holding p_code at p_site (or at all sites).
create function public.fn_notify_permission(
  p_site uuid,
  p_code text,
  p_type text,
  p_title text,
  p_body text,
  p_link text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  insert into public.notifications (user_id, site_id, type, title, body, link)
  select distinct ur.user_id, p_site, p_type, p_title, p_body, p_link
  from public.user_roles ur
  join public.profiles p
    on p.id = ur.user_id and p.active and not p.is_archived
  join public.roles r on r.id = ur.role_id and not r.is_archived
  join public.role_permissions rp
    on rp.role_id = ur.role_id and not rp.is_archived
  where not ur.is_archived
    and rp.permission_code = p_code
    and (ur.site_id is null or ur.site_id = p_site);

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Marks the caller's notifications read; p_ids null = all unread.
create function public.fn_mark_read(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not public._active() then
    raise exception 'NOT_ALLOWED: Your account is not active';
  end if;

  update public.notifications n
  set read_at = now()
  where n.user_id = auth.uid()
    and n.read_at is null
    and (p_ids is null or n.id = any (p_ids));

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create function public.fn_register_device(p_token text, p_platform text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public._active() then
    raise exception 'NOT_ALLOWED: Your account is not active';
  end if;
  if p_platform not in ('android', 'web') then
    raise exception 'INVALID: Unknown platform %', p_platform;
  end if;

  insert into public.device_tokens (user_id, token, platform)
  values (auth.uid(), p_token, p_platform)
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        is_archived = false,
        updated_at = now();
end;
$$;

-- ---------------------------------------------------------------------------
-- Function privileges: internal helpers are not callable from the app
-- ---------------------------------------------------------------------------
revoke execute on function
  public._active(),
  public._can(text, uuid),
  public.my_permissions(),
  public.next_code(uuid, text),
  public.fn_notify(uuid, uuid, text, text, text, text),
  public.fn_notify_permission(uuid, text, text, text, text, text),
  public.fn_mark_read(uuid[]),
  public.fn_register_device(text, text)
from public, anon, authenticated;

-- RLS policies call these as the signed-in user.
grant execute on function public._active(), public._can(text, uuid) to authenticated;

-- Called by the app.
grant execute on function
  public.my_permissions(),
  public.fn_mark_read(uuid[]),
  public.fn_register_device(text, text)
to authenticated;

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

-- New auth user -> profile.
create function public.fn_handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.raw_user_meta_data ->> 'phone'
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.fn_handle_new_user();

-- Keeps updated_at current.
create function public.fn_touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_touch
  before update on public.profiles
  for each row execute function public.fn_touch_updated_at();

-- Only admin.users may change who is active or archived.
create function public.fn_profiles_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (new.active is distinct from old.active
      or new.is_archived is distinct from old.is_archived)
     and auth.uid() is not null
     and not public._can('admin.users', null) then
    raise exception 'NOT_ALLOWED: Only an admin can activate or archive users';
  end if;
  return new;
end;
$$;

create trigger profiles_guard
  before update on public.profiles
  for each row execute function public.fn_profiles_guard();

-- Activity log: one row per insert/update on tables with a uuid id.
create function public.fn_log_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_new jsonb := to_jsonb(new);
  v_old jsonb;
  v_action text;
  v_details jsonb;
begin
  if tg_op = 'INSERT' then
    v_action := 'insert';
    v_details := v_new;
  else
    v_old := to_jsonb(old);
    select coalesce(jsonb_object_agg(n.key, jsonb_build_object('from', v_old -> n.key, 'to', n.value)), '{}'::jsonb)
      into v_details
    from jsonb_each(v_new) n
    where n.key not in ('updated_at')
      and (v_old -> n.key) is distinct from n.value;

    if v_details = '{}'::jsonb then
      return new;
    elsif v_details ? 'is_archived' and (v_new ->> 'is_archived')::boolean then
      v_action := 'archive';
    elsif v_details ? 'status' then
      v_action := 'status';
    else
      v_action := 'update';
    end if;
  end if;

  insert into public.activity (user_id, table_name, record_id, action, details)
  values (auth.uid(), tg_table_name, (v_new ->> 'id')::uuid, v_action, v_details);
  return new;
end;
$$;

create trigger sites_activity after insert or update on public.sites
  for each row execute function public.fn_log_activity();
create trigger areas_activity after insert or update on public.areas
  for each row execute function public.fn_log_activity();
create trigger profiles_activity after insert or update on public.profiles
  for each row execute function public.fn_log_activity();
create trigger roles_activity after insert or update on public.roles
  for each row execute function public.fn_log_activity();
create trigger user_roles_activity after insert or update on public.user_roles
  for each row execute function public.fn_log_activity();

revoke execute on function
  public.fn_handle_new_user(),
  public.fn_log_activity()
from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Row level security (no DELETE policies anywhere: archive instead)
-- ---------------------------------------------------------------------------
alter table public.sites enable row level security;
alter table public.areas enable row level security;
alter table public.profiles enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.user_roles enable row level security;
alter table public.activity enable row level security;
alter table public.notifications enable row level security;
alter table public.device_tokens enable row level security;
alter table public.code_counters enable row level security;

-- sites / areas: read by any active user; write with admin.sites
create policy sites_select on public.sites for select to authenticated
  using (public._active());
create policy sites_insert on public.sites for insert to authenticated
  with check (public._can('admin.sites', null));
create policy sites_update on public.sites for update to authenticated
  using (public._can('admin.sites', id))
  with check (public._can('admin.sites', id));

create policy areas_select on public.areas for select to authenticated
  using (public._active());
create policy areas_insert on public.areas for insert to authenticated
  with check (public._can('admin.sites', site_id));
create policy areas_update on public.areas for update to authenticated
  using (public._can('admin.sites', site_id))
  with check (public._can('admin.sites', site_id));

-- profiles: read by any active user; self edits name/phone/avatar/home site,
-- admin.users edits anything (rows are created by the sign-up trigger)
create policy profiles_select on public.profiles for select to authenticated
  using (public._active());
create policy profiles_update on public.profiles for update to authenticated
  using ((id = auth.uid() and public._active()) or public._can('admin.users', null))
  with check ((id = auth.uid() and public._active()) or public._can('admin.users', null));

-- roles & permissions: own roles, or admin.users
create policy roles_select on public.roles for select to authenticated
  using (
    public._can('admin.users', null)
    or exists (
      select 1 from public.user_roles ur
      where ur.role_id = roles.id and ur.user_id = auth.uid() and not ur.is_archived
    )
  );
create policy roles_insert on public.roles for insert to authenticated
  with check (public._can('admin.users', null));
create policy roles_update on public.roles for update to authenticated
  using (public._can('admin.users', null))
  with check (public._can('admin.users', null));

create policy permissions_select on public.permissions for select to authenticated
  using (public._can('admin.users', null));

create policy role_permissions_select on public.role_permissions for select to authenticated
  using (public._can('admin.users', null));
create policy role_permissions_insert on public.role_permissions for insert to authenticated
  with check (public._can('admin.users', null));
create policy role_permissions_update on public.role_permissions for update to authenticated
  using (public._can('admin.users', null))
  with check (public._can('admin.users', null));

create policy user_roles_select on public.user_roles for select to authenticated
  using (user_id = auth.uid() or public._can('admin.users', null));
create policy user_roles_insert on public.user_roles for insert to authenticated
  with check (public._can('admin.users', null));
create policy user_roles_update on public.user_roles for update to authenticated
  using (public._can('admin.users', null))
  with check (public._can('admin.users', null));

-- activity: stats.view (all sites); written by triggers only
create policy activity_select on public.activity for select to authenticated
  using (public._can('stats.view', null));

-- notifications: own rows; the app may only set read_at
create policy notifications_select on public.notifications for select to authenticated
  using (user_id = auth.uid() and public._active());
create policy notifications_update on public.notifications for update to authenticated
  using (user_id = auth.uid() and public._active())
  with check (user_id = auth.uid());
revoke update on public.notifications from authenticated;
grant update (read_at) on public.notifications to authenticated;

-- device_tokens: own rows
create policy device_tokens_select on public.device_tokens for select to authenticated
  using (user_id = auth.uid());
create policy device_tokens_insert on public.device_tokens for insert to authenticated
  with check (user_id = auth.uid() and public._active());
create policy device_tokens_update on public.device_tokens for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Nothing is reachable by signed-out visitors.
revoke all on
  public.schema_migrations, public.sites, public.areas, public.profiles,
  public.roles, public.permissions, public.role_permissions, public.user_roles,
  public.activity, public.notifications, public.device_tokens, public.code_counters
from anon;

-- ---------------------------------------------------------------------------
-- Realtime: new notifications
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.notifications;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Storage: private buckets, path = <site_id>/<kind>/<record_id>/<file>
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values
  ('job-photos', 'job-photos', false),
  ('chat-files', 'chat-files', false),
  ('documents', 'documents', false),
  ('meeting-audio', 'meeting-audio', false)
on conflict (id) do nothing;

-- Site id from the first folder of an object path, or null.
create function public._path_site(p_name text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case
    when split_part(p_name, '/', 1)
      ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      then split_part(p_name, '/', 1)::uuid
  end;
$$;

create policy job_photos_select on storage.objects for select to authenticated
  using (bucket_id = 'job-photos' and public._can('jobs.view', public._path_site(name)));
create policy job_photos_insert on storage.objects for insert to authenticated
  with check (
    bucket_id = 'job-photos'
    and (public._can('jobs.create', public._path_site(name))
         or public._can('jobs.close', public._path_site(name)))
  );

create policy documents_select on storage.objects for select to authenticated
  using (bucket_id = 'documents' and public._can('docs.view', public._path_site(name)));
create policy documents_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'documents' and public._can('docs.manage', public._path_site(name)));

-- chat-files and meeting-audio policies arrive with group chat (section 10)
-- and meetings (section 16), which define conversation members and attendees.

-- ---------------------------------------------------------------------------
-- Reference data
-- ---------------------------------------------------------------------------
insert into public.sites (code, name) values
  ('KAM', 'Kamativi'),
  ('SEL', 'Selous'),
  ('MAN', 'Manhizi'),
  ('HRE', 'Harare');

insert into public.permissions (code, description) values
  ('jobs.view', 'See jobs at the site'),
  ('jobs.create', 'Log new jobs'),
  ('jobs.assign', 'Assign jobs to technicians'),
  ('jobs.close', 'Close completed jobs'),
  ('chat.use', 'Take part in group chats'),
  ('chat.manage', 'Create and manage chat groups'),
  ('tools.view', 'See the tools register'),
  ('tools.issue', 'Issue and receive tools'),
  ('docs.view', 'Read SOPs and documents'),
  ('docs.manage', 'Upload and manage documents'),
  ('checklists.manage', 'Set up daily checklists'),
  ('reports.approve', 'Approve daily reports'),
  ('store.view', 'See electrical store stock'),
  ('store.issue', 'Issue store items'),
  ('store.receive', 'Receive store items'),
  ('store.adjust', 'Adjust store stock'),
  ('mr.create', 'Raise material requests'),
  ('mr.approve', 'Approve material requests'),
  ('po.manage', 'Manage purchase orders'),
  ('projects.manage', 'Manage projects, calendar and roster'),
  ('meetings.manage', 'Schedule meetings and publish minutes'),
  ('stats.view', 'See statistics and the activity log'),
  ('admin.users', 'Manage users and their roles'),
  ('admin.sites', 'Manage sites and areas');

insert into public.roles (name) values
  ('Technician'), ('Storekeeper'), ('Supervisor'), ('Admin');

insert into public.role_permissions (role_id, permission_code)
select r.id, x.code
from (values
  ('Technician', 'jobs.view'), ('Technician', 'jobs.create'), ('Technician', 'jobs.close'),
  ('Technician', 'chat.use'), ('Technician', 'tools.view'), ('Technician', 'docs.view'),
  ('Technician', 'store.view'), ('Technician', 'mr.create'),

  ('Storekeeper', 'jobs.view'), ('Storekeeper', 'chat.use'), ('Storekeeper', 'tools.view'),
  ('Storekeeper', 'tools.issue'), ('Storekeeper', 'docs.view'), ('Storekeeper', 'store.view'),
  ('Storekeeper', 'store.issue'), ('Storekeeper', 'store.receive'), ('Storekeeper', 'store.adjust'),
  ('Storekeeper', 'mr.create'), ('Storekeeper', 'po.manage'),

  ('Supervisor', 'jobs.view'), ('Supervisor', 'jobs.create'), ('Supervisor', 'jobs.assign'),
  ('Supervisor', 'jobs.close'), ('Supervisor', 'chat.use'), ('Supervisor', 'chat.manage'),
  ('Supervisor', 'tools.view'), ('Supervisor', 'tools.issue'), ('Supervisor', 'docs.view'),
  ('Supervisor', 'docs.manage'), ('Supervisor', 'checklists.manage'), ('Supervisor', 'reports.approve'),
  ('Supervisor', 'store.view'), ('Supervisor', 'mr.create'), ('Supervisor', 'mr.approve'),
  ('Supervisor', 'projects.manage'), ('Supervisor', 'meetings.manage'), ('Supervisor', 'stats.view')
) as x (role_name, code)
join public.roles r on r.name = x.role_name;

insert into public.role_permissions (role_id, permission_code)
select r.id, p.code
from public.roles r
cross join public.permissions p
where r.name = 'Admin';

insert into public.schema_migrations (filename) values ('0001_foundation.sql')
on conflict do nothing;
