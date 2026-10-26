# Bravura Electrical - API.md

App <-> Supabase contract · v0.4 work execution, verification and audit

The contract between the Flutter app (Android + web) and Supabase. **Every**
table, view, function, bucket and realtime channel the app uses is listed here.
Change it in the same pull request as the migration or screen that needs it.
Version: v0.4 (CMMS phase 2: work sessions and time tracking, safety checks,
engineering verification, escalation rules, audit log).

## 1. Conventions

| Topic | Rule |
| --- | --- |
| Time zone | All "today" logic uses the site time zone in `system_settings.timezone` (default `Africa/Harare`). Timestamps stored as `timestamptz` (UTC); every lifecycle time is set by the server, never by the device. |
| IDs | `uuid` primary keys (`gen_random_uuid()`). |
| Record codes | Job cards and requests: `EL-JC-2026-0001`, `EL-SR-2026-0001` (prefix, digits and yearly reset in `system_settings`), from `_next_doc_no(kind, at)`, row-locked, never reused. Other records keep per-site codes from `next_code(site, prefix)` (`T-` tool, `S-` SOP, `M-` meeting, `MR-` material request …). Always made inside the insert function, never by the app. |
| Links | Text form `<kind>:<uuid>`: `jobcard:<id>` → `/job-cards/<id>`, `request:<id>` → `/requests/<id>`. Used in notifications and activity. `/job-cards/<number>` also works. |
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

- `roles(id, name)` — Electrician, Electrical Engineer, Department Manager,
  Requester, Storekeeper, System Administrator (renamed in 0004 from
  Technician, Supervisor and Admin; existing assignments carried over).
- `permissions(code pk, description)` — see list below.
- `role_permissions(role_id, permission_code)`.
- `user_roles(user_id, role_id, site_id null = all sites)`; revoking a role = archiving the row.

Read: self (own roles) and `admin.users`. Write: `admin.users` (all sites).

Permission codes:
- Job cards and requests (0004): `jc.view`, `jc.register`, `jc.assess`,
  `jc.assign`, `jc.execute`, `jc.review`, `jc.cancel`, `jc.reopen`,
  `jc.escalate`, `jc.self_approve`, `req.submit`, `req.triage`.
- Assets, settings and oversight (0004): `assets.view`, `assets.manage`,
  `settings.manage`, `audit.view`, `reports.view`.
- From 0001, kept for later modules: `chat.use`, `chat.manage`, `tools.view`,
  `tools.issue`, `docs.view`, `docs.manage`, `checklists.manage`,
  `reports.approve`, `store.view`, `store.issue`, `store.receive`,
  `store.adjust`, `mr.create`, `mr.approve`, `po.manage`, `projects.manage`,
  `meetings.manage`, `stats.view`, `admin.users`, `admin.sites`.
- `jobs.*` were archived in 0003 with the old jobs board.

Job card grants (seeded in 0004; change with a new migration). The 0001 grants
for chat, tools, store and so on are unchanged:

| role | job card permissions |
| --- | --- |
| Electrician | jc.view, jc.register, jc.execute, req.submit, req.triage, assets.view |
| Electrical Engineer | jc.view, jc.register, jc.assess, jc.assign, jc.execute, jc.review, jc.cancel, jc.reopen, jc.escalate, req.submit, req.triage, assets.view, assets.manage, reports.view |
| Department Manager | jc.view, jc.reopen, jc.escalate, req.submit, assets.view, reports.view, stats.view, audit.view |
| Requester | req.submit |
| Storekeeper | jc.view, req.submit, assets.view |
| System Administrator | everything except `jc.self_approve` (approving your own work stays an explicit, audited grant) |

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
| type | text | assigned, mentioned, overdue, reminder, approval, low_stock, meeting, general, and from 0004: registered, critical, reassigned, on_hold, review, returned, closed, request |
| title | text | |
| body | text | |
| link | text | `jobcard:<uuid>`, `request:<uuid>` |
| read_at | timestamptz | null = unread |
| created_at | timestamptz | |

