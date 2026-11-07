-- 0036_tool_stats: tool statistics (API.md section 11c, issue #27). One
-- read-only function for the Job stats screen: losses, late returns, damage
-- with its repair job cards, calibration due or expired, and a summary per
-- person and company, for one site or every site the caller can see.

create function public.fn_tool_stats(p_site uuid, p_from date, p_to date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_today date := public._harare_today();
  v_sites uuid[];
  v_out jsonb;
begin
  if p_from is null or p_to is null or p_from > p_to then
    raise exception 'INVALID: Pick a date range';
  end if;
  if p_site is null then
    select coalesce(array_agg(s.id), '{}') into v_sites
    from public.sites s where not s.is_archived and public._can('tools.view', s.id);
  elsif public._can('tools.view', p_site) then
    v_sites := array[p_site];
  else
    raise exception 'NOT_ALLOWED: You cannot see tools at this site';
  end if;

  with issues as (
    select ti.*, t.site_id, t.code, t.name, t.calibration_due,
      coalesce(p.full_name, f.recipient_name, 'Someone') as holder,
      f.company,
      (ti.returned_at at time zone 'Africa/Harare')::date as returned_on
    from public.tool_issues ti
    join public.tools t on t.id = ti.tool_id
    left join public.profiles p on p.id = ti.issued_to
    left join public.tool_issue_forms f on f.id = ti.form_id
    where t.site_id = any (v_sites) and not ti.is_archived
  ),
  in_range as (
    select * from issues where returned_on between p_from and p_to
  ),
  late as (
    select i.*, (coalesce(i.returned_on, v_today) - i.due_back) as days_late
    from issues i
    where i.due_back is not null
      and ((i.returned_on between p_from and p_to and i.returned_on > i.due_back)
        or (i.returned_at is null and i.due_back < v_today))
  ),
  damage as (
    select i.*, jc.id as repair_id, jc.number as repair_number, jc.status as repair_status
    from in_range i
    left join lateral (
      select j.id, j.number, j.status from public.job_card_tools jt
      join public.job_cards j on j.id = jt.job_card_id
      where jt.tool_id = i.tool_id and j.title like 'Repair %' and j.registered_at >= i.returned_at - interval '1 minute'
      order by j.registered_at
      limit 1
    ) jc on true
    where i.return_condition in ('damaged', 'needs_repair')
  )
  select jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'sites', to_jsonb(v_sites),
    'totals', jsonb_build_object(
      'returned', (select count(*) from in_range),
      'lost', (select count(*) from in_range where return_condition = 'lost'),
      'damaged', (select count(*) from damage),
      'late', (select count(*) from late where returned_at is not null),
      'overdue_now', (select count(*) from late where returned_at is null),
      'calibration_expired', (select count(*) from public.tools t
        where t.site_id = any (v_sites) and not t.is_archived and t.calibration_due < v_today),
      'calibration_due_30', (select count(*) from public.tools t
        where t.site_id = any (v_sites) and not t.is_archived and t.calibration_due between v_today and v_today + 30)
    ),
    'losses', coalesce((select jsonb_agg(jsonb_build_object(
        'tool_id', tool_id, 'code', code, 'name', name, 'holder', holder, 'company', company,
        'returned_on', returned_on, 'note', return_note) order by returned_at desc)
      from in_range where return_condition = 'lost'), '[]'),
    'late', coalesce((select jsonb_agg(jsonb_build_object(
        'tool_id', tool_id, 'code', code, 'name', name, 'holder', holder, 'company', company,
        'due_back', due_back, 'returned_on', returned_on, 'days_late', days_late,
        'still_out', returned_at is null) order by days_late desc)
      from late), '[]'),
    'damage', coalesce((select jsonb_agg(jsonb_build_object(
        'tool_id', tool_id, 'code', code, 'name', name, 'holder', holder, 'company', company,
        'condition', return_condition, 'returned_on', returned_on, 'note', return_note,
        'repair_job_card_id', repair_id, 'repair_number', repair_number, 'repair_status', repair_status)
        order by returned_at desc)
      from damage), '[]'),
    'calibration', coalesce((select jsonb_agg(jsonb_build_object(
        'tool_id', t.id, 'code', t.code, 'name', t.name, 'calibration_due', t.calibration_due,
        'expired', t.calibration_due < v_today) order by t.calibration_due)
      from public.tools t
      where t.site_id = any (v_sites) and not t.is_archived and t.calibration_due <= v_today + 30), '[]'),
    'people', coalesce((select jsonb_agg(x order by (x ->> 'lost')::int desc, (x ->> 'late')::int desc,
        (x ->> 'damaged')::int desc, x ->> 'holder')
      from (
        select jsonb_build_object(
          'holder', holder, 'company', company,
          'returned', count(*) filter (where returned_on between p_from and p_to),
          'lost', count(*) filter (where returned_on between p_from and p_to and return_condition = 'lost'),
          'damaged', count(*) filter (where returned_on between p_from and p_to
            and return_condition in ('damaged', 'needs_repair')),
          'late', count(*) filter (where due_back is not null and ((returned_on between p_from and p_to
            and returned_on > due_back) or (returned_at is null and due_back < v_today)))
        ) as x
        from issues
        group by holder, company
        having count(*) filter (where returned_on between p_from and p_to) > 0
          or count(*) filter (where returned_at is null and due_back < v_today) > 0
      ) per_person), '[]')
  ) into v_out;
  return v_out;
end;
$$;

revoke execute on function public.fn_tool_stats(uuid, date, date) from public, anon;
grant execute on function public.fn_tool_stats(uuid, date, date) to authenticated;

insert into public.schema_migrations (filename) values ('0036_tool_stats.sql')
on conflict do nothing;
