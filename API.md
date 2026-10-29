# Bravura Electrical - API.md

App <-> Supabase contract · v0.1 foundation

The contract between the Flutter app (Android + web) and Supabase. **Every**
table, view, function, bucket and realtime channel the app uses is listed here.
Change it in the same pull request as the migration or screen that needs it.
Version: v0.1 (foundation, week 1).

## 1. Conventions

| Topic | Rule |
| --- | --- |
| Time zone | All "today" logic uses `Africa/Harare`. Timestamps stored as `timestamptz` (UTC). |
| IDs | `uuid` primary keys (`gen_random_uuid()`). |
| Record codes | Human codes per site, never reused: `J-0001` job, `T-` tool, `S-` SOP/document, `M-` meeting, `R-` daily report, `MR-` material request, `I-` store item, `PO-` purchase, `P-` project. Made by `next_code(site, prefix)` inside the insert function, never by the app. |
| Links | Text form `<kind>:<uuid>`, e.g. `job:7f3c…`. Used in notifications, chat cards, activity. App route: `/jobs/<code>` on web. |
| Archive, never delete | Every table has `is_archived boolean default false`. No DELETE policies. "Delete" in the app = archive. |
| Audit | `activity` rows are written by database triggers only. |
| Permissions | Checked by code with `_can(code, site)` in RLS and functions; the app hides UI with `can('code')`. Never check role names. |
| Writes | Simple edits may go straight to tables (RLS-checked). Anything with rules (codes, status changes, stock, approvals) goes through a function `fn_<verb>(...)`. |
| Offline retries | Every create function takes `p_client_ref uuid`; a repeat call with the same ref returns the first result (no duplicates). |
| Errors | Functions raise `'CODE: human message'`, e.g. `'NOT_ALLOWED: You cannot assign jobs'`. App shows the message, switches on CODE. |
| Files | Private buckets, signed URLs (60 min). Path = `<site_id>/<kind>/<record_id>/<file>`. |
| Migrations | `/supabase/migrations/NNNN_name.sql`, never edited after applied, each ends with `INSERT INTO schema_migrations (filename) VALUES ('NNNN_name.sql') ON CONFLICT DO NOTHING;` |
| Tests | Each migration has `/supabase/tests/NNNN_name_test.sql`, run by CI against a throwaway database. |
| Secrets | App gets only `SUPABASE_URL` + `SUPABASE_ANON_KEY` via `--dart-define`. Service role key only in edge functions. Nothing secret is committed. |

## 2. Foundation tables (migration 0001)

### sites

| column | type | notes |
| --- | --- | --- |
| id | uuid | pk |
| code | text | unique: `KAM`, `SEL`, `MAN`, `HRE` |
| name | text | Kamativi, Selous, Manhizi, Harare |
| is_archived | bool | |

Read: any active signed-in user. Write: `admin.sites` (insert needs it at all sites).

### areas

| column | type | notes |
| --- | --- | --- |
| id | uuid | pk |
| site_id | uuid | fk sites |
| name | text | e.g. "Plant – MCC room", "Camp – Block C"; unique per site |
| is_archived | bool | |

Read: any active signed-in user. Write: `admin.sites` at that site.

### profiles

| column | type | notes |
| --- | --- | --- |
| id | uuid | = auth.users.id (made by trigger on sign-up, `full_name`/`phone` from sign-up metadata) |
| full_name | text | |
| phone | text | |
| home_site_id | uuid | fk sites |
| avatar_url | text | storage path |
| active | bool | inactive users cannot sign in to data (RLS) |

Read: any active signed-in user. Write: self (name, phone, avatar, home site)
or `admin.users`. Only `admin.users` (all sites) may change `active` or
`is_archived`.

### roles, permissions, role_permissions, user_roles

- `roles(id, name)` — Technician, Storekeeper, Supervisor, Admin.
- `permissions(code pk, description)` — see list below.
- `role_permissions(role_id, permission_code)`.
- `user_roles(user_id, role_id, site_id null = all sites)`; revoking a role = archiving the row.

Read: self (own roles) and `admin.users`. Write: `admin.users` (all sites).

Permission codes (v0.1):
`jobs.view`, `jobs.create`, `jobs.assign`, `jobs.close`, `chat.use`,
`chat.manage`, `tools.view`, `tools.issue`, `docs.view`, `docs.manage`,
`checklists.manage`, `reports.approve`, `store.view`, `store.issue`,
`store.receive`, `store.adjust`, `mr.create`, `mr.approve`, `po.manage`,
`projects.manage`, `meetings.manage`, `stats.view`, `admin.users`, `admin.sites`.

Default role grants (seeded in 0001; change with a new migration):

| role | permissions |
| --- | --- |
| Technician | jobs.view, jobs.create, jobs.close, chat.use, tools.view, docs.view, store.view, mr.create |
| Storekeeper | jobs.view, chat.use, tools.view, tools.issue, docs.view, store.view, store.issue, store.receive, store.adjust, mr.create, po.manage |
| Supervisor | jobs.view, jobs.create, jobs.assign, jobs.close, chat.use, chat.manage, tools.view, tools.issue, docs.view, docs.manage, checklists.manage, reports.approve, store.view, mr.create, mr.approve, projects.manage, meetings.manage, stats.view |
| Admin | all |

### activity

`id, at, user_id, table_name, record_id, action (insert|update|archive|status), details jsonb`.
For updates, `details` holds `{column: {from, to}}` for changed columns.
Logged now for: sites, areas, profiles, roles, user_roles.

Read: `stats.view` at all sites, or the record's own readers (via function, added
per feature). Write: triggers only.

### notifications

| column | type | notes |
| --- | --- | --- |
| id | uuid | |
| user_id | uuid | recipient |
| site_id | uuid | |
| type | text | assigned, mentioned, overdue, reminder, approval, low_stock, meeting, general |
| title | text | |
| body | text | |
| link | text | `job:<uuid>` etc. |
| read_at | timestamptz | null = unread |
| created_at | timestamptz | |

