-- Behaviour checks for 0026_tool_issue_forms. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values
  ('f6000000-0000-0000-0000-0000000000a1', 'TIF', 'Tool form site'),
  ('f6000000-0000-0000-0000-0000000000a2', 'TIX', 'Other tool site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('f6000000-0000-0000-0000-000000000001', 'tif-store@test', '{"full_name":"Tif Store"}'),
  ('f6000000-0000-0000-0000-000000000002', 'tif-tech@test', '{"full_name":"Tif Tech"}'),
  ('f6000000-0000-0000-0000-000000000003', 'tif-sup@test', '{"full_name":"Tif Sup"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'f6000000-0000-0000-0000-000000000001'::uuid, id, 'f6000000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Storekeeper'
union all
select 'f6000000-0000-0000-0000-000000000002'::uuid, id, 'f6000000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Technician'
union all
select 'f6000000-0000-0000-0000-000000000003'::uuid, id, 'f6000000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Supervisor';

-- Three tools in the register, one elsewhere.
select pg_temp.act_as('f6000000-0000-0000-0000-000000000001');
select public.fn_save_tool('f6000000-0000-0000-0000-0000000000b1', 'f6000000-0000-0000-0000-0000000000a1',
  'Fluke True-RMS Clamp Meter', 'Meter', '67510984WS', null, null, 'good', false);
select public.fn_save_tool('f6000000-0000-0000-0000-0000000000b2', 'f6000000-0000-0000-0000-0000000000a1',
  'Ingco Claw Hammer', null, null, null, null, 'good', false);
select public.fn_save_tool('f6000000-0000-0000-0000-0000000000b3', 'f6000000-0000-0000-0000-0000000000a1',
  'Broken crimper', null, null, null, null, 'damaged', false);
select pg_temp.as_owner();
insert into public.tools (id, site_id, code, name) values
  ('f6000000-0000-0000-0000-0000000000b9', 'f6000000-0000-0000-0000-0000000000a2', 'T-0001', 'Elsewhere tool');

-- Issue form to someone outside the app.
select pg_temp.act_as('f6000000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_issue_tools('f6000000-0000-0000-0000-0000000000c1',
  'f6000000-0000-0000-0000-0000000000a1', '[{"tool_id":"f6000000-0000-0000-0000-0000000000b1"}]', null,
  'Tinashe Mademe', 'Electrician', 'Manhattan', 'Elia Manjawu', null, null, null, null)$$,
  'NOT_ALLOWED', 'technicians cannot issue a form');
select pg_temp.as_owner();

select pg_temp.act_as('f6000000-0000-0000-0000-000000000001');
select pg_temp.fails($$select public.fn_issue_tools('f6000000-0000-0000-0000-0000000000c1',
  'f6000000-0000-0000-0000-0000000000a1', '[{"tool_id":"f6000000-0000-0000-0000-0000000000b3"}]', null,
  'Tinashe Mademe', null, null, null, null, null, null, null)$$,
  'INVALID', 'damaged tools cannot go out');
select pg_temp.fails($$select public.fn_issue_tools('f6000000-0000-0000-0000-0000000000c1',
  'f6000000-0000-0000-0000-0000000000a1', '[{"tool_id":"f6000000-0000-0000-0000-0000000000b9"}]', null,
  'Tinashe Mademe', null, null, null, null, null, null, null)$$,
  'NOT_FOUND', 'tools must be in this site''s register');
select pg_temp.fails($$select public.fn_issue_tools('f6000000-0000-0000-0000-0000000000c1',
  'f6000000-0000-0000-0000-0000000000a1', '[{"tool_id":"f6000000-0000-0000-0000-0000000000b1"}]', null,
  ' ', null, null, null, null, null, null, null)$$,
  'INVALID', 'someone must receive the tools');
select pg_temp.check((select code = 'TI-0001' and status = 'out' and recipient_id is null
    and company = 'Manhattan' and recipient_signature = 'sig/r.png'
  from public.fn_issue_tools('f6000000-0000-0000-0000-0000000000c1',
  'f6000000-0000-0000-0000-0000000000a1',
  '[{"tool_id":"f6000000-0000-0000-0000-0000000000b1","qty":1,"condition":"good"},
    {"tool_id":"f6000000-0000-0000-0000-0000000000b2","qty":1,"condition":"needs_repair"}]',
  null, 'Tinashe Mademe', 'Electrician', 'Manhattan', 'Elia Manjawu', 'Kamativi', current_date + 14,
  null, '{"issuer":"sig/i.png","recipient":"sig/r.png","lead":"sig/l.png"}')),
  'the store issues two tools on a TI- form to someone outside the app');
