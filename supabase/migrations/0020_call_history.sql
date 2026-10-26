-- 0020_call_history: each call is recorded with who joined, when it ended
-- and whether anyone answered. The app sends a heartbeat every 30 seconds
-- while in a call (fn_call_heartbeat) and says when it leaves
-- (fn_leave_call). A call is live while someone in it was seen in the last
-- 90 seconds; when the last person leaves (or everyone goes quiet) it ends.
-- A call nobody else joined is missed, and the others are told.
--
-- fn_start_call(p_conversation, p_video) joins the chat's live call, or
-- starts a new one: a "started a call" row in the chat (from 0019) and a
-- notification. fn_my_conversations gains call_live for the chat list.
-- conversation_calls (0017) is no longer written.

create table public.calls (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id),
  started_by uuid references public.profiles (id),
  video boolean not null default false,
  message_id uuid references public.messages (id),
  started_at timestamptz not null default now(),
  answered_at timestamptz,
  ended_at timestamptz
);
create index calls_conversation_idx on public.calls (conversation_id, started_at desc);

create table public.call_participants (
  call_id uuid not null references public.calls (id),
  conversation_id uuid not null references public.conversations (id),
  user_id uuid not null references public.profiles (id),
  joined_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  left_at timestamptz,
  primary key (call_id, user_id)
);

