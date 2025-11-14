# Operations Handbook ERNI-KI

Сводный справочник для DevOps/SRE, управляющих наблюдаемостью, SLA и реакцией на
инциденты.

## 1. Цель

- Поддерживать 30 production-сервисов Healthy (см. `README.md`).
- Обеспечить идентичность по версиям (OpenWebUI v0.6.34, Prometheus v3.0.1,
  Grafana v11.6.6).
- Поддерживать response targets по 27 активным alert rules и ежедневным
  cron-скриптам.

## 2. Алерты и мониторинг

- Все правила задокументированы в `conf/prometheus/alerts.yml` (Critical,
  Performance, Database, GPU, Nginx). Подробнее —
  `docs/operations/monitoring-guide.md` (раздел «Prometheus Alerts
  Configuration»).
- SLA: критические алерты — ответ <5 мин, багфиксы и triage в течение 30 мин.
- Alertmanager v0.28.0 описывает каналы (Slack/Teams) и throttling; команды
  включают owner (SRE) и backup (Platform Lead).
- Журналирование идет через Fluent Bit → Loki и `json-file` для критичных
  сервисов (OpenWebUI, Ollama, PostgreSQL, Nginx).

## 3. Процесс реагирования

1. Проверить `docker compose ps` → `docker compose logs <service>` → `curl` на
   метрики.
2. Сравнить с дашбордами Grafana (GPU/LLM/DB). Тики: `monitoring-guide.md`
   описывает healthcheck-паттерны для экспортеров (TCP, wget, Python).
3. Если алерт критический: отправить уведомление через Alertmanager и открыть
   тикет в Archon (tasks/report). Зафиксировать статус, токены, команды (SRE
   Primary, Platform Backup).
4. Для сенсометра (non-critical) выполнить
   `runbooks/service-restart-procedures.md` или `troubleshooting-guide.md`.

## 4. Автоматизация обслуживания

- Все скрипты VACUUM и Docker cleanup описаны в
  `docs/operations/automated-maintenance-guide.md`. Запускаются по cron (VACUUM
  03:00, cleanup 04:00, log rotation daily, Backrest backups 01:30).
- Результаты проверяются через утилиты: `pg_isready`, `docker image prune`,
  `docker builder prune`, `docker volume prune`.
- При сбоях скриптов — см. `runbooks/backup-restore-procedures.md` для
  восстановления, `runbooks/configuration-change-process.md` для миграций
  конфигов.
- **Новые ноябрьские задачи:**
  - `scripts/maintenance/docling-shared-cleanup.sh` — очищает Docling shared
    volume и восстанавливает права (cron job **docling_shared_cleanup**).
  - `scripts/maintenance/redis-fragmentation-watchdog.sh` — следит за
    `redis_memory_fragmentation_ratio`, при >4 включает `activedefrag` и может
    рестартовать контейнер.
  - `scripts/monitoring/alertmanager-queue-watch.sh` — анализирует очередь
    Alertmanager (`alertmanager_cluster_messages_queued`) и выполняет защитный
    рестарт с записью в журнал `logs/alertmanager-queue.log`.
  - `scripts/infrastructure/security/monitor-certificates.sh` — следит за
    истечением TLS/Cloudflare сертификатов и перезапускает nginx/watchtower при
    необходимости.

## 5. Runbooks и playbooks

- `runbooks/service-restart-procedures.md` — безопасные перезапуски,
  healthchecks перед/после.
- `runbooks/troubleshooting-guide.md` — типовые проблемы (GPU, RAG, Redis) и
  команды `docker logs`, `nvidia-smi`, `curl`.
- `runbooks/docling-shared-volume.md` — специальные действия по очистке Docling
  shared volume и Fluent Bit.

## 6. Healthchecks & metrics

- Метрики всех экспортеров на `monitoring-guide.md`: node-exporter, Redis,
  PostgreSQL (с IPv4/IPv6 proxy), Nvidia, Blackbox, Ollama, Nginx, RAG.
- Рекомендуется запускать `curl -s http://localhost:PORT/metrics | head` для
  сверки и `docker inspect ... State.Health`.
- Использовать `docker compose top` и `docker stats` для просмотра процесса.

## 7. Data & Storage документация

- **Планы и оптимизации БД:** `docs/data/database-monitoring-plan.md`,
  `docs/data/database-production-optimizations.md`,
  `docs/data/database-troubleshooting.md`.
- **Redis:** `docs/data/redis-monitoring-grafana.md`,
  `docs/data/redis-operations-guide.md`.
- **vLLM / LiteLLM ресурсы:** `docs/data/vllm-resource-optimization.md` +
  скрипты `scripts/monitor-litellm-memory.sh`,
  `scripts/redis-performance-optimization.sh`.
- В runbooks фиксируйте ссылки на соответствующие Data-документы при выполнении
  maintenance (pgvector VACUUM, Redis defrag, Backrest restore).

## 8. Ссылки и источники

- Architecture → `docs/architecture/architecture.md`.
- Monitoring → `docs/operations/monitoring-guide.md`, `conf/prometheus`,
  `conf/grafana`.
- Automation → `docs/operations/automated-maintenance-guide.md`,
  `scripts/maintenance`.
- Runbooks → `docs/operations/runbooks/*.md`.
- Archon — обновлять короткие статусные заметки и чек-листы по каждому инциденту
  (см. task `a0169e05…`).

## 9. LiteLLM Context & RAG контроль

- LiteLLM v1.77.3-stable обслуживает Context Engineering и Context7 (Thinking
  tokens, `/lite/api/v1/think`). Убедитесь, что gateway доступен на
  `http://localhost:4000/health/liveliness`.
- `scripts/monitor-litellm-memory.sh` — cron/Ad-hoc проверка потребления памяти
  LiteLLM и отправка webhooks/Slack при превышении порога (по умолчанию 80%).
- `scripts/infrastructure/monitoring/test-network-performance.sh` — комплексная
  проверка RTT между nginx ↔ LiteLLM ↔ Ollama/PostgreSQL/Redis; при деградации
  latentcies фиксируйте результат в Archon.
- При инцидентах Context7 используйте `docs/reference/api-reference.md` и
  `docs/reference/mcpo-integration-guide.md` (раздел «Context7 & LiteLLM
  routing») и синхронизируйте статус с новым YAML блоком
  `docs/reference/status.yml`.

## 10. Архивы и отчётность

- Обзор: `docs/archive/README.md` (ссылки на audits/diagnostics/incidents).
- Compliance и документация: `docs/archive/audits/README.md`.
- Диагностика: `docs/archive/diagnostics/README.md` (используйте при RCA).
- Инциденты и remediation: `docs/archive/incidents/README.md`.
- Cron/monitoring логи и конфигурации:
  `docs/archive/config-backup/monitoring-report-2025-10-02.md`,
  `update-analysis-2025-10-02.md`, `update-execution-report-2025-10-02.md`. При
  обновлении скриптов фиксируйте изменения в этих отчётах или создавайте новые
  файлы в config-backup.
