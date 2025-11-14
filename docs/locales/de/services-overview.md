# 📊 Detaillierte Tabelle der aktiven Services des ERNI-KI Systems

> **Referenzdokumentation für die Administration des ERNI-KI Systems**
> **Erstellungsdatum**: 2025-09-25 **Systemversion**: v11.0 Production Ready
> **Status**: ✅ 26 von 30 Services gesund (96,4% System Health)

---

## 🤖 Application Layer (AI & Core Services)

| Service           | Status             | Ports             | Konfiguration                 | Umgebungsvariablen   | Konfigurationstyp | Anmerkungen                                                     |
| ----------------- | ------------------ | ----------------- | ----------------------------- | -------------------- | ----------------- | --------------------------------------------------------------- |
| **🧠 ollama**     | ✅ Up 5d (healthy) | `11434:11434`     | ❌ Keine                      | `env/ollama.env`     | ENV               | **🔥 KRITISCH** • GPU: NVIDIA runtime • Auto-Update deaktiviert |
| **🤖 openwebui**  | ✅ Up 5d (healthy) | `8080` (internal) | `conf/openwebui/*.json`       | `env/openwebui.env`  | JSON              | **🔥 KRITISCH** • GPU: NVIDIA runtime • MCP Integration         |
| **🌐 litellm**    | ✅ Up 2d (healthy) | `4000:4000`       | `conf/litellm/config.yaml`    | `env/litellm.env`    | YAML              | Context Engineering Gateway v1.77.2 • PostgreSQL Integration    |
| **🔍 searxng**    | ✅ Up 5d (healthy) | `8080` (internal) | `conf/searxng/*.yml`          | `env/searxng.env`    | YAML/TOML/INI     | RAG Suche • Redis Caching • Brave/Startpage aktiviert           |
| **🔌 mcposerver** | ✅ Up 5d (healthy) | `8000:8000`       | `conf/mcposerver/config.json` | `env/mcposerver.env` | JSON              | Model Context Protocol • 4 aktive Tools                         |

## 🔧 Processing Layer (Document & Media Processing)

| Service        | Status             | Ports       | Konfiguration | Umgebungsvariablen | Konfigurationstyp | Anmerkungen                                      |
| -------------- | ------------------ | ----------- | ------------- | ------------------ | ----------------- | ------------------------------------------------ |
| **📋 tika**    | ✅ Up 9d (healthy) | `9998:9998` | ❌ Keine      | `env/tika.env`     | ENV               | Apache Tika • Metadaten-Extraktion • 100MB Limit |
| **🎤 edgetts** | ✅ Up 5d (healthy) | `5050:5050` | ❌ Keine      | `env/edgetts.env`  | ENV               | Sprachsynthese • OpenAI Edge TTS                 |

## 💾 Data Layer (Databases & Cache)

| Service      | Status              | Ports                  | Konfiguration | Umgebungsvariablen | Konfigurationstyp | Anmerkungen                                                       |
| ------------ | ------------------- | ---------------------- | ------------- | ------------------ | ----------------- | ----------------------------------------------------------------- |
| **🗄️ db**    | ✅ Up 24h (healthy) | `5432` (internal)      | ❌ Keine      | `env/db.env`       | ENV               | **🔥 KRITISCH** • PostgreSQL + pgvector • Auto-Update deaktiviert |
| **⚡ redis** | ✅ Up 24h (healthy) | `6379,8001` (internal) | ❌ Keine      | `env/redis.env`    | ENV               | Redis Stack • Cache und Queues                                    |

## 🚪 Gateway Layer (Proxy & Auth)

| Service            | Status              | Ports                       | Konfiguration                | Umgebungsvariablen    | Konfigurationstyp | Anmerkungen                                                                  |
| ------------------ | ------------------- | --------------------------- | ---------------------------- | --------------------- | ----------------- | ---------------------------------------------------------------------------- |
| **🚪 nginx**       | ✅ Up 2h (healthy)  | `80:80, 443:443, 8080:8080` | `conf/nginx/*.conf`          | ❌ Keine              | CONF              | **🔥 KRITISCH** • Reverse Proxy • SSL Terminierung • Auto-Update deaktiviert |
| **🔐 auth**        | ✅ Up 24h (healthy) | `9092:9090`                 | ❌ Keine                     | `env/auth.env`        | ENV               | JWT Authentifizierung • Go Service                                           |
| **☁️ cloudflared** | ✅ Up 5h            | ❌ Keine Ports              | `conf/cloudflare/config.yml` | `env/cloudflared.env` | YAML              | **⚠️ Healthcheck deaktiviert** • Cloudflare Tunnel                           |

