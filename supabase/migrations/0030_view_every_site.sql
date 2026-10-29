-- 0030_view_every_site: everyone can see every site (API.md section 2b).
-- Permissions marked every_site (the .view ones) count at all sites for
-- anyone who holds them at one. Work stays at your own sites: changing a
-- job card, adding to a daily report or signing an SOP needs a role at
-- that site. Notifications still go only to people at the site.

alter table public.permissions
  add column every_site boolean not null default false;

update public.permissions set every_site = true
where code in (
  'jc.view', 'jobs.view', 'tools.view', 'docs.view', 'store.view',
  'assets.view', 'reports.view', 'stats.view'
);

-- The signed-in user has a role at the site (or at all sites).
create function public._works_at(p_site uuid)
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
    where ur.user_id = auth.uid()
      and not ur.is_archived
      and (ur.site_id is null or ur.site_id = p_site)
  );
$$;

create or replace function public._can(p_code text, p_site uuid)
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
      and (ur.site_id is null or ur.site_id = p_site or pm.every_site)
  );
$$;

-- Every-site permissions come back with site_id null (all sites); the
-- extra code 'site.member' lists the sites the user works at.
create or replace function public.my_permissions()
returns table (code text, site_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select distinct rp.permission_code, case when pm.every_site then null else ur.site_id end
  from public.user_roles ur
  join public.roles r on r.id = ur.role_id and not r.is_archived
  join public.role_permissions rp
    on rp.role_id = ur.role_id and not rp.is_archived
  join public.permissions pm
    on pm.code = rp.permission_code and not pm.is_archived
  where ur.user_id = auth.uid()
    and not ur.is_archived
    and public._active()
  union
  select distinct 'site.member', ur.site_id
  from public.user_roles ur
  join public.roles r on r.id = ur.role_id and not r.is_archived
  where ur.user_id = auth.uid()
    and not ur.is_archived
    and public._active();
$$;

-- Job card writes: seeing a site's job cards is not enough to change them.
create or replace function public._jc_for_write(p_job uuid)
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
  if not (
    public._works_at(v.site_id)
    or public._jc_is_requester(v)
    or coalesce(v.responsible_id = auth.uid(), false)
    or exists (
      select 1 from public.job_assignments a
      where a.job_card_id = v.id and a.user_id = auth.uid() and a.ended_at is null
    )
  ) then
    raise exception 'NOT_ALLOWED: You can view this site''s job cards but work only at your own sites';
  end if;
  return v;
end;
$$;

-- The old jobs board (read-only in the app) gets the same rule.
create or replace function public._job_for_write(p_job uuid)
returns public.jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.jobs;
begin
  select * into v from public.jobs where id = p_job and not is_archived for update;
  if not found or not public._can('jobs.view', v.site_id) then
    raise exception 'NOT_FOUND: Job not found';
  end if;
  if not public._works_at(v.site_id) then
    raise exception 'NOT_ALLOWED: You can view this site''s jobs but work only at your own sites';
  end if;
  return v;
end;
$$;

-- Daily report updates and SOP signatures: only from people at the site.
create function public._site_member_only()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_site uuid;
begin
  if auth.uid() is null then
    return new;
  end if;
  if tg_table_name = 'report_updates' then
    select site_id into v_site from public.daily_reports where id = new.report_id;
  else
    select site_id into v_site from public.documents where id = new.document_id;
  end if;
  if v_site is not null and not public._works_at(v_site) then
    raise exception 'NOT_ALLOWED: You can view this site but work only at your own sites';
  end if;
  return new;
end;
$$;

create trigger report_updates_site_member before insert on public.report_updates
  for each row execute function public._site_member_only();
create trigger document_acks_site_member before insert on public.document_acks
  for each row execute function public._site_member_only();

revoke execute on function public._works_at(uuid), public._site_member_only() from public, anon;
grant execute on function public._works_at(uuid) to authenticated;

insert into public.schema_migrations (filename) values ('0030_view_every_site.sql')
on conflict do nothing;
