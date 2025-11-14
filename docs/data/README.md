# Data & Storage Overview

> **Актуальность:** ноябрь 2025 (Release v12.1).  
> Используйте этот раздел как точку входа перед переходом к отдельным гайдам.

## Краткое состояние

| Компонент         | Статус / инструкция                                              | Последнее обновление |
| ----------------- | ---------------------------------------------------------------- | -------------------- |
| PostgreSQL 17     | `database-monitoring-plan.md`, `database-production-optimizations.md` – описывают pgvector, VACUUM, алерты. | 2025-10 |
| Redis 7-alpine    | `redis-monitoring-grafana.md`, `redis-operations-guide.md` – дефрагментация, watchdog, мониторинг Grafana. | 2025-10 |
| vLLM / LiteLLM    | `vllm-resource-optimization.md` + скрипты `scripts/monitor-litellm-memory.sh`, `scripts/redis-performance-optimization.sh`. | 2025-11 |
| Troubleshooting   | `database-troubleshooting.md` – чек-листы по latency/locks, pgvector, бэкапы. | 2025-10 |

## Как поддерживать актуальность

1. При изменении настроек PostgreSQL/Redis обновляйте соответствующий файл из
   таблицы и фиксируйте дату в разделе «Краткое состояние».
2. При релизе новых версий (LiteLLM/RAG) – синхронизируйте статус с
   `README.md` (раздел Data & Storage) и `docs/overview.md`.
3. Используйте `docs/archive/config-backup/monitoring-report*` для фиксации
   cron-результатов и ссылок на эти гайд-страницы.
