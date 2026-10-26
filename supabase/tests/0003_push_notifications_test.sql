-- Behaviour checks for 0003_push_notifications. Runs in a transaction and
-- rolls back.
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

insert into auth.users (id, email, raw_user_meta_data) values
  ('70000000-0000-0000-0000-000000000001', 'push-a@test', '{"full_name":"Push A"}'),
  ('70000000-0000-0000-0000-000000000002', 'push-b@test', '{"full_name":"Push B"}');

select pg_temp.check((select count(*) = 1 from public.push_config), 'one push config row');
select pg_temp.check((select endpoint is null and length(secret) = 64 from public.push_config),
  'no endpoint until CI sets one, and a random secret');

-- Devices register and unregister as their own user.
select pg_temp.act_as('70000000-0000-0000-0000-000000000001');
select public.fn_register_device('token-a1', 'web');
select public.fn_register_device('token-a2', 'android');
select pg_temp.as_owner();
select pg_temp.act_as('70000000-0000-0000-0000-000000000002');
select public.fn_unregister_device('token-a1');
select pg_temp.as_owner();
select pg_temp.check((select not is_archived from public.device_tokens where token = 'token-a1'),
  'nobody can switch off another person''s device');
select pg_temp.act_as('70000000-0000-0000-0000-000000000001');
select public.fn_unregister_device('token-a1');
select pg_temp.as_owner();
select pg_temp.check((select is_archived from public.device_tokens where token = 'token-a1'),
  'signing out switches off this device');

-- Notifications still work with and without an endpoint.
select public.fn_notify('70000000-0000-0000-0000-000000000001', null, 'general', 'Before push', null, null);
select public.fn_set_push_endpoint('http://127.0.0.1:9/functions/v1/push-send');
select pg_temp.check((select endpoint from public.push_config) = 'http://127.0.0.1:9/functions/v1/push-send',
  'CI can store the endpoint');
select public.fn_notify('70000000-0000-0000-0000-000000000001', null, 'assigned', 'Pushed', 'Body', 'job:x');
select pg_temp.check((select count(*) = 2 from public.notifications
  where user_id = '70000000-0000-0000-0000-000000000001'), 'notifications are saved whether or not a push is queued');

-- What push-send reads, behind the secret.
select pg_temp.fails($$select public.fn_push_job(
  (select id from public.notifications where title = 'Pushed'), 'wrong')$$,
  'NOT_ALLOWED', 'a wrong secret gets nothing');
select pg_temp.check((
  select j ->> 'title' = 'Pushed' and j ->> 'link' = 'job:x'
    and jsonb_array_length(j -> 'tokens') = 1 and j -> 'tokens' -> 0 ->> 'token' = 'token-a2'
  from (select public.fn_push_job((select id from public.notifications where title = 'Pushed'),
    (select secret from public.push_config)) as j) x
), 'push-send gets the message and only the active devices');
select pg_temp.check(public.fn_push_drop_tokens((select secret from public.push_config), array['token-a2']) = 1,
  'dead tokens are switched off');
select pg_temp.check(not exists (select 1 from public.device_tokens where token = 'token-a2' and not is_archived),
  'the dropped token is archived');

-- The app cannot read the config or call the service functions.
select pg_temp.act_as('70000000-0000-0000-0000-000000000001');
do $$
declare
  v_rows bigint;
begin
  begin
    select count(*) into v_rows from public.push_config;
  exception when insufficient_privilege then
    v_rows := 0;
  end;
  perform pg_temp.check(v_rows = 0, 'the app cannot read the push secret');
end $$;
select pg_temp.fails($$select public.fn_push_job(gen_random_uuid(), 'x')$$, '', 'the app cannot call fn_push_job');
select pg_temp.fails($$select public.fn_set_push_endpoint('http://evil')$$, '', 'the app cannot change the endpoint');
select pg_temp.as_owner();

rollback;
