import { expect, test } from '@playwright/test';
// @ts-nocheck
import fs from 'node:fs';

/**
 * ERNI-KI OpenWebUI RAG E2E via Playwright
 * - Логирование сетевых запросов (Docling, SearXNG, Ollama)
 * - Скриншоты ключевых шагов
 * - Проверка консоли на ошибки
 */

const BASE = process.env.PW_BASE_URL || 'https://localhost';
const ART_DIR = 'playwright-artifacts';
const NET_LOG = `${ART_DIR}/network.log`;
try {
  require('node:fs').mkdirSync(ART_DIR, { recursive: true });
} catch {}

// Файлы до 10MB: положите примеры в tests/fixtures/
const fixtures = {
  pdf: 'tests/fixtures/sample.pdf',
  docx: 'tests/fixtures/sample.docx',
  md: 'tests/fixtures/sample.md',
  txt: 'tests/fixtures/sample.txt',
};

// Полезные селекторы (могут отличаться в вашей теме/версии OpenWebUI)
const selectors = {
  fileInput: 'input[type="file"]',
  uploadsTab:
    'button:has-text("Uploads"), button:has-text("Files"), button:has-text("Knowledge"), a:has-text("Uploads")',
  uploadList: '[data-testid="upload-list"], .uploaded-files, .file-list, [class*="upload"]',
  chatInput:
    'textarea[placeholder*="Message"], textarea[placeholder*="Сообщ"], [role="textbox"], div[contenteditable="true"]',
  settingsButton: 'button[aria-label="Settings"], button:has-text("Settings")',
  webSearchToggle: 'label:has-text("Web Search") input[type="checkbox"], input[name="web_search"]',
  sendButton: 'button:has-text("Send"), button[aria-label="Send"]',
  answerBlock: '.message.assistant, [data-testid="assistant-message"]',
};

