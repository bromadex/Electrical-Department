import { expect, test } from '@playwright/test';
import { Api, expectShown, fill, open, people, q, reportFailure, shot, shown, signIn, stamp, tap } from './support';

// Phase 1 acceptance tests from the CMMS spec, run in order against one
// seeded local database. Screenshots go to e2e/screenshots/.
//
// Flutter joins the texts of a card into one accessible label, so texts
// inside panels are matched by pattern; buttons are matched exactly.

test.describe.configure({ mode: 'serial' });
test.afterEach(async ({}, testInfo) => reportFailure(testInfo));

const JOB_NUMBER = /EL-JC-\d{4}-\d{4,}/;

async function jobByTitle(api: Api, title: string) {
  const [job] = await api.select(
    `v_job_cards?select=id,number,status,responsible_name,is_critical,is_overdue,sla_state&title=eq.${q(title)}`,
  );
  expect(job, `job card "${title}"`).toBeTruthy();
  return job;
}

test('Test 1: a new job card gets a unique number and receipt time', async ({ browser }) => {
  const page = await signIn(browser, people.engineer);
  await open(page, '/v2/job-cards/new');
  await expectShown(page, /Receive and register an electrical fault/);
  const title = `MCC-4 isolator handle broken (${stamp})`;
  await fill(page, /Reported by/, 'Shift foreman');
  await fill(page, /Location details/, 'MCC-4, feeder 2');
  await fill(page, /Short title/, title);
  await fill(page, /Detailed description/, 'The isolator handle on MCC-4 feeder 2 has broken off.');
  await tap(page, 'Minor', true);
  await tap(page, 'P3 Medium', true);
  await shot(page, '01-register-form');

  await tap(page, 'Register job card', true);
  await page.waitForURL(JOB_NUMBER);
  const number = page.url().match(JOB_NUMBER)![0];
  await expectShown(page, number);
  await expectShown(page, /Received/);
  await shot(page, '01-registered-job-card');

  const api = await Api.as(people.engineer);
  const rows = await api.select<{ number: string; title: string; received_at: string }>(
    'job_cards?select=number,title,received_at',
  );
  const numbers = rows.map((r) => r.number);
  expect(new Set(numbers).size, 'job card numbers are unique').toBe(numbers.length);
  const mine = rows.find((r) => r.number === number);
  expect(mine?.title).toBe(title);
  expect(Date.now() - Date.parse(mine!.received_at)).toBeLessThan(10 * 60_000);
});

test('Test 2: an assigned job appears in the electrician’s My Jobs', async ({ browser }) => {
  const title = 'Crusher motor tripping on overload';
  const api = await Api.as(people.engineer);
  const job = await jobByTitle(api, title);
  expect(job.status).toBe('awaiting_assignment');

  const engineer = await signIn(browser, people.engineer);
  await open(engineer, `/v2/job-cards/${job.number}`);
  await expectShown(engineer, /Awaiting assignment/);
  await tap(engineer, 'Assign', true);
  await expectShown(engineer, /Responsible person/);
  await tap(engineer, /Test Technician/);
  await shot(engineer, '02-assign-dialog');
  await engineer.getByRole('button', { name: 'Assign', exact: true }).last().click();
  await expectShown(engineer, /Assignment saved/);
  await expect.poll(async () => (await jobByTitle(api, title)).status).toBe('assigned');
  expect((await jobByTitle(api, title)).responsible_name).toBe('Test Technician');
  await expectShown(engineer, /Test Technician/);

  const electrician = await signIn(browser, people.electrician);
  await open(electrician, '/v2/my-jobs');
  await expectShown(electrician, /Work assigned to you/);
  await expectShown(electrician, title);
  await shot(electrician, '02-electrician-my-jobs');
});

test('Test 4: a job past its deadline shows as overdue', async ({ browser }) => {
  const title = 'Replace control room UPS batteries';
  const api = await Api.as(people.engineer);
  const job = await jobByTitle(api, title);
  expect(job.is_overdue).toBe(true);
  expect(job.sla_state).toBe('overdue');

  const page = await signIn(browser, people.engineer);
  await open(page, '/v2/job-cards?view=overdue');
  await expectShown(page, title);
  await expectShown(page, /Overdue/);
  await shot(page, '04-overdue-job-cards');
  await open(page, '/v2/dashboard');
  await expectShown(page, /Needs you/);
  await shot(page, '04-dashboard');
});

