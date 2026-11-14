-- Behaviour checks for 0041_equipment_history_reserved_stock. Runs in a
-- transaction and rolls back.
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

insert into public.sites (id, code, name) values ('fe410000-0000-0000-0000-0000000000a1', 'EHA', 'History site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('fe410000-0000-0000-0000-000000000001', 'eh-sup@test', '{"full_name":"Eh Sup"}'),
  ('fe410000-0000-0000-0000-000000000002', 'eh-nobody@test', '{"full_name":"Eh Nobody"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'fe410000-0000-0000-0000-000000000001'::uuid, id, 'fe410000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name in ('Supervisor', 'Storekeeper');

insert into public.assets (id, site_id, tag, name) values
  ('fe410000-0000-0000-0000-0000000000e1', 'fe410000-0000-0000-0000-0000000000a1', 'GEN-03', 'Generator 3'),
  ('fe410000-0000-0000-0000-0000000000e2', 'fe410000-0000-0000-0000-0000000000a1', 'PMP-01', 'Pump 1');

-- GEN-03: three breakdowns this month, two of them out of service for
-- overlapping times (10:00-14:00 and 12:00-16:00 = 6 h, not 8), one still open.
insert into public.job_cards (id, number, source, site_id, location, received_at, reporter_name, title,
  description, priority, asset_id, maintenance_type, equipment_state, status, closed_at)
select gen_random_uuid(), 'EHA-JC-' || n, 'direct', 'fe410000-0000-0000-0000-0000000000a1', 'Plant',
  r, 'Foreman', 'Generator fault', 'Trips on load',
  (select code from public.priority_levels order by 1 limit 1),
  'fe410000-0000-0000-0000-0000000000e1', mt, st, s, c
from (values
  (1, date_trunc('day', now()) - interval '10 days' + interval '10 hours', 'corrective', 'out_of_service', 'closed',
     date_trunc('day', now()) - interval '10 days' + interval '14 hours'),
  (2, date_trunc('day', now()) - interval '10 days' + interval '12 hours', 'emergency', 'out_of_service', 'closed',
     date_trunc('day', now()) - interval '10 days' + interval '16 hours'),
  (3, now() - interval '2 hours', 'reactive', 'out_of_service', 'registered', null::timestamptz),
  (4, now() - interval '5 days', 'preventive', 'operational', 'closed', now() - interval '5 days')
) v(n, r, mt, st, s, c);
-- PMP-01: one fault 60 days ago.
insert into public.job_cards (id, number, source, site_id, location, received_at, reporter_name, title,
  description, priority, asset_id, maintenance_type, equipment_state, status, closed_at)
values (gen_random_uuid(), 'EHA-JC-9', 'direct', 'fe410000-0000-0000-0000-0000000000a1', 'Plant',
  now() - interval '60 days', 'Foreman', 'Pump fault', 'Seal leak',
  (select code from public.priority_levels order by 1 limit 1),
  'fe410000-0000-0000-0000-0000000000e2', 'corrective', 'degraded', 'closed', now() - interval '59 days');

select pg_temp.act_as('fe410000-0000-0000-0000-000000000001');
create temp table h as select * from public.fn_equipment_history('fe410000-0000-0000-0000-0000000000a1', 90);
select pg_temp.check((select faults = 3 and faults_30 = 3 from h where tag = 'GEN-03'),
  'faults count corrective, emergency and reactive work, not preventive');
select pg_temp.check((select down_hours between 7.9 and 8.1 from h where tag = 'GEN-03'),
  'overlapping breakdowns count once (6 h) plus the open one so far (2 h)');
select pg_temp.check((select down_now from h where tag = 'GEN-03'), 'equipment still out of service shows as down now');
select pg_temp.check((select faults = 1 and faults_30 = 0 and down_hours = 0 and not down_now from h where tag = 'PMP-01'),
  'degraded equipment is not counted as down');
select pg_temp.check((select tag from h limit 1) = 'GEN-03', 'the most repeated faults come first');
select pg_temp.check((select count(*) = 1 from public.fn_equipment_history('fe410000-0000-0000-0000-0000000000a1', 30)),
  'a shorter period leaves out equipment with nothing in it');

-- Reserved stock.
select public.fn_save_item('fe410000-0000-0000-0000-0000000000b1', 'fe410000-0000-0000-0000-0000000000a1',
  'Cable 16mm', 'm', 'cable', 'A1', 0, false);
select public.fn_receive_stock(gen_random_uuid(), 'fe410000-0000-0000-0000-0000000000b1', 100, null);
select pg_temp.as_owner();
insert into public.material_requests (id, site_id, code, requested_by, status)
values ('fe410000-0000-0000-0000-0000000000d1', 'fe410000-0000-0000-0000-0000000000a1', 'EHA-MR-1',
  'fe410000-0000-0000-0000-000000000001', 'approved'),
  ('fe410000-0000-0000-0000-0000000000d2', 'fe410000-0000-0000-0000-0000000000a1', 'EHA-MR-2',
  'fe410000-0000-0000-0000-000000000001', 'pending');
insert into public.mr_lines (id, mr_id, item_id, description, unit, qty, issued_qty) values
  (gen_random_uuid(), 'fe410000-0000-0000-0000-0000000000d1', 'fe410000-0000-0000-0000-0000000000b1', 'Cable 16mm', 'm', 60, 20),
  (gen_random_uuid(), 'fe410000-0000-0000-0000-0000000000d2', 'fe410000-0000-0000-0000-0000000000b1', 'Cable 16mm', 'm', 30, 0);
select pg_temp.act_as('fe410000-0000-0000-0000-000000000001');
select pg_temp.check((select on_hand = 100 and reserved = 40 and available = 60 from public.store_item_availability
  where item_id = 'fe410000-0000-0000-0000-0000000000b1'),
  'approved requests not yet issued reserve stock; pending ones do not');
select pg_temp.as_owner();
update public.material_requests set status = 'rejected' where id = 'fe410000-0000-0000-0000-0000000000d1';
select pg_temp.act_as('fe410000-0000-0000-0000-000000000001');
select pg_temp.check((select reserved = 0 and available = 100 from public.store_item_availability
  where item_id = 'fe410000-0000-0000-0000-0000000000b1'), 'a request no longer approved releases it');

select pg_temp.act_as('fe410000-0000-0000-0000-000000000002');
select pg_temp.check((select count(*) = 0 from public.fn_equipment_history(null, 90)),
  'someone without a role sees no equipment history');
select pg_temp.as_owner();

rollback;
