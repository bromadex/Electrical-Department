# Task: make Job Cards V2 as easy to use as the main app

**From:** Clement · **For:** Tafara (and your coding agent) · **Branch:** `feat/job-cards-v2`

The liquid-glass restyle looks right: same colours, glass, floating bar and
capsule menu as the main app. What is left is **layout**. The main app was
just reworked so people find things fast (see `CHANGELOG.md`); Job Cards V2
should follow the same rules. Screenshots of the current state are in
`docs/tasks/v2-layout/` (desktop 1440×900 and phone 390×844, signed in as
`supervisor@bravura.test` on the local seed).

Only change files under `app/lib/v2/` (and v2 tests). Do not change the
database, the main app's screens or the shared widgets' behaviour.

## Fixes

### 1. One title per page
Every page shows its name twice: the shell header (`_WindowHeader` /
`_PhoneTopBar` in `app/lib/v2/shell.dart`) and again in `AppPage`
(`app/lib/v2/ui/page.dart`), e.g. "Dashboard" above "Dashboard".
- Keep the shell header as the only title.
- `AppPage` keeps the subtitle (e.g. "Kamativi · last 30 days") and the
  actions (e.g. "New job card"), not the title.

### 2. Remove "Version 2" from what users see
The header eyebrow reads "JOB CARDS · VERSION 2" and the phone has no hint at
all. Users should see **Job cards**. "Version 2" can stay in code and docs.

### 3. Dashboard: what needs me first, then four numbers
`app/lib/v2/dashboard/dashboard_screen.dart` opens with 11 number tiles; on a
phone each takes a full row, so you scroll past 7 cards before anything
useful (see `phone-dashboard.jpg`). Follow the main app's Home
(`app/lib/screens/home_screen.dart`):
- **Top: a "Needs you" list**, made from the existing "Needs attention" data
  (`_Alerts`): critical, overdue, awaiting assignment, awaiting review, my
  assigned jobs. One row each with icon, one-line title, one-line detail and a
  chevron that opens the job card or the filtered list. Empty state:
  "All caught up".
- **Then four numbers in one card:** Open, Critical, Overdue, Closed today.
  Each opens the job cards list with that filter.
- The other counts (total, new/received, incoming requests, engineering
  review, equipment out of service, active split) move into the list filters
  or the charts. They are not tiles on the dashboard.
- Charts stay, below.
- Desktop: "Needs you" on the left (about 3/5), the numbers card and charts
  on the right, like Home.

### 4. Job cards list: filters in one row
`app/lib/v2/jobcards/job_cards_screen.dart`, `_FilterBar`. On a phone the
status chips, the search box, four priority chips and the date chip take three
rows; only two cards fit (see `phone-job-cards.jpg`).
- **One row:** search field, then a **Filter** button (badge = number of
  active filters) that opens a sheet with priority (P1–P4) and the received
  date.
- **Below it, one horizontally scrolling row of status chips** with counts
  (All open, New, Awaiting assignment, Active, Waiting, Critical, Overdue,
  Awaiting review, Needs clarification). Hide chips whose count is 0 except
  "All open" and the selected one. Copy the chip from
  `app/lib/screens/jobs_screen.dart` (`_FilterChip`).
- Move "New job card" off the page header on phones: the bottom bar's centre
  slot or a floating button, like the main app.

### 5. Job cards table fits the window
On a 1440 px screen the table runs off the right edge; the Priority column is
cut off (see `desk-job-cards.jpg`). `PagedTable` in
`app/lib/v2/ui/data_table.dart` scrolls sideways.
- Order columns by importance: **Priority, Job card no., Description,
  Equipment, Status, Received**. Show Work area only when the window is at
  least 1400 px wide.
- Let Description take the free width (ellipsis, 2 lines). Give Equipment a
  max width.
- Below about 1100 px wide, use the card layout (`cardBuilder`) that phones
  already use.
- No sideways scrolling at 1280×800 or wider.

### 6. "Back to main app" is easy to reach on phones
On phones it is only inside Menu.
- Put a back arrow at the left of `_PhoneTopBar` that goes to `/home`
  (`context.go('/home')`).
- Keep the Menu entry too.

## Done when
- [ ] No page shows its title twice; no user-visible "Version 2".
- [ ] Phone dashboard: the "Needs you" list and the four numbers are both
      visible without scrolling at 390×844.
- [ ] Phone job cards list: at least three cards visible at 390×844; filters
      take two rows at most.
- [ ] Desktop table: every column visible at 1280×800 and 1440×900, no
      sideways scroll.
- [ ] Phone top bar has a back arrow to `/home`.
- [ ] `dart format --set-exit-if-changed lib test`, `flutter analyze` and
      `flutter test` pass; the acceptance tests (`e2e/`) still pass. Update
      any selectors that relied on the old labels.
- [ ] New screenshots at the same sizes replace the ones in
      `docs/tasks/v2-layout/`. Delete this task file and its line in
      `CLAUDE.md` in the same commit.
