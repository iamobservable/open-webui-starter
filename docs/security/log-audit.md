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

Отчёт нужно синхронизировать с runbook-ами
(`docs/operations/monitoring-guide.md`, `docs/prometheus-alerts-guide.md`) и
создать отдельный таск на чистку `data/webhook-logs`.

## Повторный аудит (13 ноября 2025)

### Актуальные метрики (09:05 UTC+1)

- `alertmanager_cluster_messages_queued` — **301** (порог 100, см.
  `.config-backup/logs/alertmanager-queue.log`).
- Активные алерты (`/api/v2/alerts`): 13 шт. (6× `HTTPErrors`, 3×
  `HighHTTPResponseTime`, 1× `AlertmanagerClusterHealthLow`,
  `FluentBitHighMemoryUsage`, `CriticalServiceLogsMissing`,
  `ContainerWarningMemoryUsage`).
- Redis `mem_fragmentation_ratio` — **5.89**
  (`docker compose exec redis redis-cli info memory`).
- `data/webhook-logs/`: 48 МБ, 5 303 «сырых» JSON и 67 архивов в
  `archive/alert-*.tar.gz` (ротация работает).

### Новые наблюдения

1. **Cron health-monitor** (`.config-backup/monitoring/cron.log`) каждый час
   падает на `docker compose ps`, т.к. таски запускаются не из корня
   репозитория. `conf/cron/logging-reports.cron` теперь задаёт
   `PROJECT_ROOT=/home/konstantin/Documents/augment-projects/erni-ki` и вызывает
   `.config-backup/logging-monitor.sh`/`logging-alerts.sh` через `bash`, что
   исключает ошибку `./.config-backup/...: not found`.
2. **Очередь Alertmanager**: мониторинг
   (`scripts/monitoring/alertmanager-queue-watch.sh`) не запускался с 12 ноября;
   вручную зафиксировано **304** сообщений (WARN). Cron-задача добавлена в
   `conf/cron/logging-reports.cron`, лог теперь пополняется при каждом запуске.
3. **Правило `ContainerRestarting`** порождало ​>12 k спур. алертов. В
   `conf/prometheus/alerts.yml` оно переписано: учитываются только сервисные
   контейнеры `erni-ki-*`, метрики агрегируются по сервису (strip хеша),
   требуется ≥3 рестарта за 30 мин + `for: 5m`. Это гасит шум и оставляет только
   реально «флапающие» сервисы.
4. **redis-exporter**: ранее
   `command: /bin/sh -c "export REDIS_ADDR=$(cat secret)"` не выполнялся
   (entrypoint=/redis_exporter), экспортер смотрел на `redis://localhost:6379` и
   падал с `dial redis: unknown network redis`. В `compose.yml` теперь прописан
   стабильный `REDIS_ADDR=redis://redis:6379`, а секрет `redis_exporter_url`
   хранит JSON-карту `{"redis://redis:6379":""}`. При включении `requirepass`
   достаточно вписать пароль в карту — экспортер подхватит его через
   `REDIS_PASSWORD_FILE`.
5. **Fluent Bit parser conflict**: предупреждение
   `parser named 'postgres' already exists` убрано переименованием парсера в
   `postgres_structured` (`conf/fluent-bit/parsers.conf`). После
   `docker compose restart fluent-bit` ошибки исчезли.
6. **Redis fragmentation watchdog**: скрипт писал логи в `scripts/logs/...`,
   т.к. `PROJECT_DIR` указывал на `scripts/`. Исправлено на корень репо
   (`logs/redis-fragmentation-watchdog.log`), запуск (включая cron) теперь
   работает из правильной директории.
7. **Ротация webhook-логов**: `scripts/maintenance/webhook-logs-rotate.sh`
   очистил каталог до 5.3 k файлов, остальное сложено в 67 архивов —
   подтверждение, что cron `30 2 * * *` выполняет задачи.

### Выполненные remediation (13 ноября)

- `compose.yml`: для `redis-exporter` заданы постоянные
  `REDIS_ADDR`/`REDIS_PASSWORD_FILE`, контейнер пересобран.
- `conf/cron/logging-reports.cron`: введена переменная `PROJECT_ROOT`, добавлены
  cron’ы для `.config-backup/logging-monitor.sh`,
  `.config-backup/logging-alerts.sh` и очереди Alertmanager.
- `conf/fluent-bit/parsers.conf`: парсер `postgres` → `postgres_structured`.
- `scripts/maintenance/redis-fragmentation-watchdog.sh`: `PROJECT_DIR` → корень
  репозитория; логи складываются в `logs/`.
- `scripts/monitoring/alertmanager-queue-watch.sh` выполнен вручную,
  зафиксировав WARN 304 — база для алерта.
- `conf/prometheus/alerts.yml`: правило `ContainerRestarting` ужесточено для
  борьбы со спур. предупреждениями.
