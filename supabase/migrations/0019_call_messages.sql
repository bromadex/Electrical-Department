-- 0019_call_messages: starting a call also posts a row in the chat
-- ("Clement started a call", record_link call:<chat>) so the call shows in
-- the conversation and the chat list, with a Join button in the app. Same
-- 30-minute rule as the notification: rejoining posts nothing.

create or replace function public.fn_start_call(p_conversation uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.conversations;
  v_call public.conversation_calls;
  v_name text;
  v_title text;
  v_new boolean;
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

  select * into v_call from public.conversation_calls
  where conversation_id = p_conversation for update;
  v_new := not found or v_call.last_joined_at < now() - interval '30 minutes';
  insert into public.conversation_calls as k (conversation_id, started_by, started_at, last_joined_at)
  values (p_conversation, auth.uid(), now(), now())
  on conflict (conversation_id) do update set
    started_by = case when v_new then excluded.started_by else k.started_by end,
    started_at = case when v_new then excluded.started_at else k.started_at end,
    last_joined_at = now();

  if c.kind = 'direct' then
    v_title := v_name;
  else
    v_title := coalesce(c.title, 'Chat');
  end if;

  if v_new then
    -- A row in the chat, so the call shows where people talk.
    insert into public.messages (conversation_id, author_id, kind, body, record_link)
    values (p_conversation, auth.uid(), 'system', v_name || ' started a call', 'call:' || p_conversation);
    update public.conversations
    set last_message_at = now(), last_message_preview = '📞 ' || v_name || ' started a call'
    where id = p_conversation;
    update public.conversation_members set last_read_at = now()
    where conversation_id = p_conversation and user_id = auth.uid();

    insert into public.notifications (user_id, site_id, type, title, body, link)
    select m.user_id, c.site_id, 'meeting',
      v_name || ' started a call',
      case when c.kind = 'direct' then 'Tap to join' else coalesce(c.title, 'Chat') || ' · tap to join' end,
      'call:' || p_conversation
    from public.conversation_members m
    join public.profiles p on p.id = m.user_id and p.active and not p.is_archived
    where m.conversation_id = p_conversation and not m.is_archived and m.user_id <> auth.uid();
  end if;

  return jsonb_build_object(
    'room', 'chat-' || p_conversation,
    'identity', auth.uid(),
    'name', v_name,
    'title', v_title,
    'new_call', v_new
  );
end;
$$;

