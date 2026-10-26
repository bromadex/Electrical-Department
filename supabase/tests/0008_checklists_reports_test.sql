-- Behaviour checks for 0008_checklists_reports. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('c0000000-0000-0000-0000-0000000000a1', 'CHK', 'Checklist site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('c0000000-0000-0000-0000-000000000001', 'ck-sup@test', '{"full_name":"Ck Sup"}'),
  ('c0000000-0000-0000-0000-000000000002', 'ck-tech@test', '{"full_name":"Ck Tech"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'c0000000-0000-0000-0000-000000000001'::uuid, id, 'c0000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Supervisor'
union all
select 'c0000000-0000-0000-0000-000000000002'::uuid, id, 'c0000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Technician';

-- Templates.
select pg_temp.act_as('c0000000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_save_checklist_template('c0000000-0000-0000-0000-0000000000b1',
  'c0000000-0000-0000-0000-0000000000a1', null, 'Generator round', null, 'daily', null,
  '[{"label":"Oil level OK"}]', false)$$, 'NOT_ALLOWED', 'technicians cannot build checklists');
select pg_temp.as_owner();
select pg_temp.act_as('c0000000-0000-0000-0000-000000000001');
select pg_temp.fails($$select public.fn_save_checklist_template('c0000000-0000-0000-0000-0000000000b1',
  'c0000000-0000-0000-0000-0000000000a1', null, 'Generator round', null, 'daily', null, '[]', false)$$,
  'INVALID', 'a checklist needs items');
select public.fn_save_checklist_template('c0000000-0000-0000-0000-0000000000b1',
  'c0000000-0000-0000-0000-0000000000a1', null, 'Generator round', 'Daily at 08:00', 'daily',
  'c0000000-0000-0000-0000-000000000002',
  '[{"id":"c0000000-0000-0000-0000-0000000000c1","label":"Oil level OK","kind":"check"},
    {"id":"c0000000-0000-0000-0000-0000000000c2","label":"Battery voltage","kind":"number","unit":"V","min":12,"max":14.5},
    {"id":"c0000000-0000-0000-0000-0000000000c3","label":"Hour meter","kind":"text","photo_required":true}]', false);
select pg_temp.check((select count(*) = 3 from public.checklist_items
  where template_id = 'c0000000-0000-0000-0000-0000000000b1' and not is_archived), 'supervisors build a checklist');
select pg_temp.check((select due_by = public._harare_today() and done_at is null
  from public.fn_site_checklists('c0000000-0000-0000-0000-0000000000a1')), 'it is due today');
select pg_temp.as_owner();

-- Rounds.
select pg_temp.act_as('c0000000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_submit_checklist('c0000000-0000-0000-0000-0000000000d1',
  'c0000000-0000-0000-0000-0000000000b1',
  '[{"item_id":"c0000000-0000-0000-0000-0000000000c1","ok":true},
    {"item_id":"c0000000-0000-0000-0000-0000000000c2","value":13}]', null)$$,
  'INVALID', 'every item needs an answer');
select pg_temp.fails($$select public.fn_submit_checklist('c0000000-0000-0000-0000-0000000000d1',
  'c0000000-0000-0000-0000-0000000000b1',
  '[{"item_id":"c0000000-0000-0000-0000-0000000000c1","ok":true},
    {"item_id":"c0000000-0000-0000-0000-0000000000c2","value":13},
    {"item_id":"c0000000-0000-0000-0000-0000000000c3","text":"1234"}]', null)$$,
  'INVALID', 'photo items need a photo');
select public.fn_submit_checklist('c0000000-0000-0000-0000-0000000000d1', 'c0000000-0000-0000-0000-0000000000b1',
  '[{"item_id":"c0000000-0000-0000-0000-0000000000c1","ok":false,"comment":"Low, topped up 1 L"},
    {"item_id":"c0000000-0000-0000-0000-0000000000c2","value":11.2},
    {"item_id":"c0000000-0000-0000-0000-0000000000c3","text":"1234 h","photo_path":"x/checklist/a.jpg"}]',
  'All else fine');
