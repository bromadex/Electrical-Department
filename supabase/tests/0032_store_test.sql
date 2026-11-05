-- Behaviour checks for 0032_store. Runs in a transaction and rolls back.
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
  ('fc000000-0000-0000-0000-0000000000a1', 'STA', 'Store site'),
  ('fc000000-0000-0000-0000-0000000000a2', 'STB', 'Other store site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('fc000000-0000-0000-0000-000000000001', 'st-store@test', '{"full_name":"St Store"}'),
  ('fc000000-0000-0000-0000-000000000002', 'st-tech@test', '{"full_name":"St Tech"}'),
  ('fc000000-0000-0000-0000-000000000003', 'st-sup@test', '{"full_name":"St Sup"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'fc000000-0000-0000-0000-000000000001'::uuid, id, 'fc000000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Storekeeper'
union all
select 'fc000000-0000-0000-0000-000000000002'::uuid, id, 'fc000000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Technician'
union all
select 'fc000000-0000-0000-0000-000000000003'::uuid, id, 'fc000000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Supervisor';
insert into public.job_cards (id, number, source, site_id, location, received_at, reporter_name, title, description, priority)
values
  ('fc000000-0000-0000-0000-0000000000c1', 'STA-JC-0001', 'direct', 'fc000000-0000-0000-0000-0000000000a1', 'MCC room',
    now(), 'Plant foreman', 'Replace feeder cable', 'The feeder cable to pump 2 is burnt',
    (select code from public.priority_levels order by 1 limit 1)),
  ('fc000000-0000-0000-0000-0000000000c2', 'STB-JC-0001', 'direct', 'fc000000-0000-0000-0000-0000000000a2', 'Plant',
    now(), 'Plant foreman', 'Other site job', 'A job card at the other site',
    (select code from public.priority_levels order by 1 limit 1));

select pg_temp.act_as('fc000000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_save_item('fc000000-0000-0000-0000-0000000000b1',
  'fc000000-0000-0000-0000-0000000000a1', '16mm 4-core cable', 'm', 'cable', 'Rack A', 50, false)$$,
  'NOT_ALLOWED', 'technicians cannot add items');
select pg_temp.as_owner();

select pg_temp.act_as('fc000000-0000-0000-0000-000000000001');
select pg_temp.check((select code = 'I-0001' and on_hand = 0 from public.fn_save_item('fc000000-0000-0000-0000-0000000000b1',
  'fc000000-0000-0000-0000-0000000000a1', '16mm 4-core cable', 'm', 'cable', 'Rack A', 50, false)),
  'the store adds an item with an I- code and nothing in stock');
select pg_temp.fails($$select public.fn_save_item(gen_random_uuid(), 'fc000000-0000-0000-0000-0000000000a1',
  '16MM 4-core cable', 'M', 'cable', null, 0, false)$$, 'CONFLICT', 'the same item and unit cannot be added twice');
select pg_temp.check((select balance_after = 120 from public.fn_receive_stock('fc000000-0000-0000-0000-0000000000e1',
  'fc000000-0000-0000-0000-0000000000b1', 120, 'Delivery from Electro')), 'receiving adds to stock');
select pg_temp.check((select balance_after = 120 from public.fn_receive_stock('fc000000-0000-0000-0000-0000000000e1',
  'fc000000-0000-0000-0000-0000000000b1', 120, 'Delivery from Electro')), 'sending the same receipt again changes nothing');
select pg_temp.check((select balance_after = 60 and qty = -60 from public.fn_issue_stock('fc000000-0000-0000-0000-0000000000e2',
  'fc000000-0000-0000-0000-0000000000b1', 60, 'fc000000-0000-0000-0000-0000000000c1', null, null, null)),
  'issuing to a job card takes it off');
select pg_temp.fails($$select public.fn_issue_stock(gen_random_uuid(), 'fc000000-0000-0000-0000-0000000000b1', 61,
  'fc000000-0000-0000-0000-0000000000c1', null, null, null)$$, 'INVALID', 'stock never goes below zero');
select pg_temp.fails($$select public.fn_issue_stock(gen_random_uuid(), 'fc000000-0000-0000-0000-0000000000b1', 1,
  'fc000000-0000-0000-0000-0000000000c2', null, null, null)$$, 'INVALID', 'only to job cards at the item''s site');
select pg_temp.fails($$select public.fn_issue_stock(gen_random_uuid(), 'fc000000-0000-0000-0000-0000000000b1', 1,
  null, null, ' ', null)$$, 'INVALID', 'an issue says who or which job card');
select pg_temp.check((select balance_after = 45 from public.fn_issue_stock('fc000000-0000-0000-0000-0000000000e3',
  'fc000000-0000-0000-0000-0000000000b1', 15, null, null, 'Contractor: Zesa crew', null)),
  'issuing to someone named, below the minimum');
select public.fn_issue_stock(gen_random_uuid(), 'fc000000-0000-0000-0000-0000000000b1', 5, null,
  'fc000000-0000-0000-0000-000000000002', null, null);
select pg_temp.as_owner();

select pg_temp.check((select on_hand = 40 from public.store_items where id = 'fc000000-0000-0000-0000-0000000000b1')
  and (select sum(qty) = 40 from public.stock_moves where item_id = 'fc000000-0000-0000-0000-0000000000b1'),
  'stock on hand always equals the sum of its moves');
select pg_temp.check((select count(*) = 1 from public.notifications
  where user_id = 'fc000000-0000-0000-0000-000000000001' and type = 'low_stock'
    and link = 'item:fc000000-0000-0000-0000-0000000000b1'), 'the store is told once when it falls under the minimum');
select pg_temp.check((select count(*) = 1 from public.notifications
  where user_id = 'fc000000-0000-0000-0000-000000000003' and type = 'low_stock'
    and link = 'item:fc000000-0000-0000-0000-0000000000b1'), 'and the supervisor');

select pg_temp.act_as('fc000000-0000-0000-0000-000000000002');
select pg_temp.check((select count(*) = 4 from public.stock_moves where item_id = 'fc000000-0000-0000-0000-0000000000b1'),
  'technicians see stock and its history');
select pg_temp.fails($$select public.fn_issue_stock(gen_random_uuid(), 'fc000000-0000-0000-0000-0000000000b1', 1,
  'fc000000-0000-0000-0000-0000000000c1', null, null, null)$$, 'NOT_ALLOWED', 'but cannot issue it');
select pg_temp.fails($$select public.fn_receive_stock(gen_random_uuid(), 'fc000000-0000-0000-0000-0000000000b1', 1, null)$$,
  'NOT_ALLOWED', 'or receive it');
select pg_temp.as_owner();

rollback;
