# Handover from Tafara: job cards, what's left and the prompts

**From:** Tafara · **For:** Clement (and your coding agent) · **Date:** 26 October 2026

Tafara is handing the job cards work over to you. This file lists where it
stands, what is left, and ready-to-paste prompts that carry his instructions.

## Status on 27 October

**Done by Clement:**
- the layout task;
- prompt 1, one UI kit (`v2/ui` keeps only job-card pieces);
- prompt 2, charts drawn by the app, with `fl_chart` gone;
- prompt 3, job cards in the ➕ New sheet, on Home, from checklists and
  planned maintenance, in the daily report, from chat, and with SOPs;
- prompt 4, job cards are the Jobs tab and the board code is retired.

**Done by Tafara's branch `feat/job-cards-finish`:**
- **Offline:** job card comments, work-log entries and files go through the
  outbox (prompt 3).
- **Old jobs:** migration `0024` copies the jobs board's jobs into job cards,
  with photos, comments and closures, so their history shows again
  (prompt 4).
- **Dead code:** a search widget nothing used is gone (prompt 5).
- **Browser tests:** they follow job cards into the Jobs tab, using the real
  addresses plus a check that old links still lead to job cards.

**Done since (branch `feat/job-cards-polish`):**
- **"All my sites" is back:** a chip on the job card list, job statistics and
  incoming requests, shown to people with more than one site.
  - It lives on those screens, not in the shared site picker, because the
    rest of the app works with one site.
- **Outbox cleanup:** with v0.1.0 released, the eight jobs-board actions are
  off the outbox allow-list.
- **Nightly browser tests:** they now also run every night on `main`
  (03:30 Harare), as well as on `feat/**` branches and PRs.

**Still open:**
1. **Housekeeping, when you both agree:**
   - close PR #19;
   - close the branches `feat/cmms-phase-1`, `feat/push-notifications` and
     `feat/cmms-phase-2`.
2. **Firebase App Distribution:** release v0.1.0 is on GitHub, but its upload
   to the `electrical-team` testers failed with HTTP 403. Give the
   `FIREBASE_SERVICE_ACCOUNT` account the "Firebase App Distribution Admin"
   role, then send the next release (or re-run that step).

## Where it stands

- Job cards (the CMMS, "Version 2") are live on `main`: app code in
  `app/lib/v2/` under `/v2`, migrations `0012_v2_core`, `0013_v2_workflow`,
  `0014_v2_execution` (applied in production), API.md section 17.
- Branch `feat/job-cards-v2` has your layout task (`docs/tasks/v2-layout.md`)
  done in commit `6dbeb79`: one title per page, no "Version 2" on screen,
  dashboard with "Needs you" and four numbers, search + Filter row with
  status chips, a table that fits 1280 px (cards below 1100 px), and a back
  arrow on phones. `dart format`, `flutter analyze` and all 50 `flutter test`
  tests pass locally.
- Acceptance run `40358047832` (Actions) on `6dbeb79` was still running at
  handover. It includes a new layout test that checks the task's done-when
  list and saves the four screenshots.
- `6dbeb79` is **not on `main` yet**.

## What is left

1. **Finish the layout task.** When the acceptance run is green:
   - copy the four JPGs from the `acceptance` artifact
     (`e2e/screenshots/v2-layout/*.jpg`) over `docs/tasks/v2-layout/*.jpg`;
   - delete `docs/tasks/v2-layout.md` and its line in `CLAUDE.md` in the
     same commit;
   - merge `feat/job-cards-v2` into `main`.

   If the run fails, read the failing test's screenshot in the artifact:
   - So far, failures were either real bugs or CI's software rendering of the
     glass being slow. Limits are already doubled: 60 s waits, 8 min tests.
2. **Tafara's direction (below), as prompts 1–5.**
3. **Housekeeping when you both agree:**
   - close PR #19;
   - close the branches `feat/cmms-phase-1`, `feat/push-notifications` and
     `feat/cmms-phase-2` (all superseded by `main`).

## Tafara's direction (his words, typos fixed)

> My job card and maintenance system has superior features compared to
> Clement's, but Clement has better visual designs, so mine will be
> implemented on top using Clement's visuals, including the dashboard and
> graphs. Some features of Clement's that appear as my shortcomings should be
> incorporated. The source code should be rewritten cleanly to reduce the
> size of the source code.

