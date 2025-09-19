# 🏗️ ERNI-KI Systemarchitektur

> **Dokumentversion:** 10.0 **Aktualisierungsdatum:** 2025-09-19 **Status:**
> Production Ready (Monitoring-System vollständig optimiert: 18 Grafana-
> Dashboards (100% funktionsfähig), alle Prometheus-Abfragen mit Fallback-
> Werten korrigiert, LiteLLM Context Engineering, Docling OCR, Context7-
> Integration)

## 📋 Architektur-Überblick

ERNI-KI ist eine moderne Microservice-basierte AI-Plattform, die auf den
Prinzipien der Containerisierung, Sicherheit und Skalierbarkeit aufbaut. Das
System besteht aus **29 ERNI-KI Microservices** + **9 externe Services**,
einschließlich Komponenten wie LiteLLM, Docling, MCP Server, vollständigem
Monitoring-Stack mit 33/33 Containern im Status Healthy, AI-Metriken,
nginx-exporter für Web-Analytik und zentralisierter Protokollierung über
Fluent-bit → Loki.

### 🚀 Neueste Updates (v9.0 - September 2025)

#### 🔧 Kritische Optimierungen (11. September 2025)

- **Nginx-Konfiguration**: Vollständige Optimierung und Deduplizierung
  - 91 Zeilen doppelten Codes eliminiert (-20% Konfigurationsgröße)
  - 4 Include-Dateien für Wiederverwendung erstellt (openwebui-common.conf,
    searxng-api-common.conf, websocket-common.conf, searxng-web-common.conf)
  - Map-Direktiven für bedingte Logik hinzugefügt
  - Verbesserte Wartbarkeit und Konsistenz der Einstellungen

- **HTTPS und CSP Korrekturen**: Vollständige Funktionalität wiederhergestellt
  - Content Security Policy für localhost-Unterstützung optimiert
  - CORS-Header für Entwicklung und Production erweitert
  - SSL-Konfiguration mit ssl_verify_client off korrigiert
  - Kritische Skript-Ladefehler behoben

- **SearXNG API Wiederherstellung**: Vollständige Routing-Korrektur
  - Problem mit $universal_request_id Variable behoben
  - Funktionalität des /api/searxng/search Endpunkts wiederhergestellt
  - API gibt korrekte JSON-Antworten mit Suchergebnissen zurück (31 Ergebnisse
    von 4500)
  - Unterstützung für 4 Suchmaschinen: Google, Bing, DuckDuckGo, Brave
  - Antwortzeit <2 Sekunden (entspricht SLA-Anforderungen)

#### 🔴 Vorherige Korrekturen (29. August 2025)

- **Cloudflare-Tunnel**: DNS-Resolution-Fehler behoben
- **System-Diagnose**: Umfassende Überprüfung von 29 Microservices
- **Alle Services im Status "Healthy"** (15+ Container)

#### 🛡️ Architektur-Komponenten (aktualisiert)

- **OpenWebUI v0.6.26**: Haupt-AI-Interface mit CUDA-Unterstützung
- **Ollama 0.11.8**: 9 geladene AI-Modelle mit GPU-Beschleunigung
- **LiteLLM (main-stable)**: Context Engineering Gateway
- **PostgreSQL 15.13 + pgvector 0.8.0**: Vektor-Datenbank
- **Redis Stack**: WebSocket-Manager und Caching
- **SearXNG**: RAG-Integration mit 6+ Suchquellen

#### 📊 Monitoring und Observability

- **Prometheus v2.55.1**: Metriken-Sammlung mit 35+ Targets
- **Grafana**: Visualisierung und Dashboards
- **Loki**: Zentralisierte Protokollierung über Fluent Bit
- **8 Exporter**: node, postgres, redis, nginx, ollama, nvidia, cadvisor,
  blackbox
- **RAG Exporter**: SLA für RAG (Latenz & Quellen)
- **Fluent Bit**: Prometheus-Metriken unter `/api/v1/metrics/prometheus`
- **Backrest**: Lokale Backups (7 Tage + 4 Wochen)

## 🎯 Architektur-Prinzipien

### 🔒 **Security First**

- JWT-Authentifizierung für alle API-Anfragen
- Rate Limiting und DDoS-Schutz
- SSL/TLS-Verschlüsselung des gesamten Traffics
- Service-Isolation über Docker Networks

