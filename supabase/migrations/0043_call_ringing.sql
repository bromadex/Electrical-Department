-- 0043_call_ringing: the caller sees "Calling…" until the other phone is
-- actually ringing, then "Ringing…", and the call timer starts only when
-- someone answers (as on WhatsApp).
--
-- The callee's phone reports that it is ringing as soon as the incoming
-- call shows (Android, also when the app is closed and nobody is signed in
-- on that isolate), through the call-ringing edge function with the call
-- alert's notification id. That id reached only the callee's phone, so it
-- is the proof; fn_call_rang is for that function (service role) only.

alter table public.calls add column rang_at timestamptz;

create function public.fn_call_rang(p_notification uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  n public.notifications;
begin
  select * into n from public.notifications
  where id = p_notification and type = 'call' and created_at > now() - interval '2 minutes';
  if not found or n.link is null or n.link not like 'call:%' then
    return false;
  end if;
  update public.calls set rang_at = now()
  where conversation_id = substr(n.link, 6)::uuid
    and ended_at is null and answered_at is null and rang_at is null
    and started_at > now() - interval '2 minutes';
  return found;
end;
$$;

revoke execute on function public.fn_call_rang(uuid) from public, anon, authenticated;
grant execute on function public.fn_call_rang(uuid) to service_role;

insert into public.schema_migrations (filename) values ('0043_call_ringing.sql')
on conflict do nothing;
