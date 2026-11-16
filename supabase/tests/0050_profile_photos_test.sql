-- Behaviour checks for 0050_profile_photos. Runs in a transaction and rolls back.
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
  ('fe500000-0000-0000-0000-000000000001', 'pic-a@test', '{"full_name":"Pic Anna"}'),
  ('fe500000-0000-0000-0000-000000000002', 'pic-b@test', '{"full_name":"Pic Ben"}');

select pg_temp.act_as('fe500000-0000-0000-0000-000000000001');
select public.fn_set_my_avatar('fe500000-0000-0000-0000-000000000001'::text || '/1.jpg');
select pg_temp.check((select avatar_url = 'fe500000-0000-0000-0000-000000000001'::text || '/1.jpg' from public.profiles where id = 'fe500000-0000-0000-0000-000000000001'),
  'Anna sets her photo');
select pg_temp.fails($$select public.fn_set_my_avatar('fe500000-0000-0000-0000-000000000002/1.jpg')$$, 'INVALID',
  'not a photo in someone else''s folder');
select public.fn_set_my_avatar(null);
select pg_temp.check((select avatar_url is null from public.profiles where id = 'fe500000-0000-0000-0000-000000000001'), 'and removes it');

-- Storage: each person uploads only into their own folder.
insert into storage.objects (bucket_id, name, owner) values ('avatars', 'fe500000-0000-0000-0000-000000000001'::text || '/2.jpg', 'fe500000-0000-0000-0000-000000000001');
select pg_temp.check((select count(*) = 1 from storage.objects where bucket_id = 'avatars'), 'her own folder is fine');
select pg_temp.fails($$insert into storage.objects (bucket_id, name, owner)
  values ('avatars', 'fe500000-0000-0000-0000-000000000002/x.jpg', 'fe500000-0000-0000-0000-000000000001')$$, '',
  'nobody uploads into someone else''s folder');
select pg_temp.act_as('fe500000-0000-0000-0000-000000000002');
select pg_temp.check((select count(*) = 1 from storage.objects where bucket_id = 'avatars'), 'colleagues can see photos');
update storage.objects set name = 'x' where bucket_id = 'avatars';
select pg_temp.as_owner();
select pg_temp.check((select count(*) = 0 from storage.objects where bucket_id = 'avatars' and name = 'x'),
  'photos cannot be changed in place (no update policy)');
select pg_temp.as_owner();

rollback;
