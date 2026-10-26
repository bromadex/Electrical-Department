-- Behaviour checks for 0005_assets. Runs in a transaction and rolls back.
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

-- A site with a supervisor, a technician and someone from elsewhere.
insert into public.sites (id, code, name) values
  ('90000000-0000-0000-0000-0000000000a1', 'AST', 'Asset test site'),
  ('90000000-0000-0000-0000-0000000000a2', 'ASU', 'Other asset site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('90000000-0000-0000-0000-000000000001', 'ast-sup@test', '{"full_name":"Ast Sup"}'),
  ('90000000-0000-0000-0000-000000000002', 'ast-tech@test', '{"full_name":"Ast Tech"}'),
  ('90000000-0000-0000-0000-000000000003', 'ast-other@test', '{"full_name":"Ast Other"}');
insert into public.user_roles (user_id, role_id, site_id)
select '90000000-0000-0000-0000-000000000001'::uuid, id, '90000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Supervisor'
union all
select '90000000-0000-0000-0000-000000000002'::uuid, id, '90000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Technician'
union all
select '90000000-0000-0000-0000-000000000003'::uuid, id, '90000000-0000-0000-0000-0000000000a2'::uuid from public.roles where name = 'Technician';

-- The register.
select pg_temp.act_as('90000000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_save_asset('90000000-0000-0000-0000-0000000000f1',
  '90000000-0000-0000-0000-0000000000a1', null, 'MCC-01', 'Crusher motor', null, null, null, null, false)$$,
  'NOT_ALLOWED', 'technicians cannot change the register');
select pg_temp.as_owner();
select pg_temp.act_as('90000000-0000-0000-0000-000000000001');
select public.fn_save_asset('90000000-0000-0000-0000-0000000000f1',
  '90000000-0000-0000-0000-0000000000a1', null, ' mcc-01 ', 'Crusher motor', 'Motor', 'WEG 75kW', 'S123', null, false);
select pg_temp.check((select tag = 'MCC-01' and kind = 'Motor' from public.assets
  where id = '90000000-0000-0000-0000-0000000000f1'), 'supervisors add assets; tags are upper-cased');
select pg_temp.fails($$select public.fn_save_asset('90000000-0000-0000-0000-0000000000f2',
  '90000000-0000-0000-0000-0000000000a1', null, 'Mcc-01', 'Another', null, null, null, null, false)$$,
  'CONFLICT', 'tags are unique at a site');
select public.fn_save_asset('90000000-0000-0000-0000-0000000000f1',
  '90000000-0000-0000-0000-0000000000a1', null, 'MCC-01', 'Crusher motor 1', 'Motor', null, null, null, false);
select pg_temp.check((select name = 'Crusher motor 1' from public.assets
  where id = '90000000-0000-0000-0000-0000000000f1'), 'saving again edits the asset');
select pg_temp.as_owner();

select pg_temp.act_as('90000000-0000-0000-0000-000000000003');
select pg_temp.check(not exists (select 1 from public.assets where site_id = '90000000-0000-0000-0000-0000000000a1'),
  'other sites cannot see the register');
select pg_temp.as_owner();

-- Jobs on an asset.
insert into public.assets (id, site_id, tag, name) values
  ('90000000-0000-0000-0000-0000000000f9', '90000000-0000-0000-0000-0000000000a2', 'TX-01', 'Other site transformer');
select pg_temp.act_as('90000000-0000-0000-0000-000000000002');
select public.fn_create_job('90000000-0000-0000-0000-0000000000b1', '90000000-0000-0000-0000-0000000000a1', null,
  'Motor tripping', null, 'normal', null, null, null, '90000000-0000-0000-0000-0000000000f1', 'corrective', true);
select pg_temp.check((select asset_id = '90000000-0000-0000-0000-0000000000f1' and isolation_required
  and maintenance_type = 'corrective' from public.jobs where id = '90000000-0000-0000-0000-0000000000b1'),
  'a job can name an asset and need isolation');
select public.fn_create_job('90000000-0000-0000-0000-0000000000b2', '90000000-0000-0000-0000-0000000000a1', null,
  'Old app job', null, 'normal', null, null, null);
select pg_temp.check((select asset_id is null and not isolation_required and maintenance_type = 'corrective'
  from public.jobs where id = '90000000-0000-0000-0000-0000000000b2'), 'older app calls still work');
select pg_temp.fails($$select public.fn_create_job('90000000-0000-0000-0000-0000000000b3',
  '90000000-0000-0000-0000-0000000000a1', null, 'Wrong site', null, 'normal', null, null, null,
  '90000000-0000-0000-0000-0000000000f9', 'corrective', false)$$, 'INVALID', 'the asset must be at the job''s site');
select public.fn_edit_job('90000000-0000-0000-0000-0000000000b1', 'Motor tripping', null, null, 'normal', null);
select pg_temp.check((select asset_id is not null and isolation_required from public.jobs
  where id = '90000000-0000-0000-0000-0000000000b1'), 'an older app edit keeps the asset and isolation');
select public.fn_edit_job('90000000-0000-0000-0000-0000000000b1', 'Motor tripping', null, null, 'normal', null,
  null, 'corrective', false);
select pg_temp.check((select asset_id is null and not isolation_required from public.jobs
  where id = '90000000-0000-0000-0000-0000000000b1'), 'a new app edit can clear them');
select pg_temp.as_owner();

-- Planned maintenance: a recurrence on an asset makes preventive job cards
-- (0015), registered as the person who set it up.
select pg_temp.act_as('90000000-0000-0000-0000-000000000001');
select public.fn_save_recurrence('90000000-0000-0000-0000-0000000000c1', '90000000-0000-0000-0000-0000000000a1',
  null, 'Grease crusher motor', null, 'normal', 'monthly', current_date, 1, null, false,
  '90000000-0000-0000-0000-0000000000f1', true);
select pg_temp.as_owner();
select public.fn_run_recurrences();
select pg_temp.check((select maintenance_type = 'preventive' and source = 'preventive'
  and isolation_required and asset_id = '90000000-0000-0000-0000-0000000000f1'
  and registered_by = '90000000-0000-0000-0000-000000000001' and priority = 'P3'
  from public.job_cards where site_id = '90000000-0000-0000-0000-0000000000a1'
    and title = 'Grease crusher motor'),
  'recurring jobs on an asset raise preventive job cards');
select pg_temp.check(not exists (select 1 from public.jobs
  where recurrence_id = '90000000-0000-0000-0000-0000000000c1'), 'and no jobs board job');

rollback;
