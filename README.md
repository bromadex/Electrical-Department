# Bravura Electrical

Android + web app for the Bravura Electrical department, built from one
Flutter codebase on Supabase. See the build plan for features and roadmap.

```
app/        Flutter app (Android + web)
supabase/   migrations/, tests/, seed.sql
API.md      app <-> Supabase contract
```

**[API.md](API.md)** lists every table, function, bucket and realtime channel
the app uses. Update it in the same pull request as the migration or screen
that changes it.

## Way of working

- One branch per feature (`feat/jobs-board`), pull request into `main`, the
  other developer reviews before merging.
- Database changes are new numbered files in `supabase/migrations/`
  (`0002_jobs.sql` …) with a matching `supabase/tests/0002_jobs_test.sql`.
  Never edit a migration that has been applied.
- Merging to `main` applies new migrations to Supabase and deploys the web app.
  Tagging `v1.2.3` builds the APK.

## Run the app

Copy a config file and fill it in (files in `app/config/` other than the
examples are not committed):

```bash
cd app
cp config/dev.example.json config/dev.json
flutter pub get
flutter run -d chrome --dart-define-from-file=config/dev.json
flutter run --flavor dev --dart-define-from-file=config/dev.json   # Android
```

Flavors: `dev` installs as "Electrical DEV" (`com.bravura.electrical_department.dev`)
and shows a DEV label; `prod` installs as "Bravura Electrical". Both can be on
one phone.

`config/dev.example.json` points at a local Supabase. Start one with Docker:

```bash
supabase start      # applies migrations and supabase/seed.sql
```

Seeded test users (password `Passw0rd!`): `admin@bravura.test`,
`supervisor@bravura.test`, `tech@bravura.test`, `store@bravura.test`.

After changing tables in `app/lib/data/local_db.dart`, run
`dart run build_runner build`. Generated `*.g.dart` files are committed; CI
fails if they are stale.

## CI and deploys

| Workflow | When | What |
| --- | --- | --- |
| `App` | every push and PR | `flutter analyze`, `flutter test`, format and generated-code checks |
| `App` | push to `main` | web build deployed to Vercel production |
| `App` | pull request | web preview deployed to Vercel; link in the run summary |
| `App` | tag `v*` | release APK attached to a GitHub release (+ Firebase App Distribution) |
| `Supabase database` | changes under `supabase/` | migrations + SQL tests on a throwaway database; preview of pending migrations |
| `Supabase database` | push to `main` | new migrations applied to Supabase |
| `Acceptance tests` | pushes to `feat/**` and PRs touching the app or database | browser tests of Job Cards Version 2 (and Version 1's board) against a throwaway Supabase; screenshots in the `acceptance` artifact |

GitHub settings (**Settings → Secrets and variables → Actions**):

| Name | Kind | Value |
| --- | --- | --- |
| `SUPABASE_DB_URL` | secret | Session pooler connection string (Supabase **Connect → Session pooler**) |
| `SUPABASE_URL` | variable | `https://<project-ref>.supabase.co` |
| `SUPABASE_ANON_KEY` | variable | publishable key (`sb_publishable_…`) |
| `VERCEL_TOKEN` | secret | Vercel **Account Settings → Tokens** |
| `VERCEL_ORG_ID` | secret | Vercel team ID (**Team Settings → General**) |
| `VERCEL_PROJECT_ID` | secret | Vercel **Project Settings → General → Project ID** |
| `ANDROID_KEYSTORE_BASE64` etc. | secret | optional APK signing key, see `.github/workflows/app.yml` |
| `FIREBASE_APP_ID`, `FIREBASE_SERVICE_ACCOUNT` | secret | optional, for Firebase App Distribution |

GitHub Actions builds the web app and uploads the finished files to Vercel, so
Vercel never builds Flutter itself. `vercel.json` turns off Vercel's own Git
builds; leave the Vercel project's build settings at their defaults.

The repo is public, so Actions logs are public too. Workflows print only
migration names and deploy URLs, never table data or secrets.

## Users

Accounts are created by an admin, not by sign-up from the app:

1. In Supabase, turn off **Authentication → Sign In / Providers → Allow new users to sign up**.
2. Add each person under **Authentication → Users → Add user** (tick *Auto Confirm User*).
   A profile is created automatically.
3. Give them a role. For the very first admin, run this in the **SQL Editor**:

   ```sql
   insert into public.user_roles (user_id, role_id, site_id)
   select u.id, r.id, null            -- null = all sites
   from auth.users u, public.roles r
   where u.email = 'you@example.com' and r.name = 'Admin';
   ```

## Job Cards Version 2

The job card & maintenance management system runs beside the jobs board so the two can
be compared: the **Job cards** tile ("New system · trial") in Menu and on Home, or the first
link in the desktop side menu (`/v2`). It has its own menu (dashboard, job cards,
incoming requests, my jobs, my requests, audit log, settings) and shares people, sites,
assets, notifications and the theme with the main app; "Back to main app" returns to Home.
Its code is in `app/lib/v2/` and migrations 0012–0014; API.md section 17 lists its tables
and functions.

Who can use it comes from the roles: technicians work job cards, supervisors register,
assess, assign and verify them, and anyone with a role can raise a request. Settings →
priorities, escalation rules and the safety checklist need `settings.manage` (Admin).
Local test data adds `tech2@`, `manager@` and `requester@bravura.test` (password as above).

## Branding

The logo is in `app/assets/branding/`. To regenerate the app and web icons
after changing it, run `dart run flutter_launcher_icons` in `app/`.
