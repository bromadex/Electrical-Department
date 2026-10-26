-- 0007_documents: SOPs and documents (API.md section 12).
--
-- Documents live per site under a category (SOP, drawing, manual, form,
-- other). Each upload is a version; the document shows the latest. SOPs can
-- need acknowledgement: everyone at the site confirms they have read the
-- current version, and a new version asks them again. Documents can be
-- linked to jobs (e.g. the LOTO SOP on a switching job).

create table public.documents (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id),
  code text not null,
  title text not null check (length(trim(title)) between 3 and 160),
  category text not null default 'sop'
    check (category in ('sop', 'drawing', 'manual', 'form', 'other')),
  needs_ack boolean not null default false,
  current_version integer not null default 0,
  created_by uuid references public.profiles (id) default auth.uid(),
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (site_id, code)
);
create index documents_site on public.documents (site_id) where not is_archived;

create table public.document_versions (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.documents (id),
  version integer not null,
  path text not null,
  file_name text not null,
  mime_type text,
  size_bytes bigint,
  note text check (length(note) <= 500),
  created_by uuid references public.profiles (id) default auth.uid(),
  created_at timestamptz not null default now(),
  unique (document_id, version)
);

create table public.document_acks (
  document_id uuid not null references public.documents (id),
  version integer not null,
  user_id uuid not null references public.profiles (id),
  acked_at timestamptz not null default now(),
  primary key (document_id, version, user_id)
);

create table public.job_documents (
  job_id uuid not null references public.jobs (id),
  document_id uuid not null references public.documents (id),
  linked_by uuid references public.profiles (id) default auth.uid(),
  linked_at timestamptz not null default now(),
  primary key (job_id, document_id)
);

create trigger documents_touch before update on public.documents
  for each row execute function public.fn_touch_updated_at();
create trigger documents_activity after insert or update on public.documents
  for each row execute function public.fn_log_activity();

-- ---------------------------------------------------------------------------
-- Functions
-- ---------------------------------------------------------------------------
create function public.fn_save_document(
  p_client_ref uuid,
  p_site uuid,
  p_title text,
  p_category text,
  p_needs_ack boolean,
  p_archived boolean
)
returns public.documents
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.documents;
begin
  if not public._can('docs.manage', p_site) then
    raise exception 'NOT_ALLOWED: Only a supervisor can manage documents';
  end if;
  if length(trim(coalesce(p_title, ''))) not between 3 and 160 then
    raise exception 'INVALID: The title needs 3 to 160 characters';
  end if;
  if coalesce(p_category, 'sop') not in ('sop', 'drawing', 'manual', 'form', 'other') then
    raise exception 'INVALID: Unknown category';
  end if;

  select * into v from public.documents where id = p_client_ref for update;
  if found then
    if v.site_id <> p_site then
      raise exception 'INVALID: Document belongs to another site';
    end if;
    update public.documents set
      title = trim(p_title), category = coalesce(p_category, category),
      needs_ack = coalesce(p_needs_ack, needs_ack), is_archived = coalesce(p_archived, false)
    where id = v.id
    returning * into v;
    return v;
  end if;

  insert into public.documents (id, site_id, code, title, category, needs_ack)
  values (p_client_ref, p_site, public.next_code(p_site, 'S'), trim(p_title),
    coalesce(p_category, 'sop'), coalesce(p_needs_ack, false))
  returning * into v;
  return v;
end;
$$;

-- A new file for a document; it becomes the current version. The file is
-- uploaded first to documents at p_path (<site_id>/doc/<document_id>/...).
create function public.fn_add_document_version(
  p_client_ref uuid,
  p_document uuid,
  p_path text,
  p_file_name text,
  p_mime_type text,
  p_size_bytes bigint,
  p_note text
)
returns public.documents
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.documents;
begin
  select * into v from public.documents where id = p_document and not is_archived for update;
  if not found or not public._can('docs.view', v.site_id) then
    raise exception 'NOT_FOUND: Document not found';
  end if;
  if exists (select 1 from public.document_versions where id = p_client_ref) then
    return v;
  end if;
  if not public._can('docs.manage', v.site_id) then
    raise exception 'NOT_ALLOWED: Only a supervisor can upload documents';
  end if;
  if public._path_site(p_path) is distinct from v.site_id then
    raise exception 'INVALID: The file is not in this site''s folder';
  end if;
  if length(trim(coalesce(p_file_name, ''))) = 0 then
    raise exception 'INVALID: The file needs a name';
  end if;

  insert into public.document_versions (id, document_id, version, path, file_name, mime_type, size_bytes, note)
  values (p_client_ref, v.id, v.current_version + 1, p_path, trim(p_file_name), p_mime_type,
    p_size_bytes, nullif(trim(coalesce(p_note, '')), ''));
  update public.documents set current_version = current_version + 1
  where id = v.id
  returning * into v;

  if v.needs_ack then
    perform public.fn_notify_permission(v.site_id, 'docs.view', 'reminder',
      case when v.current_version = 1 then 'New SOP to read: ' else 'Updated SOP to read: ' end
        || v.code,
      v.title || ' (version ' || v.current_version || ')', 'doc:' || v.id);
  end if;
  return v;
