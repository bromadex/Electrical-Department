-- 0046_chat_extras: chat Phase 3 (docs/plan-chat-and-calls.md).
--
-- * Video messages: messages.kind 'video' (file in chat-files like photos).
-- * Edit: your own text messages within 15 minutes (fn_edit_message);
--   messages.edited_at shows "edited".
-- * Star: message_stars, one per message and person (fn_star_message).
-- * Mute: conversation_members.muted_until (fn_mute_conversation; 'infinity'
--   for always). A muted chat sends no push for ordinary messages; the
--   unread count stays. Mentions still push.
-- * Archive: conversation_members.archived_at (fn_archive_conversation);
--   fn_my_conversations says archived until a newer message arrives.
-- * Last seen: profiles.last_seen_at, set by the app when it goes to the
--   background or closes (fn_seen).
-- * Group info: conversations.description and photo_path (in chat-files
--   under <chat>/group/), changed by the owner or chat.manage
--   (fn_update_group_info).

alter table public.messages drop constraint messages_kind_check;
alter table public.messages add constraint messages_kind_check
  check (kind in ('text', 'photo', 'voice', 'file', 'record', 'system', 'video'));
alter table public.messages add column edited_at timestamptz;
alter table public.conversation_members add column muted_until timestamptz;
alter table public.conversation_members add column archived_at timestamptz;
alter table public.profiles add column last_seen_at timestamptz;
alter table public.conversations add column description text
  check (description is null or length(description) <= 500);
alter table public.conversations add column photo_path text;

create table public.message_stars (
  message_id uuid not null references public.messages (id),
  conversation_id uuid not null references public.conversations (id),
  user_id uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);
create index message_stars_conversation_idx on public.message_stars (conversation_id);
create index message_stars_user_idx on public.message_stars (user_id, created_at desc);
alter table public.message_stars enable row level security;
create policy message_stars_select on public.message_stars for select to authenticated
  using (user_id = auth.uid() and public._is_member(conversation_id));
revoke all on public.message_stars from anon;
revoke insert, update, delete on public.message_stars from authenticated;

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
    s.attachment_name, s.attachment_size, s.duration_ms, null, s.record_link, null
  );
  update public.messages set forwarded = true where id = v.id returning * into v;
  return v;
end;
$$;

drop function public.fn_my_conversations();
create function public.fn_my_conversations()
returns table (
  id uuid, kind text, title text, site_id uuid, is_default boolean,
  last_message_at timestamptz, last_message_preview text, unread integer,
  member_count integer, other_user_id uuid, pinned boolean, last_read_at timestamptz,
  call_live boolean, muted_until timestamptz, archived boolean, description text,
  photo_path text
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
      where k.conversation_id = c.id and k.ended_at is null and public._call_active_count(k.id) > 0),
    case when me.muted_until > now() then me.muted_until end,
    me.archived_at is not null and coalesce(c.last_message_at, c.created_at) <= me.archived_at,
    c.description,
    c.photo_path
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

create or replace function public.fn_notifications_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.push_config;
begin
  select * into c from public.push_config limit 1;
  if c.endpoint is null or not exists (
    select 1 from public.device_tokens d where d.user_id = new.user_id and not d.is_archived
  ) then
    return new;
  end if;
  -- A muted chat sends no push for ordinary messages (mentions still do).
  if new.type = 'chat' and new.link like 'chat:%' and exists (
    select 1 from public.conversation_members m
    where m.user_id = new.user_id and m.muted_until > now()
      and m.conversation_id::text = substr(new.link, 6)
  ) then
    return new;
  end if;
  perform net.http_post(
    url := c.endpoint,
    body := jsonb_build_object('notification_id', new.id),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', c.secret),
    timeout_milliseconds := 5000
  );
  return new;
exception when others then
  -- A push problem must never stop the notification itself.
  return new;
end;
$$;

-- Edits your own text message within 15 minutes of sending it.
create function public.fn_edit_message(p_message uuid, p_body text)
returns public.messages
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.messages;
  v_author text;
