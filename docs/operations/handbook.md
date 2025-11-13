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
  Performance, Database, GPU, Nginx). Подробнее — `docs/monitoring-guide.md`
  (раздел «Prometheus Alerts Configuration»).
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
  `docs/automated-maintenance-guide.md`. Запускаются по cron (VACUUM 03:00,
  cleanup 04:00, log rotation daily, Backrest backups 01:30).
- Результаты проверяются через утилиты: `pg_isready`, `docker image prune`,
  `docker builder prune`, `docker volume prune`.
- При сбоях скриптов — см. `runbooks/backup-restore-procedures.md` для
  восстановления, `runbooks/configuration-change-process.md` для миграций
  конфигов.

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

## 7. Ссылки и источники

- Architecture → `docs/architecture.md`.
- Monitoring → `docs/monitoring-guide.md`, `conf/prometheus`, `conf/grafana`.
- Automation → `docs/automated-maintenance-guide.md`, `scripts/maintenance`.
- Runbooks → `docs/runbooks/*.md`.
- Archon — обновлять короткие статусные заметки и чек-листы по каждому инциденту
  (см. task `a0169e05…`).
