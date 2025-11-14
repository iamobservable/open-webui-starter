import { Buffer } from 'node:buffer';
import { expect, test } from '@playwright/test';

const isMockMode = process.env.E2E_MOCK_MODE === 'true';

test.describe('Mock OpenWebUI smoke suite', () => {
  test.skip(!isMockMode, 'Mock suite запускается только при E2E_MOCK_MODE=true');

  test('отображает основные элементы интерфейса', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('textarea[placeholder*="Message" i]')).toBeVisible();
    await expect(page.getByRole('button', { name: /send/i })).toBeVisible();
    await expect(page.locator('input[type="file"]')).toBeVisible();
  });

  test('переключает web search и отправляет сообщение', async ({ page }) => {
    await page.goto('/');
    await page.getByRole('textbox').fill('Mock RAG test');
    await page.getByRole('button', { name: /send/i }).click();
    await page.getByRole('checkbox', { name: /web search/i }).check();
    await expect(page.locator('.message-log')).toContainText('Mock RAG test');
    await expect(page.locator('.message-log')).toContainText('Web search enabled');
  });

  test('обрабатывает загрузку файлов', async ({ page }) => {
    await page.goto('/');
    await page.locator('input[type="file"]').setInputFiles({
      name: 'mock.txt',
      mimeType: 'text/plain',
      buffer: Buffer.from('demo'),
    });
    await expect(page.locator('.message-log')).toContainText('Uploaded 1 file');
  });
});
