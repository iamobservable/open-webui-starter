/**
 * ERNI-KI AI Models Diagnostics with Playwright
 * Комплексная диагностика функционала AI моделей
 *
 * @author Альтэон Шульц (Tech Lead)
 * @version 1.0.0
 */

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

// Конфигурация тестирования
const CONFIG = {
  baseUrl: 'http://localhost:8080',
  timeout: 30000,
  screenshotsDir: './test-results/screenshots',
  reportsDir: './test-results/reports',
  expectedModels: ['gpt-oss:20b', 'gemma3n:e4b', 'nomic-embed-text:latest'],
  testPrompts: [
    'Привет! Как дела?',
    'Расскажи о квантовой физике в двух предложениях.',
    'Найди информацию о последних новостях в области AI',
  ],
  maxResponseTime: 5000, // 5 секунд
  ragTestQuery: 'Найди последние новости о искусственном интеллекте',
};

class AIModelsDiagnostics {
  constructor() {
    this.browser = null;
    this.page = null;
    this.results = {
      timestamp: new Date().toISOString(),
      systemStatus: {},
      modelTests: [],
      performanceMetrics: {},
      ragTests: [],
      errors: [],
      recommendations: [],
    };

    // Создание директорий для результатов
    this.ensureDirectories();
  }

  ensureDirectories() {
    [CONFIG.screenshotsDir, CONFIG.reportsDir].forEach(dir => {
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }
    });
  }

  async initialize() {
    console.log('🚀 Инициализация Playwright браузера...');

    this.browser = await chromium.launch({
      headless: false, // Показывать браузер для отладки
      slowMo: 1000, // Замедление для наблюдения
      args: ['--no-sandbox', '--disable-setuid-sandbox'],
    });

    this.page = await this.browser.newPage();

    // Настройка таймаутов
    this.page.setDefaultTimeout(CONFIG.timeout);

    // Перехват консольных сообщений
    this.page.on('console', msg => {
      if (msg.type() === 'error') {
        this.results.errors.push({
          type: 'console_error',
          message: msg.text(),
          timestamp: new Date().toISOString(),
        });
      }
    });

    console.log('✅ Браузер инициализирован');
  }

  async navigateToOpenWebUI() {
    console.log('🌐 Переход к OpenWebUI...');

    try {
      await this.page.goto(CONFIG.baseUrl, { waitUntil: 'networkidle' });

      // Скриншот главной страницы
      await this.takeScreenshot('01-main-page');

      // Проверка загрузки страницы
      const title = await this.page.title();
      console.log(`📄 Заголовок страницы: ${title}`);

      this.results.systemStatus.webUIAccessible = true;
      this.results.systemStatus.pageTitle = title;
    } catch (error) {
      this.results.errors.push({
        type: 'navigation_error',
        message: error.message,
        timestamp: new Date().toISOString(),
      });
      throw error;
    }
  }

  async checkAvailableModels() {
    console.log('🤖 Проверка доступных моделей...');

    try {
      // Ожидание загрузки интерфейса
      await this.page.waitForSelector('[data-testid="model-selector"], .model-selector, select', {
        timeout: 10000,
      });

      // Поиск селектора моделей (различные варианты)
      const modelSelectors = [
        '[data-testid="model-selector"]',
        '.model-selector',
        'select[name*="model"]',
        'button[aria-label*="model"]',
        '.dropdown-toggle',
      ];

      let modelSelector = null;
      for (const selector of modelSelectors) {
        const element = await this.page.$(selector);
        if (element) {
          modelSelector = selector;
          break;
        }
      }

      if (!modelSelector) {
        throw new Error('Селектор моделей не найден');
      }

      // Клик по селектору моделей
      await this.page.click(modelSelector);
      await this.page.waitForTimeout(2000);

      // Скриншот списка моделей
      await this.takeScreenshot('02-models-list');

      // Получение списка доступных моделей
      const models = await this.page.$$eval('option, .dropdown-item, [role="option"]', elements =>
        elements.map(el => el.textContent?.trim()).filter(Boolean),
      );

      console.log(`📋 Найдено моделей: ${models.length}`);
      models.forEach(model => console.log(`  - ${model}`));

      this.results.systemStatus.availableModels = models;
      this.results.systemStatus.modelsCount = models.length;

      // Проверка ожидаемых моделей
      const missingModels = CONFIG.expectedModels.filter(
        expected => !models.some(available => available.includes(expected.split(':')[0])),
      );

      if (missingModels.length > 0) {
        this.results.errors.push({
          type: 'missing_models',
          message: `Отсутствуют модели: ${missingModels.join(', ')}`,
          timestamp: new Date().toISOString(),
        });
      }
    } catch (error) {
      this.results.errors.push({
        type: 'models_check_error',
        message: error.message,
        timestamp: new Date().toISOString(),
      });
      console.error('❌ Ошибка при проверке моделей:', error.message);
    }
  }

  async testTextGeneration() {
    console.log('✍️ Тестирование генерации текста...');

    for (const prompt of CONFIG.testPrompts) {
      console.log(`📝 Тестирование промпта: "${prompt}"`);

      try {
        const startTime = Date.now();

        // Поиск поля ввода
        const inputSelectors = [
          'textarea[placeholder*="message"]',
          'textarea[placeholder*="сообщение"]',
          '.chat-input textarea',
          'input[type="text"]',
          '[contenteditable="true"]',
        ];

        let inputSelector = null;
        for (const selector of inputSelectors) {
          const element = await this.page.$(selector);
          if (element) {
            inputSelector = selector;
            break;
          }
        }

        if (!inputSelector) {
          throw new Error('Поле ввода не найдено');
        }

        // Ввод текста
        await this.page.fill(inputSelector, prompt);
        await this.page.waitForTimeout(1000);

        // Поиск кнопки отправки
        const sendSelectors = [
          'button[type="submit"]',
          'button[aria-label*="send"]',
          'button[aria-label*="отправить"]',
          '.send-button',
          '[data-testid="send-button"]',
        ];

        let sendButton = null;
        for (const selector of sendSelectors) {
          const element = await this.page.$(selector);
          if (element) {
            sendButton = selector;
            break;
          }
        }

        if (!sendButton) {
          // Попробовать Enter
          await this.page.press(inputSelector, 'Enter');
        } else {
          await this.page.click(sendButton);
        }

        // Ожидание ответа
        await this.page.waitForSelector('.message, .chat-message, .response', {
          timeout: CONFIG.maxResponseTime,
        });

        const responseTime = Date.now() - startTime;

        // Получение ответа
        const responses = await this.page.$$eval('.message, .chat-message, .response', elements =>
          elements.map(el => el.textContent?.trim()).filter(Boolean),
        );

        const lastResponse = responses[responses.length - 1];

        this.results.modelTests.push({
          prompt,
          response: lastResponse?.substring(0, 200) + '...',
          responseTime,
          success: true,
          timestamp: new Date().toISOString(),
        });

        console.log(`✅ Ответ получен за ${responseTime}ms`);

        // Скриншот диалога
        await this.takeScreenshot(`03-chat-${this.results.modelTests.length}`);

        await this.page.waitForTimeout(2000);
      } catch (error) {
        this.results.modelTests.push({
          prompt,
          response: null,
          responseTime: null,
          success: false,
          error: error.message,
          timestamp: new Date().toISOString(),
        });

        console.error(`❌ Ошибка при тестировании промпта "${prompt}":`, error.message);
      }
    }
  }

  async testRAGIntegration() {
    console.log('🔍 Тестирование RAG-интеграции...');

    try {
      // Поиск настроек RAG или веб-поиска
      const ragSelectors = [
        '[data-testid="web-search"]',
        '.web-search-toggle',
        'input[type="checkbox"][name*="search"]',
        'button[aria-label*="search"]',
      ];

      let ragToggle = null;
      for (const selector of ragSelectors) {
        const element = await this.page.$(selector);
        if (element) {
          ragToggle = selector;
          break;
        }
      }

      if (ragToggle) {
        await this.page.click(ragToggle);
        console.log('🔍 RAG/веб-поиск включен');
      }

      // Тестирование RAG запроса
      const startTime = Date.now();

      const inputSelector =
        'textarea[placeholder*="message"], textarea[placeholder*="сообщение"], .chat-input textarea';
      await this.page.fill(inputSelector, CONFIG.ragTestQuery);

      const sendButton = 'button[type="submit"], .send-button';
      await this.page.click(sendButton);

      // Ожидание ответа с источниками
      await this.page.waitForSelector('.message, .chat-message, .response', { timeout: 15000 });

      const responseTime = Date.now() - startTime;

      // Поиск источников
      const sources = await this.page.$$eval('.source, .citation, [href*="http"]', elements =>
        elements.map(el => el.textContent || el.href).filter(Boolean),
      );

      this.results.ragTests.push({
        query: CONFIG.ragTestQuery,
        responseTime,
        sourcesFound: sources.length,
        sources: sources.slice(0, 5), // Первые 5 источников
        success: true,
        timestamp: new Date().toISOString(),
      });

      console.log(`✅ RAG тест завершен. Найдено источников: ${sources.length}`);

      // Скриншот RAG ответа
      await this.takeScreenshot('04-rag-response');
    } catch (error) {
      this.results.ragTests.push({
        query: CONFIG.ragTestQuery,
        responseTime: null,
        sourcesFound: 0,
        sources: [],
        success: false,
        error: error.message,
        timestamp: new Date().toISOString(),
      });

      console.error('❌ Ошибка при тестировании RAG:', error.message);
    }
  }

  async takeScreenshot(name) {
    const filename = `${name}-${Date.now()}.png`;
    const filepath = path.join(CONFIG.screenshotsDir, filename);
    await this.page.screenshot({ path: filepath, fullPage: true });
    console.log(`📸 Скриншот сохранен: ${filename}`);
  }

  async generateReport() {
    console.log('📊 Генерация отчета...');

    // Расчет метрик производительности
    const successfulTests = this.results.modelTests.filter(test => test.success);
    const avgResponseTime =
      successfulTests.length > 0
        ? successfulTests.reduce((sum, test) => sum + test.responseTime, 0) / successfulTests.length
        : 0;

    this.results.performanceMetrics = {
      totalTests: this.results.modelTests.length,
      successfulTests: successfulTests.length,
      failedTests: this.results.modelTests.length - successfulTests.length,
      averageResponseTime: Math.round(avgResponseTime),
      ragTestsSuccessful: this.results.ragTests.filter(test => test.success).length,
      totalErrors: this.results.errors.length,
    };

    // Генерация рекомендаций
    this.generateRecommendations();

    // Сохранение отчета
    const reportPath = path.join(CONFIG.reportsDir, `ai-diagnostics-${Date.now()}.json`);
    fs.writeFileSync(reportPath, JSON.stringify(this.results, null, 2));

    console.log(`📋 Отчет сохранен: ${reportPath}`);

    // Вывод краткого отчета в консоль
    this.printSummary();
  }

  generateRecommendations() {
    const { performanceMetrics, errors } = this.results;

    if (performanceMetrics.averageResponseTime > CONFIG.maxResponseTime) {
      this.results.recommendations.push(
        'Время отклика превышает ожидаемое. Рекомендуется оптимизация GPU или модели.',
      );
    }

    if (performanceMetrics.failedTests > 0) {
      this.results.recommendations.push(
        'Обнаружены неудачные тесты. Проверьте логи Ollama и OpenWebUI.',
      );
    }

    if (errors.some(error => error.type === 'missing_models')) {
      this.results.recommendations.push(
        'Отсутствуют ожидаемые модели. Загрузите недостающие модели через Ollama.',
      );
    }

    if (this.results.ragTests.length === 0 || !this.results.ragTests.some(test => test.success)) {
      this.results.recommendations.push(
        'RAG-интеграция не работает. Проверьте SearXNG и настройки веб-поиска.',
      );
    }
  }

  printSummary() {
    console.log('\n' + '='.repeat(60));
    console.log('📊 КРАТКИЙ ОТЧЕТ ДИАГНОСТИКИ AI МОДЕЛЕЙ');
    console.log('='.repeat(60));

    const { systemStatus, performanceMetrics } = this.results;

    console.log(`🌐 OpenWebUI доступен: ${systemStatus.webUIAccessible ? '✅' : '❌'}`);
    console.log(`🤖 Доступно моделей: ${systemStatus.modelsCount || 0}`);
    console.log(
      `✅ Успешных тестов: ${performanceMetrics.successfulTests}/${performanceMetrics.totalTests}`,
    );
    console.log(`⏱️  Среднее время отклика: ${performanceMetrics.averageResponseTime}ms`);
    console.log(`🔍 RAG тесты: ${performanceMetrics.ragTestsSuccessful} успешных`);
    console.log(`❌ Всего ошибок: ${performanceMetrics.totalErrors}`);

    if (this.results.recommendations.length > 0) {
      console.log('\n📋 РЕКОМЕНДАЦИИ:');
      this.results.recommendations.forEach((rec, index) => {
        console.log(`${index + 1}. ${rec}`);
      });
    }

    console.log('\n' + '='.repeat(60));
  }

  async cleanup() {
    if (this.browser) {
      await this.browser.close();
      console.log('🧹 Браузер закрыт');
    }
  }

  async run() {
    try {
      await this.initialize();
      await this.navigateToOpenWebUI();
      await this.checkAvailableModels();
      await this.testTextGeneration();
      await this.testRAGIntegration();
      await this.generateReport();
    } catch (error) {
      console.error('💥 Критическая ошибка:', error.message);
      this.results.errors.push({
        type: 'critical_error',
        message: error.message,
        timestamp: new Date().toISOString(),
      });
    } finally {
      await this.cleanup();
    }
  }
}

// Запуск диагностики
if (require.main === module) {
  const diagnostics = new AIModelsDiagnostics();
  diagnostics.run().catch(console.error);
}

module.exports = AIModelsDiagnostics;