-- People still in a call: not left, and seen in the last 90 seconds.
create function public._call_active_count(p_call uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::int from public.call_participants
  where call_id = p_call and left_at is null and last_seen_at > now() - interval '90 seconds';
$$;

-- Ends a call nobody is in any more; a call nobody else answered is missed
-- and the others are told.
create function public._close_call(p_call uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  k public.calls;
  c public.conversations;
  v_name text;
begin
  select * into k from public.calls where id = p_call and ended_at is null for update;
  if not found or public._call_active_count(p_call) > 0 then
    return;
  end if;
  update public.calls set ended_at = coalesce(
    (select max(coalesce(left_at, last_seen_at)) from public.call_participants where call_id = p_call),
    now())
  where id = p_call;
  if k.answered_at is null then
    select * into c from public.conversations where id = k.conversation_id;
    select coalesce(nullif(full_name, ''), 'Someone') into v_name
    from public.profiles where id = k.started_by;
    insert into public.notifications (user_id, site_id, type, title, body, link)
    select m.user_id, c.site_id, 'meeting',
      'Missed call from ' || v_name,
      case when c.kind = 'direct' then 'Tap to call back' else coalesce(c.title, 'Chat') end,
      'chat:' || k.conversation_id
    from public.conversation_members m
    join public.profiles p on p.id = m.user_id and p.active and not p.is_archived
    where m.conversation_id = k.conversation_id and not m.is_archived
      and m.user_id is distinct from k.started_by;
  end if;
end;
$$;

drop function public.fn_start_call(uuid);
create function public.fn_start_call(p_conversation uuid, p_video boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.conversations;
  k public.calls;
  v_name text;
  v_title text;
  v_message uuid;
  v_new boolean := false;
begin
  select * into c from public.conversations where id = p_conversation and not is_archived;
  if not found or not public._is_member(p_conversation) then
    raise exception 'NOT_FOUND: Chat not found';
  end if;
  if not public._user_can_chat(auth.uid(), c.site_id) then
    raise exception 'NOT_ALLOWED: You cannot call in this chat';
  end if;
  select coalesce(nullif(full_name, ''), 'Someone') into v_name
  from public.profiles where id = auth.uid();

  -- Tidy calls everyone dropped out of, then join the live one if any.
  perform public._close_call(x.id)
  from public.calls x where x.conversation_id = p_conversation and x.ended_at is null;
  select * into k from public.calls
  where conversation_id = p_conversation and ended_at is null
  order by started_at desc limit 1 for update;

  if not found then
    v_new := true;
    insert into public.messages (conversation_id, author_id, kind, body, record_link)
    values (p_conversation, auth.uid(), 'system',
      v_name || case when p_video then ' started a video call' else ' started a call' end,
      'call:' || p_conversation)
    returning id into v_message;
    update public.conversations
    set last_message_at = now(), last_message_preview = '📞 ' || v_name || ' started a call'
    where id = p_conversation;
    update public.conversation_members set last_read_at = now()
    where conversation_id = p_conversation and user_id = auth.uid();
    insert into public.calls (conversation_id, started_by, video, message_id)
    values (p_conversation, auth.uid(), coalesce(p_video, false), v_message)
    returning * into k;

    insert into public.notifications (user_id, site_id, type, title, body, link)
    select m.user_id, c.site_id, 'meeting',
      v_name || case when p_video then ' started a video call' else ' started a call' end,
      case when c.kind = 'direct' then 'Tap to join' else coalesce(c.title, 'Chat') || ' · tap to join' end,
      'call:' || p_conversation
    from public.conversation_members m
    join public.profiles p on p.id = m.user_id and p.active and not p.is_archived
    where m.conversation_id = p_conversation and not m.is_archived and m.user_id <> auth.uid();
  elsif k.answered_at is null and k.started_by is distinct from auth.uid() then
    update public.calls set answered_at = now() where id = k.id;
  end if;

  insert into public.call_participants (call_id, conversation_id, user_id)
  values (k.id, p_conversation, auth.uid())
  on conflict (call_id, user_id) do update set last_seen_at = now(), left_at = null;

  v_title := case when c.kind = 'direct' then v_name else coalesce(c.title, 'Chat') end;
  return jsonb_build_object(
    'room', 'chat-' || p_conversation,
    'identity', auth.uid(),
    'name', v_name,
    'title', v_title,
    'call_id', k.id,
    'new_call', v_new
  );
end;
$$;

-- "Still here": every 30 seconds from the app while in a call.
create function public.fn_call_heartbeat(p_call uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.call_participants set last_seen_at = now(), left_at = null
  where call_id = p_call and user_id = auth.uid()
    and exists (select 1 from public.calls where id = p_call and ended_at is null);
$$;

-- Leaving: ends the call when you were the last one in it.
create function public.fn_leave_call(p_call uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.call_participants set left_at = now(), last_seen_at = now()
  where call_id = p_call and user_id = auth.uid() and left_at is null;
  perform public._close_call(p_call);
end;
$$;

-- A chat's calls, newest first, with what happened: live, missed or ended.
create function public.fn_conversation_calls(p_conversation uuid)
returns table (
  id uuid, message_id uuid, started_by uuid, video boolean, started_at timestamptz,
  answered_at timestamptz, ended_at timestamptz, status text, in_call integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select k.id, k.message_id, k.started_by, k.video, k.started_at, k.answered_at, k.ended_at,
    case
      when k.ended_at is null and public._call_active_count(k.id) > 0 then 'live'
      when k.answered_at is null then 'missed'
      else 'ended'
    end,
    public._call_active_count(k.id)
  from public.calls k
  where k.conversation_id = p_conversation and public._is_member(p_conversation)
  order by k.started_at desc
  limit 100;
$$;

drop function public.fn_my_conversations();
create function public.fn_my_conversations()
returns table (
  id uuid, kind text, title text, site_id uuid, is_default boolean,
  last_message_at timestamptz, last_message_preview text, unread integer,
  member_count integer, other_user_id uuid, pinned boolean, last_read_at timestamptz,
  call_live boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.kind,
    case when c.kind = 'direct' then coalesce(nullif(op.full_name, ''), 'Direct chat') else c.title end,
    c.site_id, c.is_default, c.last_message_at, c.last_message_preview,
    (select count(*)::int from public.messages msg
      where msg.conversation_id = c.id and not msg.is_archived
        and msg.created_at > me.last_read_at and msg.author_id is distinct from auth.uid()),
    (select count(*)::int from public.conversation_members m2
      where m2.conversation_id = c.id and not m2.is_archived),
    o.user_id,
    me.pinned,
    me.last_read_at,
    exists (select 1 from public.calls k
      where k.conversation_id = c.id and k.ended_at is null and public._call_active_count(k.id) > 0)
  from public.conversation_members me
  join public.conversations c on c.id = me.conversation_id and not c.is_archived
  left join lateral (
    select m.user_id from public.conversation_members m
    where c.kind = 'direct' and m.conversation_id = c.id and m.user_id <> auth.uid()
    limit 1
  ) o on true
  left join public.profiles op on op.id = o.user_id
  where me.user_id = auth.uid() and not me.is_archived and public._active()
  order by me.pinned desc, coalesce(c.last_message_at, c.created_at) desc;
$$;

revoke execute on function
  public._call_active_count(uuid),
  public._close_call(uuid),
  public.fn_start_call(uuid, boolean),
  public.fn_call_heartbeat(uuid),
  public.fn_leave_call(uuid),
  public.fn_conversation_calls(uuid),
  public.fn_my_conversations()
from public, anon;
revoke execute on function public._close_call(uuid) from authenticated;
grant execute on function
  public._call_active_count(uuid),
  public.fn_start_call(uuid, boolean),
  public.fn_call_heartbeat(uuid),
  public.fn_leave_call(uuid),
  public.fn_conversation_calls(uuid),
  public.fn_my_conversations()
to authenticated;

alter table public.calls enable row level security;
alter table public.call_participants enable row level security;
create policy calls_select on public.calls for select to authenticated
  using (public._is_member(conversation_id));
create policy call_participants_select on public.call_participants for select to authenticated
  using (public._is_member(conversation_id));
revoke all on public.calls, public.call_participants from anon;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.calls, public.call_participants;
  end if;
end;
$$;
