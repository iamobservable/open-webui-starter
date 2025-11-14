import { defineConfig } from 'vitest/config';

export default defineConfig({
  // Настройки тестирования для проекта erni-ki
  test: {
    // Глобальные настройки
    globals: true,
    environment: 'node',

    // Покрытие кода - цель ≥90%
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html', 'lcov'],
      reportsDirectory: './coverage',
      // Показываем реальный layout (unit/integration + shared setup)
      include: ['tests/unit/**/*.{ts,js}', 'tests/integration/**/*.{ts,js}', 'tests/setup.ts'],
      exclude: [
        'node_modules/**',
        'dist/**',
        'build/**',
        'coverage/**',
        '**/*.config.*',
        '**/*.d.ts',
        'auth/**', // Go код тестируется отдельно
        'data/**',
        'logs/**',
        'docs/**',
        'tests/e2e/**',
        'playwright-report/**',
        'playwright-artifacts/**',
      ],
      thresholds: {
        global: {
          branches: 90,
          functions: 90,
          lines: 90,
          statements: 90,
        },
      },
      // Vitest 4.0: coverage.all удален, используем coverage.include вместо этого
      skipFull: false,
    },

    // Настройки выполнения тестов
    testTimeout: 10000,
    hookTimeout: 10000,
    teardownTimeout: 5000,

    // Паттерны для поиска тестов
    include: ['tests/unit/**/*.{test,spec}.{ts,js}', 'tests/integration/**/*.{test,spec}.{ts,js}'],

    // Исключаем E2E тесты (они запускаются через Playwright)
    exclude: [
      'node_modules/**',
      'dist/**',
      'build/**',
      'auth/**',
      'data/**',
      'logs/**',
      'tests/e2e/**', // E2E тесты запускаются через Playwright
      'playwright-report/**',
      'playwright-artifacts/**',
    ],

    // Настройки репортеров
    reporters: ['verbose', 'json', 'html'],
    outputFile: {
      json: './coverage/test-results.json',
      html: './coverage/test-results.html',
    },

    // Настройки для параллельного выполнения
    // Vitest 4.0: poolOptions удален, все опции теперь top-level
    pool: 'threads',
    isolate: true, // Изоляция между тестами (было в poolOptions.threads.isolate)
    // singleThread: false эквивалентно maxWorkers > 1 (по умолчанию)

    // Настройки для мокирования
    mockReset: true,
    clearMocks: true,
    restoreMocks: true,

    // Настройки для работы с TypeScript
    typecheck: {
      enabled: true,
      tsconfig: './tsconfig.json',
    },

    // Настройки окружения для тестов
    env: {
      NODE_ENV: 'test',
      VITEST: 'true',
    },

    // Настройки для работы с файлами конфигурации
    setupFiles: ['./tests/setup.ts'],

    // Настройки для работы с глобальными переменными
    globalSetup: ['./tests/global-setup.ts'],
  },

  // Настройки разрешения модулей
  resolve: {
    alias: {
      '@': './types',
    },
  },

  // Настройки для работы с различными типами файлов
  define: {
    __TEST__: true,
  },

  // Настройки для оптимизации
  optimizeDeps: {
    include: ['vitest/globals'],
  },
});
