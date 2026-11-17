-- Behaviour checks for 0054_file_manager. Runs in a transaction and rolls back.
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
  ('fe540000-0000-0000-0000-0000000000a1', 'FMA', 'Files site'),
  ('fe540000-0000-0000-0000-0000000000a2', 'FMB', 'Other site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('fe540000-0000-0000-0000-000000000001', 'fm-sup@test', '{"full_name":"FM Sup"}'),
  ('fe540000-0000-0000-0000-000000000002', 'fm-tech@test', '{"full_name":"FM Tech"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'fe540000-0000-0000-0000-000000000001'::uuid, id, 'fe540000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Supervisor';
insert into public.user_roles (user_id, role_id, site_id)
select 'fe540000-0000-0000-0000-000000000002'::uuid, id, 'fe540000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Technician';
insert into public.documents (id, site_id, code, title, category) values
  ('fe540000-0000-0000-0000-0000000000d1', 'fe540000-0000-0000-0000-0000000000a1', 'S-9101', 'MCC-3 single line', 'drawing'),
  ('fe540000-0000-0000-0000-0000000000d2', 'fe540000-0000-0000-0000-0000000000a1', 'S-9102', 'Pump manual', 'manual');

create temp table f (k text primary key, v uuid);
grant all on f to authenticated;
select pg_temp.act_as('fe540000-0000-0000-0000-000000000001');
insert into f values ('drawings', (public.fn_save_folder(gen_random_uuid(), 'fe540000-0000-0000-0000-0000000000a1', 'Drawings', false)).id);
insert into f values ('mcc', (public.fn_save_folder(gen_random_uuid(), 'fe540000-0000-0000-0000-0000000000a1', 'MCC-3', false,
  (select v from f where k = 'drawings'))).id);
select pg_temp.check((select parent_id = (select v from f where k = 'drawings') from public.document_folders
  where id = (select v from f where k = 'mcc')), 'a folder can be made inside another');
insert into f values ('mcc-top', (public.fn_save_folder(gen_random_uuid(), 'fe540000-0000-0000-0000-0000000000a1', 'MCC-3', false)).id);
select pg_temp.check(true, 'the same name is fine in a different folder');
select pg_temp.fails($$select public.fn_save_folder(gen_random_uuid(), 'fe540000-0000-0000-0000-0000000000a1', 'mcc-3', false,
  (select v from f where k = 'drawings'))$$, 'CONFLICT', 'but not twice in one folder');
select public.fn_save_folder((select v from f where k = 'mcc'), 'fe540000-0000-0000-0000-0000000000a1', 'MCC 3 drawings', false, null);
select pg_temp.check((select name = 'MCC 3 drawings' and parent_id = (select v from f where k = 'drawings')
  from public.document_folders where id = (select v from f where k = 'mcc')), 'renaming keeps a folder where it is');

-- Moving folders.
select pg_temp.fails($$select public.fn_move_folder((select v from f where k = 'drawings'), (select v from f where k = 'mcc'))$$,
  'INVALID', 'a folder cannot go inside its own subfolder');
select pg_temp.fails($$select public.fn_move_folder((select v from f where k = 'drawings'), (select v from f where k = 'drawings'))$$,
  'INVALID', 'or inside itself');
select public.fn_move_folder((select v from f where k = 'mcc'), null);
select pg_temp.check((select parent_id is null from public.document_folders where id = (select v from f where k = 'mcc')),
  'a folder moves to the top');
select public.fn_move_folder((select v from f where k = 'mcc'), (select v from f where k = 'drawings'));
select pg_temp.as_owner();
insert into public.document_folders (id, site_id, name) values ('fe540000-0000-0000-0000-0000000000f9', 'fe540000-0000-0000-0000-0000000000a2', 'Elsewhere');
select pg_temp.act_as('fe540000-0000-0000-0000-000000000001');
select pg_temp.fails($$select public.fn_move_folder((select v from f where k = 'mcc'), 'fe540000-0000-0000-0000-0000000000f9')$$,
  'INVALID', 'not into another site');

-- Depth limit: 8 levels.
do $$
declare p uuid := null; i int;
begin
  for i in 1..8 loop
    p := (public.fn_save_folder(gen_random_uuid(), 'fe540000-0000-0000-0000-0000000000a1', 'Level ' || i, false, p)).id;
  end loop;
  insert into f values ('deep', p);
end $$;
select pg_temp.fails($$select public.fn_save_folder(gen_random_uuid(), 'fe540000-0000-0000-0000-0000000000a1', 'Level 9', false,
  (select v from f where k = 'deep'))$$, 'INVALID', 'folders go 8 levels deep');

-- Archiving a folder archives its subfolders; documents move up a level.
select public.fn_move_documents(array['fe540000-0000-0000-0000-0000000000d1'::uuid], (select v from f where k = 'mcc'));
select public.fn_save_folder((select v from f where k = 'drawings'), 'fe540000-0000-0000-0000-0000000000a1', 'Drawings', true);
select pg_temp.check((select bool_and(is_archived) from public.document_folders
  where id in ((select v from f where k = 'drawings'), (select v from f where k = 'mcc'))), 'archiving takes the subfolders too');
select pg_temp.check((select folder_id is null from public.documents where id = 'fe540000-0000-0000-0000-0000000000d1'),
  'and its documents move up, nothing is lost');

-- Technicians can look but not change.
select pg_temp.act_as('fe540000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_save_folder(gen_random_uuid(), 'fe540000-0000-0000-0000-0000000000a1', 'Mine', false)$$,
  'NOT_ALLOWED', 'a technician cannot make folders');
select pg_temp.fails($$select public.fn_move_folder((select v from f where k = 'mcc-top'), null)$$,
  'NOT_ALLOWED', 'or move them');

-- Stars are personal.
select public.fn_star_document('fe540000-0000-0000-0000-0000000000d2', true);
select public.fn_star_document('fe540000-0000-0000-0000-0000000000d2', true);
select pg_temp.check((select count(*) = 1 from public.document_stars), 'a technician stars a document (once)');
select pg_temp.act_as('fe540000-0000-0000-0000-000000000001');
select pg_temp.check((select count(*) = 0 from public.document_stars), 'others do not see it');
select pg_temp.act_as('fe540000-0000-0000-0000-000000000002');
select public.fn_star_document('fe540000-0000-0000-0000-0000000000d2', false);
select pg_temp.check((select count(*) = 0 from public.document_stars), 'and it can be taken off');
select pg_temp.fails($$insert into public.document_stars (document_id) values ('fe540000-0000-0000-0000-0000000000d2')$$,
  '', 'stars are only set through the function');
select pg_temp.as_owner();
insert into auth.users (id, email) values ('fe540000-0000-0000-0000-000000000009', 'fm-out@test');
select pg_temp.act_as('fe540000-0000-0000-0000-000000000009');
select pg_temp.fails($$select public.fn_star_document('fe540000-0000-0000-0000-0000000000d2', true)$$,
  'NOT_FOUND', 'someone without document access cannot star it');
select pg_temp.as_owner();

rollback;
