-- Behaviour checks for 0028_reminders_and_repairs. Runs in a transaction and rolls back.
begin;

create function pg_temp.act_as(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.as_owner() returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
end $$;

create function pg_temp.check(p_ok boolean, p_label text) returns void language plpgsql as $$
begin
  if p_ok is not true then raise exception 'FAILED: %', p_label; end if;
  raise notice 'ok - %', p_label;
end $$;

create function pg_temp.fails(p_sql text, p_code text, p_label text) returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'FAILED: % (no error)', p_label;
exception when others then
  if sqlerrm like 'FAILED:%' then raise; end if;
  if p_code <> '' and sqlerrm not like p_code || ':%' then
    raise exception 'FAILED: % (got: %)', p_label, sqlerrm;
  end if;
  raise notice 'ok - %', p_label;
end $$;

insert into public.sites (id, code, name) values ('f8000000-0000-0000-0000-0000000000a1', 'RMD', 'Reminder site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('f8000000-0000-0000-0000-000000000001', 'rmd-store@test', '{"full_name":"Rmd Store"}'),
  ('f8000000-0000-0000-0000-000000000002', 'rmd-tech@test', '{"full_name":"Rmd Tech"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'f8000000-0000-0000-0000-000000000001'::uuid, id, 'f8000000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Storekeeper'
union all
select 'f8000000-0000-0000-0000-000000000002'::uuid, id, 'f8000000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Technician';

-- Reminders.
select pg_temp.act_as('f8000000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_create_reminder('f8000000-0000-0000-0000-0000000000c9', now(), ' ', null, null)$$,
  'INVALID', 'a reminder needs a note');
select pg_temp.fails($$select public.fn_create_reminder('f8000000-0000-0000-0000-0000000000c1', now() + interval '2 years', 'Check', null, null)$$,
  'INVALID', 'reminders are within a year');
select pg_temp.fails($$select public.fn_create_reminder('f8000000-0000-0000-0000-0000000000c1', now(), 'Check', 'nonsense', null)$$,
  'INVALID', 'links must point at a record');
select public.fn_create_reminder('f8000000-0000-0000-0000-0000000000c1', now() - interval '1 minute',
  'Check the megger on feeder 3', 'tool:f8000000-0000-0000-0000-0000000000b1', 'f8000000-0000-0000-0000-0000000000a1');
select public.fn_create_reminder('f8000000-0000-0000-0000-0000000000c1', now() - interval '1 minute',
  'Changed twice', null, null);
select public.fn_create_reminder('f8000000-0000-0000-0000-0000000000c2', now() + interval '1 hour',
  'Later one', null, null);
select public.fn_create_reminder('f8000000-0000-0000-0000-0000000000c3', now() + interval '1 hour',
  'Cancelled one', null, null);
select public.fn_cancel_reminder('f8000000-0000-0000-0000-0000000000c3');
select pg_temp.check((select count(*) = 3 from public.reminders), 'you see your own reminders, a repeat changes nothing');
select pg_temp.as_owner();

select pg_temp.act_as('f8000000-0000-0000-0000-000000000001');
select pg_temp.check((select count(*) = 0 from public.reminders), 'nobody else sees them');
select public.fn_cancel_reminder('f8000000-0000-0000-0000-0000000000c2');
select pg_temp.as_owner();
select pg_temp.check((select not is_archived from public.reminders where id = 'f8000000-0000-0000-0000-0000000000c2'),
  'nor cancels them');

select pg_temp.check(public.fn_send_due_reminders() = 1, 'the due reminder goes off');
select pg_temp.check(public.fn_send_due_reminders() = 0, 'once');
select pg_temp.check(exists (select 1 from public.notifications
  where user_id = 'f8000000-0000-0000-0000-000000000002' and type = 'reminder'
    and body = 'Check the megger on feeder 3' and link = 'tool:f8000000-0000-0000-0000-0000000000b1'),
  'as a notification that opens the record');
update public.reminders set remind_at = now() - interval '1 minute';
select pg_temp.check(public.fn_send_due_reminders() = 1, 'the rest go off when due; cancelled ones never');

-- Repairs: closing the repair job card puts the tool back in service.
select pg_temp.act_as('f8000000-0000-0000-0000-000000000001');
select public.fn_save_tool('f8000000-0000-0000-0000-0000000000b1', 'f8000000-0000-0000-0000-0000000000a1',
  'Megger MIT420', null, null, null, null, 'good', false);
select public.fn_issue_tools('f8000000-0000-0000-0000-0000000000d1', 'f8000000-0000-0000-0000-0000000000a1',
  '[{"tool_id":"f8000000-0000-0000-0000-0000000000b1"}]', null, 'Outside Electrician', null, 'Contractor',
  null, null, null, null, null);
select public.fn_return_tools('f8000000-0000-0000-0000-0000000000d1',
  '[{"tool_id":"f8000000-0000-0000-0000-0000000000b1","condition":"damaged","note":"Lead burnt"}]', null, null);
select pg_temp.as_owner();
select pg_temp.check((select condition = 'damaged' and repair_job_card_id is not null from public.tools
  where id = 'f8000000-0000-0000-0000-0000000000b1'), 'a damaged return opens a repair job card');
update public.job_cards set status = 'in_progress', responsible_id = 'f8000000-0000-0000-0000-000000000002'
where id = (select repair_job_card_id from public.tools where id = 'f8000000-0000-0000-0000-0000000000b1');
select pg_temp.check((select condition = 'damaged' from public.tools where id = 'f8000000-0000-0000-0000-0000000000b1'),
  'work in progress leaves it damaged');
update public.job_cards set status = 'closed', closed_at = now(), closure_approved_at = now(),
  completion_summary = 'New test lead fitted'
where id = (select repair_job_card_id from public.tools where id = 'f8000000-0000-0000-0000-0000000000b1');
select pg_temp.check((select condition = 'good' and repair_job_card_id is null from public.tools
  where id = 'f8000000-0000-0000-0000-0000000000b1'), 'closing the repair job card puts the tool back in service');
select pg_temp.check(exists (select 1 from public.notifications
  where user_id = 'f8000000-0000-0000-0000-000000000001' and title = 'T-0001 is repaired and back in service'),
  'and the store hears');

rollback;
