// Глобальная настройка тестов для проекта erni-ki
import { afterAll, afterEach, beforeAll, beforeEach, vi } from 'vitest';

// Сохраняем оригинальные методы консоли
const originalConsoleLog = console.log;
const originalConsoleWarn = console.warn;
const originalConsoleError = console.error;

// Настройка переменных окружения для тестов
beforeAll(() => {
  // Устанавливаем тестовые переменные окружения
  process.env.NODE_ENV = 'test';
  process.env.JWT_SECRET = 'test-jwt-secret-key-for-testing-only';
  process.env.WEBUI_SECRET_KEY = 'test-webui-secret-key-for-testing-only';
  process.env.DATABASE_URL = 'postgresql://test:test@localhost:5432/test_db';
  process.env.REDIS_URL = 'redis://localhost:6379/1';

  // Отключаем логирование в тестах
  console.log = () => {};
  console.warn = () => {};
  console.error = () => {};
});

// Очистка после всех тестов
afterAll(() => {
  // Восстанавливаем оригинальные методы консоли
  console.log = originalConsoleLog;
  console.warn = originalConsoleWarn;
  console.error = originalConsoleError;
});

// Настройка перед каждым тестом
beforeEach(() => {
  // Очищаем все моки
  vi.clearAllMocks();

  // Сбрасываем состояние модулей
  vi.resetModules();
});

// Очистка после каждого теста
afterEach(() => {
  // Восстанавливаем все моки
  vi.restoreAllMocks();
});

// Глобальные утилиты для тестов
declare global {
  var testUtils: {
    createMockRequest: (options?: any) => any;
    createMockResponse: (options?: any) => any;
    waitFor: (fn: () => boolean, timeout?: number) => Promise<void>;
    sleep: (ms: number) => Promise<void>;
  };
}

// Утилиты для создания мок-объектов
globalThis.testUtils = {
  // Создание мок-запроса
  createMockRequest: (options = {}) => ({
    headers: {},
    query: {},
    params: {},
    body: {},
    cookies: {},
    method: 'GET',
    url: '/',
    ...options,
  }),

  // Создание мок-ответа
  createMockResponse: (options = {}) => {
    const res = {
      status: vi.fn().mockReturnThis(),
      json: vi.fn().mockReturnThis(),
      send: vi.fn().mockReturnThis(),
      cookie: vi.fn().mockReturnThis(),
      header: vi.fn().mockReturnThis(),
      redirect: vi.fn().mockReturnThis(),
      end: vi.fn().mockReturnThis(),
      statusCode: 200,
      ...options,
    };
    return res;
  },

  // Ожидание выполнения условия
  waitFor: async (fn: () => boolean, timeout = 5000) => {
    const start = Date.now();
    while (Date.now() - start < timeout) {
      if (fn()) return;
      await new Promise(resolve => setTimeout(resolve, 10));
    }
    throw new Error(`Timeout waiting for condition after ${timeout}ms`);
  },

  // Простая задержка
  sleep: (ms: number) => new Promise(resolve => setTimeout(resolve, ms)),
};

// Настройка fetch для тестов (если нужно)
global.fetch = vi.fn();

// Настройка для работы с таймерами
vi.useFakeTimers();

export {};
