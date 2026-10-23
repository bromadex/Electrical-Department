# Electrical-Department

Bravura Electrical Department app: Flutter (web, Android and iOS), Supabase for sign-in and data, and Vercel to host the web build.

## Configuration

The app reads its Supabase settings at build time:

| Variable                   | Value                                              |
| -------------------------- | -------------------------------------------------- |
| `SUPABASE_URL`             | `https://<project-ref>.supabase.co`                |
| `SUPABASE_PUBLISHABLE_KEY` | The project's publishable (`sb_publishable_…`) key |

If these aren't set, the app opens on a "Setup required" screen.

## Run locally

```bash
flutter pub get
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-key>
```

## Deploy to Vercel

1. Import this repo as a Vercel project. `vercel.json` sets the build command and output folder.
2. Add `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` under **Settings → Environment Variables**.
3. Deploy. `scripts/vercel-build.sh` installs Flutter and runs `flutter build web`.

## Database (Supabase migrations)

Schema changes are SQL files in `supabase/migrations/`. Create one with
`supabase migration new <name>`. The `Supabase database` GitHub Actions workflow
runs whenever anything under `supabase/` changes:

- **Every branch and PR:** applies all migrations to a throwaway local database,
  lints the schema, and (if the secret is set) prints which migrations the real
  project would receive.
- **`main` only:** applies new migrations to the real project.

One-time setup: in Supabase, open **Connect → Session pooler** and copy the
connection string with your database password filled in (URL-encode any special
characters). In GitHub, add it under **Settings → Secrets and variables →
Actions → New repository secret** as `SUPABASE_DB_URL`.

This repo is public, so its Actions logs are public too. The workflow prints
only migration names, never table data.

## Branding

The logo is in `assets/branding/`. To regenerate the app and web icons after changing it, run `dart run flutter_launcher_icons`.
