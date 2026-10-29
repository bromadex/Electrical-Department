-- 0029_document_folders: folders in each site's document library (API.md
-- section 12b). A document sits in one folder or in none; archiving a
-- folder moves its documents out, it never removes them.

create table public.document_folders (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id),
  name text not null check (length(trim(name)) between 2 and 60),
  created_by uuid references public.profiles (id) default auth.uid(),
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index document_folders_name on public.document_folders (site_id, lower(name))
  where not is_archived;

create trigger document_folders_touch before update on public.document_folders
  for each row execute function public.fn_touch_updated_at();

alter table public.documents
  add column folder_id uuid references public.document_folders (id);
create index documents_folder on public.documents (folder_id) where folder_id is not null;

-- Creates, renames or archives a folder (docs.manage).
create function public.fn_save_folder(
  p_client_ref uuid,
  p_site uuid,
  p_name text,
  p_archived boolean
)
returns public.document_folders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.document_folders;
begin
  if not public._can('docs.manage', p_site) then
    raise exception 'NOT_ALLOWED: Only a supervisor can manage folders';
  end if;
  if length(trim(coalesce(p_name, ''))) not between 2 and 60 then
    raise exception 'INVALID: The folder name needs 2 to 60 characters';
  end if;
  if not coalesce(p_archived, false) and exists (
    select 1 from public.document_folders
    where site_id = p_site and lower(name) = lower(trim(p_name)) and not is_archived
      and id <> p_client_ref
  ) then
    raise exception 'CONFLICT: There is already a folder called %', trim(p_name);
  end if;

  select * into v from public.document_folders where id = p_client_ref for update;
  if found then
    if v.site_id <> p_site then
      raise exception 'INVALID: Folder belongs to another site';
    end if;
    update public.document_folders
    set name = trim(p_name), is_archived = coalesce(p_archived, false)
    where id = v.id
    returning * into v;
    if v.is_archived then
      update public.documents set folder_id = null where folder_id = v.id;
    end if;
    return v;
  end if;

  insert into public.document_folders (id, site_id, name)
  values (p_client_ref, p_site, trim(p_name))
  returning * into v;
  return v;
end;
$$;

-- Moves documents into a folder, or out of folders with p_folder null.
create function public.fn_move_documents(p_documents uuid[], p_folder uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  f public.document_folders;
  v_site uuid;
  v_count integer;
begin
  select distinct site_id into v_site from public.documents
  where id = any (coalesce(p_documents, '{}')) and not is_archived;
  if v_site is null then
    return 0;
  end if;
  if (select count(distinct site_id) from public.documents where id = any (p_documents)) > 1 then
    raise exception 'INVALID: The documents are at different sites';
  end if;
  if not public._can('docs.manage', v_site) then
    raise exception 'NOT_ALLOWED: Only a supervisor can move documents';
  end if;
  if p_folder is not null then
    select * into f from public.document_folders where id = p_folder and not is_archived;
    if not found or f.site_id <> v_site then
      raise exception 'INVALID: That folder is not at this site';
    end if;
  end if;
  update public.documents set folder_id = p_folder
  where id = any (p_documents) and not is_archived;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function
  public.fn_save_folder(uuid, uuid, text, boolean),
  public.fn_move_documents(uuid[], uuid)
from public, anon;
grant execute on function
  public.fn_save_folder(uuid, uuid, text, boolean),
  public.fn_move_documents(uuid[], uuid)
to authenticated;

alter table public.document_folders enable row level security;
create policy document_folders_select on public.document_folders for select to authenticated
  using (public._can('docs.view', site_id));
revoke all on public.document_folders from anon;
revoke insert, update, delete on public.document_folders from authenticated;

insert into public.schema_migrations (filename) values ('0029_document_folders.sql')
on conflict do nothing;