test('Test 5: a P1 job updates the critical dashboard and sends notifications', async ({ browser }) => {
  const engineer = await signIn(browser, people.engineer);
  await open(engineer, '/v2/job-cards/new');
  const title = `Smoke from main incomer cable (${stamp})`;
  await fill(engineer, /Reported by/, 'Control room operator');
  await fill(engineer, /Location details/, 'Main substation, incomer 1');
  await fill(engineer, /Short title/, title);
  await fill(engineer, /Detailed description/, 'Smoke seen at the incomer 1 cable termination.');
  await tap(engineer, 'Safety hazard', true);
  await tap(engineer, 'P1 Emergency', true);
  await expectShown(engineer, /alerts the electrical engineers/);
  await tap(engineer, 'Register job card', true);
  await engineer.waitForURL(JOB_NUMBER);
  const number = engineer.url().match(JOB_NUMBER)![0];
  await expectShown(engineer, /\bCritical\b/);
  await shot(engineer, '05-p1-job-card');
  const api = await Api.as(people.engineer);
  expect((await jobByTitle(api, title)).is_critical).toBe(true);

  // The department manager is the P1 escalation contact.
  const manager = await signIn(browser, people.manager);
  await open(manager, '/notifications');
  await expectShown(manager, `CRITICAL ${number} (P1)`);
  await shot(manager, '05-manager-notifications');

  // The manager's home site is Harare; the P1 job is at Kamativi.
  await open(manager, '/v2/dashboard');
  await manager.getByRole('button', { name: /Switch site|Harare/ }).first().click();
  await tap(manager, 'All my sites', true);
  await tap(manager, /critical job cards?/);
  await expectShown(manager, number);
  await shot(manager, '05-manager-dashboard');
});

test('Test 10: an electrician is blocked from admin, assigning and approving', async ({ browser }) => {
  const electrician = await signIn(browser, people.electrician);
  await open(electrician, '/v2/dashboard');
  await expect(electrician.getByRole('button', { name: 'Job Cards', exact: true }).first()).toBeVisible();
  await expect(shown(electrician, 'Settings', true)).toHaveCount(0);
  await expect(shown(electrician, 'Audit Logs', true)).toHaveCount(0);
  await open(electrician, '/v2/settings');
  await expectShown(electrician, /Administrators only/);
  await shot(electrician, '10-electrician-admin-blocked');
  await open(electrician, '/v2/audit');
  await expectShown(electrician, /Audit log access needed/);

  const api = await Api.as(people.electrician);
  const review = await jobByTitle(api, 'Generator G2 weekly inspection');
  expect(review.status).toBe('awaiting_review');
  await open(electrician, `/v2/job-cards/${review.number}`);
  await expectShown(electrician, /Awaiting engineering review/);
  await expect(electrician.getByRole('button', { name: 'Verify work', exact: true })).toHaveCount(0);
  await expect(electrician.getByRole('button', { name: 'Reassign', exact: true })).toHaveCount(0);
  await shot(electrician, '10-electrician-no-verify');

  // The server refuses as well, whatever the app shows.
  const approve = await api.rpc('fn_review_job_card', { p_job: review.id, p_decision: 'approve', p_notes: 'test' });
  expect(approve.ok).toBe(false);
  expect(approve.body.message).toMatch(/^NOT_ALLOWED/);
  const heater = await jobByTitle(api, 'Main LV panel heater not working');
  const assign = await api.rpc('fn_assign_job_card', {
    p_job: heater.id, p_responsible: api.userId, p_support: [], p_planned_start_at: null,
    p_target_completion_at: null, p_estimated_hours: null, p_materials: null, p_tools: null,
    p_safety: null, p_procedure: null, p_handover_note: null, p_reason: null,
  });
  expect(assign.ok).toBe(false);
  expect(assign.body.message).toMatch(/^NOT_ALLOWED/);
});

