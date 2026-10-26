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

## 6. Feature sections (filled in as features are built)

- 7. Jobs board — Clement, phase 1 (done, see above)
- 8. Push notifications — phase 1 (done, see above)
- 9. Daily checklists + daily report — Clement, phase 2
- 10. Group chat — Tafara, phase 2
- 11. Tools — Clement, phase 3
- 12. SOPs & documents — Tafara, phase 3
- 13. Electrical store — Clement, phase 4
- 14. Material requests, purchases, BOQ — Tafara, phase 4
- 15. Projects, calendar, roster — Clement, phase 5
- 16. Meetings, transcription, minutes — Tafara, phase 5

## Changelog

- v0.3 — push notifications (push_config, notifications_push trigger, push-send function).

- v0.2 — jobs board (jobs, photos, comments, recurrences, overdue alerts).

- v0.1 — foundation (sites, areas, profiles, roles/permissions, activity, notifications, device tokens, codes, buckets).
