# 🌐 Nginx Konfigurationsleitfaden - ERNI-KI

> **Version:** 9.0 | **Datum:** 2025-09-11 | **Status:** Production Ready

## 📋 Überblick

Nginx in ERNI-KI fungiert als Reverse Proxy mit SSL/TLS-Unterstützung, WebSocket, Rate Limiting und Caching. Nach der Optimierung v9.0 ist die Konfiguration modular und wartbar geworden.

## 🏗️ Konfigurationsarchitektur

### 📁 Dateistruktur

```bash
conf/nginx/
├── nginx.conf                    # Hauptkonfiguration
│   ├── Map-Direktiven            # Bedingte Logik
│   ├── Upstream-Blöcke           # Backend-Server
│   ├── Rate Limiting Zonen       # DDoS-Schutz
│   └── Proxy Cache Einstellungen # Caching
├── conf.d/default.conf          # Server-Blöcke
│   ├── Server :80               # HTTP → HTTPS Weiterleitung
│   ├── Server :443              # HTTPS mit voller Funktionalität
│   └── Server :8080             # Cloudflare-Tunnel
└── includes/                     # Wiederverwendbare Module
    ├── openwebui-common.conf     # OpenWebUI Proxy-Einstellungen
    ├── searxng-api-common.conf   # SearXNG API-Konfiguration
    ├── searxng-web-common.conf   # SearXNG Web-Interface
    └── websocket-common.conf     # WebSocket Proxy
```

## 🔧 Schlüsselkomponenten

### 1. Map-Direktiven (nginx.conf)

```nginx
# Cloudflare-Tunnel Definition
map $server_port $is_cloudflare_tunnel {
  default 0;
  8080 1;
}

# Bedingter X-Request-ID Header
map $is_cloudflare_tunnel $request_id_header {
  default "";
  1 $final_request_id;
}

# Universelle Variable für Include-Dateien
map $is_cloudflare_tunnel $universal_request_id {
  default $final_request_id;
  1 $final_request_id;
}
```

### 2. Upstream-Blöcke

```nginx
# OpenWebUI Backend
upstream openwebui_backend {
  server openwebui:8080 max_fails=3 fail_timeout=30s weight=1;
  keepalive 64;
  keepalive_requests 1000;
  keepalive_timeout 60s;
}

# SearXNG Upstream für RAG-Suche
upstream searxngUpstream {
  server searxng:8080 max_fails=3 fail_timeout=30s weight=1;
  keepalive 48;
  keepalive_requests 200;
  keepalive_timeout 60s;
}
```

### 3. Rate Limiting

```nginx
# Geschwindigkeitsbegrenzungszonen
limit_req_zone $binary_remote_addr zone=general:20m rate=50r/s;
limit_req_zone $binary_remote_addr zone=api:20m rate=30r/s;
limit_req_zone $binary_remote_addr zone=searxng_api:10m rate=60r/s;
limit_req_zone $binary_remote_addr zone=websocket:10m rate=20r/s;

# Verbindungsbegrenzung
limit_conn_zone $binary_remote_addr zone=perip:10m;
limit_conn_zone $server_name zone=perserver:10m;
```

## 🚪 Server-Blöcke

### Port 80 - HTTP Weiterleitung

```nginx
server {
  listen 80;
  server_name ki.erni-gruppe.ch diz.zone localhost;
  
  # Zwangsweiterleitung zu HTTPS
  return 301 https://$host$request_uri;
}
```

### Port 443 - HTTPS Production

```nginx
server {
  listen 443 ssl;
  http2 on;
  server_name ki.erni-gruppe.ch diz.zone localhost;
  
  # SSL-Konfiguration
  ssl_certificate /etc/nginx/ssl/nginx-fullchain.crt;
  ssl_certificate_key /etc/nginx/ssl/nginx.key;
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_verify_client off;  # Korrektur für localhost
  
  # Security Headers (für localhost optimiert)
  add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' localhost:*; ...";
  add_header Access-Control-Allow-Origin "https://ki.erni-gruppe.ch https://localhost ...";
}
```

### Port 8080 - Cloudflare-Tunnel

```nginx
server {
  listen 8080;
  server_name ki.erni-gruppe.ch diz.zone localhost;
  
  # Für externen Zugriff optimiert
  # Ohne HTTPS-Weiterleitungen
  # Verwendet $request_id_header für Protokollierung
}
```

## 📦 Include-Dateien

### openwebui-common.conf

