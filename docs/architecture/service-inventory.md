# Справочник сервисов ERNI-KI

Документ агрегирует сведения из `compose.yml` и `env/*.env` о каждом сервисе,
чтобы инженеры могли быстро понять назначение контейнеров, точки входа,
зависимости и требования к безопасности. Для обновлений образов используйте
[checklist](image-upgrade-checklist.md).

## Базовая инфраструктура и хранение

| Сервис       | Назначение                                         | Порты                                                 | Зависимости и конфигурация                                                                         | Обновления и замечания                                                                                                                           |
| ------------ | -------------------------------------------------- | ----------------------------------------------------- | -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `watchtower` | Автообновление контейнеров, чистка старых образов. | `127.0.0.1:8091->8080` (HTTP API только с localhost). | `env/watchtower.env`, монтирует `/var/run/docker.sock`, секрет `watchtower_api_token`.             | API требует токен из Docker secret, порт привязан к localhost; лимиты `mem_limit=256M`, `mem_reservation=128M`, `cpus=0.2`, `oom_score_adj=500`. |
| `db`         | PostgreSQL 17 + pgvector, основное хранилище.      | Только внутренняя сеть.                               | `env/db.env`, секрет `postgres_password`, кастомный `postgresql.conf`, данные в `./data/postgres`. | Автообновление запрещено; healthcheck `pg_isready`.                                                                                              |
| `redis`      | Кэш, очереди и rate limiting.                      | Только внутренняя сеть.                               | `env/redis.env`, конфиг `./conf/redis/redis.conf`, данные `./data/redis`.                          | Разрешён watchtower (`cache-services`); следить за совместимостью RDB.                                                                           |
| `backrest`   | Резервное копирование данных/конфигов.             | `9898:9898`.                                          | `env/backrest.env`, множественные volume, доступ к Docker socket.                                  | Автообновление включено; требует контроля прав на бэкап каталоги.                                                                                |

## Сервисы доступа и периферия

| Сервис        | Назначение                                       | Порты                            | Зависимости и конфигурация                                                                                                                                                                                                                                                             | Обновления и замечания                                                                                                                                                    |
| ------------- | ------------------------------------------------ | -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `nginx`       | Реверс‑прокси, TLS терминация.                   | `80`, `443`, `8080`.             | Конфиги из `./conf/nginx`, SSL в `./conf/nginx/ssl`.                                                                                                                                                                                                                                   | Watchtower выключен (критический прокси); healthcheck `/etc/nginx/healthcheck.sh`.                                                                                        |
| `cloudflared` | Публикация Nginx наружу через Cloudflare Tunnel. | Нет внешних портов.              | `env/cloudflared.env`, конфиг `./conf/cloudflare/config`.                                                                                                                                                                                                                              | Watchtower включён; требует валидного токена Cloudflare.                                                                                                                  |
| `auth`        | Сервис JWT-аутентификации для внутренних API.    | `9092:9090`.                     | `env/auth.env`, image собирается из `./auth`.                                                                                                                                                                                                                                          | Автообновление разрешено (`auth-services`).                                                                                                                               |
| `mcposerver`  | MCP сервер OpenWebUI (git-91e8f94).              | `8000:8000`.                     | `env/mcposerver.env`, конфиг `./conf/mcposerver`, данные `./data`.                                                                                                                                                                                                                     | Автообновление включено; зависит от `db`.                                                                                                                                 |
| `searxng`     | Метапоиск, источник веб‑результатов.             | Нет публичного порта (internal). | `env/searxng.env`, конфиги `./conf/searxng/*.yml`.                                                                                                                                                                                                                                     | Watchtower включён; образ закреплён на digest `searxng/searxng@sha256:aaa855e8...` (linux/amd64).                                                                         |
| `edgetts`     | Синтез речи (Edge TTS).                          | `5050:5050`.                     | `env/edgetts.env`. Healthcheck через Python socket.                                                                                                                                                                                                                                    | Watchtower включён; используется digest `travisvn/openai-edge-tts@sha256:1aa9b25c...`.                                                                                    |
| `tika`        | Экстракция контента/метаданных из файлов.        | `9998:9998`.                     | `env/tika.env`.                                                                                                                                                                                                                                                                        | Watchtower включён; образ закреплён на `apache/tika@sha256:3fafa194...` (linux/amd64).                                                                                    |
| `litellm`     | Прокси LiteLLM с thinking tokens.                | `4000:4000`.                     | `env/litellm.env`, `./conf/litellm/config.yaml`, данные `./data/litellm`, entrypoint `scripts/entrypoints/litellm.sh`, secrets `litellm_db_password`, `litellm_master_key`, `litellm_salt_key`, `litellm_ui_password`, `litellm_api_key`, `openai_api_key`. Зависит от `db`, `ollama`. | Auto-update включён (`ai-services`); лимиты `mem_limit=12G`, `mem_reservation=6G`, `cpus=1.0`, `oom_score_adj=-300` защищают от OOM.                                      |
| `ollama`      | GPU LLM сервер, хранит модели в `./data/ollama`. | `11434:11434`.                   | `env/ollama.env`, GPU определяется через `.env` (`OLLAMA_GPU_VISIBLE_DEVICES`, `OLLAMA_GPU_DEVICE_IDS`).                                                                                                                                                                               | Watchtower выключен; `mem_limit=16G`, `mem_reservation=8G`, `cpus=12`, `oom_score_adj=-900`; GPU закрепляется через `.env`.                                               |
| `openwebui`   | Основной UI (Next.js) с GPU поддержкой.          | Через Nginx (`8080` внутри).     | `env/openwebui.env`, shared данные `./data/openwebui`, `./data/docling/shared`, entrypoint `scripts/entrypoints/openwebui.sh`, secrets `postgres_password`, `litellm_api_key`, `openwebui_secret_key`, GPU через `.env` (`OPENWEBUI_GPU_*`).                                           | Watchtower включён; лимиты `mem_limit=8G`, `mem_reservation=4G`, `cpus=4`, `oom_score_adj=-600`, общий volume синхронизирован с Docling.                                  |
| `docling`     | OCR/Doc ingestion pipeline (Docling Serve).      | Внутренняя сеть (`5001`).        | `env/docling.env`, образы `./data/docling/*`, артефакты `./data/docling-artifacts`, shared volume `./data/docling/shared`, GPU через `.env` (`DOCLING_GPU_*`).                                                                                                                         | Автообновление включено (`document-processing`); лимиты `mem_limit=12G`, `mem_reservation=8G`, `cpus=8`, `oom_score_adj=-500`, shared volume синхронизирован с OpenWebUI. |

