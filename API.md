# Bravura Electrical - API.md

App <-> Supabase contract · v0.2 job card & maintenance management

The contract between the Flutter app (Android + web) and Supabase. **Every**
table, view, function, bucket and realtime channel the app uses is listed here.
Change it in the same pull request as the migration or screen that needs it.
Version: v0.2 (CMMS phase 1: job cards, requests, assets, dashboard, admin).

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

- 7. Job card & maintenance management — phase 1 (below)
- Later phases add: work sessions and time tracking, verification and escalation rules,
  audit log screen (phase 2); SOP library, asset register details, preventive maintenance,
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

Scheduled (pg_cron): `jobcards-overdue` at :10 every hour notifies the responsible
person and assigner once per deadline (`fn_notify_overdue_job_cards`);
`legacy-recurrences` daily at 04:00.

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
- Overdue (hourly) → the responsible person and assigner, or `jc.assign` holders when
  unassigned.

## Changelog

- v0.2 — job card & maintenance management, phase 1: roles renamed and new permission
  codes; settings, priorities, departments, categories, escalation contacts; assets;
  service requests; job cards with assessment, assignment, holds, escalation, review and
  closure; `v_job_cards`; dashboard and search functions; user administration and the
  `admin-users` edge function; `job-files` bucket; jobs board retired and its data copied in.
- v0.1 — foundation (sites, areas, profiles, roles/permissions, activity, notifications, device tokens, codes, buckets).
