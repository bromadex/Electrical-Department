-- 0016_job_card_documents: SOPs and drawings attached to job cards
-- (API.md section 17), as job_documents did for the jobs board.
-- Who may attach: whoever registered the job card, anyone on its team, and
-- people who assess or assign job cards at the site. Closed and cancelled
-- job cards keep what they had.

create table public.job_card_documents (
  job_card_id uuid not null references public.job_cards (id),
  document_id uuid not null references public.documents (id),
  linked_by uuid references public.profiles (id) default auth.uid(),
  linked_at timestamptz not null default now(),
  primary key (job_card_id, document_id)
);
create index job_card_documents_document_idx on public.job_card_documents (document_id);

create function public.fn_link_job_card_document(p_job_card uuid, p_document uuid, p_linked boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  j public.job_cards;
  d public.documents;
begin
  select * into j from public.job_cards where id = p_job_card and not is_archived;
  if not found or not public._can('jc.view', j.site_id) then
    raise exception 'NOT_FOUND: Job card not found';
  end if;
  if not (
    coalesce(j.registered_by = auth.uid(), false)
    or coalesce(j.responsible_id = auth.uid(), false)
    or exists (
      select 1 from public.job_assignments a
      where a.job_card_id = j.id and a.user_id = auth.uid() and a.ended_at is null
    )
    or public._can('jc.assign', j.site_id)
    or public._can('jc.assess', j.site_id)
  ) then
    raise exception 'NOT_ALLOWED: Only the team on this job card or a supervisor can attach documents';
  end if;
  if j.status in ('closed', 'cancelled') then
    raise exception 'INVALID: % is %; its documents can no longer change', j.number, j.status;
  end if;
  select * into d from public.documents where id = p_document and not is_archived;
  if not found or d.site_id <> j.site_id then
    raise exception 'INVALID: That document is not at this job card''s site';
  end if;
  if coalesce(p_linked, true) then
    insert into public.job_card_documents (job_card_id, document_id) values (j.id, d.id)
    on conflict do nothing;
  else
    delete from public.job_card_documents where job_card_id = j.id and document_id = d.id;
  end if;
end;
$$;

revoke execute on function public.fn_link_job_card_document(uuid, uuid, boolean) from public, anon;
grant execute on function public.fn_link_job_card_document(uuid, uuid, boolean) to authenticated;

alter table public.job_card_documents enable row level security;
create policy job_card_documents_select on public.job_card_documents for select to authenticated
  using (exists (
    select 1 from public.job_cards j
    where j.id = job_card_documents.job_card_id and public._can('jc.view', j.site_id)
  ));
revoke all on public.job_card_documents from anon;
revoke insert, update, delete on public.job_card_documents from authenticated;

insert into public.schema_migrations (filename) values ('0016_job_card_documents.sql')
on conflict do nothing;
