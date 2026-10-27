-- 0025_ringing_calls: a direct call rings the other person's phone. The
-- call alert gets its own type, call, which push-send sends to Android as
-- a high-priority data message; the app shows a full-screen incoming call
-- with a ringtone (flutter_callkit_incoming), even when it is closed.
-- Browsers still get an ordinary notification. Group calls are unchanged.

alter table public.notifications drop constraint notifications_type_check;
alter table public.notifications add constraint notifications_type_check check (type in (
  'assigned', 'mentioned', 'overdue', 'reminder', 'approval', 'low_stock', 'meeting', 'general', 'chat',
  'registered', 'critical', 'reassigned', 'on_hold', 'review', 'returned', 'closed', 'request',
  'escalation', 'call'
));

create or replace function public.fn_start_call(p_conversation uuid, p_video boolean default false)
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

    -- A direct call rings the other person's phone (type call); a group
    -- call is an ordinary alert.
    insert into public.notifications (user_id, site_id, type, title, body, link)
    select m.user_id, c.site_id, case when c.kind = 'direct' then 'call' else 'meeting' end,
      case when c.kind = 'direct'
        then v_name
        else v_name || case when p_video then ' started a video call' else ' started a call' end
      end,
      case when c.kind = 'direct'
        then case when p_video then 'Incoming video call' else 'Incoming call' end
        else coalesce(c.title, 'Chat') || ' · tap to join' end,
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