Read/update (`read_at` only): own rows. Insert: functions and triggers only (`fn_notify`).
Realtime: INSERT on `notifications` filtered by `user_id = auth.uid()`.

### device_tokens

`id, user_id, token unique, platform (android|web), updated_at`. Read/write: own rows.
Push edge function `push-send` (week 2, Tafara) sends FCM for every new notification.

### code_counters

`site_id, prefix, last_no` — used only by `next_code`.

### schema_migrations

`filename, applied_at` — one row per applied migration. No app access.

## 3. Foundation functions

| function | returns | who | what |
| --- | --- | --- | --- |
| `_active()` | boolean | internal (RLS) | signed-in user has an active, unarchived profile |
| `_can(p_code text, p_site uuid)` | boolean | internal (RLS) | user active and has a role granting the code at that site or all sites; `p_site` null = only all-site roles count |
| `_path_site(p_name text)` | uuid | internal (storage RLS) | site id from the first folder of an object path, or null |
| `my_permissions()` | table(code, site_id) | signed-in | the app loads this once after sign-in for `can()`; `site_id` null = all sites |
| `next_code(p_site uuid, p_prefix text)` | text | internal | `J-0001` style, per site, row-locked |
| `fn_notify(p_user, p_site, p_type, p_title, p_body, p_link)` | uuid | internal | inserts a notification |
| `fn_notify_permission(p_site, p_code, p_type, p_title, p_body, p_link)` | int | internal | notifies every active user holding a permission at a site |
| `fn_mark_read(p_ids uuid[])` | int | signed-in | marks own notifications read (null = all) |
| `fn_register_device(p_token text, p_platform text)` | void | signed-in | upsert device token |

Error codes so far: `NOT_ALLOWED`, `INVALID`.

## 4. Storage buckets

| bucket | used for | read | write |
| --- | --- | --- | --- |
| job-photos | before/after photos | `jobs.view` at the site | `jobs.create` / `jobs.close` |
| chat-files | photos, voice notes, files | conversation members | members |
| documents | SOPs, drawings, PDFs | `docs.view` | `docs.manage` |
| meeting-audio | meeting recordings (deleted after 30 days) | `meetings.manage` + attendees | attendees |

The site is the first folder of the path. `chat-files` and `meeting-audio`
policies (and the 30-day clean-up) are added with group chat (section 10) and
meetings (section 16); until then nobody can read or write them.

## 5. App side

- After sign-in: load `profiles` (self), `my_permissions()`, `sites`, `areas`; cache in drift
  (`app/lib/services/session_controller.dart`, Riverpod `sessionProvider`).
- `can(code, siteId)` on `sessionProvider` hides UI; the database still enforces with `_can`.
- Current site: the one picked in the site picker, else the home site, else the first site
  the user has a role at (`currentSiteProvider`).
- Outbox: `outbox(client_ref, action, payload jsonb, tries, last_error, created_at)`; each action maps to one function in this file.
  Network errors retry (every 30 s and on app resume); `CODE:` errors from the server stop
  after one try and are shown to the user. Outbox actions so far: `fn_mark_read`, `fn_register_device`.
- Realtime channels: `notifications:<user_id>` (week 1). Features add theirs here.

## 7. Jobs board (migration 0002)

### Tables (read-only for the app; writes go through functions)

| table | key columns | read |
| --- | --- | --- |
| `jobs` | `id`, `site_id`, `area_id`, `code` (J-0001, unique per site), `title`, `description`, `priority` (low/normal/urgent), `status` (open/taken/in_progress/waiting/done/cancelled), `waiting_reason`, `due_at`, `lat`, `lng`, `created_by`, `assignee_id`, `taken_at`, `closed_at`, `closed_by`, `close_note`, `recurrence_id`, `overdue_notified_at` | `jobs.view` at the site |
| `job_photos` | `id`, `job_id`, `kind` (before/after), `path` | job readers |
| `job_comments` | `id`, `job_id`, `author_id`, `body` | job readers |
| `job_recurrences` | `id`, `site_id`, `area_id`, `title`, `priority`, `every` (daily/weekly/monthly), `next_run`, `due_days`, `assignee_id` | `jobs.view` at the site |

### Functions

| function | who | what |
| --- | --- | --- |
| `fn_create_job(p_client_ref, p_site, p_area, p_title, p_description, p_priority, p_due_at, p_lat, p_lng)` | `jobs.create` | job id = client ref; urgent → notify `jobs.assign` |
| `fn_edit_job(p_job, p_title, p_description, p_area, p_priority, p_due_at)` | poster or `jobs.assign` | open jobs only |
| `fn_take_job(p_job)` | `jobs.close` | open → taken; `CONFLICT` if someone else took it |
| `fn_assign_job(p_job, p_user)` | `jobs.assign` | null = back to open; notifies the assignee |
| `fn_set_job_status(p_job, p_status, p_reason)` | assignee or `jobs.assign` (cancel: poster or `jobs.assign`) | in_progress, waiting (reason required), open (hand back), cancelled |
| `fn_close_job(p_job, p_note)` | assignee with `jobs.close`, or `jobs.assign` | needs a note and ≥1 after photo; notifies the poster |
| `fn_add_job_photo(p_client_ref, p_job, p_kind, p_path)` | `jobs.create` or `jobs.close` | path `<site>/job/<job>/<file>` in `job-photos` |
| `fn_comment_job(p_client_ref, p_job, p_body)` | job readers | notifies poster and assignee |
| `fn_job_assignees(p_site)` | job readers | people with `jobs.close` at the site + open job count |
| `fn_job_history(p_job)` | job readers | activity timeline |
| `fn_save_recurrence(p_client_ref, p_site, …, p_archived)` | `jobs.assign` | create/update/stop a recurring job |
| `fn_run_recurrences()` | pg_cron 04:00 UTC (06:00 Harare) | posts due recurring jobs |
| `fn_notify_overdue()` | pg_cron hourly | notifies assignee (or supervisors) once per overdue job |

Errors: `NOT_ALLOWED`, `NOT_FOUND`, `INVALID`, `CONFLICT`.

