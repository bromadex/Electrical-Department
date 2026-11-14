-- 0040_permission_hardening: findings of the permission audit (issue #35).
--
-- 1. fn_send_standby_reminders is run by the scheduler only, but Supabase
--    grants every new function to signed-in users by default and 0034 only
--    revoked it from public and anon: anyone signed in could send
--    tomorrow's standby reminders early. Revoked.
-- 2. Defence in depth: nobody signed out (anon) holds any right on the
--    public tables, and signed-in users hold insert, update or delete only
--    where a row-level policy allows that command (everything else already
--    goes through fn_* functions; row-level security refused it anyway).
--    Test 0040 keeps it so for tables added later.
-- 3. Nobody can lock the department out of administration: the Admin role
--    keeps admin.users, and the last active admin cannot lose the role or
--    be deactivated.

revoke execute on function public.fn_send_standby_reminders() from authenticated;

do $$
declare
  t record;
  c text;
begin
  for t in
    select c.relname, c.relkind
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'v', 'm', 'p')
  loop
    execute format('revoke all on public.%I from anon', t.relname);
    foreach c in array array['INSERT', 'UPDATE', 'DELETE'] loop
      if t.relkind <> 'r' or not exists (
        select 1 from pg_policies p
        where p.schemaname = 'public' and p.tablename = t.relname
          and p.cmd in (c, 'ALL') and 'authenticated' = any (p.roles)
      ) then
        execute format('revoke %s on public.%I from authenticated', c, t.relname);
      end if;
    end loop;
  end loop;
end;
$$;

-- An active admin: an active, unarchived profile with an unarchived Admin role.
create function public._other_admin_exists(p_except_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id and r.name = 'Admin'
    join public.profiles p on p.id = ur.user_id
    where not ur.is_archived and p.active and not p.is_archived
      and ur.user_id is distinct from p_except_user
  );
$$;

create function public._guard_admin_role()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_was_admin boolean;
begin
  select r.name = 'Admin' and not old.is_archived into v_was_admin
  from public.roles r where r.id = old.role_id;
  if coalesce(v_was_admin, false)
     and (tg_op = 'DELETE' or new.is_archived or new.role_id <> old.role_id)
     and not public._other_admin_exists(old.user_id)
     and not exists (
       select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id and r.name = 'Admin'
       where ur.user_id = old.user_id and ur.id <> old.id and not ur.is_archived
     ) then
    raise exception 'INVALID: Keep at least one admin, or nobody can manage people';
  end if;
  return coalesce(new, old);
end;
$$;

create trigger user_roles_keep_admin
  before update or delete on public.user_roles
  for each row execute function public._guard_admin_role();

create function public._guard_admin_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (old.active and not old.is_archived) and (not new.active or new.is_archived)
     and exists (
       select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id and r.name = 'Admin'
       where ur.user_id = old.id and not ur.is_archived
     )
     and not public._other_admin_exists(old.id) then
    raise exception 'INVALID: This is the last admin; make someone else admin first';
  end if;
  return new;
end;
$$;

create trigger profiles_keep_admin
  before update of active, is_archived on public.profiles
  for each row execute function public._guard_admin_profile();

create function public._guard_admin_permission()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.permission_code = 'admin.users'
     and exists (select 1 from public.roles r where r.id = old.role_id and r.name = 'Admin')
     and (tg_op = 'DELETE' or new.is_archived or new.permission_code <> old.permission_code) then
    raise exception 'INVALID: Admin keeps admin.users, or nobody could manage people';
  end if;
  return coalesce(new, old);
end;
$$;

create trigger role_permissions_keep_admin
  before update or delete on public.role_permissions
  for each row execute function public._guard_admin_permission();

revoke execute on function
  public._other_admin_exists(uuid),
  public._guard_admin_role(),
  public._guard_admin_profile(),
  public._guard_admin_permission()
from public, anon, authenticated;

insert into public.schema_migrations (filename) values ('0040_permission_hardening.sql')
on conflict do nothing;
