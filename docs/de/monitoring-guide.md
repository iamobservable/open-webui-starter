# 📊 ERNI-KI Monitoring-Leitfaden

Umfassender Leitfaden für die Überwachung des ERNI-KI Systems mit 9
spezialisierten Exporters, standardisierten Healthchecks und produktionsreifen
Observability-Stack.

## 🎯 Überblick

Das ERNI-KI Monitoring-System umfasst:

- **9 spezialisierte Exporters** - optimiert und standardisiert (25.
  September 2025)
- **Prometheus v2.55.1** - Metriken-Sammlung und -Speicherung
- **Grafana** - 18 Dashboards (100% funktional) - Visualisierung
- **Loki + Fluent Bit** - zentralisierte Protokollierung
- **AlertManager** - Benachrichtigungen und Alarmierung
- **System Health:** 96,4% (26/30 Container gesund)

## 📈 Exporter-Konfiguration

### 🖥️ Node Exporter (Port 9101)

**Zweck:** Systemebene-Metriken (CPU, Speicher, Festplatte, Netzwerk)

**Status:** ✅ Healthy | HTTP 200 | Standard wget healthcheck

**Wichtige Metriken:**

- `node_cpu_seconds_total` - CPU-Nutzung nach Modus
- `node_memory_MemAvailable_bytes` - verfügbarer Speicher
- `node_filesystem_avail_bytes` - verfügbarer Festplattenspeicher
- `node_load1` - 1-Minuten-Lastdurchschnitt

**Gesundheitsprüfung:**

```bash
curl -s http://localhost:9101/metrics | grep node_up
```

### 🐘 PostgreSQL Exporter (Port 9187)

**Zweck:** Datenbankleistung und Gesundheitsmetriken

**Status:** ✅ Healthy | HTTP 200 | Standard wget healthcheck

**Wichtige Metriken:**

- `pg_up` - PostgreSQL-Verfügbarkeit
- `pg_stat_activity_count` - aktive Verbindungen
- `pg_stat_database_blks_hit` / `pg_stat_database_blks_read` - Cache-Hit-Ratio
- `pg_locks_count` - Datenbank-Sperren

**Gesundheitsprüfung:**

```bash
curl -s http://localhost:9187/metrics | grep pg_up
```

### 🔴 Redis Exporter (Port 9121) - 🔧 Behoben 19.09.2025

**Zweck:** Redis Cache-Leistung und Gesundheitsmetriken

**Status:** 🔧 Running | HTTP 200 | TCP healthcheck (behoben von wget)
**Problem:** Redis-Authentifizierung (nicht kritisch für HTTP-Metriken-Endpunkt)

**Konfiguration (BEHOBEN):**

```yaml
redis-exporter:
  image: oliver006/redis_exporter:v1.62.0
  ports:
    - '127.0.0.1:9121:9121'
  environment:
    - REDIS_EXPORTER_INCL_SYSTEM_METRICS=true
    - REDIS_EXPORTER_LOG_FORMAT=txt
    - REDIS_EXPORTER_DEBUG=true
    - REDIS_ADDR=redis://redis:6379
    - REDIS_PASSWORD_FILE=/run/secrets/redis_exporter_url
  secrets:
    - redis_exporter_url
  healthcheck: {} # Überwachung via Prometheus Scrape
```

**Wichtige Metriken:**

- `redis_up` - Redis-Verfügbarkeit (korrekt dank Passwortdatei)

> Das Secret `redis_exporter_url` enthält jetzt eine JSON-Map
> `{"redis://redis:6379":"<passwort>"}`, sodass der Exporter das Kennwort anhand
> der Adresse auswählt.

- `redis_memory_used_bytes` - Speichernutzung
- `redis_connected_clients` - verbundene Clients
- `redis_keyspace_hits_total` / `redis_keyspace_misses_total` - Hit-Ratio

**Gesundheitsprüfung:**

```bash
# HTTP-Endpunkt funktioniert (gibt Metriken zurück)
curl -s http://localhost:9121/metrics | head -5

# TCP-Healthcheck
timeout 5 sh -c '</dev/tcp/localhost/9121' && echo "Redis Exporter verfügbar"

# Direkte Redis-Prüfung (mit Passwort)
docker exec erni-ki-redis-1 redis-cli -a ErniKiRedisSecurePassword2024 ping
```

### 🎮 NVIDIA GPU Exporter (Port 9445) - ✅ Verbessert 19.09.2025

