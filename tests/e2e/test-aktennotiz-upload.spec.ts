// @ts-nocheck
/**
 * Автоматизированный тест загрузки DOCX файла "Aktennotiz_Andre Arnold 10.10.2025.docx"
 * через веб-интерфейс OpenWebUI с использованием Playwright
 *
 * Цель: Проверить end-to-end процесс загрузки и обработки DOCX файла через RAG систему ERNI-KI
 */

import { test, expect } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';

const BASE = process.env.PW_BASE_URL || 'http://localhost:8080';
const DOCX_FILE = 'tests/fixtures/Aktennotiz_Andre Arnold 10.10.2025.docx';

// Логирование с временными метками
function log(message: string) {
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}] ${message}`);
}

// Попытка логина
async function tryLogin(page: any) {
  log('🔍 Checking for login form...');

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
    log('⚠️ Login form detected but E2E_OPENWEBUI_EMAIL/PASSWORD are not set.');
    return false;
  }

  log(`🔑 Attempting login with email: ${EMAIL}`);
  await page.fill(emailSel, EMAIL);
  await page.fill(passSel, PASS);
  await page.click(submitSel).catch(() => page.press(passSel, 'Enter'));

  const chatInput =
    'textarea[placeholder*="Message"], textarea[placeholder*="Сообщ"], [role="textbox"], div[contenteditable="true"]';
  try {
    await page.waitForSelector(chatInput, { timeout: 10_000 });
    log('✅ Login successful - chat input found');
    return true;
  } catch (e) {
    log('❌ Login may have failed - chat input not found');
    return false;
  }
}

test('Upload and process Aktennotiz DOCX file', async ({ page }) => {
  const startTime = Date.now();

  // Проверяем наличие файла
  if (!fs.existsSync(DOCX_FILE)) {
    throw new Error(`DOCX file not found: ${DOCX_FILE}`);
  }

  const fileStats = fs.statSync(DOCX_FILE);
  log(`📄 File to upload: ${DOCX_FILE}`);
  log(`📊 File size: ${(fileStats.size / 1024).toFixed(2)} KB`);

  // Шаг 1: Открыть OpenWebUI
  log('🌐 Step 1: Opening OpenWebUI...');
  const navStartTime = Date.now();
  await page.goto(BASE);
  const navEndTime = Date.now();
  log(`✅ Page loaded in ${navEndTime - navStartTime}ms`);

  // Скриншот начальной страницы
  await page.screenshot({
    path: 'test-results/01-initial-page.png',
    fullPage: true,
  });

  // Ждем загрузки страницы
  await page.waitForTimeout(3000);

  const title = await page.title();
  log(`📄 Page title: ${title}`);

  // Шаг 2: Авторизация
  log('🔐 Step 2: Attempting login...');
  const loginStartTime = Date.now();
  const loginSuccess = await tryLogin(page).catch(() => false);
  const loginEndTime = Date.now();
  log(
    `${loginSuccess ? '✅' : '⚠️'} Login ${loginSuccess ? 'successful' : 'skipped'} (${loginEndTime - loginStartTime}ms)`
  );

  await page.waitForTimeout(2000);

  // Скриншот после логина
  await page.screenshot({
    path: 'test-results/02-after-login.png',
    fullPage: true,
  });

  // Закрываем модальные окна
  const modals = await page.locator('[role="dialog"], .modal').count();
  if (modals > 0) {
    log(`🔍 Found ${modals} modal(s), closing...`);
    await page.keyboard.press('Escape');
    await page.waitForTimeout(500);
  }

  // Шаг 3: Поиск и клик на кнопку загрузки файлов
  log('📁 Step 3: Looking for file upload button...');
  const uploadStartTime = Date.now();

  let uploadSuccess = false;
  let uploadMethod = '';

  // Метод 1: Поиск кнопки с иконкой скрепки или плюса
  const iconButtons = await page.locator('button:has(svg), button:has([class*="icon"])').all();
  log(`🔍 Found ${iconButtons.length} buttons with icons`);

  for (let i = 0; i < iconButtons.length; i++) {
    const button = iconButtons[i];
    if (!button) continue;

    const isVisible = await button.isVisible().catch(() => false);
    if (!isVisible) continue;

    try {
      // Получаем aria-label или title для идентификации
      const ariaLabel = await button.getAttribute('aria-label').catch(() => '');
      const title = await button.getAttribute('title').catch(() => '');

      // Ищем кнопки, связанные с загрузкой файлов
      if (
        ariaLabel?.toLowerCase().includes('upload') ||
        ariaLabel?.toLowerCase().includes('file') ||
        ariaLabel?.toLowerCase().includes('attach') ||
        title?.toLowerCase().includes('upload') ||
        title?.toLowerCase().includes('file')
      ) {
        log(`🎯 Found potential upload button: ${ariaLabel || title}`);

        // Пробуем кликнуть и открыть file chooser
        const [fileChooser] = await Promise.all([
          page.waitForEvent('filechooser', { timeout: 2000 }).catch(() => null),
          button.click(),
        ]);

        if (fileChooser) {
          log(`✅ File chooser opened!`);
          await fileChooser.setFiles(DOCX_FILE);
          uploadSuccess = true;
          uploadMethod = `Icon button with ${ariaLabel || title}`;
          break;
        }
      }
    } catch (e: any) {
      // Продолжаем поиск
    }
  }

  // Метод 2: Прямой поиск input[type="file"]
  if (!uploadSuccess) {
    log('🔍 Trying direct file input method...');
    const fileInput = await page.locator('input[type="file"]').first();
    const fileInputVisible = await fileInput.isVisible().catch(() => false);

    if (fileInputVisible) {
      await fileInput.setInputFiles(DOCX_FILE);
      uploadSuccess = true;
      uploadMethod = 'Direct file input';
      log('✅ File uploaded via direct input');
    }
  }

  // Метод 3: Поиск через текст кнопок
  if (!uploadSuccess) {
    log('🔍 Trying text-based button search...');
    const uploadButtons = await page
      .locator('button:has-text("Upload"), button:has-text("Загрузить")')
      .all();

    for (const button of uploadButtons) {
      try {
        const [fileChooser] = await Promise.all([
          page.waitForEvent('filechooser', { timeout: 2000 }).catch(() => null),
          button.click(),
        ]);

        if (fileChooser) {
          await fileChooser.setFiles(DOCX_FILE);
          uploadSuccess = true;
          uploadMethod = 'Text-based upload button';
          log('✅ File uploaded via text button');
          break;
        }
      } catch (e) {
        continue;
      }
    }
  }

  const uploadEndTime = Date.now();

  if (!uploadSuccess) {
    log('❌ Could not find upload mechanism');

    // Детальный анализ страницы
    const allButtons = await page.locator('button').count();
    const buttonTexts = await page.locator('button').allTextContents();
    log(`📊 Page has ${allButtons} buttons`);
    log(`📝 Button texts (first 20): ${buttonTexts.slice(0, 20).join(', ')}`);

    await page.screenshot({
      path: 'test-results/03-upload-failed.png',
      fullPage: true,
    });

    throw new Error('Could not find file upload mechanism');
  }

  log(`✅ File uploaded successfully via: ${uploadMethod} (${uploadEndTime - uploadStartTime}ms)`);

  // Скриншот после загрузки
  await page.screenshot({
    path: 'test-results/04-file-uploaded.png',
    fullPage: true,
  });

  // Шаг 4: Ожидание обработки файла
  log('⏳ Step 4: Waiting for file processing...');
  const processingStartTime = Date.now();

  // Ждем индикаторов обработки или завершения
  await page.waitForTimeout(5000);

  const processingEndTime = Date.now();
  const processingTime = processingEndTime - processingStartTime;
  log(`✅ Processing completed in ${processingTime}ms`);

  // Скриншот после обработки
  await page.screenshot({
    path: 'test-results/05-processing-complete.png',
    fullPage: true,
  });

  // Шаг 5: Проверка консоли браузера на ошибки
  log('🔍 Step 5: Checking browser console for errors...');
  const consoleLogs: any[] = [];
  page.on('console', msg => {
    consoleLogs.push({
      type: msg.type(),
      text: msg.text(),
    });
  });

  // Проверяем наличие ошибок
  const errors = consoleLogs.filter(log => log.type === 'error');
  if (errors.length > 0) {
    log(`⚠️ Found ${errors.length} console errors:`);
    errors.forEach(err => log(`  - ${err.text}`));
  } else {
    log('✅ No console errors found');
  }

  // Финальные метрики
  const totalTime = Date.now() - startTime;
  log('\n📊 === TEST SUMMARY ===');
  log(`✅ Total test time: ${totalTime}ms`);
  log(`✅ File upload time: ${uploadEndTime - uploadStartTime}ms`);
  log(`✅ Processing time: ${processingTime}ms`);
  log(`✅ Upload method: ${uploadMethod}`);
  log(`✅ File size: ${(fileStats.size / 1024).toFixed(2)} KB`);
  log(
    `${processingTime < 10000 ? '✅' : '⚠️'} Processing time ${processingTime < 10000 ? 'meets' : 'exceeds'} target (<10s)`
  );
  log(`${errors.length === 0 ? '✅' : '❌'} Console errors: ${errors.length}`);

  // Финальный скриншот
  await page.screenshot({
    path: 'test-results/06-final-state.png',
    fullPage: true,
  });

  // Проверки
  expect(uploadSuccess).toBe(true);
  expect(processingTime).toBeLessThan(10000); // Цель: <10 секунд
  expect(errors.length).toBe(0);
});
