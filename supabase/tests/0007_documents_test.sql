-- Behaviour checks for 0007_documents. Runs in a transaction and rolls back.
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
  ('b0000000-0000-0000-0000-0000000000a1', 'DOC', 'Docs test site'),
  ('b0000000-0000-0000-0000-0000000000a2', 'DOD', 'Other docs site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('b0000000-0000-0000-0000-000000000001', 'dc-sup@test', '{"full_name":"Dc Sup"}'),
  ('b0000000-0000-0000-0000-000000000002', 'dc-tech@test', '{"full_name":"Dc Tech"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'b0000000-0000-0000-0000-000000000001'::uuid, id, 'b0000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Supervisor'
union all
select 'b0000000-0000-0000-0000-000000000002'::uuid, id, 'b0000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Technician';

select pg_temp.act_as('b0000000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_save_document('b0000000-0000-0000-0000-0000000000d1',
  'b0000000-0000-0000-0000-0000000000a1', 'LOTO procedure', 'sop', true, false)$$,
  'NOT_ALLOWED', 'technicians cannot add documents');
select pg_temp.as_owner();

select pg_temp.act_as('b0000000-0000-0000-0000-000000000001');
select pg_temp.check((select code = 'S-0001' and current_version = 0 from public.fn_save_document(
  'b0000000-0000-0000-0000-0000000000d1', 'b0000000-0000-0000-0000-0000000000a1',
  'Isolation and LOTO procedure', 'sop', true, false)), 'supervisors add a document with an S- code');
select pg_temp.fails($$select public.fn_add_document_version('b0000000-0000-0000-0000-0000000000e1',
  'b0000000-0000-0000-0000-0000000000d1', 'b0000000-0000-0000-0000-0000000000a2/doc/x/loto.pdf',
  'loto.pdf', 'application/pdf', 1000, null)$$, 'INVALID', 'files must be in the site''s folder');
select pg_temp.check((select current_version = 1 from public.fn_add_document_version(
  'b0000000-0000-0000-0000-0000000000e1', 'b0000000-0000-0000-0000-0000000000d1',
  'b0000000-0000-0000-0000-0000000000a1/doc/d1/loto-v1.pdf', 'loto.pdf', 'application/pdf', 1000, null)),
  'the first upload is version 1');
select public.fn_add_document_version('b0000000-0000-0000-0000-0000000000e1', 'b0000000-0000-0000-0000-0000000000d1',
  'b0000000-0000-0000-0000-0000000000a1/doc/d1/loto-v1.pdf', 'loto.pdf', 'application/pdf', 1000, null);
select pg_temp.check((select current_version = 1 from public.documents
  where id = 'b0000000-0000-0000-0000-0000000000d1'), 'sending the same upload twice adds one version');
select pg_temp.as_owner();
select pg_temp.check(exists (select 1 from public.notifications
  where user_id = 'b0000000-0000-0000-0000-000000000002' and title = 'New SOP to read: S-0001'),
  'people at the site are asked to read it');

-- Acknowledgement.
select pg_temp.act_as('b0000000-0000-0000-0000-000000000002');
select public.fn_acknowledge_document('b0000000-0000-0000-0000-0000000000d1', 1);
select public.fn_acknowledge_document('b0000000-0000-0000-0000-0000000000d1', 1);
select pg_temp.check((select count(*) = 1 from public.document_acks), 'acknowledging twice is one record');
select pg_temp.as_owner();
select pg_temp.act_as('b0000000-0000-0000-0000-000000000001');
select public.fn_add_document_version('b0000000-0000-0000-0000-0000000000e2', 'b0000000-0000-0000-0000-0000000000d1',
  'b0000000-0000-0000-0000-0000000000a1/doc/d1/loto-v2.pdf', 'loto.pdf', 'application/pdf', 1200, 'Step 4 changed');
select pg_temp.check((select acked_at is null from public.fn_document_acks('b0000000-0000-0000-0000-0000000000d1')
  where full_name = 'Dc Tech'), 'a new version asks again');
select pg_temp.as_owner();
select pg_temp.act_as('b0000000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_acknowledge_document('b0000000-0000-0000-0000-0000000000d1', 1)$$,
  'CONFLICT', 'an old version cannot be acknowledged');
select pg_temp.fails($$select * from public.fn_document_acks('b0000000-0000-0000-0000-0000000000d1')$$,
  'NOT_ALLOWED', 'only supervisors see who has signed');
select pg_temp.as_owner();

-- Linking to a job.
select pg_temp.act_as('b0000000-0000-0000-0000-000000000002');
select public.fn_create_job('b0000000-0000-0000-0000-0000000000f1', 'b0000000-0000-0000-0000-0000000000a1', null,
  'Switch out feeder 3', null, 'normal', null, null, null);
select public.fn_link_document('b0000000-0000-0000-0000-0000000000f1', 'b0000000-0000-0000-0000-0000000000d1', true);
select pg_temp.check((select count(*) = 1 from public.job_documents), 'the poster can attach the SOP');
select public.fn_link_document('b0000000-0000-0000-0000-0000000000f1', 'b0000000-0000-0000-0000-0000000000d1', false);
select pg_temp.check((select count(*) = 0 from public.job_documents), 'and detach it');
select pg_temp.as_owner();

rollback;
