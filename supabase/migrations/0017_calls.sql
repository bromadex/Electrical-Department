-- 0017_calls: voice and video calls in chats (LiveKit). A chat's call is the
-- LiveKit room "chat-<conversation id>". fn_start_call checks the caller is
-- in the chat, names the room, and tells the other members a call started
-- (at most once per 30 minutes per chat, so rejoining is quiet). The
-- livekit-token edge function calls it, then signs the room pass.

create table public.conversation_calls (
  conversation_id uuid primary key references public.conversations (id),
  started_by uuid references public.profiles (id),
  started_at timestamptz not null default now(),
  last_joined_at timestamptz not null default now()
);

create function public.fn_start_call(p_conversation uuid)
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

revoke execute on function public.fn_start_call(uuid) from public, anon;
grant execute on function public.fn_start_call(uuid) to authenticated;

alter table public.conversation_calls enable row level security;
create policy conversation_calls_select on public.conversation_calls for select to authenticated
  using (public._is_member(conversation_id));
revoke all on public.conversation_calls from anon;
revoke insert, update, delete on public.conversation_calls from authenticated;

insert into public.schema_migrations (filename) values ('0017_calls.sql')
on conflict do nothing;