Read/update (`read_at` only): own rows. Insert: functions and triggers only (`fn_notify`).
Realtime: INSERT on `notifications` filtered by `user_id = auth.uid()`.

### device_tokens

`id, user_id, token unique, platform (android|web), updated_at`. Read/write: own rows.
The `push-send` edge function sends every new notification to these devices (section 8).

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
| job-files | job card and request photos, test sheets, documents (25 MB, images, PDF, Office, text) | `jc.view` at the site; request files also `req.triage` and the requester | see section 7.6 |
| job-photos | photos from the retired jobs board (read-only) | `jc.view` at the site | nobody |
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
  after one try and are shown to the user. Outbox actions: `fn_mark_read`, `fn_register_device`.
  Job card status and time actions are never queued offline, so server times stay true.
- Realtime channels: `notifications:<user_id>`; job card lists and the dashboard refresh on
  changes to `job_cards`, `job_assignments`, `job_comments`, `job_attachments` and
  `service_requests` (all in the `supabase_realtime` publication, filtered by RLS).
- Reference data loaded once after sign-in (`referenceDataProvider`): `departments`,
  `job_categories`, `asset_categories`, `priority_levels`, `system_settings`,
  `job_status_transitions`.
- My Assigned Jobs is cached in drift (`local_job_cards`) for poor signal.

## 6. Feature sections

- 7. Job card & maintenance management — phase 1
- 8. Push notifications
- 9. Work execution, time tracking, verification, escalation and audit — phase 2
- Later phases add: SOP library, asset register details, preventive maintenance,
  calendar (phase 3); materials, email notifications, reports and analytics (phase 4);
  QR codes, offline work, monitoring-ready measurements (phase 5).

## 7. Job card & maintenance management (0003–0006)

0003 retired the jobs board: `jobs`, `job_photos`, `job_comments` and `job_recurrences`
are now `legacy_*` (kept, no app writes) and their functions and cron jobs are gone.
0006 copied every legacy job into a job card (new number, old code in `legacy_code`;
open → registered, taken → assigned, waiting → on_hold, done → closed; urgent → P2,
normal → P3, low → P4) and runs due legacy recurring templates daily at 04:00 until
phase 3 replaces them with PM plans.

All tables below are read-only for the app (RLS select); every write goes through a function.

### 7.1 Configuration and reference tables

| table | what | read | write |
| --- | --- | --- | --- |
| `system_settings` | one row: timezone, jobcard_prefix, request_prefix, number_digits, number_reset_yearly, response_ends_at (acknowledged \| assessed \| assigned), at_risk_percent, hold_alert_hours, handover_note_required, company_name, department_name, logo_path | active users | `fn_save_settings` |
| `priority_levels` | P1–P4: name, description, response_minutes, completion_minutes, targets_confirmed (false = seeded default, shown as "Default — confirm") | active users | `fn_save_priority` |
| `departments` | code, name, is_electrical | active users | `fn_save_department` |
| `job_categories`, `asset_categories` | name, sort_order | active users | `fn_save_job_category`, `fn_save_asset_category` |
| `escalation_contacts` | site (null = all), priority_code, user | `settings.manage` | `fn_save_escalation_contact` |
| `job_status_transitions` | allowed (from_status, to_status) pairs | active users | migrations only |
| `doc_sequences` | (kind, year, last_no) for record numbers | none | `_next_doc_no` |

`profiles.department_id` links a person to a department.

### 7.2 Assets

`assets`: asset_no (unique, upper case), name, category_id, site_id, area_id, location,
manufacturer, model, serial_no, electrical_rating, voltage_v, current_a, power_kw,
installed_on, operational_status (in_service \| out_of_service \| standby \|
decommissioned), criticality (high \| medium \| low), department_id,
maintenance_frequency, warranty_expires_on, warranty_notes, notes.
Read: `assets.view`, `jc.view` or `req.submit` at the site. Write: `fn_save_asset`
(`assets.manage`).

### 7.3 Service requests

