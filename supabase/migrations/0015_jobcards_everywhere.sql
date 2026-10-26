-- 0015_jobcards_everywhere: job cards are the app's one job system
-- (API.md section 17). The jobs board's tables stay as they are, with their
-- data; nothing new is written to them.
--
-- - A failed checklist item raises a job card (checklist_answers.job_card_id).
-- - Planned maintenance (job_recurrences) raises preventive job cards,
--   registered as the person who set the plan up.
-- - The daily report counts job cards received, closed and open.
-- - Chat # tags find job cards (links jobcard:<id>).

alter table public.checklist_answers
  add column job_card_id uuid references public.job_cards (id);

create or replace function public.fn_submit_checklist(
  p_client_ref uuid,
  p_template uuid,
  p_answers jsonb,
  p_notes text
)
returns public.checklist_runs
language plpgsql
security definer
set search_path = ''
as $$
declare
  t public.checklist_templates;
  r public.checklist_runs;
  it public.checklist_items;
  a jsonb;
  v_failed boolean;
  v_value numeric;
  v_job public.job_cards;
  v_reporter text;
  v_count integer := 0;
begin
  select * into r from public.checklist_runs where id = p_client_ref;
  if found then
    return r;
  end if;
  select * into t from public.checklist_templates where id = p_template and not is_archived;
  if not found or not public._can('jobs.view', t.site_id) then
    raise exception 'NOT_FOUND: Checklist not found';
  end if;
  if not public._can('jobs.close', t.site_id) then
    raise exception 'NOT_ALLOWED: You cannot do rounds at this site';
  end if;

  insert into public.checklist_runs (id, template_id, site_id, run_date, notes)
  values (p_client_ref, t.id, t.site_id, public._harare_today(), nullif(trim(coalesce(p_notes, '')), ''))
  returning * into r;

  for it in
    select * from public.checklist_items where template_id = t.id and not is_archived order by position
  loop
    a := (
      select x from jsonb_array_elements(coalesce(p_answers, '[]'::jsonb)) x
      where x ->> 'item_id' = it.id::text limit 1
    );
    if a is null then
      raise exception 'INVALID: Answer "%"', it.label;
    end if;
    if it.photo_required and coalesce(a ->> 'photo_path', '') = '' then
      raise exception 'INVALID: "%" needs a photo', it.label;
    end if;
    v_value := null;
    if it.kind = 'check' then
      if a -> 'ok' is null or jsonb_typeof(a -> 'ok') <> 'boolean' then
        raise exception 'INVALID: Mark "%" as OK or not', it.label;
      end if;
      v_failed := not (a ->> 'ok')::boolean;
    elsif it.kind = 'number' then
      begin
        v_value := (a ->> 'value')::numeric;
      exception when others then
        v_value := null;
      end;
      if v_value is null then
        raise exception 'INVALID: Enter the reading for "%"', it.label;
      end if;
      v_failed := (it.min_value is not null and v_value < it.min_value)
               or (it.max_value is not null and v_value > it.max_value);
    else
      if length(trim(coalesce(a ->> 'text', ''))) = 0 then
        raise exception 'INVALID: Fill in "%"', it.label;
      end if;
      v_failed := false;
    end if;

    v_job := null;
    if v_failed then
      v_count := v_count + 1;
      -- A failed item raises a job card. If the person cannot register job
      -- cards the round is still saved; supervisors see the failure.
      select coalesce(nullif(full_name, ''), 'Checklist round') into v_reporter
      from public.profiles where id = auth.uid();
      begin
        v_job := public.fn_register_job_card(
          gen_random_uuid(), null, t.site_id, t.area_id,
          case when t.area_id is null then t.name end,
          now(), coalesce(v_reporter, 'Checklist round'), null, null, null, null, null,
          null,
          left(t.name || ': ' || it.label, 120),
          concat_ws(E'\n',
            'Failed on the ' || t.name || ' round.',
            case when v_value is not null then 'Reading: ' || v_value || coalesce(' ' || it.unit, '')
              || coalesce(' (limits ' || coalesce(it.min_value::text, '…') || '–'
              || coalesce(it.max_value::text, '…') || ')', '') end,
            nullif(trim(coalesce(a ->> 'comment', '')), '')),
          'minor', 'P3', null);
        update public.job_cards set maintenance_type = 'inspection' where id = v_job.id;
      exception when others then
        if sqlerrm not like 'NOT_ALLOWED:%' then
          raise;
        end if;
        v_job := null;
      end;
    end if;

    insert into public.checklist_answers (
      run_id, item_id, ok, value, text_value, photo_path, comment, failed, job_card_id
    ) values (
      r.id, it.id, case when it.kind = 'check' then (a ->> 'ok')::boolean end, v_value,
      nullif(trim(coalesce(a ->> 'text', '')), ''), nullif(a ->> 'photo_path', ''),
      nullif(trim(coalesce(a ->> 'comment', '')), ''), v_failed, v_job.id
    );
  end loop;

  update public.checklist_runs set failed_count = v_count where id = r.id returning * into r;
  return r;
