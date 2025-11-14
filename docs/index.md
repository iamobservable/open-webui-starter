# ERNI-KI Documentation Hub

ERNI-KI — production-ready AI платформа на базе OpenWebUI, Ollama, LiteLLM и
MCP, окружённая полным стеком наблюдаемости, мониторинга и безопасности. Здесь
собраны актуальные гайды для DevOps/SRE и ML-инженеров, ответственные за
стабильность, операции и развитие платформы.

## Обновления

- 30/30 контейнеров Healthy, GPU ускорено (Ollama 0.12.3 + OpenWebUI v0.6.34).
- Мониторинг: Prometheus v3.0.1 + 27 алертов, Grafana v11.6.6, Loki v3.5.5,
  Fluent Bit v3.2.0.
- Avtomated tasks: PostgreSQL VACUUM (воскресенье 03:00), Docker cleanup
  (воскресенье 04:00), log rotation и Backrest бэкапы.

## Быстрые переходы

- **Архитектура и сервисы** — `architecture/architecture.md`,
  `architecture/service-inventory.md`, `architecture/services-overview.md`.
- **Операции** — `operations/operations-handbook.md`,
  `operations/monitoring-guide.md`, `operations/automated-maintenance-guide.md`,
  `operations/runbooks/`.
- **ML и API** — `reference/api-reference.md`, `README.md` (вне MkDocs, но
  всегда актуален в корне репозитория).
- **Безопасность** — `security/security-policy.md` и related compliance notes.

> Для быстрых решений используйте Archon (runbooks, checklists, status updates)
> и держите синхронизацию с этими материалами.
