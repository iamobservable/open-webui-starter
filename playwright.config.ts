import { defineConfig, devices, type ReporterDescription } from '@playwright/test';

// Playwright E2E config for ERNI-KI OpenWebUI RAG
// Рус: визуальные тесты (headless: false), расширенные таймауты и артефакты

const baseURL = process.env.PW_FORCE_HOST
  ? `https://${process.env.PW_FORCE_HOST}`
  : (process.env.PW_BASE_URL ?? 'https://localhost');

const launchArgs: string[] = [];
if (process.env.PW_SNI_HOST && process.env.PW_SNI_IP) {
  // Принудительное SNI + резолв домена на нужный IP
  launchArgs.push(`--host-resolver-rules=MAP ${process.env.PW_SNI_HOST} ${process.env.PW_SNI_IP}`);
}

const mockMode = process.env.E2E_MOCK_MODE === 'true';
const headless =
  process.env.PLAYWRIGHT_HEADFUL === 'true' ? false : process.env.CI ? true : mockMode;
const testMatch = mockMode ? /mock-openwebui\.spec\.ts$/ : undefined;

const reporter: ReporterDescription[] = process.env.CI
  ? [['dot'], ['html', { outputFolder: 'playwright-report', open: 'never' }]]
  : [['list'], ['html', { outputFolder: 'playwright-report', open: 'never' }]];

export default defineConfig({
  testDir: 'tests/e2e',
  testMatch,
  fullyParallel: !mockMode,
  workers: mockMode ? 1 : undefined,
  timeout: mockMode ? 30_000 : 90_000,
  expect: {
    timeout: mockMode ? 10_000 : 30_000,
  },
  reporter,
  use: {
    baseURL,
    headless,
    ignoreHTTPSErrors: true, // self-signed TLS
    actionTimeout: mockMode ? 5_000 : 15_000,
    navigationTimeout: mockMode ? 10_000 : 20_000,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'], launchOptions: { args: launchArgs } },
    },
  ],
});
