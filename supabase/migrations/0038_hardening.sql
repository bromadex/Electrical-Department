-- 0038_hardening: offline and performance hardening (API.md section 21,
-- issue #17).
--
-- 1. An index on every foreign key that had none (the Supabase performance
--    advisor's "unindexed foreign keys"), so joins, RLS lookups and deletes
--    on the referenced rows stay fast as the tables grow. user_roles.role_id
--    and site_id matter most: every permission check reads them.
-- 2. Error reports from the app (a free stand-in for a hosted service):
--    the same error from the same person is counted, not repeated.

create index if not exists activity_user_id_fk on public.activity (user_id);
create index if not exists assets_area_id_fk on public.assets (area_id);
create index if not exists assets_created_by_fk on public.assets (created_by);
create index if not exists assets_department_id_fk on public.assets (department_id);
create index if not exists boq_lines_item_id_fk on public.boq_lines (item_id);
create index if not exists call_participants_conversation_id_fk on public.call_participants (conversation_id);
create index if not exists call_participants_user_id_fk on public.call_participants (user_id);
create index if not exists calls_message_id_fk on public.calls (message_id);
create index if not exists calls_started_by_fk on public.calls (started_by);
create index if not exists checklist_answers_item_id_fk on public.checklist_answers (item_id);
create index if not exists checklist_answers_job_card_id_fk on public.checklist_answers (job_card_id);
create index if not exists checklist_answers_job_id_fk on public.checklist_answers (job_id);
create index if not exists checklist_runs_done_by_fk on public.checklist_runs (done_by);
create index if not exists checklist_templates_area_id_fk on public.checklist_templates (area_id);
create index if not exists checklist_templates_assignee_id_fk on public.checklist_templates (assignee_id);
create index if not exists checklist_templates_created_by_fk on public.checklist_templates (created_by);
create index if not exists checklist_templates_site_id_fk on public.checklist_templates (site_id);
create index if not exists conversation_calls_started_by_fk on public.conversation_calls (started_by);
create index if not exists conversations_created_by_fk on public.conversations (created_by);
create index if not exists conversations_site_id_fk on public.conversations (site_id);
create index if not exists daily_reports_approved_by_fk on public.daily_reports (approved_by);
create index if not exists document_acks_user_id_fk on public.document_acks (user_id);
create index if not exists document_folders_created_by_fk on public.document_folders (created_by);
create index if not exists document_versions_created_by_fk on public.document_versions (created_by);
create index if not exists documents_created_by_fk on public.documents (created_by);
create index if not exists escalation_contacts_priority_code_fk on public.escalation_contacts (priority_code);
create index if not exists escalation_contacts_user_id_fk on public.escalation_contacts (user_id);
create index if not exists escalation_rules_priority_code_fk on public.escalation_rules (priority_code);
create index if not exists job_assignments_assigned_by_fk on public.job_assignments (assigned_by);
create index if not exists job_attachments_uploaded_by_fk on public.job_attachments (uploaded_by);
create index if not exists job_card_comments_author_id_fk on public.job_card_comments (author_id);
create index if not exists job_card_documents_linked_by_fk on public.job_card_documents (linked_by);
create index if not exists job_card_tools_linked_by_fk on public.job_card_tools (linked_by);
create index if not exists job_cards_area_id_fk on public.job_cards (area_id);
create index if not exists job_cards_assessed_by_fk on public.job_cards (assessed_by);
create index if not exists job_cards_assigned_by_fk on public.job_cards (assigned_by);
create index if not exists job_cards_category_id_fk on public.job_cards (category_id);
create index if not exists job_cards_escalated_by_fk on public.job_cards (escalated_by);
create index if not exists job_cards_parent_job_id_fk on public.job_cards (parent_job_id);
create index if not exists job_cards_performed_by_fk on public.job_cards (performed_by);
create index if not exists job_cards_priority_fk on public.job_cards (priority);
create index if not exists job_cards_registered_by_fk on public.job_cards (registered_by);
create index if not exists job_cards_requesting_department_id_fk on public.job_cards (requesting_department_id);
create index if not exists job_cards_verified_by_fk on public.job_cards (verified_by);
create index if not exists job_closures_performed_by_fk on public.job_closures (performed_by);
create index if not exists job_closures_submission_id_fk on public.job_closures (submission_id);
create index if not exists job_closures_verified_by_fk on public.job_closures (verified_by);
create index if not exists job_comments_author_id_fk on public.job_comments (author_id);
create index if not exists job_documents_document_id_fk on public.job_documents (document_id);
create index if not exists job_documents_linked_by_fk on public.job_documents (linked_by);
create index if not exists job_escalations_rule_id_fk on public.job_escalations (rule_id);
create index if not exists job_photos_created_by_fk on public.job_photos (created_by);
create index if not exists job_recurrences_area_id_fk on public.job_recurrences (area_id);
create index if not exists job_recurrences_asset_id_fk on public.job_recurrences (asset_id);
create index if not exists job_recurrences_assignee_id_fk on public.job_recurrences (assignee_id);
create index if not exists job_recurrences_created_by_fk on public.job_recurrences (created_by);
create index if not exists job_recurrences_site_id_fk on public.job_recurrences (site_id);
create index if not exists job_requests_area_id_fk on public.job_requests (area_id);
create index if not exists job_requests_decided_by_fk on public.job_requests (decided_by);
create index if not exists job_reviews_answered_by_fk on public.job_reviews (answered_by);
create index if not exists job_reviews_follow_up_job_id_fk on public.job_reviews (follow_up_job_id);
create index if not exists job_reviews_reviewer_id_fk on public.job_reviews (reviewer_id);
create index if not exists job_reviews_submission_id_fk on public.job_reviews (submission_id);
create index if not exists job_safety_checks_user_id_fk on public.job_safety_checks (user_id);
create index if not exists job_safety_records_item_id_fk on public.job_safety_records (item_id);
create index if not exists job_safety_records_recorded_by_fk on public.job_safety_records (recorded_by);
create index if not exists job_status_history_changed_by_fk on public.job_status_history (changed_by);
create index if not exists job_submissions_submitted_by_fk on public.job_submissions (submitted_by);
create index if not exists job_time_corrections_corrected_by_fk on public.job_time_corrections (corrected_by);
create index if not exists job_time_corrections_session_id_fk on public.job_time_corrections (session_id);
create index if not exists job_time_corrections_user_id_fk on public.job_time_corrections (user_id);
create index if not exists job_waits_ended_by_fk on public.job_waits (ended_by);
create index if not exists job_waits_sla_changed_by_fk on public.job_waits (sla_changed_by);
create index if not exists job_waits_started_by_fk on public.job_waits (started_by);
create index if not exists job_work_records_author_id_fk on public.job_work_records (author_id);
create index if not exists jobs_area_id_fk on public.jobs (area_id);
create index if not exists jobs_closed_by_fk on public.jobs (closed_by);
create index if not exists jobs_created_by_fk on public.jobs (created_by);
create index if not exists jobs_recurrence_id_fk on public.jobs (recurrence_id);
create index if not exists material_requests_decided_by_fk on public.material_requests (decided_by);
create index if not exists material_requests_job_card_id_fk on public.material_requests (job_card_id);
create index if not exists material_requests_project_id_fk on public.material_requests (project_id);
create index if not exists material_requests_requested_by_fk on public.material_requests (requested_by);
create index if not exists meeting_captions_conversation_id_fk on public.meeting_captions (conversation_id);
create index if not exists meeting_captions_user_id_fk on public.meeting_captions (user_id);
create index if not exists meetings_chair_id_fk on public.meetings (chair_id);
create index if not exists meetings_message_id_fk on public.meetings (message_id);
create index if not exists message_reactions_user_id_fk on public.message_reactions (user_id);
create index if not exists messages_author_id_fk on public.messages (author_id);
create index if not exists messages_reply_to_fk on public.messages (reply_to);
create index if not exists mr_lines_item_id_fk on public.mr_lines (item_id);
create index if not exists notifications_site_id_fk on public.notifications (site_id);
create index if not exists po_deliveries_po_id_fk on public.po_deliveries (po_id);
create index if not exists po_deliveries_received_by_fk on public.po_deliveries (received_by);
create index if not exists po_lines_item_id_fk on public.po_lines (item_id);
create index if not exists priority_levels_updated_by_fk on public.priority_levels (updated_by);
create index if not exists profiles_department_id_fk on public.profiles (department_id);
create index if not exists profiles_home_site_id_fk on public.profiles (home_site_id);
create index if not exists project_members_user_id_fk on public.project_members (user_id);
create index if not exists projects_created_by_fk on public.projects (created_by);
create index if not exists projects_owner_id_fk on public.projects (owner_id);
create index if not exists purchase_orders_created_by_fk on public.purchase_orders (created_by);
create index if not exists purchase_orders_supplier_id_fk on public.purchase_orders (supplier_id);
create index if not exists reminders_site_id_fk on public.reminders (site_id);
create index if not exists report_updates_user_id_fk on public.report_updates (user_id);
create index if not exists request_attachments_uploaded_by_fk on public.request_attachments (uploaded_by);
create index if not exists role_permissions_permission_code_fk on public.role_permissions (permission_code);
create index if not exists roster_entries_updated_by_fk on public.roster_entries (updated_by);
create index if not exists roster_entries_user_id_fk on public.roster_entries (user_id);
create index if not exists roster_weeks_published_by_fk on public.roster_weeks (published_by);
create index if not exists safety_checklist_items_category_id_fk on public.safety_checklist_items (category_id);
create index if not exists service_requests_area_id_fk on public.service_requests (area_id);
create index if not exists service_requests_asset_id_fk on public.service_requests (asset_id);
create index if not exists service_requests_department_id_fk on public.service_requests (department_id);
create index if not exists service_requests_job_card_id_fk on public.service_requests (job_card_id);
create index if not exists service_requests_reviewed_by_fk on public.service_requests (reviewed_by);
create index if not exists stock_count_lines_item_id_fk on public.stock_count_lines (item_id);
create index if not exists stock_counts_created_by_fk on public.stock_counts (created_by);
create index if not exists stock_counts_site_id_fk on public.stock_counts (site_id);
create index if not exists stock_moves_count_id_fk on public.stock_moves (count_id);
create index if not exists stock_moves_created_by_fk on public.stock_moves (created_by);
create index if not exists stock_moves_mr_id_fk on public.stock_moves (mr_id);
create index if not exists stock_moves_po_id_fk on public.stock_moves (po_id);
create index if not exists stock_moves_site_id_fk on public.stock_moves (site_id);
create index if not exists stock_moves_to_user_fk on public.stock_moves (to_user);
create index if not exists store_items_created_by_fk on public.store_items (created_by);
create index if not exists system_settings_updated_by_fk on public.system_settings (updated_by);
create index if not exists tool_certificates_uploaded_by_fk on public.tool_certificates (uploaded_by);
create index if not exists tool_issue_forms_issued_by_fk on public.tool_issue_forms (issued_by);
create index if not exists tool_issue_forms_job_card_id_fk on public.tool_issue_forms (job_card_id);
create index if not exists tool_issue_forms_received_back_by_fk on public.tool_issue_forms (received_back_by);
create index if not exists tool_issue_forms_recipient_id_fk on public.tool_issue_forms (recipient_id);
create index if not exists tool_issues_issued_by_fk on public.tool_issues (issued_by);
create index if not exists tool_issues_issued_to_fk on public.tool_issues (issued_to);
create index if not exists tool_issues_returned_by_fk on public.tool_issues (returned_by);
create index if not exists tools_created_by_fk on public.tools (created_by);
create index if not exists tools_issue_form_id_fk on public.tools (issue_form_id);
create index if not exists tools_repair_job_card_id_fk on public.tools (repair_job_card_id);
create index if not exists user_roles_role_id_fk on public.user_roles (role_id);
create index if not exists user_roles_site_id_fk on public.user_roles (site_id);

-- ---------------------------------------------------------------------------
-- Error reports
-- ---------------------------------------------------------------------------
create table public.client_errors (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles (id) default auth.uid(),
  fingerprint text not null,
  message text not null check (length(message) <= 1000),
  stack text check (length(stack) <= 8000),
  route text check (length(route) <= 300),
  platform text check (length(platform) <= 40),
  app_version text check (length(app_version) <= 40),
  count integer not null default 1,
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  is_archived boolean not null default false
);
create unique index client_errors_open on public.client_errors (user_id, fingerprint) where not is_archived;
create index client_errors_last_seen on public.client_errors (last_seen desc) where not is_archived;

-- Records an error from the app (any active user). The same error (same
-- fingerprint) from the same person adds to its count.
create function public.fn_report_error(
  p_fingerprint text,
  p_message text,
  p_stack text,
  p_route text,
  p_platform text,
  p_app_version text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public._active() then
    return;
  end if;
  if length(coalesce(p_fingerprint, '')) not between 1 and 100 then
    raise exception 'INVALID: Missing fingerprint';
  end if;
  insert into public.client_errors as e (fingerprint, message, stack, route, platform, app_version)
  values (p_fingerprint, left(coalesce(p_message, '?'), 1000), left(p_stack, 8000), left(p_route, 300),
    left(p_platform, 40), left(p_app_version, 40))
  on conflict (user_id, fingerprint) where not is_archived do update
  set count = e.count + 1, last_seen = now(), route = excluded.route, app_version = excluded.app_version;
end;
$$;

alter table public.client_errors enable row level security;
create policy client_errors_select on public.client_errors for select to authenticated
  using (public._can('admin.users', null));
create policy client_errors_update on public.client_errors for update to authenticated
  using (public._can('admin.users', null))
  with check (public._can('admin.users', null));
revoke all on public.client_errors from anon;
revoke insert, delete on public.client_errors from authenticated;

revoke execute on function public.fn_report_error(text, text, text, text, text, text) from public, anon;
grant execute on function public.fn_report_error(text, text, text, text, text, text) to authenticated;

insert into public.schema_migrations (filename) values ('0038_hardening.sql')
on conflict do nothing;
