import { expect, Page, test } from '@playwright/test';
import { Api, expectShown, fill, open, people, q, reportFailure, shot, signIn, tap } from './support';

// Phase 2 acceptance tests: time tracking (Test 3) and engineering approval
// (Test 6), plus both themes. Uses the seeded job card "Replace damaged 63 A
// MCB in DB-3", assigned to Tatenda Ncube (electrician@).

test.describe.configure({ mode: 'serial' });
test.afterEach(async ({}, testInfo) => reportFailure(testInfo));

const TITLE = 'Replace damaged 63 A MCB in DB-3';

async function job(api: Api) {
  const [row] = await api.select(`v_job_cards?select=id,number,status&title=eq.${q(TITLE)}`);
  expect(row, TITLE).toBeTruthy();
  return row as { id: string; number: string; status: string };
}

async function submit(page: Page, summary: string) {
  await tap(page, 'Submit for review', true);
  await expectShown(page, /Work completion summary/);
  await fill(page, /Work completion summary/, summary);
  await fill(page, /Fault cause or findings/, 'Cracked MCB body, running hot');
  await fill(page, /Corrective action taken/, 'Replaced the 63 A MCB on way 7');
  await fill(page, /Functional test results/, 'Load test 41 A, no heating');
  await tap(page, 'Operational', true);
  await tap(page, /required checks and tests were completed/);
  await tap(page, /safety procedures were followed/);
  await shot(page, `p2-submit-form-${summary.length}`);
  await page.getByRole('button', { name: 'Submit for review', exact: true }).last().click();
  await expectShown(page, /Submitted for engineering review/);
}

