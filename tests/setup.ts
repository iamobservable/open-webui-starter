// Глобальная настройка тестов для проекта erni-ki
import { afterAll, afterEach, beforeAll, beforeEach, vi } from 'vitest';

import testUtils from './utils/test-utils';

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
globalThis.testUtils = testUtils;

// Настройка fetch для тестов (если нужно)
global.fetch = vi.fn();

// Настройка для работы с таймерами
vi.useFakeTimers();

export {};
