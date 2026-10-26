-- 0021_settings: the Settings page's writes go through functions.
-- fn_update_my_profile: your own name, phone and home site.
-- fn_save_site / fn_save_area: add, rename or archive sites and areas
-- (admin.sites). A new site gets its default chat from the 0011 trigger.

create function public.fn_update_my_profile(p_full_name text, p_phone text, p_home_site uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public._active() then
    raise exception 'NOT_ALLOWED: Sign in first';
  end if;
  if length(trim(coalesce(p_full_name, ''))) < 2 then
    raise exception 'INVALID: Enter your name';
  end if;
  if length(coalesce(p_phone, '')) > 30 then
    raise exception 'INVALID: That phone number is too long';
  end if;
  if p_home_site is not null
     and not exists (select 1 from public.sites where id = p_home_site and not is_archived) then
    raise exception 'NOT_FOUND: Site not found';
  end if;
  update public.profiles
  set full_name = trim(p_full_name),
      phone = nullif(trim(coalesce(p_phone, '')), ''),
      home_site_id = p_home_site
  where id = auth.uid();
end;
$$;

-- p_id null adds a site. Codes are 2–5 capital letters and unique.
create function public.fn_save_site(p_id uuid, p_code text, p_name text, p_archived boolean)
returns public.sites
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text := upper(trim(coalesce(p_code, '')));
  s public.sites;
begin
  if not public._can('admin.sites', p_id) then
    raise exception 'NOT_ALLOWED: Only an administrator can change sites';
  end if;
  if v_code !~ '^[A-Z]{2,5}$' then
    raise exception 'INVALID: The site code is 2 to 5 letters, e.g. KAM';
  end if;
  if length(trim(coalesce(p_name, ''))) < 2 then
    raise exception 'INVALID: Enter the site''s name';
  end if;
  if exists (select 1 from public.sites where code = v_code and id is distinct from p_id) then
    raise exception 'INVALID: Another site already uses %', v_code;
  end if;
  if p_id is null then
    insert into public.sites (code, name) values (v_code, trim(p_name)) returning * into s;
  else
    update public.sites
    set code = v_code, name = trim(p_name), is_archived = coalesce(p_archived, is_archived)
    where id = p_id
    returning * into s;
    if not found then
      raise exception 'NOT_FOUND: Site not found';
    end if;
  end if;
  return s;
end;
$$;

-- p_id null adds an area at p_site. Names are unique within a site.
create function public.fn_save_area(p_id uuid, p_site uuid, p_name text, p_archived boolean)
returns public.areas
language plpgsql
security definer
set search_path = ''
as $$
declare
  a public.areas;
  v_site uuid := p_site;
begin
  if p_id is not null then
    select site_id into v_site from public.areas where id = p_id;
    if not found then
      raise exception 'NOT_FOUND: Area not found';
    end if;
  end if;
  if v_site is null or not exists (select 1 from public.sites where id = v_site) then
    raise exception 'NOT_FOUND: Site not found';
  end if;
  if not public._can('admin.sites', v_site) then
    raise exception 'NOT_ALLOWED: Only an administrator can change areas';
  end if;
  if length(trim(coalesce(p_name, ''))) < 2 then
    raise exception 'INVALID: Enter the area''s name';
  end if;
  if exists (select 1 from public.areas
             where site_id = v_site and lower(name) = lower(trim(p_name)) and id is distinct from p_id) then
    raise exception 'INVALID: This site already has an area called %', trim(p_name);
  end if;
  if p_id is null then
    insert into public.areas (site_id, name) values (v_site, trim(p_name)) returning * into a;
  else
    update public.areas
    set name = trim(p_name), is_archived = coalesce(p_archived, is_archived)
    where id = p_id
    returning * into a;
  end if;
  return a;
end;
$$;

revoke execute on function
  public.fn_update_my_profile(text, text, uuid),
  public.fn_save_site(uuid, text, text, boolean),
  public.fn_save_area(uuid, uuid, text, boolean)
from public, anon;
grant execute on function
  public.fn_update_my_profile(text, text, uuid),
  public.fn_save_site(uuid, text, text, boolean),
  public.fn_save_area(uuid, uuid, text, boolean)
to authenticated;
