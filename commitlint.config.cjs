// Commitlint configuration для проекта erni-ki
// Валидация Conventional Commits для автоматических релизов

module.exports = {
  // Расширяем стандартную конфигурацию
  extends: ['@commitlint/config-conventional'],

  // Настройки парсера
  parserPreset: {
    parserOpts: {
      headerPattern: /^(\w*)(?:\((.*)\))?: (.*)$/,
      headerCorrespondence: ['type', 'scope', 'subject'],
    },
  },

  // Правила валидации
  rules: {
    // Тип коммита
    'type-enum': [
      2,
      'always',
      [
        'feat', // новая функциональность
        'fix', // исправление бага
        'docs', // изменения в документации
        'style', // форматирование, отсутствующие точки с запятой и т.д.
        'refactor', // рефакторинг кода
        'perf', // улучшение производительности
        'test', // добавление тестов
        'chore', // обновление задач сборки, настроек и т.д.
        'ci', // изменения в CI/CD
        'build', // изменения в системе сборки
        'revert', // откат изменений
        'security', // исправления безопасности
        'deps', // обновление зависимостей
        'config', // изменения конфигурации
        'docker', // изменения Docker
        'deploy', // изменения развертывания
      ],
    ],

    // Область изменений (scope)
    'scope-enum': [
      2,
      'always',
      [
        'auth', // auth сервис
        'nginx', // nginx конфигурация
        'docker', // docker файлы
        'compose', // docker-compose
        'ci', // CI/CD pipeline
        'docs', // документация
        'config', // конфигурационные файлы
        'monitoring', // мониторинг
        'security', // безопасность
        'ollama', // Ollama сервис
        'openwebui', // Open WebUI
        'postgres', // PostgreSQL
        'redis', // Redis
        'searxng', // SearXNG
        'cloudflare', // Cloudflare
        'tika', // Apache Tika
        'docling', // Docling
        'edgetts', // EdgeTTS
        'mcposerver', // MCP Server
        'watchtower', // Watchtower
        'deps', // зависимости
        'tests', // тесты
        'lint', // линтинг
        'format', // форматирование
      ],
    ],

    // Обязательные поля
    'type-case': [2, 'always', 'lower-case'],
    'type-empty': [2, 'never'],
    'scope-case': [2, 'always', 'lower-case'],
    'subject-case': [2, 'never', ['sentence-case', 'start-case', 'pascal-case', 'upper-case']],
    'subject-empty': [2, 'never'],
    'subject-full-stop': [2, 'never', '.'],

    // Длина строк
    'header-max-length': [2, 'always', 100],
    'body-max-line-length': [2, 'always', 100],
    'footer-max-line-length': [2, 'always', 100],

    // Формат
    'body-leading-blank': [1, 'always'],
    'footer-leading-blank': [1, 'always'],

    // Дополнительные правила для breaking changes
    'body-max-length': [0],
    'footer-max-length': [0],
  },

  // Настройки для игнорирования определенных коммитов
  ignores: [
    // Игнорируем merge коммиты
    commit => commit.includes('Merge'),
    // Игнорируем коммиты от Renovate
    commit => commit.includes('renovate'),
    // Игнорируем коммиты от dependabot
    commit => commit.includes('dependabot'),
  ],

  // Настройки для интерактивного режима (используется с git-cz)
  prompt: {
    questions: {
      type: {
        description: 'Выберите тип изменения:',
      },
      scope: {
        description: 'Укажите область изменения (опционально):',
      },
      subject: {
        description: 'Краткое описание изменения:',
      },
      body: {
        description: 'Подробное описание изменения (опционально):',
      },
      isBreaking: {
        description: 'Есть ли breaking changes?',
      },
      breaking: {
        description: 'Описание breaking change:',
      },
      isIssueAffected: {
        description: 'Влияет ли это изменение на открытые issues?',
      },
      issues: {
        description: 'Добавьте ссылки на issues (например, "fix #123", "re #123"):',
      },
    },
  },
};
