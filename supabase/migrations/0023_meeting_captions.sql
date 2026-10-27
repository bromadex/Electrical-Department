-- 0023_meeting_captions: live captions instead of recordings (#15). During
-- a meeting each person's app sends their own voice in short pieces to the
-- meeting-caption edge function, which turns it into text (Groq Whisper) and
-- adds it here with their name. Everyone in the chat sees the captions as
-- they arrive; the minutes are drafted from them. No audio is stored, so
-- the recording columns of 0022 are no longer used.

create table public.meeting_captions (
  id uuid primary key default gen_random_uuid(),
  meeting_id uuid not null references public.meetings (id),
  conversation_id uuid not null references public.conversations (id),
  user_id uuid not null references public.profiles (id) default auth.uid(),
  -- When the person started saying it (their phone's clock).
  spoken_at timestamptz not null,
  body text not null check (length(trim(body)) between 1 and 4000),
  created_at timestamptz not null default now()
);
create index meeting_captions_meeting_idx on public.meeting_captions (meeting_id, spoken_at);

-- Adds one caption for the caller. Only people in the chat, only while the
-- meeting is on (from 15 minutes before until 2 hours after the planned end).
create function public.fn_add_caption(p_meeting uuid, p_spoken_at timestamptz, p_body text)
returns public.meeting_captions
language plpgsql
security definer
set search_path = ''
as $$
declare
  m public.meetings;
  c public.meeting_captions;
begin
  select * into m from public.meetings where id = p_meeting;
  if not found or not public._is_member(m.conversation_id) then
    raise exception 'NOT_FOUND: Meeting not found';
  end if;
  if m.status = 'cancelled'
     or now() < m.starts_at - interval '15 minutes'
     or now() > m.starts_at + make_interval(mins => m.duration_min + 120) then
    raise exception 'INVALID: The meeting is not on now';
  end if;
  if m.minutes_status = 'approved' then
    raise exception 'INVALID: The minutes are already approved';
  end if;
  if length(trim(coalesce(p_body, ''))) = 0 then
    raise exception 'INVALID: Nothing was said';
  end if;
  insert into public.meeting_captions (meeting_id, conversation_id, spoken_at, body)
  values (p_meeting, m.conversation_id, least(coalesce(p_spoken_at, now()), now()), left(trim(p_body), 4000))
  returning * into c;
  return c;
end;
$$;

-- The whole transcript, oldest first, with names.
create function public.fn_meeting_transcript(p_meeting uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select string_agg(
    to_char(c.spoken_at at time zone 'Africa/Harare', 'HH24:MI') || ' '
      || coalesce(nullif(p.full_name, ''), 'Someone') || ': ' || c.body,
    E'\n' order by c.spoken_at, c.created_at)
  from public.meeting_captions c
  join public.meetings m on m.id = c.meeting_id
  join public.profiles p on p.id = c.user_id
  where c.meeting_id = p_meeting and public._is_member(m.conversation_id);
$$;

revoke execute on function
  public.fn_add_caption(uuid, timestamptz, text),
  public.fn_meeting_transcript(uuid)
from public, anon;
grant execute on function
  public.fn_add_caption(uuid, timestamptz, text),
  public.fn_meeting_transcript(uuid)
to authenticated;

alter table public.meeting_captions enable row level security;
create policy meeting_captions_select on public.meeting_captions for select to authenticated
  using (public._is_member(conversation_id));
revoke all on public.meeting_captions from anon;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.meeting_captions;
  end if;
end;
$$;