### App side
- Outbox actions: every function above except the cron and read ones.
- Photos upload first (pending uploads table), then their `fn_add_job_photo`.
- Cache: jobs at the current site (open + closed in the last 30 days) and people's names in drift.
- Realtime: `jobs:<site_id>` (jobs), `job:<job_id>` (comments, photos).
- Routes: `/board`, `/jobs/<id>`, `/jobs/recurring`. Notification link `job:<uuid>` opens `/jobs/<uuid>`.

## 8. Push notifications (migration 0003)

Every row inserted into `notifications` is also sent to the person's phones and browsers.

- Table `push_config` (one row, no client access): `endpoint` of the push-send function and a random `secret`.
- Trigger `notifications_push`: after insert on `notifications`, posts `{notification_id}` to the endpoint through pg_net with header `x-push-secret`. Does nothing while `endpoint` is null (local and test databases). A push failure never blocks the notification.
- `fn_register_device(p_token, p_platform)` (0001) and `fn_unregister_device(p_token)`: the signed-in person's own devices only. The app unregisters before sign-out.
- Service role only: `fn_push_job(p_notification, p_secret)` → `{id, type, title, body, link, tokens[]}`; `fn_push_drop_tokens(p_secret, p_tokens)` archives tokens FCM rejects.
- `fn_set_push_endpoint(p_url)`: owner only, called by CI after deploying the function.
- Edge function `push-send` (no JWT, checks the secret): sends through FCM HTTP v1 with the `FIREBASE_SERVICE_ACCOUNT` secret. Urgent types (`critical`, `overdue`, `assigned`, `reassigned`) go high priority.
- Links: `job:<id>` → `/jobs/<id>`, `chat:<id>` → `/chat/<id>`. Browser notifications open `APP_URL/#/<path>`.
- App: push stays off until `FirebaseConfig` has the project id and the platform's API key. Users switch alerts on from the Today card or More → Alerts on this device.

## 8b. Personal reminders (migration 0028)

"Remind me at 14:00 about EL-JC-2026-0142." Each person's own reminders.

- Table `reminders`: `user_id, site_id, remind_at, note (1–300), link (a record link such as jobcard:<id>, tool:<id>, doc:<id>), notified_at, is_archived`. Read your own only.
- `fn_create_reminder(p_client_ref, p_remind_at, p_note, p_link, p_site)`: any active user, for themselves; within a year; a time already passed (queued offline) goes off at the next minute. Repeats with the same `p_client_ref` return the reminder.
- `fn_cancel_reminder(p_reminder)`: your own, before it goes off.
- pg_cron `personal-reminders` every minute: `fn_send_due_reminders()` turns due reminders into a `reminder` notification (title "Reminder", body the note, link the record), so they reach the phone as a push.
- App: Menu → Reminders (`/reminders`: coming up, with ×, and what went off), ➕ New → Reminder, and "Remind me" (alarm icon) on a job card and on a tool. Quick times: in 1 or 3 hours, today 14:00, tomorrow 08:00, Monday 08:00, or any date and time. Setting and cancelling go through the outbox.

## 9. Users (migration 0004)

For system administrators only: `admin.users` at all sites (site-only admins are refused).