**Zweck:** GPU-Auslastung und Leistungsmetriken

**Status:** ✅ Healthy | HTTP 200 | TCP healthcheck (verbessert von pgrep)

**Konfiguration (VERBESSERT):**

```yaml
nvidia-exporter:
  image: mindprince/nvidia_gpu_prometheus_exporter:0.1
  ports:
    - '9445:9445'
  healthcheck:
    test: ['CMD-SHELL', "timeout 5 sh -c '</dev/tcp/localhost/9445' || exit 1"] # VERBESSERT: TCP-Prüfung
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 15s
```

**Wichtige Metriken:**

- `nvidia_gpu_utilization_gpu` - GPU-Auslastung in Prozent
- `nvidia_gpu_memory_used_bytes` - GPU-Speichernutzung
- `nvidia_gpu_temperature_celsius` - GPU-Temperatur
- `nvidia_gpu_power_draw_watts` - Stromverbrauch

**Gesundheitsprüfung:**

```bash
curl -s http://localhost:9445/metrics | grep nvidia_gpu_utilization
```

### 📦 Blackbox Exporter (Port 9115)

**Zweck:** Überwachung der Verfügbarkeit externer Services

**Status:** ✅ Healthy | HTTP 200 | Standard wget healthcheck

**Wichtige Metriken:**

- `probe_success` - Probe-Erfolgsstatus
- `probe_duration_seconds` - Probe-Dauer
- `probe_http_status_code` - HTTP-Antwortcode

**Gesundheitsprüfung:**

```bash
curl -s http://localhost:9115/metrics | grep probe_success
```

### 🧠 Ollama AI Exporter (Port 9778) - ✅ Standardisiert 19.09.2025

**Zweck:** AI-Modell-Leistung und Verfügbarkeitsmetriken

**Status:** ✅ Healthy | HTTP 200 | wget healthcheck (standardisiert von
127.0.0.1)

**Konfiguration (STANDARDISIERT):**

```yaml
ollama-exporter:
  build:
    context: ./monitoring
    dockerfile: Dockerfile.ollama-exporter
  ports:
    - '127.0.0.1:9778:9778'
  environment:
    - OLLAMA_URL=http://ollama:11434
    - EXPORTER_PORT=9778
```

**Wichtige Metriken:**

- `ollama_models_total` - Gesamtzahl der Modelle
- `ollama_model_size_bytes{model="model_name"}` - Modellgrößen
- `ollama_info{version="x.x.x"}` - Ollama-Version
- GPU-Nutzung für AI-Workloads

**Gesundheitsprüfung:**

```bash
curl -s http://localhost:9778/metrics | grep ollama_models_total
```

### 🚪 Nginx Web Exporter (Port 9113) - 🔧 Behoben 19.09.2025

**Zweck:** Webserver-Leistung und Traffic-Metriken

**Status:** 🔧 Running | HTTP 200 | TCP healthcheck (behoben von wget)

**Konfiguration (BEHOBEN):**

```yaml
nginx-exporter:
  image: nginx/nginx-prometheus-exporter:1.1.0
  ports:
    - '9113:9113'
  command:
    - '--nginx.scrape-uri=http://nginx:80/nginx_status'
    - '--web.listen-address=:9113'
  healthcheck:
    test: ['CMD-SHELL', "timeout 5 sh -c '</dev/tcp/localhost/9113' || exit 1"] # BEHOBEN: TCP-Prüfung
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 10s
```

**Wichtige Metriken:**

- `nginx_connections_active` - aktive Verbindungen
- `nginx_connections_accepted` - akzeptierte Verbindungen
- `nginx_http_requests_total` - gesamte HTTP-Anfragen
- `nginx_connections_handled` - behandelte Verbindungen

**Gesundheitsprüfung:**

```bash
# HTTP-Endpunkt funktioniert
curl -s http://localhost:9113/metrics | grep nginx_connections_active

# TCP-Healthcheck
timeout 5 sh -c '</dev/tcp/localhost/9113' && echo "Nginx Exporter verfügbar"
```

### 📈 RAG SLA Exporter (Port 9808)

**Zweck:** RAG (Retrieval-Augmented Generation) Leistungsmetriken

**Status:** ✅ Healthy | HTTP 200 | Python healthcheck

**Wichtige Metriken:**

- `erni_ki_rag_response_latency_seconds` - RAG-Antwortlatenz-Histogramm
- `erni_ki_rag_sources_count` - Anzahl der Quellen in der Antwort
- RAG-Verfügbarkeit und Leistungs-SLA-Tracking

