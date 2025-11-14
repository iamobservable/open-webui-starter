# ERNI-KI Monitoring Audit (November 2025)

This report documents the current state of the ERNI-KI observability stack,
highlights gaps against modern SRE/observability practices, and proposes a
phased refactoring roadmap. Evidence-based findings below reference concrete
configuration files checked into the repository.

## 1. Stack Snapshot (as-is)

| Layer         | Implementation                                                                                                                                          | Notes                                                                                                  |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| Metrics       | Single Prometheus `v3.0.0` container with local TSDB, alert rules, Alertmanager hookup (`compose.yml:577-617`, `conf/prometheus/prometheus.yml:1-384`). | Retention limited to `30d/10GB`; admin & lifecycle APIs exposed without auth; no remote write/replica. |
| Visualization | Grafana `v11.3.0` with file-based provisioning (`compose.yml:620-656`, `conf/grafana/provisioning/datasources/prometheus.yml:8-54`).                    | Datasource metadata still claims Prometheus `2.48.0`, dashboards stored locally only.                  |
| Alerting      | Alertmanager single instance with HTTP-only webhooks and SMTP placeholders (`conf/alertmanager/alertmanager.yml:4-150`).                                | Notifications never leave the cluster; cron scripts auto-restart services instead of paging humans.    |
| Logging       | Fluent Bit → Loki pipeline (`compose.yml:983-1024`, `conf/fluent-bit/fluent-bit.conf:10-200`, `conf/loki/loki-config.yaml:1-48`).                       | HTTP servers bound to `0.0.0.0`, filters drop entire classes of events, Loki auth disabled.            |
| Automation    | Host-level cron jobs & watchdog scripts (`conf/cron/logging-reports.cron:5-27`, `scripts/monitoring/alertmanager-queue-watch.sh:1-62`).                 | Cron outputs to `/var/log`, watchdogs restart services on thresholds without incident context.         |
| Documentation | `docs/operations/monitoring-guide.md`, `docs/archive/config-backup/*.md`.                                                                               | Guide enumerates exporters & scripts but lacks objective health scoring/SLO references.                |

## 2. Key Findings

### 2.1 Platform Resilience & Data Safety (High)

- Prometheus, Alertmanager, Grafana, Loki, and Fluent Bit all run as single
  containers with `watchtower` auto-updates turned on (`compose.yml:615-653`,
  `compose.yml:1021-1023`). There is no replica, warm standby, or remote write;
  a failed auto-update or disk loss wipes historical metrics/logs.
- Prometheus enables lifecycle/admin APIs without any auth or mTLS
  (`compose.yml:584-592`) and exposes them on the host network
  (`compose.yml:601`). Best practices require those endpoints to be disabled or
  fronted by auth.
- Loki explicitly disables auth (`conf/loki/loki-config.yaml:1-45`) and stores
  data on a single filesystem without compactor/retention monitoring, so any
  compromise yields full log access.

**Impact:** Loss of monitoring visibility during incidents, inability to meet
compliance/log retention obligations, and attack surface for lateral movement.

**Recommendations:**

1. Introduce remote_write to a managed Prometheus/LTS (e.g., VictoriaMetrics,
   Thanos) and schedule volume snapshots before enabling watchtower updates.
2. Disable `--web.enable-admin-api`/`--web.enable-lifecycle` or restrict via
   reverse proxy + mTLS; same for Grafana/Alertmanager UIs.
3. Convert Loki to the single-binary “simple scalable” mode with object storage
   (S3/minio) and enable auth + compactor cron; raise Fluent Bit disk buffer to
   survive >24h outages.

### 2.2 Alert Delivery & Runbook Hygiene (High)

- Alertmanager routes every severity to the local `webhook-receiver` (no Slack,
  PagerDuty, email) (`conf/alertmanager/alertmanager.yml:32-135`). SMTP
  credentials are blank and TLS disabled
  (`conf/alertmanager/alertmanager.yml:4-15`).