## Мониторинг и логирование

| Сервис                    | Назначение                                          | Порты                             | Зависимости и конфигурация                                                                | Обновления и замечания                                                                                                       |
| ------------------------- | --------------------------------------------------- | --------------------------------- | ----------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `prometheus`              | Сбор метрик.                                        | `127.0.0.1:9091->9090`.           | Конфиги в `./conf/prometheus`, данные `./data/prometheus`.                                | Доступен только локально; внешний доступ через Nginx/SSH-туннель.                                                            |
| `grafana`                 | Дашборды и алерты.                                  | `127.0.0.1:3000->3000`.           | Данные `./data/grafana`, provisioning `./conf/grafana`, secret `grafana_admin_password`.  | Порт доступен только локально; админ-пароль берётся из Docker secret, внешний доступ через Nginx/VPN.                        |
| `loki`                    | Хранилище логов.                                    | `127.0.0.1:3100->3100`.           | Конфиг `./conf/loki/loki-config.yaml`, данные `./data/loki`.                              | Watchtower включён; порт теперь доступен только локально.                                                                    |
| `alertmanager`            | Управление алертами Prometheus.                     | `127.0.0.1:9093/9094`.            | Конфиг `./conf/alertmanager`, данные `./data/alertmanager`.                               | Теперь только localhost; проксируйте через Nginx при необходимости.                                                          |
| `node-exporter`           | Метрики узла.                                       | `127.0.0.1:9101->9100`.           | Монтирует `/proc`, `/sys`, `/rootfs`, `pid: host`.                                        | Слушает только localhost, утечки наружу исключены.                                                                           |
| `postgres-exporter`       | Метрики PostgreSQL.                                 | `127.0.0.1:9188->9188`.           | DSN читается из Docker secret `postgres_exporter_dsn` (shell wrapper), зависит от `db`.   | Доступ локальный; подключение извне через туннель.                                                                           |
| `postgres-exporter-proxy` | Socat-прокси IPv4→IPv6.                             | Делит сеть с `postgres-exporter`. | Без env/volumes, работает на `alpine/socat@sha256:86b69d2e...`.                           | Следим за ресурсами, автообновление разрешено.                                                                               |
| `redis-exporter`          | Метрики Redis.                                      | `127.0.0.1:9121->9121`.           | Авторизация через `REDIS_PASSWORD_FILE` (`redis_exporter_url` содержит JSON host→пароль). | Теперь виден только с локального хоста.                                                                                      |
| `nvidia-exporter`         | Метрики GPU.                                        | `127.0.0.1:9445->9445`.           | Требует GPU (`runtime: nvidia`).                                                          | Healthcheck отсутствует, но порт локальный.                                                                                  |
| `blackbox-exporter`       | HTTP/TCP проверки доступности.                      | `127.0.0.1:9115->9115`.           | Конфиг `./conf/blackbox-exporter/blackbox.yml`.                                           | Используйте Nginx/SSH для удалённого доступа.                                                                                |
| `nginx-exporter`          | Метрики Nginx.                                      | `127.0.0.1:9113->9113`.           | Команда `--nginx.scrape-uri=http://nginx:80/nginx_status`.                                | Порт доступен только локально.                                                                                               |
| `ollama-exporter`         | Метрики Ollama.                                     | `127.0.0.1:9778->9778`.           | Dockerfile в `./monitoring/Dockerfile.ollama-exporter`.                                   | Нет healthcheck; порт не публикуется наружу.                                                                                 |
| `cadvisor`                | Метрики контейнеров.                                | `127.0.0.1:8081->8080`.           | Монтирует корневые FS.                                                                    | Порт ограничен localhost; внешний доступ через прокси.                                                                       |
| `fluent-bit`              | Централизованный сбор логов → Loki.                 | `127.0.0.1:2020/2021/24224`.      | Конфиги `./conf/fluent-bit`, volume `erni-ki-logs`.                                       | Доступ к HTTP/metrics/forward только через localhost.                                                                        |
| `rag-exporter`            | SLA-мониторинг RAG.                                 | `127.0.0.1:9808->9808`.           | Переменные `RAG_TEST_URL`, зависит от `openwebui`.                                        | Endpoint виден только локально.                                                                                              |
| `webhook-receiver`        | Приём уведомлений Alertmanager и кастомные скрипты. | `127.0.0.1:9095->9093`.           | Скрипты `./conf/webhook-receiver`, логи `./data/webhook-logs`.                            | Endpoint доступен через локальный прокси; лимиты `mem_limit=256M`, `mem_reservation=128M`, `cpus=0.25`, `oom_score_adj=250`. |