select public.fn_submit_checklist('c0000000-0000-0000-0000-0000000000d1', 'c0000000-0000-0000-0000-0000000000b1',
  '[]', null);
select pg_temp.check((select failed_count = 2 from public.checklist_runs
  where id = 'c0000000-0000-0000-0000-0000000000d1'), 'a failed tick and a low reading count as failed');
select pg_temp.check((select count(*) = 1 from public.checklist_runs), 'sending the round twice saves it once');
select pg_temp.check((select count(*) = 2 from public.job_cards where title like 'Generator round:%'),
  'each failed item raises a job card');
select pg_temp.check((select description like '%Reading: 11.2 V%' and maintenance_type = 'inspection'
  from public.job_cards where title = 'Generator round: Battery voltage'), 'the job card says what was read');
select pg_temp.check((select count(*) = 2 from public.checklist_answers
  where run_id = 'c0000000-0000-0000-0000-0000000000d1' and job_card_id is not null),
  'the answers link their job cards');
select pg_temp.check((select done_at is not null and failed_count = 2
  from public.fn_site_checklists('c0000000-0000-0000-0000-0000000000a1')), 'the round shows as done');
select pg_temp.as_owner();

-- Alerts: a second daily template nobody did.
insert into public.checklist_templates (id, site_id, name, frequency)
values ('c0000000-0000-0000-0000-0000000000b2', 'c0000000-0000-0000-0000-0000000000a1', 'DB board inspection', 'daily');
select public.fn_checklist_alerts('reminder');
select public.fn_checklist_alerts('reminder');
select pg_temp.check((select count(*) = 1 from public.notifications
  where title = 'DB board inspection is due today' and user_id = 'c0000000-0000-0000-0000-000000000002'),
  'undone rounds remind, once');
select pg_temp.check(not exists (select 1 from public.notifications where title = 'Generator round is due today'),
  'done rounds do not remind');
select public.fn_checklist_alerts('missed');
select pg_temp.check((select count(*) = 1 from public.notifications
  where title = 'DB board inspection was missed' and user_id = 'c0000000-0000-0000-0000-000000000001'),
  'supervisors hear about missed rounds');

-- Daily report.
select pg_temp.act_as('c0000000-0000-0000-0000-000000000002');
select public.fn_add_report_update('c0000000-0000-0000-0000-0000000000e1', 'c0000000-0000-0000-0000-0000000000a1',
  public._harare_today(), 'Generator serviced, battery to replace', array['x/report/a.jpg']);
select pg_temp.check((select code like 'R-%' from public.daily_reports
  where site_id = 'c0000000-0000-0000-0000-0000000000a1'), 'an update opens the day''s R- report');
select pg_temp.check((
  select jsonb_array_length(summary -> 'jobs_opened') = 2
    and jsonb_array_length(summary -> 'checklists_done') = 1
    and summary -> 'checklists_missed' = '["DB board inspection"]'::jsonb
  from public.fn_build_daily_report('c0000000-0000-0000-0000-0000000000a1', public._harare_today())),
  'the report sums up job cards and checklists');
select pg_temp.fails($$select public.fn_approve_report((select id from public.daily_reports
  where site_id = 'c0000000-0000-0000-0000-0000000000a1'), 'ok')$$, 'NOT_ALLOWED', 'technicians cannot approve');
select pg_temp.as_owner();
select pg_temp.act_as('c0000000-0000-0000-0000-000000000001');
select public.fn_approve_report((select id from public.daily_reports
  where site_id = 'c0000000-0000-0000-0000-0000000000a1'), 'Good day');
select pg_temp.check((select status = 'approved' and supervisor_comment = 'Good day' from public.daily_reports
  where site_id = 'c0000000-0000-0000-0000-0000000000a1'), 'supervisors approve with a comment');
select pg_temp.fails($$select public.fn_add_report_update('c0000000-0000-0000-0000-0000000000e2',
  'c0000000-0000-0000-0000-0000000000a1', public._harare_today(), 'Late note', null)$$,
  'CONFLICT', 'approved reports take no more updates');
select pg_temp.as_owner();

rollback;