test('Test 10: nobody approves the closure of their own work', async () => {
  const engineer = await Api.as(people.engineer);
  const [site] = await engineer.select<{ id: string }>('sites?select=id&code=eq.KAM');
  const job = await engineer.call('fn_register_job_card', {
    p_client_ref: null, p_request: null, p_site: site.id, p_area: null, p_location: 'Workshop bench',
    p_received_at: null, p_reporter_name: 'Farai Chikwanha', p_department: null, p_asset: null,
    p_equipment_name: null, p_equipment_asset_no: null, p_equipment_location: null, p_category: null,
    p_title: `Bench grinder plug replacement (${stamp})`, p_description: 'The plug top is cracked.',
    p_impact: 'none', p_priority: 'P4', p_requested_completion_at: null,
  });
  await engineer.call('fn_assess_job_card', {
    p_job: job.id, p_valid: true, p_maintenance_type: 'corrective', p_severity: 'minor',
    p_safety_risk: 'low', p_safety_notes: null, p_equipment_state: 'operational', p_competencies: null,
    p_personnel: null, p_resources: null, p_isolation: false, p_permit: false, p_loto: false,
    p_duration_hours: null, p_priority: 'P4', p_target_response_at: null,
    p_target_completion_at: null, p_notes: null,
  });
  await engineer.call('fn_assign_job_card', {
    p_job: job.id, p_responsible: engineer.userId, p_support: [], p_planned_start_at: null,
    p_target_completion_at: null, p_estimated_hours: null, p_materials: null, p_tools: null,
    p_safety: null, p_procedure: null, p_handover_note: null, p_reason: null,
  });
  await engineer.call('fn_set_job_card_status', { p_job: job.id, p_status: 'in_progress', p_reason: null });
  await engineer.call('fn_submit_job_card', {
    p_job: job.id, p_summary: 'Replaced the plug top and tested.', p_findings: 'Cracked plug top.',
    p_corrective_action: 'Fitted a new plug top.', p_equipment_state_after: 'operational',
    p_checks_confirmed: true,
  });
  const own = await engineer.rpc('fn_review_job_card', { p_job: job.id, p_decision: 'approve', p_notes: 'own work' });
  expect(own.ok).toBe(false);
  expect(own.body.message).toMatch(/^NOT_ALLOWED/);
  console.log(`Self-approval refused: ${own.body.message}`);
});

test('Request flow: a request reaches the queue and becomes a job card', async ({ browser }) => {
  const title = `Sockets dead in production office (${stamp})`;
  const requester = await signIn(browser, people.requester);
  await open(requester, '/v2/my-requests/new');
  await expectShown(requester, /Report an electrical fault or ask for electrical work/);
  await fill(requester, /Name of the person reporting/, 'Blessing Dube');
  await fill(requester, /Exact location/, 'Production office, east wall');
  await fill(requester, /Short title/, title);
  await fill(requester, /What is wrong/, 'All the sockets on the east wall stopped working this morning.');
  await tap(requester, 'Reduced output', true);
  await shot(requester, '07-request-form');
  await tap(requester, 'Send request', true);
  await expectShown(requester, title);
  await shot(requester, '07-request-sent');

  const engineer = await signIn(browser, people.engineer);
  await open(engineer, '/v2/requests');
  await expectShown(engineer, /waiting to be registered/);
  await expectShown(engineer, title);
  await shot(engineer, '07-incoming-requests');
  await tap(engineer, title);
  await engineer.waitForURL(/#\/v2\/requests\/[0-9a-f-]{36}/);
  await expectShown(engineer, title);
  await tap(engineer, 'Register job card', true);
  await expectShown(engineer, /Register EL-SR-/);
  await tap(engineer, 'P3 Medium', true);
  await shot(engineer, '07-register-from-request');
  await tap(engineer, 'Register job card', true);
  await engineer.waitForURL(JOB_NUMBER);
  const number = engineer.url().match(JOB_NUMBER)![0];
  await shot(engineer, '07-job-card-from-request');

  await open(requester, '/v2/my-requests');
  await tap(requester, title);
  await requester.waitForURL(/#\/v2\/requests\/[0-9a-f-]{36}/);
  await expectShown(requester, number);
  await shot(requester, '07-requester-tracking');
});

for (const [name, viewport] of [
  ['desktop', { width: 1440, height: 900 }],
  ['tablet', { width: 820, height: 1180 }],
  ['phone', { width: 390, height: 844 }],
] as const) {
  test(`Test 12: ${name} layout`, async ({ browser }) => {
    const api = await Api.as(people.engineer);
    const job = await jobByTitle(api, 'Conveyor 3 VFD fault F0002');
    const engineer = await signIn(browser, people.engineer, viewport);
    await open(engineer, '/v2/dashboard');
    await expectShown(engineer, /Needs you/);
    await shot(engineer, `12-${name}-dashboard`);
    await open(engineer, '/v2/job-cards');
    // Phones start a job card from the + in the bottom bar.
    const create = name === 'phone' ? 'New' : /New job card/;
    await expect(engineer.getByRole('button', { name: create, exact: name === 'phone' }).first()).toBeVisible();
    await shot(engineer, `12-${name}-job-cards`);
    await open(engineer, `/v2/job-cards/${job.number}`);
    await expectShown(engineer, 'Conveyor 3 VFD fault F0002');
    await shot(engineer, `12-${name}-job-card`);

    const electrician = await signIn(browser, people.electrician, viewport);
    await open(electrician, '/v2/my-jobs');
    await expectShown(electrician, /Work assigned to you/);
    await shot(electrician, `12-${name}-my-jobs`);
  });
}
