-- 0047_call_add_people: meetings Phase 4 (docs/plan-chat-and-calls.md).
--
-- Add people to a running call: someone in the call rings other members
-- of the chat. Their phones ring like a direct call (type 'call', link
-- call:<chat>); in a browser it is an ordinary alert. Only members of the
-- chat, only while the call is live, and only by someone in it.

create function public.fn_call_ring(p_conversation uuid, p_users uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.conversations;
  k public.calls;
  v_name text;
  n integer;
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
  select coalesce(nullif(full_name, ''), 'Someone') into v_name
  from public.profiles where id = auth.uid();
  insert into public.notifications (user_id, site_id, type, title, body, link)
  select m.user_id, c.site_id, 'call', v_name,
    case when c.kind = 'direct' then 'Incoming call'
      else 'Asks you to join the call in ' || coalesce(c.title, 'the chat') end,
    'call:' || p_conversation
  from public.conversation_members m
  join public.profiles p on p.id = m.user_id and p.active and not p.is_archived
  where m.conversation_id = p_conversation and not m.is_archived
    and m.user_id = any (coalesce(p_users, '{}'))
    and m.user_id <> auth.uid()
    and not exists (
      select 1 from public.call_participants cp
      where cp.call_id = k.id and cp.user_id = m.user_id and cp.left_at is null
        and cp.last_seen_at > now() - interval '90 seconds'
    );
  get diagnostics n = row_count;
  return n;
end;
$$;

revoke execute on function public.fn_call_ring(uuid, uuid[]) from public, anon;
grant execute on function public.fn_call_ring(uuid, uuid[]) to authenticated;

insert into public.schema_migrations (filename) values ('0047_call_add_people.sql')
on conflict do nothing;