### 📈 **Scalability & Performance**

- Horizontale Skalierung über Docker Compose
- GPU-Beschleunigung für AI-Berechnungen
- Caching über Redis
- Asynchrone Dokumentenverarbeitung

### 🛡️ **Reliability & Monitoring**

- Health Checks für alle Services
- Automatische Neustarts bei Ausfällen
- Zentralisiertes Logging
- Automatische Backups

## 🏛️ High-Level Diagramm

```mermaid
graph TB
    subgraph "🌐 External Layer"
        USER[👤 User Browser]
        CF[☁️ Cloudflare Zero Trust]
    end

    subgraph "🚪 Gateway Layer"
        NGINX[🚪 Nginx Reverse Proxy]
        AUTH[🔐 Auth Service JWT]
        TUNNEL[🔗 Cloudflared Tunnel]
    end

    subgraph "🤖 Application Layer"
        OWUI[🤖 Open WebUI]
        OLLAMA[🧠 Ollama LLM Server]
        SEARXNG[🔍 SearXNG Search]
        MCP[🔌 MCP Servers]
    end

    subgraph "🔧 Processing Layer"
        DOCLING[📄 Docling Parser]
        TIKA[📋 Apache Tika]
        EDGETTS[🎤 EdgeTTS Speech]
    end

    subgraph "💾 Data Layer"
        POSTGRES[(🗄️ PostgreSQL + pgvector)]
        REDIS[(⚡ Redis Cache)]
        BACKREST[💾 Backrest Backup]
    end

    subgraph "📊 Monitoring Layer"
        PROMETHEUS[📈 Prometheus Metrics]
        GRAFANA[📊 Grafana Dashboards]
        ALERTMANAGER[🚨 Alert Manager]
        WEBHOOK_REC[📨 Webhook Receiver]
        NODE_EXP[📊 Node Exporter]
        PG_EXP[📊 PostgreSQL Exporter]
        REDIS_EXP[📊 Redis Exporter]
        NVIDIA_EXP[📊 NVIDIA GPU Exporter]
        BLACKBOX_EXP[📊 Blackbox Exporter]
        CADVISOR[📊 cAdvisor Container Metrics]
    end

    subgraph "🛠️ Infrastructure Layer"
        WATCHTOWER[🔄 Watchtower Updates]
        DOCKER[🐳 Docker Engine]
    end

    %% External connections
    USER --> CF
    CF --> TUNNEL
    TUNNEL --> NGINX

    %% Gateway layer
    NGINX --> AUTH
    NGINX --> OWUI

    %% Application connections
    OWUI --> OLLAMA
    OWUI --> SEARXNG
    OWUI --> MCP
    OWUI --> DOCLING
    OWUI --> TIKA
    OWUI --> EDGETTS

    %% Data connections
    OWUI --> POSTGRES
    OWUI --> REDIS
    SEARXNG --> REDIS
    BACKREST --> POSTGRES
    BACKREST --> REDIS

    %% Infrastructure
    WATCHTOWER -.-> OWUI
    WATCHTOWER -.-> OLLAMA
    WATCHTOWER -.-> SEARXNG
```

## 🔧 Detaillierte Service-Architektur

### 🚪 **Gateway Layer (Gateway)**

#### Nginx Reverse Proxy

- **Zweck**: Einheitlicher Eingangspunkt, Load Balancing, SSL-Terminierung
- **Ports**: 80 (HTTP), 443 (HTTPS), 8080 (Internal)
- **Funktionen**:
  - Rate Limiting (100 req/min für allgemeine Anfragen, 10 req/min für SearXNG)
  - SSL/TLS-Terminierung mit modernen Cipher Suites
  - WebSocket-Verbindungen proxying
  - Statische Datei-Bereitstellung
  - Caching von statischem Content

#### Auth Service (JWT)

- **Technologie**: Go 1.23+
- **Port**: 9090
- **Funktionen**:
  - JWT-Token-Generierung und -Validierung
  - Integration mit nginx auth_request
  - Benutzer-Session-Management
  - Rate Limiting für Authentifizierung

#### Cloudflared Tunnel

- **Zweck**: Sichere Verbindung zu Cloudflare Zero Trust
- **Funktionen**:
  - Verschlüsselte Tunnel ohne offene Ports
  - Automatisches SSL-Zertifikat-Management
  - DDoS-Schutz auf Cloudflare-Ebene
  - Geografische Traffic-Verteilung

