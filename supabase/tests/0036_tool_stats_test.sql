-- Behaviour checks for 0036_tool_stats. Runs in a transaction and rolls back.
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
  ('f1000000-0000-0000-0000-0000000000a1', 'TSA', 'Stats site'),
  ('f1000000-0000-0000-0000-0000000000a2', 'TSB', 'Other stats site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('f1000000-0000-0000-0000-000000000001', 'ts-sup@test', '{"full_name":"Ts Sup"}'),
  ('f1000000-0000-0000-0000-000000000002', 'ts-tech@test', '{"full_name":"Ts Tech"}'),
  ('f1000000-0000-0000-0000-000000000003', 'ts-none@test', '{"full_name":"Ts None"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'f1000000-0000-0000-0000-000000000001'::uuid, id, null::uuid from public.roles where name = 'Supervisor'
union all
select 'f1000000-0000-0000-0000-000000000002'::uuid, id, 'f1000000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Technician';
insert into public.tools (id, site_id, code, name, calibration_due) values
  ('f1000000-0000-0000-0000-0000000000b1', 'f1000000-0000-0000-0000-0000000000a1', 'T-9361', 'Fluke 1587', null),
  ('f1000000-0000-0000-0000-0000000000b2', 'f1000000-0000-0000-0000-0000000000a1', 'T-9362', 'Crimping tool', null),
  ('f1000000-0000-0000-0000-0000000000b3', 'f1000000-0000-0000-0000-0000000000a1', 'T-9363', 'Cable cutter', null),
  ('f1000000-0000-0000-0000-0000000000b4', 'f1000000-0000-0000-0000-0000000000a1', 'T-9364', 'Megger MIT525',
    current_date - 3),
  ('f1000000-0000-0000-0000-0000000000b5', 'f1000000-0000-0000-0000-0000000000a1', 'T-9365', 'Clamp meter',
    current_date + 10),
  ('f1000000-0000-0000-0000-0000000000b6', 'f1000000-0000-0000-0000-0000000000a2', 'T-9366', 'Other site drill', null);
insert into public.tool_issue_forms (id, site_id, code, recipient_name, company) values
  ('f1000000-0000-0000-0000-0000000000e1', 'f1000000-0000-0000-0000-0000000000a1', 'TI-9361', 'Tinashe Mademe', 'Zesa');
insert into public.job_cards (id, number, source, site_id, location, received_at, reporter_name, title, description,
  priority, registered_at)
values ('f1000000-0000-0000-0000-0000000000c1', 'TSA-JC-0001', 'direct', 'f1000000-0000-0000-0000-0000000000a1',
  'Tool store', now(), 'Store', 'Repair T-9362 Crimping tool', 'Came back damaged',
  (select code from public.priority_levels order by 1 limit 1), now() - interval '2 days');
insert into public.job_card_tools (job_card_id, tool_id) values
  ('f1000000-0000-0000-0000-0000000000c1', 'f1000000-0000-0000-0000-0000000000b2');
insert into public.tool_issues (tool_id, issued_to, form_id, issued_at, due_back, returned_at, return_condition) values
  -- lost by an app user, returned yesterday
  ('f1000000-0000-0000-0000-0000000000b1', 'f1000000-0000-0000-0000-000000000002', null,
    now() - interval '10 days', current_date - 2, now() - interval '1 day', 'lost'),
  -- damaged on a form, returned two days ago, five days late
  ('f1000000-0000-0000-0000-0000000000b2', null, 'f1000000-0000-0000-0000-0000000000e1',
    now() - interval '20 days', current_date - 7, now() - interval '2 days' - interval '5 minutes', 'damaged'),
  -- still out, overdue
  ('f1000000-0000-0000-0000-0000000000b3', null, 'f1000000-0000-0000-0000-0000000000e1',
    now() - interval '6 days', current_date - 1, null, null),
  -- returned fine, on time, long ago (outside the range)
  ('f1000000-0000-0000-0000-0000000000b5', 'f1000000-0000-0000-0000-000000000002', null,
    now() - interval '90 days', current_date - 80, now() - interval '85 days', 'good'),
  -- the other site
  ('f1000000-0000-0000-0000-0000000000b6', 'f1000000-0000-0000-0000-000000000002', null,
    now() - interval '3 days', current_date - 2, now() - interval '1 day', 'lost');

select pg_temp.act_as('f1000000-0000-0000-0000-000000000002');
create temp table st as select public.fn_tool_stats('f1000000-0000-0000-0000-0000000000a1',
  current_date - 30, current_date) as s;
select pg_temp.check((select (s -> 'totals' ->> 'returned')::int = 2 and (s -> 'totals' ->> 'lost')::int = 1
    and (s -> 'totals' ->> 'damaged')::int = 1 and (s -> 'totals' ->> 'late')::int = 2
    and (s -> 'totals' ->> 'overdue_now')::int = 1 from st), 'totals for the range at one site');
select pg_temp.check((select s -> 'losses' -> 0 ->> 'holder' = 'Ts Tech' and s -> 'losses' -> 0 ->> 'code' = 'T-9361'
  from st), 'a loss names who had it');
select pg_temp.check((select s -> 'damage' -> 0 ->> 'company' = 'Zesa'
    and s -> 'damage' -> 0 ->> 'repair_number' = 'TSA-JC-0001' from st),
  'damage shows the company and its repair job card');
select pg_temp.check((select (s -> 'late' -> 0 ->> 'days_late')::int = 5 and s -> 'late' -> 0 ->> 'holder' = 'Tinashe Mademe'
  from st), 'late returns say how late, worst first');
select pg_temp.check((select bool_or((x ->> 'still_out')::boolean) from st, jsonb_array_elements(s -> 'late') x),
  'and include what is overdue now');
select pg_temp.check((select jsonb_array_length(s -> 'calibration') = 2
    and (s -> 'calibration' -> 0 ->> 'expired')::boolean and not (s -> 'calibration' -> 1 ->> 'expired')::boolean
  from st), 'calibration expired and due within 30 days');
select pg_temp.check((select s -> 'people' -> 0 ->> 'holder' = 'Ts Tech' and (s -> 'people' -> 0 ->> 'lost')::int = 1
  from st), 'people with losses come first');
select pg_temp.fails($$select public.fn_tool_stats('f1000000-0000-0000-0000-0000000000a1', current_date, current_date - 1)$$,
  'INVALID', 'the range runs forwards');
select pg_temp.as_owner();

select pg_temp.act_as('f1000000-0000-0000-0000-000000000001');
select pg_temp.check((select (public.fn_tool_stats(null, current_date - 30, current_date) -> 'totals' ->> 'lost')::int >= 2),
  'all sites adds up every site');
select pg_temp.as_owner();

select pg_temp.act_as('f1000000-0000-0000-0000-000000000003');
select pg_temp.fails($$select public.fn_tool_stats('f1000000-0000-0000-0000-0000000000a1', current_date - 30, current_date)$$,
  'NOT_ALLOWED', 'someone with no role sees no stats');
select pg_temp.as_owner();

rollback;
