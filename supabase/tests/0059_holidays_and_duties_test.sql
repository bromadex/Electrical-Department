-- Behaviour checks for 0059_holidays_and_duties. Runs in a transaction and rolls back.
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

-- The holidays, before anything is set aside.
select pg_temp.check((select count(*) = 9 from public.work_closures
  where kind = 'holiday' and site_id is null and starts_on between date '2027-01-01' and date '2027-12-31'),
  'the nine 2027 public holidays are in, for every site');
select pg_temp.check((select bool_and(message is not null) from public.work_closures
  where site_id is null and (kind = 'holiday' or starts_on = date '2026-12-19')),
  'each holiday and the Christmas shutdown has a message for the team');
select pg_temp.check((select starts_on = date '2027-04-19' from public.work_closures where reason like 'Independence Day%')
  and (select starts_on = date '2027-08-09' and ends_on = date '2027-08-10' from public.work_closures where reason like 'Heroes%')
  and (select starts_on = date '2027-03-26' and ends_on = date '2027-03-29' from public.work_closures where reason like 'Easter%'),
  'Sunday holidays move to Monday; Heroes'' Day is the second Monday of August; Easter 2027 is 26 to 29 March');

create temp table t (today date);
insert into t values ((now() at time zone 'Africa/Harare')::date);
grant select on t to authenticated;
update public.work_closures set is_archived = true;

insert into public.sites (id, code, name) values ('f5900000-0000-0000-0000-0000000000a1', 'DUT', 'Duty site');
insert into auth.users (id, email, raw_user_meta_data) values
  ('f5900000-0000-0000-0000-000000000001', 'du-sup@test', '{"full_name":"Du Supervisor"}'),
  ('f5900000-0000-0000-0000-000000000002', 'du-geri@test', '{"full_name":"Geri"}'),
  ('f5900000-0000-0000-0000-000000000003', 'du-nyasha@test', '{"full_name":"Nyasha"}'),
  ('f5900000-0000-0000-0000-000000000004', 'du-out@test', '{"full_name":"Elsewhere"}');
insert into public.sites (id, code, name) values ('f5900000-0000-0000-0000-0000000000a2', 'DUO', 'Other site');
insert into public.user_roles (user_id, role_id, site_id)
select u.id, r.id, u.site
from (values
  ('f5900000-0000-0000-0000-000000000001'::uuid, 'Supervisor', 'f5900000-0000-0000-0000-0000000000a1'::uuid),
  ('f5900000-0000-0000-0000-000000000002'::uuid, 'Technician', 'f5900000-0000-0000-0000-0000000000a1'::uuid),
  ('f5900000-0000-0000-0000-000000000003'::uuid, 'Technician', 'f5900000-0000-0000-0000-0000000000a1'::uuid),
  ('f5900000-0000-0000-0000-000000000004'::uuid, 'Technician', 'f5900000-0000-0000-0000-0000000000a2'::uuid)
) as u (id, role, site)
join public.roles r on r.name = u.role;

-- Messages on closures --------------------------------------------------------------
select pg_temp.act_as('f5900000-0000-0000-0000-000000000001');
select public.fn_save_closure('f5900000-0000-0000-0000-0000000000e1', 'f5900000-0000-0000-0000-0000000000a1',
  date '2030-01-01', date '2030-01-01', 'Site open day', false, 'holiday', 'Enjoy the day!');
select public.fn_save_closure('f5900000-0000-0000-0000-0000000000e1', 'f5900000-0000-0000-0000-0000000000a1',
  date '2030-01-01', date '2030-01-02', 'Site open day');
select pg_temp.check((select message = 'Enjoy the day!' and kind = 'holiday' and ends_on = date '2030-01-02'
  from public.work_closures where id = 'f5900000-0000-0000-0000-0000000000e1'),
  'saving the dates without a message keeps the message and kind');

-- A rota ------------------------------------------------------------------------------
select public.fn_save_duty_rota('f5900000-0000-0000-0000-0000000000d1', 'f5900000-0000-0000-0000-0000000000a1',
  'Morning duties', 'daily',
  array['f5900000-0000-0000-0000-000000000002', 'f5900000-0000-0000-0000-000000000003']::uuid[],
  array['Read the meters', 'Generator check', 'Sweep the substation'],
  array[null, null, 'f5900000-0000-0000-0000-000000000003']::uuid[]);
select pg_temp.fails($$select public.fn_save_duty_rota(null, 'f5900000-0000-0000-0000-0000000000a1', 'Bad', 'daily',
  array['f5900000-0000-0000-0000-000000000004']::uuid[], array['Something'])$$,
  'INVALID', 'someone from another site cannot be on the duties');
select pg_temp.act_as('f5900000-0000-0000-0000-000000000002');
select pg_temp.fails($$select public.fn_save_duty_rota(null, 'f5900000-0000-0000-0000-0000000000a1', 'Mine', 'daily',
  '{}'::uuid[], array['Something'])$$, 'NOT_ALLOWED', 'a technician cannot set up duties');

-- Today: Geri reads the meters, Nyasha checks the generator and sweeps (her own).
select pg_temp.check((select string_agg(title || '=' || person_id, ',' order by position)
  = 'Read the meters=f5900000-0000-0000-0000-000000000002,Generator check=f5900000-0000-0000-0000-000000000003,'
    'Sweep the substation=f5900000-0000-0000-0000-000000000003'
  from public.fn_duties('f5900000-0000-0000-0000-0000000000a1', (select today from t))),
  'on the first day the team takes the duties in order, and a fixed duty goes to its person');

