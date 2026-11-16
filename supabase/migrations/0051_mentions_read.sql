-- 0051_mentions_read: opening a chat also marks its @mention alerts read,
-- so the green @ in the chat list (0049) clears like the unread count.

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
  where user_id = auth.uid() and type in ('chat', 'mentioned') and read_at is null
    and link = 'chat:' || p_conversation;
  if public._is_member(p_conversation) then
    perform public._receipt_upto(p_conversation, auth.uid(), true);
  end if;
end;
$$;

insert into public.schema_migrations (filename) values ('0051_mentions_read.sql')
on conflict do nothing;
