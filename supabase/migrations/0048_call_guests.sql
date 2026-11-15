-- 0048_call_guests: join by link for outsiders (contractors, clients).
--
-- Someone who can run the call (the group's owner, chat.manage or
-- meetings.manage at its site, whoever started the live call, or the chair
-- of a meeting on now) makes a link for a group chat's call that works for
-- 1 to 72 hours. An outsider opens it in a browser (no account), gives their
-- name and waits; the guest-join edge function (service role) records them
-- in call_guests as waiting and tells the link's maker. People in the call
-- see who is waiting and admit or turn them away; once admitted, guest-join
-- hands the guest a LiveKit pass for that call only, until the link ends.
-- The guest's secret is kept only as a SHA-256 hash.

create table public.call_guest_links (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id),
  token text not null unique,
  created_by uuid not null references public.profiles (id) default auth.uid(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);
create index call_guest_links_conversation_idx on public.call_guest_links (conversation_id);
create index call_guest_links_created_by_idx on public.call_guest_links (created_by);

create table public.call_guests (
  id uuid primary key default gen_random_uuid(),
  link_id uuid not null references public.call_guest_links (id),
  conversation_id uuid not null references public.conversations (id),
  name text not null check (length(trim(name)) between 1 and 60),
  secret_hash text not null,
  status text not null default 'waiting' check (status in ('waiting', 'admitted', 'denied')),
  decided_by uuid references public.profiles (id),
  decided_at timestamptz,
  created_at timestamptz not null default now()
);
create index call_guests_link_idx on public.call_guests (link_id);
create index call_guests_conversation_idx on public.call_guests (conversation_id, status);
create index call_guests_decided_by_idx on public.call_guests (decided_by);

alter table public.call_guest_links enable row level security;
alter table public.call_guests enable row level security;
create policy call_guest_links_select on public.call_guest_links for select to authenticated
  using (public._is_member(conversation_id));
create policy call_guests_select on public.call_guests for select to authenticated
  using (public._is_member(conversation_id));
revoke all on public.call_guest_links, public.call_guests from anon;
revoke insert, update, delete on public.call_guest_links, public.call_guests from authenticated;

-- May the caller let outsiders into this chat's call?
create function public._can_admit(p_conversation uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.conversations c
    where c.id = p_conversation and c.kind = 'group' and not c.is_archived
      and public._is_member(c.id)
      and (
        public._can('chat.manage', c.site_id)
        or public._can('meetings.manage', c.site_id)
        or exists (select 1 from public.conversation_members cm
          where cm.conversation_id = c.id and cm.user_id = auth.uid() and cm.role = 'owner')
        or exists (select 1 from public.calls k
          where k.conversation_id = c.id and k.ended_at is null and k.started_by = auth.uid())
        or exists (select 1 from public.meetings m
          where m.conversation_id = c.id and m.status = 'scheduled' and m.chair_id = auth.uid()
            and now() between m.starts_at - interval '15 minutes'
              and m.starts_at + make_interval(mins => m.duration_min) + interval '1 hour')
      )
  );
$$;

create function public.fn_create_guest_link(p_conversation uuid, p_hours integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.call_guest_links;
begin
  if not public._can_admit(p_conversation) then
    raise exception 'NOT_ALLOWED: Only whoever runs the call can invite guests';
  end if;
  insert into public.call_guest_links (conversation_id, token, expires_at)
  values (
    p_conversation,
    replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''),
    now() + make_interval(hours => least(greatest(coalesce(p_hours, 4), 1), 72))
  )
  returning * into v;
  return jsonb_build_object('id', v.id, 'token', v.token, 'expires_at', v.expires_at);
end;
$$;

create function public.fn_revoke_guest_link(p_link uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.call_guest_links;
begin
  select * into v from public.call_guest_links where id = p_link;
  if not found or not public._can_admit(v.conversation_id) then
    raise exception 'NOT_FOUND: Link not found';
  end if;
  update public.call_guest_links set revoked_at = now() where id = p_link and revoked_at is null;
end;
$$;

create function public.fn_decide_guest(p_guest uuid, p_admit boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  g public.call_guests;
begin
  select * into g from public.call_guests where id = p_guest for update;
  if not found or not public._can_admit(g.conversation_id) then
    raise exception 'NOT_FOUND: Guest not found';
  end if;
  update public.call_guests
  set status = case when coalesce(p_admit, false) then 'admitted' else 'denied' end,
      decided_by = auth.uid(), decided_at = now()
  where id = p_guest;
end;
$$;

-- guest-join (service role): an outsider asks to join through a link.
create function public.fn_guest_request(p_token text, p_name text, p_secret_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  l public.call_guest_links;
  c public.conversations;
  v_id uuid;
begin
  select * into l from public.call_guest_links
  where token = p_token and revoked_at is null and expires_at > now();
  if not found then
    raise exception 'NOT_FOUND: This link has ended or does not exist';
  end if;
  if length(trim(coalesce(p_name, ''))) not between 1 and 60 then
    raise exception 'INVALID: Give your name';
  end if;
  if (select count(*) from public.call_guests g where g.link_id = l.id) >= 50 then
    raise exception 'INVALID: This link has been used too many times';
  end if;
  select * into c from public.conversations where id = l.conversation_id;
  insert into public.call_guests (link_id, conversation_id, name, secret_hash)
  values (l.id, l.conversation_id, trim(p_name), p_secret_hash)
  returning id into v_id;
  insert into public.notifications (user_id, site_id, type, title, body, link)
  values (l.created_by, c.site_id, 'meeting', trim(p_name) || ' (guest) is waiting',
    'Open the call in ' || coalesce(c.title, 'the chat') || ' to let them in',
    'call:' || l.conversation_id);
  return jsonb_build_object('guest_id', v_id, 'title', coalesce(c.title, 'Call'),
    'expires_at', l.expires_at);
end;
$$;

-- guest-join (service role): has the guest been let in?
create function public.fn_guest_status(p_guest uuid, p_secret_hash text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'status', case when l.revoked_at is not null or l.expires_at <= now() then 'ended' else g.status end,
    'conversation_id', g.conversation_id,
    'name', g.name,
    'expires_at', l.expires_at,
    'title', coalesce(c.title, 'Call'))
  from public.call_guests g
  join public.call_guest_links l on l.id = g.link_id
  join public.conversations c on c.id = g.conversation_id
  where g.id = p_guest and g.secret_hash = p_secret_hash;
$$;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.call_guests;
  end if;
end;
$$;

revoke execute on function
  public._can_admit(uuid),
  public.fn_guest_request(text, text, text),
  public.fn_guest_status(uuid, text)
from public, anon, authenticated;
grant execute on function
  public.fn_guest_request(text, text, text),
  public.fn_guest_status(uuid, text)
to service_role;
revoke execute on function
  public.fn_create_guest_link(uuid, integer),
  public.fn_revoke_guest_link(uuid),
  public.fn_decide_guest(uuid, boolean)
from public, anon;
grant execute on function
  public.fn_create_guest_link(uuid, integer),
  public.fn_revoke_guest_link(uuid),
  public.fn_decide_guest(uuid, boolean)
to authenticated;

insert into public.schema_migrations (filename) values ('0048_call_guests.sql')
on conflict do nothing;