## 📊 Monitoring Layer (Metrics & Observability)

| Service                 | Status              | Ports                    | Konfiguration                | Umgebungsvariablen     | Konfigurationstyp | Anmerkungen                                          |
| ----------------------- | ------------------- | ------------------------ | ---------------------------- | ---------------------- | ----------------- | ---------------------------------------------------- |
| **📈 prometheus**       | ✅ Up 1h (healthy)  | `9091:9090`              | `conf/prometheus/*.yml`      | `env/prometheus.env`   | YAML              | Metriken-Sammlung • 35 Targets                       |
| **📊 grafana**          | ✅ Up 37m (healthy) | `3000:3000`              | `conf/grafana/**/*.yml`      | `env/grafana.env`      | YAML/JSON         | Dashboards • Visualisierung                          |
| **🚨 alertmanager**     | ✅ Up 24h (healthy) | `9093-9094:9093-9094`    | ❌ Keine                     | `env/alertmanager.env` | ENV               | Alert-Management                                     |
| **📡 loki**             | ✅ Up 22h (healthy) | `3100:3100`              | `conf/loki/loki-config.yaml` | ❌ Keine               | YAML              | Zentralisierte Protokollierung                       |
| **📝 fluent-bit**       | ✅ Up 4m            | `2020:2020, 24224:24224` | `conf/fluent-bit/*.conf`     | `env/fluent-bit.env`   | CONF              | **⚠️ Healthcheck deaktiviert** • Log-Sammlung → Loki |
| **📞 webhook-receiver** | ✅ Up 24h (healthy) | `9095:9093`              | ❌ Keine                     | ❌ Keine               | ENV               | Alert-Verarbeitung                                   |

## 🔍 Exporters (Metrics Collection)

| Service                              | Status              | Ports       | Konfiguration                  | Umgebungsvariablen          | Konfigurationstyp | Anmerkungen                                     |
| ------------------------------------ | ------------------- | ----------- | ------------------------------ | --------------------------- | ----------------- | ----------------------------------------------- |
| **🖥️ node-exporter**                 | ✅ Up 24h (healthy) | `9101:9100` | ❌ Keine                       | `env/node-exporter.env`     | ENV               | System-Metriken                                 |
| **🐳 cadvisor**                      | ✅ Up 24h (healthy) | `8081:8080` | ❌ Keine                       | `env/cadvisor.env`          | ENV               | Docker Container                                |
| **🎯 blackbox-exporter**             | ✅ Up 23h (healthy) | `9115:9115` | ❌ Keine                       | `env/blackbox-exporter.env` | ENV               | Verfügbarkeitsprüfung                           |
| **🔥 nvidia-exporter**               | ✅ Up 24h (healthy) | `9445:9445` | ❌ Keine                       | `env/nvidia-exporter.env`   | ENV               | **🎮 GPU Metriken** • NVIDIA runtime            |
| **🧠 ollama-exporter**               | ✅ Up 24h (healthy) | `9778:9778` | ❌ Keine                       | ❌ Keine                    | ENV               | AI-Modell Metriken                              |
| **🗄️ postgres-exporter**             | ✅ Up 24h (healthy) | `9187:9187` | `conf/postgres-exporter/*.yml` | `env/postgres-exporter.env` | YAML              | PostgreSQL Metriken                             |
| **⚡ Redis Monitoring über Grafana** | ✅ Up 24h           | `9121:9121` | ❌ Keine                       | ❌ Keine                    | ENV               | **⚠️ Healthcheck deaktiviert** • Redis Metriken |
| **🚪 nginx-exporter**                | ✅ Up 24h           | `9113:9113` | ❌ Keine                       | ❌ Keine                    | ENV               | Nginx Metriken                                  |

