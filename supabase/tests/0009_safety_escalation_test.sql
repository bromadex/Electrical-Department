-- Behaviour checks for 0009_safety_escalation. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('d0000000-0000-0000-0000-0000000000a1', 'SAF', 'Safety site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('d0000000-0000-0000-0000-000000000001', 'sf-sup@test', '{"full_name":"Sf Sup"}'),
  ('d0000000-0000-0000-0000-000000000002', 'sf-tech@test', '{"full_name":"Sf Tech"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'd0000000-0000-0000-0000-000000000001'::uuid, id, 'd0000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Supervisor'
union all
select 'd0000000-0000-0000-0000-000000000002'::uuid, id, 'd0000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Technician';

-- Safety check.
select pg_temp.act_as('d0000000-0000-0000-0000-000000000002');
select public.fn_create_job('d0000000-0000-0000-0000-0000000000b1', 'd0000000-0000-0000-0000-0000000000a1', null,
  'Replace MCC breaker', null, 'normal', null, null, null, null, 'corrective', true);
select public.fn_take_job('d0000000-0000-0000-0000-0000000000b1');
select pg_temp.fails($$select public.fn_set_job_status('d0000000-0000-0000-0000-0000000000b1', 'in_progress', null)$$,
  'INVALID', 'isolated work cannot start without a safety check');
select pg_temp.fails($$select public.fn_record_safety_check('d0000000-0000-0000-0000-0000000000c1',
  'd0000000-0000-0000-0000-0000000000b1', array['Hazards identified'], 'L-12')$$,
  'INVALID', 'every item must be confirmed');
select pg_temp.fails($$select public.fn_record_safety_check('d0000000-0000-0000-0000-0000000000c1',
  'd0000000-0000-0000-0000-0000000000b1', public._safety_items(), ' ')$$,
  'INVALID', 'the lock or permit number is needed');
select public.fn_record_safety_check('d0000000-0000-0000-0000-0000000000c1',
  'd0000000-0000-0000-0000-0000000000b1', public._safety_items(), 'Lock 12');
select public.fn_set_job_status('d0000000-0000-0000-0000-0000000000b1', 'in_progress', null);
select pg_temp.check((select status = 'in_progress' from public.jobs
  where id = 'd0000000-0000-0000-0000-0000000000b1'), 'after the check the job starts');
select public.fn_create_job('d0000000-0000-0000-0000-0000000000b2', 'd0000000-0000-0000-0000-0000000000a1', null,
  'Change a lamp', null, 'normal', null, null, null);
select public.fn_take_job('d0000000-0000-0000-0000-0000000000b2');
select public.fn_set_job_status('d0000000-0000-0000-0000-0000000000b2', 'in_progress', null);
select pg_temp.check((select status = 'in_progress' from public.jobs
  where id = 'd0000000-0000-0000-0000-0000000000b2'), 'other jobs start as before');

-- Escalation.
select public.fn_create_job('d0000000-0000-0000-0000-0000000000b3', 'd0000000-0000-0000-0000-0000000000a1', null,
  'Plant tripped', null, 'urgent', now() - interval '2 days', null, null);
select pg_temp.as_owner();
update public.jobs set created_at = now() - interval '45 minutes' where id = 'd0000000-0000-0000-0000-0000000000b3';
select public.fn_escalate_jobs();
select public.fn_escalate_jobs();
select pg_temp.check((select count(*) = 1 from public.notifications
  where title = 'Nobody has taken urgent ' || (select code from public.jobs where id = 'd0000000-0000-0000-0000-0000000000b3')
    and user_id = 'd0000000-0000-0000-0000-000000000001'), 'untaken urgent jobs alert supervisors once');
select pg_temp.check((select count(*) = 1 from public.notifications
  where title like '% is more than a day overdue' and user_id = 'd0000000-0000-0000-0000-000000000001'),
  'long-overdue jobs alert managers once');

-- Names.
insert into auth.users (id, email) values ('d0000000-0000-0000-0000-000000000009', 'john.moyo@test');
select pg_temp.check((select full_name = 'John Moyo' from public.profiles
  where id = 'd0000000-0000-0000-0000-000000000009'), 'people without a name are named from their email');

rollback;