`service_requests`: request_no, requested_by, site/area/location, department_id,
reporter_name, contact, asset_id or equipment text, title, description,
operational_impact (none \| minor \| reduced_output \| production_stopped \|
safety_hazard), status (submitted \| returned \| registered \| rejected \| withdrawn),
status_reason, job_card_id. `request_attachments` hold its files.
A request never becomes a work order by itself: someone with `req.triage` registers
a job card from it. Read: the requester, or `req.triage` / `jc.view` at the site.

### 7.4 Job cards

`job_cards` holds every stage: receipt (number, source, received_at, reporter, department,
site/area/location, asset or equipment details, category, title, description, impact,
priority, requested completion), assessment (valid, maintenance_type, severity,
safety_risk, equipment_state, competencies, personnel, resources, isolation / permit /
LOTO required, expected duration, target_response_at, target_completion_at, notes),
plan (responsible_id, planned start, estimated hours, materials, tools, safety
precautions, procedure), critical flag and reason, closure fields, status_reason, and
every lifecycle timestamp. Related tables:

| table | what |
| --- | --- |
| `job_assignments` | responsible and supporting people; ended_at, end_reason, handover_note; one current responsible per job |
| `job_status_history` | from, to, reason, user, server time; written by trigger on every status change |
| `job_comments` | kind (comment \| finding \| instruction \| handover \| assistance), visibility (internal \| requester), mentions; append-only |
| `job_attachments` | kind (photo_before \| photo_after \| photo \| test_sheet \| document \| other), bucket, path, caption |
| `job_closures` | one row per approved closure (so reopening never loses one): closed_at, completion summary, findings, corrective action, equipment state after, performed_by, verified_by, self_approved, legacy |

Job cards and their records are readable with `jc.view` at the site. Requesters never
read these tables; they follow their request through `fn_request_tracking`.

**Statuses** (`job_status_transitions`): registered → awaiting_clarification |
awaiting_assignment → assigned → accepted → in_progress → awaiting_review → closed.
Work can stop and resume through on_hold, awaiting_materials, awaiting_isolation,
awaiting_specialist and awaiting_production_clearance. A rejected review goes back to
accepted; closed → reopened → assigned or accepted; any open status → cancelled.
Holds, cancel, reopen, return for clarification and rejection need a reason.
P1, critical severity and extreme safety risk make a job critical automatically.

**`v_job_cards`** (`security_invoker`, so the job card RLS applies) adds names
(site, area, reporter, department, category, responsible, assigned by, registered by),
`equipment_display`, `asset_no_display`, `priority_rank`, and computed fields:
is_new, is_awaiting_assignment, is_active, is_working, is_waiting, is_critical_open,
is_overdue, is_awaiting_review; response_minutes, elapsed_minutes, remaining_minutes,
overdue_minutes, response_target_met, status_changed_at, and `sla_state`
(on_time \| at_risk \| overdue \| completed_on_time \| completed_late \| no_target \|
cancelled). Overdue comes only from the deadline, never from priority.

### 7.5 Functions

Requests:

| function | who | what |
| --- | --- | --- |
| `fn_submit_request(p_client_ref, p_site, p_area, p_location, p_department, p_reporter_name, p_contact, p_asset, p_equipment, p_title, p_description, p_impact)` | `req.submit` at the site | new request; notifies `req.triage` holders |
| `fn_triage_request(p_request, p_action 'return'\|'reject', p_reason)` | `req.triage` | returns for more detail or rejects, with a reason |
| `fn_resubmit_request(p_request, p_title, p_description, p_impact, p_note)` | the requester | after a return |
| `fn_withdraw_request(p_request, p_reason)` | the requester | while not registered |
| `fn_add_request_attachment(p_client_ref, p_request, p_path, p_file_name, p_content_type, p_size)` | requester or `req.triage` | records an uploaded file |
| `fn_request_tracking(p_request)` | requester, `req.triage` or `jc.view` | jsonb: `request`, `site_name`, `area_name`, `department_name`, `attachments`, `job` (number, status, priority, times, responsible) and `updates` (requester-visible comments) |

Job cards (all take `p_job uuid` first unless shown):

