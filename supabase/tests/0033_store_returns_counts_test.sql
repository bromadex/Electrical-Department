-- Behaviour checks for 0033_store_returns_counts. Runs in a transaction and rolls back.
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
  ('fd000000-0000-0000-0000-0000000000a1', 'SRA', 'Return site'),
  ('fd000000-0000-0000-0000-0000000000a2', 'SRB', 'Other return site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('fd000000-0000-0000-0000-000000000001', 'sr-store@test', '{"full_name":"Sr Store"}'),
  ('fd000000-0000-0000-0000-000000000002', 'sr-tech@test', '{"full_name":"Sr Tech"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'fd000000-0000-0000-0000-000000000001'::uuid, id, 'fd000000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Storekeeper'
union all
select 'fd000000-0000-0000-0000-000000000001'::uuid, id, 'fd000000-0000-0000-0000-0000000000a2'::uuid
from public.roles where name = 'Storekeeper'
union all
select 'fd000000-0000-0000-0000-000000000002'::uuid, id, 'fd000000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Technician';
insert into public.job_cards (id, number, source, site_id, location, received_at, reporter_name, title, description, priority)
values ('fd000000-0000-0000-0000-0000000000c1', 'SRA-JC-0001', 'direct', 'fd000000-0000-0000-0000-0000000000a1',
  'MCC room', now(), 'Plant foreman', 'Rewire lighting', 'Rewire the workshop lighting circuit',
  (select code from public.priority_levels order by 1 limit 1));

select pg_temp.act_as('fd000000-0000-0000-0000-000000000001');
select public.fn_save_item('fd000000-0000-0000-0000-0000000000b1', 'fd000000-0000-0000-0000-0000000000a1',
  '20mm brass gland', 'pcs', 'glands', 'B2', 10, false);
select public.fn_save_item('fd000000-0000-0000-0000-0000000000b2', 'fd000000-0000-0000-0000-0000000000a1',
  'LED floodlight 100W', 'pcs', 'lamps', 'C1', 0, false);
select public.fn_save_item('fd000000-0000-0000-0000-0000000000b3', 'fd000000-0000-0000-0000-0000000000a2',
  'Elsewhere lug', 'pcs', 'lugs', null, 0, false);
select public.fn_receive_stock(gen_random_uuid(), 'fd000000-0000-0000-0000-0000000000b1', 30, null);
select public.fn_receive_stock(gen_random_uuid(), 'fd000000-0000-0000-0000-0000000000b2', 8, null);
select public.fn_issue_stock(gen_random_uuid(), 'fd000000-0000-0000-0000-0000000000b1', 20,
  'fd000000-0000-0000-0000-0000000000c1', null, null, null);

select pg_temp.check((select balance_after = 16 and kind = 'return' from public.fn_return_stock(
  'fd000000-0000-0000-0000-0000000000e1', 'fd000000-0000-0000-0000-0000000000b1', 6,
  'fd000000-0000-0000-0000-0000000000c1', 'fd000000-0000-0000-0000-000000000002', null, 'Not used')),
  'unused stock comes back from the job card');
select pg_temp.check((select balance_after = 16 from public.fn_return_stock(
  'fd000000-0000-0000-0000-0000000000e1', 'fd000000-0000-0000-0000-0000000000b1', 6, null, null, 'x', null)),
  'sending the same return again changes nothing');
select pg_temp.fails($$select public.fn_adjust_stock(gen_random_uuid(), 'fd000000-0000-0000-0000-0000000000b1', -2, ' ')$$,
  'INVALID', 'an adjustment needs a reason');
select pg_temp.check((select balance_after = 14 and note = 'Two cracked in the bin' from public.fn_adjust_stock(
  gen_random_uuid(), 'fd000000-0000-0000-0000-0000000000b1', -2, 'Two cracked in the bin')),
  'adjusting with a reason corrects stock');
select pg_temp.fails($$select public.fn_adjust_stock(gen_random_uuid(), 'fd000000-0000-0000-0000-0000000000b2', -9, 'Lost')$$,
  'INVALID', 'adjustments never take stock below zero');

select pg_temp.check((select items = 2 and differences = 1 from public.fn_submit_count(
  'fd000000-0000-0000-0000-0000000000f1', 'fd000000-0000-0000-0000-0000000000a1',
  '[{"item_id":"fd000000-0000-0000-0000-0000000000b1","counted":9},
    {"item_id":"fd000000-0000-0000-0000-0000000000b2","counted":8}]', 'Monthly count')),
  'a count records every item and corrects only the ones that differ');
select pg_temp.check((select items = 2 from public.fn_submit_count(
  'fd000000-0000-0000-0000-0000000000f1', 'fd000000-0000-0000-0000-0000000000a1', '[]', null)),
  'sending the same count again changes nothing');
select pg_temp.fails($$select public.fn_submit_count(gen_random_uuid(), 'fd000000-0000-0000-0000-0000000000a1',
  '[{"item_id":"fd000000-0000-0000-0000-0000000000b3","counted":1}]', null)$$, 'INVALID',
  'a count only covers the site''s own items');
select pg_temp.as_owner();

select pg_temp.check((select on_hand = 9 from public.store_items where id = 'fd000000-0000-0000-0000-0000000000b1')
  and (select sum(qty) = 9 from public.stock_moves where item_id = 'fd000000-0000-0000-0000-0000000000b1'),
  'stock on hand still equals the sum of its moves');
select pg_temp.check((select count(*) = 1 and bool_and(count_id = 'fd000000-0000-0000-0000-0000000000f1' and qty = -5)
  from public.stock_moves where kind = 'count' and item_id = 'fd000000-0000-0000-0000-0000000000b1'),
  'the count''s correction is linked to it');
select pg_temp.check((select count(*) = 1 from public.notifications
  where user_id = 'fd000000-0000-0000-0000-000000000001' and type = 'low_stock'
    and link = 'item:fd000000-0000-0000-0000-0000000000b1'), 'falling under the minimum on a count alerts the store');

select pg_temp.act_as('fd000000-0000-0000-0000-000000000002');
select pg_temp.check((select count(*) = 1 from public.stock_counts where id = 'fd000000-0000-0000-0000-0000000000f1')
  and (select count(*) = 2 from public.stock_count_lines where count_id = 'fd000000-0000-0000-0000-0000000000f1'),
  'technicians see counts');
select pg_temp.fails($$select public.fn_adjust_stock(gen_random_uuid(), 'fd000000-0000-0000-0000-0000000000b1', 1, 'Found one')$$,
  'NOT_ALLOWED', 'but cannot adjust');
select pg_temp.fails($$select public.fn_return_stock(gen_random_uuid(), 'fd000000-0000-0000-0000-0000000000b1', 1,
  null, null, 'Me', null)$$, 'NOT_ALLOWED', 'or take returns');
select pg_temp.fails($$select public.fn_submit_count(gen_random_uuid(), 'fd000000-0000-0000-0000-0000000000a1',
  '[{"item_id":"fd000000-0000-0000-0000-0000000000b2","counted":1}]', null)$$, 'NOT_ALLOWED', 'or count');
select pg_temp.as_owner();

rollback;
