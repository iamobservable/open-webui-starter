# ERNI-KI — аудит логов (12 ноября 2025)

## Область и источники

- `data/webhook-logs/` — 69 235 JSON-артефактов Alertmanager (314 МБ) с
  2025‑08‑29 по 2025‑11‑12.
- `scripts/health-monitor.sh`, `.config-backup/monitoring/cron.log`,
  `.config-backup/logs/*.log` — журналы регулярных проверок.
- Конфигурация Fluent Bit (`conf/fluent-bit/*.conf`) и docker-compose
  (лог-драйверы fluentd/json-file).
- Части `data/*` (Redis, Postgres, Grafana, Loki, Fluent Bit) — проверка
  каталогов, права доступа.

### Ограничения

- Каталоги `data/postgres`, `data/postgres.old`, `data/postgres-pg15-backup`,
  `data/redis/appendonlydir`, `data/grafana/pdf` и `data/backrest/oplog*`
  недоступны для чтения непривилегированному пользователю — прямой анализ их
  журналов невозможен.
- Набор `data/webhook-logs` содержит события до августа: анализ сфокусирован на
  последних 7 днях (05‑12 ноября), чтобы отделить актуальные проблемы от
  исторических.

## Сводная телеметрия Alertmanager (05‑12 ноября)

- Всего за 7 дней: **18 226 событий** (13 313 warning, 4 913 critical).
- Суточная нагрузка:

| Дата       | Alert-ов |
| ---------- | -------: |
| 2025‑11‑05 |      532 |
| 2025‑11‑06 |    4 189 |
| 2025‑11‑07 |    3 154 |
| 2025‑11‑08 |    1 850 |
| 2025‑11‑09 |    1 922 |
| 2025‑11‑10 |    1 848 |
| 2025‑11‑11 |    2 467 |
| 2025‑11‑12 |    2 267 |

### Топ alert-типов (05‑12 ноября)

| Alert                              | Кол-во |
| ---------------------------------- | -----: |
| `ContainerRestarting`              | 12 848 |
| `RedisDown`                        |  1 507 |
| `HighDiskUtilization`              |    678 |
| `CriticalServiceLogsMissing`       |    678 |
| `CriticalDiskSpace`                |    673 |
| `CriticalLowDiskSpace`             |    672 |
| `RedisCriticalMemoryFragmentation` |    394 |
| `FluentBitHighMemoryUsage`         |    172 |
| `AlertmanagerClusterHealthLow`     |    170 |
| `ContainerHighMemoryUsage`         |    135 |

### Топ сервисов по количеству предупреждений

| Сервис/метрика                       | Кол-во alert-ов |
| ------------------------------------ | --------------: |
| `cadvisor` (перезапуски контейнеров) |          12 933 |
| `redis`                              |           1 930 |
| `system` (`/boot/efi`, `root`)       |           1 345 |
| `node-exporter`                      |             678 |
| `logging` (Fluent Bit поток)         |             678 |
| `alertmanager`                       |             200 |
| `fluent-bit`                         |             183 |
| `postgres`                           |             111 |
| `ollama`                             |              65 |
| `nginx`                              |              20 |

## Ключевые наблюдения

### 1. Шторм `ContainerRestarting` перегружает всю систему оповещений

- 12 848 предупреждений за неделю, охватывающих буквально каждый контейнер
  (`data/webhook-logs/alert_warning_20251106_110452.json`).
- Alertmanager фиксирует очередь >4 000 сообщений
  (`data/webhook-logs/alert_critical_20251112_131718.json`), из‑за чего теряются
  реальные критические события.
- Почти вся нагрузка идёт от выражения `rate(container_last_seen[5m]) > 0`,
  поэтому cadvisor сообщает «перезапуск» даже при обычной активности контейнера.
- Рекомендации: временно отключить/ослабить правило, заменить его на проверку
  `container_last_seen` + `container_start_time_seconds`, ограничить namespace
  `erni-ki-*`, добавить фильтрацию по фактическому росту `RestartCount` (см.
  docker `State.RestartCount`).

### 2. Повторяющиеся отказы Redis

- 1 507 `RedisDown` + 394 `RedisCriticalMemoryFragmentation` событий (например,
  `data/webhook-logs/alert_critical_20251112_145333.json`,
  `data/webhook-logs/alert_critical_20251111_155047.json`).
- Последствия описаны прямо в alert-ах: падение кэша OpenWebUI/LiteLLM/SearXNG и
  рост латентности.
