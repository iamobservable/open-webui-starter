# 👨‍💼 Administration Guide - ERNI-KI

> **Версия:** 4.0  
> **Дата обновления:** 25.07.2025  
> **Статус:** Production Ready  

## 📋 Обзор

Comprehensive руководство по администрированию и мониторингу системы ERNI-KI с архитектурой 25+ сервисов в production окружении.

## 🔧 Ежедневное администрирование

### Утренняя проверка системы
```bash
# Проверка здоровья всех сервисов
./scripts/maintenance/health-check.sh

# Быстрый аудит системы
./scripts/maintenance/quick-audit.sh

# Проверка веб-интерфейсов
./scripts/maintenance/check-web-interfaces.sh
```

### Мониторинг ресурсов
```bash
# Мониторинг системы
./scripts/performance/system-health-monitor.sh

# Мониторинг GPU (если доступно)
./scripts/performance/gpu-monitor.sh

# Проверка использования дисков
df -h
```

## 📊 Система мониторинга

### Grafana Dashboard
- **URL:** https://your-domain/grafana
- **Логин:** admin / admin (изменить при первом входе)

**Основные dashboard:**
- **System Overview** - общий обзор системы
- **Docker Containers** - мониторинг контейнеров
- **GPU Metrics** - метрики GPU (если доступно)
- **Application Metrics** - метрики приложений

### Prometheus Metrics
- **URL:** https://your-domain/prometheus
- **Основные метрики:**
  - `container_cpu_usage_seconds_total` - использование CPU
  - `container_memory_usage_bytes` - использование памяти
  - `nvidia_gpu_utilization_percent` - использование GPU

### AlertManager
- **URL:** https://your-domain/alertmanager
- **Настройка алертов:** `monitoring/alertmanager.yml`

## 💾 Управление backup

### Ежедневные backup
```bash
# Проверка статуса backup
./scripts/backup/check-local-backup.sh

# Ручной запуск backup
./scripts/backup/backrest-management.sh backup

# Проверка целостности backup
./scripts/backup/backrest-management.sh verify
```

### Восстановление из backup
```bash
# Список доступных backup
./scripts/backup/backrest-management.sh list

# Восстановление конкретного backup
./scripts/backup/backrest-management.sh restore --date=2025-07-25

# Тестовое восстановление
./scripts/backup/backrest-management.sh test-restore
```

## 🔄 Управление сервисами

### Основные команды Docker Compose
```bash
# Просмотр статуса всех сервисов
docker compose ps

# Просмотр логов
docker compose logs -f [service-name]

# Перезапуск сервиса
docker compose restart [service-name]

# Обновление сервиса
docker compose pull [service-name]
docker compose up -d [service-name]
```

### Управление Ollama
```bash
# Просмотр доступных моделей
docker compose exec ollama ollama list

# Загрузка новой модели
docker compose exec ollama ollama pull llama2

# Удаление модели
docker compose exec ollama ollama rm model-name
```

### Управление PostgreSQL
```bash
# Подключение к базе данных
docker compose exec postgres psql -U postgres -d openwebui

# Создание backup базы данных
docker compose exec postgres pg_dump -U postgres openwebui > backup.sql

# Восстановление базы данных
docker compose exec -T postgres psql -U postgres openwebui < backup.sql
```

## 📝 Управление логами

### Просмотр логов
```bash
# Логи всех сервисов
docker compose logs -f

# Логи конкретного сервиса
docker compose logs -f openwebui

# Логи с фильтрацией по времени
docker compose logs --since="1h" --until="30m"
```

### Ротация логов
```bash
# Автоматическая ротация логов
./scripts/maintenance/log-rotation-manager.sh

# Настройка ротации логов
./scripts/setup/setup-log-rotation.sh

# Очистка старых логов
./scripts/security/rotate-logs.sh
```

## 🔒 Управление безопасностью