end;
$$;


create or replace function public.fn_run_recurrences()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.job_recurrences;
  v_today date := (now() at time zone 'Africa/Harare')::date;
  v_job public.job_cards;
  v_claims text := current_setting('request.jwt.claims', true);
  v_count integer := 0;
begin
  for r in
    select * from public.job_recurrences
    where not is_archived and next_run <= v_today
    for update skip locked
  loop
    -- Registered as the person who set the plan up, so the job card
    -- records who asked for it and their permissions apply.
    perform set_config('request.jwt.claims',
      json_build_object('sub', r.created_by, 'role', 'authenticated')::text, true);
    begin
      v_job := public.fn_register_job_card(
        gen_random_uuid(), null, r.site_id, r.area_id,
        case when r.area_id is null and r.asset_id is null then 'Planned maintenance' end,
        now(), 'Planned maintenance', null, r.asset_id, null, null, null, null,
        r.title,
        coalesce(nullif(trim(coalesce(r.description, '')), ''), 'Planned maintenance: ' || r.title),
        'none',
        case r.priority when 'urgent' then 'P2' when 'low' then 'P4' else 'P3' end,
        ((v_today + r.due_days)::timestamp + time '17:00') at time zone 'Africa/Harare');
      update public.job_cards set
        source = 'preventive',
        maintenance_type = case when r.asset_id is null then 'inspection' else 'preventive' end,
        isolation_required = r.isolation_required
      where id = v_job.id;
      if r.assignee_id is not null then
        perform public.fn_notify(r.assignee_id, r.site_id, 'assigned',
          v_job.number || ' is due (planned maintenance)', v_job.title, 'jobcard:' || v_job.id);
      end if;
    exception when others then
      -- The person who set it up can no longer register job cards here:
      -- tell the site's planners instead of stopping every other plan.
      perform public.fn_notify_permission(r.site_id, 'jc.register', 'general',
        'Planned job "' || r.title || '" could not be raised', sqlerrm, null);
    end;
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

    update public.job_recurrences set next_run = case r.every
        when 'daily' then v_today + 1
        when 'weekly' then v_today + 7
        else (v_today + interval '1 month')::date
      end
    where id = r.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;


create or replace function public.fn_build_daily_report(p_site uuid, p_date date)
returns public.daily_reports
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.daily_reports;
  v_from timestamptz := (p_date::timestamp at time zone 'Africa/Harare');
  v_to timestamptz := ((p_date + 1)::timestamp at time zone 'Africa/Harare');
