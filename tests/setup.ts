// Глобальная настройка тестов для проекта erni-ki
import { afterAll, afterEach, beforeAll, beforeEach, vi } from 'vitest';
import type { MockRequest, MockResponse, WaitForPredicate } from '../types/global';

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
    createMockRequest: <
      TBody = Record<string, unknown>,
      TQuery = Record<string, string | string[] | undefined>,
      TParams = Record<string, string>,
    >(
      options?: Partial<MockRequest<TBody, TQuery, TParams>>
    ) => MockRequest<TBody, TQuery, TParams>;
    createMockResponse: <TBody = unknown>(
      options?: Partial<MockResponse<TBody>>
    ) => MockResponse<TBody>;
    waitFor: (fn: WaitForPredicate, timeout?: number) => Promise<void>;
    sleep: (ms: number) => Promise<void>;
  };
}

// Утилиты для создания мок-объектов
globalThis.testUtils = {
  // Создание мок-запроса
  createMockRequest: <
    TBody = Record<string, unknown>,
    TQuery = Record<string, string | string[] | undefined>,
    TParams = Record<string, string>,
  >(
    options: Partial<MockRequest<TBody, TQuery, TParams>> = {}
  ): MockRequest<TBody, TQuery, TParams> => ({
    headers: {},
    query: {} as TQuery,
    params: {} as TParams,
    body: {} as TBody,
    cookies: {},
    method: 'GET',
    url: '/',
    ...options,
  }),

  // Создание мок-ответа
  createMockResponse: <TBody = unknown>(
    options: Partial<MockResponse<TBody>> = {}
  ): MockResponse<TBody> => {
    const res = {} as MockResponse<TBody>;
    res.statusCode = 200;
    res.status = vi.fn().mockImplementation((code: number) => {
      res.statusCode = code;
      return res;
    });
    res.json = vi.fn().mockImplementation(() => res);
    res.send = vi.fn().mockImplementation(() => res);
    res.cookie = vi.fn().mockImplementation(() => res);
    res.header = vi.fn().mockImplementation(() => res);
    res.redirect = vi.fn().mockImplementation(() => res);
    res.end = vi.fn().mockImplementation(() => res);

    return Object.assign(res, options);
  },

  // Ожидание выполнения условия
  waitFor: async (fn: WaitForPredicate, timeout = 5000) => {
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
