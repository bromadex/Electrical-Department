-- 0028_reminders_and_repairs: personal reminders ("remind me at 14:00 about
-- EL-JC-2026-0142", issue #7, API.md section 8b), and a tool comes back into
-- service when its repair job card is closed (API.md section 11b).

-- ---------------------------------------------------------------------------
-- Personal reminders
-- ---------------------------------------------------------------------------
create table public.reminders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) default auth.uid(),
  site_id uuid references public.sites (id),
  remind_at timestamptz not null,
  note text not null check (length(trim(note)) between 1 and 300),
  link text check (link ~ '^[a-z]+:[0-9a-f-]{36}$'),
  notified_at timestamptz,
  is_archived boolean not null default false,
  created_at timestamptz not null default now()
);
create index reminders_due on public.reminders (remind_at)
  where notified_at is null and not is_archived;
create index reminders_user on public.reminders (user_id, remind_at desc);

-- A reminder for yourself. p_link points at a record (jobcard:<id>,
-- tool:<id>, doc:<id>…) that the notification opens. A time already passed
-- (a reminder queued offline) fires at the next minute.
create function public.fn_create_reminder(
  p_client_ref uuid,
  p_remind_at timestamptz,
  p_note text,
  p_link text,
  p_site uuid
)
returns public.reminders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.reminders;
begin
  select * into v from public.reminders where id = p_client_ref;
  if found then
    return v;
  end if;
  if auth.uid() is null or not exists (
    select 1 from public.profiles where id = auth.uid() and active and not is_archived
  ) then
    raise exception 'NOT_ALLOWED: Sign in to set reminders';
  end if;
  if length(trim(coalesce(p_note, ''))) not between 1 and 300 then
    raise exception 'INVALID: Say what to remind you about (up to 300 characters)';
  end if;
  if p_remind_at is null or p_remind_at > now() + interval '1 year' then
    raise exception 'INVALID: Pick a time within the next year';
  end if;
  if p_link is not null and p_link !~ '^[a-z]+:[0-9a-f-]{36}$' then
    raise exception 'INVALID: Unknown record link';
  end if;
  insert into public.reminders (id, site_id, remind_at, note, link)
  values (p_client_ref, p_site, p_remind_at, trim(p_note), p_link)
  returning * into v;
  return v;
end;
$$;

-- Cancels one of your reminders that has not gone off yet.
create function public.fn_cancel_reminder(p_reminder uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.reminders set is_archived = true
  where id = p_reminder and user_id = auth.uid() and notified_at is null;
end;
$$;

-- Every minute: due reminders become notifications (and pushes).
create function public.fn_send_due_reminders()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_count integer := 0;
begin
  for r in
    select * from public.reminders
    where notified_at is null and not is_archived and remind_at <= now()
    order by remind_at
    for update skip locked
  loop
    perform public.fn_notify(r.user_id, r.site_id, 'reminder', 'Reminder', r.note, r.link);
    update public.reminders set notified_at = now() where id = r.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke execute on function
  public.fn_create_reminder(uuid, timestamptz, text, text, uuid),
  public.fn_cancel_reminder(uuid),
  public.fn_send_due_reminders()
from public, anon, authenticated;
grant execute on function
  public.fn_create_reminder(uuid, timestamptz, text, text, uuid),
  public.fn_cancel_reminder(uuid)
to authenticated;

alter table public.reminders enable row level security;
create policy reminders_select on public.reminders for select to authenticated
  using (user_id = auth.uid());
revoke all on public.reminders from anon;
revoke insert, update, delete on public.reminders from authenticated;

select cron.schedule('personal-reminders', '* * * * *', 'select public.fn_send_due_reminders()');

-- ---------------------------------------------------------------------------
-- Repairs: closing a tool's repair job card puts the tool back in service
-- ---------------------------------------------------------------------------
create function public._tool_repaired()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  t record;
begin
  for t in
    update public.tools set condition = 'good', repair_job_card_id = null
    where repair_job_card_id = new.id and not is_archived and condition <> 'lost'
    returning id, site_id, code, name
  loop
    perform public.fn_notify_permission(t.site_id, 'tools.issue', 'general',
      t.code || ' is repaired and back in service',
      t.name || ' · ' || new.number || ' closed', 'tool:' || t.id);
  end loop;
  -- A cancelled repair leaves the tool as it is, free for a new repair card.
  return null;
end;
$$;

create trigger job_cards_tool_repaired
  after update of status on public.job_cards
  for each row
  when (new.status = 'closed' and old.status is distinct from 'closed')
  execute function public._tool_repaired();

revoke execute on function public._tool_repaired() from public, anon, authenticated;

insert into public.schema_migrations (filename) values ('0028_reminders_and_repairs.sql')
on conflict do nothing;
