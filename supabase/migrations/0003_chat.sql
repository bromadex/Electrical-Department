-- 0003_chat: group chat and direct messages (API.md section 10).
-- Default groups ("Electrical Department" + one per site) keep their
-- membership in step with chat.use roles. Every conversation can later hold
-- group calls and meetings (section 16).

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('group', 'direct')),
  title text check (title is null or length(trim(title)) between 1 and 80),
  site_id uuid references public.sites (id),
  is_default boolean not null default false,
  created_by uuid references public.profiles (id),
  last_message_at timestamptz,
  last_message_preview text,
  is_archived boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index conversations_default_idx
  on public.conversations (coalesce(site_id, '00000000-0000-0000-0000-000000000000'::uuid))
  where is_default;

create table public.conversation_members (
  conversation_id uuid not null references public.conversations (id),
  user_id uuid not null references public.profiles (id),
  role text not null default 'member' check (role in ('owner', 'member')),
  last_read_at timestamptz not null default now(),
  is_archived boolean not null default false,
  joined_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);
create index conversation_members_user_idx on public.conversation_members (user_id) where not is_archived;

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id),
  author_id uuid references public.profiles (id),
  kind text not null default 'text' check (kind in ('text', 'photo', 'voice', 'file', 'record', 'system')),
  body text check (body is null or length(body) <= 4000),
  attachment_path text,
  attachment_name text,
  attachment_size integer,
  duration_ms integer,
  reply_to uuid references public.messages (id),
  record_link text,
  mentions uuid[] not null default '{}',
  is_archived boolean not null default false,
  created_at timestamptz not null default now()
);
create index messages_conversation_idx on public.messages (conversation_id, created_at desc);

create table public.message_reactions (
  message_id uuid not null references public.messages (id),
  user_id uuid not null references public.profiles (id),
  emoji text not null check (length(emoji) between 1 and 16),
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, emoji)
);

