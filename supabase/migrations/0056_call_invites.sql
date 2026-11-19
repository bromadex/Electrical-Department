-- 0056_call_invites: add anyone to a call, also a one-to-one call.
--
-- Someone in a live call can ring people who are not in the chat (a
-- direct chat has only two). They are invited to that call only: their
-- phone rings, fn_start_call lets them join the live call (never start a
-- new one), and they see the call but not the chat's messages. Members of
-- the chat are rung as before (fn_call_ring). Invites end with the call.

create table public.call_invites (
  call_id uuid not null references public.calls (id),
  user_id uuid not null references public.profiles (id),
  invited_by uuid not null references public.profiles (id) default auth.uid(),
  created_at timestamptz not null default now(),
  primary key (call_id, user_id)
);
create index call_invites_user_idx on public.call_invites (user_id);
create index call_invites_invited_by_idx on public.call_invites (invited_by);
alter table public.call_invites enable row level security;
create policy call_invites_select on public.call_invites for select to authenticated
  using (user_id = auth.uid() or exists (
    select 1 from public.calls k
    where k.id = call_invites.call_id and public._is_member(k.conversation_id)));
revoke all on public.call_invites from anon;
revoke insert, update, delete on public.call_invites from authenticated;

-- Was the caller invited to this call? (Reads call_invites without its
-- row security, so the calls policy below does not loop back into it.)
create function public._invited_to_call(p_call uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.call_invites where call_id = p_call and user_id = auth.uid());
$$;
revoke execute on function public._invited_to_call(uuid) from public, anon;
grant execute on function public._invited_to_call(uuid) to authenticated;

-- Someone invited sees the call they were invited to (and who is in it).
create policy calls_select_invited on public.calls for select to authenticated
  using (public._invited_to_call(id));
create policy call_participants_select_invited on public.call_participants
  for select to authenticated
  using (public._invited_to_call(call_id));

-- Rings people into the caller's live call in this chat: members as
-- before, anyone else the caller may chat with as an invited guest.
-- Returns how many were rung.
create function public.fn_call_invite(p_conversation uuid, p_users uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.conversations;
  k public.calls;
  v_name text;
  u uuid;
  n integer := 0;
begin
  select * into c from public.conversations where id = p_conversation and not is_archived;
  if not found or not public._is_member(p_conversation) then
    raise exception 'NOT_FOUND: Chat not found';
  end if;
  select * into k from public.calls
  where conversation_id = p_conversation and ended_at is null
  order by started_at desc limit 1;
  if not found or not exists (
    select 1 from public.call_participants cp
    where cp.call_id = k.id and cp.user_id = auth.uid() and cp.left_at is null
  ) then
    raise exception 'INVALID: Join the call first';
  end if;
  if coalesce(array_length(p_users, 1), 0) > 20 then
    raise exception 'INVALID: Add up to 20 people at a time';
  end if;
  select coalesce(nullif(full_name, ''), 'Someone') into v_name
  from public.profiles where id = auth.uid();
  foreach u in array coalesce(p_users, '{}') loop
    continue when u = auth.uid();
    continue when not exists (
      select 1 from public.profiles p where p.id = u and p.active and not p.is_archived);
    -- Already in the call: nothing to do.
    continue when exists (
      select 1 from public.call_participants cp
      where cp.call_id = k.id and cp.user_id = u and cp.left_at is null
        and cp.last_seen_at > now() - interval '90 seconds');
    if not exists (
      select 1 from public.conversation_members m
      where m.conversation_id = p_conversation and m.user_id = u and not m.is_archived
    ) then
      continue when not public._user_can_chat(u, c.site_id);
      insert into public.call_invites (call_id, user_id) values (k.id, u)
      on conflict do nothing;
    end if;
    insert into public.notifications (user_id, site_id, type, title, body, link)
    values (u, c.site_id, 'call', v_name, 'Asks you to join a call', 'call:' || p_conversation);
    n := n + 1;
  end loop;
  return n;
end;
$$;

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
  v_invited boolean;
begin
  select * into c from public.conversations where id = p_conversation and not is_archived;
  -- Members, or someone added to the live call (fn_call_invite).
  v_invited := exists (
    select 1 from public.call_invites i
    join public.calls x on x.id = i.call_id
    where x.conversation_id = p_conversation and x.ended_at is null
      and i.user_id = auth.uid()
  );
  if not found or not (public._is_member(p_conversation) or v_invited) then
    raise exception 'NOT_FOUND: Chat not found';
  end if;
  if v_invited and not public._is_member(p_conversation) then
    -- Joins the call only (never starts one); named after who called.
    select * into k from public.calls
    where conversation_id = p_conversation and ended_at is null
    order by started_at desc limit 1;
    if not found then
      raise exception 'NOT_FOUND: The call has ended';
    end if;
    select coalesce(nullif(full_name, ''), 'Someone') into v_name
    from public.profiles where id = auth.uid();
    insert into public.call_participants (call_id, conversation_id, user_id)
    values (k.id, p_conversation, auth.uid())
    on conflict (call_id, user_id) do update set last_seen_at = now(), left_at = null;
    if k.answered_at is null then
      update public.calls set answered_at = now() where id = k.id;
    end if;
    return jsonb_build_object(
      'room', 'chat-' || p_conversation,
      'identity', auth.uid(),
      'name', v_name,
      'title', 'Call with ' || coalesce((
        select nullif(full_name, '') from public.profiles where id = k.started_by), 'someone'),
      'call_id', k.id,
      'new_call', false
    );
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

revoke execute on function public.fn_call_invite(uuid, uuid[]) from public, anon;
grant execute on function public.fn_call_invite(uuid, uuid[]) to authenticated;

insert into public.schema_migrations (filename) values ('0056_call_invites.sql')
on conflict do nothing;
