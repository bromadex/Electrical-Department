-- Behaviour checks for 0029_document_folders. Runs in a transaction and rolls back.
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
  ('f9000000-0000-0000-0000-0000000000a1', 'DFA', 'Folder site'),
  ('f9000000-0000-0000-0000-0000000000a2', 'DFB', 'Other folder site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('f9000000-0000-0000-0000-000000000001', 'df-sup@test', '{"full_name":"Df Sup"}'),
  ('f9000000-0000-0000-0000-000000000002', 'df-tech@test', '{"full_name":"Df Tech"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'f9000000-0000-0000-0000-000000000001'::uuid, id, 'f9000000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Supervisor'
union all
select 'f9000000-0000-0000-0000-000000000001'::uuid, id, 'f9000000-0000-0000-0000-0000000000a2'::uuid
from public.roles where name = 'Supervisor'
union all
select 'f9000000-0000-0000-0000-000000000002'::uuid, id, 'f9000000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Technician';
insert into public.documents (id, site_id, code, title)
select 'f9000000-0000-0000-0000-0000000000d1'::uuid, 'f9000000-0000-0000-0000-0000000000a1'::uuid, 'S-9101', 'Feeder 3 single line'
union all
select 'f9000000-0000-0000-0000-0000000000d2'::uuid, 'f9000000-0000-0000-0000-0000000000a1'::uuid, 'S-9102', 'LOTO procedure';

select pg_temp.act_as('f9000000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_save_folder('f9000000-0000-0000-0000-0000000000f1',
  'f9000000-0000-0000-0000-0000000000a1', 'Drawings', false)$$, 'NOT_ALLOWED', 'technicians cannot make folders');
select pg_temp.as_owner();

select pg_temp.act_as('f9000000-0000-0000-0000-000000000001');
select public.fn_save_folder('f9000000-0000-0000-0000-0000000000f1', 'f9000000-0000-0000-0000-0000000000a1',
  'Substation drawings', false);
select pg_temp.fails($$select public.fn_save_folder('f9000000-0000-0000-0000-0000000000f2',
  'f9000000-0000-0000-0000-0000000000a1', 'substation DRAWINGS', false)$$, 'CONFLICT', 'folder names are unique per site');
select pg_temp.fails($$select public.fn_save_folder('f9000000-0000-0000-0000-0000000000f2',
  'f9000000-0000-0000-0000-0000000000a1', 'x', false)$$, 'INVALID', 'a folder needs a name');
select public.fn_save_folder('f9000000-0000-0000-0000-0000000000f3', 'f9000000-0000-0000-0000-0000000000a2',
  'Elsewhere', false);
select pg_temp.check((select name = 'Single lines' from public.fn_save_folder('f9000000-0000-0000-0000-0000000000f1',
  'f9000000-0000-0000-0000-0000000000a1', 'Single lines', false)), 'a supervisor renames a folder');

select pg_temp.check(public.fn_move_documents(array['f9000000-0000-0000-0000-0000000000d1',
  'f9000000-0000-0000-0000-0000000000d2']::uuid[], 'f9000000-0000-0000-0000-0000000000f1') = 2,
  'documents move into a folder');
select pg_temp.fails($$select public.fn_move_documents(array['f9000000-0000-0000-0000-0000000000d1']::uuid[],
  'f9000000-0000-0000-0000-0000000000f3')$$, 'INVALID', 'only into a folder at the same site');
select public.fn_move_documents(array['f9000000-0000-0000-0000-0000000000d2']::uuid[], null);
select pg_temp.check((select folder_id is null from public.documents where id = 'f9000000-0000-0000-0000-0000000000d2'),
  'and out of folders');
select pg_temp.as_owner();

select pg_temp.act_as('f9000000-0000-0000-0000-000000000002');
select pg_temp.check((select count(*) = 1 from public.document_folders
  where site_id = 'f9000000-0000-0000-0000-0000000000a1'), 'people at the site see its folders');
select pg_temp.fails($$select public.fn_move_documents(array['f9000000-0000-0000-0000-0000000000d2']::uuid[],
  'f9000000-0000-0000-0000-0000000000f1')$$, 'NOT_ALLOWED', 'technicians cannot move documents');
select pg_temp.as_owner();

select pg_temp.act_as('f9000000-0000-0000-0000-000000000001');
select public.fn_save_folder('f9000000-0000-0000-0000-0000000000f1', 'f9000000-0000-0000-0000-0000000000a1',
  'Single lines', true);
select pg_temp.check((select folder_id is null and not is_archived from public.documents
  where id = 'f9000000-0000-0000-0000-0000000000d1'), 'archiving a folder moves its documents out, it keeps them');
select public.fn_save_folder('f9000000-0000-0000-0000-0000000000f4', 'f9000000-0000-0000-0000-0000000000a1',
  'Single lines', false);
select pg_temp.check(true, 'the name of an archived folder can be used again');
select pg_temp.as_owner();

rollback;
