-- Behaviour checks for 0037_stock_stats_imports. Runs in a transaction and rolls back.
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
  ('f2000000-0000-0000-0000-0000000000a1', 'SSA', 'Stock stats site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('f2000000-0000-0000-0000-000000000001', 'ss-store@test', '{"full_name":"Ss Store"}'),
  ('f2000000-0000-0000-0000-000000000002', 'ss-tech@test', '{"full_name":"Ss Tech"}'),
  ('f2000000-0000-0000-0000-000000000003', 'ss-none@test', '{"full_name":"Ss None"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'f2000000-0000-0000-0000-000000000001'::uuid, id, 'f2000000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Storekeeper'
union all
select 'f2000000-0000-0000-0000-000000000002'::uuid, id, 'f2000000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Technician';
insert into public.projects (id, site_id, code, name, target_date) values
  ('f2000000-0000-0000-0000-0000000000f1', 'f2000000-0000-0000-0000-0000000000a1', 'P-9371', 'Pump house',
    current_date - 1);

-- Imports
select pg_temp.act_as('f2000000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_import_items('f2000000-0000-0000-0000-0000000000a1',
  '[{"name":"Lugs 16mm","unit":"pcs","qty":1}]')$$, 'NOT_ALLOWED', 'technicians cannot import items');
select pg_temp.fails($$select public.fn_import_tools('f2000000-0000-0000-0000-0000000000a1',
  '[{"name":"Drill"}]')$$, 'NOT_ALLOWED', 'or tools');
select pg_temp.as_owner();

select pg_temp.act_as('f2000000-0000-0000-0000-000000000001');
select pg_temp.check((select (r ->> 'created')::int = 3 and (r ->> 'updated')::int = 0 from public.fn_import_items(
  'f2000000-0000-0000-0000-0000000000a1',
  '[{"name":"Lugs 16mm","unit":"PCS","category":"lugs","bin":"A1","min_level":50,"on_hand":40},
    {"name":"95mm cable","unit":"m","category":"Cable","on_hand":300},
    {"name":"Mystery part","category":"widgets"},
    {"name":"x"}]') r), 'the store imports items; short names are skipped');
select pg_temp.check((select category = 'other' and unit = 'pcs' from public.store_items where name = 'Mystery part')
  and (select category = 'cable' and on_hand = 300 from public.store_items where name = '95mm cable'),
  'unknown categories become other, and opening stock is received');
select pg_temp.check((select (r ->> 'created')::int = 0 and (r ->> 'updated')::int = 1 from public.fn_import_items(
  'f2000000-0000-0000-0000-0000000000a1', '[{"name":"lugs 16MM","unit":"pcs","category":"lugs","bin":"B4","on_hand":999}]') r),
  'importing an item again updates it');
select pg_temp.check((select bin = 'B4' and on_hand = 40 from public.store_items where name = 'Lugs 16mm'),
  'but never touches its stock');
select pg_temp.check((select (r ->> 'created')::int = 2 and (r ->> 'skipped')::int = 0 from public.fn_import_tools(
  'f2000000-0000-0000-0000-0000000000a1',
  '[{"name":"Fluke 1587","kind":"meter","serial_no":"FL-001","calibration_due":"2027-01-31"},
    {"name":"Crimper","serial_no":"CR-9"}]') r), 'the store imports tools with T- codes');
select pg_temp.check((select (r ->> 'created')::int = 1 and (r ->> 'skipped')::int = 1 from public.fn_import_tools(
  'f2000000-0000-0000-0000-0000000000a1', '[{"name":"Fluke 1587","serial_no":"fl-001"},{"name":"Drill"}]') r),
  'a serial number already in the register is skipped');
select pg_temp.check((select calibration_due = '2027-01-31' and code like 'T-%' from public.tools where serial_no = 'FL-001'),
  'with their calibration dates');

-- Moves for the stats
select public.fn_issue_stock(gen_random_uuid(), (select id from public.store_items where name = '95mm cable'), 120,
  null, null, 'Crew A', null, 'f2000000-0000-0000-0000-0000000000f1');
select public.fn_issue_stock(gen_random_uuid(), (select id from public.store_items where name = 'Lugs 16mm'), 5,
  null, null, 'Crew A', null);
select public.fn_adjust_stock(gen_random_uuid(), (select id from public.store_items where name = 'Lugs 16mm'), -1, 'Crushed');
select pg_temp.as_owner();

select pg_temp.act_as('f2000000-0000-0000-0000-000000000002');
create temp table st as select public.fn_stock_stats('f2000000-0000-0000-0000-0000000000a1',
  current_date - 7, current_date) as s;
select pg_temp.check((select (s -> 'totals' ->> 'items')::int = 3 and (s -> 'totals' ->> 'low')::int = 1
    and (s -> 'totals' ->> 'issues')::int = 2 and (s -> 'totals' ->> 'corrections')::int = 1
    and (s -> 'totals' ->> 'projects_overdue')::int = 1 from st), 'totals for inventory and projects');
select pg_temp.check((select s -> 'top_items' -> 0 ->> 'name' = '95mm cable' and (s -> 'top_items' -> 0 ->> 'qty')::numeric = 120
  from st), 'what went out most comes first');
select pg_temp.check((select x -> 'items' -> 0 ->> 'name' = '95mm cable' and (x -> 'items' -> 0 ->> 'qty')::numeric = 120
  from st, jsonb_array_elements(s -> 'projects') x where x ->> 'code' = 'P-9371'), 'stock used per project');
select pg_temp.check((select s -> 'corrections' -> 0 ->> 'note' = 'Crushed' from st), 'corrections with their reason');
select pg_temp.check((select s -> 'low' -> 0 ->> 'name' = 'Lugs 16mm' from st), 'and what is low');
select pg_temp.as_owner();

select pg_temp.act_as('f2000000-0000-0000-0000-000000000003');
select pg_temp.fails($$select public.fn_stock_stats('f2000000-0000-0000-0000-0000000000a1', current_date - 7, current_date)$$,
  'NOT_ALLOWED', 'someone with no role sees no stock stats');
select pg_temp.as_owner();

rollback;