> **Примечание:** Docling восстановлен в основном `compose.yml`; shared volume
> `./data/docling/shared` используется совместно с OpenWebUI.

> **Доступ к метрикам:** все мониторинговые сервисы проброшены только на
> `127.0.0.1`. Для удалённого просмотра используйте Nginx (с auth/TLS), VPN или
> SSH-туннель; внутри docker-сети сервисы продолжают работать без изменений.

## Политика лимитов ресурсов (обновлено 2025-11-12)

- Watchtower и webhook-receiver теперь используют нативные поля `mem_limit`,
  `mem_reservation`, `cpus` и `oom_score_adj`, поэтому ограничения работают в
  `docker compose` без Swarm.
- LiteLLM, Ollama, OpenWebUI и Docling фиксируют лимиты памяти/CPU и
  отрицательные `oom_score_adj`, что уменьшает вероятность убийства критичных
  процессов (Ollama: -900, OpenWebUI: -600, Docling: -500, LiteLLM: -300).
- GPU-привязка осуществляется через переменные `.env` (`*_GPU_VISIBLE_DEVICES`,
  `*_CUDA_VISIBLE_DEVICES`, `*_GPU_DEVICE_IDS`) и `nvidia-container-runtime`;
  чтобы развести сервисы по разным девайсам или MIG-слайсам, достаточно обновить
  `.env` и перезапустить сервисы.

## Политика Docling shared volume

- Структура тома: `uploads/` (сырьё, 2 дня), `processed/` (промежуточные
  артефакты, 14 дней), `exports/` (результаты, 30 дней), `quarantine/`
  (инциденты, 60 дней), `tmp/` (1 день). Детали —
  `docs/operations/runbooks/docling-shared-volume.md`.
- Права доступа: владелец — пользователь docker host; группа `docling-data`
  имеет `rwx`; аудиторы добавляются через ACL `docling-readonly` с `rx` на
  `exports/`.
- Очистка и квоты: `scripts/maintenance/docling-shared-cleanup.sh` (dry-run по
  умолчанию, `--apply` для удаления). Скрипт предупреждает при превышении
  `DOC_SHARED_MAX_SIZE_GB` (20 ГБ).
- Рекомендуемый cron:
  `10 2 * * * cd /home/konstantin/Documents/augment-projects/erni-ki && ./scripts/maintenance/docling-shared-cleanup.sh --apply >> logs/docling-shared-cleanup.log 2>&1`.

## Обновление digest для образов без версионных тегов

Некоторые сервисы (SearXNG, EdgeTTS, Apache Tika) публикуют только `latest`,
поэтому мы фиксируем sha256-digest, чтобы Watchtower не подтягивал неожиданные
релизы.

1. Получите свежий digest для amd64:
   ```bash
   docker manifest inspect <image>:latest | jq -r '.manifests[] | select(.platform.architecture=="amd64") | .digest' | head -n1
   # EdgeTTS использует однoарх. образ → можно .config.digest
   ```
