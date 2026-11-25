-- 0060_job_kind_at_registration: not every job is a fault. Whoever
-- registers a job card says what kind of work it is (a breakdown, or
-- planned work: an installation, an improvement, an inspection,
-- maintenance), which fills job_cards.maintenance_type before assessment.
-- The engineer can still change it when assessing (API.md section 5c).

create function public.fn_set_job_kind(p_job uuid, p_type text)
returns public.job_cards
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.job_cards;
begin
  select * into v from public.job_cards where id = p_job and not is_archived;
  if not found then
    raise exception 'NOT_FOUND: Job card not found';
  end if;
  if p_type is null or p_type not in (
    'reactive', 'preventive', 'corrective', 'emergency', 'inspection', 'installation', 'improvement'
  ) then
    raise exception 'INVALID: Unknown kind of work';
  end if;
  -- The person who registered it, or someone who assesses at the site.
  if v.registered_by is distinct from auth.uid() and not public._can('jc.assess', v.site_id) then
    raise exception 'NOT_ALLOWED: Only who registered the job card or an engineer can say what kind it is';
  end if;
  -- Once assessed, the assessment decides.
  if v.assessed_at is not null then
    return v;
  end if;
  update public.job_cards set maintenance_type = p_type where id = v.id
  returning * into v;
  return v;
end;
$$;

revoke execute on function public.fn_set_job_kind(uuid, text) from public, anon;
grant execute on function public.fn_set_job_kind(uuid, text) to authenticated;

insert into public.schema_migrations (filename) values ('0060_job_kind_at_registration.sql')
on conflict do nothing;
