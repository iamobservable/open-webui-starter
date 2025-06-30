# TypeScript Configuration Comments

Комментарии к настройкам tsconfig.json для проекта erni-ki.

## Основные настройки компиляции

- `target: "ES2022"` - целевая версия JavaScript
- `module: "ESNext"` - система модулей
- `moduleResolution: "bundler"` - разрешение модулей для бандлеров
- `lib: ["ES2022", "DOM", "DOM.Iterable"]` - библиотеки типов

## Строгая типизация

- `strict: true` - включает все строгие проверки
- `noImplicitAny: true` - запрещает неявный any
- `strictNullChecks: true` - строгие проверки null/undefined
- `strictFunctionTypes: true` - строгие типы функций
- `strictBindCallApply: true` - строгие bind/call/apply
- `strictPropertyInitialization: true` - инициализация свойств
- `noImplicitThis: true` - явное указание типа this
- `noImplicitReturns: true` - все пути должны возвращать значение
- `noFallthroughCasesInSwitch: true` - проверка switch statements
- `noUncheckedIndexedAccess: true` - проверка индексного доступа
- `exactOptionalPropertyTypes: true` - точные опциональные типы

## Дополнительные проверки

- `noUnusedLocals: true` - неиспользуемые локальные переменные
- `noUnusedParameters: true` - неиспользуемые параметры

## Разрешение модулей

- `allowSyntheticDefaultImports: true` - синтетические default импорты
- `esModuleInterop: true` - совместимость ES модулей
- `forceConsistentCasingInFileNames: true` - регистр имен файлов
- `resolveJsonModule: true` - импорт JSON файлов
- `isolatedModules: true` - изолированные модули

## Генерация кода

- `declaration: true` - генерация .d.ts файлов
- `declarationMap: true` - source maps для деклараций
- `sourceMap: true` - source maps
- `removeComments: false` - сохранение комментариев
- `importHelpers: true` - использование tslib
- `downlevelIteration: true` - итерация для старых версий

## Пути и выходные файлы

- `outDir: "./dist"` - папка для скомпилированных файлов
- `baseUrl: "."` - базовый URL для разрешения модулей
- `paths` - алиасы путей для удобного импорта

## Экспериментальные функции

- `experimentalDecorators: true` - поддержка декораторов
- `emitDecoratorMetadata: true` - метаданные декораторов

## Совместимость

- `skipLibCheck: true` - пропуск проверки библиотек
- `allowJs: false` - запрет JavaScript файлов
- `checkJs: false` - не проверять JS файлы
- `moduleDetection: "force"` - принудительное определение модулей
