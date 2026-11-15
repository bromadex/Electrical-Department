-- 0044_chat_receipts_forward: chat Phase 1 (docs/plan-chat-and-calls.md).
--
-- Ticks like WhatsApp: a receipt per message and person, delivered when
-- the message reached their phone and read when they saw it. The sender's
-- ticks come from fn_message_ticks; message info (Read by, Delivered to)
-- from fn_message_info.
--   * Delivered: the app marks it when a message arrives while it runs
--     (fn_mark_delivered), when it starts or resumes (all chats), and when
--     a chat push reaches the phone in the background (push-received edge
--     function → fn_push_received, with the alert's id as proof).
--   * Read: opening a chat (fn_mark_conversation_read, unchanged signature)
--     now also marks every message in it read.
-- Delete for me: message_hidden hides a message for one person.
-- Forward: fn_forward_message copies a message into another chat (the app
-- copies the file first), marked forwarded.

create table public.message_receipts (
  message_id uuid not null references public.messages (id),
  conversation_id uuid not null references public.conversations (id),
  user_id uuid not null references public.profiles (id),
  delivered_at timestamptz not null default now(),
  read_at timestamptz,
  primary key (message_id, user_id)
);
create index message_receipts_conversation_idx on public.message_receipts (conversation_id);
create index message_receipts_user_idx on public.message_receipts (user_id);

create table public.message_hidden (
  message_id uuid not null references public.messages (id),
  conversation_id uuid not null references public.conversations (id),
  user_id uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);
create index message_hidden_conversation_idx on public.message_hidden (conversation_id, user_id);
create index message_hidden_user_idx on public.message_hidden (user_id);

alter table public.messages add column forwarded boolean not null default false;

alter table public.message_receipts enable row level security;
alter table public.message_hidden enable row level security;
create policy message_receipts_select on public.message_receipts for select to authenticated
  using (public._is_member(conversation_id));
create policy message_hidden_select on public.message_hidden for select to authenticated
  using (user_id = auth.uid());
revoke all on public.message_receipts, public.message_hidden from anon;
revoke insert, update, delete on public.message_receipts, public.message_hidden from authenticated;

-- Marks the caller's messages in a chat (from others, the last 30 days) as
-- delivered; p_read also marks them read. Returns how many changed.
create function public._receipt_upto(p_conversation uuid, p_user uuid, p_read boolean)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  n integer;
begin
  insert into public.message_receipts as r (message_id, conversation_id, user_id, delivered_at, read_at)
  select m.id, m.conversation_id, p_user, now(), case when p_read then now() end
  from public.messages m
  where m.conversation_id = p_conversation
    and m.author_id is distinct from p_user and m.kind <> 'system'
    and not m.is_archived and m.created_at > now() - interval '30 days'
  on conflict (message_id, user_id) do update
    set read_at = coalesce(r.read_at, excluded.read_at)
    where r.read_at is null and excluded.read_at is not null;
  get diagnostics n = row_count;
  return n;
end;
$$;

-- Delivered to this phone: one chat, or (null) every chat of the caller.
create function public.fn_mark_delivered(p_conversation uuid default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  c uuid;
  n integer := 0;
begin
  for c in
    select cm.conversation_id from public.conversation_members cm
    where cm.user_id = auth.uid() and not cm.is_archived
      and (p_conversation is null or cm.conversation_id = p_conversation)
  loop
    n := n + public._receipt_upto(c, auth.uid(), false);
  end loop;
  return n;
end;
$$;

-- Opening a chat: read up to now (as before), and every message read.
create or replace function public.fn_mark_conversation_read(p_conversation uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.conversation_members set last_read_at = now()
  where conversation_id = p_conversation and user_id = auth.uid();
  update public.notifications set read_at = now()
  where user_id = auth.uid() and type = 'chat' and read_at is null
    and link = 'chat:' || p_conversation;
  if public._is_member(p_conversation) then
    perform public._receipt_upto(p_conversation, auth.uid(), true);
  end if;
end;
$$;

-- The sender's ticks for their own latest messages in a chat: how many
-- people should get each one (members when it was sent, apart from the
-- sender), and how many have it and have read it.
create function public.fn_message_ticks(p_conversation uuid)
returns table (message_id uuid, recipients integer, delivered integer, read integer)
language sql
stable
security definer
set search_path = ''
as $$
  select m.id,
    (select count(*) from public.conversation_members cm
      where cm.conversation_id = m.conversation_id and cm.user_id <> m.author_id
        and cm.joined_at <= m.created_at and not cm.is_archived)::integer,
    (select count(*) from public.message_receipts r where r.message_id = m.id)::integer,
    (select count(*) from public.message_receipts r where r.message_id = m.id and r.read_at is not null)::integer
  from public.messages m
  where m.conversation_id = p_conversation and m.author_id = auth.uid()
    and m.kind <> 'system' and not m.is_archived
    and public._is_member(p_conversation)
  order by m.created_at desc
  limit 200;
$$;

-- Message info: each person who should get the message, with when it
-- reached them and when they read it.
create function public.fn_message_info(p_message uuid)
returns table (user_id uuid, full_name text, delivered_at timestamptz, read_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select cm.user_id, coalesce(nullif(p.full_name, ''), 'Someone'), r.delivered_at, r.read_at
  from public.messages m
  join public.conversation_members cm on cm.conversation_id = m.conversation_id
    and cm.user_id <> m.author_id and cm.joined_at <= m.created_at and not cm.is_archived
  join public.profiles p on p.id = cm.user_id
  left join public.message_receipts r on r.message_id = m.id and r.user_id = cm.user_id
  where m.id = p_message and public._is_member(m.conversation_id)
  order by r.read_at desc nulls last, r.delivered_at desc nulls last, p.full_name;
$$;

-- A chat push reached the phone (push-received edge function, service role
-- only): the alert's id is the proof. Chat alerts mark that chat
-- delivered for the person; call alerts mark the call ringing (0043).
create function public.fn_push_received(p_notification uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  n public.notifications;
begin
  select * into n from public.notifications
  where id = p_notification and created_at > now() - interval '7 days';
  if not found or n.link is null then
    return false;
  end if;
  if n.type = 'call' then
    return public.fn_call_rang(p_notification);
  end if;
  if n.type in ('chat', 'mentioned') and n.link like 'chat:%' then
    perform public._receipt_upto(substr(n.link, 6)::uuid, n.user_id, false);
    return true;
  end if;
  return false;
end;
$$;

-- Delete for me: hides messages for the caller only.
create function public.fn_hide_messages(p_messages uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  n integer;
begin
  insert into public.message_hidden (message_id, conversation_id, user_id)
  select m.id, m.conversation_id, auth.uid()
  from public.messages m
  where m.id = any (coalesce(p_messages, '{}')) and public._is_member(m.conversation_id)
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end;
$$;

-- Forwards one message into another chat as the caller's own message,
-- marked forwarded. For photos, voice notes and files the app first copies
-- the file into the target chat's folder and passes its path.
create function public.fn_forward_message(
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
    case when s.kind in ('photo', 'voice', 'file') then p_attachment_path end,
    s.attachment_name, s.attachment_size, s.duration_ms, null, s.record_link, null
  );
  update public.messages set forwarded = true where id = v.id returning * into v;
  return v;
end;
$$;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.message_receipts;
  end if;
end;
$$;

revoke execute on function
  public._receipt_upto(uuid, uuid, boolean),
  public.fn_push_received(uuid)
from public, anon, authenticated;
grant execute on function public.fn_push_received(uuid) to service_role;

revoke execute on function
  public.fn_mark_delivered(uuid),
  public.fn_message_ticks(uuid),
  public.fn_message_info(uuid),
  public.fn_hide_messages(uuid[]),
  public.fn_forward_message(uuid, uuid, uuid, text)
from public, anon;
grant execute on function
  public.fn_mark_delivered(uuid),
  public.fn_message_ticks(uuid),
  public.fn_message_info(uuid),
  public.fn_hide_messages(uuid[]),
  public.fn_forward_message(uuid, uuid, uuid, text)
to authenticated;

insert into public.schema_migrations (filename) values ('0044_chat_receipts_forward.sql')
on conflict do nothing;
