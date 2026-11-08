-- Behaviour checks for 0038_hardening. Runs in a transaction and rolls back.
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

select pg_temp.check(not exists (
  select 1
  from pg_constraint c
  join pg_class t on t.oid = c.conrelid
  join pg_namespace n on n.oid = t.relnamespace
  where c.contype = 'f' and n.nspname = 'public' and array_length(c.conkey, 1) = 1
    and not exists (select 1 from pg_index i where i.indrelid = c.conrelid and i.indkey[0] = c.conkey[1])
), 'every foreign key in public has an index (add one with any new foreign key)');

insert into auth.users (id, email, raw_user_meta_data) values
  ('f3000000-0000-0000-0000-000000000001', 'er-tech@test', '{"full_name":"Er Tech"}'),
  ('f3000000-0000-0000-0000-000000000002', 'er-admin@test', '{"full_name":"Er Admin"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'f3000000-0000-0000-0000-000000000001'::uuid, id, null::uuid from public.roles where name = 'Technician'
union all
select 'f3000000-0000-0000-0000-000000000002'::uuid, id, null::uuid from public.roles where name = 'Admin';

select pg_temp.act_as('f3000000-0000-0000-0000-000000000001');
select public.fn_report_error('abc123', 'Null check operator used on a null value', 'at Foo.bar', '/inventory',
  'android', '0.1.3');
select public.fn_report_error('abc123', 'Null check operator used on a null value', 'at Foo.bar', '/inventory/count',
  'android', '0.1.3');
select pg_temp.fails($$select public.fn_report_error('', 'x', null, null, null, null)$$, 'INVALID',
  'an error needs a fingerprint');
select pg_temp.check((select count(*) = 0 from public.client_errors), 'people cannot read error reports');
select pg_temp.fails($$insert into public.client_errors (fingerprint, message) values ('x', 'y')$$, '',
  'or write them directly');
select pg_temp.as_owner();

select pg_temp.check((select count = 2 and route = '/inventory/count' and user_id = 'f3000000-0000-0000-0000-000000000001'
  from public.client_errors where fingerprint = 'abc123'), 'the same error is counted, not repeated');

select pg_temp.act_as('f3000000-0000-0000-0000-000000000002');
select pg_temp.check((select count(*) = 1 from public.client_errors where fingerprint = 'abc123'),
  'admins read error reports');
update public.client_errors set is_archived = true where fingerprint = 'abc123';
select pg_temp.as_owner();

select pg_temp.act_as('f3000000-0000-0000-0000-000000000001');
select public.fn_report_error('abc123', 'Null check operator used on a null value', null, '/inventory', 'android', '0.1.4');
select pg_temp.as_owner();
select pg_temp.check((select count(*) = 2 from public.client_errors where fingerprint = 'abc123')
  and (select count = 1 from public.client_errors where fingerprint = 'abc123' and not is_archived),
  'after an admin marks it fixed, the error coming back starts a new report');

rollback;