Earlier choices that still stand:
- burgundy, dusty/dark rose, blue, black and white, with light and dark themes;
- the Inter font;
- your liquid-glass look, which Tafara approved.

## Prompts (paste one at a time, in order)

### Prompt 1: one design system
> Job cards in `app/lib/v2/` carry their own UI kit that duplicates the main
> app's: `v2/theme/tokens.dart` (Space, Radii, Motion, AppColors) and
> `v2/ui/bits.dart`, `page.dart`, `panels.dart`, `status.dart`, `charts.dart`
> (Pill, EmptyState, SectionHeader, AppAvatar, RecordCode, Skeleton,
> DonutChart…). Move job cards onto the main app's `theme/tokens.dart`,
> `ui/surfaces.dart`, `ui/bits.dart`, `ui/page.dart` and `ui/charts.dart`.
> - Keep only what the main app lacks, such as job-card status/priority pills
>   and the paged table, and keep it in the main kit's style.
> - Delete the duplicates. No behaviour or database changes.
> - `flutter analyze`, `flutter test` and the acceptance tests (`e2e/`) must
>   pass. Report how many lines were removed.

### Prompt 2: dashboard and graphs in the main app's style
> Rebuild the job cards dashboard (`v2/dashboard/`) with the main app's chart
> widgets (`ui/charts.dart`: BarChart, DonutChart, TrendChip, GlassSegmented),
> laid out like Home, and remove `fl_chart` from `pubspec.yaml`.
> - Keep every figure `fn_dashboard` returns: trend, by priority/type/area/
>   equipment/technician, overdue ageing, response and closure times.
> - Keep "Needs you" and the four numbers on top.

### Prompt 3: bring the main app's strengths to job cards
> Give job cards what the main app does better:
> - **New sheet:** "Report a fault" in the ➕ New sheet can raise a job
>   card (or a request for people without `jc.register`).
> - **Offline queue:** comments, photos and work-log entries queue offline
>   through the outbox (`services/outbox_service.dart` allow-list +
>   `test/outbox_actions_test.dart`). Status changes and timers stay
>   online-only so server times stay true.
> - **Chat:** "make a job from this message" can create a job card.
> - **Checklists:** a failed checklist item can raise a job card.
> - **SOPs:** documents/SOPs can be attached to job cards (like
>   `job_documents` for jobs).
> - **Daily report:** includes job card updates.
> - **Home:** Home's to-do list includes my job cards.
>
> New tables or functions come as a new numbered migration with a test in
> `supabase/tests/`; update API.md.

### Prompt 4: job cards as the one job system (agree first)
> Only after Clement and Tafara agree: make job cards the Jobs tab, copy
> existing jobs into job cards (old code kept), and point documents,
> checklists, chat, reports, recurring jobs (as planned maintenance) and the
> safety check at job cards.
> - Then retire the jobs board screens and their code.
> - Use a new migration that keeps the old tables as `legacy_*` (never
>   drop data), with tests.
> - Plan it first and list what each existing feature will use.

### Prompt 5: lean code
> After prompts 1–4, remove dead code and duplication across `app/lib`.
> - Delete unused screens, providers and widgets.
> - Merge near-identical helpers (formatting, time zones, pills).
> - Keep the outbox allow-list and every test green.
> - Report lines of code and APK/web bundle size before and after.

## Good to know

- **CI database tests:**
  - CI loads `seed.sql`, and the 10-minute escalation cron can fire during
    the SQL tests.
  - Count only the test's own notifications, never all of them (see
    `0006_tools_test.sql` and `0014_v2_execution_test.sql`).
- **Acceptance builds:**
  - Acceptance builds use `--dart-define=E2E=true`. That keeps the
    accessibility tree on and switches motion off (`main.dart`), so the
    mesh wallpaper doesn't redraw every frame on CI.
  - Playwright reads the accessibility tree, so text inside a tappable card
    merges into one label: match by pattern, not exact text.
- **Job cards names next to the jobs board:**
  - job cards use `job_card_comments` (the jobs board has `job_comments`)
    and `fn_jc_site_people` (the jobs board has `fn_site_people`);
  - job card notification links are `jobcard:` and `servicerequest:`
    (`request:` is the jobs board's).
- **Roles:**
  - roles keep the main app's names;
  - job cards add the `jc.*` / `req.submit` / `req.triage` codes and a
    Department Manager role.