2. Обновите `compose.yml`, заменив строку вида `image: <img>@sha256:...`.
3. Зафиксируйте новый digest в таблице выше и в Archon документе (раздел
   «recent_updates»).
4. После пуша выполните
   `docker compose pull <service> && docker compose up -d <service>` и
   проконтролируйте healthchecks.

Актуальные digests на 2025‑11‑12:

- `travisvn/openai-edge-tts@sha256:1aa9b25c71c91071ec7ff18f6b38bf817a9b19dd5a7722c2860c9cb085dbd742`
- `apache/tika@sha256:3fafa194474c5f3a8cff25a0eefd07e7c0513b7f552074ad455e1af58a06bbea`
- `searxng/searxng@sha256:aaa855e878bd4f6e61c7c471f03f0c9dd42d223914729382b34b875c57339b98`

## Операционные заметки (из Context7 /docker/compose)

- Для быстрой диагностики состояния контейнеров используйте
  `docker compose ps --status=running` или `--filter status=running`, а для
  завершившихся сервисов — `--status=exited`. Это удобнее, чем просматривать
  полный список длинного стека.
- `docker compose top` показывает процессы внутри сервисов с PID/UID — полезно
  при отладке зависаний LiteLLM/Ollama без захода в контейнер.
- Рекомендуется регулярно прогонять линтеры/тесты Compose-проекта (см.
  официальные рекомендации `golint`, `go test`), если меняются инструменты
  управления стеком.
- Watchtower теперь факультативен: все сервисы запускаются без `depends_on` от
  него, поэтому при сбоях Watchtower остальная инфраструктура поднимается
  автономно.
- GPU для Ollama/OpenWebUI/Docling назначаются через `.env` (`OLLAMA_GPU_*`,
  `OPENWEBUI_GPU_*`, `DOCLING_GPU_*`). Рекомендуемый шаблон в `.env.example`:
  GPU0 → Ollama, GPU1 → OpenWebUI/Docling. Для одно-GPU систем укажите
  одинаковые значения или используйте MIG-слайсы.
- Kibana/Elasticsearch исключены; для просмотра логов используйте Grafana →
  Explore (Loki), а для обслуживания хранилища —
  `scripts/maintenance/docling-shared-cleanup.sh` + Fluent Bit ↔ Loki пайплайн.

## Наблюдаемость и безопасность

- **LLM & Model Context**: LiteLLM v1.77.3-stable, MCP Server 8000 и RAG API
  (`/api/mcp/*`, `/api/search`) используют PostgreSQL + Redis для context
  storage; `docs/reference/api-reference.md` и `docs/operations/operations-handbook.md` содержат
  маршруты, SLA и список инструментов.
- **Docling/EdgeTTS**: работают через internal ports, используют CPU,
  обеспечивают многоязычный RAG pipeline и служат источником для
  `docs/operations/monitoring-guide.md`.

- Журналы высылаются во Fluent Bit (24224 forward, 2020 HTTP) и передаются в
  Loki, а критические сервисы (OpenWebUI, Ollama, PostgreSQL, Nginx) также пишут
  в `json-file` с tag `critical.*` по настройке `compose.yml`.
- Прометей 3.0.1 опрашивает 32 target’а и содержит 27 активных правил в
  `conf/prometheus/alerts.yml` (Critical, Performance, Database, GPU, Nginx).
  Alertmanager v0.28.0 отправляет оповещения по предопределённому каналу
  (Slack/Teams через Watchtower metrics API).
- Grafana v11.6.6 содержит 18 дашбордов, включая GPU/LLM, PostgreSQL, Redis,
  Docker-хост. Каждое обновление дашборда фиксируется в
  `docs/operations/grafana-dashboards-guide.md`.
- Безопасность базируется на Nginx WAF, Cloudflare Zero Trust (5 туннелей), JWT
  Go-сервисе и секретах в `secrets/`. Подробнее см.
  `security/security-policy.md`.

## Источники и ссылки

- Docker Compose: `compose.yml` (logging tiers, healthchecks, restart policies,
  GPU labels).
- Конфигурации: `env/*.env`, `conf/nginx`, `conf/redis/redis.conf`,
  `conf/litellm`, `conf/prometheus`.
- Мониторинг и runbooks: `docs/operations/monitoring-guide.md`,
  `docs/operations/automated-maintenance-guide.md`, `docs/operations/runbooks/`.
- Архитектура: `docs/architecture/architecture.md` (GPU allocation, Cloudflare tunnels, 30
  сервисов).
- Безопасность: `security/security-policy.md`,
  `docs/archive/reports/documentation-audit-2025-10-24.md` (указаны риски и необходимые
  актуализации).