test('Test 3: active work, waiting and elapsed time are measured separately', async ({ browser }) => {
  const api = await Api.as(people.electrician);
  const j = await job(api);
  expect(j.status).toBe('assigned');

  const tech = await signIn(browser, people.electrician);
  await open(tech, `/job-cards/${j.number}`);
  await tap(tech, 'Start work', true);
  await expectShown(tech, /You are working on this job/);
  await tech.waitForTimeout(4000);
  await shot(tech, 'p2-work-clock-running');

  // Pause because the job is waiting for materials (stops the timer).
  await tap(tech, 'Pause', true);
  await tap(tech, 'Awaiting materials', true);
  await fill(tech, /What is it waiting for/, 'New 63 A MCB from stores');
  await tap(tech, 'Put on hold', true);
  await expectShown(tech, /Job card on hold/);
  await tech.waitForTimeout(4000);

  await tap(tech, 'Resume work', true);
  await expectShown(tech, /Work started/);
  await tech.waitForTimeout(3000);
  await submit(tech, 'Replaced the MCB and tested under load.');

  const work = await api.call('fn_job_work', { p_job: j.id });
  const t = work.time;
  console.log(`Measured: active ${t.active_seconds}s, waiting ${t.wait_seconds}s, elapsed ${t.elapsed_seconds}s, labour ${t.labour_seconds}s`);
  expect(t.active_seconds).toBeGreaterThanOrEqual(6);
  expect(t.wait_seconds).toBeGreaterThanOrEqual(3);
  expect(t.elapsed_seconds).toBeGreaterThan(t.active_seconds + t.wait_seconds);
  expect(t.pause_count).toBeGreaterThanOrEqual(1);
  expect(work.sessions.length).toBe(2);
  expect(work.waits.length).toBe(1);

  await tap(tech, /^Work \(/);
  await expectShown(tech, /work sessions/i);
  await shot(tech, 'p2-work-tab');
});

test('Test 6: returned once, then approved, with the whole history kept', async ({ browser }) => {
  const api = await Api.as(people.engineer);
  const j = await job(api);
  expect(j.status).toBe('awaiting_review');

  const engineer = await signIn(browser, people.engineer);
  await open(engineer, `/job-cards/${j.number}`);
  await tap(engineer, 'Verify work', true);
  await expect(engineer.getByRole('checkbox', { name: 'Approve closure' })).toBeVisible();
  await tap(engineer, 'Return for more work', true);
  await fill(engineer, /What still needs to be done/, 'Record the insulation test result');
  await shot(engineer, 'p2-review-return');
  await engineer.getByRole('button', { name: 'Return for more work', exact: true }).last().click();
  await expectShown(engineer, /Returned to the technician/);

  const tech = await signIn(browser, people.electrician);
  await open(tech, `/job-cards/${j.number}`);
  await expectShown(tech, /Returned by the engineer/);
  await tap(tech, 'Start work', true);
  await expectShown(tech, /Work started/);
  await submit(tech, 'Replaced the MCB; insulation test 500 MOhm.');

  await open(engineer, '/dashboard');
  await open(engineer, `/job-cards/${j.number}`);
  await tap(engineer, 'Verify work', true);
  await expectShown(engineer, /insulation test 500 MOhm/);
  await engineer.getByRole('button', { name: 'Approve and close', exact: true }).click();
  await expectShown(engineer, /Job card closed/);

  await tap(engineer, 'Closure', true);
  await expectShown(engineer, /submissions \(2\)/i);
  await expectShown(engineer, /engineering reviews \(2\)/i);
  await shot(engineer, 'p2-closure-history');

  const work = await api.call('fn_job_work', { p_job: j.id });
  expect(work.submissions.length).toBe(2);
  expect(work.reviews.map((r: { decision: string }) => r.decision)).toEqual(['reject', 'approve']);
  const [closure] = await api.select(
    `job_closures?select=active_minutes,labour_minutes,wait_minutes,elapsed_minutes&job_card_id=eq.${j.id}`,
  );
  expect(closure.active_minutes).not.toBeNull();
  expect(closure.elapsed_minutes).toBeGreaterThan(0);
  const history = await api.select(`job_status_history?select=to_status&job_card_id=eq.${j.id}&order=changed_at`);
  const statuses = history.map((h: { to_status: string }) => h.to_status);
  expect(statuses.filter((s: string) => s === 'awaiting_review').length).toBe(2);
  expect(statuses).toContain('closed');
});

test('Settings and audit log: a rule change is saved and shows in the audit trail', async ({ browser }) => {
  const RULE = 'Waiting for engineering review';
  const api = await Api.as(people.admin);
  const admin = await signIn(browser, people.admin);
  await open(admin, '/admin/settings');
  await expectShown(admin, /P1 not acknowledged within its response target/);
  await expectShown(admin, /Hazards identified/);
  await shot(admin, 'p2-settings-escalation-safety');

  await tap(admin, new RegExp(RULE));
  await fill(admin, /After \(minutes\)/, '720');
  await shot(admin, 'p2-settings-edit-rule');
  await admin.getByRole('button', { name: 'Save', exact: true }).last().click();
  await expect
    .poll(async () => (await api.select(`escalation_rules?select=after_minutes&name=eq.${q(RULE)}`))[0]?.after_minutes)
    .toBe(720);
  await expectShown(admin, /Waiting for review longer than 12 h/);

  await open(admin, '/admin/audit');
  await expectShown(admin, /Every change: who, what and when/);
  await fill(admin, /Search number, person or value/, RULE);
  await admin.keyboard.press('Enter');
  await expectShown(admin, new RegExp(`Escalation rules ${RULE}`));
  await expectShown(admin, /1440 → 720/);
  await shot(admin, 'p2-audit-log');

  const techApi = await Api.as(people.electrician);
  const rows = await techApi.call('fn_audit_log', {
    p_from: null, p_to: null, p_table: null, p_user: null, p_query: null, p_limit: 10, p_offset: 0,
  });
  expect(rows).toHaveLength(0);
  const tech = await signIn(browser, people.electrician);
  await open(tech, '/admin/audit');
  await expectShown(tech, /Audit log access needed/);
});

test('Both themes: light and dark', async ({ browser }) => {
  const api = await Api.as(people.engineer);
  const [running] = await api.select(`v_job_cards?select=number&title=eq.${q('Conveyor 3 VFD fault F0002')}`);
  for (const scheme of ['light', 'dark'] as const) {
    const engineer = await signIn(browser, people.engineer, { width: 1440, height: 1000 }, scheme);
    await open(engineer, '/dashboard');
    await expectShown(engineer, /Total job cards/);
    await shot(engineer, `theme-${scheme}-dashboard`);
    await open(engineer, `/job-cards/${running.number}`);
    await expectShown(engineer, /Work time|You are working/);
    await shot(engineer, `theme-${scheme}-job-card`);

    const tech = await signIn(browser, people.electrician, { width: 390, height: 844 }, scheme);
    await open(tech, '/my-jobs');
    await expectShown(tech, /Work assigned to you/);
    await shot(tech, `theme-${scheme}-phone-my-jobs`);
  }
  const login = await (await browser.newContext({ colorScheme: 'dark', viewport: { width: 1440, height: 900 } })).newPage();
  await open(login, '/login');
  await expectShown(login, /Job Card & Maintenance Management/);
  await shot(login, 'theme-dark-login');
});
