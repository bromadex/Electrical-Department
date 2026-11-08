-- Behaviour checks for 0039_count_at_time. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('fe390000-0000-0000-0000-0000000000a1', 'CAT', 'Count site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('fe390000-0000-0000-0000-000000000001', 'cat-store@test', '{"full_name":"Cat Store"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'fe390000-0000-0000-0000-000000000001'::uuid, id, 'fe390000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Storekeeper';

select pg_temp.act_as('fe390000-0000-0000-0000-000000000001');
select public.fn_save_item('fe390000-0000-0000-0000-0000000000b1', 'fe390000-0000-0000-0000-0000000000a1',
  'Cable 4mm', 'm', 'cable', 'A1', 0, false);
select public.fn_save_item('fe390000-0000-0000-0000-0000000000b2', 'fe390000-0000-0000-0000-0000000000a1',
  'Lugs 16mm', 'pcs', 'lugs', 'A2', 0, false);
select public.fn_save_item('fe390000-0000-0000-0000-0000000000b3', 'fe390000-0000-0000-0000-0000000000a1',
  'Fuses 10A', 'pcs', 'consumables', 'A3', 0, false);
select public.fn_receive_stock(gen_random_uuid(), 'fe390000-0000-0000-0000-0000000000b1', 100, null);
select public.fn_receive_stock(gen_random_uuid(), 'fe390000-0000-0000-0000-0000000000b2', 20, null);
select public.fn_receive_stock(gen_random_uuid(), 'fe390000-0000-0000-0000-0000000000b3', 10, null);

-- The receipts above happened "now"; the count was typed an hour earlier,
-- when the shelves were empty, so pretend the stock arrived before it.
select pg_temp.as_owner();
update public.stock_moves set created_at = now() - interval '2 hours'
where item_id in ('fe390000-0000-0000-0000-0000000000b1', 'fe390000-0000-0000-0000-0000000000b2',
  'fe390000-0000-0000-0000-0000000000b3');
-- Then 30 m of cable and 15 fuses went out after the count was typed.
insert into public.stock_moves (id, item_id, site_id, kind, qty, balance_after, note, created_at)
values (gen_random_uuid(), 'fe390000-0000-0000-0000-0000000000b1', 'fe390000-0000-0000-0000-0000000000a1',
  'issue', -30, 70, 'after the count', now() - interval '30 minutes');
update public.store_items set on_hand = 70 where id = 'fe390000-0000-0000-0000-0000000000b1';
insert into public.stock_moves (id, item_id, site_id, kind, qty, balance_after, note, created_at)
values (gen_random_uuid(), 'fe390000-0000-0000-0000-0000000000b3', 'fe390000-0000-0000-0000-0000000000a1',
  'issue', -8, 2, 'after the count', now() - interval '30 minutes');
update public.store_items set on_hand = 2 where id = 'fe390000-0000-0000-0000-0000000000b3';
select pg_temp.act_as('fe390000-0000-0000-0000-000000000001');

select public.fn_submit_count('fe390000-0000-0000-0000-0000000000f1', 'fe390000-0000-0000-0000-0000000000a1',
  jsonb_build_array(
    jsonb_build_object('item_id', 'fe390000-0000-0000-0000-0000000000b1', 'counted', 95,
      'counted_at', now() - interval '1 hour'),
    jsonb_build_object('item_id', 'fe390000-0000-0000-0000-0000000000b2', 'counted', 18),
    jsonb_build_object('item_id', 'fe390000-0000-0000-0000-0000000000b3', 'counted', 5,
      'counted_at', now() - interval '1 hour')), 'Offline count');

select pg_temp.check((select on_hand = 65 from public.store_items where id = 'fe390000-0000-0000-0000-0000000000b1'),
  'a count typed before an issue keeps the issue (100 then, 95 counted, 30 out since: 65)');
select pg_temp.check((select expected = 100 and counted = 95 and counted_at < now()
  from public.stock_count_lines where item_id = 'fe390000-0000-0000-0000-0000000000b1'),
  'the line keeps stock as it was when counted, and when');
select pg_temp.check((select on_hand = 18 from public.store_items where id = 'fe390000-0000-0000-0000-0000000000b2'),
  'a line without a time is counted as of now, as before');
select pg_temp.check((select on_hand = 0 from public.store_items where id = 'fe390000-0000-0000-0000-0000000000b3'),
  'more issued since than counted takes stock to 0, not below');
select pg_temp.check((select note like '%stock goes to 0%' from public.stock_moves
  where kind = 'count' and item_id = 'fe390000-0000-0000-0000-0000000000b3'),
  'and the correction says so');
select pg_temp.check((select differences = 3 from public.stock_counts where id = 'fe390000-0000-0000-0000-0000000000f1'),
  'the count records its differences');

-- A phone clock ahead of the server is treated as now; a stale one as 14 days.
select public.fn_submit_count('fe390000-0000-0000-0000-0000000000f2', 'fe390000-0000-0000-0000-0000000000a1',
  jsonb_build_array(jsonb_build_object('item_id', 'fe390000-0000-0000-0000-0000000000b2', 'counted', 17,
    'counted_at', now() + interval '3 days')), null);
select pg_temp.check((select on_hand = 17 from public.store_items where id = 'fe390000-0000-0000-0000-0000000000b2')
  and (select counted_at = now() from public.stock_count_lines where count_id = 'fe390000-0000-0000-0000-0000000000f2'),
  'a time in the future counts as now');
select public.fn_submit_count('fe390000-0000-0000-0000-0000000000f3', 'fe390000-0000-0000-0000-0000000000a1',
  jsonb_build_array(jsonb_build_object('item_id', 'fe390000-0000-0000-0000-0000000000b2', 'counted', 17,
    'counted_at', 'not a time')), null);
select pg_temp.check((select counted_at = now() from public.stock_count_lines where count_id = 'fe390000-0000-0000-0000-0000000000f3'),
  'an unreadable time counts as now');
select pg_temp.as_owner();

rollback;