- `fn_admin_users()` → `id, email, full_name, phone, home_site_id, active, last_sign_in_at, created_at, roles` where `roles` is `[{role, site_id}]` (`site_id` null = all sites).
- `fn_set_user_profile(p_user, p_full_name, p_phone, p_home_site, p_active)`: name needed; you cannot switch yourself off.
- `fn_set_user_roles(p_user, p_roles jsonb)`: replaces all of a person's roles with `[{"role": "Technician", "site_id": uuid|null}]`. You cannot remove your own admin rights.
- Edge function `admin-users` (POST, caller's token): `{action: "create", email, password, full_name}` → `{id}`; `{action: "reset_password", user_id, password}` → `{ok: true}`. Errors are `{error: "CODE: message"}`. The sign-up trigger creates the profile; roles are then set with `fn_set_user_roles`.
- App: More → Admin → People (`/admin/users`). Online only.

**Settings (migration 0021).** `fn_update_my_profile(p_full_name, p_phone, p_home_site)`: your
own name, phone and home site. `fn_save_site(p_id, p_code, p_name, p_archived)` and
`fn_save_area(p_id, p_site, p_name, p_archived)` (`admin.sites`; `p_id` null adds): site codes
are 2–5 letters and unique, area names unique within a site; a new site gets its default chat.
App: Menu → Settings (`/settings`: you, this device, admin, about) and Settings → Sites and
areas (`/admin/sites`). Passwords change with Supabase Auth `updateUser`.

## 10. Assets and planned maintenance (migration 0005)

A light asset register; jobs can point at an asset, so each asset has a job history.

- Table `assets`: `site_id, area_id, tag` (upper case, unique among live assets at a site), `name, kind, make_model, serial_no, notes`, `is_archived`. Readable with `jobs.view` at the site.
- `fn_save_asset(p_client_ref, p_site, p_area, p_tag, p_name, p_kind, p_make_model, p_serial_no, p_notes, p_archived)`: supervisors (`jobs.assign`); insert or edit by id; archive to remove.
- `jobs` gains `asset_id`, `maintenance_type` (`corrective` | `preventive`, default corrective) and `isolation_required` (default false).
- `fn_create_job(..., p_asset, p_maintenance_type, p_isolation_required)` and `fn_edit_job(..., p_asset, p_maintenance_type, p_isolation_required)`: new trailing parameters with defaults, so calls from older apps still work. In `fn_edit_job` a null `p_maintenance_type` leaves the asset, type and isolation unchanged.
- `job_recurrences` gains `asset_id` and `isolation_required`; `fn_save_recurrence(..., p_asset, p_isolation_required)`. Planned maintenance = a recurring job on an asset: `fn_run_recurrences` marks those jobs `preventive`.
- App: Board → Assets (`/assets`), asset page (`/assets/<id>`) with open/done counts, planned maintenance and job history, "Job on this asset". The job form has Asset, "Isolation (lock-out) required" and "Planned maintenance"; jobs needing isolation show a lock and a LOTO warning. Assets are cached on the device with the jobs (drift schema v3).

## 11. Tools register (migration 0006)

Who holds which tool, when it is due back, and when calibration is due.

- Table `tools`: `site_id, code (T-0001), name, kind, serial_no, condition (good | needs_repair | damaged | lost), calibration_due, notes, photo_path, holder_id, issued_at, due_back, last_counted_at`. Read with `tools.view`.
- Table `tool_issues`: one row per time a tool goes out: `issued_to, issued_by, issued_at, due_back, signature_path, returned_at, returned_by, return_condition, return_note`.
- `fn_save_tool(p_client_ref, p_site, p_name, p_kind, p_serial_no, p_calibration_due, p_notes, p_condition, p_archived, p_photo_path)`: `tools.issue`; new tools get the next T- code. A tool that is out cannot be removed.
- `fn_issue_tool(p_client_ref, p_tool, p_to, p_due_back, p_signature_path)`: `tools.issue`; the person must hold `tools.view` at the site; damaged or lost tools cannot go out. Notifies the person (`tool:<id>`).
- `fn_return_tool(p_tool, p_condition, p_note)`: `tools.issue`; a note is needed unless the tool is good; supervisors hear about damaged returns.
- `fn_count_tools(p_site, p_tools uuid[])`: monthly count; sets `last_counted_at` on the tools seen.
- `fn_site_people(p_site, p_code)` → `id, full_name` of active people holding a permission at a site (pickers).
- pg_cron `tools-reminders` daily 07:15 Harare: overdue returns (holder and store, once) and calibration due within 7 days (store, once per due date).
- Storage bucket `tool-files`: `<site_id>/tool/<tool_id>/signature-<id>.png` and photos; read `tools.view`, upload `tools.issue`.
- App: Menu → Equipment & tools (`/equipment?side=tools`; `/tools` redirects there): search, In store · Out · Overdue back · Calibration due tiles and filters; `/tools/<id>` (lend with on-screen signature, take back with condition; tabs Who had it · Jobs · Details), `/tools/count`. Cached offline (drift schema v7); all writes go through the outbox.
- Since 0026 a tool is out while it has an open `tool_issues` row; `holder_id` is the app user holding it (null for someone outside the app) and `holder_name` always says who. Tools whose calibration has expired cannot be lent or issued.

## 11b. Tool issue forms and tools on job cards (migration 0026)

The paper tool issue form in the app: several tools to one person, who may work for another company and not use the app, with the project team lead, place, expected return date, each tool's condition out and back, and three signatures each way.

- Table `tool_issue_forms`: `site_id, code (TI-0001), issued_by, issued_at, recipient_id (app user or null), recipient_name, recipient_role, company, team_lead, location, job_card_id, due_back, remarks, issuer_signature, recipient_signature, lead_signature, status (out | part_returned | returned), returned_at, received_back_by, return_issuer_signature, return_recipient_signature, return_lead_signature, return_remarks`. Read with `tools.view`.
- `tool_issues` gains `form_id, qty, issue_condition`; `issued_to` is null for someone outside the app. `tools` gains `holder_name, issue_form_id`.
- `fn_issue_tools(p_client_ref, p_site, p_items, p_to, p_name, p_role, p_company, p_team_lead, p_location, p_due_back, p_remarks, p_signatures, p_job_card default null)`: `tools.issue`. `p_items` is `[{tool_id, qty, condition}]` (1–100 tools, condition good or needs_repair); `p_to` an app user with `tools.view` at the site, or null with `p_name`; `p_signatures` `{issuer, recipient, lead}` storage paths. Every tool must be in the site's register, in store, not damaged or lost, and in calibration. Gives the next TI- code; repeats with the same `p_client_ref` return the form. Notifies an app-user recipient (`toolform:<id>`). With `p_job_card`, the tools are also linked to that job card.
- `fn_return_tools(p_form, p_items, p_signatures, p_remarks)`: `tools.issue`. `p_items` is `[{tool_id, condition, note}]`; a note is needed unless good; tools already back are skipped. Part returns are allowed; the form becomes `returned` when the last tool is back. Supervisors hear about damaged or lost tools. `fn_return_tool` on one tool also updates its form.
- Overdue reminders for someone outside the app go to the store only, with the holder's name.
- **Repair job cards:** a tool taken back `damaged` or `needs_repair` (on a form or with `fn_return_tool`) gets a job card "Repair T-… name" (source `direct`, P3, minor impact, location "Tool store", reporter the store person), registered by the system on the store's behalf since storekeepers lack `jc.register`. The tool is linked to it (`job_card_tools`) and `tools.repair_job_card_id` points at it; `jc.assess` holders are notified. While that job card is open, another damaged return does not open a second one.
- **Repaired:** closing a tool's repair job card (status `closed`) sets the tool back to `good` and clears `repair_job_card_id` (trigger `job_cards_tool_repaired`, migration 0028); the store (`tools.issue`) is told "T-… is repaired and back in service". A cancelled repair job card leaves the tool as it is.
- **Calibration certificates:** table `tool_certificates (tool_id, path, file_name, issued_on, valid_until, uploaded_by, uploaded_at)`, read with `tools.view`. `fn_add_tool_certificate(p_client_ref, p_tool, p_path, p_file_name, p_issued_on, p_valid_until)`: `tools.issue`; the file is uploaded first to `tool-files` under `<site_id>/tool/<tool_id>/`; the newest valid-until becomes the tool's `calibration_due` (an older certificate never shortens it) and calibration reminders start again.
- Table `job_card_tools (job_card_id, tool_id, linked_by, linked_at)`: the tools a job needs or used. `fn_link_job_card_tool(p_job_card, p_tool, p_linked)`: the job card's team, its registrar, `jc.assign`, `jc.assess` or `tools.issue`, until the job card is closed or cancelled; the tool must be in the job card site's register. Read with `jc.view`.
- Signatures in `tool-files`: `<site_id>/form/<form_id>/<issue|return-…>-<issuer|recipient|lead>-<id>.png`.
- App: Equipment & tools → **Forms** (`/tools/forms`: Out · Returned · All, search), **New form** (`/tools/forms/new?tools=<ids>&job=<job card id>`: someone else or an app user, team lead, place, return date, tools from the register or added on the spot, quantity and condition each, remarks, three signatures), the form page `/tools/forms/<id>` (tools with condition out and back, signatures, **Take back** part or all with condition per tool and the return signatures, **PDF** laid out like the company's paper form). A job card's Assignment tab has **Tools** (add or remove, who has each, "Issue … in store on a form"); a tool's page has a **Jobs** tab (including its repair job cards) and, on Details, **Calibration certificates** (upload a PDF or photo with its dates; tap to open). **Who has what** (`/tools/holders`, the people icon on the tools side) lists everyone holding tools now, app users and people on forms with their company, overdue first. Forms are online to view; issuing and taking back work offline through the outbox.

## 12. SOPs and documents (migration 0007)

Per-site documents with versions, read-and-sign acknowledgement, and links to jobs.

- Table `documents`: `site_id, code (S-0001), title, category (sop | drawing | manual | form | other), needs_ack, current_version`. Read with `docs.view`.
- Table `document_versions`: `document_id, version, path, file_name, mime_type, size_bytes, note`. Files live in the `documents` bucket at `<site_id>/doc/<document_id>/<file>` (upload needs `docs.manage`).
- Table `document_acks`: `document_id, version, user_id, acked_at`. You read your own; supervisors read all.
- Table `job_documents`: `job_id, document_id`.
- `fn_save_document(p_client_ref, p_site, p_title, p_category, p_needs_ack, p_archived)`: `docs.manage`; new documents get the next S- code.
- `fn_add_document_version(p_client_ref, p_document, p_path, p_file_name, p_mime_type, p_size_bytes, p_note)`: `docs.manage`; the path must be in the site's folder; becomes the current version. If the document needs acknowledgement, everyone with `docs.view` is notified (`doc:<id>`).
- `fn_acknowledge_document(p_document, p_version)`: the current version only (`CONFLICT` if a newer one exists).
- `fn_document_acks(p_document)` → `user_id, full_name, acked_at` for the current version (supervisors).
- `fn_link_document(p_job, p_document, p_linked)`: the job's poster, assignee or a supervisor; same site only.
- App: More → Library → Documents & SOPs (`/documents`, filters All / To sign / categories), `/documents/<id>` (open, sign, who has signed, versions, edit or new version). Images open in the app; PDFs and drawings open in the phone's or browser's viewer through a one-hour signed link. Jobs show a Documents panel to attach SOPs. Online only for now (no offline file copies yet).

## 12b. Document folders and the library screen (migration 0029)

- Table `document_folders`: `site_id, name (2–60), created_by, is_archived`. Names are unique per site among folders that are not archived. Read with `docs.view`.
- `documents.folder_id`: the folder a document is in, or null.
- `fn_save_folder(p_client_ref, p_site, p_name, p_archived)` → the folder: `docs.manage`; creates, renames or archives. `CONFLICT` when the name is taken, `INVALID` for a name under 2 or over 60 characters. Archiving moves the folder's documents out (to no folder); nothing is deleted.
- `fn_move_documents(p_documents uuid[], p_folder)` → how many moved: `docs.manage`; all documents at one site, and the folder at that site (`INVALID` otherwise); `p_folder` null moves them out of folders.
- Both are on the outbox allow-list.
- App (`/documents`): folders with file count, size and how many to sign; a grid or list view remembered on the device (list has Updated, Added by, Size and Signed columns on wide screens); filters All / To sign / Recent (30 days) / Added by me plus the type; coloured file-type badges (PDF, DOC, XLS, PPT, DWG, IMG). Upload takes several files at once, each its own document titled from its file name, with the folder, type and signing chosen once and progress per file. Each document's ⋮ menu: open, download, share in a chat (`doc:<id>`), copy a 7-day signed link for someone without the app (supervisors), move to folder, edit or new version, archive. Supervisors see how many people signed the current version.

## 13. Checklists and daily report (migration 0008)

- `checklist_templates` (`site_id, area_id, name, description, frequency daily|weekly|monthly, assignee_id`) and `checklist_items` (`position, label, kind check|number|text, unit, min_value, max_value, photo_required`).
- `checklist_runs` (`template_id, site_id, run_date, done_by, done_at, notes, failed_count`) and `checklist_answers` (`ok, value, text_value, photo_path, comment, failed, job_id`).
- `fn_save_checklist_template(p_client_ref, p_site, p_area, p_name, p_description, p_frequency, p_assignee, p_items jsonb, p_archived)`: `checklists.manage`; items `[{id, label, kind, unit, min, max, photo_required}]` in order; items left out are archived.
- `fn_submit_checklist(p_client_ref, p_template, p_answers jsonb, p_notes)`: `jobs.close`; every item answered, photos where required; a not-OK tick or a reading outside its limits is failed and raises a job.
- `fn_site_checklists(p_site)` → each template's `due_by` (end of its period), and this period's `done_at, done_by, failed_count`.
- pg_cron 15:00 Harare: rounds whose period ends today and are not done remind the assignee (or everyone on site); 19:00: supervisors hear they were missed (`checklist:<id>`). Once per period each.
- Daily report: `daily_reports` (`site_id, report_date, code R-, summary jsonb, status open|approved, supervisor_comment`) and `report_updates` (`body, photo_paths`). `fn_build_daily_report(p_site, p_date)` (also nightly 19:10 for every site) sums up jobs opened/closed, checklists done/missed and tools; `fn_add_report_update(p_client_ref, p_site, p_date, p_body, p_photo_paths)`; `fn_approve_report(p_report, p_comment)` (`reports.approve`). Photos go to `job-photos` under `<site_id>/checklist/...` and `<site_id>/report/...`.
- App: More → Library → Checklists (`/checklists`): status per round (done, failed, due today), supervisors build templates; `/checklists/<id>` runs a round offline (templates cached on the device). The daily report screen and PDF export are next.

## 14. Safety check, escalation, audit log (migration 0009)

Adopted in a light form from Tafara's CMMS phase 2.

- `job_safety_checks` (`job_id, user_id, items, reference, checked_at`). `fn_record_safety_check(p_client_ref, p_job, p_items, p_reference)`: the assignee or a supervisor; every item in `_safety_items()` and a lock or permit number. A job with `isolation_required` cannot move to `in_progress` without a check recorded since it was taken (trigger `jobs_safety_guard`).
- `fn_escalate_jobs()` every 10 minutes: urgent jobs still open 30 minutes after posting → `jobs.assign` (once, `urgent_escalated_at`); jobs more than a day past due → `checklists.manage` (once, `overdue_escalated_at`).
- `activity` is readable by `admin.users` (all sites) as well as `stats.view`: More → Admin → Audit log (`/admin/activity`).
- Profiles without a name are named from their email (`_name_from_email`), on sign-up and once for existing accounts.
- App: Start on an isolation job opens the safety check sheet; theme toggle in the top bar, light by default.

## 15. Requests and priority targets (migration 0010)

Adopted in a light form from Tafara's PR #19, on top of the jobs board.

- Permission `req.create` (new role **Requester**, and every existing role). Record code `RQ-`.
- Table `job_requests`: `site_id, area_id, code, title, description, department, priority, status (new | accepted | declined), requested_by, decided_by, decided_at, decline_reason, job_id`. Requesters read their own; `jobs.assign` reads the site's.
- `fn_create_request(p_client_ref, p_site, p_area, p_title, p_description, p_department, p_priority)`: notifies `jobs.assign` (`request:<id>`).
- `fn_accept_request(p_request, p_priority, p_assignee)`: posts the request as a job (description names the requester and RQ- code), optionally assigns it, tells the requester. `fn_decline_request(p_request, p_reason)`: reason required, tells the requester. When the job is done the requester is told (trigger `jobs_tell_requester`).
- Table `priority_targets` (`priority, respond_minutes, close_hours`; defaults urgent 30 min / 24 h, normal 4 h / 72 h, low 24 h / 7 days). A job inserted without `due_at` gets `created_at + close_hours` (trigger `jobs_default_due`). The urgent escalation uses the urgent response time. `fn_set_priority_target(p_priority, p_respond_minutes, p_close_hours)`: `admin.users` at all sites.
- App: More → Library → Requests (`/requests`: incoming for supervisors, mine for everyone; new request form; accept as a job with priority and assignee, or decline with a reason); More → Admin → Priority targets (`/admin/targets`). "Requests to decide" appears under Needs attention.

## 16. Chat (migration 0011; pins 0018)

Groups and direct chats for people with `chat.use`. Every site has a default group and
the department has one; members are kept in sync with roles (`fn_sync_default_chats`, and
triggers on `user_roles` and new sites).

- Tables (members read, nobody writes directly): `conversations` (`kind` group | direct,
  `title`, `site_id`, `is_default`, `last_message_at`, `last_message_preview`),
  `conversation_members` (`role`, `last_read_at`, `pinned`), `messages` (`kind` text |
  photo | voice | file | record | system, `body`, `attachment_path/name/size`,
  `duration_ms`, `reply_to`, `record_link`, `mentions`), `message_reactions`.
- `fn_send_message(p_client_ref, p_conversation, p_kind, p_body, p_attachment_path,
  p_attachment_name, p_attachment_size, p_duration_ms, p_reply_to, p_record_link,
  p_mentions)`: queued offline (idempotent on `p_client_ref`). Attachments live in the
  `chat-files` bucket at `<conversation id>/<message id>/<file>` (members only). Record
  links are `jobcard:`, `asset:`, `tool:` or `doc:` + uuid. Mentioned members get a
  `mentioned` notification; everyone else one `chat` notification until they open it.
- `fn_unsend_message(p_message)`, `fn_react(p_message, p_emoji)` (again removes it),
  `fn_mark_conversation_read(p_conversation)`, `fn_open_direct(p_client_ref, p_user)`,
  `fn_create_group` / `fn_update_group` (`chat.manage`), `fn_leave_conversation`,
  `fn_pin_conversation(p_conversation, p_pinned)`.
- Reads: `fn_my_conversations()` (unread counts, `pinned`, `last_read_at`, `call_live`;
  pinned first), `fn_search_records(p_query)` for the # picker, `fn_chat_people()`.
- Realtime: `messages`, `message_reactions`, `conversation_members`, `conversations`. A
  presence channel `online` (key = user id) shows who has the app open; broadcast
  `typing` `{c, u}` shows who is typing. Neither is stored.
- App: `/chat` (two panes from 1000 px), `/chat/<id>`. Voice notes are AAC (phones) or
  Opus/WebM (browsers). The chat list and the latest 50 messages of each opened chat are
  kept on the device (`CachedJson`) for reading without signal.

## 16b. Calls (migration 0017)

Voice and video calls in any chat, on LiveKit Cloud. A chat's call is the room
`chat-<conversation id>`. `fn_start_call(p_conversation)` checks the caller is a member with
`chat.use`, records `conversation_calls` and, when no one joined in the last 30 minutes,
tells the other members ("<name> started a call", type `meeting`, link `call:<id>` →
`/chat/<id>/call`). The `livekit-token` edge function calls it with the user's sign-in and
signs a two-hour LiveKit token (HS256) with `LIVEKIT_API_SECRET`; it returns `{ url, token,
room, title }`, or 503 `UNAVAILABLE` until `LIVEKIT_URL`, `LIVEKIT_API_KEY` and
`LIVEKIT_API_SECRET` are set as Supabase secrets. Calls start with sound only; cameras are
optional.

**Pins and call history (migrations 0018–0020).** `fn_pin_conversation(p_conversation,
p_pinned)` pins a chat for the caller; `fn_my_conversations` also returns `pinned`,
`last_read_at` (for the "New messages" line) and `call_live`, pinned chats first. Each call
is a row in `calls` (`video`, `message_id`, `started_at`, `answered_at`, `ended_at`) with
`call_participants` (`joined_at`, `last_seen_at`, `left_at`); members can read both.
`fn_start_call(p_conversation, p_video default false)` joins the chat's live call or starts
one: a system message ("<name> started a call", `record_link call:<chat>`), the chat
preview, and a `meeting` notification; it returns `call_id` too, which `livekit-token`
passes on (the app sends `{ conversation_id, video }`). While in a call the app sends
`fn_call_heartbeat(p_call)` every 30 seconds and `fn_leave_call(p_call)` when it leaves. A
call is live while someone in it was seen in the last 90 seconds; the last one out ends it.
A call nobody else answered is missed and the others get "Missed call from <name>" (link
`chat:<id>`). `fn_conversation_calls(p_conversation)` lists a chat's calls with `status`
(live | missed | ended) and `in_call`. A direct call that rings 45 seconds with no answer
hangs up in the app. `conversation_calls` (0017) is no longer written.

## 16c. Meetings (migration 0022)

Meetings live inside group chats. Someone with `meetings.manage` schedules one from a chat
(⋮ → Schedule a meeting); everyone in the chat is invited and joins with the chat's call.

- Table `meetings` (members of the chat read it): `code` (M-), `title`, `agenda`,
  `starts_at`, `duration_min`, `chair_id`, `status` (scheduled | cancelled),
  `recording_status` (none | recording | processing | ready | failed), `egress_id`,
  `audio_path`, `transcript`, `minutes` (`{summary, decisions[], actions[{text, owner_id,
  owner_name, due}]}`), `minutes_status` (none | draft | approved).
- `fn_create_meeting(p_client_ref, p_conversation, p_site, p_title, p_agenda, p_starts_at,
  p_duration_min)`: group chats only; posts the meeting card (system message,
  `record_link meeting:<id>`) and tells the chat. `fn_update_meeting(p_meeting, p_title,
  p_agenda, p_starts_at, p_duration_min, p_cancel)`: chair or `meetings.manage`.
- `fn_meeting_reminders()`: pg_cron every 5 minutes; one "Starting soon" notification 15
  minutes before. `fn_meeting_attendance(p_meeting)`: who joined the chat's call from 30
  minutes before until 90 minutes after the planned end.
- Chair only: `fn_save_minutes(p_meeting, p_transcript, p_minutes)` (a draft; approved minutes
  are final), `fn_approve_minutes(p_meeting)` (posts "Minutes: …" to the chat and tells each
  action owner). Links `meeting:<id>` open `/meetings/<id>`.
- **Live captions (migration 0023, instead of recordings).** While a meeting is on (15 minutes
  before until 2 hours after the planned end), each person in the chat's call sends their own
  voice in 15-second pieces to the edge function `meeting-caption` `{meeting_id, spoken_at,
  mime, audio (base64)}`. It is transcribed with Groq Whisper (free plan;
  `whisper-large-v3-turbo`, else `whisper-large-v3`) and saved with `fn_add_caption(p_meeting,
  p_spoken_at, p_body)` into `meeting_captions` (members read; realtime). No audio is kept.
  The browser listens to the microphone itself; the Android app takes the call's own
  microphone sound (flutter_webrtc audio input channel). Muted pieces are dropped; pieces
  wait and retry on poor signal; the screen stays awake during the call.
  `fn_meeting_transcript(p_meeting)` gives the whole text with times and names.
- Edge function `meeting-minutes` `{meeting_id, notes?}` drafts the minutes from the typed
  notes, else the transcript, as JSON; owners are matched to the chat's members by name.
  It uses Groq's free chat models (picks `openai/gpt-oss-120b`, else
  `llama-3.3-70b-versatile`, …; `MINUTES_MODEL` overrides), or Claude `claude-opus-5-5` when
  `ANTHROPIC_API_KEY` is set.
- Secrets: `TRANSCRIBE_API_KEY` (a Groq key; `GROQ_API_KEY` also works) for both. Optional:
  `TRANSCRIBE_URL`, `TRANSCRIBE_MODEL`, `GROQ_BASE_URL`. Without a key both answer 503
  `UNAVAILABLE` and minutes can still be written by hand. Both accept `{check: true}` to report
  whether the key works (no secret shown).
- The recording columns of 0022 (`recording_status`, `egress_id`, `audio_path`) are unused;
  the `meeting-record` function is gone. Not yet: attendees from outside the chat.

## 17. Job Cards Version 2 (migrations 0012–0014)

The job card & maintenance management system from Tafara's PR #19 and its phase 2.
**Job cards are the app's job system.** The Jobs tab is the job cards list (`/jobs`); a
job card opens at `/jobs/<number or id>`, My jobs at `/jobs/mine`, a new job card at
`/jobs/new`; requests at `/requests` (incoming) and `/my-requests` (mine, new at
`/my-requests/new`); statistics at `/job-stats`; settings at `/admin/job-settings`; the
activity log at `/admin/audit`. Old `/v2/...` addresses redirect. Home's "Needs you" and
the four numbers come from `fn_dashboard`; the ➕ New sheet raises a job card (or a
request for people without `jc.register`). The retired jobs board's pages stay at
`/old-jobs/<id>` for old links. (Section 16 is left for chat, migration 0011.)

**0015 (job cards everywhere).** A failed checklist item raises a job card
(`checklist_answers.job_card_id`); planned maintenance (`job_recurrences`) raises preventive
job cards, registered as the person who set the plan up (if they no longer can, the site's
`jc.register` holders are told); the daily report counts job cards; chat `#` tags find job
cards (`jobcard:<id>`). The jobs board's tables keep their data; nothing new is written there.

**0016 (documents on job cards).** `job_card_documents` links SOPs and drawings to job
cards; `fn_link_job_card_document(p_job_card, p_document, p_linked)` (registrar, the team,
or `jc.assign`/`jc.assess` holders; not on closed or cancelled job cards; same site). The
job card's Files tab lists them with Attach and Detach (queued offline).

**Shared with Version 1.** Profiles, sites, areas and roles (no renames); notifications
and push (`notifications_push` sends v2 notifications too); the `activity` log (every v2
table is audited); the asset register: `assets` gains optional columns (category,
location, manufacturer, model, ratings, operational_status, criticality, department,
warranty) and `asset_no`, generated as `upper(tag)`. Assets are still added in Version 1's
register. `profiles.department_id` is new.

**Permissions** (new codes): `jc.view`, `jc.register`, `jc.assess`, `jc.assign`,
`jc.execute`, `jc.review`, `jc.cancel`, `jc.reopen`, `jc.escalate`, `jc.self_approve` (no
one by default), `req.submit`, `req.triage`, `assets.view`, `assets.manage`,
`settings.manage`, `audit.view`, `reports.view`.

| role | v2 codes |
| --- | --- |
| Technician | jc.view, jc.register, jc.execute, req.submit, req.triage, assets.view |
| Supervisor | all jc.* except self_approve, req.submit, req.triage, assets.*, reports.view |
| Admin | every code except jc.self_approve |
| Department Manager (new) | jc.view, jc.reopen, jc.escalate, req.submit, assets.view, reports.view, stats.view, audit.view |
| Requester | req.submit (beside Version 1's req.create) |
| Storekeeper | jc.view, req.submit, assets.view |

**Tables** (read-only for the app; every write goes through a function):

| area | tables |
| --- | --- |
| settings | `system_settings` (numbering `EL-JC`/`EL-SR`, time zone, response end point, at-risk %, hold alert hours, handover note rule, `safety_before_start` off | when_required | always), `priority_levels` (P1–P4 targets), `departments`, `job_categories`, `asset_categories`, `escalation_contacts`, `escalation_rules`, `safety_checklist_items`, `doc_sequences`, `job_status_transitions` |
| requests | `service_requests` (`EL-SR-YYYY-NNNN`), `request_attachments` |
| job cards | `job_cards` (`EL-JC-YYYY-NNNN`, every stage), `job_assignments`, `job_status_history`, `job_card_comments`, `job_attachments`, `job_closures` (with frozen metrics) |
| work | `job_work_sessions`, `job_waits`, `job_time_corrections`, `job_work_records`, `job_safety_records`, `job_submissions`, `job_reviews`, `job_escalations` |

`v_job_cards` (security_invoker) adds names, SLA state, effective deadline (waits excluded
from the SLA move it), elapsed/remaining/overdue minutes and who is working now.

**Functions** (parameters in the migrations; errors are `CODE: message`):
- Requests: `fn_submit_request`, `fn_triage_request`, `fn_resubmit_request`,
  `fn_withdraw_request`, `fn_add_request_attachment`, `fn_request_tracking`.
- Job cards: `fn_register_job_card`, `fn_assess_job_card`, `fn_return_for_clarification`,
  `fn_provide_clarification`, `fn_assign_job_card`, `fn_unassign_job_card`,
  `fn_accept_job_card`, `fn_start_work`, `fn_pause_work`, `fn_set_job_card_status`,
  `fn_escalate_job_card`, `fn_add_work_record`, `fn_record_safety`, `fn_submit_for_review`
  (`fn_submit_job_card`), `fn_verify_job_card` (approve, approve with a follow-up job card,
  return, ask a question; `fn_review_job_card`), `fn_answer_review`,
  `fn_correct_work_session`, `fn_add_work_session`, `fn_set_wait_sla`, `fn_cancel_job_card`,
  `fn_reopen_job_card`, `fn_comment_job_card`, `fn_add_job_attachment`.
- Reads: `fn_job_card_timeline`, `fn_job_work`, `fn_workload`, `fn_jc_site_people`,
  `fn_dashboard`, `fn_search`, `fn_audit_log`.
- Settings (`settings.manage`): `fn_save_settings`, `fn_save_priority`, `fn_save_department`,
  `fn_save_job_category`, `fn_save_asset_category`, `fn_save_escalation_contact`,
  `fn_save_escalation_rule`, `fn_save_safety_item`, `fn_save_safety_policy`.

**Other.** pg_cron `jobcards-escalations` runs `fn_run_escalations()` every 10 minutes (nine
seeded rules, each notice once per job, rule and deadline). Bucket `job-files`
(`<site_id>/jobcard/<job_id>/<file>`, `<site_id>/request/<request_id>/<file>`). Links
`jobcard:<id>` → `/v2/job-cards/<id>` and `servicerequest:<id>` → `/v2/requests/<id>`
(Version 1 keeps `request:`). Realtime on `job_cards`, `job_assignments`, `job_card_comments`,
`job_attachments`, `service_requests` and the work tables.

## 6. Feature sections (filled in as features are built)

- 7. Jobs board — Clement, phase 1 (done, see above)
- 8. Push notifications — phase 1 (done, see above)
- 9. Daily checklists + daily report — Clement, phase 2
- 10. Group chat — Tafara, phase 2
- 11. Tools — phase 3 (done, see above)
- 12. SOPs & documents — phase 3 (done, see above)
- 13. Electrical store — Clement, phase 4
- 14. Material requests, purchases, BOQ — Tafara, phase 4
- 15. Projects, calendar, roster — Clement, phase 5
- 16. Meetings, transcription, minutes — Tafara, phase 5

## Changelog

- v0.12 — Job Cards Version 2 beside the jobs board (migrations 0012–0014).
- v0.10 — requests from other departments, priority targets.
- v0.9 — safety check before isolated work, escalation, audit log, names from email.
- v0.8 — checklists and daily report backend.
- v0.7 — SOPs and documents (documents, versions, acknowledgements, job links).
- v0.6 — tools register (tools, tool_issues, tool-files bucket, reminders).
- v0.5 — asset register, planned maintenance, isolation flag (assets, jobs.asset_id/maintenance_type/isolation_required).
- v0.4 — user management (fn_admin_users, fn_set_user_profile, fn_set_user_roles, admin-users function).
- v0.3 — push notifications (push_config, notifications_push trigger, push-send function).

- v0.2 — jobs board (jobs, photos, comments, recurrences, overdue alerts).

- v0.1 — foundation (sites, areas, profiles, roles/permissions, activity, notifications, device tokens, codes, buckets).
