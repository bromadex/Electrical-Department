# Electrical-Department

Bravura Electrical Department app: Flutter (web, Android and iOS), Supabase for sign-in and data, and Vercel to host the web build.

**[API.md](API.md)** is the contract between the app and Supabase: every table,
function, bucket and realtime channel the app uses. Update it in the same pull
request as the migration or screen that changes it.

## Configuration

The app reads its Supabase settings at build time:

| Variable            | Value                                                |
| ------------------- | ---------------------------------------------------- |
| `SUPABASE_URL`      | `https://<project-ref>.supabase.co`                  |
| `SUPABASE_ANON_KEY` | The project's publishable (`sb_publishable_…`) key   |

If these aren't set, the app opens on a "Setup required" screen.

## Run locally

```bash
flutter pub get
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable-key>
```

To run against a local Supabase instead (needs Docker), run `supabase start`
and use the API URL and publishable key it prints.

After changing tables in `lib/data/local_db.dart`, regenerate the drift code
with `dart run build_runner build`. The generated `*.g.dart` files are committed.

## Deploy to Vercel

1. Import this repo as a Vercel project. `vercel.json` sets the build command and output folder.
2. Add `SUPABASE_URL` and `SUPABASE_ANON_KEY` under **Settings → Environment Variables**.
3. Deploy. `scripts/vercel-build.sh` installs Flutter and runs `flutter build web`.

## Database (Supabase migrations)

Schema changes are SQL files in `supabase/migrations/NNNN_name.sql`, each with a
matching `supabase/tests/NNNN_name_test.sql`. The `Supabase database` GitHub
Actions workflow runs whenever anything under `supabase/` changes:

- **Every branch and PR:** applies all migrations to a throwaway local database,
  lints the schema, runs the SQL tests, and (if the secret is set) prints which
  migrations the real project would receive.
- **`main` only:** applies new migrations to the real project.

One-time setup: in Supabase, open **Connect → Session pooler** and copy the
connection string with your database password filled in (URL-encode any special
characters). In GitHub, add it under **Settings → Secrets and variables →
Actions → New repository secret** as `SUPABASE_DB_URL`.

This repo is public, so its Actions logs are public too. The workflow prints
only migration names, never table data.

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

   After that, admins can give roles from the app once user management is built.

## Branding

The logo is in `assets/branding/`. To regenerate the app and web icons after changing it, run `dart run flutter_launcher_icons`.
