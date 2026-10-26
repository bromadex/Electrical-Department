# Bravura Electrical Department

Flutter app (Android and web) in `app/`, Supabase in `supabase/`, web hosted on
Vercel. What changed recently is in `CHANGELOG.md`; the API and data rules are
in `API.md`.

## Open tasks
- **Job Cards V2 layout fixes.** Read `docs/tasks/v2-layout.md` and do it
  before other v2 UI work. Screenshots are in `docs/tasks/v2-layout/`.

## Working rules
- Main app tabs: Home `/home`, Jobs `/jobs`, Chat `/chat`, Menu `/menu`. The
  ➕ New sheet is `app/lib/widgets/create_sheet.dart`. Job Cards V2 lives in
  `app/lib/v2/` under `/v2`.
- Keep the liquid-glass look (`app/lib/ui/surfaces.dart`,
  `app/lib/theme/tokens.dart`). Light theme is the default.
- Pushed screens use `AppBackButton` (`app/lib/widgets/app_back_button.dart`).
- Before pushing: `dart format --set-exit-if-changed lib test`,
  `flutter analyze` and `flutter test` in `app/`; database changes come with
  a test in `supabase/tests/`.
- Migrations are numbered and never edited once on `main`; add a new one.
- Calls queued offline must be on the outbox allow-list
  (`app/lib/services/outbox_service.dart`); `test/outbox_actions_test.dart`
  checks it.
