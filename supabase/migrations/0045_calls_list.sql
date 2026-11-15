-- 0045_calls_list: calls Phase 2 (docs/plan-chat-and-calls.md).
--
-- Calls list: every call in the caller's chats, newest first, as outgoing
-- (you started it), incoming (you joined) or missed (you did not join),
-- with how long it lasted. call_log_seen remembers when you last opened the
-- list, for the missed-call badge.

create table public.call_log_seen (
  user_id uuid primary key references public.profiles (id),
  seen_at timestamptz not null default now()
);
alter table public.call_log_seen enable row level security;
create policy call_log_seen_select on public.call_log_seen for select to authenticated
  using (user_id = auth.uid());
revoke all on public.call_log_seen from anon;
revoke insert, update, delete on public.call_log_seen from authenticated;

-- The caller's calls across chats, newest first.
create function public.fn_my_calls(p_limit integer default 100)
returns table (
  call_id uuid, conversation_id uuid, title text, is_direct boolean, other_user_id uuid,
  video boolean, direction text, started_by uuid, started_at timestamptz,
  answered_at timestamptz, ended_at timestamptz, seconds integer, live boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select k.id, c.id,
    case when c.kind = 'direct' then coalesce(nullif(op.full_name, ''), 'Direct chat')
      else coalesce(c.title, 'Chat') end,
    c.kind = 'direct', o.user_id, k.video,
    case when k.started_by = auth.uid() then 'outgoing'
      when cp.user_id is not null then 'incoming'
      else 'missed' end,
    k.started_by, k.started_at, k.answered_at, k.ended_at,
    case when k.answered_at is null then 0
      else greatest(0, extract(epoch from coalesce(k.ended_at, now()) - k.answered_at))::integer end,
    k.ended_at is null and public._call_active_count(k.id) > 0
  from public.conversation_members me
  join public.conversations c on c.id = me.conversation_id and not c.is_archived
  join public.calls k on k.conversation_id = c.id and k.started_at >= me.joined_at
  left join public.call_participants cp on cp.call_id = k.id and cp.user_id = auth.uid()
  left join lateral (
    select m.user_id from public.conversation_members m
    where c.kind = 'direct' and m.conversation_id = c.id and m.user_id <> auth.uid()
    limit 1
  ) o on true
  left join public.profiles op on op.id = o.user_id
  where me.user_id = auth.uid() and not me.is_archived and public._active()
  order by k.started_at desc
  limit least(greatest(coalesce(p_limit, 100), 1), 300);
$$;

-- Missed calls since the calls list was last opened.
create function public.fn_missed_call_count()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer from public.fn_my_calls(300) x
  where x.direction = 'missed' and not x.live
    and x.started_at > coalesce(
      (select s.seen_at from public.call_log_seen s where s.user_id = auth.uid()),
      '-infinity'::timestamptz);
$$;

-- Opening the calls list clears the badge.
create function public.fn_calls_seen()
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.call_log_seen (user_id, seen_at) values (auth.uid(), now())
  on conflict (user_id) do update set seen_at = excluded.seen_at;
$$;

revoke execute on function
  public.fn_my_calls(integer),
  public.fn_missed_call_count(),
  public.fn_calls_seen()
from public, anon;
grant execute on function
  public.fn_my_calls(integer),
  public.fn_missed_call_count(),
  public.fn_calls_seen()
to authenticated;

insert into public.schema_migrations (filename) values ('0045_calls_list.sql')
on conflict do nothing;
