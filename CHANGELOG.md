# What's new

## 14 November 2026

### Safer permissions (issue #35)
- A permission audit found one hole: anyone signed in could trigger the
  standby reminders early. Closed. Nobody signed out can touch any table,
  and nothing can be written directly that should go through the app's
  checks; a test keeps it so.
- The last admin can no longer be removed or deactivated, and the Admin role
  always keeps user management, so nobody can lock the department out.

### Equipment history (issue #33)
- Each piece of equipment shows its faults in 30 and 90 days, how long it
  was out of service, and a **Repeat faults** sign at 3 or more in 30 days.
- Job statistics has a **Repeat faults and downtime** panel.

### Reserved stock (issue #34)
- Stock on approved material requests not yet issued counts as reserved;
  an item shows how much is reserved and how much is free. A project's BOQ
  counts only stock not reserved for someone else.

### Search and sync (issue #36)
- A **search** button on every tab finds job cards, equipment, tools,
  documents, inventory, projects, material requests and purchases by code or
  name.
- **Waiting to send** shows when something last reached the server and how
  long the oldest unsent change has waited.

### Backups (issue #31)
- The nightly restore test now compares a checksum of every table's values,
  not just row counts.
- Uploaded files can be copied, encrypted, every night to Google Drive or
  other free storage once set up (docs/backup-files.md).

## 8 November 2026, night

### Stock take
- **Past counts** (Inventory → clock icon, `/inventory/counts`): every count
  with who, when, how many items and which were corrected, from what to what.
- A count in progress is kept on the phone: leaving the screen (a call,
  another app) no longer loses it. **Start again** clears it.
- A count typed without signal and sent later no longer wipes out stock
  issued or received in between: each line is corrected as of when it was
  counted (migration 0039).

### Nothing is lost by accident (issues #28, #29)
- **Signing out** with changes not yet sent no longer deletes them: the app
  says how many, and offers to wait, see them, or sign out and delete them.
- A change whose photo or file the server refused waits (with the reason in
  **Waiting to send**) instead of being saved pointing at a missing file.
  Trying the file again sends both; discarding the file discards the change.

### Documents
- Drag a document that is not in a folder onto a folder to move it there
  (with the mouse on a computer, long-press on a phone), with Undo.

### Releases (issue #30) and README (issue #32)
- A release without the signing key now stops instead of producing an APK
  signed with the debug key. The README describes the system as it is now.

## 8 November 2026, evening

### Work done without signal is never lost (issue #17)
- Before, a phone without signal for about two and a half minutes gave up
  on changes waiting to send. Now no signal never counts as a failure: the
  app waits a little longer each time and sends as soon as it can. Changes
  an older version gave up on come back by themselves.
- **Settings → Waiting to send** shows everything not yet on the server,
  with **Try again** and **Discard** for anything the server refused, and
  **Send now**.
- **App errors** (Settings → Admin): errors on people's phones are reported
  and grouped, so they can be fixed.
- Faster lookups: every link between tables now has an index.
- Releases now also build the bundle the Play Store needs; the privacy
  policy is published with the web app.

## 8 November 2026, afternoon

### Smaller things
- **All my sites** now also works on Inventory, Projects and Documents:
  everything from every site, each tagged with its site.
- **Excel files**: the BOQ import takes .xlsx files as well as CSV.
- **Drag and drop**: on a PC, drop files onto Documents to upload them.

### Statistics, imports, backups and admin (issue #16)
- **Inventory stats** (chart icon on Inventory): what was used most, stock
  per project, the job cards using the most, corrections and what is low.
- **Import from Excel** on Inventory (items with their opening stock) and
  on Equipment & tools (tools with serial numbers and calibration dates).
  The first row names the columns; the app works out which is which.
- **Roles and permissions** (Settings → Admin): switch what each role may
  do.
- **Reports archive** (archive icon on the daily report): every daily
  report, with search through what people wrote.
- **Nightly backups**: the database is copied every night, test-restored to
  prove it works, encrypted and kept for 90 days.

## 8 November 2026

### The store is now called Inventory
- Menu → **Inventory** (was Store). Old links still open.

### Projects, calendar and roster (issue #14)
- **Projects** (Menu): each with a progress ring from its job cards, a
  team, the materials issued to it and its bill of quantities. Add or take
  off job cards from the project page.
