// @ts-nocheck
import { test } from '@playwright/test';
import fs from 'node:fs';

const BASE = process.env.PW_BASE_URL || 'https://localhost';

// Попытка логина
async function tryLogin(page: any) {
  console.log('🔍 Checking for login form...');

  const emailSel = 'input[type="email"], input[name="email"], input#email';
  const passSel = 'input[type="password"], input[name="password"], input#password';
  const submitSel = 'button:has-text("Sign In"), button:has-text("Войти"), button[type="submit"]';

  let hasLogin = await page
    .locator(emailSel)
    .first()
    .isVisible()
    .catch(() => false);

  if (!hasLogin) {
    await page.goto(`${BASE}/login`).catch(() => {});
    hasLogin = await page
      .locator(emailSel)
      .first()
      .isVisible()
      .catch(() => false);
    if (!hasLogin) return false;
  }

  const EMAIL = process.env.E2E_OPENWEBUI_EMAIL || '';
  const PASS = process.env.E2E_OPENWEBUI_PASSWORD || '';
  if (!EMAIL || !PASS) {
    console.warn('⚠️ Login form detected but E2E_OPENWEBUI_EMAIL/PASSWORD are not set.');
    return false;
  }

  console.log(`🔑 Attempting login with email: ${EMAIL}`);
  await page.fill(emailSel, EMAIL);
  await page.fill(passSel, PASS);
  await page.click(submitSel).catch(() => page.press(passSel, 'Enter'));

  const chatInput =
    'textarea[placeholder*="Message"], textarea[placeholder*="Сообщ"], [role="textbox"], div[contenteditable="true"]';
  try {
    await page.waitForSelector(chatInput, { timeout: 10_000 });
    console.log('✅ Login successful - chat input found');
    return true;
  } catch (e) {
    console.log('❌ Login may have failed - chat input not found');
    return false;
  }
}

test('Upload file via icon buttons', async ({ page }) => {
  const path = 'tests/fixtures/sample.md';

  // Создаем тестовый файл если его нет
  if (!fs.existsSync(path)) {
    fs.mkdirSync('tests/fixtures', { recursive: true });
    fs.writeFileSync(path, '# Test Document\n\nThis is a test markdown file for upload testing.');
  }

  await page.goto(BASE);

  // Ждем загрузки страницы
  await page.waitForTimeout(3000);

  // Проверяем, что страница загрузилась
  const title = await page.title();
  console.log(`📄 Page title: ${title}`);

  const url = page.url();
  console.log(`🌐 Current URL: ${url}`);

  // Пытаемся войти
  const loginSuccess = await tryLogin(page).catch(() => false);
  console.log(`🔐 Login success: ${loginSuccess}`);

  // Ждем после логина
  await page.waitForTimeout(2000);

  // Проверяем URL после логина
  const urlAfterLogin = page.url();
  console.log(`🌐 URL after login: ${urlAfterLogin}`);

  // Закрываем любые модальные окна
  const modals = await page.locator('[role="dialog"], .modal').count();
  if (modals > 0) {
    console.log(`🔍 Found ${modals} modal(s), trying to close them...`);

    // Пробуем нажать Escape
    await page.keyboard.press('Escape');
    await page.waitForTimeout(500);

    // Пробуем кликнуть на кнопки закрытия
    const closeButtons = [
      'button:has-text("×")',
      'button:has-text("Close")',
      'button[aria-label="Close"]',
      '.modal button:last-child',
      '[role="dialog"] button:last-child',
    ];

    for (const closeSel of closeButtons) {
      const hasClose = await page
        .locator(closeSel)
        .first()
        .isVisible()
        .catch(() => false);
      if (hasClose) {
        await page.click(closeSel);
        await page.waitForTimeout(500);
        break;
      }
    }
  }

  console.log(`📁 Attempting to upload file: ${path}`);

  let uploadSuccess = false;

  // Ищем кнопки с иконками
  const iconButtons = await page.locator('button:has(svg), button:has([class*="icon"])').all();
  console.log(`🔍 Found ${iconButtons.length} buttons with icons, trying each one...`);

  for (let i = 0; i < iconButtons.length; i++) {
    const button = iconButtons[i];
    if (!button) continue;

    const isVisible = await button.isVisible().catch(() => false);
    if (!isVisible) continue;

    console.log(`Trying icon button ${i + 1}/${iconButtons.length}`);

    try {
      // Кликаем на кнопку с иконкой
      await button.click();
      await page.waitForTimeout(500);

      // Проверяем, появился ли file input
      const fileInput = await page
        .locator('input[type="file"]')
        .first()
        .isVisible()
        .catch(() => false);
      if (fileInput) {
        console.log(`✅ Found file input after clicking icon button ${i + 1}`);
        await page.setInputFiles('input[type="file"]', path);
        uploadSuccess = true;
        break;
      }

      // Проверяем, открылся ли file chooser
      try {
        const fileChooserPromise = page.waitForEvent('filechooser', { timeout: 1000 });
        const fileChooser = await fileChooserPromise;
        if (fileChooser) {
          console.log(`✅ File chooser opened after clicking icon button ${i + 1}`);
          await fileChooser.setFiles(path);
          uploadSuccess = true;
          break;
        }
      } catch (e) {
        // File chooser не открылся, продолжаем
      }
    } catch (e: any) {
      console.log(`❌ Icon button ${i + 1} failed: ${e.message}`);
      continue;
    }
  }

  if (!uploadSuccess) {
    console.log('❌ No upload method worked, analyzing page structure...');

    // Детальный анализ страницы
    const allButtons = await page.locator('button').count();
    const allInputs = await page.locator('input').count();
    const allLinks = await page.locator('a').count();

    console.log(`Page analysis: ${allButtons} buttons, ${allInputs} inputs, ${allLinks} links`);

    // Логируем все кнопки с текстом
    const buttonTexts = await page.locator('button').allTextContents();
    console.log('Button texts:', buttonTexts.slice(0, 20));

    await page.screenshot({
      path: `test-results/debug-upload-failed.png`,
      fullPage: true,
    });

    throw new Error(`Could not find upload mechanism. Check debug screenshot and logs.`);
  }

  console.log('✅ File upload successful!');

  // Ждем обработки файла
  await page.waitForTimeout(2000);

  await page.screenshot({
    path: `test-results/upload-success.png`,
    fullPage: true,
  });
});
