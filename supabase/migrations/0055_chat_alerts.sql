-- 0055_chat_alerts: every chat message reaches the phone.
--
-- Until now a chat sent one alert and then nothing more until it was opened
-- in the app, so swiping that alert away silenced the chat. Now each
-- message replaces the chat's unread alert with a new one (pushed again,
-- with the newest text), and muted chats send none (an @mention still
-- does). push-send sends chat alerts at high priority.

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
  p_mentions uuid[],
  p_links jsonb default null
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
  v_links jsonb := public._clean_links(p_links);
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
  if p_kind not in ('text', 'photo', 'voice', 'file', 'record', 'video') then
    raise exception 'INVALID: Unknown message kind';
  end if;
  if p_kind = 'text' and length(trim(coalesce(p_body, ''))) = 0 then
    raise exception 'INVALID: Message is empty';
  end if;
  if p_kind in ('photo', 'voice', 'file', 'video') and (
    p_attachment_path is null or split_part(p_attachment_path, '/', 1) <> p_conversation::text
  ) then
    raise exception 'INVALID: Attachment path must start with the chat id';
  end if;
  if p_kind = 'record' and p_record_link !~ '^(jobcard|job|asset|tool|doc|item|project|mr|po):[0-9a-f-]{36}$' then
    raise exception 'INVALID: Record link must look like job:<uuid>';
  end if;

  insert into public.messages (
    id, conversation_id, author_id, kind, body, attachment_path, attachment_name,
    attachment_size, duration_ms, reply_to, record_link, mentions, links
  ) values (
    p_client_ref, p_conversation, auth.uid(), p_kind, nullif(trim(coalesce(p_body, '')), ''),
    p_attachment_path, p_attachment_name, p_attachment_size, p_duration_ms, p_reply_to,
    p_record_link, coalesce(p_mentions, '{}'), v_links
  )
  returning * into v;

  select coalesce(nullif(full_name, ''), 'Someone') into v_author
  from public.profiles where id = auth.uid();
  v_preview := v_author || ': ' || case p_kind
    when 'photo' then '📷 Photo'
    when 'voice' then '🎤 Voice note'
    when 'video' then '🎥 Video'
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

  -- Everyone else (not muted) hears every message, as on WhatsApp: the
  -- chat's unread alert is replaced by one for the newest message, so each
  -- message pushes once and the alerts list keeps one line per chat.
  delete from public.notifications n
  using public.conversation_members m
  where m.conversation_id = p_conversation and n.user_id = m.user_id
    and m.user_id <> auth.uid()
    and n.type = 'chat' and n.read_at is null
    and n.link = 'chat:' || p_conversation;
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
    and (m.muted_until is null or m.muted_until <= now());
  return v;
end;
$$;


insert into public.schema_migrations (filename) values ('0055_chat_alerts.sql')
on conflict do nothing;
