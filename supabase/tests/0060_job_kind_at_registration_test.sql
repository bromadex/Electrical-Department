-- Behaviour checks for 0060_job_kind_at_registration. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('f6000000-0000-0000-0000-0000000000a1', 'JKD', 'Job kind site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('f6000000-0000-0000-0000-000000000001', 'jk-sup@test', '{"full_name":"JK Supervisor"}'),
  ('f6000000-0000-0000-0000-000000000002', 'jk-tech@test', '{"full_name":"JK Tech"}'),
  ('f6000000-0000-0000-0000-000000000003', 'jk-sup2@test', '{"full_name":"JK Other"}');
insert into public.user_roles (user_id, role_id, site_id)
select u.id, r.id, 'f6000000-0000-0000-0000-0000000000a1'::uuid
from (values
  ('f6000000-0000-0000-0000-000000000001'::uuid, 'Supervisor'),
  ('f6000000-0000-0000-0000-000000000002'::uuid, 'Technician')
) as u (id, role)
join public.roles r on r.name = u.role;

select pg_temp.act_as('f6000000-0000-0000-0000-000000000001');
select public.fn_register_job_card('f6000000-0000-0000-0000-0000000000b1', null,
  'f6000000-0000-0000-0000-0000000000a1', null, 'Block C', null, 'Office manager', null, null, null, null, null, null,
  'Install a new DB in Block C', 'Supply and install a 12-way board for the new offices.', 'none', 'P4', null);
select public.fn_set_job_kind('f6000000-0000-0000-0000-0000000000b1', 'installation');
select pg_temp.check((select maintenance_type = 'installation' from public.job_cards
  where id = 'f6000000-0000-0000-0000-0000000000b1'),
  'whoever registers a job says it is planned work, not a fault');
select pg_temp.fails($$select public.fn_set_job_kind('f6000000-0000-0000-0000-0000000000b1', 'party')$$,
  'INVALID', 'only the known kinds of work');

select pg_temp.act_as('f6000000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_set_job_kind('f6000000-0000-0000-0000-0000000000b1', 'reactive')$$,
  'NOT_ALLOWED', 'someone else cannot change it');
select pg_temp.act_as('f6000000-0000-0000-0000-000000000003');
select pg_temp.fails($$select public.fn_set_job_kind('f6000000-0000-0000-0000-0000000000b1', 'reactive')$$,
  'NOT_ALLOWED', 'nor someone from another site');

-- The assessment decides once made.
select pg_temp.act_as('f6000000-0000-0000-0000-000000000001');
select public.fn_assess_job_card('f6000000-0000-0000-0000-0000000000b1', true, 'improvement', 'minor', 'low', null,
  'operational', null, null, null, false, false, false, null, null, null, null, null);
select public.fn_set_job_kind('f6000000-0000-0000-0000-0000000000b1', 'installation');
select pg_temp.check((select maintenance_type = 'improvement' from public.job_cards
  where id = 'f6000000-0000-0000-0000-0000000000b1'),
  'after assessment the engineer''s choice stands');
select pg_temp.as_owner();

rollback;
