-- Local/CI data only: `supabase db reset` and `supabase start` load this file;
-- `supabase db push` (production) never does. Sites, roles and permissions
-- come from migration 0001.
--
-- Test users (password for all: Passw0rd!)
--   admin@bravura.test       Admin, all sites
--   supervisor@bravura.test  Supervisor, Kamativi
--   tech@bravura.test        Technician, Kamativi + Selous
--   store@bravura.test       Storekeeper, Kamativi

insert into public.areas (site_id, name)
select s.id, a.name
from public.sites s
join (values
  ('KAM', 'Plant – MCC room'),
  ('KAM', 'Plant – Crusher'),
  ('KAM', 'Camp – Block C'),
  ('KAM', 'Workshop'),
  ('SEL', 'Main substation'),
  ('SEL', 'Offices'),
  ('MAN', 'Pump station'),
  ('HRE', 'Head office')
) as a (site_code, name) on a.site_code = s.code;

with users (id, email, full_name, home) as (
  values
    ('10000000-0000-0000-0000-000000000001'::uuid, 'admin@bravura.test', 'Test Admin', 'HRE'),
    ('10000000-0000-0000-0000-000000000002'::uuid, 'supervisor@bravura.test', 'Test Supervisor', 'KAM'),
    ('10000000-0000-0000-0000-000000000003'::uuid, 'tech@bravura.test', 'Test Technician', 'KAM'),
    ('10000000-0000-0000-0000-000000000004'::uuid, 'store@bravura.test', 'Test Storekeeper', 'KAM')
), inserted as (
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  )
  select
    '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated',
    u.email, extensions.crypt('Passw0rd!', extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}',
    jsonb_build_object('full_name', u.full_name), now(), now(), '', '', '', ''
  from users u
  returning id, email
)
insert into auth.identities (
  id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at
)
select gen_random_uuid(), i.id, i.id::text, 'email',
  jsonb_build_object('sub', i.id::text, 'email', i.email, 'email_verified', true),
  now(), now(), now()
from inserted i;

update public.profiles p
set home_site_id = s.id
from (values
  ('10000000-0000-0000-0000-000000000001'::uuid, 'HRE'),
  ('10000000-0000-0000-0000-000000000002'::uuid, 'KAM'),
  ('10000000-0000-0000-0000-000000000003'::uuid, 'KAM'),
  ('10000000-0000-0000-0000-000000000004'::uuid, 'KAM')
) as h (user_id, site_code)
join public.sites s on s.code = h.site_code
where p.id = h.user_id;

insert into public.user_roles (user_id, role_id, site_id)
select g.user_id, r.id, s.id
from (values
  ('10000000-0000-0000-0000-000000000001'::uuid, 'Admin', null),
  ('10000000-0000-0000-0000-000000000002'::uuid, 'Supervisor', 'KAM'),
  ('10000000-0000-0000-0000-000000000003'::uuid, 'Technician', 'KAM'),
  ('10000000-0000-0000-0000-000000000003'::uuid, 'Technician', 'SEL'),
  ('10000000-0000-0000-0000-000000000004'::uuid, 'Storekeeper', 'KAM')
) as g (user_id, role_name, site_code)
join public.roles r on r.name = g.role_name
left join public.sites s on s.code = g.site_code;

select public.fn_notify(
  '10000000-0000-0000-0000-000000000003', s.id, 'general',
  'Welcome to Bravura Electrical', 'This is a test notification from seed.sql.', null
)
from public.sites s where s.code = 'KAM';
