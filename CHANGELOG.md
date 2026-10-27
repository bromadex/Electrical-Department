# What's new

## 27 October 2026, afternoon (not on `main` yet)

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