| function | who | what |
| --- | --- | --- |
| `fn_register_job_card(p_client_ref, p_request, p_site, p_area, p_location, p_received_at, p_reporter_name, p_department, p_asset, p_equipment_name, p_equipment_asset_no, p_equipment_location, p_category, p_title, p_description, p_impact, p_priority, p_requested_completion_at)` | `jc.register` | numbered job card, directly or from a request; needs description, source and a location |
| `fn_assess_job_card(p_job, p_valid, p_maintenance_type, p_severity, p_safety_risk, p_safety_notes, p_equipment_state, p_competencies, p_personnel, p_resources, p_isolation, p_permit, p_loto, p_duration_hours, p_priority, p_target_response_at, p_target_completion_at, p_notes)` | `jc.assess` | invalid → cancelled; valid → awaiting assignment |
| `fn_return_for_clarification(p_job, p_reason)`, `fn_provide_clarification(p_job, p_note)` | `jc.assess`; the registrar, `jc.register` or the requester | the answer is saved as a comment and the job goes back to registered |
| `fn_assign_job_card(p_job, p_responsible, p_support uuid[], p_planned_start_at, p_target_completion_at, p_estimated_hours, p_materials, p_tools, p_safety, p_procedure, p_handover_note, p_reason)` | `jc.assign` | assign or reassign (with a reason); a handover note is needed when reassigning started work and `handover_note_required` is on |
| `fn_unassign_job_card(p_job, p_reason)` | `jc.assign` | back to awaiting assignment |
| `fn_accept_job_card(p_job)` | the responsible person | ends response time when `response_ends_at = acknowledged` |
| `fn_set_job_card_status(p_job, p_status, p_reason)` | the assigned team (`jc.execute`) or `jc.assign` | in_progress or a hold; the responsible person starting work also accepts |
| `fn_escalate_job_card(p_job, p_critical, p_reason)` | `jc.escalate` | critical on/off; alerts engineers and escalation contacts |
| `fn_submit_job_card(p_job, p_summary, p_findings, p_corrective_action, p_equipment_state_after, p_checks_confirmed)` | responsible (`jc.execute`) or `jc.assign` | → awaiting_review |
| `fn_review_job_card(p_job, p_decision 'approve'\|'reject', p_notes)` | `jc.review`, not the performer unless `jc.self_approve` | approve → closed; reject → accepted |
| `fn_cancel_job_card(p_job, p_reason)`, `fn_reopen_job_card(p_job, p_reason)` | `jc.cancel`, `jc.reopen` | |
| `fn_comment_job_card(p_client_ref, p_job, p_body, p_kind, p_visibility, p_mentions uuid[])` | `jc.view` at the site, or the requester (visibility forced to requester) | mentions notify |
| `fn_add_job_attachment(p_client_ref, p_job, p_kind, p_path, p_file_name, p_content_type, p_size, p_caption)` | `jc.register`, `jc.assess` or `jc.execute` at the site; not on closed or cancelled jobs | records an uploaded file |
| `fn_job_card_timeline(p_job)` | `jc.view` | status changes, assignments, comments, files and activity in time order |

Reads, search and dashboard:

| function | returns |
| --- | --- |
| `fn_workload(p_site)` | per person holding `jc.execute` at the site: user_id, full_name, responsible_open, support_open, overdue, critical, estimated_hours (for assignment) |
| `fn_site_people(p_site)` | id, full_name of active people who can see job cards at the site (for @mentions) |
| `fn_dashboard(p_site, p_from, p_to)` | jsonb: `cards`, `open_vs_closed`, `by_priority`, `by_area`, `by_equipment`, `by_technician`, `by_type`, `trend`, `overdue_ageing`, `avg_response_minutes`, `avg_closure_minutes`, `response_target`, `completion_target`, `alerts{critical, overdue, approaching, awaiting_review, on_hold_long, production_impact}`; `p_site` null = all the user's sites |
| `fn_search(p_query)` | rows (kind jobcard \| asset \| request, id, ref, title, subtitle) the user may see |