end;
$$;

-- "I have read and understood" the current version.
create function public.fn_acknowledge_document(p_document uuid, p_version integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.documents;
begin
  select * into v from public.documents where id = p_document and not is_archived;
  if not found or not public._can('docs.view', v.site_id) then
    raise exception 'NOT_FOUND: Document not found';
  end if;
  if p_version is distinct from v.current_version or v.current_version = 0 then
    raise exception 'CONFLICT: There is a newer version of %; open it again', v.code;
  end if;
  insert into public.document_acks (document_id, version, user_id)
  values (v.id, p_version, auth.uid())
  on conflict do nothing;
end;
$$;

-- Link or unlink a document on a job (the job's poster or a supervisor).
create function public.fn_link_document(p_job uuid, p_document uuid, p_linked boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  j public.jobs;
  d public.documents;
begin
  select * into j from public.jobs where id = p_job and not is_archived;
  if not found or not public._can('jobs.view', j.site_id) then
    raise exception 'NOT_FOUND: Job not found';
  end if;
  if not (j.created_by = auth.uid() or j.assignee_id = auth.uid()
          or public._can('jobs.assign', j.site_id)) then
    raise exception 'NOT_ALLOWED: Only the poster, the assignee or a supervisor can attach documents';
  end if;
  select * into d from public.documents where id = p_document and not is_archived;
  if not found or d.site_id <> j.site_id then
    raise exception 'INVALID: That document is not at this job''s site';
  end if;
  if coalesce(p_linked, true) then
    insert into public.job_documents (job_id, document_id) values (j.id, d.id)
    on conflict do nothing;
  else
    delete from public.job_documents where job_id = j.id and document_id = d.id;
  end if;
end;
$$;

-- Who has and has not acknowledged the current version (supervisors).
create function public.fn_document_acks(p_document uuid)
returns table (user_id uuid, full_name text, acked_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v public.documents;
begin
  select * into v from public.documents where id = p_document;
  if not found or not public._can('docs.manage', v.site_id) then
    raise exception 'NOT_ALLOWED: Only a supervisor can see who has signed';
  end if;
  return query
  select p.id, p.full_name, a.acked_at
  from public.profiles p
  left join public.document_acks a
    on a.user_id = p.id and a.document_id = v.id and a.version = v.current_version
  where p.active and not p.is_archived and public._user_can(p.id, 'docs.view', v.site_id)
  order by a.acked_at nulls first, lower(p.full_name);
end;
$$;

revoke execute on function
  public.fn_save_document(uuid, uuid, text, text, boolean, boolean),
  public.fn_add_document_version(uuid, uuid, text, text, text, bigint, text),
  public.fn_acknowledge_document(uuid, integer),
  public.fn_link_document(uuid, uuid, boolean),
  public.fn_document_acks(uuid)
from public, anon;

grant execute on function
  public.fn_save_document(uuid, uuid, text, text, boolean, boolean),
  public.fn_add_document_version(uuid, uuid, text, text, text, bigint, text),
  public.fn_acknowledge_document(uuid, integer),
  public.fn_link_document(uuid, uuid, boolean),
  public.fn_document_acks(uuid)
to authenticated;

-- ---------------------------------------------------------------------------
-- RLS: read with docs.view; your own acknowledgements; writes via functions
-- ---------------------------------------------------------------------------
alter table public.documents enable row level security;
alter table public.document_versions enable row level security;
alter table public.document_acks enable row level security;
alter table public.job_documents enable row level security;

create policy documents_select on public.documents for select to authenticated
  using (public._can('docs.view', site_id));
create policy document_versions_select on public.document_versions for select to authenticated
  using (exists (
    select 1 from public.documents d
    where d.id = document_versions.document_id and public._can('docs.view', d.site_id)
  ));
create policy document_acks_select on public.document_acks for select to authenticated
  using (user_id = auth.uid() or exists (
    select 1 from public.documents d
    where d.id = document_acks.document_id and public._can('docs.manage', d.site_id)
  ));
create policy job_documents_select on public.job_documents for select to authenticated
  using (exists (
    select 1 from public.jobs j
    where j.id = job_documents.job_id and public._can('jobs.view', j.site_id)
  ));

revoke all on public.documents, public.document_versions, public.document_acks, public.job_documents
from anon;
revoke insert, update, delete on public.documents, public.document_versions, public.document_acks,
  public.job_documents
from authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.documents;
  end if;
end;
$$;

insert into public.schema_migrations (filename) values ('0007_documents.sql')
on conflict do nothing;
