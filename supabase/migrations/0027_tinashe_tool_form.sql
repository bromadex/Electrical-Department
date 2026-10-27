-- 0027_tinashe_tool_form: records the signed paper Tool Issue Form of
-- 27 October 2026 (Tinashe Mademe, Manhattan) at the Harare site, so the
-- official record is in the app (API.md section 11b). Adds the 15 tools to
-- the Harare register and issues them on one form. The signatures are on
-- the paper form. Does nothing where there is no Harare site, and never
-- records the form twice.

create function public._record_tinashe_form()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_site uuid;
  v_form uuid;
  v_tool uuid;
  r record;
begin
  select id into v_site from public.sites
  where lower(trim(name)) = 'harare' and not is_archived;
  if v_site is null then
    return 0;
  end if;
  if exists (
    select 1 from public.tool_issue_forms
    where site_id = v_site and recipient_name = 'Tinashe Mademe'
      and issued_at::date = date '2026-10-27'
  ) then
    return 0;
  end if;

  insert into public.tool_issue_forms (
    site_id, code, issued_by, issued_at, recipient_name, recipient_role, company,
    team_lead, remarks
  ) values (
    v_site, public.next_code(v_site, 'TI'), null, timestamptz '2026-10-27 08:00:00+02',
    'Tinashe Mademe', 'Electrician', 'Manhattan', 'Elia Manjawu',
    'Entered from the paper Tool Issue Form of 27 October 2026; the signatures are on the paper form.'
  )
  returning id into v_form;

  for r in
    select * from (values
      (1, 'Fluke True-RMS Clamp Meter', '67510984WS'),
      (2, 'Forge Ratchet Screwdriver & Bits Set (26 pcs)', null),
      (3, 'Ingco Impact Screwdriver Bits Set (31 pcs)', null),
      (4, 'Ingco Hex Key (Allen Key) Set (9 pcs)', null),
      (5, 'HellermannTyton Medium Duty Crimper 275 mm', null),
      (6, 'Ingco Steel Measuring Tape 5 m', null),
      (7, 'Worksite 2-in-1 Wire Stripper / Cutter 7"', null),
      (8, 'Ingco Pump Pliers 200 mm (8")', null),
      (9, 'Ingco 20 oz Claw Hammer, Fiberglass Handle', null),
      (10, 'Ingco Hacksaw Frame 300 mm (12")', null),
      (11, 'Ingco Hacksaw Blade 18T', null),
      (12, 'Ingco Insulated Screwdriver Set (6 pcs)', null),
      (13, 'Ingco Insulated Pliers Set (3 pcs)', null),
      (14, 'Forge Toolbox', null),
      (15, 'Ingco Padlock', null)
    ) as t (no, name, serial_no)
    order by no
  loop
    insert into public.tools (
      site_id, code, name, serial_no, holder_name, issue_form_id, issued_at
    ) values (
      v_site, public.next_code(v_site, 'T'), r.name, r.serial_no, 'Tinashe Mademe', v_form,
      timestamptz '2026-10-27 08:00:00+02'
    )
    returning id into v_tool;
    insert into public.tool_issues (tool_id, issued_to, issued_by, issued_at, form_id, qty)
    values (v_tool, null, null, timestamptz '2026-10-27 08:00:00+02', v_form, 1);
  end loop;
  return 1;
end;
$$;

revoke execute on function public._record_tinashe_form() from public, anon, authenticated;

select public._record_tinashe_form();

insert into public.schema_migrations (filename) values ('0027_tinashe_tool_form.sql')
on conflict do nothing;