Administration (`settings.manage` or `admin.users` at all sites):
`fn_save_settings(p_timezone, p_jobcard_prefix, p_request_prefix, p_number_digits,
p_number_reset_yearly, p_response_ends_at, p_at_risk_percent, p_hold_alert_hours,
p_handover_note_required, p_company_name, p_department_name, p_logo_path)`,
`fn_save_priority(p_code, p_name, p_description, p_response_minutes, p_completion_minutes)`,
`fn_save_department(p_id, p_code, p_name, p_is_electrical, p_archived)`,
`fn_save_job_category(p_id, p_name, p_description, p_sort_order, p_archived)`,
`fn_save_asset_category(p_id, p_name, p_sort_order, p_archived)`,
`fn_save_escalation_contact(p_id, p_site, p_priority, p_user, p_archived)`,
`fn_save_asset(p_id, p_site, p_area, p_asset_no, p_name, p_category, p_location,
p_manufacturer, p_model, p_serial_no, p_rating, p_voltage_v, p_current_a, p_power_kw,
p_installed_on, p_status, p_criticality, p_department, p_maintenance_frequency,
p_warranty_expires_on, p_warranty_notes, p_notes, p_archived)` (`assets.manage`),
`fn_admin_users()` (people with email, last sign-in and roles),
`fn_set_user_profile(p_user, p_full_name, p_phone, p_department, p_home_site, p_active)`,
`fn_set_user_roles(p_user, p_roles jsonb [{role_id, site_id}])`. At least one active
administrator must always remain; nobody can deactivate themselves.

Scheduled (pg_cron): `legacy-recurrences` daily at 04:00. The hourly `jobcards-overdue`
notice was replaced in 0008 by escalation rules (section 9.5).

Error codes: `NOT_ALLOWED`, `INVALID`, `NOT_FOUND`, `CONFLICT`.

### 7.6 Files

Bucket `job-files`, path `<site_id>/jobcard/<job_id>/<file>` or
`<site_id>/request/<request_id>/<file>`. Upload, then record with
`fn_add_job_attachment` / `fn_add_request_attachment`. Job card files: read with
`jc.view`; upload with `jc.register`, `jc.assess` or `jc.execute` at the site.
Request files: read by the requester and `req.triage` / `jc.view` at the site; upload
with `req.submit` or `req.triage`. The `fn_add_*` functions check the rest.

### 7.7 Edge function `admin-users`

`POST /functions/v1/admin-users` with the user's token. The caller must hold
`admin.users` at all sites (checked through `my_permissions`). Holds the service key;
the app never does.

| body | result |
| --- | --- |
| `{"action": "create", "email", "password", "full_name"}` | `{"id"}`; the sign-in is confirmed, the profile made by trigger; the app then calls `fn_set_user_profile` and `fn_set_user_roles` |
| `{"action": "reset_password", "user_id", "password"}` | `{"ok": true}` |

Passwords need 8–72 characters. Errors: `{"error": "CODE: message"}` with HTTP 400,
401, 403, 404 or 409. CI deploys it from `main` when the `SUPABASE_ACCESS_TOKEN`
secret is set.

### 7.8 Notifications sent

- New or updated request → `req.triage` holders at the site ("Urgent" when production
  stopped or a safety hazard).
- Job card registered or clarified → `jc.assess` holders; P1 or critical → engineers at
  the site and escalation contacts at once.
- Assigned, reassigned, taken off, on hold, mentioned → the people involved; submitted
  for review → `jc.review` holders; closed, returned for more work, reopened, cancelled →
  the responsible person and registrar.
- The requester: request returned or not accepted, registered, more information needed,
  work started, requester-visible updates, complete, cancelled.
- Overdue and other escalations → as the escalation rules say (section 9.5).

## 8. Push notifications (0007)

Every row inserted into `notifications` is also sent as a push message to the person's
registered phones and browsers, so alerts arrive when the app is closed.

**Flow.**
1. The app gets an FCM registration token and calls `fn_register_device(p_token, p_platform)`
   (through the outbox). It does this when the person taps **Turn on** (banner or account
   menu), and again on each start once permission was given.
