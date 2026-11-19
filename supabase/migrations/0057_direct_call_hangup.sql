-- A one-to-one call ends for both people when either hangs up, as on
-- WhatsApp. Before, the server waited for the other phone to say it left
-- too, so a phone that dropped off without saying so (no signal, app
-- closed) kept "Call in progress · 1 in the call" showing for a while.
--
-- Also: a late "still here" ping no longer puts someone who already left
-- back in the call. Joining again goes through fn_start_call.

create or replace function public.fn_call_heartbeat(p_call uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.call_participants set last_seen_at = now()
  where call_id = p_call and user_id = auth.uid() and left_at is null
    and exists (select 1 from public.calls where id = p_call and ended_at is null);
$$;

create or replace function public.fn_leave_call(p_call uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_left integer;
begin
  update public.call_participants set left_at = now(), last_seen_at = now()
  where call_id = p_call and user_id = auth.uid() and left_at is null;
  get diagnostics v_left = row_count;

  -- In a direct chat, one person left alone in the call is hung up too.
  -- (Someone added to the call keeps it going while two are still in it.)
  if v_left > 0 and exists (
    select 1 from public.calls k
    join public.conversations c on c.id = k.conversation_id
    where k.id = p_call and k.ended_at is null and c.kind = 'direct'
  ) and public._call_active_count(p_call) <= 1 then
    update public.call_participants set left_at = now()
    where call_id = p_call and left_at is null;
  end if;

  perform public._close_call(p_call);
end;
$$;

revoke execute on function public.fn_call_heartbeat(uuid), public.fn_leave_call(uuid)
from public, anon;
grant execute on function public.fn_call_heartbeat(uuid), public.fn_leave_call(uuid)
to authenticated;