```nginx
# Gemeinsame Einstellungen für OpenWebUI Proxy
limit_req zone=general burst=20 nodelay;
limit_conn perip 30;
limit_conn perserver 2000;

# Standard-Proxy-Header
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Request-ID $universal_request_id;

# HTTP-Version und Verbindungen
proxy_http_version 1.1;
proxy_set_header Connection "";

# Timeouts
proxy_connect_timeout 30s;
proxy_send_timeout 60s;
proxy_read_timeout 60s;

# Proxying zu OpenWebUI
proxy_pass http://openwebui_backend;
```

### searxng-api-common.conf

```nginx
# Rate Limiting für SearXNG API
limit_req zone=searxng_api burst=30 nodelay;
limit_req_status 429;

# SearXNG-Antworten cachen
proxy_cache searxng_cache;
proxy_cache_valid 200 5m;
proxy_cache_key "$scheme$request_method$host$request_uri";

# URL-Rewriting für API
rewrite ^/api/searxng/(.*)$ /$1 break;

# Proxying zu SearXNG Upstream
proxy_pass http://searxngUpstream;
proxy_set_header X-Request-ID $universal_request_id;

# Timeouts für Suchanfragen
proxy_connect_timeout 5s;
proxy_send_timeout 30s;
proxy_read_timeout 30s;
```

## 🔍 API-Endpunkte

### Haupt-Endpunkte

| Endpunkt | Status | Beschreibung | Antwortzeit |
|----------|--------|--------------|-------------|
| `/health` | ✅ | Systemstatusüberprüfung | <100ms |
| `/api/config` | ✅ | Systemkonfiguration | <200ms |
| `/api/searxng/search` | ✅ | RAG Web-Suche | <2s |
| `/api/mcp/` | ✅ | Model Context Protocol | <500ms |
| WebSocket-Endpunkte | ✅ | Echtzeit-Kommunikation | <50ms |

### Verwendungsbeispiele

```bash
# Systemstatusüberprüfung
curl http://localhost:8080/health
# Antwort: {"status":true}

# SearXNG-Suche für RAG
curl "http://localhost:8080/api/searxng/search?q=test&format=json"
# Antwort: JSON mit Suchergebnissen (31 Ergebnisse von 4500)

# Systemkonfiguration
curl http://localhost:8080/api/config
# Antwort: JSON mit OpenWebUI-Einstellungen
```

## 🛠️ Administration

### Änderungen anwenden

```bash
# Konfiguration überprüfen
docker exec erni-ki-nginx-1 nginx -t

# Hot-Reload ohne Neustart
docker exec erni-ki-nginx-1 nginx -s reload

# Include-Dateien kopieren
docker cp conf/nginx/includes/ erni-ki-nginx-1:/etc/nginx/
```

### Monitoring

```bash
# Logs überprüfen
docker logs --tail=20 erni-ki-nginx-1

# Container-Status
docker ps | grep nginx

# Ports überprüfen
netstat -tlnp | grep nginx
```

## 🔧 Fehlerbehebung

### Häufige Probleme

1. **404 bei API-Endpunkten**
   - Include-Dateien im Container überprüfen
   - Korrektheit der Upstream-Blöcke sicherstellen

2. **WebSocket-Verbindungen funktionieren nicht**
   - websocket-common.conf überprüfen
   - Vorhandensein der Upgrade-Header sicherstellen

3. **SSL-Fehler bei localhost**
   - ssl_verify_client off überprüfen
   - Korrektheit der CSP-Richtlinie sicherstellen

### Diagnosebefehle

```bash
# Nginx-Konfiguration überprüfen
docker exec erni-ki-nginx-1 nginx -T

# Upstream-Status überprüfen
docker exec erni-ki-nginx-1 curl -s http://openwebui:8080/health

# Include-Dateien überprüfen
docker exec erni-ki-nginx-1 ls -la /etc/nginx/includes/
```

## 📊 Leistungsmetriken

- **API-Antwortzeit:** <2 Sekunden
- **WebSocket-Latenz:** <50ms
- **SSL-Handshake:** <100ms
- **Cache-Hit-Rate:** >80%
- **Rate Limiting:** 60 req/s für SearXNG API

## 🔐 Sicherheit

- **SSL/TLS:** TLSv1.2, TLSv1.3
- **HSTS:** max-age=31536000
- **CSP:** Für localhost und Production optimiert
- **Rate Limiting:** Schutz vor DDoS-Angriffen
- **CORS:** Für erlaubte Domains konfiguriert
