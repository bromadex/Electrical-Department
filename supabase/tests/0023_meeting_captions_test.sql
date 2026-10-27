-- Behaviour checks for 0023_meeting_captions. Runs in a transaction and rolls back.
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

insert into public.sites (id, code, name) values ('f9000000-0000-0000-0000-0000000000a1', 'CAP', 'Caption site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('f9000000-0000-0000-0000-000000000001', 'cap-sup@test', '{"full_name":"Cap Sup"}'),
  ('f9000000-0000-0000-0000-000000000002', 'cap-tech@test', '{"full_name":"Cap Tech"}'),
  ('f9000000-0000-0000-0000-000000000003', 'cap-out@test', '{"full_name":"Cap Out"}');
insert into public.user_roles (user_id, role_id, site_id)
select 'f9000000-0000-0000-0000-000000000001'::uuid, id, 'f9000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Supervisor'
union all
select 'f9000000-0000-0000-0000-000000000002'::uuid, id, 'f9000000-0000-0000-0000-0000000000a1'::uuid from public.roles where name = 'Technician';

create temp table cchat as
  select id from public.conversations where is_default and site_id = 'f9000000-0000-0000-0000-0000000000a1';
grant select on cchat to authenticated;
create temp table cm (id uuid, later uuid);
grant select, insert on cm to authenticated;

select pg_temp.act_as('f9000000-0000-0000-0000-000000000001');
insert into cm select
  (public.fn_create_meeting(gen_random_uuid(), (select id from cchat), null, 'Now', null, now() - interval '5 minutes', 60)).id,
  (public.fn_create_meeting(gen_random_uuid(), (select id from cchat), null, 'Tomorrow', null, now() + interval '1 day', 60)).id;
select public.fn_add_caption((select id from cm), now() - interval '10 seconds', 'Let us start with the outages.');

select pg_temp.act_as('f9000000-0000-0000-0000-000000000002');
select public.fn_add_caption((select id from cm), now(), '  DB-3 tripped twice.  ');
select pg_temp.check((select count(*) = 2 from public.meeting_captions where meeting_id = (select id from cm)),
  'people in the chat add captions while the meeting is on');
select pg_temp.check((select public.fn_meeting_transcript((select id from cm)) like '%Cap Sup: Let us start with the outages.%Cap Tech: DB-3 tripped twice.'),
  'the transcript is in order, with names');
select pg_temp.fails($$select public.fn_add_caption((select later from cm), now(), 'Too early')$$,
  'INVALID', 'not before the meeting');
select pg_temp.fails($$select public.fn_add_caption((select id from cm), now(), '   ')$$, 'INVALID', 'not empty');

select pg_temp.act_as('f9000000-0000-0000-0000-000000000003');
select pg_temp.fails($$select public.fn_add_caption((select id from cm), now(), 'Hello')$$,
  'NOT_FOUND', 'outsiders cannot add captions');
select pg_temp.check(not exists (select 1 from public.meeting_captions), 'or read them');
select pg_temp.check(public.fn_meeting_transcript((select id from cm)) is null, 'or the transcript');
select pg_temp.as_owner();

rollback;
