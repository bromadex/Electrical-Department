-- 0052_polls: polls in chats, as on WhatsApp.
--
-- fn_create_poll posts the question as a chat message (kind text, body
-- "📊 <question>", record_link poll:<id>) and keeps the options in polls.
-- Members vote with fn_vote_poll (one option, or several when the poll
-- allows it; voting again replaces your vote, an empty list takes it back).
-- Everyone in the chat sees who voted for what, live.

create table public.polls (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id),
  message_id uuid references public.messages (id),
  question text not null check (length(trim(question)) between 1 and 300),
  options text[] not null check (cardinality(options) between 2 and 12),
  multiple boolean not null default false,
  created_by uuid not null references public.profiles (id) default auth.uid(),
  created_at timestamptz not null default now()
);
create index polls_conversation_idx on public.polls (conversation_id);
create index polls_message_idx on public.polls (message_id);
create index polls_created_by_idx on public.polls (created_by);

create table public.poll_votes (
  poll_id uuid not null references public.polls (id),
  user_id uuid not null references public.profiles (id),
  option integer not null check (option >= 0),
  voted_at timestamptz not null default now(),
  primary key (poll_id, user_id, option)
);
create index poll_votes_user_idx on public.poll_votes (user_id);

alter table public.polls enable row level security;
alter table public.poll_votes enable row level security;
create policy polls_select on public.polls for select to authenticated
  using (public._is_member(conversation_id));
create policy poll_votes_select on public.poll_votes for select to authenticated
  using (exists (select 1 from public.polls p
    where p.id = poll_votes.poll_id and public._is_member(p.conversation_id)));
revoke all on public.polls, public.poll_votes from anon;
revoke insert, update, delete on public.polls, public.poll_votes from authenticated;

create function public.fn_create_poll(
  p_client_ref uuid,
  p_conversation uuid,
  p_question text,
  p_options text[],
  p_multiple boolean
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_options text[];
begin
  select id into v_id from public.polls where message_id = p_client_ref;
  if found then
    return v_id;
  end if;
  if not public._is_member(p_conversation) then
    raise exception 'NOT_FOUND: Chat not found';
  end if;
  select coalesce(array_agg(trim(o) order by n), '{}') into v_options
  from unnest(coalesce(p_options, '{}')) with ordinality as x(o, n)
  where length(trim(o)) > 0;
  if cardinality(v_options) < 2 then
    raise exception 'INVALID: A poll needs at least two options';
  end if;
  if cardinality(v_options) > 12 then
    raise exception 'INVALID: A poll can have up to 12 options';
  end if;
  if length(trim(coalesce(p_question, ''))) = 0 then
    raise exception 'INVALID: Ask a question';
  end if;
  insert into public.polls (conversation_id, question, options, multiple)
  values (p_conversation, trim(p_question), v_options, coalesce(p_multiple, false))
  returning id into v_id;
  perform public.fn_send_message(p_client_ref, p_conversation, 'text', '📊 ' || trim(p_question),
    null, null, null, null, null, 'poll:' || v_id, null);
  update public.polls set message_id = p_client_ref where id = v_id;
  return v_id;
end;
$$;

create function public.fn_vote_poll(p_poll uuid, p_options integer[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.polls;
  v_opts integer[] := coalesce(p_options, '{}');
begin
  select * into p from public.polls where id = p_poll;
  if not found or not public._is_member(p.conversation_id) then
    raise exception 'NOT_FOUND: Poll not found';
  end if;
  if exists (select 1 from unnest(v_opts) o where o < 0 or o >= cardinality(p.options)) then
    raise exception 'INVALID: Unknown option';
  end if;
  if not p.multiple and cardinality(v_opts) > 1 then
    raise exception 'INVALID: Choose one option';
  end if;
  delete from public.poll_votes where poll_id = p_poll and user_id = auth.uid();
  insert into public.poll_votes (poll_id, user_id, option)
  select p_poll, auth.uid(), o from (select distinct unnest(v_opts) as o) x;
end;
$$;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.poll_votes;
  end if;
end;
$$;

revoke execute on function
  public.fn_create_poll(uuid, uuid, text, text[], boolean),
  public.fn_vote_poll(uuid, integer[])
from public, anon;
grant execute on function
  public.fn_create_poll(uuid, uuid, text, text[], boolean),
  public.fn_vote_poll(uuid, integer[])
to authenticated;

insert into public.schema_migrations (filename) values ('0052_polls.sql')
on conflict do nothing;
