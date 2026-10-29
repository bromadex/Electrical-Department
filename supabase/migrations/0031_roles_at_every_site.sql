-- 0031_roles_at_every_site: the department is one team, so every role
-- applies at every site (API.md section 2b). Each site-only role becomes
-- the same role at all sites (site_id null); the site-only rows are
-- archived, so the change shows in the activity log. New roles default
-- to All sites in Admin → Users.

create function public._roles_to_all_sites()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  insert into public.user_roles (user_id, role_id, site_id)
  select distinct user_id, role_id, null::uuid
  from public.user_roles
  where site_id is not null and not is_archived
  on conflict (user_id, role_id, site_id) do update set is_archived = false;

  update public.user_roles set is_archived = true
  where site_id is not null and not is_archived;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public._roles_to_all_sites() from public, anon, authenticated;

select public._roles_to_all_sites();

insert into public.schema_migrations (filename) values ('0031_roles_at_every_site.sql')
on conflict do nothing;
