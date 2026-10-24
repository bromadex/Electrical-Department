-- 0007_push_notifications: send every new notification to the person's
-- phones and browsers as a push message (API.md section 8).
--
-- A trigger on notifications calls the push-send edge function through
-- pg_net, with a shared secret only the database and the function know.
-- Until CI has deployed the function and stored its address in push_config,
-- the trigger does nothing, so local and test databases never call out.

create extension if not exists pg_net with schema extensions;

-- One row: where push-send lives and the secret it checks.
create table public.push_config (
  id boolean primary key default true check (id),
  endpoint text,
  secret text not null default encode(extensions.gen_random_bytes(32), 'hex'),
  updated_at timestamptz not null default now()
);
insert into public.push_config default values;
-- No policies: the app never reads it.
alter table public.push_config enable row level security;

-- Sign-out: stop pushes to this device for the signed-in user.
create function public.fn_unregister_device(p_token text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.device_tokens
  set is_archived = true, updated_at = now()
  where token = p_token and user_id = auth.uid() and not is_archived;
end;
$$;

-- Queues a push for each new notification whose person has a device.
create function public.fn_notifications_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.push_config;
begin
  select * into c from public.push_config limit 1;
  if c.endpoint is null or not exists (
    select 1 from public.device_tokens d where d.user_id = new.user_id and not d.is_archived
  ) then
    return new;
  end if;
  perform net.http_post(
    url := c.endpoint,
    body := jsonb_build_object('notification_id', new.id),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', c.secret),
    timeout_milliseconds := 5000
  );
  return new;
exception when others then
  -- A push problem must never stop the notification itself.
  return new;
end;
$$;

create trigger notifications_push
  after insert on public.notifications
  for each row execute function public.fn_notifications_push();

-- For push-send (service role): the message and the person's device tokens.
create function public.fn_push_job(p_notification uuid, p_secret text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  n public.notifications;
begin
  if p_secret is distinct from (select secret from public.push_config limit 1) then
    raise exception 'NOT_ALLOWED: Wrong push secret';
  end if;
  select * into n from public.notifications where id = p_notification;
  if not found then
    raise exception 'NOT_FOUND: Notification not found';
  end if;
  return jsonb_build_object(
    'id', n.id,
    'type', n.type,
    'title', n.title,
    'body', n.body,
    'link', n.link,
    'tokens', coalesce((
      select jsonb_agg(jsonb_build_object('token', d.token, 'platform', d.platform))
      from public.device_tokens d
      where d.user_id = n.user_id and not d.is_archived
    ), '[]'::jsonb)
  );
end;
$$;

-- For push-send: tokens the push service says no longer exist.
create function public.fn_push_drop_tokens(p_secret text, p_tokens text[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if p_secret is distinct from (select secret from public.push_config limit 1) then
    raise exception 'NOT_ALLOWED: Wrong push secret';
  end if;
  update public.device_tokens
  set is_archived = true, updated_at = now()
  where token = any (coalesce(p_tokens, '{}'::text[])) and not is_archived;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- CI stores the deployed function's address here (as the database owner).
create function public.fn_set_push_endpoint(p_url text)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.push_config set endpoint = nullif(trim(p_url), ''), updated_at = now();
$$;

revoke execute on function
  public.fn_unregister_device(text),
  public.fn_notifications_push(),
  public.fn_push_job(uuid, text),
  public.fn_push_drop_tokens(text, text[]),
  public.fn_set_push_endpoint(text)
from public, anon, authenticated;

grant execute on function public.fn_unregister_device(text) to authenticated;
grant execute on function
  public.fn_push_job(uuid, text),
  public.fn_push_drop_tokens(text, text[])
to service_role;

insert into public.schema_migrations (filename) values ('0007_push_notifications.sql')
on conflict do nothing;