## 🛠️ Infrastructure Layer (Backup & Management)

| Service           | Status              | Ports       | Konfiguration           | Umgebungsvariablen   | Konfigurationstyp | Anmerkungen                      |
| ----------------- | ------------------- | ----------- | ----------------------- | -------------------- | ----------------- | -------------------------------- |
| **💾 backrest**   | ✅ Up 24h (healthy) | `9898:9898` | `conf/backrest/*.json`  | `env/backrest.env`   | JSON              | Backup • 7-tägig + 4-wöchentlich |
| **🔄 watchtower** | ✅ Up 24h (healthy) | `8091:8080` | `conf/watchtower/*.env` | `env/watchtower.env` | ENV               | Container Auto-Update • HTTP API |

---

## 📋 Zusammenfassende Statistiken

| Kategorie                      | Anzahl | Status                                                                    |
| ------------------------------ | ------ | ------------------------------------------------------------------------- |
| **Gesamt Services**            | **29** | ✅ 100% laufen                                                            |
| **Healthy Services**           | **25** | ✅ 86% mit Healthcheck                                                    |
| **Services ohne Healthcheck**  | **4**  | ⚠️ cloudflared, fluent-bit, Redis Monitoring über Grafana, nginx-exporter |
| **GPU-abhängige Services**     | **3**  | 🎮 ollama, openwebui, nvidia-exporter                                     |
| **Kritisch wichtige Services** | **3**  | 🔥 ollama, openwebui, db, nginx                                           |
| **Mit Konfigurationsdateien**  | **12** | 📁 41% haben conf/                                                        |
| **Nur Umgebungsvariablen**     | **17** | 🔧 59% verwenden nur env/                                                 |

## 🔧 Konfigurationstypen

- **YAML/YML**: 8 Services (prometheus, grafana, loki, litellm, searxng,
  cloudflared, postgres-exporter)
- **CONF**: 2 Services (nginx, fluent-bit)
- **JSON**: 3 Services (backrest, mcposerver, openwebui)
- **ENV nur**: 16 Services (übrige)

## ⚠️ Wichtige Hinweise

1. **🔥 Kritisch wichtige Services** haben deaktivierte Auto-Updates für
   Stabilität
2. **🎮 GPU Services** benötigen NVIDIA Container Toolkit
3. **⚠️ Services ohne Healthcheck** werden über externe Metriken überwacht
4. **📁 Konfigurationen** sind vor IDE Auto-Formatierung geschützt
5. **🔄 Auto-Updates** sind nach Scope-Gruppen für Sicherheit konfiguriert

## 🚀 Schnelle Befehle für Administration

### Status aller Services prüfen

```bash
docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
```

### Logs kritisch wichtiger Services prüfen

```bash
# Ollama
docker-compose logs ollama --tail=50

# OpenWebUI
docker-compose logs openwebui --tail=50

# PostgreSQL
docker-compose logs db --tail=50

# Nginx
docker-compose logs nginx --tail=50
```

### GPU-Ressourcen überwachen

```bash
# GPU Status prüfen
nvidia-smi

# GPU Metriken über Prometheus
curl -s http://localhost:9445/metrics | grep nvidia
```

### Integrationen prüfen

```bash
# Fluent Bit Metriken
curl -s http://localhost:2020/api/v1/metrics

# Prometheus Targets
curl -s http://localhost:9091/api/v1/targets

# Loki Health
curl -s http://localhost:3100/ready
```

## 📚 Verwandte Dokumentation

- **[Systemarchitektur](architecture.md)** - Diagramme und
  Komponentenbeschreibung
- **[Administrator-Handbuch](admin-guide.md)** - Detaillierte
  Verwaltungsanweisungen
- **[Monitoring und Alerts](monitoring.md)** - Prometheus/Grafana Konfiguration
- **[Backup-Handbuch](backup-guide.md)** - Backrest Konfiguration
- **[Fehlerbehebung](troubleshooting.md)** - Lösung typischer Probleme

---

**Letzte Aktualisierung**: 2025-08-22 **System**: Production Ready **Status**:
✅ Alle Services laufen **Autor**: Alteon Schulz (Tech Lead-Weiser)