**Gesundheitsprüfung:**

```bash
curl -s http://localhost:9808/metrics | grep erni_ki_rag_response_latency
```

## 🔧 Healthcheck-Standardisierung

### Probleme und Lösungen (19. September 2025)

| Exporter            | Problem                           | Lösung                                 | Status            |
| ------------------- | --------------------------------- | -------------------------------------- | ----------------- |
| **Redis Exporter**  | wget nicht verfügbar im Container | TCP-Prüfung `</dev/tcp/localhost/9121` | 🔧 Behoben        |
| **Nginx Exporter**  | wget nicht verfügbar im Container | TCP-Prüfung `</dev/tcp/localhost/9113` | 🔧 Behoben        |
| **NVIDIA Exporter** | pgrep-Prozess ineffizient         | TCP-Prüfung `</dev/tcp/localhost/9445` | ✅ Verbessert     |
| **Ollama Exporter** | 127.0.0.1 statt localhost         | wget localhost standardisiert          | ✅ Standardisiert |

### Standard-Healthcheck-Methoden

```yaml
# TCP-Prüfung (für minimale Container ohne wget/curl)
healthcheck:
  test: ["CMD-SHELL", "timeout 5 sh -c '</dev/tcp/localhost/PORT' || exit 1"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 10s

# HTTP-Prüfung (für Container mit wget)
healthcheck:
  test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:PORT/metrics || exit 1"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 10s

# Benutzerdefinierte Prüfung (für spezialisierte Container)
healthcheck:
  test: ["CMD-SHELL", "python -c \"import requests; requests.get('http://localhost:PORT/metrics')\""]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 10s
```

## 📊 Metriken-Verifikation

### Status-Prüfung aller Exporters

```bash
# HTTP-Status aller Exporters prüfen
for port in 9101 9187 9121 9445 9115 9778 9113 9808; do
  echo "Port $port: $(curl -s -o /dev/null -w "%{http_code}" http://localhost:$port/metrics)"
done

# Erwartete Ausgabe: Alle Ports sollten 200 zurückgeben
```

### Docker-Gesundheitsstatus

```bash
# Docker-Gesundheitsstatus prüfen
docker ps --format "table {{.Names}}\t{{.Status}}" | grep exporter

# Spezifische Healthcheck-Details prüfen
docker inspect erni-ki-Redis Monitoring über Grafana --format='{{.State.Health.Status}}'
```

## 🚨 Fehlerbehebungsleitfaden

### Häufige Probleme und Lösungen

#### 1. Exporter gibt HTTP 200 zurück, aber Docker zeigt keinen Gesundheitsstatus

**Problem:** Healthcheck-Konfiguration verwendet nicht verfügbare Tools
(wget/curl) **Lösung:** TCP-Prüfung für minimale Container verwenden

```bash
# Diagnose
docker inspect CONTAINER_NAME --format='{{.State.Health}}'

# Wenn <nil> zurückgegeben wird, funktioniert Healthcheck nicht
# Lösung: compose.yml mit TCP-Prüfung aktualisieren
healthcheck:
  test: ["CMD-SHELL", "timeout 5 sh -c '</dev/tcp/localhost/PORT' || exit 1"]
```

#### 2. Redis Exporter zeigt redis_up = 0

**Problem:** Authentifizierungsproblem mit Redis **Lösung:**
Redis-Verbindungsstring und Passwort überprüfen

```bash
# Redis-Verbindung direkt testen
docker exec erni-ki-redis-1 redis-cli -a ErniKiRedisSecurePassword2024 ping

# Redis Exporter Logs prüfen
docker logs erni-ki-Redis Monitoring über Grafana --tail 20
```

## 🎯 Erfolgskriterien

Nach der Fehlerbehebung überprüfen:

- ✅ Alle 8 Exporters geben HTTP 200 auf /metrics zurück
- ✅ Docker-Healthcheck zeigt healthy/running Status
- ✅ Keine Fehlermeldungen in Container-Logs
- ✅ Metriken enthalten erwartete Daten
- ✅ Ressourcennutzung innerhalb normaler Grenzen

## 🔗 Verwandte Dokumentation

- [Admin-Leitfaden](admin-guide.md) - Systemverwaltung
- [Architektur](architecture.md) - Systemarchitektur
- [Installationsanleitung](installation-guide.md) - Setup-Anweisungen