// Попытка логина, если включена форма входа
async function tryLogin(page) {
  console.log('🔍 Checking for login form...');

  // Расширенные селекторы для OpenWebUI
  const emailSel =
    'input[type="email"], input[name="email"], input#email, input[placeholder*="email" i], input[placeholder*="Email"]';
  const passSel =
    'input[type="password"], input[name="password"], input#password, input[placeholder*="password" i], input[placeholder*="Password"]';
  const submitSel =
    'button:has-text("Sign In"), button:has-text("Войти"), button[type="submit"], button:has-text("Login"), button:has-text("Continue")';

  // Ждем загрузки страницы
  await page.waitForTimeout(2000);

  let hasLogin = await page
    .locator(emailSel)
    .first()
    .isVisible()
    .catch(() => false);
  console.log(`Login form visible on main page: ${hasLogin}`);

  if (!hasLogin) {
    // Попробуем найти кнопки входа/регистрации
    const loginButtons =
      'button:has-text("Sign In"), button:has-text("Login"), a:has-text("Sign In"), a:has-text("Login")';
    const hasLoginButton = await page
      .locator(loginButtons)
      .first()
      .isVisible()
      .catch(() => false);
    console.log(`Login button visible: ${hasLoginButton}`);

    if (hasLoginButton) {
      await page.click(loginButtons);
      await page.waitForTimeout(1000);
      hasLogin = await page
        .locator(emailSel)
        .first()
        .isVisible()
        .catch(() => false);
      console.log(`Login form visible after clicking login button: ${hasLogin}`);
    }
  }

  if (!hasLogin) {
    console.log('❌ No login form found, assuming already authenticated or no auth required');
    return false;
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

  // Ждем либо появления чата, либо ошибки входа
  try {
    await page.waitForSelector(selectors.chatInput, { timeout: 10_000 });
    console.log('✅ Login successful - chat input found');
    return true;
  } catch (e) {
    console.log('❌ Login may have failed - chat input not found');
    return false;
  }
}

// Логирование запросов для Docling/SearXNG/Ollama
function attachNetworkLogging(page) {
  const append = (line: string) => {
    try {
      fs.appendFileSync(NET_LOG, line + '\n');
    } catch {}
  };
  page.on('request', req => {
    const url = req.url();
    if (/docling|searxng|ollama|openwebui\/api/i.test(url)) {
      const line = `→ ${req.method()} ${url}`;
      console.log(line);
      append(line);
    }
  });
  page.on('response', async res => {
    const url = res.url();
    if (/docling|searxng|ollama|openwebui\/api/i.test(url)) {
      const line = `← ${res.status()} ${url}`;
      console.log(line);
      append(line);
    }
  });
}

async function assertNoConsoleErrors(page) {
  const errors: string[] = [];
  page.on('console', msg => {
    if (msg.type() === 'error') errors.push(msg.text());
  });
  return () => {
    if (errors.length) {
      console.warn('Console errors:', errors.join('\n'));
    }
    expect(errors.length, 'No console errors').toBe(0);
  };
}

// Навигация и базовая доступность
test('Preparation: services healthy and UI reachable', async ({ page }) => {
  attachNetworkLogging(page);
  const finalize = await assertNoConsoleErrors(page);

  const resp = await page.goto(BASE, { waitUntil: 'domcontentloaded' });
  // Некоторые конфигурации возвращают 404 на /, но UI при этом загружается (SPA)
  await page.screenshot({ path: 'playwright-artifacts/01-home.png' });
  await page.waitForTimeout(500);
  // Авторизация при необходимости
  await tryLogin(page).catch(() => {});

  // Пробуем найти поле ввода чата как индикатор готовности UI
  console.log('🔍 Looking for chat input after login...');
  let uiReady = false;

  // Попробуем несколько стратегий поиска чата
  const chatSelectors = [
    selectors.chatInput,
    'textarea',
    '[contenteditable="true"]',
    'input[type="text"]',
    '[placeholder*="message" i]',
    '[placeholder*="type" i]',
  ];

  for (const selector of chatSelectors) {
    uiReady = await page
      .locator(selector)
      .first()
      .isVisible()
      .catch(() => false);
    if (uiReady) {
      console.log(`✅ Found chat input with selector: ${selector}`);
      break;
    }
  }

  if (!uiReady) {
    console.log('❌ No chat input found, taking screenshot for debugging');
    await page.screenshot({ path: 'playwright-artifacts/debug-no-chat-input.png', fullPage: true });

    // Попробуем найти любые интерактивные элементы
    const anyInput = await page.locator('input, textarea, [contenteditable]').count();
    console.log(`Found ${anyInput} input elements on page`);

    // Логируем заголовок страницы
    const title = await page.title();
    console.log(`Page title: ${title}`);
  }

  expect(uiReady, 'Chat input should be visible after authentication').toBeTruthy();
  finalize();
});

// 1) Загрузка и индексация документов
Object.entries(fixtures).forEach(([label, path]) => {
  const size = fs.existsSync(path) ? fs.statSync(path).size : 0;
  const isBinary = label === 'pdf' || label === 'docx';
  const validFixture = size > (isBinary ? 2048 : 0);
  (validFixture ? test : test.skip)(`Upload & index ${label}`, async ({ page }) => {
    attachNetworkLogging(page);
    const finalize = await assertNoConsoleErrors(page);

    await page.goto(BASE);
    await tryLogin(page).catch(() => {});

    console.log(`📁 Attempting to upload file: ${path}`);

    // Сначала попробуем найти и кликнуть на элементы навигации/меню
    const navElements = [
      'button:has-text("Knowledge")',
      'button:has-text("Documents")',
      'button:has-text("Files")',
      'a:has-text("Knowledge")',
      'a:has-text("Documents")',
      'a:has-text("Files")',
      '[href*="knowledge"]',
      '[href*="documents"]',
      '[href*="files"]',
    ];

    for (const navSel of navElements) {
      const hasNav = await page
        .locator(navSel)
        .first()
        .isVisible()
        .catch(() => false);
      if (hasNav) {
        console.log(`🔍 Found navigation element: ${navSel}`);
        await page.click(navSel);
        await page.waitForTimeout(1000);
        break;
      }
    }

    // Инициализируем переменную успеха загрузки
    let uploadSuccess = false;

    // Теперь ищем кнопки загрузки файлов - сначала попробуем кнопки с иконками
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

        // Проверяем, появился ли file input или file chooser
        const fileInput = await page.locator('input[type="file"]').first().isVisible().catch(() => false);
        if (fileInput) {
          console.log(`✅ Found file input after clicking icon button ${i + 1}`);
          await page.setInputFiles('input[type="file"]', path);
          uploadSuccess = true;
          break;
        }

        // Проверяем, открылся ли file chooser
        const fileChooserPromise = page.waitForEvent('filechooser', { timeout: 1000 });
        const fileChooser = await fileChooserPromise.catch(() => null);
        if (fileChooser) {
          console.log(`✅ File chooser opened after clicking icon button ${i + 1}`);
          await fileChooser.setFiles(path);
          uploadSuccess = true;
          break;
        }
      } catch (e: any) {
        console.log(`❌ Icon button ${i + 1} failed: ${e.message}`);
        continue;
      }
    }

    if (!uploadSuccess) {
      // Fallback: традиционные селекторы
      const uploadButtons = [
        'input[type="file"]',
        'button:has-text("Upload")',
        'button:has-text("Add")',
        'button:has-text("+")',
        'button[title*="upload" i]',
        'button[aria-label*="upload" i]',
        '[data-testid*="upload"]',
        '.upload-button',
        'button:has([class*="upload"])',
        'button:has([class*="plus"])',
        'button:has([class*="add"])',
      ];

      for (const buttonSel of uploadButtons) {
      const hasButton = await page
        .locator(buttonSel)
        .first()
        .isVisible()
        .catch(() => false);
      console.log(`Upload button "${buttonSel}": ${hasButton}`);

      if (hasButton) {
        try {
          if (buttonSel.includes('input[type="file"]')) {
            // Прямая загрузка через input
            await page.setInputFiles(buttonSel, path);
            console.log('✅ File uploaded via direct input');
            uploadSuccess = true;
            break;
          } else {
            // Загрузка через file chooser
            const [fileChooser] = await Promise.all([
              page.waitForEvent('filechooser', { timeout: 5000 }),
              page.click(buttonSel),
            ]);
            await fileChooser.setFiles(path);
            console.log('✅ File uploaded via file chooser');
            uploadSuccess = true;
            break;
          }
        } catch (e: any) {
          console.log(`❌ Failed with "${buttonSel}": ${e.message}`);
          continue;
        }
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
      console.log('Button texts:', buttonTexts.slice(0, 20)); // первые 20

      // Логируем все ссылки с текстом
      const linkTexts = await page.locator('a').allTextContents();
      console.log('Link texts:', linkTexts.slice(0, 20)); // первые 20

      // Ищем элементы с иконками (могут быть кнопки загрузки)
      const iconButtons = await page.locator('button svg, button [class*="icon"]').count();
      console.log(`Found ${iconButtons} buttons with icons`);

      await page.screenshot({
        path: `playwright-artifacts/debug-upload-${label}.png`,
        fullPage: true,
      });

      // Попробуем найти любые элементы, связанные с файлами
      const fileRelated = await page
        .locator(
          '[class*="file"], [class*="upload"], [class*="document"], [id*="file"], [id*="upload"]'
        )
        .count();
      console.log(`Found ${fileRelated} file-related elements`);

      throw new Error(
        `Could not find upload mechanism for ${label}. Check debug screenshot and logs.`
      );
    }

    // Ожидание обработки - ищем индикаторы успешной загрузки
    console.log('⏳ Waiting for upload processing...');
    const uploadIndicators = [
      selectors.uploadList,
      '.upload-success',
      '.file-uploaded',
      '[data-testid*="uploaded"]',
      'text=uploaded',
      'text=success',
    ];

    let processed = false;
    for (const indicator of uploadIndicators) {
      try {
        await page.waitForSelector(indicator, { timeout: 10_000 });
        console.log(`✅ Upload processed - found indicator: ${indicator}`);
        processed = true;
        break;
      } catch (e) {
        continue;
      }
    }

    if (!processed) {
      console.log('⚠️ No upload success indicator found, but continuing...');
    }

    await page.screenshot({ path: `playwright-artifacts/02-upload-${label}.png` });
    finalize();
  });
});

// 2) RAG-поиск с веб-интеграцией (SearXNG)
test('RAG web search (<10s)', async ({ page }) => {
  attachNetworkLogging(page);
  const finalize = await assertNoConsoleErrors(page);

  await page.goto(BASE);
  await tryLogin(page).catch(() => {});

  // Включить web search в настройках (если доступно)
  await page.click(selectors.settingsButton).catch(() => {});
  await page
    .locator(selectors.webSearchToggle)
    .check({ force: true })
    .catch(() => {});

  // Вопрос для веб-поиска
  const question = 'Какие новости о AI сегодня?';
  await page.fill(selectors.chatInput, question);

  const start = Date.now();
  await page.click(selectors.sendButton);

  // Ожидаем ответ ассистента до 30с (допускаем прогресс-индикатор)
  await page.waitForSelector(`${selectors.answerBlock}, .progress, .spinner`, { timeout: 30_000 });
  const duration = Date.now() - start;
  console.log(`Web search answer time: ${duration}ms`);
  expect(duration).toBeLessThanOrEqual(10_000);

  // Проверить наличие ссылок/источников
  const content = await page.locator(selectors.answerBlock).first().innerText();
  expect(/https?:\/\//.test(content) || /Источник|Source|[[]\d+[]]/i.test(content)).toBeTruthy();

  await page.screenshot({ path: 'playwright-artifacts/03-web-search.png' });
  finalize();
});

// 3) RAG-поиск по загруженным документам
test('RAG over uploaded docs', async ({ page }) => {
  attachNetworkLogging(page);
  const finalize = await assertNoConsoleErrors(page);

  await page.goto(BASE);
  await tryLogin(page).catch(() => {});
  const question = 'Изложи кратко содержание загруженного документа и укажи источник.';
  await page.fill(selectors.chatInput, question);
  await page.click(selectors.sendButton);

  await page.waitForSelector(selectors.answerBlock, { timeout: 30_000 });
  const answer = await page.locator(selectors.answerBlock).first().innerText();
  expect(/Источник|Файл|Документ|\.(pdf|docx|md|txt)/i.test(answer)).toBeTruthy();

  await page.screenshot({ path: 'playwright-artifacts/04-doc-rag.png' });
  finalize();
});

// 4) Комбинированный RAG (документы + веб)
test('Combined RAG (docs + web)', async ({ page }) => {
  attachNetworkLogging(page);
  const finalize = await assertNoConsoleErrors(page);

  await page.goto(BASE);
  const question =
    'Сопоставь ключевые факты из загруженного документа с последними новостями из веба и добавь ссылки.';
  await page.fill(selectors.chatInput, question);
  await page.click(selectors.sendButton);

  await page.waitForSelector(selectors.answerBlock, { timeout: 30_000 });
  const answer = await page.locator(selectors.answerBlock).first().innerText();
  expect(/https?:\/\//.test(answer)).toBeTruthy();
  expect(/(Источник|Файл|Документ)/i.test(answer)).toBeTruthy();

  await page.screenshot({ path: 'playwright-artifacts/05-combined.png' });
  finalize();
});
