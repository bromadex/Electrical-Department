-- Behaviour checks for 0030_view_every_site. Runs in a transaction and rolls back.
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
  ('fa000000-0000-0000-0000-0000000000a1', 'VEA', 'Home site'),
  ('fa000000-0000-0000-0000-0000000000a2', 'VEB', 'Other site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('fa000000-0000-0000-0000-000000000001', 've-tech@test', '{"full_name":"Ve Tech"}'),
  ('fa000000-0000-0000-0000-000000000002', 've-sup@test', '{"full_name":"Ve Sup"}'),
  ('fa000000-0000-0000-0000-000000000003', 've-none@test', '{"full_name":"Ve None"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'fa000000-0000-0000-0000-000000000001'::uuid, id, 'fa000000-0000-0000-0000-0000000000a1'::uuid
from public.roles where name = 'Technician'
union all
select 'fa000000-0000-0000-0000-000000000002'::uuid, id, 'fa000000-0000-0000-0000-0000000000a2'::uuid
from public.roles where name = 'Supervisor';
insert into public.documents (id, site_id, code, title, needs_ack, current_version)
values ('fa000000-0000-0000-0000-0000000000d1', 'fa000000-0000-0000-0000-0000000000a2', 'S-9301',
  'Other site SOP', true, 1);
insert into public.document_folders (id, site_id, name)
values ('fa000000-0000-0000-0000-0000000000f1', 'fa000000-0000-0000-0000-0000000000a2', 'Other drawings');
insert into public.job_cards (id, number, source, site_id, location, received_at, reporter_name, title, description, priority)
values ('fa000000-0000-0000-0000-0000000000c1', 'VEB-JC-0001', 'direct', 'fa000000-0000-0000-0000-0000000000a2', 'Plant',
  now(), 'Plant foreman', 'Conveyor motor trips', 'The conveyor motor trips after ten minutes',
  (select code from public.priority_levels order by 1 limit 1));

select pg_temp.act_as('fa000000-0000-0000-0000-000000000001');
select pg_temp.check((select count(*) = 1 from public.documents where site_id = 'fa000000-0000-0000-0000-0000000000a2'),
  'a technician at one site reads documents at another');
select pg_temp.check((select count(*) = 1 from public.document_folders where site_id = 'fa000000-0000-0000-0000-0000000000a2'),
  'and its folders');
select pg_temp.check((select count(*) = 1 from public.job_cards where site_id = 'fa000000-0000-0000-0000-0000000000a2'),
  'and its job cards');
select pg_temp.check(public._can('tools.view', 'fa000000-0000-0000-0000-0000000000a2')
  and public._can('store.view', 'fa000000-0000-0000-0000-0000000000a2'),
  'and its tools and store');
select pg_temp.check(not public._can('jc.execute', 'fa000000-0000-0000-0000-0000000000a2'),
  'working permissions stay at their own site');
select pg_temp.check(exists (select 1 from public.my_permissions() where code = 'docs.view' and site_id is null)
  and exists (select 1 from public.my_permissions() where code = 'site.member'
    and site_id = 'fa000000-0000-0000-0000-0000000000a1')
  and not exists (select 1 from public.my_permissions() where code = 'site.member'
    and site_id = 'fa000000-0000-0000-0000-0000000000a2'),
  'my_permissions gives views at all sites and the sites I work at');
select pg_temp.fails($$select public.fn_comment_job_card(gen_random_uuid(), 'fa000000-0000-0000-0000-0000000000c1',
  'I can help', 'comment', 'internal', null)$$, 'NOT_ALLOWED', 'no comments on another site''s job cards');
select pg_temp.fails($$select public.fn_acknowledge_document('fa000000-0000-0000-0000-0000000000d1', 1)$$,
  'NOT_ALLOWED', 'no signing another site''s SOPs');
select pg_temp.fails($$select public.fn_add_report_update(gen_random_uuid(), 'fa000000-0000-0000-0000-0000000000a2',
  current_date, 'Helped at the other site', null)$$, 'NOT_ALLOWED', 'no updates to another site''s daily report');
select pg_temp.fails($$select public.fn_save_folder(gen_random_uuid(), 'fa000000-0000-0000-0000-0000000000a2',
  'Mine', false)$$, 'NOT_ALLOWED', 'no managing another site''s documents');
select pg_temp.as_owner();

select pg_temp.act_as('fa000000-0000-0000-0000-000000000002');
select public.fn_comment_job_card(gen_random_uuid(), 'fa000000-0000-0000-0000-0000000000c1',
  'Checking the overload setting', 'comment', 'internal', null);
select pg_temp.check(true, 'people at the site still work on its job cards');
select pg_temp.as_owner();

select pg_temp.act_as('fa000000-0000-0000-0000-000000000003');
select pg_temp.check((select count(*) = 0 from public.documents), 'someone with no role sees nothing');
select pg_temp.as_owner();

select pg_temp.check(public.fn_notify_permission('fa000000-0000-0000-0000-0000000000a2', 'docs.view', 'reminder',
  'New SOP', 'Read it', 'doc:x') >= 1, 'site notifications still go out');
select pg_temp.check(not exists (select 1 from public.notifications
  where user_id = 'fa000000-0000-0000-0000-000000000001' and link = 'doc:x'),
  'but not to people at other sites');

rollback;