select pg_temp.check((select count(*) = 1 from public.tool_issue_forms where site_id = 'f6000000-0000-0000-0000-0000000000a1'
  and id = (select id from public.fn_issue_tools('f6000000-0000-0000-0000-0000000000c1',
  'f6000000-0000-0000-0000-0000000000a1', '[]', null, null, null, null, null, null, null, null, null))),
  'sending the same form again changes nothing');
select pg_temp.check((select bool_and(holder_id is null and holder_name = 'Tinashe Mademe'
    and issue_form_id = 'f6000000-0000-0000-0000-0000000000c1')
  from public.tools where id in ('f6000000-0000-0000-0000-0000000000b1', 'f6000000-0000-0000-0000-0000000000b2')),
  'the tools show who holds them');
select pg_temp.check((select condition = 'needs_repair' from public.tools where id = 'f6000000-0000-0000-0000-0000000000b2'),
  'condition on issue is kept');
select pg_temp.fails($$select public.fn_issue_tool('f6000000-0000-0000-0000-0000000000c9',
  'f6000000-0000-0000-0000-0000000000b1', 'f6000000-0000-0000-0000-000000000002', null, null)$$,
  'CONFLICT', 'a tool out on a form cannot be lent again');
select pg_temp.as_owner();

select pg_temp.act_as('f6000000-0000-0000-0000-000000000002');
select pg_temp.check((select count(*) = 1 from public.tool_issue_forms
  where site_id = 'f6000000-0000-0000-0000-0000000000a1'), 'people at the site see the form');
select pg_temp.as_owner();

-- Part return, then the rest.
select pg_temp.act_as('f6000000-0000-0000-0000-000000000001');
select pg_temp.fails($$select public.fn_return_tools('f6000000-0000-0000-0000-0000000000c1',
  '[{"tool_id":"f6000000-0000-0000-0000-0000000000b1","condition":"damaged"}]', null, null)$$,
  'INVALID', 'a damaged return needs a note');
select pg_temp.check((select status = 'part_returned' from public.fn_return_tools('f6000000-0000-0000-0000-0000000000c1',
  '[{"tool_id":"f6000000-0000-0000-0000-0000000000b1","condition":"good"}]', null, null)),
  'one tool back: part returned');
select pg_temp.check((select holder_name is null and issue_form_id is null from public.tools
  where id = 'f6000000-0000-0000-0000-0000000000b1'), 'the returned tool is in store');
select pg_temp.check((select status = 'returned' and returned_at is not null and return_remarks = 'All in'
    and return_recipient_signature = 'sig/r2.png'
  from public.fn_return_tools('f6000000-0000-0000-0000-0000000000c1',
  '[{"tool_id":"f6000000-0000-0000-0000-0000000000b2","condition":"damaged","note":"Handle cracked"},
    {"tool_id":"f6000000-0000-0000-0000-0000000000b1","condition":"good"}]',
  '{"recipient":"sig/r2.png"}', 'All in')),
  'the rest back: returned, and a repeat of a returned tool is ignored');
select pg_temp.check((select condition = 'damaged' from public.tools where id = 'f6000000-0000-0000-0000-0000000000b2'),
  'condition on return is kept');
select pg_temp.check((select j.title = 'Repair T-0002 Ingco Claw Hammer' and j.status = 'registered'
    and j.description like '%Handle cracked%'
  from public.tools t join public.job_cards j on j.id = t.repair_job_card_id
  where t.id = 'f6000000-0000-0000-0000-0000000000b2'),
  'a damaged return opens a repair job card');
select pg_temp.check(exists (select 1 from public.job_card_tools jt join public.tools t on t.repair_job_card_id = jt.job_card_id
  where t.id = 'f6000000-0000-0000-0000-0000000000b2' and jt.tool_id = t.id),
  'and the tool is on it');
select pg_temp.as_owner();
select pg_temp.check(exists (select 1 from public.notifications
  where user_id = 'f6000000-0000-0000-0000-000000000003' and title like '% came back damaged'),
  'the supervisor hears about the damaged tool');

select pg_temp.check(exists (select 1 from public.notifications
  where user_id = 'f6000000-0000-0000-0000-000000000003' and title like 'New job card % repair T-0002'),
  'the supervisor hears about the repair job card');

