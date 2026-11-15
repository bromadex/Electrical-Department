-- 0049_chat_list: the chat list like WhatsApp for iPhone
-- (docs/plan-whatsapp-theme.md, Phase C).
--
-- * Favourites: conversation_members.favourite (fn_favourite_conversation),
--   for the Favourites filter.
-- * fn_my_conversations also returns favourite, mentions (unread @mentions
--   of you in that chat), and the last message's author and kind, and when
--   it is yours its tick (sent, delivered to everyone, read by everyone),
--   so the list shows ticks and "You:" like WhatsApp.

alter table public.conversation_members add column favourite boolean not null default false;

drop function public.fn_my_conversations();
create function public.fn_my_conversations()
returns table (
  id uuid, kind text, title text, site_id uuid, is_default boolean,
  last_message_at timestamptz, last_message_preview text, unread integer,
  member_count integer, other_user_id uuid, pinned boolean, last_read_at timestamptz,
  call_live boolean, muted_until timestamptz, archived boolean, description text,
  photo_path text, favourite boolean, mentions integer, last_author_id uuid,
  last_kind text, last_tick text
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
    c.photo_path,
    me.favourite,
    (select count(*)::int from public.notifications n
      where n.user_id = auth.uid() and n.type = 'mentioned' and n.read_at is null
        and n.link = 'chat:' || c.id),
    lm.author_id,
    lm.kind,
    case when lm.author_id = auth.uid() then (
      select case
        when x.recipients > 0 and x.seen >= x.recipients then 'read'
        when x.recipients > 0 and x.got >= x.recipients then 'delivered'
        else 'sent' end
      from (select
        (select count(*) from public.conversation_members cm
          where cm.conversation_id = c.id and cm.user_id <> lm.author_id
            and cm.joined_at <= lm.created_at and not cm.is_archived) as recipients,
        (select count(*) from public.message_receipts r where r.message_id = lm.id) as got,
        (select count(*) from public.message_receipts r
          where r.message_id = lm.id and r.read_at is not null) as seen) x)
    end
  from public.conversation_members me
  join public.conversations c on c.id = me.conversation_id and not c.is_archived
  left join lateral (
    select m.user_id from public.conversation_members m
    where c.kind = 'direct' and m.conversation_id = c.id and m.user_id <> auth.uid()
    limit 1
  ) o on true
  left join public.profiles op on op.id = o.user_id
  left join lateral (
    select m.id, m.author_id, m.kind, m.created_at from public.messages m
    where m.conversation_id = c.id and not m.is_archived and m.kind <> 'system'
    order by m.created_at desc limit 1
  ) lm on true
  where me.user_id = auth.uid() and not me.is_archived and public._active()
  order by me.pinned desc, coalesce(c.last_message_at, c.created_at) desc;
$$;

create function public.fn_favourite_conversation(p_conversation uuid, p_on boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.conversation_members set favourite = coalesce(p_on, true)
  where conversation_id = p_conversation and user_id = auth.uid() and not is_archived;
  if not found then
    raise exception 'NOT_FOUND: Chat not found';
  end if;
end;
$$;

revoke execute on function
  public.fn_my_conversations(),
  public.fn_favourite_conversation(uuid, boolean)
from public, anon;
grant execute on function
  public.fn_my_conversations(),
  public.fn_favourite_conversation(uuid, boolean)
to authenticated;

insert into public.schema_migrations (filename) values ('0049_chat_list.sql')
on conflict do nothing;