- Cron/watchdog scripts try to self-heal by restarting services instead of
  paging humans (`conf/cron/logging-reports.cron:5-27`,
  `scripts/monitoring/alertmanager-queue-watch.sh:1-61`). Queue overload merely
  triggers `docker compose restart alertmanager`
  (`scripts/monitoring/alertmanager-queue-watch.sh:54-60`).
- The Monitoring Guide touts watchdog scripts but doesn’t define on-call
  expectations or SLO breaches (`docs/operations/monitoring-guide.md:18-43`).

**Impact:** Critical outages can be silently “auto-remediated” without
visibility, and no one is paged if cron jobs or webhooks fail.

**Recommendations:**

1. Integrate Alertmanager with at least two independent channels (Slack/MS
   Teams + PagerDuty/Squadcast) and enforce TLS for SMTP/webhooks.
2. Replace auto-restart scripts with alert annotations/runbooks that guide
   responders; scripts may still gather context but should not restart core
   services autonomously.
3. Extend the documentation to map each alert to an owner, runbook URL, and
   escalation policy.

### 2.3 Coverage Gaps for Core Services (Medium)

- Multiple critical services lack metrics instrumentation and are merely
  commented out (“ОТКЛЮЧЕНО”) in Prometheus
  (`conf/prometheus/prometheus.yml:88-210` for Auth, Docling, Tika, EdgeTTS,
  Fluent Bit metrics, Webhook receiver, etc.).
- Blackbox jobs probe HTTP endpoints but do not validate workflows (e.g.,
  inference success, doc processing) nor capture RED metrics beyond basic
  `/health` responses (`conf/prometheus/prometheus.yml:224-347`).
- Grafana datasource metadata still references Prometheus 2.x
  (`conf/grafana/provisioning/datasources/prometheus.yml:21-33`), so
  auto-generated dashboards miss exemplars and native histograms available in
  v3.

**Impact:** Blind spots remain for document pipelines, MCP tooling, and logging
agents; regression at those layers won’t trigger alerts until user-visible
failure.

**Recommendations:**

1. Expose `/metrics` for Docling/Tika/EdgeTTS via lightweight sidecars or
   exporters; where impossible, add synthetic workflows (document upload/render)
   measured via blackbox.
2. Capture Fluent Bit output counters through the Prometheus exporter already
   enabled in config by actually scraping it (re-enable job) and alert on
   ingestion gaps.
3. Update Grafana datasources/dashboards to align with Prometheus 3.x features
   (exemplars, native histograms) and add SLO overlays.

### 2.4 Logging Pipeline Security & Fidelity (Medium)

- Fluent Bit HTTP server listens on `0.0.0.0:2020` while Compose overrides
  attempt to bind to `127.0.0.1` (`conf/fluent-bit/fluent-bit.conf:10-30`,
  `compose.yml:990-1018`). The config file wins, so unauthenticated
  metrics/control endpoints are exposed.
- The global forward input also listens on `0.0.0.0:24224`
  (`conf/fluent-bit/fluent-bit.conf:35-46`), allowing any container/host process
  to inject logs without auth.
- Aggressive `grep` filters drop all successful HTTP access logs and every DEBUG
  message (`conf/fluent-bit/fluent-bit.conf:56-137`), and disk buffering is
  capped at `1G` (`conf/fluent-bit/fluent-bit.conf:167-199`). Together this
  prevents forensic reconstruction and triggers data loss after ~minutes of Loki
  downtime.
- Loki’s `auth_enabled: false` compounds the issue by granting unrestricted log
  access (`conf/loki/loki-config.yaml:1-18`).

**Impact:** Inability to investigate incidents, potential tampering/injection of
logs, and exposure of log data to untrusted clients.

**Recommendations:**

1. Bind Fluent Bit/Loki HTTP interfaces to the monitoring network only, enforce
   basic auth or mTLS, and leverage Docker `extra_hosts` instead of exposing
   ports to localhost.
