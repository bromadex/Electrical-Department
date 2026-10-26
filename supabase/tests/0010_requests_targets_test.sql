-- Behaviour checks for 0010_requests_targets. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('e0000000-0000-0000-0000-0000000000a1', 'REQ', 'Request site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('e0000000-0000-0000-0000-000000000001', 'rq-sup@test', '{"full_name":"Rq Sup"}'),
  ('e0000000-0000-0000-0000-000000000002', 'rq-tech@test', '{"full_name":"Rq Tech"}'),
  ('e0000000-0000-0000-0000-000000000003', 'rq-prod@test', '{"full_name":"Rq Production"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'e0000000-0000-0000-0000-000000000001'::uuid, id, 'e0000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Supervisor'
union all
select 'e0000000-0000-0000-0000-000000000002'::uuid, id, 'e0000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Technician'
union all
select 'e0000000-0000-0000-0000-000000000003'::uuid, id, 'e0000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Requester';

-- Targets give jobs a due time.
select pg_temp.act_as('e0000000-0000-0000-0000-000000000002');
select public.fn_create_job('e0000000-0000-0000-0000-0000000000f1', 'e0000000-0000-0000-0000-0000000000a1', null,
  'No due given', null, 'urgent', null, null, null);
select pg_temp.check((select due_at between now() + interval '23 hours' and now() + interval '25 hours'
  from public.jobs where id = 'e0000000-0000-0000-0000-0000000000f1'), 'urgent jobs are due in 24 hours by default');
select pg_temp.fails($$select public.fn_set_priority_target('urgent', 15, 12)$$, 'NOT_ALLOWED', 'only admins change targets');
select pg_temp.as_owner();

-- Requests.
select pg_temp.act_as('e0000000-0000-0000-0000-000000000003');
select pg_temp.check(not exists (select 1 from public.jobs where site_id = 'e0000000-0000-0000-0000-0000000000a1'),
  'requesters do not see the board');
select public.fn_create_request('e0000000-0000-0000-0000-0000000000b1', 'e0000000-0000-0000-0000-0000000000a1', null,
  'Conveyor 2 motor not starting', 'Since the night shift', 'Production', 'urgent');
select public.fn_create_request('e0000000-0000-0000-0000-0000000000b1', 'e0000000-0000-0000-0000-0000000000a1', null,
  'Conveyor 2 motor not starting', 'Since the night shift', 'Production', 'urgent');
select pg_temp.check((select count(*) = 1 and min(code) like 'RQ-%' from public.job_requests),
  'a request gets an RQ- code, once');
select pg_temp.fails($$select public.fn_accept_request('e0000000-0000-0000-0000-0000000000b1', null, null)$$,
  '', 'requesters cannot accept');
select pg_temp.as_owner();
select pg_temp.check(exists (select 1 from public.notifications
  where user_id = 'e0000000-0000-0000-0000-000000000001' and title like 'New request RQ-% from Production'),
  'supervisors are told of new requests');

select pg_temp.act_as('e0000000-0000-0000-0000-000000000001');
select public.fn_accept_request('e0000000-0000-0000-0000-0000000000b1', 'urgent', 'e0000000-0000-0000-0000-000000000002');
select pg_temp.check((select r.status = 'accepted' and j.assignee_id = 'e0000000-0000-0000-0000-000000000002'
    and j.description like '%Requested by Rq Production (Production)%'
  from public.job_requests r join public.jobs j on j.id = r.job_id), 'accepting posts an assigned job');
select pg_temp.fails($$select public.fn_decline_request('e0000000-0000-0000-0000-0000000000b1', 'no')$$,
  'CONFLICT', 'a decided request stays decided');
select pg_temp.as_owner();

select pg_temp.act_as('e0000000-0000-0000-0000-000000000003');
select pg_temp.check((select count(*) = 1 from public.job_requests), 'requesters see their own requests');
select public.fn_create_request('e0000000-0000-0000-0000-0000000000b2', 'e0000000-0000-0000-0000-0000000000a1', null,
  'Paint the office', null, null, 'low');
select pg_temp.as_owner();
select pg_temp.act_as('e0000000-0000-0000-0000-000000000001');
select pg_temp.fails($$select public.fn_decline_request('e0000000-0000-0000-0000-0000000000b2', ' ')$$,
  'INVALID', 'declining needs a reason');
select public.fn_decline_request('e0000000-0000-0000-0000-0000000000b2', 'Not electrical; ask maintenance');
select pg_temp.as_owner();
select pg_temp.check(exists (select 1 from public.notifications
  where user_id = 'e0000000-0000-0000-0000-000000000003' and title like '% was declined'), 'the requester is told');

-- Done jobs tell the requester.
update public.jobs set status = 'done', closed_at = now(), close_note = 'Replaced contactor'
where id = (select job_id from public.job_requests where id = 'e0000000-0000-0000-0000-0000000000b1');
select pg_temp.check(exists (select 1 from public.notifications
  where user_id = 'e0000000-0000-0000-0000-000000000003' and title like '% is done' and body = 'Replaced contactor'),
  'the requester hears when the job is done');

rollback;