### 🤖 **Application Layer (Anwendungen)**

#### Open WebUI

- **Technologie**: Python FastAPI + Svelte
- **Port**: 8080
- **GPU**: NVIDIA CUDA-Unterstützung
- **Funktionen**:
  - Web-Interface für AI-Modelle
  - RAG (Retrieval-Augmented Generation) Suche
  - Chat- und Verlaufs-Management
  - Integration mit externen Services
  - Dokument-Upload und -Verarbeitung
  - Sprach-Ein-/Ausgabe

#### Ollama LLM Server

- **Technologie**: Go + CUDA
- **Port**: 11434
- **GPU**: Vollständige NVIDIA GPU-Unterstützung
- **Funktionen**:
  - Lokale Ausführung von Sprachmodellen
  - Automatisches GPU-Speicher-Management
  - OpenAI-kompatible API
  - Multi-Modell-Unterstützung
  - Streaming-Antworten

#### SearXNG Search Engine

- **Technologie**: Python Flask
- **Port**: 8080 (internal)
- **Funktionen**:
  - Meta-Suchmaschine (Google, Bing, DuckDuckGo)
  - Private Suche ohne Tracking
  - JSON API für RAG-Integration
  - Ergebnis-Caching in Redis
  - Rate Limiting und Blockierungs-Schutz

#### MCP Servers

- **Technologie**: Model Context Protocol
- **Port**: 8000
- **Funktionen**:
  - AI-Funktionserweiterung durch Tools
  - Integration mit externen APIs
  - Code- und Befehlsausführung
  - Datenbankzugriff

### 🔧 **Processing Layer (Verarbeitung)**

#### Docling Document Parser

- **Technologie**: Python + AI-Modelle
- **Port**: 5001
- **Funktionen**:
  - Textextraktion aus PDF, DOCX, PPTX
  - OCR für gescannte Dokumente
  - Strukturelle Dokumentenanalyse
  - Tabellen- und Bildunterstützung

#### Apache Tika

- **Technologie**: Java
- **Port**: 9998
- **Funktionen**:
  - Metadaten-Extraktion aus Dateien
  - Unterstützung für 1000+ Dateiformate
  - Dateityp-Erkennung
  - Text- und Strukturextraktion

#### EdgeTTS Speech Synthesis

- **Technologie**: Python + Microsoft Edge TTS
- **Port**: 5050
- **Funktionen**:
  - Hochqualitative Sprachsynthese
  - Multi-Sprach- und Stimmen-Unterstützung
  - Streaming-Audio
  - Open WebUI-Integration

### 💾 **Data Layer (Daten)**

#### PostgreSQL + pgvector

- **Version**: PostgreSQL 16 + pgvector Extension
- **Port**: 5432
- **Funktionen**:
  - Haupt-Anwendungsdatenbank
  - Vektor-Speicher für RAG
  - Volltext-Suche
  - ACID-Transaktionen
  - Replikation und Backups

#### Redis Cache

- **Version**: Redis Stack (Redis + RedisInsight)
- **Ports**: 6379 (Redis), 8001 (RedisInsight)
- **Funktionen**:
  - Suchanfragen-Caching
  - Benutzer-Sessions
  - Task-Queues
  - Pub/Sub für Real-time-Benachrichtigungen

#### Backrest Backup System

- **Technologie**: Go + Restic
- **Port**: 9898
- **Funktionen**:
  - Automatische inkrementelle Backups
  - Datenverschlüsselung
  - Deduplizierung
  - Web-Management-Interface
  - Point-in-Time-Recovery

### 🛠️ **Infrastructure Layer (Infrastruktur)**

#### Watchtower Auto-updater

- **Funktionen**:
  - Automatische Docker-Image-Updates
  - Überwachung neuer Versionen
  - Graceful Service-Neustarts
  - Update-Benachrichtigungen

## 🌐 Netzwerk-Architektur

### Ports und Protokolle

