-- 0018_chat_pins: pin chats to the top of your list, and tell the app where
-- you stopped reading so a chat can open with a "New messages" line.
-- fn_my_conversations gains pinned and last_read_at and lists pinned chats
-- first.

alter table public.conversation_members
  add column pinned boolean not null default false;

-- Pins or unpins one of the caller's chats (only their own list changes).
create function public.fn_pin_conversation(p_conversation uuid, p_pinned boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.conversation_members set pinned = coalesce(p_pinned, false)
  where conversation_id = p_conversation and user_id = auth.uid() and not is_archived;
  if not found then
    raise exception 'NOT_FOUND: Chat not found';
  end if;
end;
$$;

drop function public.fn_my_conversations();
create function public.fn_my_conversations()
returns table (
  id uuid, kind text, title text, site_id uuid, is_default boolean,
  last_message_at timestamptz, last_message_preview text, unread integer,
  member_count integer, other_user_id uuid, pinned boolean, last_read_at timestamptz
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
    me.last_read_at
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
  public.fn_pin_conversation(uuid, boolean),
  public.fn_my_conversations()
from public, anon;
grant execute on function
  public.fn_pin_conversation(uuid, boolean),
  public.fn_my_conversations()
to authenticated;
