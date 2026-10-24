# Bravura Electrical

Electrical Department Job Card & Maintenance Management System: an Android +
web app, built from one Flutter codebase on Supabase. Faults and requests are
received, registered, assessed, assigned, worked, verified and closed as
numbered job cards, with a live dashboard, an asset register and role-based
access per site.

```
app/        Flutter app (Android + web)
supabase/   migrations/, tests/, functions/, seed.sql
API.md      app <-> Supabase contract
```

**[API.md](API.md)** lists every table, function, bucket and realtime channel
the app uses. Update it in the same pull request as the migration or screen
that changes it.

## Way of working

- One branch per phase or feature (`feat/cmms-phase-1`), pull request into
  `main`, reviewed before merging.
- Database changes are new numbered files in `supabase/migrations/`
  (`0007_…sql`) with a matching test in `supabase/tests/`.
  Never edit a migration that has been applied to production.
- Merging to `main` applies new migrations to Supabase, deploys edge functions
  and deploys the web app. Tagging `v1.2.3` builds the APK.

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

### Local Supabase

`config/dev.example.json` points at a local Supabase, so development never
touches real data. It runs in Docker. On Windows, Docker Engine inside WSL
works and needs no Docker Desktop licence:

1. In an administrator PowerShell: `wsl --install -d Ubuntu`, then restart.
2. In Ubuntu: `sudo apt update && sudo apt install -y docker.io` and
   `sudo usermod -aG docker $USER` (close and reopen Ubuntu).
3. Install the Supabase CLI (same version as CI, see
   `.github/workflows/supabase.yml`) from its GitHub releases.
4. In the repo folder (`/mnt/c/...` from Ubuntu):

```bash
supabase start      # applies migrations and supabase/seed.sql
supabase db reset   # start again from migrations + seed
```

API on `127.0.0.1:54321`, Studio on `127.0.0.1:54323`, test mail inbox on
`127.0.0.1:54324`.

Seeded users (password `Passw0rd!`, all `@bravura.test`):

| email | person | role |
| --- | --- | --- |
| `admin@` | Tendai Moyo | System Administrator |
| `engineer@` | Farai Chikwanha | Electrical Engineer, Kamativi |
| `electrician@` | Tatenda Ncube | Electrician, Kamativi and Selous |
| `electrician2@` | Kudakwashe Sibanda | Electrician, Kamativi |
| `manager@` | Nyasha Mlambo | Department Manager, all sites; P1 escalation contact |
| `requester@` | Blessing Dube | Requester (Production), Kamativi |
| `store@` | Rudo Mutasa | Storekeeper, Kamativi |

The seed also adds work areas, 20 assets, requests and job cards in every
state, including overdue and P1 jobs.

### Checks

```bash
dart format lib test
flutter analyze
flutter test
```

After changing tables in `app/lib/data/local_db.dart`, run
`dart run build_runner build`. Generated `*.g.dart` files are committed; CI
fails if they are stale.

Database tests are plain SQL in `supabase/tests/`; with local Supabase running:
`psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -f supabase/tests/<file>.sql`.

## CI and deploys

| Workflow | When | What |
| --- | --- | --- |
| `App` | every push and PR | `flutter analyze`, `flutter test`, format and generated-code checks |
| `App` | pull request | Android debug build check; web preview deployed to Vercel, link in the run summary (built against production Supabase) |
| `App` | push to `main` | web build deployed to Vercel production |
| `App` | tag `v*` | release APK attached to a GitHub release (+ Firebase App Distribution) |
| `Acceptance tests` | pushes to `feat/**` and PRs touching the app or database | browser tests against a throwaway Supabase; screenshots in the `acceptance` artifact |
| `Supabase database` | changes under `supabase/` | edge function type check, migrations + lint + SQL tests on a throwaway database, preview of pending migrations |
| `Supabase database` | push to `main` | new migrations applied to Supabase; edge functions deployed and push notifications switched on |

GitHub settings (**Settings → Secrets and variables → Actions**):

