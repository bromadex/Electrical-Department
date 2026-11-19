-- Behaviour checks for 0057_direct_call_hangup. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('fe570000-0000-0000-0000-0000000000a1', 'DCH', 'Invite site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('fe570000-0000-0000-0000-000000000001', 'dch-a@test', '{"full_name":"DCH Anna"}'),
  ('fe570000-0000-0000-0000-000000000002', 'dch-b@test', '{"full_name":"DCH Ben"}'),
  ('fe570000-0000-0000-0000-000000000003', 'dch-c@test', '{"full_name":"DCH Cara"}');
insert into public.user_roles (user_id, role_id, site_id)
select u, r.id, 'fe570000-0000-0000-0000-0000000000a1'::uuid
from public.roles r, unnest(array['fe570000-0000-0000-0000-000000000001'::uuid,
  'fe570000-0000-0000-0000-000000000002'::uuid, 'fe570000-0000-0000-0000-000000000003'::uuid]) u
where r.name = 'Technician';
insert into public.user_roles (user_id, role_id, site_id)
select 'fe570000-0000-0000-0000-000000000001'::uuid, id, 'fe570000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Supervisor';

create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
create function pg_temp.call(p text) returns uuid language sql as $$
  select id from public.calls where conversation_id = (select v from ids where k = p)
  order by ended_at is null desc, started_at desc limit 1 $$;
create function pg_temp.active(p text) returns integer language sql as $$
  select count(*)::int from public.call_participants where call_id = pg_temp.call(p) and left_at is null $$;

select pg_temp.act_as('fe570000-0000-0000-0000-000000000001');
insert into ids values ('direct', public.fn_open_direct(gen_random_uuid(), 'fe570000-0000-0000-0000-000000000002'));
insert into ids values ('group', (public.fn_create_group(gen_random_uuid(), 'Hang-up group',
  'fe570000-0000-0000-0000-0000000000a1', array['fe570000-0000-0000-0000-000000000002'::uuid])).id);

-- 1. Anna calls Ben, Ben answers, Anna hangs up: Ben's side ends too.
select public.fn_start_call((select v from ids where k = 'direct'), false);
select pg_temp.act_as('fe570000-0000-0000-0000-000000000002');
select public.fn_start_call((select v from ids where k = 'direct'), false);
select pg_temp.check(pg_temp.active('direct') = 2, 'both are in the one-to-one call');
select pg_temp.act_as('fe570000-0000-0000-0000-000000000001');
select public.fn_leave_call(pg_temp.call('direct'));
select pg_temp.as_owner();
select pg_temp.check(pg_temp.active('direct') = 0, 'when Anna hangs up, Ben is out of the call too');
select pg_temp.check((select ended_at is not null from public.calls where id = pg_temp.call('direct')),
  'and the call has ended, so no "Call in progress"');

-- 2. A late "still here" from Ben does not put him back in.
select pg_temp.act_as('fe570000-0000-0000-0000-000000000002');
select public.fn_call_heartbeat(pg_temp.call('direct'));
select pg_temp.as_owner();
select pg_temp.check(pg_temp.active('direct') = 0, 'a late heartbeat does not rejoin the call');

-- 3. With Cara added, the call goes on when one of three leaves.
select pg_temp.act_as('fe570000-0000-0000-0000-000000000001');
select public.fn_start_call((select v from ids where k = 'direct'), false);
select pg_temp.act_as('fe570000-0000-0000-0000-000000000002');
select public.fn_start_call((select v from ids where k = 'direct'), false);
select pg_temp.act_as('fe570000-0000-0000-0000-000000000001');
select public.fn_call_invite((select v from ids where k = 'direct'), array['fe570000-0000-0000-0000-000000000003'::uuid]);
select pg_temp.act_as('fe570000-0000-0000-0000-000000000003');
select public.fn_start_call((select v from ids where k = 'direct'), false);
select pg_temp.act_as('fe570000-0000-0000-0000-000000000001');
select public.fn_leave_call(pg_temp.call('direct'));
select pg_temp.as_owner();
select pg_temp.check(pg_temp.active('direct') = 2, 'with three in it, Ben and Cara carry on when Anna leaves');
select pg_temp.act_as('fe570000-0000-0000-0000-000000000002');
select public.fn_leave_call(pg_temp.call('direct'));
select pg_temp.as_owner();
select pg_temp.check(pg_temp.active('direct') = 0 and
  (select ended_at is not null from public.calls where id = pg_temp.call('direct')),
  'then when Ben leaves, Cara is hung up and the call ends');

-- 4. Group calls are unchanged: the last one there keeps it going.
select pg_temp.act_as('fe570000-0000-0000-0000-000000000001');
select public.fn_start_call((select v from ids where k = 'group'), false);
select pg_temp.act_as('fe570000-0000-0000-0000-000000000002');
select public.fn_start_call((select v from ids where k = 'group'), false);
select pg_temp.act_as('fe570000-0000-0000-0000-000000000001');
select public.fn_leave_call(pg_temp.call('group'));
select pg_temp.as_owner();
select pg_temp.check(pg_temp.active('group') = 1 and
  (select ended_at is null from public.calls where id = pg_temp.call('group')),
  'in a group, Ben stays in the call when Anna leaves');

rollback;