| Service    | Externer Port | Interner Port | Protokoll  | Zweck                |
| ---------- | ------------- | ------------- | ---------- | -------------------- |
| nginx      | 80, 443, 8080 | 80, 443, 8080 | HTTP/HTTPS | Web Gateway          |
| auth       | -             | 9090          | HTTP       | JWT-Validierung      |
| openwebui  | -             | 8080          | HTTP/WS    | AI-Interface         |
| ollama     | -             | 11434         | HTTP       | LLM API              |
| db         | -             | 5432          | PostgreSQL | Datenbank            |
| redis      | -             | 6379, 8001    | Redis/HTTP | Cache & UI           |
| searxng    | -             | 8080          | HTTP       | Such-API             |
| mcposerver | -             | 8000          | HTTP       | MCP-Protokoll        |
| docling    | -             | 5001          | HTTP       | Dokument-Parsing     |
| tika       | -             | 9998          | HTTP       | Metadaten-Extraktion |
| edgetts    | -             | 5050          | HTTP       | Sprachsynthese       |
| backrest   | 9898          | 9898          | HTTP       | Backup-Management    |

### Docker Networks

- **erni-ki_default**: Haupt-Netzwerk für alle Services
- **Isolation**: Jeder Service nur über Container-Namen erreichbar
- **DNS**: Automatische Namensauflösung über Docker DNS

## 🔄 Datenflüsse

### Benutzeranfrage

1. **Browser** → **Cloudflare** → **Cloudflared** → **Nginx**
2. **Nginx** → **Auth Service** (JWT-Validierung)
3. **Nginx** → **Open WebUI** (Haupt-Interface)
4. **Open WebUI** → **Ollama** (Antwort-Generierung)
5. **Open WebUI** → **PostgreSQL** (Verlaufs-Speicherung)

### RAG-Suche

1. **Open WebUI** → **SearXNG** (Informationssuche)
2. **SearXNG** → **Redis** (Ergebnis-Caching)
3. **Open WebUI** → **PostgreSQL/pgvector** (Vektor-Suche)
4. **Open WebUI** → **Ollama** (Generierung mit Kontext)

### Dokumentenverarbeitung

1. **Open WebUI** → **Docling/Tika** (Dokument-Parsing)
2. **Open WebUI** → **PostgreSQL/pgvector** (Vektor-Speicherung)
3. **Open WebUI** → **Ollama** (Inhalts-Analyse)

## 📊 Monitoring und Observability

### Health Checks

- Alle Services haben konfigurierte Health Checks
- Automatischer Neustart bei Ausfällen
- Überwachung über `docker compose ps`

### Logging

- Zentralisierte Logs über Docker Logging Driver
- Log-Rotation zur Festplatten-Überlauf-Vermeidung
- Strukturiertes Logging im JSON-Format

### Metriken

- Ressourcenverbrauch über `docker stats`
- GPU-Überwachung über nvidia-smi
- Datenbank-Performance-Monitoring

## 🔧 Konfiguration und Deployment

### Umgebungsvariablen

- Jeder Service hat separate `.env`-Datei
- Automatische Generierung geheimer Schlüssel
- Konfiguration über Docker Compose

### Skalierung

- Horizontale Skalierung über Docker Compose scale
- Load Balancing über Nginx upstream
- Automatische Erkennung neuer Instanzen

### Sicherheit

- Minimale Berechtigungen für alle Container
- Netzwerk- und Dateisystem-Isolation
- Regelmäßige Sicherheitsupdates über Watchtower

## 🔌 Ports & Endpoints (lokal)

- Nginx: 80, 443, 8080
- OpenWebUI: 8080
- LiteLLM: 4000 (`/health/liveliness`, `/health/readiness`)
- PostgreSQL Exporter: 9187 (`/metrics`)
- Redis Exporter: 9121 (`/metrics`)
- Node Exporter: 9101 (`/metrics`)
- cAdvisor: 8081 → Container 8080 (`/metrics`)
- NVIDIA GPU Exporter: 9445 (`/metrics`)
- Nginx Exporter: 9113 (`/metrics`)
- Blackbox Exporter: 9115 (`/probe`)
- Prometheus: 9091 (`/-/ready`, `/api/v1/targets`)
- Grafana: 3000 (`/api/health`)
- Alertmanager: 9093–9094 (`/-/healthy`, `/api/v2/status`)
- Loki: 3100 (`/ready`)
- Fluent Bit Service: 2020 (`/api/v1/metrics`, Prometheus:
  `/api/v1/metrics/prometheus`)
- RAG Exporter: 9808 (`/metrics`)

---

**📝 Hinweis**: Diese Architektur ist für den Produktionseinsatz optimiert mit
Fokus auf Sicherheit, Performance und Zuverlässigkeit.