- `docs/operations/monitoring-guide.md`, `docs/locales/de/monitoring-guide.md`,
  `docs/architecture/service-inventory.md`, `secrets/README.md` и
  `secrets/redis_exporter_url.txt.example` обновлены под новую схему
  redis-exporter.

### Следующие шаги

- Отследить снижение шума от `ContainerRestarting`. При необходимости добавить
  `apply_modulo` по namespace либо вынести правило в отдельный silence.
- Использовать обновлённые cron-файлы на хосте (`crontab -e` / `/etc/cron.d`) и
  проверить, что `.config-backup/logging-monitor.sh` больше не падает на
  `docker compose ps`.
- Мониторить `alertmanager_cluster_messages_queued`: при сохранении уровня
  > 100 продолжить чистку шумных алертов (`HTTPErrors`,
  > `CriticalServiceLogsMissing`).
- Решить, когда включать `requirepass` для Redis и, соответственно, вписать
  пароль в `redis_exporter_url` (JSON). Пока значение пустое, redis-exporter
  работает без `AUTH`.
- Использовать `logs/redis-fragmentation-watchdog.log` для автоматического
  завершения remediation (порог 4.0), т.к. текущее значение 5.89 всё ещё выше
  нормы.

## Дополнение (13 ноября 2025): публичный провайдер PublicAI в LiteLLM

- Добавлен собственный обработчик `conf/litellm/custom_providers/publicai.py`
  (поддерживает sync/async/streaming, формирует ответы через
  `convert_to_model_response_object`, маскирует user-agent). Провайдер
  подключается через `litellm_settings.custom_provider_map` в
  `conf/litellm/config.yaml`.
- `compose.yml` теперь монтирует каталог `conf/litellm/custom_providers` в
  контейнер LiteLLM, а `env/litellm.env` экспортирует
  `PYTHONPATH=/app/custom_providers:/app`, чтобы не пересобирать образ.
- Модель `publicai-apertus-70b` обновлена через
  `PATCH /model/704e30c3-e423-4fc2-9c42-087c070e7a41/update` (api_base
  `https://api.publicai.co/v1`, `custom_llm_provider=publicai`, `mode=chat`,
  свежий PublicAI API‑ключ).
- Ключ LiteLLM `sk-7b788…38bb` снова видит список моделей: `models` для его
  token-хеша `52b606a12ab1…` в `LiteLLM_VerificationToken` выставлены в
  `{'all-proxy-models'}`.
- `conf/litellm/config.yaml` теперь мапит `apertus-70b-instruct` →
  `publicai/apertus-70b-instruct`, чтобы запросы от OpenWebUI проходили через
  PublicAI (custom_llm_provider `publicai`) вместо неправильно распознаваемого
  `swiss-ai/apertus-70b-instruct`.
- Были прогнаны smoke‑тесты (13.11.2025 08:31 UTC):

  ```bash
  # /v1/models вновь возвращает 3 модели
  curl -s -H 'Authorization: Bearer sk-7b7…38bb' http://localhost:4000/models

  # обычный completion
  curl -s -H 'Authorization: Bearer sk-7b7…38bb' \
    -H 'Content-Type: application/json' \
    -d '{"model":"publicai-apertus-70b","messages":[{"role":"user","content":"привет"}]}' \
    http://localhost:4000/v1/chat/completions

  # streaming completion
  curl -sN -H 'Authorization: Bearer sk-7b7…38bb' \
    -H 'Content-Type: application/json' \
    -d '{"model":"publicai-apertus-70b","stream":true,"messages":[{"role":"user","content":"привет"}]}' \
    http://localhost:4000/v1/chat/completions | head

  # OpenWebUI → LiteLLM
  docker compose exec openwebui curl -s -H 'Authorization: Bearer sk-7b7…38bb' \
    -H 'Content-Type: application/json' \
    -d '{"model":"publicai-apertus-70b","messages":[{"role":"user","content":"ping"}]}' \
    http://litellm:4000/v1/chat/completions
  ```

  Все запросы завершились HTTP 200 и валидным JSON/SSE ответом («Привет! Как я
  могу помочь вам сегодня?»), что подтверждает восстановление цепочки LiteLLM ↔
  PublicAI ↔ OpenWebUI.

- Ключ хранится в Docker Secret `publicai_api_key` (см.
  `secrets/publicai_api_key.txt`
  - README). Entry-point `scripts/entrypoints/litellm.sh` экспортирует его в
    `PUBLICAI_API_KEY`, а сама модель в БД ссылается на
    `os.environ/PUBLICAI_API_KEY`, поэтому ротация теперь сводится к обновлению
    файла секрета без SQL.
- Кастомный провайдер публикует Prometheus-метрики (`litellm_publicai_*`) на
  `litellm:9109`, Prometheus job `litellm-publicai` собирает их, а новые алерты
  `LiteLLMPublicAIHighErrorRate` и `LiteLLMPublicAIRepeated404` предупреждают о
  всплесках 4xx/5xx до того, как проблемы доберутся до UI.
