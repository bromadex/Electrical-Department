-- 0004_users: user management for system administrators (API.md section 9).
--
-- Sign-ins are created and passwords reset by the admin-users edge function
-- (it needs the service role key). Everything else goes through these
-- functions, which need admin.users at all sites.

-- Everyone, with email, last sign-in and roles, for the users screen.
create function public.fn_admin_users()
returns table (
  id uuid,
  email text,
  full_name text,
  phone text,
  home_site_id uuid,
  active boolean,
  last_sign_in_at timestamptz,
  created_at timestamptz,
  roles jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public._can('admin.users', null) then
    raise exception 'NOT_ALLOWED: Only a system administrator can manage users';
  end if;
  return query
  select
    p.id,
    u.email::text,
    p.full_name,
    p.phone,
    p.home_site_id,
    p.active,
    u.last_sign_in_at,
    p.created_at,
    coalesce((
      select jsonb_agg(jsonb_build_object('role', r.name, 'site_id', ur.site_id) order by r.name)
      from public.user_roles ur
      join public.roles r on r.id = ur.role_id
      where ur.user_id = p.id and not ur.is_archived
    ), '[]'::jsonb)
  from public.profiles p
  join auth.users u on u.id = p.id
  where not p.is_archived
  order by p.active desc, lower(p.full_name);
end;
$$;

-- Name, phone, home site and whether the person can sign in.
create function public.fn_set_user_profile(
  p_user uuid,
  p_full_name text,
  p_phone text,
  p_home_site uuid,
  p_active boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public._can('admin.users', null) then
    raise exception 'NOT_ALLOWED: Only a system administrator can manage users';
  end if;
  if length(trim(coalesce(p_full_name, ''))) < 2 then
    raise exception 'INVALID: Enter the person''s name';
  end if;
  if p_user = auth.uid() and not p_active then
    raise exception 'INVALID: You cannot switch off your own account';
  end if;
  if p_home_site is not null
     and not exists (select 1 from public.sites where id = p_home_site and not is_archived) then
    raise exception 'NOT_FOUND: Site not found';
  end if;
  update public.profiles
  set full_name = trim(p_full_name),
      phone = nullif(trim(coalesce(p_phone, '')), ''),
      home_site_id = p_home_site,
      active = coalesce(p_active, active)
  where id = p_user and not is_archived;
  if not found then
    raise exception 'NOT_FOUND: User not found';
  end if;
end;
$$;

-- Replaces all of a person's roles. p_roles: [{"role": "Technician",
-- "site_id": "<uuid>" | null}] where a null site means all sites.
create function public.fn_set_user_roles(p_user uuid, p_roles jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_wanted record;
  v_role uuid;
  v_roles uuid[] := '{}';
  v_sites uuid[] := '{}';
begin
  if not public._can('admin.users', null) then
    raise exception 'NOT_ALLOWED: Only a system administrator can manage users';
  end if;
  if not exists (select 1 from public.profiles where id = p_user and not is_archived) then
    raise exception 'NOT_FOUND: User not found';
  end if;
  if jsonb_typeof(coalesce(p_roles, '[]'::jsonb)) <> 'array' then
    raise exception 'INVALID: Roles must be a list';
  end if;

  for v_wanted in
    select x ->> 'role' as role, nullif(x ->> 'site_id', '')::uuid as site_id
    from jsonb_array_elements(coalesce(p_roles, '[]'::jsonb)) x
  loop
    v_role := (select id from public.roles where name = v_wanted.role and not is_archived);
    if v_role is null then
      raise exception 'INVALID: Unknown role %', v_wanted.role;
    end if;
    if v_wanted.site_id is not null
       and not exists (select 1 from public.sites where id = v_wanted.site_id and not is_archived) then
      raise exception 'NOT_FOUND: Site not found';
    end if;
    v_roles := v_roles || v_role;
    v_sites := v_sites || v_wanted.site_id;
  end loop;

  update public.user_roles ur
  set is_archived = not exists (
    select 1 from unnest(v_roles, v_sites) w (role_id, site_id)
    where w.role_id = ur.role_id and w.site_id is not distinct from ur.site_id
  )
  where ur.user_id = p_user;

  insert into public.user_roles (user_id, role_id, site_id)
  select distinct p_user, w.role_id, w.site_id
  from unnest(v_roles, v_sites) w (role_id, site_id)
  on conflict (user_id, role_id, site_id) do update set is_archived = false;

  -- Nobody can lock the department out of user management.
  if p_user = auth.uid() and not public._can('admin.users', null) then
    raise exception 'INVALID: You cannot remove your own admin rights';
  end if;
end;
$$;

revoke execute on function
  public.fn_admin_users(),
  public.fn_set_user_profile(uuid, text, text, uuid, boolean),
  public.fn_set_user_roles(uuid, jsonb)
from public, anon;

grant execute on function
  public.fn_admin_users(),
  public.fn_set_user_profile(uuid, text, text, uuid, boolean),
  public.fn_set_user_roles(uuid, jsonb)
to authenticated;

insert into public.schema_migrations (filename) values ('0004_users.sql')
on conflict do nothing;