2. Replace blanket `grep` exclusions with structured filters or sampling so that
   at least one copy of nginx/access logs remains; keep DEBUG logs in cold
   storage rather than deleting at ingestion.
3. Increase `storage.total_limit_size` and move Fluent Bit DB to SSD-backed
   volume with logrotate integration; enable Loki multi-tenant auth or front it
   via Grafana Access Policy.

### 2.5 Operational Automation & Evidence (Medium)

- Cron definitions write to `/var/log/erni-ki-*.log` but there is no
  rotation/alerting for these host logs (`conf/cron/logging-reports.cron:5-27`).
  Failures silently accumulate.
- Runbook references (`docs/operations/monitoring-guide.md:18-43`) highlight
  scripts but do not state how results are reviewed or filed (no ticket
  automation, no dashboards summarizing cron health).
- Monitoring reports live under `docs/archive/config-backup` and require manual
  refresh; there is no CI/CD check verifying they match the current config.

**Impact:** Regressions in cron jobs or scripts go unnoticed until a backlog
accumulates, creating compliance and audit risk.

**Recommendations:**

1. Export cron/script status as metrics (e.g., via node_exporter textfile or
   pushgateway) and alert when reports fail or go stale.
2. Store watchdog outputs in Loki/Grafana dashboards rather than plain text
   logs; add CI validation to ensure documentation snapshots get updated
   alongside config changes.
3. Consider replacing host cron with a dedicated automation runner (e.g.,
   systemd timers in the repo or GitHub Actions) for better traceability.

## 3. Refactoring Roadmap

| Phase                                        | Window    | Goals                                                       | Key Actions                                                                                                                                                                                                                                                                                        |
| -------------------------------------------- | --------- | ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **0 – Stabilize & Secure**                   | Week 1    | Reduce blast radius, stop silent failures.                  | Disable Prom admin/admin APIs, restrict Fluent Bit/Loki endpoints, raise Fluent Bit disk buffer to 10–20 GB, wire Alertmanager to Slack + PagerDuty, add “cron freshness” alert using node_exporter textfile.                                                                                      |
| **1 – Coverage & Instrumentation**           | Weeks 2–3 | Close blind spots for document/LLM services.                | Build lightweight `/metrics` shims for Docling/Tika/EdgeTTS/LiteLLM, re-enable Fluent Bit Prometheus scrape, add synthetic workflows (doc upload, inference request) via blackbox exporter, update Grafana datasource metadata + dashboards for Prometheus 3.x, define RED/USE panels per service. |
| **2 – Data Durability & Observability SLOs** | Weeks 3–4 | Ensure monitoring data survives incidents and ties to SLOs. | Introduce remote_write → VictoriaMetrics/Thanos, snapshot Prometheus/Loki volumes before watchtower updates, migrate Loki to object storage with auth, define availability/error-budget SLOs per key service and map existing alerts to them.                                                      |
| **3 – Automation & Governance**              | Weeks 4–5 | Make scripts auditable and runbook-driven.                  | Replace host cron tasks with containerized systemd timers or GitHub workflows, publish watchdog outputs to Grafana, add CI job verifying docs vs config, document alert owners/escalations in `docs/operations/monitoring-guide.md` + link from Alertmanager annotations.                          |
| **4 – Continuous Improvement**               | Ongoing   | Keep parity with best practices.                            | Add unit tests for alert rules (promtool), adopt `monitoring` GitHub label for changes, schedule quarterly chaos tests (simulate exporter crashes/queue stalls) and record learnings.                                                                                                              |

## 4. Next Steps

1. Prioritize Phase 0 items as blocking debt and create corresponding Archon
   tasks (hardening, alert delivery, evidence metrics).
2. Socialize this report with Ops/ML teams; agree on owners for each phase and
   attach timeline to the ERNI-KI project board.
3. Once Phase 0 completes, update `docs/operations/monitoring-guide.md` with the
   new architecture diagram and embed SLO dashboards.

---

Prepared by Codex · 14 Nov 2025