2. Trigger `notifications_push` (after insert on `notifications`) calls the `push-send` edge
   function through `pg_net` with `{"notification_id"}` and the `x-push-secret` header. It
   does nothing while `push_config.endpoint` is empty or the person has no active device.
3. `push-send` calls `fn_push_job(p_notification, p_secret)` for the title, body, link and
   tokens, and signs in to Google with `FIREBASE_SERVICE_ACCOUNT`. It then sends one FCM HTTP
   v1 message per token. Critical, overdue and assignment messages go at high priority.
4. Tokens FCM reports as gone are archived with `fn_push_drop_tokens(p_secret, p_tokens)`.

**Tables and functions.**

| name | who | what |
| --- | --- | --- |
| `push_config(endpoint, secret)` | nobody (RLS, no policies) | one row; `secret` is random, made by the migration |
| `fn_unregister_device(p_token)` | signed-in | archives the caller's own token: on sign-out and when alerts are switched off |
| `fn_push_job(p_notification, p_secret)` | service role | jsonb: `id, type, title, body, link, tokens[{token, platform}]` |
| `fn_push_drop_tokens(p_secret, p_tokens text[])` | service role | archives dead tokens, returns how many |
| `fn_set_push_endpoint(p_url)` | database owner (CI) | stores where `push-send` lives |

**Messages.** `notification {title, body}` plus `data {link, type, notification_id, url}`.
- **Android:** tapping a message opens `link`. `jobcard:<id>` goes to `/job-cards/<id>`,
  `request:<id>` to `/requests/<id>`.
- **Browsers:** `web/firebase-messaging-sw.js` shows the message and opens `url`
  (`APP_URL` + `#` + path).

**Configuration.**
- **App:** `app/lib/config/firebase_config.dart` holds the public Firebase identifiers (project,
  web app, Android app for `com.bravura.electrical_department` and the web push key). Push
  stays off on a platform until its values are filled in. The dev flavor has no pushes.
- **Server:** CI deploys `push-send`, copies the `FIREBASE_SERVICE_ACCOUNT` repo secret and
  `APP_URL` into the function's secrets, then calls `fn_set_push_endpoint`. It needs the
  `SUPABASE_ACCESS_TOKEN` repo secret.

## 9. Work execution, time tracking, verification, escalation and audit (0008)

Every table below is read-only for the app: select with `jc.view` at the job's site
(`safety_checklist_items` and `escalation_rules`: any active user). Every write goes
through a function, and every table is audited by `fn_log_activity`.

### 9.1 Work sessions, waits and time

| table | what |
| --- | --- |
| `job_work_sessions` | one per person per stretch of work: started_at, ended_at, end_reason (pause \| hold \| submitted \| cancelled \| stopped \| reassigned \| corrected), pause_reason (break \| end_of_shift \| other_job \| other), pause_note, corrected. At most one open session per person per job |
| `job_waits` | one per hold: hold_status, note, counts_toward_sla (false = the wait moves the deadline), sla_reason / sla_changed_by / sla_changed_at, started/ended at and by. At most one open wait per job |
| `job_time_corrections` | every change to recorded time: session, user, old and new start/end, reason (5+ characters), corrected_by, corrected_at |

Sessions and waits follow the status, so none can be missed: trigger
`job_cards_time_tracking` opens a wait when a job goes on any hold status and closes it on
resume, and ends everyone's sessions whenever the job leaves in_progress (hold,
submission, cancellation).
Trigger `job_assignments_sessions` ends a person's session when they come off the job.
Times are always the server's.

**Measured time** (`fn_job_work` → `time`, all in seconds): `active_seconds` (sessions
merged, so two people working together count once), `labour_seconds` (sessions added
up: person-time), `wait_seconds`, `sla_excluded_seconds`, `pause_count`,
`session_count`, `elapsed_seconds` (received → now or closed), `response_seconds`,
`assignment_seconds`, `start_seconds`.