begin
  if auth.uid() is not null and not public._can('jobs.view', p_site) then
    raise exception 'NOT_ALLOWED: You do not work at this site';
  end if;
  if p_date > public._harare_today() then
    raise exception 'INVALID: That day has not happened yet';
  end if;
  v := public._report_for(p_site, p_date);
  if v.status = 'approved' then
    return v;
  end if;

  update public.daily_reports set built_at = now(), summary = jsonb_build_object(
    'jobs_opened', coalesce((
      select jsonb_agg(jsonb_build_object('id', j.id, 'code', j.number, 'title', j.title,
        'priority', j.priority, 'status', j.status) order by j.received_at)
      from public.job_cards j
      where j.site_id = p_site and not j.is_archived and j.received_at >= v_from and j.received_at < v_to
    ), '[]'::jsonb),
    'jobs_closed', coalesce((
      select jsonb_agg(jsonb_build_object('id', j.id, 'code', j.number, 'title', j.title,
        'by', p.full_name, 'note', j.completion_summary) order by j.closed_at)
      from public.job_cards j
      left join public.profiles p on p.id = coalesce(j.performed_by, j.responsible_id)
      where j.site_id = p_site and j.status = 'closed' and j.closed_at >= v_from and j.closed_at < v_to
    ), '[]'::jsonb),
    'jobs_open_now', (
      select count(*) from public.job_cards j
      where j.site_id = p_site and not j.is_archived and j.status not in ('closed', 'cancelled')
    ),
    'checklists_done', coalesce((
      select jsonb_agg(jsonb_build_object('name', t.name, 'by', p.full_name,
        'failed', r.failed_count, 'at', r.done_at) order by r.done_at)
      from public.checklist_runs r
      join public.checklist_templates t on t.id = r.template_id
      left join public.profiles p on p.id = r.done_by
      where r.site_id = p_site and r.run_date = p_date
    ), '[]'::jsonb),
    'checklists_missed', coalesce((
      select jsonb_agg(t.name order by t.name)
      from public.checklist_templates t
      where t.site_id = p_site and not t.is_archived
        and public._period_end(t.frequency, p_date) = p_date
        and not exists (
          select 1 from public.checklist_runs r
          where r.template_id = t.id and r.run_date >= public._period_start(t.frequency, p_date)
            and r.run_date <= p_date
        )
    ), '[]'::jsonb),
    'tools_issued', (
      select count(*) from public.tool_issues i join public.tools t on t.id = i.tool_id
      where t.site_id = p_site and i.issued_at >= v_from and i.issued_at < v_to
    ),
    'tools_returned', (
      select count(*) from public.tool_issues i join public.tools t on t.id = i.tool_id
      where t.site_id = p_site and i.returned_at >= v_from and i.returned_at < v_to
    ),
    'tools_out', (
      select count(*) from public.tools t
      where t.site_id = p_site and not t.is_archived and t.holder_id is not null
    )
  )
  where id = v.id
  returning * into v;
  return v;
end;
$$;


create or replace function public.fn_send_message(
  p_client_ref uuid,
  p_conversation uuid,
  p_kind text,
  p_body text,
  p_attachment_path text,
  p_attachment_name text,
  p_attachment_size integer,
  p_duration_ms integer,
  p_reply_to uuid,
  p_record_link text,
  p_mentions uuid[]
)
returns public.messages
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.messages;
  c public.conversations;
  u uuid;
  v_author text;
  v_preview text;
