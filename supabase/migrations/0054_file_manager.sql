-- 0054_file_manager: Documents as a file manager (API.md section 12c).
--
-- * Folders inside folders: document_folders.parent_id (null = the top of
--   the site's library). Names are unique among a folder's live children,
--   up to 8 levels deep. A folder moves with fn_move_folder, never into
--   itself or one of its own subfolders.
-- * Archiving a folder archives its subfolders too; their documents move
--   up to the archived folder's parent. Nothing is ever deleted.
-- * Starred documents: each person's own list (document_stars).

alter table public.document_folders
  add column parent_id uuid references public.document_folders (id);
create index document_folders_parent on public.document_folders (parent_id)
  where parent_id is not null;

drop index public.document_folders_name;
create unique index document_folders_name on public.document_folders (
  site_id, coalesce(parent_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(name)
) where not is_archived;

-- The folder and everything under it (ids), live or not.
create function public._folder_tree(p_folder uuid)
returns setof uuid
language sql
stable
set search_path = ''
as $$
  with recursive t as (
    select id from public.document_folders where id = p_folder
    union
    select f.id from public.document_folders f join t on f.parent_id = t.id
  )
  select id from t;
$$;

-- How deep a folder sits: 1 at the top.
create function public._folder_depth(p_folder uuid)
returns integer
language sql
stable
set search_path = ''
as $$
  with recursive up as (
    select id, parent_id, 1 as d from public.document_folders where id = p_folder
    union all
    select f.id, f.parent_id, up.d + 1 from public.document_folders f
    join up on f.id = up.parent_id
    where up.d < 50
  )
  select coalesce(max(d), 0) from up;
$$;

-- Creates (p_parent: where), renames or archives a folder (docs.manage).
drop function public.fn_save_folder(uuid, uuid, text, boolean);
create function public.fn_save_folder(
  p_client_ref uuid,
  p_site uuid,
  p_name text,
  p_archived boolean,
  p_parent uuid default null
)
returns public.document_folders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.document_folders;
  p public.document_folders;
  v_parent uuid;
begin
  if not public._can('docs.manage', p_site) then
    raise exception 'NOT_ALLOWED: Only a supervisor can manage folders';
  end if;
  if length(trim(coalesce(p_name, ''))) not between 2 and 60 then
    raise exception 'INVALID: The folder name needs 2 to 60 characters';
  end if;

  select * into v from public.document_folders where id = p_client_ref for update;
  -- New folders go where asked; existing ones stay where they are.
  v_parent := case when found then v.parent_id else p_parent end;
  if v.id is not null and v.site_id <> p_site then
    raise exception 'INVALID: Folder belongs to another site';
  end if;
  if v.id is null and v_parent is not null then
    select * into p from public.document_folders where id = v_parent and not is_archived;
    if not found or p.site_id <> p_site then
      raise exception 'INVALID: That folder is not at this site';
    end if;
    if public._folder_depth(v_parent) >= 8 then
      raise exception 'INVALID: Folders go up to 8 levels deep';
    end if;
  end if;
  if not coalesce(p_archived, false) and exists (
    select 1 from public.document_folders
    where site_id = p_site and not is_archived and id <> p_client_ref
      and lower(name) = lower(trim(p_name))
      and parent_id is not distinct from v_parent
  ) then
    raise exception 'CONFLICT: There is already a folder called % here', trim(p_name);
  end if;

  if v.id is not null then
    if coalesce(p_archived, false) and not v.is_archived then
      -- Its documents, and those of its subfolders, move up a level.
      update public.documents set folder_id = v.parent_id
      where folder_id in (select public._folder_tree(v.id));
      update public.document_folders set is_archived = true
      where id in (select public._folder_tree(v.id)) and id <> v.id;
    end if;
    update public.document_folders
    set name = trim(p_name), is_archived = coalesce(p_archived, false)
    where id = v.id
    returning * into v;
    return v;
  end if;

  insert into public.document_folders (id, site_id, name, parent_id)
  values (p_client_ref, p_site, trim(p_name), v_parent)
  returning * into v;
  return v;
end;
$$;

-- Moves a folder into another (or to the top with p_parent null).
create function public.fn_move_folder(p_folder uuid, p_parent uuid)
returns public.document_folders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.document_folders;
  p public.document_folders;
begin
  select * into v from public.document_folders where id = p_folder and not is_archived for update;
  if not found or not public._can('docs.view', v.site_id) then
    raise exception 'NOT_FOUND: Folder not found';
  end if;
  if not public._can('docs.manage', v.site_id) then
    raise exception 'NOT_ALLOWED: Only a supervisor can move folders';
  end if;
  if p_parent is not null then
    select * into p from public.document_folders where id = p_parent and not is_archived;
    if not found or p.site_id <> v.site_id then
      raise exception 'INVALID: That folder is not at this site';
    end if;
    if p_parent in (select public._folder_tree(v.id)) then
      raise exception 'INVALID: A folder cannot go inside itself';
    end if;
    -- Its own depth below it plus where it lands.
    if public._folder_depth(p_parent) + (
      select coalesce(max(public._folder_depth(t)) - public._folder_depth(v.id), 0) + 1
      from public._folder_tree(v.id) t
    ) > 8 then
      raise exception 'INVALID: Folders go up to 8 levels deep';
    end if;
  end if;
  if exists (
    select 1 from public.document_folders
    where site_id = v.site_id and not is_archived and id <> v.id
      and lower(name) = lower(v.name) and parent_id is not distinct from p_parent
  ) then
    raise exception 'CONFLICT: There is already a folder called % there', v.name;
  end if;
  update public.document_folders set parent_id = p_parent where id = v.id returning * into v;
  return v;
end;
$$;

-- Starred documents: each person's own.
create table public.document_stars (
  user_id uuid not null references public.profiles (id) default auth.uid(),
  document_id uuid not null references public.documents (id),
  created_at timestamptz not null default now(),
  primary key (user_id, document_id)
);
create index document_stars_document on public.document_stars (document_id);
alter table public.document_stars enable row level security;
create policy document_stars_select on public.document_stars for select to authenticated
  using (user_id = auth.uid());
revoke all on public.document_stars from anon;
revoke insert, update, delete on public.document_stars from authenticated;

create function public.fn_star_document(p_document uuid, p_starred boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_site uuid;
begin
  select site_id into v_site from public.documents where id = p_document;
  if not found or not public._can('docs.view', v_site) then
    raise exception 'NOT_FOUND: Document not found';
  end if;
  if coalesce(p_starred, false) then
    insert into public.document_stars (user_id, document_id) values (auth.uid(), p_document)
    on conflict do nothing;
  else
    delete from public.document_stars where user_id = auth.uid() and document_id = p_document;
  end if;
  return coalesce(p_starred, false);
end;
$$;

revoke execute on function public._folder_tree(uuid), public._folder_depth(uuid) from public, anon;
revoke execute on function
  public.fn_save_folder(uuid, uuid, text, boolean, uuid),
  public.fn_move_folder(uuid, uuid),
  public.fn_star_document(uuid, boolean)
from public, anon;
grant execute on function
  public.fn_save_folder(uuid, uuid, text, boolean, uuid),
  public.fn_move_folder(uuid, uuid),
  public.fn_star_document(uuid, boolean)
to authenticated;

insert into public.schema_migrations (filename) values ('0054_file_manager.sql')
on conflict do nothing;