| Name | Kind | Value |
| --- | --- | --- |
| `SUPABASE_DB_URL` | secret | Session pooler connection string (Supabase **Connect → Session pooler**) |
| `SUPABASE_ACCESS_TOKEN` | secret | optional, deploys edge functions; supabase.com **Account → Access Tokens** |
| `SUPABASE_URL` | variable | `https://<project-ref>.supabase.co` |
| `SUPABASE_ANON_KEY` | variable | publishable key (`sb_publishable_…`) |
| `VERCEL_TOKEN` | secret | Vercel **Account Settings → Tokens** |
| `VERCEL_ORG_ID` | secret | Vercel team ID (**Team Settings → General**) |
| `VERCEL_PROJECT_ID` | secret | Vercel **Project Settings → General → Project ID** |
| `ANDROID_KEYSTORE_BASE64` etc. | secret | optional APK signing key, see `.github/workflows/app.yml` |
| `FIREBASE_APP_ID` | secret | Android app ID, for Firebase App Distribution |
| `FIREBASE_SERVICE_ACCOUNT` | secret | Firebase Admin SDK service account JSON: App Distribution uploads and push notifications |
| `APP_URL` | variable | optional; the web app's address, opened by browser notifications (defaults to the Vercel production URL) |

GitHub Actions builds the web app and uploads the finished files to Vercel, so
Vercel never builds Flutter itself. `vercel.json` turns off Vercel's own Git
builds; leave the Vercel project's build settings at their defaults.

The repo is public, so Actions logs are public too. Workflows print only
migration names and deploy URLs, never table data or secrets.

## Users

Accounts are created by a System Administrator, not by sign-up from the app.
In Supabase, turn off **Authentication → Sign In / Providers → Allow new users
to sign up**.

**The first administrator.** Add yourself under **Authentication → Users → Add
user** (tick *Auto Confirm User*); a profile is created automatically. Then
run this in the **SQL Editor**:

```sql
insert into public.user_roles (user_id, role_id, site_id)
select u.id, r.id, null            -- null = all sites
from auth.users u, public.roles r
where u.email = 'you@example.com' and r.name = 'System Administrator';
```

**Everyone else.** In the app, **User Management → Add user** creates the
account with a temporary password (give it to the person in person) and sets
their department, home site and roles per site. This needs the `admin-users`
edge function, deployed by CI when `SUPABASE_ACCESS_TOKEN` is set; until then,
add people in the Supabase dashboard as above and set their roles in the app.

## Push notifications and testers' APKs

Both use the team's Firebase project (sender ID `86873598340`). See API.md section 8.

**Push notifications** (alerts when the app is closed):

1. **App config.** Put the public identifiers in `app/lib/config/firebase_config.dart`:
   - the project ID;
   - the **Web** app's API key and app ID (Project settings → Your apps → Web);
   - the **Android** app's API key (`current_key` in its `google-services.json`).

   The web push key and the Android app ID are already there.
2. **Service account.** Make sure the `FIREBASE_SERVICE_ACCOUNT` repo secret is a Firebase
   Admin SDK key (Project settings → Service accounts → Generate new private key).
3. **Supabase token.** Add the `SUPABASE_ACCESS_TOKEN` repo secret.
4. **Merge.** The next merge to `main` deploys `push-send`, gives it the key and switches
   pushes on.
5. **Each person.** In the app, tap **Turn on** in the blue banner, or choose **Alerts on this
   device** in the account menu.

Pushes come on browsers and on the prod Android app, not on the dev flavor. On iPhones,
browser pushes work only once the site is added to the home screen.

**APKs for testers.**
1. In Firebase App Distribution, create a tester group called `electrical-team` and add
   people to it.
2. Push a version tag, e.g. `git tag v1.0.0 && git push origin v1.0.0`. CI builds the release
   APK, attaches it to a GitHub release and sends it to the group. It needs
   `FIREBASE_APP_ID` and `FIREBASE_SERVICE_ACCOUNT`, and a signing key for upgrades to install
   over each other.

## Branding

The logo is in `app/assets/branding/`. To regenerate the app and web icons
after changing it, run `dart run flutter_launcher_icons` in `app/`.
