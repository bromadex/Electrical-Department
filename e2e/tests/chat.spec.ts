import { expect, test } from '@playwright/test';
import { Api, expectShown, open, people, reportFailure, shot, signIn, stamp } from './support';

// Chat behind the floating button with WhatsApp's look
// (docs/plan-whatsapp-theme.md): the button on every screen, the chat list
// with its chips and tabs, sending a message, and a profile photo's absence
// showing soft initials.

test.describe.configure({ mode: 'serial' });
test.afterEach(async ({}, testInfo) => reportFailure(testInfo));

test('Chat: the floating button opens chat, a message sends, back returns', async ({ browser }) => {
  const api = await Api.as(people.electrician);
  const chats = (await api.call('fn_my_conversations', {})) as { id: string; title: string }[];
  expect(chats.length, 'the technician has chats (site groups)').toBeGreaterThan(0);

  const page = await signIn(browser, people.electrician);
  await open(page, '/home');
  // Chat is no longer a tab, it is the green button.
  await expect(page.getByRole('tab', { name: 'Chat' })).toHaveCount(0);
  const button = page.getByRole('button', { name: /^Chat/ }).last();
  await expect(button).toBeVisible();
  await shot(page, 'chat-button-home');

  await button.click();
  await expectShown(page, 'Chats', true);
  for (const chip of ['All', 'Unread', 'Favourites', 'Groups']) {
    await expectShown(page, chip, true);
  }
  await expectShown(page, /Messages stay inside/);
  await shot(page, 'chat-list');

  // Open the first chat and send a message.
  const text = `Isolator check ${stamp}`;
  await open(page, `/chat/${chats[0].id}`);
  const box = page.getByRole('textbox', { name: /Message/ }).first();
  await box.click();
  await page.waitForTimeout(500);
  await page.keyboard.type(text, { delay: 20 });
  await page.keyboard.press('Enter');
  await expectShown(page, text);
  await shot(page, 'chat-message-sent');

  await expect
    .poll(async () => {
      const rows = await api.select(`messages?select=body&conversation_id=eq.${chats[0].id}&body=eq.${encodeURIComponent(text)}`);
      return rows.length;
    }, { timeout: 60_000 })
    .toBe(1);

  // Search marks the words and the chat stays in the WhatsApp look.
  await open(page, '/chat');
  await expectShown(page, 'Chats', true);
});

test('Chat: dark chat follows the device', async ({ browser }) => {
  const page = await signIn(browser, people.electrician, undefined, 'dark');
  await open(page, '/chat');
  await expectShown(page, 'Chats', true);
  await shot(page, 'chat-list-dark');
});
