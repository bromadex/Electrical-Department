# Offline test plan

How to check that work done without signal is kept and sent. Run it on an
Android phone before each release (issue #17). Airplane mode is "no signal";
"back online" means turning it off again.

## How the app behaves

- Changes made offline wait in the phone's outbox and send oldest first,
  files before the changes that use them. Settings → *Waiting to send*
  (`/outbox`) lists them.
- No signal never counts as a failure: the app keeps the change and tries
  again after 30 seconds, then 1, 2, 4… up to 10 minutes, and straight away
  when the app comes back to the foreground or someone taps *Send now*.
- Only the server refusing a change (for example a job card closed by
  someone else meanwhile) marks it *not saved*; it then shows in the banner
  and on *Waiting to send* with **Try again** and **Discard**.
- Up to 300 MB of files can wait on a phone.

## Steps

For each row: turn airplane mode on, do the action, check it shows as
waiting, close the app completely, reopen it (still offline), turn airplane
mode off, and check it reaches the server (on another device or the web).

| Area | Action | Expected offline | Expected back online |
|---|---|---|---|
| Job cards | Add a note | Note shows with a clock | Sent; others see it |
| Job cards | Add a work-log entry with a photo | Photo shows from the phone | Photo uploads first, then the entry |
| Chat | Send a message and a photo | Message shows pending | Sent in order |
| Checklists | Complete a checklist | Saved | Submitted; a failed item raises a job card |
| Daily report | Add my update | Saved | On the day's report |
| Tools | Issue tools on a form with signatures | Tools show as out | Form TI- created, signatures uploaded |
| Tools | Take tools back | Tools show in store | Form updated |
| Tools | Upload a calibration certificate | Due date updated | Certificate listed |
| Inventory | Receive, issue, take back, adjust | Change queued | Stock and history updated |
| Inventory | Count stock | Count queued | Corrections made |
| Inventory | Open Inventory with no signal | Saved list with its date | Live list |
| Materials | Request materials | Queued | MR- created, supervisor notified |
| Projects | Create or edit a project | Queued | P- created |
| Roster | Save or publish a week | Queued | Published; people notified |
| Documents | Upload files | Files waiting | Documents created |
| Reminders | Set a reminder | Shows as waiting | Reminder fires at its time |

## Conflict cases

| Case | How | Expected |
|---|---|---|
| Job card closed meanwhile | Phone A offline adds a note; phone B closes the job card; A goes online | The note is refused, shows *not saved* with the reason; Discard removes it |
| Stock gone meanwhile | Phone A offline issues the last 5 m; phone B issues them first | A's issue is refused ("Only 0 m in stock") |
| Same change twice | Send now twice quickly | Saved once (each change carries its own id) |
| Long time offline | Leave the phone offline for an hour with changes waiting | Nothing becomes *not saved*; everything sends when back |
| Old app with given-up changes | Changes that an older version gave up for lack of signal | They come back into the queue on start |
