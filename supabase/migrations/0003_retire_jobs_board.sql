-- 0003_retire_jobs_board: the jobs board (0002) is replaced by job cards
-- (0004). Its tables are renamed to legacy_* rather than dropped, so 0005 can
-- copy their rows into job cards and the old records stay readable.

-- ---------------------------------------------------------------------------
-- Schedules and realtime
-- ---------------------------------------------------------------------------
select cron.unschedule(jobid)
from cron.job
where jobname in ('jobs-recurrences', 'jobs-overdue');

do $$
begin
  if exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'jobs'
  ) then
    alter publication supabase_realtime
      drop table public.jobs, public.job_comments, public.job_photos;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Functions: job cards (0004) bring their own
-- ---------------------------------------------------------------------------
drop function public.fn_create_job(uuid, uuid, uuid, text, text, text, timestamptz, double precision, double precision);
drop function public.fn_edit_job(uuid, text, text, uuid, text, timestamptz);
drop function public.fn_take_job(uuid);
drop function public.fn_assign_job(uuid, uuid);
drop function public.fn_set_job_status(uuid, text, text);
drop function public.fn_close_job(uuid, text);
drop function public.fn_add_job_photo(uuid, uuid, text, text);
drop function public.fn_comment_job(uuid, uuid, text);
drop function public.fn_job_assignees(uuid);
drop function public.fn_job_history(uuid);
drop function public.fn_save_recurrence(uuid, uuid, uuid, text, text, text, text, date, integer, uuid, boolean);
drop function public.fn_run_recurrences();
drop function public.fn_notify_overdue();
drop function public._job_for_write(uuid);

-- ---------------------------------------------------------------------------
-- Tables, keys and indexes: renamed so 0004 can reuse the plain names
-- (writes were already revoked from the app in 0002)
-- ---------------------------------------------------------------------------
alter table public.job_comments rename to legacy_job_comments;
alter table public.job_photos rename to legacy_job_photos;
alter table public.jobs rename to legacy_jobs;
alter table public.job_recurrences rename to legacy_job_recurrences;

alter table public.legacy_job_comments rename constraint job_comments_pkey to legacy_job_comments_pkey;
alter table public.legacy_job_photos rename constraint job_photos_pkey to legacy_job_photos_pkey;
alter table public.legacy_jobs rename constraint jobs_pkey to legacy_jobs_pkey;
alter table public.legacy_jobs rename constraint jobs_site_id_code_key to legacy_jobs_site_id_code_key;
alter table public.legacy_job_recurrences rename constraint job_recurrences_pkey to legacy_job_recurrences_pkey;

alter index public.jobs_site_status_idx rename to legacy_jobs_site_status_idx;
alter index public.jobs_assignee_idx rename to legacy_jobs_assignee_idx;
alter index public.jobs_due_idx rename to legacy_jobs_due_idx;
alter index public.jobs_updated_idx rename to legacy_jobs_updated_idx;
alter index public.job_photos_job_idx rename to legacy_job_photos_job_idx;
alter index public.job_comments_job_idx rename to legacy_job_comments_job_idx;

-- The old permission codes grant nothing from now on; 0004 adds jc.* codes.
update public.permissions set is_archived = true
where code in ('jobs.view', 'jobs.create', 'jobs.assign', 'jobs.close');

insert into public.schema_migrations (filename) values ('0003_retire_jobs_board.sql')
on conflict do nothing;
