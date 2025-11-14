# ERNI-KI Documentation Hub

ERNI-KI — production-ready AI платформа на базе OpenWebUI, Ollama, LiteLLM и
MCP, окружённая полным стеком наблюдаемости, мониторинга и безопасности. Здесь
собраны актуальные гайды для DevOps/SRE и ML-инженеров, ответственные за
стабильность, операции и развитие платформы.

## Обновления

<!-- STATUS_SNIPPET_START -->

> **Статус системы (2025-11-14) — Production Ready v12.1**
>
> - Контейнеры: 30/30 контейнеров healthy
> - Графана: 18/18 Grafana дашбордов
> - Алерты: 27 Prometheus alert rules активны
> - AI/GPU: Ollama 0.12.3 + OpenWebUI v0.6.34 (GPU)
> - Context & RAG: LiteLLM v1.77.3-stable + Context7, Docling, Tika, EdgeTTS
> - Мониторинг: Prometheus v3.0.1, Grafana v11.6.6, Loki v3.5.5, Fluent Bit
>   v3.2.0, Alertmanager v0.28.0
> - Автоматизация: Cron: PostgreSQL VACUUM 03:00, Docker cleanup 04:00, Backrest
>   01:30, Watchtower selective updates
> - Примечание: Наблюдаемость и AI стек актуализированы в ноябре 2025

<!-- STATUS_SNIPPET_END -->

## Быстрые переходы

- **Архитектура и сервисы** — `architecture/architecture.md`,
  `architecture/service-inventory.md`, `architecture/services-overview.md`.
- **Операции** — `operations/operations-handbook.md`,
  `operations/monitoring-guide.md`, `operations/automated-maintenance-guide.md`,
  `operations/runbooks/`.
- **Хранилище и данные** — `docs/data/database-monitoring-plan.md`,
  `docs/data/redis-operations-guide.md`,
  `docs/data/database-production-optimizations.md`.
- **ML и API** — `reference/api-reference.md`, `README.md` (вне MkDocs, но
  всегда актуален в корне репозитория).
- **Безопасность** — `security/security-policy.md` и related compliance notes.

> Для быстрых решений используйте Archon (runbooks, checklists, status updates)
> и держите синхронизацию с этими материалами.
