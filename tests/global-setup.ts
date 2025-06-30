// Глобальная настройка окружения для тестов проекта erni-ki
import { execSync } from 'child_process';
import { existsSync, mkdirSync } from 'fs';

export async function setup() {
  console.log('🚀 Настройка тестового окружения...');

  // Создаем необходимые директории для тестов
  const testDirs = ['tests/fixtures', 'tests/mocks', 'tests/integration', 'tests/unit', 'coverage'];

  testDirs.forEach(dir => {
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
      console.log(`✅ Создана директория: ${dir}`);
    }
  });

  // Проверяем доступность тестовых сервисов
  await checkTestServices();

  // Настраиваем тестовую базу данных (если нужно)
  await setupTestDatabase();

  console.log('✅ Тестовое окружение готово');
}

export async function teardown() {
  console.log('🧹 Очистка тестового окружения...');

  // Очищаем тестовые данные
  await cleanupTestData();

  console.log('✅ Тестовое окружение очищено');
}

async function checkTestServices() {
  const services = [
    {
      name: 'PostgreSQL',
      command: 'pg_isready -h localhost -p 5432',
      optional: true,
    },
    {
      name: 'Redis',
      command: 'redis-cli -h localhost -p 6379 ping',
      optional: true,
    },
  ];

  for (const service of services) {
    try {
      execSync(service.command, { stdio: 'ignore' });
      console.log(`✅ ${service.name} доступен`);
    } catch (error) {
      if (service.optional) {
        console.log(`⚠️  ${service.name} недоступен (опционально)`);
      } else {
        throw new Error(`❌ ${service.name} недоступен и требуется для тестов`);
      }
    }
  }
}

async function setupTestDatabase() {
  // Здесь можно добавить настройку тестовой БД
  // Например, создание схемы, миграции и т.д.
  console.log('📊 Настройка тестовой базы данных...');

  // Пример настройки (раскомментировать при необходимости)
  /*
  try {
    execSync('createdb test_erni_ki', { stdio: 'ignore' });
    console.log('✅ Тестовая база данных создана');
  } catch (error) {
    console.log('⚠️  Тестовая база данных уже существует или недоступна');
  }
  */
}

async function cleanupTestData() {
  // Очистка временных файлов и данных после тестов
  console.log('🗑️  Очистка временных данных...');

  // Здесь можно добавить логику очистки
  // Например, удаление тестовых файлов, очистка кэша и т.д.
}
