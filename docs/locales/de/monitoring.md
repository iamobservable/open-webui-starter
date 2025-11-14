# Monitoring Übersicht (DE)

Aktueller Stack (November 2025):

- **Prometheus v3.0.1** + 27 Alert Rules
- **Grafana v11.6.6**, **Loki v3.5.5**, **Fluent Bit v3.2.0**
- **Alertmanager v0.28.0** inkl. Queue-Watchdog
- Automatisierte Skripte:
  - `scripts/monitoring/alertmanager-queue-watch.sh`
  - `scripts/maintenance/docling-shared-cleanup.sh`
  - `scripts/maintenance/redis-fragmentation-watchdog.sh`
  - `scripts/monitor-litellm-memory.sh`
  - `scripts/infrastructure/monitoring/test-network-performance.sh`

Weitere Details:

- **Monitoring Guide (EN):** `docs/operations/monitoring-guide.md` –
  Healthchecks, Ports, Exporter.
- **Operations Handbook (EN):** `docs/operations/operations-handbook.md` – SLA,
  on-call, cron-Aufgaben.
- **Archive Diagnostics:** `docs/archive/diagnostics/README.md` – detaillierte
  Server/RAG-Berichte.

### Beispielchecks

```bash
# Prometheus Health
curl -s http://localhost:9091/-/ready

# LiteLLM Gateway
curl -s http://localhost:4000/health/liveliness

# Alertmanager Queue Watchdog Log
tail -n 50 logs/alertmanager-queue.log
```

> Diese Abläufe spiegeln den englischen Monitoring Guide wider – Ergebnisse
> bitte im jeweiligen Archon-Task dokumentieren.
