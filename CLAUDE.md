# Bravura Electrical Department

Flutter app (Android and web) in `app/`, Supabase in `supabase/`, web hosted on
Vercel. What changed recently is in `CHANGELOG.md`; the API and data rules are
in `API.md`.

## Open tasks
- **Handover from Tafara (job cards).** Prompts 1–4 are done; see "Status on 27
  October" in `docs/tasks/handover-from-tafara.md` for what is still open.

## Working rules
- Main app tabs: Home `/home`, Jobs `/jobs`, Chat `/chat`, Menu `/menu`. The
  ➕ New sheet is `app/lib/widgets/create_sheet.dart`.
- Job cards are the one job system: code in `app/lib/v2/`, screens at
  `/jobs` (list, the Jobs tab), `/jobs/<number>`, `/jobs/mine`, `/jobs/new`,
  `/requests`, `/my-requests`, `/job-stats` (see `app/lib/v2/routes.dart`).
  The old jobs board is gone; its tables keep their data but nothing writes
  to them. Shared data (people, equipment, plans) is in
  `app/lib/data/site_data.dart`.
- One UI kit: `app/lib/theme/tokens.dart`, `app/lib/ui/` (bits, surfaces with
  `Panel`, charts, media, time). `app/lib/v2/ui/` only adds job-card pieces
  (status pills, paged table, forms) and re-exports the kit.
- Keep the liquid-glass look (`app/lib/ui/surfaces.dart`,
  `app/lib/theme/tokens.dart`). Dark liquid glass is the default (issue
  #26); light stays in Settings → Appearance. In the dark theme all
  transparency is white or black at low opacity over the brand colours;
  only status colours (green, amber, red) add other hues.
- Pushed screens use `AppBackButton` (`app/lib/widgets/app_back_button.dart`).
- Before pushing: `dart format --set-exit-if-changed lib test`,
  `flutter analyze` and `flutter test` in `app/`; database changes come with
  a test in `supabase/tests/`.
- Migrations are numbered and never edited once on `main`; add a new one.
- Calls queued offline must be on the outbox allow-list
  (`app/lib/services/outbox_service.dart`); `test/outbox_actions_test.dart`
  checks it.
