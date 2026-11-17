-- 0053_message_links: tag files and records inside a chat message.
--
-- Typing # in chat suggests documents, job cards and other records; each
-- one picked stays in the text as a highlighted label (e.g. "#LOTO
-- procedure") and is kept in messages.links as {"label", "link"}, where
-- link is doc:<id>, jobcard:<id>, asset:<id>, tool:<id>, item:<id>,
-- project:<id>, mr:<id> or po:<id>. Nothing is uploaded or copied: the
-- message points at the record, so a document opens at its newest version.
-- Up to 10 per message. Forwarding keeps them.

alter table public.messages add column links jsonb not null default '[]'
  check (jsonb_typeof(links) = 'array' and jsonb_array_length(links) <= 10);

-- Where a document or record is tagged (Properties → "Tagged in").
create index messages_links_idx on public.messages using gin (links jsonb_path_ops);

-- Keeps only well-formed {label, link} pairs, without repeats.
create function public._clean_links(p_links jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  e jsonb;
  out jsonb := '[]';
  seen text[] := '{}';
  v_label text;
  v_link text;
begin
  if p_links is null or jsonb_typeof(p_links) <> 'array' then
    return '[]';
  end if;
  if jsonb_array_length(p_links) > 10 then
    raise exception 'INVALID: Tag up to 10 things in one message';
  end if;
  for e in select * from jsonb_array_elements(p_links) loop
    v_label := trim(coalesce(e ->> 'label', ''));
    v_link := coalesce(e ->> 'link', '');
    if v_link !~ '^(jobcard|job|asset|tool|doc|item|project|mr|po):[0-9a-f-]{36}$' then
      raise exception 'INVALID: A tag must look like doc:<uuid>';
    end if;
    if length(v_label) not between 2 and 80 then
      raise exception 'INVALID: A tag needs a short name';
    end if;
    if not (v_link = any (seen)) then
      seen := seen || v_link;
      out := out || jsonb_build_array(jsonb_build_object('label', v_label, 'link', v_link));
    end if;
  end loop;
  return out;
end;
$$;

-- The send function gains p_links (optional, so older apps keep working).
drop function public.fn_send_message(uuid, uuid, text, text, text, text, integer, integer, uuid, text, uuid[]);
create function public.fn_send_message(
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

-- Forwarding keeps the tags.
create or replace function public.fn_forward_message(
  p_client_ref uuid,
  p_message uuid,
  p_conversation uuid,
  p_attachment_path text
)
returns public.messages
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.messages;
  v public.messages;
begin
  select * into v from public.messages where id = p_client_ref;
  if found then
    return v;
  end if;
  select * into s from public.messages where id = p_message and not is_archived;
  if not found or not public._is_member(s.conversation_id) then
    raise exception 'NOT_FOUND: Message not found';
  end if;
  if s.kind = 'system' then
    raise exception 'INVALID: This message cannot be forwarded';
  end if;
  v := public.fn_send_message(
    p_client_ref, p_conversation, s.kind, s.body,
    case when s.kind in ('photo', 'voice', 'file', 'video') then p_attachment_path end,
    s.attachment_name, s.attachment_size, s.duration_ms, null, s.record_link, null, s.links
  );
  update public.messages set forwarded = true where id = v.id returning * into v;
  return v;
end;
$$;

-- Where a document is tagged, in chats the caller is in: newest first.
create function public.fn_document_mentions(p_document uuid)
returns table (message_id uuid, conversation_id uuid, conversation_title text,
  author_name text, created_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select m.id, m.conversation_id,
    case when c.kind = 'direct' then coalesce(o.full_name, 'Direct chat') else coalesce(c.title, 'Chat') end,
    coalesce(nullif(a.full_name, ''), 'Someone'), m.created_at
  from public.messages m
  join public.conversations c on c.id = m.conversation_id
  left join public.profiles a on a.id = m.author_id
  left join lateral (
    select p.full_name from public.conversation_members cm
    join public.profiles p on p.id = cm.user_id
    where cm.conversation_id = c.id and cm.user_id <> auth.uid()
    limit 1
  ) o on c.kind = 'direct'
  where not m.is_archived
    and public._is_member(m.conversation_id)
    and (m.links @> jsonb_build_array(jsonb_build_object('link', 'doc:' || p_document))
      or m.record_link = 'doc:' || p_document)
  order by m.created_at desc
  limit 50;
$$;

revoke execute on function public._clean_links(jsonb) from public, anon;
revoke execute on function
  public.fn_send_message(uuid, uuid, text, text, text, text, integer, integer, uuid, text, uuid[], jsonb),
  public.fn_document_mentions(uuid)
from public, anon;
grant execute on function
  public.fn_send_message(uuid, uuid, text, text, text, text, integer, integer, uuid, text, uuid[], jsonb),
  public.fn_document_mentions(uuid)
to authenticated;

insert into public.schema_migrations (filename) values ('0053_message_links.sql')
on conflict do nothing;
