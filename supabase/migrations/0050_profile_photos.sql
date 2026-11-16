-- 0050_profile_photos: everyone can set their own profile photo.
--
-- Photos live in the private avatars bucket at <user id>/<file>; anyone
-- signed in and active may see them, each person may add files only in
-- their own folder (no update or delete policies: a new photo is a new
-- file). fn_set_my_avatar saves the path in profiles.avatar_url (null
-- removes the photo). The app signs links to show them.

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', false)
on conflict (id) do nothing;

create policy avatars_select on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and public._active());
create policy avatars_insert on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and public._active()
    and split_part(name, '/', 1) = auth.uid()::text
  );

create function public.fn_set_my_avatar(p_path text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public._active() then
    raise exception 'NOT_ALLOWED: Sign in first';
  end if;
  if p_path is not null and (
    split_part(p_path, '/', 1) <> auth.uid()::text or length(p_path) > 300
  ) then
    raise exception 'INVALID: The photo must be in your own folder';
  end if;
  update public.profiles set avatar_url = nullif(p_path, '') where id = auth.uid();
end;
$$;

revoke execute on function public.fn_set_my_avatar(text) from public, anon;
grant execute on function public.fn_set_my_avatar(text) to authenticated;

insert into public.schema_migrations (filename) values ('0050_profile_photos.sql')
on conflict do nothing;