begin
  select * into v from public.messages where id = p_message and not is_archived for update;
  if not found or v.author_id is distinct from auth.uid() then
    raise exception 'NOT_FOUND: Message not found';
  end if;
  if v.kind <> 'text' then
    raise exception 'INVALID: Only text messages can be edited';
  end if;
  if v.created_at < now() - interval '15 minutes' then
    raise exception 'INVALID: Messages can be edited for 15 minutes';
  end if;
  if length(trim(coalesce(p_body, ''))) = 0 then
    raise exception 'INVALID: Message is empty';
  end if;
  update public.messages set body = trim(p_body), edited_at = now()
  where id = p_message returning * into v;
  -- Still the newest message: the chat list shows the new text.
  if not exists (
    select 1 from public.messages m
    where m.conversation_id = v.conversation_id and m.created_at > v.created_at and not m.is_archived
  ) then
    select coalesce(nullif(full_name, ''), 'Someone') into v_author
    from public.profiles where id = auth.uid();
    update public.conversations set last_message_preview = v_author || ': ' || left(v.body, 120)
    where id = v.conversation_id;
  end if;
  return v;
end;
$$;

create function public.fn_star_message(p_message uuid, p_on boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.messages;
begin
  select * into v from public.messages where id = p_message and not is_archived;
  if not found or not public._is_member(v.conversation_id) then
    raise exception 'NOT_FOUND: Message not found';
  end if;
  if coalesce(p_on, true) then
    insert into public.message_stars (message_id, conversation_id, user_id)
    values (p_message, v.conversation_id, auth.uid())
    on conflict do nothing;
  else
    delete from public.message_stars where message_id = p_message and user_id = auth.uid();
  end if;
  return coalesce(p_on, true);
end;
$$;

-- p_until: when the mute ends; 'infinity' for always; null unmutes.
create function public.fn_mute_conversation(p_conversation uuid, p_until timestamptz)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.conversation_members set muted_until = p_until
  where conversation_id = p_conversation and user_id = auth.uid() and not is_archived;
  if not found then
    raise exception 'NOT_FOUND: Chat not found';
  end if;
end;
$$;

create function public.fn_archive_conversation(p_conversation uuid, p_on boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.conversation_members
  set archived_at = case when coalesce(p_on, true) then now() end,
      pinned = case when coalesce(p_on, true) then false else pinned end
  where conversation_id = p_conversation and user_id = auth.uid() and not is_archived;
  if not found then
    raise exception 'NOT_FOUND: Chat not found';
  end if;
end;
$$;

-- The app went to the background or closed: "last seen".
create function public.fn_seen()
returns void
language sql
security definer
set search_path = ''
as $$
  update public.profiles set last_seen_at = now() where id = auth.uid();
$$;

create function public.fn_update_group_info(
  p_conversation uuid,
  p_description text,
  p_photo_path text
)
returns public.conversations
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.conversations;
begin
  select * into v from public.conversations where id = p_conversation and not is_archived;
  if not found or not public._is_member(v.id) then
    raise exception 'NOT_FOUND: Chat not found';
  end if;
  if v.kind <> 'group' then
    raise exception 'INVALID: Direct chats have no group info';
  end if;
  if not (
    public._can('chat.manage', v.site_id)
    or exists (select 1 from public.conversation_members
               where conversation_id = v.id and user_id = auth.uid() and role = 'owner')
  ) then
    raise exception 'NOT_ALLOWED: Only the group owner or a supervisor can change it';
  end if;
  if p_photo_path is not null and p_photo_path <> ''
     and split_part(p_photo_path, '/', 1) <> v.id::text then
    raise exception 'INVALID: The picture must be in the chat''s folder';
  end if;
  update public.conversations
  set description = case when p_description is null then description
                         else nullif(trim(p_description), '') end,
      photo_path = case when p_photo_path is null then photo_path
                        else nullif(p_photo_path, '') end
  where id = v.id returning * into v;
  return v;
end;
$$;

revoke execute on function
  public.fn_edit_message(uuid, text),
  public.fn_star_message(uuid, boolean),
  public.fn_mute_conversation(uuid, timestamptz),
  public.fn_archive_conversation(uuid, boolean),
  public.fn_seen(),
  public.fn_update_group_info(uuid, text, text),
  public.fn_my_conversations()
from public, anon;
grant execute on function
  public.fn_edit_message(uuid, text),
  public.fn_star_message(uuid, boolean),
  public.fn_mute_conversation(uuid, timestamptz),
  public.fn_archive_conversation(uuid, boolean),
  public.fn_seen(),
  public.fn_update_group_info(uuid, text, text),
  public.fn_my_conversations()
to authenticated;

insert into public.schema_migrations (filename) values ('0046_chat_extras.sql')
on conflict do nothing;