**Deadline.** Waits with `counts_toward_sla = false` move the completion deadline by
their length. `v_job_cards` now adds `effective_deadline`, `sla_excluded_minutes`,
`open_sessions` (how many people are working now) and `review_question_open`; its
overdue, at-risk and remaining-time fields use the effective deadline.

### 9.2 Work log and safety checks

| table | what |
| --- | --- |
| `job_work_records` | append-only: kind (work_performed \| symptoms \| diagnosis \| root_cause \| corrective_action \| components \| spares_used \| readings \| test_results \| safety_observation \| recommendation \| follow_up \| delay_reason), body (≤ 4000), readings `[{name, value, unit}]` (≤ 50), author |
| `safety_checklist_items` | phase (before \| after), label, category (null = all), applies_when (always \| isolation \| permit \| loto: only when the assessment asks for it), needs_reference, sort_order. 14 seeded |
| `job_safety_records` | each confirmation as recorded: item, label and phase at the time, confirmed, reference (e.g. permit number), note, recorded_by, recorded_at. The latest per item counts |

`system_settings.safety_before_start` (off \| when_required \| always; default off) sets
whether Start needs the required "before" checks and Submit needs the "after" checks.
`when_required` applies to job cards whose assessment asks for isolation, a permit or
lockout. The checklist is a record of what people confirmed, never a control.

### 9.3 Submissions and engineering reviews

Every round is kept.

| table | what |
| --- | --- |
| `job_submissions` | completion_summary, findings, corrective_action, equipment_state_after (operational \| degraded \| out_of_service), functional_tests, electrical_tests, materials_used, labour_hours (reported), recorded_labour_minutes (measured then), outstanding_defects, recommendations, checks_confirmed, safety_confirmed |
| `job_reviews` | submission, reviewer, decision (approve \| reject \| request_info), notes, follow_up_job_id, self_approved, answer / answered_by / answered_at |
| `job_closures` (new columns) | submission_id and the metrics frozen at approval: received_at, elapsed, active, labour, wait and sla_excluded minutes, pause_count, response, assignment and start minutes, response_target_met, completion_target_met, labour_hours_reported |

### 9.4 Functions

| function | who | what |
| --- | --- | --- |
| `fn_start_work(p_job)` | the assigned team (`jc.execute`) | start, resume or join as support: accepts for the responsible person, moves the job to in_progress, opens the caller's session. With the safety policy on, needs the "before" checks |
| `fn_pause_work(p_job, p_reason, p_note, p_counts_toward_sla)` | the team, or `jc.assign` | break \| end_of_shift \| other_job \| other stops only the caller's timer; a hold status (on_hold, awaiting_materials, …) puts the job on hold, stops everyone and starts a wait (note required) |
| `fn_set_job_card_status(p_job, p_status, p_reason)` | as before | phase 1 action, now runs through start and pause |
| `fn_add_work_record(p_client_ref, p_job, p_kind, p_body, p_readings)` | the team, `jc.assign` or `jc.review`; not on closed or cancelled jobs | adds to the work log (outbox-safe) |
| `fn_record_safety(p_job, p_items)` | the team, `jc.assign` or `jc.assess` | `p_items = [{item_id, confirmed, reference, note}]` |
| `fn_submit_for_review(p_job, p_summary, p_findings, p_corrective_action, p_equipment_state_after, p_functional_tests, p_electrical_tests, p_materials_used, p_labour_hours, p_outstanding_defects, p_recommendations, p_checks_confirmed, p_safety_confirmed)` | the responsible person or `jc.assign`; job in progress | both confirmations must be true; → awaiting_review. `fn_submit_job_card` (phase 1) calls it |
| `fn_verify_job_card(p_job, p_decision, p_notes, p_follow_up_title, p_follow_up_description, p_follow_up_priority)` | `jc.review`; not the performer unless `jc.self_approve` | `approve` → closed with metrics frozen; with a follow-up title it also registers a linked job card (source `follow_up`, `parent_job_id`); `reject` → back to accepted (notes required); `request_info` → stays awaiting review with a question. `fn_review_job_card` (phase 1) calls it |
| `fn_answer_review(p_job, p_answer)` | the team or `jc.assign` | answers the open question |
| `fn_correct_work_session(p_session, p_started_at, p_ended_at, p_reason)` | `jc.assign` | fixes a session's times; no future times, overlaps or starts before receipt |
| `fn_add_work_session(p_job, p_user, p_started_at, p_ended_at, p_reason)` | `jc.assign` | a session someone forgot to start; the person must have been assigned |
| `fn_set_wait_sla(p_wait, p_counts, p_reason)` | `jc.assign` | whether a wait counts toward the deadline |
| `fn_job_work(p_job)` | `jc.view` | jsonb for the Work, Safety and Closure tabs: `now`, `time`, `deadline`, `effective_deadline`, `sessions`, `waits`, `corrections`, `records`, `safety {policy, required, missing_before, missing_after, items}`, `submissions`, `reviews` |
| `fn_job_card_timeline(p_job)` | `jc.view` | now also lists sessions, waits, work log, safety checks, submissions, reviews, corrections and escalations |

