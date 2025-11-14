# ERNI-KI Monitoring & Logging Audit — 2025-11-14 (repeat)

## Scope & Method

- **Repository:** `erni-ki`
  (`/home/konstantin/Documents/augment-projects/erni-ki`).
- **What was reviewed:** `compose.yml`, Prometheus/Grafana/Alertmanager configs
  under `conf/prometheus` and `conf/alertmanager`, logging configs
  (`conf/fluent-bit/*`, `conf/loki/loki-config.yaml`), and runtime behaviour
  verified via `docker compose ps/logs` plus HTTP checks
  (`curl -H 'X-Scope-OrgID: erni-ki' http://localhost:3100/ready`,
  `curl -k https://localhost/health`, etc.).
- **Goal:** confirm the remediation landed earlier and identify remaining gaps
  against best practices (HA, retention, coverage, redaction, traceability).

## Stack Inventory (current)

| Layer         | Components (per `compose.yml`)                                                                                                              | Notes                                                                         |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| Metrics       | Prometheus v3.0.0, Alertmanager v0.27.0, Grafana v11.6.6, exporters for node/redis/postgres/ollama/nginx, cAdvisor (`compose.yml:582-910`). | Single instances, no remote storage.                                          |
| Logging       | Fluent Bit v3.1.0 (`compose.yml:986-1029`), Loki v3.0.0 with filesystem backend (`conf/loki/loki-config.yaml:1-35`).                        | All service profiles now send logs via `fluentd` driver (`compose.yml:6-56`). |
| Docs/Runbooks | `docs/operations/monitoring-guide.md` (snapshot before this audit), scripts under `scripts/monitoring` and `scripts/core/maintenance`.      | Guide still references phased rollouts but not new findings.                  |

## Findings & Recommendations

| Sev.      | Area                       | Observation                                                                                                                                                                                                                                                                                                           | Evidence                                                                   | Recommendation                                                                                                                                                                                                                                                     |
| --------- | -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 🔴 High   | Metrics durability         | Prometheus and Loki both run as single instances with local disk (`compose.yml:582-612`, `conf/loki/loki-config.yaml:1-35`). There is no retention policy beyond defaults (Loki) nor remote write / snapshots (Prom).                                                                                                 | Node loss = total loss of metrics/log history; no redundancy for alerting. | Introduce remote storage: e.g., Prometheus `remote_write` + Thanos/Promscale, and Loki boltdb-shipper + S3-compatible bucket. At minimum configure `loki` `compactor` and `limits_config.retention_period`. Consider hot-standby or HA pair for Prom/Alertmanager. |
| 🔴 High   | Alerting availability      | Alertmanager is single-instance with local state only (`compose.yml:691-710`). No gossip peers or external notification preview beyond Slack/PagerDuty secrets.                                                                                                                                                       | Loss of container drops all alerts.                                        | Run a second Alertmanager replica (dedicated container or cloud service) and configure Prometheus `alerting.alertmanagers` with both endpoints. Persist silences in a replicated store.                                                                            |
| 🟠 Medium | Metrics coverage           | Multiple jobs remain commented/disabled in `conf/prometheus/prometheus.yml` (auth-service, docling, EdgeTTS, SearXNG). No blackbox or HTTP synthetic checks for external endpoints.                                                                                                                                   | Missing jobs around lines 100-150.                                         | Define lightweight `/metrics` endpoints (or exporters) for these services, or explicitly document why they are excluded. Add blackbox exporter targets for `https://ki.erni-gruppe.ch/health` and webhook receivers to catch TLS/route regressions.                |
| 🟠 Medium | Logging delivery           | Fluent Bit only accepts `forward` input. There is no fallback `tail` or Kubernetes metadata, so backlog replay depends entirely on Docker’s log-driver. Additionally, no TLS/auth is configured between fluentd drivers and Fluent Bit or from Fluent Bit to Loki (`conf/fluent-bit/fluent-bit.conf:1-120, 180-205`). | Plaintext log transport; attacker on host can spoof logs.                  | Enable TLS certificates for Fluent Bit forward input (`#TLS`/`Shared_Key`), and secure Loki output via HTTPS/auth tokens. Consider re-enabling a `tail` input with rate-limits to capture json-file logs if Docker logging hiccups.                                |
| 🟠 Medium | Log processing errors      | Runtime inspection (`docker compose logs fluent-bit`) shows frequent `HTTP status=400 … entry too far behind` errors when backlog chunks flush; `conf/fluent-bit/fluent-bit.conf` lacks `Time_key` adjustments for legacy entries.                                                                                    | Errors observed at `2025-11-14 12:32:37`.                                  | Add `log` timestamp normalization (e.g., `Time_Key`/`Time_Format` per parser) or set Loki `max_age` limits to avoid repeated drops. Monitor Fluent Bit’s `.output["loki."].error` metric (currently >1k).                                                          |
| 🟠 Medium | Monitoring docs & runbooks | `docs/operations/monitoring-guide.md` still references phased rollouts and object storage plans but doesn’t include the latest remediation or the remaining risks above.                                                                                                                                              | Guide lines 8-60.                                                          | Update the guide with the new architecture, current limitations, and runbook steps for HA/retention rollout.                                                                                                                                                       |
| 🟡 Low    | Request tracing            | nginx now injects `X-Request-ID` for HTTP/HTTPS (`conf/nginx/nginx.conf:70-90`, `conf/nginx/conf.d/default.conf:70-115, 401-430`), and auth logs include the same ID (`auth/main.go:19-120`). However, Prometheus scrape/alert logs don’t attach correlation to Loki.                                                 | Observed via curl/logs.                                                    | Optional: forward request IDs into Loki labels (via Fluent Bit `modify Add request_id`).                                                                                                                                                                           |

