import { Browser, expect, Locator, Page, TestInfo } from '@playwright/test';
import { mkdirSync } from 'node:fs';

// The app is a Flutter web build with its accessibility tree switched on
// (--dart-define=E2E=true). Text fields appear as real inputs named by
// their label; buttons and texts appear as DOM text or aria-labels.

export const PASSWORD = 'Passw0rd!';
export const SUPABASE_URL = process.env.SUPABASE_URL ?? 'http://127.0.0.1:54321';
export const ANON_KEY = process.env.SUPABASE_ANON_KEY ?? '';

export const people = {
  admin: 'admin@bravura.test',
  engineer: 'engineer@bravura.test',
  electrician: 'electrician@bravura.test',
  manager: 'manager@bravura.test',
  requester: 'requester@bravura.test',
} as const;

export const desktop = { width: 1440, height: 2400 };

/** A short tag that makes this run's records easy to tell apart. */
export const stamp = Date.now().toString().slice(-6);

const pages: Page[] = [];

/** Text the app shows, exposed either as DOM text or as an aria-label. */
export function shown(page: Page, text: string | RegExp, exact = false): Locator {
  return page.getByText(text, { exact }).or(page.getByLabel(text, { exact }));
}

export async function expectShown(page: Page, text: string | RegExp, exact = false) {
  await expect(shown(page, text, exact).first()).toBeVisible();
}

/** Clicks a button, chip, list row or menu item by its text. */
export async function tap(page: Page, text: string | RegExp, exact = false) {
  const target = page.getByRole('button', { name: text, exact }).or(shown(page, text, exact)).first();
  await target.click();
}

/**
 * Types into the text field with this label, replacing what is there.
 * Flutter attaches its editor a moment after the field takes focus, and keys
 * typed before that are lost, so it waits, checks the result and retries.
 */
export async function fill(page: Page, label: string | RegExp, value: string) {
  const box = page.getByRole('textbox', { name: label }).first();
  for (let attempt = 1; ; attempt++) {
    await box.click();
    await page.waitForTimeout(500);
    await page.keyboard.press('Control+A');
    await page.keyboard.press('Delete');
    await page.keyboard.type(value, { delay: 20 });
    try {
      await expect(box).toHaveValue(value, { timeout: 3_000 });
      return;
    } catch (e) {
      if (attempt >= 3) throw e;
    }
  }
}

export async function open(page: Page, path: string) {
  await page.goto(`/#${path}`);
}

export async function shot(page: Page, name: string) {
  mkdirSync('screenshots', { recursive: true });
  await page.waitForTimeout(800); // let charts and transitions settle
  await page.screenshot({ path: `screenshots/${name}.png` });
}

/** A fresh browser window signed in as [email]. */
export async function signIn(
  browser: Browser,
  email: string,
  viewport: { width: number; height: number } = desktop,
): Promise<Page> {
  const context = await browser.newContext({ viewport });
  const page = await context.newPage();
  pages.push(page);
  await open(page, '/login');
  await fill(page, /Email/, email);
  await fill(page, /Password/, PASSWORD);
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  await page.waitForURL((u) => !u.hash.startsWith('#/login') && !u.hash.startsWith('#/home'), {
    timeout: 60_000,
  });
  return page;
}

/** On failure: a screenshot and the visible texts of every open window. */
export async function reportFailure(testInfo: TestInfo) {
  if (testInfo.status === testInfo.expectedStatus) {
    pages.length = 0;
    return;
  }
  for (const [i, page] of pages.entries()) {
    if (page.isClosed()) continue;
    await testInfo.attach(`window-${i}.png`, { body: await page.screenshot(), contentType: 'image/png' });
    const texts = await page.evaluate(() => {
      const out: string[] = [];
      document.querySelectorAll('flt-semantics, input, textarea').forEach((e) => {
        const el = e as HTMLElement;
        const label = el.getAttribute('aria-label');
        const text = el.childElementCount === 0 ? el.textContent?.trim() : '';
        const role = el.getAttribute('role');
        if (label || text) out.push(`${el.tagName.toLowerCase()}${role ? `[${role}]` : ''}: ${label ?? text}`);
      });
      return `${location.href}\n${out.join('\n')}`;
    });
    await testInfo.attach(`window-${i}.txt`, { body: texts, contentType: 'text/plain' });
    console.log(`--- window ${i} ---\n${texts}`);
  }
  pages.length = 0;
}

/** Direct calls to the local Supabase as a seeded user, for setup and checks. */
export class Api {
  private constructor(
    private readonly token: string,
    readonly userId: string,
  ) {}

  static async as(email: string): Promise<Api> {
    const res = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
      method: 'POST',
      headers: { apikey: ANON_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: PASSWORD }),
    });
    const body = await res.json();
    if (!res.ok) throw new Error(`Sign-in failed for ${email}: ${JSON.stringify(body)}`);
    return new Api(body.access_token, body.user.id);
  }

  private headers() {
    return {
      apikey: ANON_KEY,
      Authorization: `Bearer ${this.token}`,
      'Content-Type': 'application/json',
    };
  }

  async select<T = Record<string, any>>(path: string): Promise<T[]> {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { headers: this.headers() });
    const body = await res.json();
    if (!res.ok) throw new Error(`GET ${path} failed: ${JSON.stringify(body)}`);
    return body as T[];
  }

  async rpc(fn: string, params: Record<string, unknown>) {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
      method: 'POST',
      headers: this.headers(),
      body: JSON.stringify(params),
    });
    const text = await res.text();
    let body: any = null;
    try {
      body = text ? JSON.parse(text) : null;
    } catch {
      body = text;
    }
    return { ok: res.ok, status: res.status, body };
  }

  /** Calls [fn] and fails the test with the server's message if it is refused. */
  async call(fn: string, params: Record<string, unknown>) {
    const res = await this.rpc(fn, params);
    if (!res.ok) throw new Error(`${fn} failed: ${JSON.stringify(res.body)}`);
    return res.body;
  }
}

export const q = encodeURIComponent;