-- Calibration certificates.
select pg_temp.act_as('f6000000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_add_tool_certificate('f6000000-0000-0000-0000-0000000000d1',
  'f6000000-0000-0000-0000-0000000000b1', 'f6000000-0000-0000-0000-0000000000a1/tool/f6000000-0000-0000-0000-0000000000b1/cert.pdf',
  'cert.pdf', current_date, current_date + 365)$$, 'NOT_ALLOWED', 'technicians cannot add certificates');
select pg_temp.as_owner();
select pg_temp.act_as('f6000000-0000-0000-0000-000000000001');
select pg_temp.fails($$select public.fn_add_tool_certificate('f6000000-0000-0000-0000-0000000000d1',
  'f6000000-0000-0000-0000-0000000000b1', 'elsewhere/cert.pdf', 'cert.pdf', current_date, current_date + 365)$$,
  'INVALID', 'the file must be in the tool''s folder');
select public.fn_add_tool_certificate('f6000000-0000-0000-0000-0000000000d1',
  'f6000000-0000-0000-0000-0000000000b1', 'f6000000-0000-0000-0000-0000000000a1/tool/f6000000-0000-0000-0000-0000000000b1/cert.pdf',
  'Fluke cal cert.pdf', current_date - 1, current_date + 365);
select pg_temp.check((select calibration_due = current_date + 365 from public.tools
  where id = 'f6000000-0000-0000-0000-0000000000b1'), 'a certificate sets the calibration due date');
select public.fn_add_tool_certificate('f6000000-0000-0000-0000-0000000000d2',
  'f6000000-0000-0000-0000-0000000000b1', 'f6000000-0000-0000-0000-0000000000a1/tool/f6000000-0000-0000-0000-0000000000b1/old.pdf',
  'Old cert.pdf', current_date - 400, current_date + 10);
select pg_temp.check((select calibration_due = current_date + 365 from public.tools
  where id = 'f6000000-0000-0000-0000-0000000000b1'), 'an older certificate does not shorten it');
select pg_temp.as_owner();
select pg_temp.act_as('f6000000-0000-0000-0000-000000000002');
select pg_temp.check((select count(*) = 2 from public.tool_certificates
  where tool_id = 'f6000000-0000-0000-0000-0000000000b1'), 'people at the site see the certificates');
select pg_temp.as_owner();
update public.tools set calibration_due = null where id = 'f6000000-0000-0000-0000-0000000000b1';

-- Single-tool lending still works, and fn_return_tool closes a form too.
select pg_temp.act_as('f6000000-0000-0000-0000-000000000001');
select public.fn_issue_tool('f6000000-0000-0000-0000-0000000000c8', 'f6000000-0000-0000-0000-0000000000b1',
  'f6000000-0000-0000-0000-000000000002', null, null);
select pg_temp.check((select holder_name = 'Tif Tech' from public.tools where id = 'f6000000-0000-0000-0000-0000000000b1'),
  'lending to an app user fills in their name');
select public.fn_return_tool('f6000000-0000-0000-0000-0000000000b1', 'good', null);
select public.fn_issue_tools('f6000000-0000-0000-0000-0000000000c2', 'f6000000-0000-0000-0000-0000000000a1',
  '[{"tool_id":"f6000000-0000-0000-0000-0000000000b1"}]', 'f6000000-0000-0000-0000-000000000002',
  null, null, null, null, null, null, null, null);
select pg_temp.check((select recipient_name = 'Tif Tech' and code = 'TI-0002' from public.tool_issue_forms
  where id = 'f6000000-0000-0000-0000-0000000000c2'), 'a form to an app user takes their name');
select public.fn_return_tool('f6000000-0000-0000-0000-0000000000b1', 'good', null);
select pg_temp.check((select status = 'returned' from public.tool_issue_forms
  where id = 'f6000000-0000-0000-0000-0000000000c2'), 'taking the tool back on its page returns the form');
select pg_temp.as_owner();

-- Overdue: someone outside the app has no inbox; the store hears.
select pg_temp.act_as('f6000000-0000-0000-0000-000000000001');
select public.fn_issue_tools('f6000000-0000-0000-0000-0000000000c3', 'f6000000-0000-0000-0000-0000000000a1',
  '[{"tool_id":"f6000000-0000-0000-0000-0000000000b1"}]', null,
  'Tinashe Mademe', null, 'Manhattan', null, null, null, null, null);
