// ESLint Flat Config для проекта erni-ki
// Поддержка TypeScript, современный JavaScript, безопасность
import js from '@eslint/js';
import typescript from '@typescript-eslint/eslint-plugin';
import typescriptParser from '@typescript-eslint/parser';
import nodePlugin from 'eslint-plugin-n';
import promise from 'eslint-plugin-promise';
import security from 'eslint-plugin-security';

export default [
  // Базовые рекомендуемые правила JavaScript
  js.configs.recommended,

  // Игнорируемые файлы и папки
  {
    ignores: [
      'node_modules/**',
      'vendor/**',
      'dist/**',
      'build/**',
      'coverage/**',
      '*.min.js',
      '*.min.css',
      'data/**',
      'cache/**', // Backrest cache с ограниченными правами доступа
      'logs/**',
      '*.log',
      '.tmp/**',
      'tmp/**',
      '.cache/**',
      '.venv/**', // Python virtual environment
      '**/*.go',
      'package-lock.json',
      'yarn.lock',
      '*.pb.js',
      '*.pb.ts',
      'Dockerfile*',
      '.dockerignore',
      '*.md',
      'docs/**',
      'site/**',
      '.env*',
      '*.example',
      '.vscode/**',
      '.idea/**',
      '.DS_Store',
      'Thumbs.db',
      '.config-backup/**',
      'playwright-report/**',
      'playwright-artifacts/**',
      'test-results/**',
      'tests/e2e/**', // E2E тесты используют Playwright, не ESLint
    ],
  },

  // Глобальная конфигурация для всех файлов
  {
    languageOptions: {
      ecmaVersion: 2024,
      sourceType: 'module',
      globals: {
        console: 'readonly',
        process: 'readonly',
        Buffer: 'readonly',
        __dirname: 'readonly',
        __filename: 'readonly',
        global: 'readonly',
        module: 'readonly',
        require: 'readonly',
        exports: 'readonly',
      },
    },
    plugins: {
      security,
      n: nodePlugin,
      promise,
    },
    rules: {
      // Общие правила качества кода
      'no-console': 'warn',
      'no-debugger': 'error',
      'no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      'no-var': 'error',
      'prefer-const': 'error',
      'prefer-arrow-callback': 'error',
      'arrow-spacing': 'error',
      'comma-dangle': ['error', 'always-multiline'],
      quotes: ['error', 'single', { avoidEscape: true }],
      semi: ['error', 'always'],
      indent: ['error', 2, { SwitchCase: 1 }],
      'max-len': ['warn', { code: 100, ignoreUrls: true }],
      'eol-last': 'error',
      'no-trailing-spaces': 'error',

      // Безопасность
      'security/detect-object-injection': 'warn',
      'security/detect-non-literal-regexp': 'warn',
      'security/detect-unsafe-regex': 'error',
      'security/detect-buffer-noassert': 'error',
      'security/detect-child-process': 'warn',
      'security/detect-disable-mustache-escape': 'error',
      'security/detect-eval-with-expression': 'error',
      'security/detect-no-csrf-before-method-override': 'error',
      'security/detect-non-literal-fs-filename': 'warn',
      'security/detect-non-literal-require': 'warn',
      'security/detect-possible-timing-attacks': 'warn',
      'security/detect-pseudoRandomBytes': 'error',

      // Node.js специфичные правила
      'n/no-deprecated-api': 'error',
      'n/no-missing-import': 'off', // Отключаем, так как используем TypeScript
      'n/no-missing-require': 'off', // Отключаем, так как используем TypeScript

      // Promises
      'promise/always-return': 'error',
      'promise/no-return-wrap': 'error',
      'promise/param-names': 'error',
      'promise/catch-or-return': 'error',
      'promise/no-native': 'off',
      'promise/no-nesting': 'warn',
      'promise/no-promise-in-callback': 'warn',
      'promise/no-callback-in-promise': 'warn',
      'promise/avoid-new': 'off',
    },
  },

  // Конфигурация для TypeScript файлов
  {
    files: ['**/*.ts', '**/*.tsx'],
    languageOptions: {
      parser: typescriptParser,
      parserOptions: {
        ecmaVersion: 2024,
        sourceType: 'module',
        project: './tsconfig.json',
      },
    },
    plugins: {
      '@typescript-eslint': typescript,
    },
    rules: {
      // Отключаем базовые правила, которые конфликтуют с TypeScript
      'no-unused-vars': 'off',
      'no-undef': 'off',

      // TypeScript специфичные правила
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      '@typescript-eslint/no-explicit-any': 'warn',
      '@typescript-eslint/explicit-function-return-type': 'off',
      '@typescript-eslint/explicit-module-boundary-types': 'off',
      '@typescript-eslint/no-inferrable-types': 'error',
      '@typescript-eslint/prefer-nullish-coalescing': 'error',
      '@typescript-eslint/prefer-optional-chain': 'error',
      '@typescript-eslint/no-non-null-assertion': 'warn',
      '@typescript-eslint/ban-ts-comment': 'warn',
      '@typescript-eslint/no-empty-function': 'warn',
      '@typescript-eslint/consistent-type-definitions': ['error', 'interface'],
      '@typescript-eslint/array-type': ['error', { default: 'array-simple' }],
    },
  },

  // Игнорируемые файлы и директории
  {
    ignores: [
      'node_modules/**',
      'dist/**',
      'build/**',
      'data/**',
      'logs/**',
      '*.min.js',
      'vendor/**',
      '.git/**',
      'coverage/**',
      '*.config.js',
      'auth/main', // Скомпилированный Go бинарник
    ],
  },

  // Специальные правила для тестовых файлов
  {
    files: ['**/*.test.{js,ts}', '**/*.spec.{js,ts}', 'tests/**/*.{js,ts}'],
    rules: {
      'no-console': 'off',
      '@typescript-eslint/ban-ts-comment': 'off',
      '@typescript-eslint/no-explicit-any': 'off',
      '@typescript-eslint/no-empty-function': 'off',
      '@typescript-eslint/no-unused-vars': 'off',
      'security/detect-non-literal-fs-filename': 'off',
    },
  },

  // Специальные правила для конфигурационных файлов
  {
    files: ['**/*.config.{js,ts,cjs}', 'commitlint.config.cjs'],
    rules: {
      'security/detect-unsafe-regex': 'off',
    },
  },

  // Специальные правила для типов
  {
    files: ['**/*.d.ts'],
    rules: {
      '@typescript-eslint/no-explicit-any': 'off',
    },
  },
];
