import { defineConfig } from '@playwright/test';

// The app must be built first with --dart-define=E2E=true pointing at the
// local Supabase (see .github/workflows/acceptance.yml). Tests share one
// seeded database, so they run in order in a single worker.
export default defineConfig({
  testDir: './tests',
  outputDir: process.env.E2E_OUTPUT_DIR ?? 'test-results',
  timeout: 240_000,
  expect: { timeout: 30_000 },
  fullyParallel: false,
  workers: 1,
  retries: 0,
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL: 'http://127.0.0.1:8091',
    // Tall enough that long forms fit without scrolling the Flutter canvas.
    viewport: { width: 1440, height: 2400 },
    actionTimeout: 30_000,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  webServer: {
    command: 'node serve.mjs ../app/build/web 8091',
    url: 'http://127.0.0.1:8091',
    reuseExistingServer: false,
  },
});
