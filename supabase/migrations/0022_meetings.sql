-- 0022_meetings: meetings live inside group chats (#15). A meeting (M-) is
-- scheduled from a chat by someone with meetings.manage; the chat's call is
-- the meeting room, so everyone in the chat can join. Its card, a reminder
-- 15 minutes before and the approved minutes are posted into the chat.
-- Recording and AI-drafted minutes come through the meeting-record and
-- meeting-minutes edge functions, which call the functions below with the
-- chair's sign-in. Minutes hold a summary, decisions and action items; an
-- action item can become a job card in the app.

create table public.meetings (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id),
  conversation_id uuid not null references public.conversations (id),
  code text not null,
  title text not null check (length(trim(title)) between 2 and 160),
  agenda text check (length(agenda) <= 4000),
  starts_at timestamptz not null,
  duration_min integer not null default 60 check (duration_min between 5 and 600),
  chair_id uuid not null references public.profiles (id) default auth.uid(),
  status text not null default 'scheduled' check (status in ('scheduled', 'cancelled')),
  reminded_at timestamptz,
  message_id uuid references public.messages (id),
  -- none | recording | processing | ready | failed
  recording_status text not null default 'none'
    check (recording_status in ('none', 'recording', 'processing', 'ready', 'failed')),
  egress_id text,
  audio_path text,
  recording_error text,
  transcript text,
  -- {summary, decisions: [text], actions: [{text, owner_id, due}]}
  minutes jsonb,
  minutes_status text not null default 'none' check (minutes_status in ('none', 'draft', 'approved')),
  minutes_approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (site_id, code)
);
create index meetings_conversation_idx on public.meetings (conversation_id, starts_at desc);
create index meetings_upcoming_idx on public.meetings (starts_at) where status = 'scheduled';

create trigger meetings_touch before update on public.meetings
  for each row execute function public.fn_touch_updated_at();
create trigger meetings_activity after insert or update on public.meetings
  for each row execute function public.fn_log_activity();

-- Chair, or meetings.manage at the meeting's site.
create function public._can_run_meeting(m public.meetings)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select m.chair_id = auth.uid() or public._can('meetings.manage', m.site_id);
$$;