## Coverage Checklist

| Component                | Logs in Loki                                                      | Metrics in Prometheus             | Health endpoint w/ Request-ID                                    |
| ------------------------ | ----------------------------------------------------------------- | --------------------------------- | ---------------------------------------------------------------- |
| Nginx                    | ✅ (`compose.yml:424-454` logging:critical)                       | ✅ (nginx-exporter job)           | ✅ (`conf/nginx/conf.d/default.conf:70-120`)                     |
| Auth                     | ✅ (`compose.yml:239-257`; structured JSON `auth/main.go:19-152`) | ❌ (auth service scrape disabled) | ✅ (`curl http://localhost:9092/health` includes `X-Request-ID`) |
| Docling / EdgeTTS / Tika | ✅ (via auxiliary logging profile)                                | ❌ (scrape jobs commented)        | Health only (Docling `/health`), no metrics.                     |
| Prometheus / Grafana     | ✅ (monitoring profile)                                           | N/A (self-monitored)              | HTTP health but no HA.                                           |
| Alertmanager             | ✅                                                                | ✅ (`job_name: "alertmanager"`)   | No redundancy.                                                   |

## Recommended Next Steps

1. **Durability upgrades (High priority).** Add object storage & compactor
   configs to Loki; enable Prometheus remote_write + scheduled snapshot exports;
   deploy second Alertmanager instance.
2. **Coverage improvements.** Instrument auth/docling/EdgeTTS via exporters or
   expose `/metrics`; add blackbox checks for public endpoints and Cron-based
   synthetic alerts for doc ingestion.
3. **Security hardening.** Enable TLS/shared keys for Fluent Bit forward input
   and Loki output; restrict Loki API via nginx/mTLS instead of plain HTTP on
   `127.0.0.1:3100`.
4. **Operational hygiene.** Document the above changes plus existing known
   limitations in `docs/operations/monitoring-guide.md`; create runbooks for
   backlog errors seen in Fluent Bit.
5. **Observability KPIs.** Track Fluent Bit `error`/`dropped_record` via
   Prometheus dashboards; add alerts when backlog grows or when `.error` spikes,
   ensuring the remediation stays healthy.

_Prepared: 2025‑11‑14_