- Рекомендации: проанализировать реальные логи Redis (доступ к
  `data/redis/appendonlydir` нужен sudo), включить `maxmemory-policy` ≠
  `noeviction`, добавить watchdog, увеличить память контейнера, включить
  auto-restart в compose с backoff, настроить отдельный alerta на
  `redis_uptime_in_seconds` для подтверждения падений.

### 3. Критические проблемы с диском `/boot/efi`

- 673 `CriticalDiskSpace` и 672 `CriticalLowDiskSpace` за 7 дней
  (`data/webhook-logs/alert_critical_20251112_160557.json`), показывает 100 %
  заполнения `/dev/nvme0n1p1` (vfat, 512 МБ).
- Очевидно, partition не чистится после обновлений ядра/GRUB, а alert
  срабатывает непрерывно → высокий шум.
- Рекомендации: очистить старые EFI-записи, уменьшить частоту alert-а (порог
  98 % бессмысленен на 512 МБ), либо исключить `fstype=vfat` из запроса
  Prometheus, оставив отдельный runbook для ручного контроля.

### 4. Нестабильная цепочка логирования (Fluent Bit → Loki)

- Частые `ServiceDown` для `fluent-bit:2020` и `loki:3100`
  (`data/webhook-logs/alert_critical_20251112_153014.json`), плюс
  `CriticalServiceLogsMissing` (678 раз, пример
  `data/webhook-logs/alert_critical_20251007_042049.json`).
- `FluentBitHighMemoryUsage` и Alertmanager предупреждают о росте памяти
  (`data/webhook-logs/alert_warning_20251112_153751.json`).
- Последствия: исчезающие логи критических сервисов и лавинообразные alert-ы
  «нет логов». Архив `data/webhook-logs` копит 314 МБ JSON без ротации.
- Рекомендации: включить `storage.max_chunks_up`/`storage.backlog.mem_limit`,
  перенести буферы Fluent Bit на SSD (24–32 ГБ), добавить перезапуск с
  `mem_limit`, включить Promtail как резерв. Настроить cron-очистку
  `data/webhook-logs`, иначе Alertmanager спамит даже после тушения инцидента.

### 5. Alertmanager сам испытывает деградацию

- `AlertmanagerQueueCritical` и `AlertmanagerClusterHealthLow` (пример
  `data/webhook-logs/alert_critical_20251112_131718.json`) срабатывают десятками
  раз в день.
- Причина — поток из п. 1: очередь превышает 4 000 сообщений, узел не успевает
  отправлять webhooks → файлы в `data/webhook-logs` множатся, cron-ы
  перегружаются.
- Рекомендации: включить `inhibit_rules` / `group_by` для шумных
  `ContainerRestarting`, увеличить `--cluster.peer-timeout`, либо временно
  переводить alertmanager в `--log.level=error` и включать HA only после
  фильтрации событий.

### 6. Мониторы/cron-скрипты сами падают

- `scripts/health-monitor.sh:130-143` жёстко вызывают `python`, которого нет в
  окружении (`.config-backup/monitoring/cron.log` фиксирует
  `python: command not found`). В итоге чек контейнеров всегда `FAIL`, cron лог
  переполнен.
- Там же `⚠️ Nginx proxy` (ответ не содержит `ok`) и
  `Логи — 17 210 критических записей` (простая grep по `compose logs` реагирует
  на текст Alertmanager, а не реальные ошибки).
- `./.config-backup/logging-monitor.sh` и `./.config-backup/logging-alerts.sh`
  отсутствуют, но cron вызывает их каждую минуту
  (`.config-backup/logs/daily-report.log`, `.config-backup/logs/alerts.log`
  заспамлены `/bin/sh: ... not found`).
- Рекомендации: переключить скрипты на `python3`, добавить проверку наличия curl
  endpoints (`/healthz` у nginx реально выводит `ok`?), вычистить несуществующие
  cron-задания или добавить stub-скрипты, иначе наблюдение даёт только шум.

### 7. Постгрес и сервисы AI периодически деградируют

- 111 событий `postgres` (мм. `PostgreSQLSlowQueries`, `ServiceDownPostgreSQL`,
  см. `data/webhook-logs/alert_warning_20251107_101129.json`), 65 alert-ов от
  `ollama`, 20 от `nginx`, `ServiceDown` для `fluent-bit`/`loki` (см. выше).