-- Posts a line from the app into the chat (not counted as anyone's unread
-- for its author) and moves the chat to the top.
create function public._post_system(p_conversation uuid, p_body text, p_link text, p_preview text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  insert into public.messages (conversation_id, author_id, kind, body, record_link)
  values (p_conversation, auth.uid(), 'system', p_body, p_link)
  returning id into v_id;
  update public.conversations set last_message_at = now(), last_message_preview = p_preview
  where id = p_conversation;
  return v_id;
end;
$$;

create function public.fn_create_meeting(
  p_client_ref uuid,
  p_conversation uuid,
  p_site uuid,
  p_title text,
  p_agenda text,
  p_starts_at timestamptz,
  p_duration_min integer
)
returns public.meetings
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.conversations;
  m public.meetings;
  v_site uuid;
  v_when text;
begin
  select * into m from public.meetings where id = p_client_ref;
  if found then
    return m;
  end if;
  select * into c from public.conversations where id = p_conversation and not is_archived;
  if not found or not public._is_member(p_conversation) then
    raise exception 'NOT_FOUND: Chat not found';
  end if;
  if c.kind <> 'group' then
    raise exception 'INVALID: Meetings are held in group chats';
  end if;
  v_site := coalesce(c.site_id, p_site);
  if v_site is null then
    raise exception 'INVALID: Pick the site this meeting is for';
  end if;
  if not public._can('meetings.manage', v_site) then
    raise exception 'NOT_ALLOWED: You cannot schedule meetings';
  end if;
  if length(trim(coalesce(p_title, ''))) < 2 then
    raise exception 'INVALID: Give the meeting a title';
  end if;
  if p_starts_at is null or p_starts_at < now() - interval '1 hour' then
    raise exception 'INVALID: Pick when the meeting starts';
  end if;

  insert into public.meetings (id, site_id, conversation_id, code, title, agenda, starts_at, duration_min)
  values (p_client_ref, v_site, p_conversation, public.next_code(v_site, 'M'), trim(p_title),
          nullif(trim(coalesce(p_agenda, '')), ''), p_starts_at, coalesce(p_duration_min, 60))
  returning * into m;

  v_when := to_char(p_starts_at at time zone 'Africa/Harare', 'Dy DD Mon, HH24:MI');
  update public.meetings
  set message_id = public._post_system(p_conversation,
        m.code || ' · ' || m.title || ' · ' || v_when, 'meeting:' || m.id,
        '📅 Meeting: ' || m.title || ' · ' || v_when)
  where id = m.id
  returning * into m;

  insert into public.notifications (user_id, site_id, type, title, body, link)
  select cm.user_id, v_site, 'meeting', 'Meeting: ' || m.title, v_when || ' in ' || coalesce(c.title, 'the chat'),
    'meeting:' || m.id
  from public.conversation_members cm
  join public.profiles p on p.id = cm.user_id and p.active and not p.is_archived
  where cm.conversation_id = p_conversation and not cm.is_archived and cm.user_id <> auth.uid();
  return m;
end;
$$;

-- Change or cancel (p_cancel) a meeting.
create function public.fn_update_meeting(
  p_meeting uuid,
  p_title text,
  p_agenda text,
  p_starts_at timestamptz,
  p_duration_min integer,
  p_cancel boolean
)
returns public.meetings
language plpgsql
security definer
set search_path = ''
as $$
declare
  m public.meetings;
begin
  select * into m from public.meetings where id = p_meeting for update;
  if not found or not public._is_member(m.conversation_id) then
    raise exception 'NOT_FOUND: Meeting not found';
  end if;
  if not public._can_run_meeting(m) then
    raise exception 'NOT_ALLOWED: Only the chair can change this meeting';
  end if;
  if length(trim(coalesce(p_title, m.title))) < 2 then
    raise exception 'INVALID: Give the meeting a title';
  end if;
  update public.meetings set
    title = trim(coalesce(p_title, title)),
    agenda = case when p_agenda is null then agenda else nullif(trim(p_agenda), '') end,
    starts_at = coalesce(p_starts_at, starts_at),
    duration_min = coalesce(p_duration_min, duration_min),
    status = case when coalesce(p_cancel, false) then 'cancelled' else status end,
    reminded_at = case when p_starts_at is distinct from null and p_starts_at <> starts_at then null else reminded_at end
  where id = p_meeting
  returning * into m;
  if coalesce(p_cancel, false) then
    perform public._post_system(m.conversation_id, m.code || ' cancelled: ' || m.title,
      'meeting:' || m.id, '📅 Cancelled: ' || m.title);
  end if;
  return m;
end;
$$;

-- Who joined the chat's call during the meeting.
create function public.fn_meeting_attendance(p_meeting uuid)
returns table (user_id uuid, full_name text, joined_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select cp.user_id, coalesce(nullif(p.full_name, ''), 'Someone'), min(cp.joined_at)
  from public.meetings m
  join public.call_participants cp on cp.conversation_id = m.conversation_id
    and cp.joined_at between m.starts_at - interval '30 minutes'
      and m.starts_at + make_interval(mins => m.duration_min + 90)
  join public.profiles p on p.id = cp.user_id
  where m.id = p_meeting and public._is_member(m.conversation_id)
  group by cp.user_id, p.full_name
  order by min(cp.joined_at);
$$;

-- Recording state, set by the meeting-record edge function (chair only).
create function public.fn_meeting_recording(
  p_meeting uuid,
  p_status text,
  p_egress text,
  p_audio_path text,
  p_error text
)
returns public.meetings
language plpgsql
security definer
set search_path = ''
as $$
declare
  m public.meetings;
begin
  select * into m from public.meetings where id = p_meeting for update;
  if not found or not public._is_member(m.conversation_id) then
    raise exception 'NOT_FOUND: Meeting not found';
  end if;
  if not public._can_run_meeting(m) then
    raise exception 'NOT_ALLOWED: Only the chair can record';
  end if;
  if p_status not in ('none', 'recording', 'processing', 'ready', 'failed') then
    raise exception 'INVALID: Unknown recording state';
  end if;
  update public.meetings set
    recording_status = p_status,
    egress_id = coalesce(p_egress, egress_id),
    audio_path = coalesce(p_audio_path, audio_path),
    recording_error = case when p_status = 'failed' then left(p_error, 500) else null end
  where id = p_meeting
  returning * into m;
  if p_status = 'recording' then
    perform public._post_system(m.conversation_id, 'Recording started: ' || m.title,
      'meeting:' || m.id, '🔴 Recording: ' || m.title);
  end if;
  return m;
end;
$$;

-- Saves the transcript and/or a draft of the minutes (chair; the
-- meeting-minutes edge function and the minutes editor).
create function public.fn_save_minutes(p_meeting uuid, p_transcript text, p_minutes jsonb)
returns public.meetings
language plpgsql
security definer
set search_path = ''
as $$
declare
  m public.meetings;
begin
  select * into m from public.meetings where id = p_meeting for update;
  if not found or not public._is_member(m.conversation_id) then
    raise exception 'NOT_FOUND: Meeting not found';
  end if;
  if not public._can_run_meeting(m) then
    raise exception 'NOT_ALLOWED: Only the chair can write the minutes';
  end if;
  if m.minutes_status = 'approved' then
    raise exception 'INVALID: These minutes are already approved';
  end if;
  if p_minutes is not null and jsonb_typeof(p_minutes) <> 'object' then
    raise exception 'INVALID: Minutes must be an object';
  end if;
  update public.meetings set
    transcript = coalesce(p_transcript, transcript),
    minutes = coalesce(p_minutes, minutes),
    minutes_status = case when coalesce(p_minutes, minutes) is null then minutes_status else 'draft' end
  where id = p_meeting
  returning * into m;
  return m;
end;
$$;

-- Publishes the minutes: posted into the chat, and each action owner told.
create function public.fn_approve_minutes(p_meeting uuid)
returns public.meetings
language plpgsql
security definer
set search_path = ''
as $$
declare
  m public.meetings;
  a jsonb;
begin
  select * into m from public.meetings where id = p_meeting for update;
  if not found or not public._is_member(m.conversation_id) then
    raise exception 'NOT_FOUND: Meeting not found';
  end if;
  if not public._can_run_meeting(m) then
    raise exception 'NOT_ALLOWED: Only the chair can approve the minutes';
  end if;
  if m.minutes is null or length(trim(coalesce(m.minutes ->> 'summary', ''))) = 0 then
    raise exception 'INVALID: Write a summary first';
  end if;
  if m.minutes_status = 'approved' then
    return m;
  end if;
  update public.meetings set minutes_status = 'approved', minutes_approved_at = now()
  where id = p_meeting
  returning * into m;
  perform public._post_system(m.conversation_id, 'Minutes: ' || m.code || ' · ' || m.title,
    'meeting:' || m.id, '📝 Minutes: ' || m.title);
  for a in select * from jsonb_array_elements(coalesce(m.minutes -> 'actions', '[]'::jsonb)) loop
    if (a ->> 'owner_id') ~ '^[0-9a-f-]{36}$'
       and exists (select 1 from public.profiles where id = (a ->> 'owner_id')::uuid) then
      perform public.fn_notify((a ->> 'owner_id')::uuid, m.site_id, 'meeting',
        'Action for you: ' || m.title, left(a ->> 'text', 140), 'meeting:' || m.id);
    end if;
  end loop;
  return m;
end;
$$;

-- Every 5 minutes: remind the chat 15 minutes before a meeting.
create function public.fn_meeting_reminders()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  m public.meetings;
begin
  for m in
    update public.meetings set reminded_at = now()
    where status = 'scheduled' and reminded_at is null
      and starts_at between now() and now() + interval '15 minutes'
    returning *
  loop
    insert into public.notifications (user_id, site_id, type, title, body, link)
    select cm.user_id, m.site_id, 'meeting', 'Starting soon: ' || m.title,
      to_char(m.starts_at at time zone 'Africa/Harare', 'HH24:MI') || ' · tap to join',
      'meeting:' || m.id
    from public.conversation_members cm
    join public.profiles p on p.id = cm.user_id and p.active and not p.is_archived
    where cm.conversation_id = m.conversation_id and not cm.is_archived;
  end loop;
end;
$$;

revoke execute on function
  public._can_run_meeting(public.meetings),
  public._post_system(uuid, text, text, text),
  public.fn_create_meeting(uuid, uuid, uuid, text, text, timestamptz, integer),
  public.fn_update_meeting(uuid, text, text, timestamptz, integer, boolean),
  public.fn_meeting_attendance(uuid),
  public.fn_meeting_recording(uuid, text, text, text, text),
  public.fn_save_minutes(uuid, text, jsonb),
  public.fn_approve_minutes(uuid),
  public.fn_meeting_reminders()
from public, anon;
revoke execute on function
  public._post_system(uuid, text, text, text),
  public.fn_meeting_reminders()
from authenticated;
grant execute on function
  public._can_run_meeting(public.meetings),
  public.fn_create_meeting(uuid, uuid, uuid, text, text, timestamptz, integer),
  public.fn_update_meeting(uuid, text, text, timestamptz, integer, boolean),
  public.fn_meeting_attendance(uuid),
  public.fn_meeting_recording(uuid, text, text, text, text),
  public.fn_save_minutes(uuid, text, jsonb),
  public.fn_approve_minutes(uuid)
to authenticated;

alter table public.meetings enable row level security;
create policy meetings_select on public.meetings for select to authenticated
  using (public._is_member(conversation_id));
revoke all on public.meetings from anon;

-- Recordings: the chat's members may listen (path <meeting id>/...).
create policy meeting_audio_read on storage.objects for select to authenticated
  using (
    bucket_id = 'meeting-audio'
    and exists (
      select 1 from public.meetings m
      where m.id::text = split_part(name, '/', 1) and public._is_member(m.conversation_id)
    )
  );

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.meetings;
  end if;
end;
$$;

select cron.schedule('meeting-reminders', '*/5 * * * *', 'select public.fn_meeting_reminders()');
