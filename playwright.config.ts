import { defineConfig, devices } from '@playwright/test';

// Playwright E2E config for ERNI-KI OpenWebUI RAG
// Рус: визуальные тесты (headless: false), расширенные таймауты и артефакты

const baseURL = process.env.PW_FORCE_HOST
  ? `https://${process.env.PW_FORCE_HOST}`
  : process.env.PW_BASE_URL || 'https://localhost';

const launchArgs: string[] = [];
if (process.env.PW_SNI_HOST && process.env.PW_SNI_IP) {
  // Принудительное SNI + резолв домена на нужный IP
  launchArgs.push(`--host-resolver-rules=MAP ${process.env.PW_SNI_HOST} ${process.env.PW_SNI_IP}`);
}

export default defineConfig({
  testDir: 'tests/e2e',
  fullyParallel: false,
  timeout: 90_000, // общий таймаут теста
  expect: {
    timeout: 30_000, // ожидание ответов/элементов
  },
  reporter: [['list'], ['html', { outputFolder: 'playwright-report', open: 'never' }]],
  use: {
    baseURL,
    headless: false, // визуальный контроль
    ignoreHTTPSErrors: true, // self-signed TLS
    actionTimeout: 15_000,
    navigationTimeout: 20_000,
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