- Следует сопоставить эти периоды с нагрузкой LiteLLM/OpenWebUI и добавить
  автоматическую отмену «idle in transaction» через `pg_terminate_backend` при
  длительности >5 мин.

## Рекомендации (в порядке приоритета)

1. **Срочно приглушить или переписать правило `ContainerRestarting`**, иначе
   Alertmanager остаётся бесполезным. Ограничить количество событий <500/сутки.
2. **Восстановить устойчивость Redis**: анализ реальных логов, лимиты памяти,
   watchdog, отдельные alert-ы на `redis_uptime` и `connected_clients`.
3. **Разгрузить `/boot/efi` и обновить диск-алерты**, чтобы critical приходили
   только при риске срыва загрузки.
4. **Починить цепочку Fluent Bit → Loki** (лимиты памяти, persistent
   backpressure, мониторинг WAL), добавить retention для `data/webhook-logs`.
5. **Починить cron-скрипты**: заменить `python` на `python3`, либо поставить
   `/usr/bin/python`, вернуть отсутствующие `logging-*.sh` или убрать вызовы;
   переписать проверку логов на Loki API, а не `compose logs`.
6. **Отреагировать на Alertmanager backlog**: увеличить ресурсы контейнера,
   включить HA/peer, либо временно выключить шумные алерты.
7. **Продолжить аудит сервисных логов после выдачи прав** на `data/postgres*`,
   `data/redis/appendonlydir` — сейчас нет возможности подтвердить реальные
   причины падений БД/кэша.

## Выполненные remediation (12 ноября 2025)

- **Redis**: снижены пороги активной дефрагментации (1 МБ / 5–50 %) и включены
  `lazyfree-*` опции в `conf/redis/redis.conf:65-109`, добавлен watchdog
  `scripts/maintenance/redis-fragmentation-watchdog.sh` (использует
  `redis-cli memory purge`, лог `logs/redis-fragmentation-watchdog.log`). Запуск
  автоматизирован через cron (`conf/cron/logging-reports.cron`, каждые 5 мин);
  добавлен alert `RedisHighFragmentation` (см. `conf/prometheus/alert_rules.yml`
  и Prometheus Alerts Guide) — при ratio >5 оператор получает уведомление с
  runbook-ссылкой.
- **/boot/efi**: проверены каталоги `EFI/{BOOT,Dell,ubuntu}`, удалён устаревший
  `EFI/Dell/logs/diags_previous.xml` (резервные диагностические логи) — раздел
  теперь чист, используется <4 %.
- **Дисковые алерты**: все Prometheus-правила низкого дискового пространства
  исключают `fstype="vfat"` и `mountpoint="/boot/efi"`
  (`conf/prometheus/alert_rules.yml:44-63`,
  `conf/prometheus/rules/erni-ki-alerts.yml:60-95`,
  `conf/prometheus/rules/production-sla-alerts.yml:120-132`), чтобы
  предупреждения больше не сыпались по EFI-разделу. После
  `docker compose restart prometheus alertmanager` убедиться, что
  `HighDiskUtilization`/`CriticalDiskSpace` теперь отражают критические тома
  (`/`, `/data`).
- **Fluent Bit → Loki**: обновлён `conf/fluent-bit/fluent-bit.conf` — теперь
  используется `Host erni-ki-loki` (container_name) для DNS-устойчивости,
  `storage.type filesystem` для входного потока и `Retry_Limit False` + лимит
  backlog 1 ГБ, чтобы Fluent Bit буферизовал логи при недоступности Loki вместо
  спама `getaddrinfo`.
- **Ротация Alertmanager вебхуков**: добавлен скрипт
  `scripts/maintenance/webhook-logs-rotate.sh` (архивация по датам, удаление
  старше 30 дней) и cron-задание `30 2 * * *` в
  `conf/cron/logging-reports.cron`. Каталог `data/webhook-logs/archive` содержит
  tar.gz по дням.
- **Cron-скрипты мониторинга**: созданы `.config-backup/logging-monitor.sh` и
  `.config-backup/logging-alerts.sh`, которые вызывают
  `scripts/health-monitor.sh` и запрашивают Alertmanager API соответственно (лог
  `.config-backup/logs/alerts.log`). `health-monitor.sh` теперь использует
  `python3`, что устраняет ошибку `python: command not found`.

Отчёт нужно синхронизировать с runbook-ами (`docs/monitoring-guide.md`,
`docs/prometheus-alerts-guide.md`) и создать отдельный таск на чистку
`data/webhook-logs`.
