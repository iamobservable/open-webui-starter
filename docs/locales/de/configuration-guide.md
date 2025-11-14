# 🔧 ERNI-KI Konfigurationsleitfaden

> **Version:** 11.0 **Aktualisierungsdatum:** 2025-09-25 **Status:** Production
> Ready

Dieser Leitfaden enthält production-ready Konfigurationen für alle Komponenten
des ERNI-KI Systems mit deutschen Kommentaren für wichtige Einstellungen.

## 📋 Konfigurationsübersicht

Das ERNI-KI System verwendet eine modulare Konfigurationsstruktur:

```
env/                    # Umgebungsvariablen für jeden Service
├── openwebui.env      # Haupt-AI-Interface
├── ollama.env         # LLM Server mit GPU
├── litellm.env        # Context Engineering Gateway
├── mcposerver.env     # Model Context Protocol
├── searxng.env        # Suchmaschine
├── tika.env           # Metadaten-Extraktion
└── ...

conf/                   # Konfigurationsdateien
├── nginx/             # Reverse Proxy Konfiguration
├── prometheus/        # Metriken-Monitoring
├── grafana/           # Dashboards und Visualisierung
├── litellm/           # LLM Gateway Einstellungen
└── ...
```

## 🤖 AI & ML Services

### OpenWebUI Konfiguration

**Datei:** `env/openwebui.env`

```bash
# === GRUNDEINSTELLUNGEN ===
WEBUI_NAME="ERNI-KI AI Platform"
WEBUI_URL="https://ki.erni-gruppe.ch"

# === SICHERHEIT ===
WEBUI_SECRET_KEY="your-secret-key-here"  # KRITISCH: Eindeutigen Schlüssel verwenden # pragma: allowlist secret
ENABLE_SIGNUP=false                       # Registrierung in Production deaktivieren
DEFAULT_USER_ROLE="user"                  # Standard-Rolle für neue Benutzer
CORS_ALLOW_ORIGIN="https://diz.zone;https://webui.diz.zone;https://ki.erni-gruppe.ch;https://192.168.62.153;http://192.168.62.153:8080"  # Origins mit ';' trennen

# === GPU BESCHLEUNIGUNG ===
NVIDIA_VISIBLE_DEVICES=all                # Zugriff auf alle GPUs
NVIDIA_DRIVER_CAPABILITIES=compute,utility # Erforderliche Treiber-Funktionen

# === INTEGRATIONEN ===
OLLAMA_BASE_URL="http://ollama:11434"     # Verbindung zu Ollama
LITELLM_BASE_URL="http://litellm:4000"    # LiteLLM Gateway
SEARXNG_QUERY_URL="http://nginx:8080/api/searxng/search?q=<query>&format=json"

# === DOKUMENTENVERARBEITUNG ===
TIKA_BASE_URL="http://tika:9998"          # Apache Tika für Metadaten

# === LEISTUNG ===
WEBUI_SESSION_COOKIE_SAME_SITE="lax"     # iframe-Kompatibilität
WEBUI_SESSION_COOKIE_SECURE=true         # Nur HTTPS Cookies
```

### Ollama Konfiguration

**Datei:** `env/ollama.env`

```bash
# === GPU EINSTELLUNGEN ===
NVIDIA_VISIBLE_DEVICES=all                # Alle verfügbaren GPUs verwenden
OLLAMA_GPU_LAYERS=35                      # Anzahl GPU-Layer (optimal)
OLLAMA_NUM_PARALLEL=4                     # Parallele Anfragen

# === SPEICHER UND LEISTUNG ===
OLLAMA_MAX_LOADED_MODELS=3                # Maximum Modelle im Speicher
OLLAMA_FLASH_ATTENTION=true               # Attention-Optimierung
OLLAMA_KV_CACHE_TYPE="f16"               # Key-Value Cache Typ

# === NETZWERK EINSTELLUNGEN ===
OLLAMA_HOST="0.0.0.0:11434"              # Auf allen Interfaces lauschen
OLLAMA_ORIGINS="*"                        # CORS für alle Quellen

# === PROTOKOLLIERUNG ===
OLLAMA_DEBUG=false                        # Debug in Production deaktivieren
OLLAMA_VERBOSE=false                      # Minimale Protokollierung
```

### LiteLLM Konfiguration

**Datei:** `env/litellm.env`

```bash
# === GRUNDEINSTELLUNGEN ===
LITELLM_PORT=4000
LITELLM_HOST="0.0.0.0"

# === DATENBANK ===
DATABASE_URL="postgresql://erni_ki:password@db:5432/erni_ki"  # pragma: allowlist secret

# === SICHERHEIT ===
LITELLM_MASTER_KEY="sk-your-master-key-here"  # KRITISCH: Eindeutiger Master-Key # pragma: allowlist secret
LITELLM_SALT_KEY="your-salt-key-here"         # Salt für Hashing

# === INTEGRATIONEN ===
OLLAMA_BASE_URL="http://ollama:11434"          # Lokaler Ollama
OPENAI_API_KEY="your-openai-key"               # OpenAI API (optional) # pragma: allowlist secret

# === LEISTUNG ===
LITELLM_REQUEST_TIMEOUT=600                    # Request Timeout (10 Minuten)
LITELLM_MAX_BUDGET=1000                        # Maximales Budget pro Monat
```

