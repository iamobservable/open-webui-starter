# Alertmanager Noise Reduction & Redis Autoscaling

## Цели

- Снизить количество спамящих `HTTPErrors`/`HighHTTPResponseTime` алертов от
  blackbox.
- Зафиксировать процедуру автоскейла Redis при хронической фрагментации и
  переполнении очереди Alertmanager.

## Blackbox rate limiting

1. **Прометеевские правила** — пример в
   `ops/prometheus/blackbox-noise.rules.yml`. Группа `blackbox-noise.rules`
   добавляет агрегирующие alerts (`BlackboxHTTPErrorBurst`,
   `BlackboxSustainedLatency`) и помечает их `noise_group=blackbox`. Скопируйте
   файл в конфигурацию Prometheus и добавьте в `rule_files`.
2. **Маршрут Alertmanager** — `ops/alertmanager/blackbox-noise-route.yml`
   содержит блок для `route.routes`. Он увеличивает
   `group_interval`/`repeat_interval` до 15m/3h. Разместите его выше маршрута
   `severity: warning`.
3. **Деплой**:
   - Внесите файлы в продовую конфигурацию (`conf/*`), перезапустите
     `prometheus` и `alertmanager` контейнеры.
   - Убедитесь через UI, что вместо десятков `HTTPErrors` приходит единый
     агрегированный alert.

## Redis auto-scaling

1. **Watchdog** — `scripts/maintenance/redis-fragmentation-watchdog.sh`
   поддерживает переменные `REDIS_AUTOSCALE_ENABLED`, `REDIS_AUTOSCALE_STEP_MB`
   (default 256MB) и `REDIS_AUTOSCALE_MAX_GB` (default 4GB). После `MAX_PURGES`
   скрипт bump'ит `maxmemory` через `CONFIG SET` и перезаписывает конфиг.
2. **Как включить**:
   - Экспортировать переменные (например, в cron):
     ```bash
     export REDIS_AUTOSCALE_ENABLED=true
     export REDIS_AUTOSCALE_STEP_MB=512
     export REDIS_AUTOSCALE_MAX_GB=4
     ```
   - Запустить watchdog (cron/systemd) и убедиться, что в
     `logs/redis-fragmentation-watchdog.log` появляются строки
     `Autoscaling Redis maxmemory...`.
3. **Мониторинг** — держим метрики `mem_fragmentation_ratio` и `maxmemory`
   (внутри watchdog выводятся значения в MB). Дополнительно рекомендуется
   добавить панель в Grafana (Redis dashboard) для отслеживания bump'ов.

## Процедура при всплеске

1. **Очередь Alertmanager**:
   `tail -f .config-backup/logs/alertmanager-queue.log` — если >500 в течение 10
   минут, убедиться, что blackbox alerts не заспамили (см. маршрут). Установить
   временный silence, если необходимо.
2. **Redis autoscale**: проверить лог watchdog; при отсутствии bump'ов можно
   вручную выполнить
   `docker compose exec redis redis-cli config set maxmemory <value>`.
3. **Документация**: ссылаться на этот runbook при разборе инцидента, фиксируя
   сколько раз autoscale сработал.