begin
  select * into v from public.messages where id = p_client_ref;
  if found then
    return v;
  end if;
  select * into c from public.conversations where id = p_conversation for update;
  if not found or not public._is_member(p_conversation) then
    raise exception 'NOT_FOUND: Chat not found';
  end if;
  if not public._user_can_chat(auth.uid(), c.site_id) then
    raise exception 'NOT_ALLOWED: You cannot send messages here';
  end if;
  if p_kind not in ('text', 'photo', 'voice', 'file', 'record') then
    raise exception 'INVALID: Unknown message kind';
  end if;
  if p_kind = 'text' and length(trim(coalesce(p_body, ''))) = 0 then
    raise exception 'INVALID: Message is empty';
  end if;
  if p_kind in ('photo', 'voice', 'file') and (
    p_attachment_path is null or split_part(p_attachment_path, '/', 1) <> p_conversation::text
  ) then
    raise exception 'INVALID: Attachment path must start with the chat id';
  end if;
  if p_kind = 'record' and p_record_link !~ '^(jobcard|job|asset|tool|doc):[0-9a-f-]{36}$' then
    raise exception 'INVALID: Record link must look like job:<uuid>';
  end if;

  insert into public.messages (
    id, conversation_id, author_id, kind, body, attachment_path, attachment_name,
    attachment_size, duration_ms, reply_to, record_link, mentions
  ) values (
    p_client_ref, p_conversation, auth.uid(), p_kind, nullif(trim(coalesce(p_body, '')), ''),
    p_attachment_path, p_attachment_name, p_attachment_size, p_duration_ms, p_reply_to,
    p_record_link, coalesce(p_mentions, '{}')
  )
  returning * into v;

  select coalesce(nullif(full_name, ''), 'Someone') into v_author
  from public.profiles where id = auth.uid();
  v_preview := v_author || ': ' || case p_kind
    when 'photo' then '📷 Photo'
    when 'voice' then '🎤 Voice note'
    when 'file' then '📎 ' || coalesce(p_attachment_name, 'File')
    when 'record' then '🔖 ' || coalesce(v.body, p_record_link)
    else left(v.body, 120)
  end;
  update public.conversations set last_message_at = v.created_at, last_message_preview = v_preview
  where id = p_conversation;
  update public.conversation_members set last_read_at = v.created_at
  where conversation_id = p_conversation and user_id = auth.uid();

  foreach u in array coalesce(p_mentions, '{}') loop
    if u <> auth.uid() and exists (
      select 1 from public.conversation_members
      where conversation_id = p_conversation and user_id = u and not is_archived
    ) then
      perform public.fn_notify(u, c.site_id, 'mentioned',
        v_author || ' mentioned you', left(coalesce(v.body, v_preview), 140),
        'chat:' || p_conversation);
    end if;
  end loop;

  -- Everyone else hears once per chat until they open it.
  insert into public.notifications (user_id, site_id, type, title, body, link)
  select m.user_id, c.site_id, 'chat',
    case when c.kind = 'direct' then v_author else coalesce(c.title, 'Chat') end,
    case when c.kind = 'direct' then substr(v_preview, length(v_author) + 3) else v_preview end,
    'chat:' || p_conversation
  from public.conversation_members m
  join public.profiles p on p.id = m.user_id and p.active and not p.is_archived
  where m.conversation_id = p_conversation and not m.is_archived
    and m.user_id <> auth.uid()
    and not (m.user_id = any (coalesce(p_mentions, '{}')))
    and not exists (
      select 1 from public.notifications n
      where n.user_id = m.user_id and n.type = 'chat' and n.read_at is null
        and n.link = 'chat:' || p_conversation
    );
  return v;
end;
$$;


create or replace function public.fn_search_records(p_query text)
returns table (link text, code text, title text, status text, site_code text)
language sql
stable
security definer
set search_path = ''
as $$
  select link, code, title, status, site_code from (
    select 'jobcard:' || j.id as link, j.number as code, j.title, replace(j.status, '_', ' ') as status,
      s.code as site_code, j.updated_at as at, 1 as rank
    from public.job_cards j
    join public.sites s on s.id = j.site_id
    where not j.is_archived and public._can('jc.view', j.site_id)
      and (coalesce(p_query, '') = '' or j.number ilike '%' || p_query || '%'
           or j.title ilike '%' || p_query || '%')
    union all
    select 'asset:' || a.id, a.tag, a.name, 'asset', s.code, a.updated_at, 2
    from public.assets a
    join public.sites s on s.id = a.site_id
    where not a.is_archived and public._can('jobs.view', a.site_id)
      and (coalesce(p_query, '') = '' or a.tag ilike '%' || p_query || '%'
           or a.name ilike '%' || p_query || '%')
    union all
    select 'tool:' || t.id, t.code, t.name, 'tool', s.code, t.updated_at, 3
    from public.tools t
    join public.sites s on s.id = t.site_id
    where not t.is_archived and public._can('tools.view', t.site_id)
      and (coalesce(p_query, '') = '' or t.code ilike '%' || p_query || '%'
           or t.name ilike '%' || p_query || '%')
  ) r
  order by rank, at desc
  limit 20;
$$;


insert into public.schema_migrations (filename) values ('0015_jobcards_everywhere.sql')
on conflict do nothing;