Settings (`settings.manage` at all sites): `fn_save_escalation_rule(p_id, p_name, p_kind,
p_priority, p_after_minutes, p_notify_responsible, p_notify_assigner, p_notify_engineers,
p_notify_contacts, p_notify_managers, p_active, p_sort_order, p_archived)`,
`fn_save_safety_item(p_id, p_category, p_phase, p_label, p_applies_when,
p_needs_reference, p_sort_order, p_archived)`, `fn_save_safety_policy(p_policy)`.

Audit (`audit.view` at all sites): `fn_audit_log(p_from, p_to, p_table, p_user, p_query,
p_limit, p_offset)` returns `id, at, user_id, user_name, table_name, record_id,
record_label, action, details, total` from `activity`, newest first. `details` holds the
new record for inserts and `{field: {from, to}}` for changes.

### 9.5 Escalation rules

`escalation_rules`: name, kind (not_acknowledged \| approaching_deadline \| overdue \|
on_hold_too_long \| review_waiting), priority_code (null = all), after_minutes (null =
the kind's default: the at-risk share for deadlines, `hold_alert_hours` for holds, 24 h
for reviews), who to tell (notify_responsible, notify_assigner, notify_engineers =
`jc.assign` holders, notify_contacts = escalation contacts for the priority,
notify_managers = `stats.view` holders), is_active. Nine are seeded, covering the
spec: P1/P2 not acknowledged, deadline approaching, overdue, P1 overdue by 1 h, P2 by
4 h, any by a day, on hold too long, review waiting a day.

pg_cron `jobcards-escalations` runs `fn_run_escalations()` every 10 minutes. Each notice
(type `escalation` for not acknowledged, `reminder`, `overdue`, `on_hold` or `review` for
the others) is sent once per job, rule and trigger point
(`job_escalations`), so a new deadline re-arms a rule. When nobody is responsible yet,
the engineers are told instead.

### 9.6 Realtime

The job card channel also listens to `job_work_sessions`, `job_waits`,
`job_work_records`, `job_submissions` and `job_reviews`.

## Changelog

- v0.4 — phase 2: work sessions, waits and time corrections; work log; safety checklist
  and policy; submissions and engineering reviews with follow-up jobs and questions;
  closure metrics; escalation rules every 10 minutes (replacing the hourly overdue
  notice); audit log function; `v_job_cards` effective deadline.
- v0.3 — push notifications: `push_config`, trigger `notifications_push`,
  `fn_unregister_device`, `fn_push_job`, `fn_push_drop_tokens`, `fn_set_push_endpoint`; the
  `push-send` edge function; alerts toggle in the app.
- v0.2 — job card & maintenance management, phase 1: roles renamed and new permission
  codes; settings, priorities, departments, categories, escalation contacts; assets;
  service requests; job cards with assessment, assignment, holds, escalation, review and
  closure; `v_job_cards`; dashboard and search functions; user administration and the
  `admin-users` edge function; `job-files` bucket; jobs board retired and its data copied in.
- v0.1 — foundation (sites, areas, profiles, roles/permissions, activity, notifications, device tokens, codes, buckets).