create trigger conversations_activity after insert or update on public.conversations
  for each row execute function public.fn_log_activity();

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create function public._is_member(p_conversation uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public._active() and exists (
    select 1 from public.conversation_members m
    join public.conversations c on c.id = m.conversation_id and not c.is_archived
    where m.conversation_id = p_conversation
      and m.user_id = auth.uid()
      and not m.is_archived
  );
$$;

-- True when the user holds chat.use anywhere (p_site null) or at p_site.
create function public._user_can_chat(p_user uuid, p_site uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    join public.user_roles ur on ur.user_id = p.id and not ur.is_archived
    join public.roles r on r.id = ur.role_id and not r.is_archived
    join public.role_permissions rp on rp.role_id = ur.role_id and not rp.is_archived
    where p.id = p_user and p.active and not p.is_archived
      and rp.permission_code = 'chat.use'
      and (p_site is null or ur.site_id is null or ur.site_id = p_site)
  );
$$;

-- Adds/removes a user from the default groups to match their roles.
create function public.fn_sync_default_chats(p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.conversations;
  v_should boolean;
begin
  for c in select * from public.conversations where is_default and not is_archived loop
    v_should := public._user_can_chat(p_user, c.site_id);
    if v_should then
      insert into public.conversation_members (conversation_id, user_id)
      values (c.id, p_user)
      on conflict (conversation_id, user_id) do update set is_archived = false
        where public.conversation_members.is_archived;
    else
      update public.conversation_members set is_archived = true
      where conversation_id = c.id and user_id = p_user and not is_archived;
    end if;
  end loop;
end;
$$;

create function public.fn_user_roles_sync_chats()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.fn_sync_default_chats(new.user_id);
  return new;
end;
$$;

create trigger user_roles_sync_chats after insert or update on public.user_roles
  for each row execute function public.fn_user_roles_sync_chats();

create function public.fn_site_default_chat()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  u uuid;
begin
  insert into public.conversations (kind, title, site_id, is_default)
  values ('group', new.name, new.id, true)
  on conflict do nothing;
  for u in select id from public.profiles loop
    perform public.fn_sync_default_chats(u);
  end loop;
  return new;
end;
$$;

create trigger sites_default_chat after insert on public.sites
  for each row execute function public.fn_site_default_chat();

-- ---------------------------------------------------------------------------
-- Functions for the app
-- ---------------------------------------------------------------------------
create function public.fn_create_group(
  p_client_ref uuid,
  p_title text,
  p_site uuid,
  p_members uuid[]
)
returns public.conversations
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.conversations;
  u uuid;
begin
  select * into v from public.conversations where id = p_client_ref;
  if found then
    return v;
  end if;
  if not public._can('chat.manage', p_site) then
    raise exception 'NOT_ALLOWED: You cannot create chat groups here';
  end if;
  if length(trim(coalesce(p_title, ''))) not between 1 and 80 then
    raise exception 'INVALID: Give the group a name';
  end if;

  insert into public.conversations (id, kind, title, site_id, created_by)
  values (p_client_ref, 'group', trim(p_title), p_site, auth.uid())
  returning * into v;

  insert into public.conversation_members (conversation_id, user_id, role)
  values (v.id, auth.uid(), 'owner');
  foreach u in array coalesce(p_members, '{}') loop
    if u <> auth.uid() and public._user_can_chat(u, p_site) then
      insert into public.conversation_members (conversation_id, user_id)
      values (v.id, u) on conflict do nothing;
    end if;
  end loop;
  return v;
end;
$$;

create function public.fn_update_group(
  p_conversation uuid,
  p_title text,
  p_add uuid[],
  p_remove uuid[]
)
returns public.conversations
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.conversations;
  u uuid;
begin
  select * into v from public.conversations where id = p_conversation and not is_archived;
  if not found or not public._is_member(v.id) then
    raise exception 'NOT_FOUND: Chat not found';
  end if;
  if v.kind <> 'group' then
    raise exception 'INVALID: Direct chats cannot be changed';
  end if;
  if not (
    public._can('chat.manage', v.site_id)
    or exists (select 1 from public.conversation_members
               where conversation_id = v.id and user_id = auth.uid() and role = 'owner')
  ) then
    raise exception 'NOT_ALLOWED: Only the group owner or a supervisor can change it';
  end if;
  if v.is_default and (cardinality(coalesce(p_add, '{}')) > 0 or cardinality(coalesce(p_remove, '{}')) > 0) then
    raise exception 'INVALID: Members of site groups follow their roles';
  end if;

  if p_title is not null then
    if length(trim(p_title)) not between 1 and 80 then
      raise exception 'INVALID: Give the group a name';
    end if;
    update public.conversations set title = trim(p_title) where id = v.id returning * into v;
  end if;
  foreach u in array coalesce(p_add, '{}') loop
    if public._user_can_chat(u, v.site_id) then
      insert into public.conversation_members (conversation_id, user_id)
      values (v.id, u)
      on conflict (conversation_id, user_id) do update set is_archived = false;
    end if;
  end loop;
  foreach u in array coalesce(p_remove, '{}') loop
    update public.conversation_members set is_archived = true
    where conversation_id = v.id and user_id = u;
  end loop;
  return v;
end;
$$;

-- Opens (or creates) the direct chat between the caller and p_user.
create function public.fn_open_direct(p_client_ref uuid, p_user uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if p_user = auth.uid() then
    raise exception 'INVALID: Pick someone else';
  end if;
  if not public._user_can_chat(auth.uid(), null) or not public._user_can_chat(p_user, null) then
    raise exception 'NOT_ALLOWED: Chat is not available for this person';
  end if;
  select c.id into v_id
  from public.conversations c
  where c.kind = 'direct' and not c.is_archived
    and exists (select 1 from public.conversation_members m where m.conversation_id = c.id and m.user_id = auth.uid())
    and exists (select 1 from public.conversation_members m where m.conversation_id = c.id and m.user_id = p_user)
  limit 1;
  if v_id is not null then
    return v_id;
  end if;
  select id into v_id from public.conversations where id = p_client_ref;
  if v_id is not null then
    return v_id;
  end if;

  insert into public.conversations (id, kind, created_by)
  values (p_client_ref, 'direct', auth.uid())
  returning id into v_id;
  insert into public.conversation_members (conversation_id, user_id)
  values (v_id, auth.uid()), (v_id, p_user);
  return v_id;
end;
$$;

create function public.fn_leave_conversation(p_conversation uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.conversations where id = p_conversation and is_default) then
    raise exception 'INVALID: You stay in site groups while you have a role there';
  end if;
  update public.conversation_members set is_archived = true
  where conversation_id = p_conversation and user_id = auth.uid();
end;
$$;

create function public.fn_send_message(
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
  if p_kind not in ('text', 'photo', 'voice', 'file', 'record') then
    raise exception 'INVALID: Unknown message kind';
  end if;
  if p_kind = 'text' and length(trim(coalesce(p_body, ''))) = 0 then
    raise exception 'INVALID: Message is empty';
  end if;
  if p_kind in ('photo', 'voice', 'file') and (
    p_attachment_path is null or split_part(p_attachment_path, '/', 1) <> p_conversation::text
  ) then
    raise exception 'INVALID: Attachment path must start with the chat id';
  end if;
  if p_kind = 'record' and p_record_link !~ '^[a-z]+:[0-9a-f-]{36}$' then
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
  return v;
end;
$$;

-- Author hides their own message.
create function public.fn_unsend_message(p_message uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.messages set is_archived = true
  where id = p_message and author_id = auth.uid();
  if not found then
    raise exception 'NOT_ALLOWED: You can only remove your own messages';
  end if;
end;
$$;

-- Toggles a reaction; returns true when added.
create function public.fn_react(p_message uuid, p_emoji text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv uuid;
  v_on boolean;
begin
  select conversation_id into v_conv from public.messages where id = p_message;
  if v_conv is null or not public._is_member(v_conv) then
    raise exception 'NOT_FOUND: Message not found';
  end if;
  insert into public.message_reactions as r (message_id, user_id, emoji)
  values (p_message, auth.uid(), p_emoji)
  on conflict (message_id, user_id, emoji) do update set is_archived = not r.is_archived
  returning not is_archived into v_on;
  return v_on;
end;
$$;

create function public.fn_mark_conversation_read(p_conversation uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.conversation_members set last_read_at = now()
  where conversation_id = p_conversation and user_id = auth.uid();
$$;

-- The caller's chats with unread counts, newest first.
create function public.fn_my_conversations()
returns table (
  id uuid, kind text, title text, site_id uuid, is_default boolean,
  last_message_at timestamptz, last_message_preview text, unread integer,
  member_count integer, other_user_id uuid
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
    o.user_id
  from public.conversation_members me
  join public.conversations c on c.id = me.conversation_id and not c.is_archived
  left join lateral (
    select m.user_id from public.conversation_members m
    where c.kind = 'direct' and m.conversation_id = c.id and m.user_id <> auth.uid()
    limit 1
  ) o on true
  left join public.profiles op on op.id = o.user_id
  where me.user_id = auth.uid() and not me.is_archived and public._active()
  order by coalesce(c.last_message_at, c.created_at) desc;
$$;

-- Records the caller can see, for the # picker. Later features add theirs.
create function public.fn_search_records(p_query text)
returns table (link text, code text, title text, status text, site_code text)
language sql
stable
security definer
set search_path = ''
as $$
  select 'job:' || j.id, j.code, j.title, j.status, s.code
  from public.jobs j
  join public.sites s on s.id = j.site_id
  where not j.is_archived
    and public._can('jobs.view', j.site_id)
    and (coalesce(p_query, '') = ''
         or j.code ilike '%' || p_query || '%'
         or j.title ilike '%' || p_query || '%')
  order by j.updated_at desc
  limit 20;
$$;

-- People the caller can start a chat with or add to a group.
create function public.fn_chat_people()
returns table (id uuid, full_name text)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.full_name from public.profiles p
  where public._user_can_chat(auth.uid(), null)
    and p.id <> auth.uid()
    and public._user_can_chat(p.id, null)
  order by p.full_name;
$$;

-- ---------------------------------------------------------------------------
-- Privileges
-- ---------------------------------------------------------------------------
revoke execute on function
  public._is_member(uuid),
  public._user_can_chat(uuid, uuid),
  public.fn_sync_default_chats(uuid),
  public.fn_user_roles_sync_chats(),
  public.fn_site_default_chat(),
  public.fn_create_group(uuid, text, uuid, uuid[]),
  public.fn_update_group(uuid, text, uuid[], uuid[]),
  public.fn_open_direct(uuid, uuid),
  public.fn_leave_conversation(uuid),
  public.fn_send_message(uuid, uuid, text, text, text, text, integer, integer, uuid, text, uuid[]),
  public.fn_unsend_message(uuid),
  public.fn_react(uuid, text),
  public.fn_mark_conversation_read(uuid),
  public.fn_my_conversations(),
  public.fn_search_records(text),
  public.fn_chat_people()
from public, anon, authenticated;

grant execute on function public._is_member(uuid) to authenticated;
grant execute on function
  public.fn_create_group(uuid, text, uuid, uuid[]),
  public.fn_update_group(uuid, text, uuid[], uuid[]),
  public.fn_open_direct(uuid, uuid),
  public.fn_leave_conversation(uuid),
  public.fn_send_message(uuid, uuid, text, text, text, text, integer, integer, uuid, text, uuid[]),
  public.fn_unsend_message(uuid),
  public.fn_react(uuid, text),
  public.fn_mark_conversation_read(uuid),
  public.fn_my_conversations(),
  public.fn_search_records(text),
  public.fn_chat_people()
to authenticated;

-- ---------------------------------------------------------------------------
-- RLS: members read; writes through functions
-- ---------------------------------------------------------------------------
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.message_reactions enable row level security;

create policy conversations_select on public.conversations for select to authenticated
  using (public._is_member(id));
create policy conversation_members_select on public.conversation_members for select to authenticated
  using (public._is_member(conversation_id));
create policy messages_select on public.messages for select to authenticated
  using (public._is_member(conversation_id));
create policy message_reactions_select on public.message_reactions for select to authenticated
  using (exists (
    select 1 from public.messages m
    where m.id = message_reactions.message_id and public._is_member(m.conversation_id)
  ));

revoke all on public.conversations, public.conversation_members, public.messages, public.message_reactions from anon;
revoke insert, update, delete on public.conversations, public.conversation_members, public.messages, public.message_reactions
from authenticated;

-- chat-files: path <conversation_id>/<message_id>/<file>; members only.
create policy chat_files_select on storage.objects for select to authenticated
  using (bucket_id = 'chat-files' and public._is_member(public._path_site(name)));
create policy chat_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'chat-files' and public._is_member(public._path_site(name)));

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table
      public.messages, public.message_reactions, public.conversation_members, public.conversations;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Default groups for existing sites, and members for existing users
-- ---------------------------------------------------------------------------
insert into public.conversations (kind, title, site_id, is_default)
values ('group', 'Electrical Department', null, true);
insert into public.conversations (kind, title, site_id, is_default)
select 'group', s.name, s.id, true from public.sites s where not s.is_archived;

do $$
declare
  u uuid;
begin
  for u in select id from public.profiles loop
    perform public.fn_sync_default_chats(u);
  end loop;
end;
$$;

insert into public.schema_migrations (filename) values ('0003_chat.sql')
on conflict do nothing;