### Мониторинг безопасности
```bash
# Проверка безопасности системы
./scripts/security/security-monitor.sh

# Аудит конфигураций безопасности
./scripts/security/security-hardening.sh --audit

# Ротация секретов
./scripts/security/rotate-secrets.sh
```

### Управление SSL сертификатами
```bash
# Проверка срока действия сертификатов
openssl x509 -in conf/ssl/cert.pem -text -noout | grep "Not After"

# Обновление сертификатов
./conf/ssl/generate-ssl-certs.sh

# Перезагрузка nginx после обновления
docker compose restart nginx
```

## ⚡ Оптимизация производительности

### Мониторинг производительности
```bash
# Быстрый тест производительности
./scripts/performance/quick-performance-test.sh

# Тест производительности GPU
./scripts/performance/gpu-performance-test.sh

# Нагрузочное тестирование
./scripts/performance/load-testing.sh
```

### Оптимизация ресурсов
```bash
# Оптимизация сети
./scripts/maintenance/optimize-network.sh

# Оптимизация SearXNG
./scripts/maintenance/optimize-searxng.sh

# Анализ использования ресурсов
./scripts/performance/hardware-analysis.sh
```

## 🔧 Обслуживание системы

### Еженедельные задачи
```bash
# Полный аудит системы
./scripts/maintenance/comprehensive-audit.sh

# Очистка неиспользуемых Docker образов
docker system prune -f

# Проверка обновлений
docker compose pull
```

### Ежемесячные задачи
```bash
# Обновление системы
sudo apt update && sudo apt upgrade

# Проверка дискового пространства
./scripts/performance/hardware-analysis.sh

# Архивирование старых логов
./scripts/maintenance/log-rotation-manager.sh --archive
```

## 🚨 Аварийное восстановление

### Автоматическое восстановление
```bash
# Запуск автоматического восстановления
./scripts/troubleshooting/automated-recovery.sh

# Исправление критических проблем
./scripts/troubleshooting/fix-critical-issues.sh

# Исправление нездоровых сервисов
./scripts/troubleshooting/fix-unhealthy-services.sh
```

### Ручное восстановление
```bash
# Корректный перезапуск системы
./scripts/maintenance/graceful-restart.sh

# Восстановление из backup
./scripts/backup/backrest-management.sh restore

# Проверка целостности данных
./scripts/troubleshooting/test-healthcheck.sh
```

## 📈 Масштабирование

### Горизонтальное масштабирование
```bash
# Добавление дополнительных worker'ов
docker compose up -d --scale openwebui=3

# Настройка load balancer
nano conf/nginx/nginx.conf
```

### Вертикальное масштабирование
```bash
# Увеличение ресурсов для сервисов
nano compose.yml
# Изменить memory и cpu limits

# Применение изменений
docker compose up -d
```

## 🔍 Диагностика проблем

### Общая диагностика
```bash
# Проверка статуса всех сервисов
docker compose ps

# Проверка использования ресурсов
docker stats

# Проверка сетевых подключений
docker network ls
```

### Специфичная диагностика
```bash
# Диагностика Ollama
./scripts/troubleshooting/test-healthcheck.sh

# Диагностика SearXNG
./scripts/troubleshooting/test-searxng-integration.sh

# Диагностика сети
./scripts/troubleshooting/test-network-simple.sh
```

## 📞 Контакты и поддержка

### Внутренние ресурсы
- **Мониторинг:** https://your-domain/grafana
- **Логи:** https://your-domain/kibana
- **Метрики:** https://your-domain/prometheus

### Внешние ресурсы
- **📖 Документация:** [docs/troubleshooting.md](troubleshooting.md)
- **🐛 Issues:** [GitHub Issues](https://github.com/DIZ-admin/erni-ki/issues)
- **💬 Discussions:** [GitHub Discussions](https://github.com/DIZ-admin/erni-ki/discussions)

---

**📝 Примечание:** Данное руководство актуализировано для архитектуры 25+ сервисов ERNI-KI версии 4.0.
