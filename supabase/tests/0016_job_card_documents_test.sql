-- Behaviour checks for 0016_job_card_documents. Runs in a transaction and rolls back.
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
  ('f2000000-0000-0000-0000-0000000000a1', 'JCD', 'Job card docs site'),
  ('f2000000-0000-0000-0000-0000000000a2', 'JCX', 'Other docs site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('f2000000-0000-0000-0000-000000000001', 'jcd-sup@test', '{"full_name":"Jcd Sup"}'),
  ('f2000000-0000-0000-0000-000000000002', 'jcd-store@test', '{"full_name":"Jcd Store"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'f2000000-0000-0000-0000-000000000001'::uuid, id, 'f2000000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Supervisor'
union all
select 'f2000000-0000-0000-0000-000000000002'::uuid, id, 'f2000000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Storekeeper';
insert into public.documents (id, site_id, code, title)
select 'f2000000-0000-0000-0000-0000000000d1'::uuid, 'f2000000-0000-0000-0000-0000000000a1'::uuid, 'S-9001', 'LOTO procedure'
union all
select 'f2000000-0000-0000-0000-0000000000d2'::uuid, 'f2000000-0000-0000-0000-0000000000a2'::uuid, 'S-9002', 'Elsewhere document';

select pg_temp.act_as('f2000000-0000-0000-0000-000000000001');
select public.fn_register_job_card('f2000000-0000-0000-0000-0000000000e1', null,
  'f2000000-0000-0000-0000-0000000000a1', null, 'Substation', now(), 'Jcd Sup', null, null, null, null, null, null,
  'Isolate feeder 3', 'Feeder 3 needs isolating for a cable repair', 'minor', 'P3', null);
select public.fn_link_job_card_document('f2000000-0000-0000-0000-0000000000e1',
  'f2000000-0000-0000-0000-0000000000d1', true);
select public.fn_link_job_card_document('f2000000-0000-0000-0000-0000000000e1',
  'f2000000-0000-0000-0000-0000000000d1', true);
select pg_temp.check((select count(*) = 1 from public.job_card_documents
  where job_card_id = 'f2000000-0000-0000-0000-0000000000e1'), 'a supervisor attaches an SOP, once');
select pg_temp.fails($$select public.fn_link_job_card_document('f2000000-0000-0000-0000-0000000000e1',
  'f2000000-0000-0000-0000-0000000000d2', true)$$, 'INVALID', 'documents must be at the job card''s site');
select pg_temp.as_owner();

select pg_temp.act_as('f2000000-0000-0000-0000-000000000002');
select pg_temp.check(exists (select 1 from public.job_card_documents
  where job_card_id = 'f2000000-0000-0000-0000-0000000000e1'), 'people who see the job card see its documents');
select pg_temp.fails($$select public.fn_link_job_card_document('f2000000-0000-0000-0000-0000000000e1',
  'f2000000-0000-0000-0000-0000000000d1', false)$$, 'NOT_ALLOWED', 'people off the job cannot detach');
select pg_temp.as_owner();

select pg_temp.act_as('f2000000-0000-0000-0000-000000000001');
select public.fn_link_job_card_document('f2000000-0000-0000-0000-0000000000e1',
  'f2000000-0000-0000-0000-0000000000d1', false);
select pg_temp.check(not exists (select 1 from public.job_card_documents
  where job_card_id = 'f2000000-0000-0000-0000-0000000000e1'), 'and the supervisor detaches it');
select pg_temp.as_owner();

rollback;
