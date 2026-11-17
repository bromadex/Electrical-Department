# Bravura Electrical Department

Flutter app (Android and web) in `app/`, Supabase in `supabase/`, web hosted on
Vercel. What changed recently is in `CHANGELOG.md`; the API and data rules are
in `API.md`.

## Open tasks
- **Handover from Tafara (job cards).** Prompts 1–4 are done; see "Status on 27
  October" in `docs/tasks/handover-from-tafara.md` for what is still open.

## Working rules
- Main app tabs: Home `/home`, Jobs `/jobs`, Menu `/menu`. Chat is not a
  tab: it opens at `/chat` from the floating green button on every screen
  (`app/lib/chat/chat_fab.dart`). The ➕ New sheet is
  `app/lib/widgets/create_sheet.dart`.
- Wider than 720 points, the side bar (`app/lib/widgets/side_bar.dart`,
  `SideBarLayer` in `main.dart`) shows on every page and can be collapsed
  to icons; screens check `SideBarScope.shownOf` instead of drawing their
  own tab rail. It lists every page of the Menu tab in groups and has no
  Menu entry: a new Menu page goes in both `more_screen.dart` and the bar.
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
  `app/lib/theme/tokens.dart`) in burgundy, rose and blue. Light is the
  default for new users; dark liquid glass (issue #26) is in Settings →
  Appearance and the sun button.
  In the dark theme all transparency is white or black at low opacity over
  the brand colours; only status colours (green, amber, red) add other
  hues. Chat screens alone are WhatsApp for iPhone green (`ChatColors`,
  `AppTheme.chat`, `ChatThemed` in `app/lib/chat/wallpaper.dart`), light
  or dark as the phone is set: flat bubbles on the doodle wallpaper.
- Pushed screens use `AppBackButton` (`app/lib/widgets/app_back_button.dart`).
- Before pushing: `dart format --set-exit-if-changed lib test`,
  `flutter analyze` and `flutter test` in `app/`; database changes come with
  a test in `supabase/tests/`.
- Migrations are numbered and never edited once on `main`; add a new one.
- New tables and views: revoke writes from `authenticated` unless a policy
  allows them, and everything from `anon` (test 0040 checks).
- Give every new foreign key an index (test 0038 checks); queued calls must
  treat no signal as "wait", never as a failure (`OutboxService`).
- Calls queued offline must be on the outbox allow-list
  (`app/lib/services/outbox_service.dart`); `test/outbox_actions_test.dart`
  checks it.