**Datei:** `conf/litellm/config.yaml`

```yaml
# === MODELL KONFIGURATION ===
model_list:
  # Lokale Modelle über Ollama
  - model_name: 'llama3.2'
    litellm_params:
      model: 'ollama/llama3.2'
      api_base: 'http://ollama:11434'

  - model_name: 'qwen2.5-coder'
    litellm_params:
      model: 'ollama/qwen2.5-coder:1.5b'
      api_base: 'http://ollama:11434'

# === ALLGEMEINE EINSTELLUNGEN ===
general_settings:
  master_key: 'sk-your-master-key-here' # Muss mit env übereinstimmen
  database_url: 'postgresql://erni_ki:password@db:5432/erni_ki' # pragma: allowlist secret

  # === SICHERHEIT ===
  enforce_user_param: true # Benutzerparameter erforderlich
  max_budget: 1000 # Maximales Budget
  budget_duration: '30d' # Budget-Zeitraum

  # === LEISTUNG ===
  request_timeout: 600 # Request Timeout
  max_parallel_requests: 10 # Maximum parallele Anfragen

  # === PROTOKOLLIERUNG ===
  set_verbose: false # Minimale Protokollierung in Production
```

## 📄 Dokumentenverarbeitung

### Apache Tika Konfiguration

**Datei:** `env/tika.env`

```bash
# === GRUNDEINSTELLUNGEN ===
TIKA_PORT=9998
TIKA_HOST="0.0.0.0"

# === SICHERHEIT ===
TIKA_CONFIG_FILE="/opt/tika/tika-config.xml"  # Konfigurationsdatei
TIKA_MAX_FILE_SIZE=104857600                   # 100MB maximale Dateigröße

# === LEISTUNG ===
TIKA_REQUEST_TIMEOUT=300000                    # 5 Minuten Timeout
TIKA_TASK_TIMEOUT=120000                       # 2 Minuten pro Aufgabe
TIKA_MAX_FORK_COUNT=4                          # Maximum Prozesse

# === JVM EINSTELLUNGEN ===
JAVA_OPTS="-Xmx2g -Xms1g -XX:+UseG1GC"       # Speicher-Optimierung
```

## 🔍 Suche & RAG

### SearXNG Konfiguration

**Datei:** `env/searxng.env`

```bash
# === GRUNDEINSTELLUNGEN ===
SEARXNG_PORT=8080
SEARXNG_BASE_URL="http://searxng:8080"

# === SICHERHEIT ===
SEARXNG_SECRET_KEY="your-searxng-secret-key"  # KRITISCH: Eindeutiger Schlüssel # pragma: allowlist secret
SEARXNG_BIND_ADDRESS="0.0.0.0:8080"

# === LEISTUNG ===
SEARXNG_DEFAULT_HTTP_TIMEOUT=3.0              # HTTP Request Timeout
SEARXNG_POOL_CONNECTIONS=100                   # Verbindungspool
SEARXNG_POOL_MAXSIZE=20                        # Maximum Verbindungen im Pool

# === SUCHMASCHINEN ===
SEARXNG_ENGINES_BRAVE_DISABLED=false          # Brave Search aktivieren
SEARXNG_ENGINES_STARTPAGE_DISABLED=false      # Startpage aktivieren
SEARXNG_ENGINES_WIKIPEDIA_TIMEOUT=5.0         # Erhöhter Wikipedia Timeout
```

## 💾 Datenschicht

### PostgreSQL Konfiguration

**Datei:** `env/postgres.env`

```bash
# === GRUNDEINSTELLUNGEN ===
POSTGRES_DB=erni_ki
POSTGRES_USER=erni_ki
POSTGRES_PASSWORD=your-secure-password     # KRITISCH: Starkes Passwort

# === LEISTUNG ===
POSTGRES_SHARED_BUFFERS=256MB              # Geteilte Speicherpuffer
POSTGRES_MAX_CONNECTIONS=200               # Maximum Verbindungen
POSTGRES_WORK_MEM=4MB                      # Arbeitsspeicher pro Operation

# === SICHERHEIT ===
POSTGRES_HOST_AUTH_METHOD=md5              # Passwort-Authentifizierung
POSTGRES_INITDB_ARGS="--auth-host=md5"     # Initialisierung mit MD5

# === ERWEITERUNGEN ===
POSTGRES_EXTENSIONS="pgvector,pg_stat_statements"  # Erforderliche Erweiterungen
```

### Redis Konfiguration

**Datei:** `env/redis.env`

