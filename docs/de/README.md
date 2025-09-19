# 🤖 ERNI-KI - Moderne AI-Plattform

**ERNI-KI** ist eine produktionsreife AI-Plattform basierend auf OpenWebUI
v0.6.26 mit vollständiger Containerisierung, GPU-Beschleunigung und umfassendem
Sicherheitssystem. Das System umfasst **29+ ERNI-KI Microservices** mit
vollständigem Monitoring-Stack, AI-Metriken, zentralisierter Protokollierung und
automatisiertem Management.

> **✅ Systemstatus (19. September 2025):** Monitoring-System vollständig
> optimiert. **18 Grafana-Dashboards (100% funktionsfähig)**, alle Prometheus-
> Abfragen mit Fallback-Werten korrigiert. **LiteLLM Context Engineering**,
> **Docling OCR**, **Context7-Integration**. 100% Metrik-Verfügbarkeit. System
> produktionsbereit mit maximaler Zuverlässigkeit.

[![CI](https://github.com/DIZ-admin/erni-ki/actions/workflows/ci.yml/badge.svg)](https://github.com/DIZ-admin/erni-ki/actions/workflows/ci.yml)
[![Security](https://github.com/DIZ-admin/erni-ki/actions/workflows/security.yml/badge.svg)](https://github.com/DIZ-admin/erni-ki/actions/workflows/security.yml)
[![Docker](https://img.shields.io/badge/Docker-Ready-blue?logo=docker)](https://docker.com)
[![GPU](https://img.shields.io/badge/NVIDIA-GPU%20Accelerated-green?logo=nvidia)](https://nvidia.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## 🚀 Funktionen

### 🤖 **AI-Interface**

- **Open WebUI** - moderne Weboberfläche für die Arbeit mit AI
- **Ollama** - lokaler Sprachmodell-Server mit GPU-Beschleunigung (NVIDIA Quadro
  P2200)
  - 6 vorinstallierte Modelle inklusive qwen2.5-coder:1.5b für Programmierung
  - Generierungszeit: ~1,5 Sekunden (GPU-Beschleunigung)
- **LiteLLM** - einheitliche API für verschiedene LLM-Anbieter (optimierte
  Konfiguration)
- **RAG-Suche** - Integration mit SearXNG (Startpage, Brave, Bing Engines)
  - Antwortzeit: <3 Sekunden, 60+ Suchergebnisse
- **MCP-Server** - erweiterte Funktionen über Model Context Protocol
- **Docling** - Dokumentenverarbeitung mit OCR-Unterstützung (EN, DE, FR, IT)
- **Apache Tika** - Textextraktion aus verschiedenen Dokumentformaten
- **EdgeTTS** - Sprachsynthese für Audioausgabe

### 🔒 **Sicherheit**

- **JWT-Authentifizierung** - eigener Go-Service für sicheren Zugang
- **Nginx Reverse Proxy** - geschütztes Proxying mit Rate Limiting
- **SSL/TLS-Verschlüsselung** - vollständige HTTPS-Unterstützung
- **Cloudflare Zero Trust** - sichere Tunnel ohne offene Ports

### 📊 **Daten und Speicherung**

- **PostgreSQL + pgvector** - Vektordatenbank für RAG
- **Redis** - hochperformantes Caching und Sessions
- **Backrest** - automatische Backups mit Verschlüsselung
- **Dokumentenverarbeitung** - Unterstützung für Docling und Apache Tika

### 🛠️ **DevOps-Bereitschaft**

- **Docker Compose** - vollständige Containerisierung aller Services
- **Health Checks** - automatische Zustandsüberwachung
- **Auto-Updates** - Watchtower für aktuelle Images
- **Logging** - zentralisierte Logs aller Komponenten

## 📋 Inhaltsverzeichnis

- [🚀 Funktionen](#-funktionen)
- [📋 Systemanforderungen](#-systemanforderungen)
- [⚡ Schnellstart](#-schnellstart)
- [🔧 Konfiguration](#-konfiguration)
- [🐳 Docker Compose Services](#-docker-compose-services)
- [🛠️ Entwicklung](#️-entwicklung)
- [📊 Monitoring](#-monitoring)
- [🔒 Sicherheit](#-sicherheit)
- [📚 Dokumentation](#-dokumentation)
- [🤝 Mitwirkung](#-mitwirkung)
- [📄 Lizenz](#-lizenz)

## 📋 Systemanforderungen

### Mindestanforderungen

- **OS**: Ubuntu 20.04+ / CentOS 8+ / Debian 11+
- **RAM**: 8GB (empfohlen 16GB+)
- **Festplatte**: 50GB freier Speicherplatz
- **Docker**: 20.10+ mit Docker Compose v2

### Empfohlene Anforderungen

- **GPU**: NVIDIA GPU mit 6GB+ VRAM für Ollama-Beschleunigung
- **RAM**: 32GB für große Sprachmodelle
- **Festplatte**: SSD 100GB+ für optimale Performance

## ⚡ Schnellstart

### Installation

1. **Repository klonen**

```bash
git clone https://github.com/DIZ-admin/erni-ki.git
cd erni-ki
```

1. **Konfigurationsdateien erstellen**

```bash
# Haupt-Docker Compose Datei
cp compose.yml.example compose.yml

# Service-Konfigurationen
cp conf/cloudflare/config.example conf/cloudflare/config.yml
cp conf/mcposerver/config.example conf/mcposerver/config.json
cp conf/nginx/nginx.example conf/nginx/nginx.conf
cp conf/nginx/conf.d/default.example conf/nginx/conf.d/default.conf
cp conf/searxng/settings.yml.example conf/searxng/settings.yml
cp conf/searxng/uwsgi.ini.example conf/searxng/uwsgi.ini
```

1. **Umgebungsvariablen konfigurieren**

```bash
# Umgebungsdateien kopieren und bearbeiten
cp env/auth.example env/auth.env
cp env/db.example env/db.env
cp env/ollama.example env/ollama.env
cp env/openwebui.example env/openwebui.env
cp env/redis.example env/redis.env
cp env/searxng.example env/searxng.env
# ... und weitere nach Bedarf
```

1. **Services starten**

```bash
# Alle Services starten
docker compose up -d

# Status prüfen
docker compose ps

# Erstes Sprachmodell laden
docker compose exec ollama ollama pull llama3.2:3b
```

## 🔧 Konfiguration

### Hauptservices

| Service      | Port  | Beschreibung          |
| ------------ | ----- | --------------------- |
| Open WebUI   | 8080  | Haupt-Webinterface    |
| Ollama       | 11434 | API für Sprachmodelle |
| Auth Service | 9090  | JWT-Authentifizierung |
| SearXNG      | 8080  | Suchmaschine          |
| PostgreSQL   | 5432  | Datenbank             |
| Redis        | 6379  | Cache und Queues      |
| Nginx        | 80    | Reverse Proxy         |

### Umgebungsvariablen

Hauptvariablen für die Konfiguration in `env/*.env` Dateien:

- `WEBUI_SECRET_KEY` - Geheimer Schlüssel für JWT
- `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` - DB-Einstellungen
- `OLLAMA_BASE_URL` - URL für Ollama-Verbindung
- `SEARXNG_SECRET_KEY` - Geheimer Schlüssel für SearXNG

## 🐳 Docker Compose Services

| Service         | Beschreibung                    | Ports         | Abhängigkeiten   |
| --------------- | ------------------------------- | ------------- | ---------------- |
| **nginx**       | Reverse Proxy und Load Balancer | 80, 443, 8080 | -                |
| **auth**        | JWT-Authentifizierung (Go)      | 9090          | -                |
| **openwebui**   | Haupt-AI-Interface              | 8080          | auth, db, ollama |
| **ollama**      | Sprachmodell-Server             | 11434         | -                |
| **db**          | PostgreSQL + pgvector           | 5432          | -                |
| **redis**       | Cache und Message Broker        | 6379, 8001    | -                |
| **searxng**     | Meta-Suchmaschine               | 8080          | redis            |
| **mcposerver**  | MCP-Server                      | 8000          | -                |
| **docling**     | Dokumentenverarbeitung          | 5001          | -                |
| **tika**        | Metadaten-Extraktion            | 9998          | -                |
| **edgetts**     | Sprachsynthese                  | 5050          | -                |
| **backrest**    | Backup-System                   | 9898          | db, redis        |
| **cloudflared** | Cloudflare-Tunnel               | -             | nginx            |
| **watchtower**  | Container-Auto-Update           | -             | -                |

## 🛠️ Entwicklung

### Entwicklungsumgebung einrichten

```bash
# Node.js Abhängigkeiten installieren
npm install

# Git Hooks installieren
npm run prepare

# Code prüfen
npm run lint
npm run type-check
npm run format:check

# Tests ausführen
npm test

# Go Service testen
cd auth && go test -v ./...
```

### Projektstruktur

```text
erni-ki/
├── auth/                 # Go JWT Service
│   ├── main.go          # Hauptdatei
│   ├── main_test.go     # Tests
│   ├── Dockerfile       # Docker Image
│   └── go.mod           # Go Abhängigkeiten
├── conf/                # Service-Konfigurationen
├── env/                 # Umgebungsvariablen
├── docs/                # Dokumentation
├── conf/                # Service-Konfigurationen (inkl. Monitoring)
├── tests/               # TypeScript Tests
├── types/               # TypeScript Typen
└── compose.yml.example  # Docker Compose Template
```

### Code-Qualität

Das Projekt verwendet moderne Tools zur Qualitätssicherung:

- **ESLint** (flat config) - statische Analyse JavaScript/TypeScript
- **Prettier** - Code-Formatierung
- **TypeScript** - strenge Typisierung
- **Vitest** - Tests mit ≥90% Abdeckung
- **Husky** - Git Hooks für automatische Prüfungen
- **Commitlint** - Validierung von Conventional Commits
- **Renovate** - automatische Abhängigkeits-Updates

## 📊 Monitoring (Optimiert 19.09.2025)

Das Monitoring-System umfasst **8 spezialisierte Exporters** (standardisiert und
optimiert):

**Kern-Services:**

- **Prometheus v2.55.1** - Metriken-Sammlung und -Speicherung
- **Grafana** - Datenvisualisierung und Dashboards
- **Loki + Fluent Bit** - zentralisierte Protokollierung
- **Alertmanager** - Problem-Benachrichtigungen

**8 Exporters (standardisiert 19.09.2025):**

- **Node Exporter** (Port 9101) - Systemmetriken ✅ Healthy
- **PostgreSQL Exporter** (Port 9187) - Datenbankmetriken ✅ Healthy
- **Redis Exporter** (Port 9121) - Cache-Metriken 🔧 TCP Healthcheck (behoben)
- **NVIDIA GPU Exporter** (Port 9445) - GPU-Metriken ✅ Verbessert (TCP statt
  pgrep)
- **Blackbox Exporter** (Port 9115) - Verfügbarkeitsüberwachung ✅ Healthy
- **Ollama AI Exporter** (Port 9778) - AI-Metriken ✅ Standardisiert (localhost)
- **Nginx Web Exporter** (Port 9113) - Webserver-Metriken 🔧 TCP Healthcheck
  (behoben)
- **RAG SLA Exporter** (Port 9808) - RAG-Performance-Metriken ✅ Healthy

**Verbesserungen (19.09.2025):**

- ✅ **100% Metriken-Verfügbarkeit** - alle Ports geben HTTP 200 zurück
- 🔧 **Healthcheck-Standardisierung** - TCP-Prüfungen für minimale Container
- ✅ **Einheitliche Konfiguration** - standardisierte timeout/retry Parameter
- 🛠️ **Problemlösung** - Redis/Nginx Exporter Healthcheck behoben

## 🔒 Sicherheit

- JWT-Authentifizierung mit Token-Validierung
- Cloudflare Zero Trust Tunnel
- Regelmäßige Security-Scans (Gosec, npm audit)
- Prinzip der minimalen Berechtigungen für Container
- Automatische Sicherheitsupdates

## 📚 Dokumentation

### 👤 Für Benutzer

- [📖 Benutzerhandbuch](user-guide.md) - Arbeit mit der Oberfläche
- [🔍 RAG-Suche verwenden](user-guide.md#rag-search) - Suche mit SearXNG
- [🎤 Sprachfunktionen](user-guide.md#voice) - Synthese und Spracherkennung

### 👨‍💼 Für Administratoren

- [⚙️ Administrator-Handbuch](admin-guide.md) - Systemverwaltung
- [🔧 Installationsanleitung](installation-guide.md) - detaillierte Installation
- [🛡️ Monitoring und Logs](admin-guide.md#monitoring) - Zustandsüberwachung

### 👨‍💻 Für Entwickler

- [🏗️ Systemarchitektur](architecture.md) - technische Dokumentation
- [🔌 API-Referenz](../api-reference.md) - API-Dokumentation
- [📎 Docling Upload Hinweis](snippets/docling-multipart-note.md) – Multipart
  Feldname ist "files" (nicht "file")
- [💻 Entwicklerhandbuch](../development.md) - Entwicklungsumgebung einrichten

## 🤝 Mitwirkung

Wir begrüßen Beiträge zur Entwicklung von ERNI-KI! Bitte lesen Sie das
[Entwicklerhandbuch](../development.md) für detaillierte Informationen.

### Schnellstart für Entwickler

```bash
# Entwicklungsabhängigkeiten installieren
npm install

# Tests ausführen
npm test

# Code-Linting
npm run lint

# Auth Service kompilieren
cd auth && go build
```

## 🆕 Neueste Updates

### ✅ Fehlerbehebungen (August 2025)

- **SearXNG RAG-Integration wiederhergestellt**
  - DuckDuckGo wegen CAPTCHA-Blockierung deaktiviert
  - Aktive Engines: Startpage, Brave, Bing
  - Antwortzeit: <3 Sekunden, 60+ Ergebnisse

- **Backrest API wiederhergestellt**
  - Umstellung auf JSON RPC Endpoints (`/v1.Backrest/*`)
  - Automatisiertes Backup-Monitoring funktioniert

- **Ollama Modelle aktualisiert**
  - qwen2.5-coder:1.5b für Programmierung hinzugefügt
  - Insgesamt 6 Modelle, GPU-Beschleunigung optimiert

- **Monitoring-System optimiert (19.09.2025)**
  - 8/8 Exporters standardisiert und optimiert
  - Redis/Nginx Exporter Healthcheck behoben (TCP-Prüfungen)
  - NVIDIA Exporter verbessert (TCP statt pgrep)
  - Ollama Exporter standardisiert (localhost statt 127.0.0.1)
  - 100% Metriken-Verfügbarkeit auf allen Ports (HTTP 200)
  - Einheitliche timeout/retries Parameter für Healthcheck

## 📄 Lizenz

Dieses Projekt ist unter der MIT License lizenziert - siehe
[LICENSE](../../LICENSE) Datei für Details.

---

## 🎯 Projektstatus

- ✅ **Production Ready** - bereit für den Produktionseinsatz
- 🔄 **Aktive Entwicklung** - regelmäßige Updates und Verbesserungen
- 🛡️ **Sicherheit** - regelmäßige Sicherheitsaudits
- 📊 **Monitoring** - umfassendes Monitoring-System
- 🤖 **AI-First** - optimiert für AI-Workloads

---

Erstellt mit ❤️ vom ERNI-KI Team
