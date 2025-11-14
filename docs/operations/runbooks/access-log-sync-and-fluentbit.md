# Nginx access sync & Fluent Bit DB monitoring

## 1. Автоматическая синхронизация access.log

1. Скрипт: `scripts/infrastructure/monitoring/sync-nginx-access.sh` копирует
   `/var/log/nginx/access.log` из контейнера в `data/nginx/logs/access.log`.
2. Unit-файлы находятся в `ops/systemd/nginx-access-sync.service` и `.timer`.
3. Установка:
   ```bash
   ./scripts/maintenance/install-docling-cleanup-unit.sh  # пример — для sync используйте аналогию
   cp ops/systemd/nginx-access-sync.service ~/.config/systemd/user/
   cp ops/systemd/nginx-access-sync.timer ~/.config/systemd/user/
   mkdir -p ~/.config && cp ops/systemd/nginx-access-sync.env.example ~/.config/nginx-access-sync.env
   systemctl --user daemon-reload
   systemctl --user enable --now nginx-access-sync.timer
   ```
4. Настройте переменную `NGINX_SYNC_TARGET` в env-файле, если нужно сохранять
   лог в другом месте.
5. Лог работы — `logs/nginx-access-sync.log`.

## 2. Fluent Bit DB monitoring

1. Скрипт: `scripts/infrastructure/monitoring/check-fluentbit-db.sh` вычисляет
   размер каталога `data/fluent-bit/db` и пишет в
   `logs/fluentbit-db-monitor.log`.
2. Переменные:
   - `FLUENTBIT_DB_DIR` — путь к базе.
   - `FLUENTBIT_DB_WARN_GB`/`FLUENTBIT_DB_CRIT_GB` — пороги (по умолчанию 5/8).
3. Пример cron:
   ```cron
   0 * * * * cd /home/konstantin/Documents/augment-projects/erni-ki && ./scripts/infrastructure/monitoring/check-fluentbit-db.sh
   ```
4. Для Alertmanager можно создать правило, которое читает лог через Fluent Bit →
   Loki или добавляет метрику (см. TODO link).