select pg_temp.as_owner();
update public.tool_issues set due_back = current_date - 3
where form_id = 'f6000000-0000-0000-0000-0000000000c3';
select public.fn_notify_tools();
select pg_temp.check(exists (select 1 from public.notifications
  where user_id = 'f6000000-0000-0000-0000-000000000001' and type = 'overdue' and body like '%Tinashe Mademe%'),
  'the store is told whose tool is overdue');

-- Expired calibration blocks issuing.
select pg_temp.as_owner();
update public.tools set calibration_due = current_date - 1 where id = 'f6000000-0000-0000-0000-0000000000b1';
select pg_temp.act_as('f6000000-0000-0000-0000-000000000001');
select public.fn_return_tools('f6000000-0000-0000-0000-0000000000c3',
  '[{"tool_id":"f6000000-0000-0000-0000-0000000000b1","condition":"good"}]', null, null);
select pg_temp.fails($$select public.fn_issue_tools('f6000000-0000-0000-0000-0000000000c5',
  'f6000000-0000-0000-0000-0000000000a1', '[{"tool_id":"f6000000-0000-0000-0000-0000000000b1"}]', null,
  'Tinashe Mademe', null, null, null, null, null, null, null)$$,
  'INVALID', 'a tool with expired calibration cannot go out on a form');
select pg_temp.fails($$select public.fn_issue_tool('f6000000-0000-0000-0000-0000000000c6',
  'f6000000-0000-0000-0000-0000000000b1', 'f6000000-0000-0000-0000-000000000002', null, null)$$,
  'INVALID', 'or be lent');
select pg_temp.as_owner();
update public.tools set calibration_due = null where id = 'f6000000-0000-0000-0000-0000000000b1';

-- Job cards list the tools they need.
select pg_temp.act_as('f6000000-0000-0000-0000-000000000003');
select public.fn_register_job_card('f6000000-0000-0000-0000-0000000000e1', null,
  'f6000000-0000-0000-0000-0000000000a1', null, 'Substation', now(), 'Tif Sup', null, null, null, null, null, null,
  'Repair feeder cable', 'Feeder 3 cable needs a new joint', 'minor', 'P3', null);
select public.fn_link_job_card_tool('f6000000-0000-0000-0000-0000000000e1', 'f6000000-0000-0000-0000-0000000000b2', true);
select public.fn_link_job_card_tool('f6000000-0000-0000-0000-0000000000e1', 'f6000000-0000-0000-0000-0000000000b2', true);
select pg_temp.check((select count(*) = 1 from public.job_card_tools
  where job_card_id = 'f6000000-0000-0000-0000-0000000000e1'), 'a supervisor adds a tool to a job card, once');
select pg_temp.fails($$select public.fn_link_job_card_tool('f6000000-0000-0000-0000-0000000000e1',
  'f6000000-0000-0000-0000-0000000000b9', true)$$, 'INVALID', 'tools must be at the job card''s site');
select pg_temp.as_owner();

select pg_temp.act_as('f6000000-0000-0000-0000-000000000002');
select pg_temp.check(exists (select 1 from public.job_card_tools
  where tool_id = 'f6000000-0000-0000-0000-0000000000b2'), 'people at the site see which jobs used a tool');
select pg_temp.fails($$select public.fn_link_job_card_tool('f6000000-0000-0000-0000-0000000000e1',
  'f6000000-0000-0000-0000-0000000000b2', false)$$, 'NOT_ALLOWED', 'people off the job cannot change its tools');
select pg_temp.as_owner();

-- A form issued for a job card links its tools to it.
select pg_temp.act_as('f6000000-0000-0000-0000-000000000001');
select public.fn_issue_tools('f6000000-0000-0000-0000-0000000000c4', 'f6000000-0000-0000-0000-0000000000a1',
  '[{"tool_id":"f6000000-0000-0000-0000-0000000000b1"}]', 'f6000000-0000-0000-0000-000000000002',
  null, null, null, null, null, null, null, null, 'f6000000-0000-0000-0000-0000000000e1');
select pg_temp.check(exists (select 1 from public.job_card_tools
  where job_card_id = 'f6000000-0000-0000-0000-0000000000e1' and tool_id = 'f6000000-0000-0000-0000-0000000000b1'),
  'tools issued for a job card are linked to it');
select pg_temp.check((select (summary->>'tools_out')::int = 1
  from public.fn_build_daily_report('f6000000-0000-0000-0000-0000000000a1', public._harare_today())),
  'the daily report counts tools out on forms');
select pg_temp.as_owner();

rollback;