- **Calendar**: a month view with a coloured dot for everything due (job
  cards, meetings, tools coming back, calibration, planned maintenance,
  project deadlines, your shifts and reminders); tap a day for its list.
- **Roster**: your shifts for the week at the top. Supervisors tap a day to
  set day, night, off or leave, press and hold for standby, then publish;
  everyone on it is told, and standby people are reminded the day before.

### Materials and purchases (issue #13)
- **Request materials** from ➕ New, a project or Menu → Materials: pick
  from inventory or type what is not stocked. A supervisor approves or
  rejects with a reason.
- The store **issues** from inventory, or **orders** what is missing: a
  purchase with supplier, PO number, expected date and prices, filled in
  from the request. **Receive delivery** puts it into inventory and tells
  whoever asked.
- On a project, **import the BOQ** by pasting three columns from Excel (or
  a CSV file) and see each line issued, requested, on order and in
  inventory. **Request the shortfall** turns what is missing into one
  request.

### Tool stats (issue #27)
- Equipment & tools → the chart icon (or Menu → Tool stats): losses, late
  returns, damage with its repair job card, calibration due or expired, and
  who had what, for 7 days to a year, one site or all.

## 7 November 2026, evening: database for three more features

No screens yet; these are the server side, tested and live.

- **Projects, roster and calendar (issue #14):** projects with P- codes,
  a team and progress from their job cards; store stock can be issued to a
  project. A weekly roster with day, night, off and leave shifts and
  standby; publishing it tells everyone on it, and standby people get a
  reminder the afternoon before. One calendar of job cards due, meetings,
  tool returns, calibration, planned maintenance, project dates, your own
  shifts and your reminders.
- **Material requests, purchases and BOQ (issue #13):** ask for materials
  (MR-) for a job card or project; a supervisor approves; the store issues
  from stock or buys it. Purchases (PO-) with supplier, prices and expected
  date, received into the store; whoever asked is told when it arrives.
  A project's bill of quantities compared with what was issued, requested,
  on order and in stock; the shortfall becomes a request in one go.
- **Tool statistics (issue #27):** losses, late returns, damage with its
  repair job cards, calibration due or expired, and who had what, for one
  site or all of them.

## 7 November 2026

### Electrical store, second half (issue #12)
- **Take back**: unused stock coming back from a job card or a person.
- **Adjust**: add or take off stock with a reason (damaged, found,
  written off); it shows in the item's history.
- **Count stock** (the # icon on Store): items sorted by bin; type what is
  on the shelf and see the difference as you go. Saving corrects only the
  items that differ and keeps the whole count on record.
- **Without signal** the store shows the stock as last loaded on the phone,
  with when that was. Moves and counts are kept and sent when back online.
- The store and supervisors are alerted about low stock whatever caused it:
  an issue, an adjustment or a count.

## 5 November 2026

### Electrical store (first half of issue #12)
- **Menu → Store**: every store item at the site with its I- code, bin and
  stock on hand. Search by name, code or bin; filter by low stock or by
  type (cable, breakers, lugs, glands, lamps, fittings, consumables).
  Stock shows red when empty and amber when below its minimum.
- The storekeeper adds items (unit, category, bin, "alert below" level),
  **receives** deliveries and **issues** stock to a job card or a person.
  Every movement is kept with who, when and the balance after.
- Stock can never go below zero, and the store and supervisors are
  alerted when an item falls under its minimum.
- Next: returns, adjustments, stock counts and issuing to projects.

## 29 October 2026

### One team: everyone works at every site
- Everyone's roles now apply at **all sites**: a Harare technician can
  comment on and work Kamativi job cards, do its checklists, add to its
  daily report and sign its SOPs, as people at Kamativi do.
- Alerts follow: supervisors hear about critical and overdue job cards at
  every site, and everyone is in every site's group chat.
- Admin → Users still lets you limit a role to one site if needed.

### Everyone can see every site
- The site picker now lists all four sites (Harare, Kamativi, Manhizi,
  Selous) for everyone. Sites where you have no role are marked
  **view only**: you see their job cards, tools, store, documents, reports
  and statistics.
- Work stays at your own sites: commenting on or working a job card,
  adding to the daily report, doing checklists and signing SOPs need a
  role at that site. Alerts still come only from your own sites.

### Documents, now a proper file library
- **Folders** per site (supervisors make, rename and archive them). Each
  shows how many files it holds, their size and how many still need
  signing. Move a document with ⋮ → Move to folder; archiving a folder
  moves its documents out and deletes nothing.
- **File-type badges**: PDF red, Word blue, Excel green, PowerPoint amber,
  drawings coral, photos pink.
- **Grid or list**, remembered on each phone or PC. On a wide screen the
  list has columns: updated, added by, size and signatures.
- **Filters**: All, To sign, Recent (30 days), Added by me, and the type
  (SOP, Drawing, Manual, Form, Other).
- **Upload several files at once**: each becomes its own document named
  after the file. Choose the folder, type and signing once; every file
  shows waiting, uploading or done.
- **Quick actions** on each document (⋮): open, download, share in a chat,
  copy a 7-day link for a contractor without the app, move, edit or upload
  a new version, archive.
- Supervisors see how many people signed each SOP's current version.

## 28 October 2026

- **Personal reminders** (issue #7): "Remind me" on a job card or a tool
  (alarm icon), ➕ New → Reminder, or Menu → Reminders. Pick in 1 hour,
  3 hours, today 14:00, tomorrow 08:00, Monday 08:00 or any time; it comes
  as a notification that opens the job card or tool. Works offline.
- **Share from Documents in chat** (issue #23): + → From Documents sends a
  message that opens the SOP or drawing.
- **Repairs close the loop**: when a tool's repair job card is closed, the
  tool is back to Good (in service) and the store is told.
- The unused `meeting-record` function is removed from Supabase on the next
  deploy.
- Issues #4, #5, #6, #8, #9 and #20 closed (done); PR #19 closed (replaced
  by job cards).

## 27 October 2026, evening

### Dark liquid glass is the new look (issue #26)
- The app now opens in a **dark liquid-glass** theme in the Bravura
  colours: a deep burgundy backdrop with soft burgundy and rose glows and
  two slowly drifting blurred blobs (still when the phone asks for less
  motion).
- Four levels of glass, each more solid: panels, tiles, controls, then
  sheets, dialogs and menus (a dark burgundy tint). Panels have a lit top
  edge and a soft shadow; the top bar fades and blurs what scrolls under it.
- The open tab glows; text is near-white with two softer levels; inputs
  are dark wells; focus rings show for keyboards.
- Light is still there: **Settings → Appearance → Light** (or the sun icon
  in the top bar).
- Tool icons now use the Bravura colours only; status colours keep their
  meaning (green in store, amber due, red late).
- Fixed: the Jobs tab showed a big empty gap above My jobs / All job cards.

## 27 October 2026, afternoon

### Tool issue forms, and tools on job cards
- **Tool issue form** (Equipment & tools → Forms → New form): the paper form
  in the app. Issue several tools at once to one person, also someone from
  another company who does not use the app (name, trade, company), with the
  project team lead, the place and the expected return date. Each tool has a
  quantity and its condition going out. The store, the person receiving and
  the team lead sign on the screen. Tools not in the register yet are added
  on the spot with "New tool".
- **Take back** part or all of a form, with each tool's condition and a note
  when it is not good; supervisors hear about damaged or lost tools. The form
  shows Out, "N still out" or Returned.
- **PDF** of the form, laid out like the company's paper form, with the
  signatures, to share or print.
- **Who has it**: tools out on a form show the person's name and company on
  the register and the tool's page, with a link to the form.
- **Tools on job cards**: a job card's Assignment tab lists the tools the job
  needs, who has each one, and issues the ones in store on a form for that
  job. Each tool's page has a **Jobs** tab: the job cards it was used on.
- **Calibration**: a tool whose calibration has expired can no longer be lent
  or issued. Upload the **calibration certificate** (PDF or photo) on the
  tool's Details tab with the date it is valid until; that becomes the
  tool's calibration due date.
- **Repairs**: a tool that comes back Damaged or Needs repair gets a
  **repair job card** straight away, so it queues with the rest of the work
  and shows on the tool's Jobs tab.
- **First official form recorded**: Tinashe Mademe's Tool Issue Form of 27
  October (Manhattan, 15 tools) is in the app at Harare as TI-0001, with its
  15 tools added to the Harare register (migration 0027; the signatures are
  on the paper form).
- **Who has what** (people icon on the tools side): everyone holding tools
  right now, also outside contractors with their company, with overdue
  tools first. What to check before someone goes on leave or leaves.

## 27 October 2026 (on `main`)

### Calls on Android phones
- **Ringing calls.** A direct call rings the other phone with a full-screen
  incoming call and ringtone (Answer / Decline), even when the app is closed
  or the phone is locked. It stops after 45 seconds and becomes a missed
  call. The server sends call pushes to Android as high-priority data
  messages (`push-send`, type `call`, migration 0025).
- **Calls keep going when minimised.** While in a call the phone shows a
  "Call in progress" notification (tap to return, or hang up from it), so
  the microphone and sound keep working with the app in the background.
- **Speaker button** in the call to switch between earpiece and loudspeaker
  (video calls start on the loudspeaker).
- Samsung phones: if calls do not ring with the app closed, set the app's
  battery use to **Unrestricted** (Settings → Apps → Bravura Electrical →
  Battery).

## 26 October 2026 (on `main`)

### New layout and names
The app was rearranged so people find things quickly. Tabs are now
**Home · Jobs · ➕ · Chat · Menu** (phones); the desktop side menu has the same
tabs, a **New** button and direct links to Job cards, Checklists, Daily report,
Equipment, Tools and Documents.

| Was | Now | Address |
|---|---|---|
| Today | Home | `/home` |
| Board | Jobs | `/jobs` |
| More | Menu | `/menu` |
| Store tab | removed (tools are under Tools) | `/tools` |
| Assets | Equipment | `/assets` |
| Recurring jobs | Planned maintenance | `/jobs/recurring` |
| Requests | Work requests | `/requests` |
| Priority targets | Response times | `/admin/targets` |
| Audit log | Activity log | `/admin/activity` |

The old addresses (`/today`, `/board`, `/more`, `/store`) redirect, so old links
still work.

- **➕ New** (middle of the phone bar, top of the desktop menu): one sheet to
  report a fault, add to today's report, do a checklist, lend a tool, send a
  message, add a document or open work requests. It only shows what the
  person's role allows. `lib/widgets/create_sheet.dart`
- **Home** is a to-do list (my jobs, checklists due, documents to sign, tools to
  return; for supervisors urgent jobs with nobody and requests to decide), four
  site numbers that open the matching jobs, and shortcuts on phones.
  `lib/screens/home_screen.dart`
- **Jobs** has one filter row (All active, Mine, Needs someone, Urgent, Overdue,
  Waiting, Done) and groups active jobs as Needs someone / In hand / Waiting.
  `JobFilter` in `lib/jobs/job_rules.dart` changed to these values;
  `openJobs(context, ref, filter)` opens the tab on a filter.
  `lib/screens/jobs_screen.dart` replaces `board_screen.dart`.
- **Menu** is a tile grid (`lib/ui/tiles.dart`: `TileGrid`, `ShortcutTile`).
- Every pushed screen has `AppBackButton` (`lib/widgets/app_back_button.dart`):
  it goes back, or to Home when opened from a link or a notification.
- Job history speaks plainly ("changed the equipment and the lock-out rule") and
  hides the system's own reminder stamps.

### Job Cards Version 2 in the layout
- Reached from the **Job cards** tile on Menu and Home and the desktop menu
  link (people with `jc.view` or `req.submit`).
- Its back link reads **Back to main app** and goes to `/home`.
- The acceptance test uses `/jobs`, `/menu` and `/home`.
- It uses the main app's liquid-glass look: the mesh wallpaper, a floating glass
  menu beside a glass window (floating tab bar on phones), glass panels and KPI
  cards, and the same burgundy, dark rose and blue.

### Also landed today
- **Group chat** (`0011_chat.sql`, `lib/chat/`): department and site groups,
  direct chats, photos, replies, reactions, `#` tags for jobs, equipment and
  tools, "make a job from this message", one push per chat until it is opened.
  Chat pushes use notification type `chat` and are left out of the
  notifications list.
- **Daily report** screen with photos, approval, PDF and week/month totals
  (`lib/reports/`).
- `ReportUpdateForm` and `RequestForm` are public so the ➕ sheet can open them.
