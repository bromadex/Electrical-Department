-- Behaviour checks for 0035_procurement. Runs in a transaction and rolls back.
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
  ('ff000000-0000-0000-0000-0000000000a1', 'PRA', 'Procurement site'),
  ('ff000000-0000-0000-0000-0000000000a2', 'PRB', 'Other procurement site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('ff000000-0000-0000-0000-000000000001', 'pr-tech@test', '{"full_name":"Pr Tech"}'),
  ('ff000000-0000-0000-0000-000000000002', 'pr-sup@test', '{"full_name":"Pr Sup"}'),
  ('ff000000-0000-0000-0000-000000000003', 'pr-store@test', '{"full_name":"Pr Store"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'ff000000-0000-0000-0000-000000000001'::uuid, id, 'ff000000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Technician'
union all
select 'ff000000-0000-0000-0000-000000000002'::uuid, id, 'ff000000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Supervisor'
union all
select 'ff000000-0000-0000-0000-000000000003'::uuid, id, null::uuid from public.roles where name = 'Storekeeper';
insert into public.job_cards (id, number, source, site_id, location, received_at, reporter_name, title, description, priority)
values ('ff000000-0000-0000-0000-0000000000c1', 'PRA-JC-0001', 'direct', 'ff000000-0000-0000-0000-0000000000a1', 'Plant',
  now(), 'Foreman', 'Replace DB board', 'Replace the distribution board in the workshop',
  (select code from public.priority_levels order by 1 limit 1));
insert into public.projects (id, site_id, code, name) values
  ('ff000000-0000-0000-0000-0000000000f1', 'ff000000-0000-0000-0000-0000000000a1', 'P-9351', 'Workshop rewiring');

select pg_temp.act_as('ff000000-0000-0000-0000-000000000003');
select public.fn_save_item('ff000000-0000-0000-0000-0000000000b1', 'ff000000-0000-0000-0000-0000000000a1',
  '2.5mm twin and earth', 'm', 'cable', null, 0, false);
select public.fn_save_item('ff000000-0000-0000-0000-0000000000b2', 'ff000000-0000-0000-0000-0000000000a2',
  'Other site lug', 'pcs', 'lugs', null, 0, false);
select public.fn_receive_stock(gen_random_uuid(), 'ff000000-0000-0000-0000-0000000000b1', 100, null);
select pg_temp.as_owner();

-- Material request
select pg_temp.act_as('ff000000-0000-0000-0000-000000000001');
select pg_temp.fails($$select public.fn_create_mr(gen_random_uuid(), 'ff000000-0000-0000-0000-0000000000a1', null, null,
  null, null, '[{"item_id":"ff000000-0000-0000-0000-0000000000b2","qty":1}]')$$, 'INVALID',
  'only items in the site''s own store');
select pg_temp.check((select code = 'MR-0001' and status = 'pending' from public.fn_create_mr(
  'ff000000-0000-0000-0000-0000000000d1', 'ff000000-0000-0000-0000-0000000000a1',
  'ff000000-0000-0000-0000-0000000000c1', null, current_date + 2, 'For the DB board',
  '[{"item_id":"ff000000-0000-0000-0000-0000000000b1","qty":60},
    {"description":"36-way DB board","unit":"pcs","qty":1}]')), 'a technician asks for materials for a job card');
select pg_temp.fails($$select public.fn_decide_mr('ff000000-0000-0000-0000-0000000000d1', true, null)$$,
  'NOT_ALLOWED', 'technicians cannot approve');
select pg_temp.as_owner();
select pg_temp.check((select count(*) = 1 from public.notifications
  where user_id = 'ff000000-0000-0000-0000-000000000002' and link = 'mr:ff000000-0000-0000-0000-0000000000d1'),
  'the supervisor is asked to approve');

select pg_temp.act_as('ff000000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_decide_mr('ff000000-0000-0000-0000-0000000000d1', false, '')$$,
  'INVALID', 'a rejection needs a reason');
select pg_temp.check((select status = 'approved' from public.fn_decide_mr('ff000000-0000-0000-0000-0000000000d1',
  true, null)), 'the supervisor approves');
select pg_temp.as_owner();

-- Issue from stock
create temp table ln as select id, item_id from public.mr_lines where mr_id = 'ff000000-0000-0000-0000-0000000000d1';
grant select on ln to authenticated;
select pg_temp.act_as('ff000000-0000-0000-0000-000000000003');
select pg_temp.check((select status = 'part_issued' from public.fn_issue_mr('ff000000-0000-0000-0000-0000000000e1',
  'ff000000-0000-0000-0000-0000000000d1',
  jsonb_build_array(jsonb_build_object('line_id', (select id from ln where item_id is not null), 'qty', 60)))),
  'the store issues the cable; the board is still to buy');
select pg_temp.check((select status = 'part_issued' from public.fn_issue_mr('ff000000-0000-0000-0000-0000000000e1',
  'ff000000-0000-0000-0000-0000000000d1',
  jsonb_build_array(jsonb_build_object('line_id', (select id from ln where item_id is not null), 'qty', 60))))
  and (select on_hand = 40 from public.store_items where id = 'ff000000-0000-0000-0000-0000000000b1'),
  'sending the same issue again changes nothing');
select pg_temp.fails($$select public.fn_issue_mr(gen_random_uuid(), 'ff000000-0000-0000-0000-0000000000d1',
  jsonb_build_array(jsonb_build_object('line_id', (select id from ln where item_id is not null), 'qty', 1)))$$,
  'INVALID', 'never more than was asked for');
select pg_temp.fails($$select public.fn_issue_mr(gen_random_uuid(), 'ff000000-0000-0000-0000-0000000000d1',
  jsonb_build_array(jsonb_build_object('line_id', (select id from ln where item_id is null), 'qty', 1)))$$,
  'INVALID', 'something not stocked is ordered, not issued');
select pg_temp.check((select job_card_id = 'ff000000-0000-0000-0000-0000000000c1'
    and mr_id = 'ff000000-0000-0000-0000-0000000000d1' and note = 'MR-0001'
  from public.stock_moves where item_id = 'ff000000-0000-0000-0000-0000000000b1' and kind = 'issue'),
  'the stock goes to the request''s job card');

-- Suppliers and a purchase
select public.fn_save_supplier('ff000000-0000-0000-0000-0000000000a9', 'ff000000-0000-0000-0000-0000000000a1',
  'Electro Supplies', 'Mr Moyo', '0772 000 000', null, false);
select pg_temp.fails($$select public.fn_save_supplier(gen_random_uuid(), 'ff000000-0000-0000-0000-0000000000a1',
  'electro supplies', null, null, null, false)$$, 'CONFLICT', 'one supplier per name');
select pg_temp.check((select code = 'PO-0001' and status = 'requested' from public.fn_create_po(
  'ff000000-0000-0000-0000-0000000000e2', 'ff000000-0000-0000-0000-0000000000a1',
  'ff000000-0000-0000-0000-0000000000a9', null, current_date + 5, null,
  jsonb_build_array(
    jsonb_build_object('description', '36-way DB board', 'unit', 'pcs', 'qty', 1, 'unit_price', 180,
      'mr_line_id', (select id from ln where item_id is null)),
    jsonb_build_object('item_id', 'ff000000-0000-0000-0000-0000000000b1', 'qty', 200, 'unit_price', 1.2)))),
  'the store raises a purchase from the request and adds stock');
select pg_temp.check((select status = 'ordered' and po_number = 'BRV-5521' from public.fn_set_po_status(
  'ff000000-0000-0000-0000-0000000000e2', 'ordered', 'BRV-5521', null)), 'and marks it ordered');
create temp table pl as select id, item_id from public.po_lines where po_id = 'ff000000-0000-0000-0000-0000000000e2';
grant select on pl to authenticated;
select pg_temp.check((select status = 'ordered' from public.fn_receive_po('ff000000-0000-0000-0000-0000000000e3',
  'ff000000-0000-0000-0000-0000000000e2',
  jsonb_build_array(jsonb_build_object('line_id', (select id from pl where item_id is not null), 'qty', 150)),
  'First load')), 'part of a delivery keeps the purchase open');
select pg_temp.check((select on_hand = 190 from public.store_items where id = 'ff000000-0000-0000-0000-0000000000b1'),
  'and goes into stock');
select pg_temp.check((select status = 'ordered' from public.fn_receive_po('ff000000-0000-0000-0000-0000000000e3',
  'ff000000-0000-0000-0000-0000000000e2',
  jsonb_build_array(jsonb_build_object('line_id', (select id from pl where item_id is not null), 'qty', 150)), null))
  and (select on_hand = 190 from public.store_items where id = 'ff000000-0000-0000-0000-0000000000b1'),
  'receiving the same delivery again changes nothing');
select pg_temp.check((select status = 'delivered' and delivered_at is not null from public.fn_receive_po(
  gen_random_uuid(), 'ff000000-0000-0000-0000-0000000000e2',
  jsonb_build_array(jsonb_build_object('line_id', (select id from pl where item_id is not null), 'qty', 50),
    jsonb_build_object('line_id', (select id from pl where item_id is null), 'qty', 1)), null)),
  'the rest arrives and the purchase is delivered');
select pg_temp.as_owner();
select pg_temp.check((select status = 'issued' from public.material_requests where id = 'ff000000-0000-0000-0000-0000000000d1'),
  'the bought board completes the request');
select pg_temp.check((select count(*) >= 1 from public.notifications
  where user_id = 'ff000000-0000-0000-0000-000000000001' and link = 'po:ff000000-0000-0000-0000-0000000000e2'),
  'the requester hears the delivery arrived');

select pg_temp.act_as('ff000000-0000-0000-0000-000000000001');
select pg_temp.check((select count(*) = 1 from public.material_requests where id = 'ff000000-0000-0000-0000-0000000000d1')
  and (select count(*) = 0 from public.purchase_orders), 'technicians see requests but not purchase prices');
select pg_temp.as_owner();

-- BOQ
select pg_temp.act_as('ff000000-0000-0000-0000-000000000002');
select pg_temp.check(public.fn_import_boq('ff000000-0000-0000-0000-0000000000f1',
  '[{"description":"2.5mm twin and earth","unit":"m","qty":500},
    {"description":"Weatherproof isolator 63A","unit":"pcs","qty":4}]', false) = 2, 'a supervisor loads the BOQ');
select pg_temp.check((select item_id = 'ff000000-0000-0000-0000-0000000000b1' from public.boq_lines
  where description = '2.5mm twin and earth'), 'a BOQ line naming a store item is linked to it');
select pg_temp.as_owner();

select pg_temp.act_as('ff000000-0000-0000-0000-000000000003');
select public.fn_issue_stock(gen_random_uuid(), 'ff000000-0000-0000-0000-0000000000b1', 100, null, null, null, null,
  'ff000000-0000-0000-0000-0000000000f1');
select pg_temp.as_owner();

select pg_temp.act_as('ff000000-0000-0000-0000-000000000002');
select pg_temp.check((select issued = 100 and in_stock = 140 and still_needed = 400 and to_request = 400
  from public.boq_status where description = '2.5mm twin and earth'), 'the BOQ compares issued, in stock and still needed');
select pg_temp.check((select status = 'pending' and project_id = 'ff000000-0000-0000-0000-0000000000f1'
  from public.fn_boq_shortfall_to_mr('ff000000-0000-0000-0000-0000000000d2', 'ff000000-0000-0000-0000-0000000000f1', null)),
  'the shortfall becomes one material request');
select pg_temp.check((select count(*) = 2 from public.mr_lines where mr_id = 'ff000000-0000-0000-0000-0000000000d2')
  and (select to_request = 0 and requested = 400 from public.boq_status where description = '2.5mm twin and earth'),
  'with every short line, now counted as requested');
select pg_temp.check((select public.fn_boq_shortfall_to_mr(gen_random_uuid(), 'ff000000-0000-0000-0000-0000000000f1', null) is null),
  'nothing more to request');
select pg_temp.check((select status = 'cancelled' from public.fn_cancel_mr('ff000000-0000-0000-0000-0000000000d2')),
  'a supervisor can cancel a request');
select pg_temp.as_owner();

rollback;