-- Tomorrow they swap.
select pg_temp.as_owner();
update public.duty_rotas set starts_on = (select today from t) - 1 where id = 'f5900000-0000-0000-0000-0000000000d1';
select pg_temp.act_as('f5900000-0000-0000-0000-000000000002');
select pg_temp.check((select string_agg(title || '=' || person_id, ',' order by position)
  = 'Read the meters=f5900000-0000-0000-0000-000000000003,Generator check=f5900000-0000-0000-0000-000000000002,'
    'Sweep the substation=f5900000-0000-0000-0000-000000000003'
  from public.fn_duties('f5900000-0000-0000-0000-0000000000a1', (select today from t))),
  'the next day Geri and Nyasha swap; the fixed duty stays');

-- Nyasha on leave: Geri covers everything.
select pg_temp.as_owner();
insert into public.roster_entries (site_id, user_id, day, shift)
values ('f5900000-0000-0000-0000-0000000000a1', 'f5900000-0000-0000-0000-000000000003', (select today from t), 'leave');
select pg_temp.act_as('f5900000-0000-0000-0000-000000000002');
select pg_temp.check((select bool_and(person_id = 'f5900000-0000-0000-0000-000000000002') and count(*) = 3
  from public.fn_duties('f5900000-0000-0000-0000-0000000000a1', (select today from t))),
  'someone on leave is left out, their own duty too');

-- Ticking.
select public.fn_mark_duty((select task_id from public.fn_duties('f5900000-0000-0000-0000-0000000000a1', (select today from t))
  where title = 'Read the meters'), (select today from t), true, 'All normal');
select pg_temp.check((select done_by = 'f5900000-0000-0000-0000-000000000002' and note = 'All normal'
  from public.fn_duties('f5900000-0000-0000-0000-0000000000a1', (select today from t)) where title = 'Read the meters'),
  'a duty ticked done shows who and the note');
select public.fn_mark_duty((select task_id from public.fn_duties('f5900000-0000-0000-0000-0000000000a1', (select today from t))
  where title = 'Read the meters'), (select today from t), false);
select pg_temp.check((select done_by is null
  from public.fn_duties('f5900000-0000-0000-0000-0000000000a1', (select today from t)) where title = 'Read the meters'),
  'and the tick can be taken back');
select pg_temp.fails($$select public.fn_mark_duty((select id from public.duty_tasks where title = 'Generator check'),
  current_date + 1, true)$$, 'INVALID', 'tomorrow''s duties cannot be ticked yet');
select pg_temp.act_as('f5900000-0000-0000-0000-000000000004');
select pg_temp.fails($$select public.fn_mark_duty((select id from public.duty_tasks where title = 'Generator check'),
  current_date, true)$$, 'NOT_ALLOWED', 'someone from another site cannot tick them');

-- Editing keeps ticked tasks, removes dropped ones.
select pg_temp.act_as('f5900000-0000-0000-0000-000000000002');
select public.fn_mark_duty((select id from public.duty_tasks where title = 'Generator check'), (select today from t), true);
select pg_temp.act_as('f5900000-0000-0000-0000-000000000001');
select public.fn_save_duty_rota('f5900000-0000-0000-0000-0000000000d1', 'f5900000-0000-0000-0000-0000000000a1',
  'Morning duties', 'daily',
  array['f5900000-0000-0000-0000-000000000002', 'f5900000-0000-0000-0000-000000000003']::uuid[],
  array['Generator check', 'Read the meters']);
select pg_temp.check((select count(*) = 2 and bool_or(title = 'Generator check' and done_by is not null)
  from public.fn_duties('f5900000-0000-0000-0000-0000000000a1', (select today from t))),
  'renaming the list keeps what was ticked and drops removed duties');

-- Closed days and weekdays.
select public.fn_save_closure(null, 'f5900000-0000-0000-0000-0000000000a1', (select today from t), (select today from t), 'Holiday');
select pg_temp.check((select count(*) = 0 from public.fn_duties('f5900000-0000-0000-0000-0000000000a1', (select today from t))),
  'no duties on a closed day');
select pg_temp.check((select count(*) = 0 from public.fn_duties('f5900000-0000-0000-0000-0000000000a1', date '2030-01-05')
  where rota_id is not null) is not null, 'a future day can be looked at');
select pg_temp.as_owner();
update public.duty_rotas set every = 'weekdays' where id = 'f5900000-0000-0000-0000-0000000000d1';
select pg_temp.act_as('f5900000-0000-0000-0000-000000000001');
select pg_temp.check((select count(*) = 0 from public.fn_duties('f5900000-0000-0000-0000-0000000000a1', date '2030-01-05')),
  'a weekdays list has nothing on a Saturday');
select pg_temp.check((select count(*) = 2 from public.fn_duties('f5900000-0000-0000-0000-0000000000a1', date '2030-01-07')),
  'and its duties on a Monday');
select pg_temp.as_owner();

select pg_temp.fails($$insert into public.duty_done (task_id, day) select id, current_date from public.duty_tasks limit 1$$,
  '', 'ticks are only written through the function');

rollback;