```bash
# === GRUNDEINSTELLUNGEN ===
REDIS_PORT=6379
REDIS_BIND="0.0.0.0"

# === SICHERHEIT ===
REDIS_PASSWORD="your-redis-password"       # KRITISCH: Starkes Passwort # pragma: allowlist secret
REDIS_PROTECTED_MODE=yes                   # Geschützter Modus

# === SPEICHER ===
REDIS_MAXMEMORY=2gb                        # Maximum Speicher
REDIS_MAXMEMORY_POLICY=allkeys-lru         # Verdrängungsrichtlinie

# === LEISTUNG ===
REDIS_SAVE="900 1 300 10 60 10000"        # Speicher-Einstellungen
REDIS_TCP_KEEPALIVE=300                    # Keep-alive Verbindungen
```

## 🌐 Netzwerk & Sicherheit

### Nginx Konfiguration

**Hauptdatei:** `conf/nginx/conf.d/default.conf`

```nginx
# === HAUPT SERVER BLOCK ===
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    # === DOMAINS ===
    server_name ki.erni-gruppe.ch diz.zone localhost nginx;

    # === SSL EINSTELLUNGEN ===
    ssl_certificate /etc/nginx/ssl/nginx-fullchain.crt;
    ssl_certificate_key /etc/nginx/ssl/nginx.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:100m;
    ssl_session_timeout 8h;

    # === SICHERHEIT ===
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # === LEISTUNG ===
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript;

    # === PROXY ZU OPENWEBUI ===
    location / {
        include /etc/nginx/includes/openwebui-common.conf;
        proxy_pass http://openwebuiUpstream;
    }

    # === API ROUTEN ===
    location /api/searxng/ {
        include /etc/nginx/includes/searxng-api-common.conf;
        proxy_pass http://searxngUpstream;
    }

}
```

## 📊 Monitoring Konfiguration

### Prometheus Konfiguration

**Datei:** `conf/prometheus/prometheus.yml`

```yaml
# === GLOBALE EINSTELLUNGEN ===
global:
  scrape_interval: 15s # Metriken-Sammelintervall
  evaluation_interval: 15s # Regel-Bewertungsintervall
  external_labels:
    cluster: 'erni-ki' # Cluster-Label
    environment: 'production' # Umgebung

# === ALERT REGELN ===
rule_files:
  - 'rules/*.yml' # Regel-Dateien

# === ALERTMANAGER ===
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager:9093

# === METRIKEN-SAMMLUNG JOBS ===
scrape_configs:
  # Haupt-Services
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'ollama-exporter'
    static_configs:
      - targets: ['ollama-exporter:9778']

  - job_name: 'postgres-exporter'
    static_configs:
      - targets: ['postgres-exporter:9187']

  # Blackbox Monitoring für HTTPS Endpoints
  - job_name: 'blackbox-https'
    metrics_path: /probe
    params:
      module: [https_2xx]
    static_configs:
      - targets:
          - https://ki.erni-gruppe.ch
          - https://diz.zone
          - https://webui.diz.zone
          - https://lite.diz.zone
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter:9115
```

## 🔒 Sicherheits-Best-Practices

### 1. Umgebungsvariablen

```bash
# === KRITISCHE VARIABLEN ===
# Immer starke, eindeutige Werte verwenden:

WEBUI_SECRET_KEY="$(openssl rand -hex 32)"
LITELLM_MASTER_KEY="sk-$(openssl rand -hex 32)"
POSTGRES_PASSWORD="$(openssl rand -base64 32)"
REDIS_PASSWORD="$(openssl rand -base64 32)"
SEARXNG_SECRET_KEY="$(openssl rand -hex 16)"
```

### 2. SSL/TLS Einstellungen

```nginx
# === MODERNE SSL EINSTELLUNGEN ===
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
ssl_prefer_server_ciphers off;
ssl_session_cache shared:SSL:100m;
ssl_session_timeout 8h;

# === HSTS ===
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
```

### 3. Dateiberechtigungen

```bash
# === SICHERE BERECHTIGUNGEN ===
chmod 600 env/*.env              # Nur Besitzer kann env-Dateien lesen
chmod 644 conf/nginx/*.conf      # Nginx Konfigurationen
chmod 600 conf/nginx/ssl/*       # SSL Zertifikate und Schlüssel
```

## 🚀 Production Deployment

### 1. Konfigurationsprüfung

```bash
# Nginx Syntax prüfen
docker exec erni-ki-nginx-1 nginx -t

# Prometheus Konfiguration prüfen
docker exec erni-ki-prometheus promtool check config /etc/prometheus/prometheus.yml

# Datenbankverbindung prüfen
docker exec erni-ki-db-1 pg_isready -U erni_ki
```

### 2. Konfigurationsmonitoring

```bash
# Status aller Services prüfen
docker-compose ps

# Logs kritischer Services prüfen
docker-compose logs --tail=50 openwebui ollama litellm nginx postgres
```

### 3. Konfigurationsbackup

```bash
# Backup erstellen
tar -czf erni-ki-config-$(date +%Y%m%d).tar.gz env/ conf/

# Aus Backup wiederherstellen
tar -xzf erni-ki-config-YYYYMMDD.tar.gz
```

---

> **⚠️ Wichtig:** Testen Sie Konfigurationsänderungen immer in einer
> Testumgebung vor der Anwendung in der Produktion. Erstellen Sie Backups vor
> Änderungen.
