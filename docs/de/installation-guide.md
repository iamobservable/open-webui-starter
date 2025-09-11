# 🚀 Detaillierte Installationsanleitung für ERNI-KI

> **Dokumentversion:** 2.0 **Aktualisierungsdatum:** 2025-07-04
> **Installationszeit:** 30-60 Minuten

## 📋 Systemanforderungen

### Mindestanforderungen

- **OS**: Ubuntu 20.04+ / CentOS 8+ / Debian 11+ / RHEL 8+
- **CPU**: 4 Kerne (Intel/AMD x86_64)
- **RAM**: 8GB (Minimum für Grundbetrieb)
- **Festplatte**: 50GB freier Speicherplatz (SSD empfohlen)
- **Netzwerk**: Stabile Internetverbindung

### Empfohlene Anforderungen

- **CPU**: 8+ Kerne mit AVX2-Unterstützung
- **RAM**: 32GB (für große Sprachmodelle)
- **GPU**: NVIDIA GPU mit 8GB+ VRAM (RTX 3070/4060 oder höher)
- **Festplatte**: 200GB+ NVMe SSD
- **Netzwerk**: 100 Mbps+ für Modell-Downloads

### Unterstützte GPUs

- **NVIDIA**: RTX 20/30/40 Serie, Tesla, Quadro mit CUDA 11.8+
- **Minimaler VRAM**: 6GB für 7B-Parameter-Modelle
- **Empfohlener VRAM**: 12GB+ für 13B+ Parameter-Modelle

## 🔧 System-Vorbereitung

### 1. System-Update

#### Ubuntu/Debian

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git unzip software-properties-common
```

#### CentOS/RHEL/Fedora

```bash
sudo dnf update -y
sudo dnf install -y curl wget git unzip
```

### 2. Docker und Docker Compose Installation

#### Automatische Installation (empfohlen)

```bash
# Docker Installation über offizielles Skript
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Benutzer zur Docker-Gruppe hinzufügen
sudo usermod -aG docker $USER

# Neustart für Gruppenänderungen
newgrp docker

# Installation prüfen
docker --version
docker compose version
```

#### Manuelle Docker Installation (Ubuntu)

```bash
# Alte Versionen entfernen
sudo apt remove docker docker-engine docker.io containerd runc

# Abhängigkeiten installieren
sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release

# Offiziellen Docker GPG-Schlüssel hinzufügen
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Docker Repository hinzufügen
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Docker Engine installieren
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

### 3. NVIDIA GPU Konfiguration (optional)

#### NVIDIA Treiber Installation

```bash
# GPU-Verfügbarkeit prüfen
lspci | grep -i nvidia

# Treiber installieren (Ubuntu)
sudo apt install -y nvidia-driver-535 nvidia-utils-535

# System neu starten
sudo reboot
```

#### NVIDIA Container Toolkit Installation

```bash
# NVIDIA Repository hinzufügen
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list

# nvidia-container-toolkit installieren
sudo apt update
sudo apt install -y nvidia-container-toolkit

# Docker neu starten
sudo systemctl restart docker

# GPU in Docker testen
docker run --rm --gpus all nvidia/cuda:11.8-base-ubuntu20.04 nvidia-smi
```

## 📦 ERNI-KI Installation

### 1. Repository klonen

```bash
# Projekt klonen
git clone https://github.com/DIZ-admin/erni-ki.git
cd erni-ki

# Projektstruktur prüfen
ls -la
```

### 2. Konfigurationsdateien einrichten

#### Beispiel-Konfigurationen kopieren

```bash
# Haupt-Compose-Datei kopieren
cp compose.yml.example compose.yml

# Alle Umgebungsvariablen kopieren
for file in env/*.example; do
  cp "$file" "${file%.example}"
done

# Nginx-Konfigurationen kopieren
cp conf/nginx/nginx.example conf/nginx/nginx.conf
cp conf/nginx/conf.d/default.example conf/nginx/conf.d/default.conf
```

#### Geheime Schlüssel generieren

```bash
# Skript für Schlüsselgenerierung erstellen
cat > scripts/generate-secrets.sh << 'EOF'
#!/bin/bash

# Zufällige Schlüssel generieren
JWT_SECRET=$(openssl rand -hex 32)
WEBUI_SECRET_KEY=$(openssl rand -hex 32)
SEARXNG_SECRET_KEY=$(openssl rand -hex 16)
POSTGRES_PASSWORD=$(openssl rand -base64 32)

# Umgebungsdateien aktualisieren
sed -i "s/CHANGE_BEFORE_GOING_LIVE/$JWT_SECRET/g" env/auth.env
sed -i "s/89f03e7ae86485051232d47071a15241ae727f705589776321b5a52e14a6fe57/$WEBUI_SECRET_KEY/g" env/openwebui.env
sed -i "s/CHANGE_BEFORE_GOING_LIVE/$SEARXNG_SECRET_KEY/g" env/searxng.env
sed -i "s/CHANGE_BEFORE_GOING_LIVE/$POSTGRES_PASSWORD/g" env/postgres.env

echo "✅ Geheime Schlüssel erfolgreich generiert!"
EOF

chmod +x scripts/generate-secrets.sh
./scripts/generate-secrets.sh
```

### 3. Umgebungsvariablen konfigurieren

#### Grundeinstellungen (env/openwebui.env)

```bash
# Grundeinstellungen bearbeiten
nano env/openwebui.env
```

Wichtige Parameter zur Konfiguration:

```env
# URL Ihrer Domain (bei Cloudflare-Nutzung)
WEBUI_URL=https://your-domain.com

# GPU-Einstellungen (für GPU-Nutzung auskommentieren)
USE_CUDA_DOCKER=true

# RAG-Sucheinstellungen
WEB_SEARCH_ENGINE=searxng
ENABLE_RAG_WEB_SEARCH=true

# Datei-Upload-Limits (in Bytes, Standard 100MB)
FILE_UPLOAD_LIMIT=104857600
```

#### Cloudflare-Konfiguration (optional)

```bash
# Tunnel-Einstellungen bearbeiten
nano env/cloudflared.env
```

```env
# Cloudflare Tunnel Token (aus Cloudflare Dashboard)
TUNNEL_TOKEN=your-cloudflare-tunnel-token
```

#### Datenbank-Konfiguration

```bash
# PostgreSQL-Einstellungen prüfen
nano env/postgres.env
```

```env
# Datenbankeinstellungen (Passwort bereits generiert)
POSTGRES_DB=openwebui
POSTGRES_USER=openwebui
POSTGRES_PASSWORD=generated-password
```

### 4. Nginx-Konfiguration

#### Domain-Namen aktualisieren

```bash
# Platzhalter durch Ihre Domain ersetzen
sed -i 's/<domain-name>/your-domain.com/g' conf/nginx/conf.d/default.conf
```

#### SSL-Zertifikate einrichten (ohne Cloudflare)

```bash
# Selbstsignierte Zertifikate für Tests erstellen
sudo mkdir -p /etc/nginx/ssl
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/nginx-selfsigned.key \
  -out /etc/nginx/ssl/nginx-selfsigned.crt \
  -subj "/C=DE/ST=Berlin/L=Berlin/O=ERNI-KI/CN=localhost"
```

## 🚀 System starten

### 1. Erster Start

```bash
# Alle Services starten
docker compose up -d

# Service-Status prüfen
docker compose ps

# Logs anzeigen (optional)
docker compose logs -f
```

### 2. Initialisierung abwarten

```bash
# Service-Bereitschaft prüfen (kann 2-5 Minuten dauern)
watch -n 5 'docker compose ps --format "table {{.Name}}\t{{.Status}}"'

# Warten bis alle Services "healthy" sind
```

### 3. Erstes Sprachmodell laden

```bash
# Leichtes Modell zum Testen laden (3B Parameter)
docker compose exec ollama ollama pull llama3.2:3b

# Für leistungsstärkere Systeme größeres Modell
docker compose exec ollama ollama pull llama3.1:8b

# Geladene Modelle prüfen
docker compose exec ollama ollama list
```

## ✅ Installation prüfen

### 1. Service-Verfügbarkeit prüfen

```bash
# Haupt-Interface prüfen
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/
# Erwartetes Ergebnis: 200

# Ollama API prüfen
curl -s http://localhost:11434/api/tags
# Erwartetes Ergebnis: JSON mit Modellliste

# SearXNG API prüfen
curl -s "http://localhost:8080/api/searxng/search?q=test&format=json" | head -5
# Erwartetes Ergebnis: JSON mit Suchergebnissen
```

### 3. Monitoring-Dienste (lokal)

- Prometheus: http://localhost:9091
- Grafana: http://localhost:3000
- Alertmanager: http://localhost:9093
- Loki: http://localhost:3100
- Fluent Bit (Prometheus): http://localhost:2020/api/v1/metrics/prometheus
- RAG Exporter: http://localhost:9808/metrics

### 2. GPU prüfen (falls installiert)

```bash
# GPU-Verfügbarkeit in Ollama prüfen
docker exec erni-ki-ollama-1 nvidia-smi

# GPU-Nutzung prüfen
docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
```

### 3. Erste Anmeldung

1. Browser öffnen und zu `http://localhost:8080` navigieren
2. Administrator-Account erstellen
3. Ollama-Verbindung konfigurieren: `http://ollama:11434`
4. Chat mit AI-Modell testen

## 🔧 Konfiguration nach Installation

### 1. Autostart einrichten

```bash
# Systemd-Service für Autostart erstellen
sudo tee /etc/systemd/system/erni-ki.service > /dev/null << EOF
[Unit]
Description=ERNI-KI AI Platform
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/path/to/erni-ki
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

# Autostart aktivieren
sudo systemctl enable erni-ki.service
sudo systemctl start erni-ki.service
```

### 2. Monitoring einrichten

```bash
# Monitoring-Skript erstellen
cat > scripts/health-check.sh << 'EOF'
#!/bin/bash
echo "=== ERNI-KI Health Check ==="
echo "Datum: $(date)"
echo ""

# Container-Status prüfen
echo "📊 Service-Status:"
docker compose ps --format "table {{.Name}}\t{{.Status}}"
echo ""

# Ressourcenverbrauch prüfen
echo "💾 Ressourcenverbrauch:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
echo ""

# API-Verfügbarkeit prüfen
echo "🌐 API-Prüfung:"
curl -s -o /dev/null -w "OpenWebUI: %{http_code}\n" http://localhost:8080/
curl -s -o /dev/null -w "Ollama: %{http_code}\n" http://localhost:11434/
echo ""
EOF

chmod +x scripts/health-check.sh
```

### 3. Backup-Konfiguration

```bash
# Backrest über Web-Interface konfigurieren
echo "Öffnen Sie http://localhost:9898 für Backup-Konfiguration"
echo "Login: admin"
echo "Passwort: siehe env/backrest.env"
```

## 🛠️ Fehlerbehebung

### Startprobleme

```bash
# Logs des problematischen Services prüfen
docker compose logs service-name

# Bestimmten Service neu starten
docker compose restart service-name

# Vollständiger System-Neustart
docker compose down && docker compose up -d
```

### GPU-Probleme

```bash
# NVIDIA-Treiber prüfen
nvidia-smi

# Docker GPU-Unterstützung prüfen
docker run --rm --gpus all nvidia/cuda:11.8-base-ubuntu20.04 nvidia-smi

# GPU-Einstellungen in compose.yml aktivieren
sed -i 's/# deploy: \*gpu-deploy/deploy: *gpu-deploy/g' compose.yml
```

### Netzwerk-Probleme

```bash
# Docker-Netzwerke prüfen
docker network ls
docker network inspect erni-ki_default

# Docker-Netzwerk-Stack neu starten
sudo systemctl restart docker
```

## 📚 Nächste Schritte

Nach erfolgreicher Installation wird empfohlen:

1. **[Benutzerhandbuch](user-guide.md) studieren** - Grundlagen der
   Interface-Bedienung
2. **[Monitoring](admin-guide.md#monitoring) konfigurieren** - Systemzustand
   überwachen
3. **[API-Dokumentation](../api-reference.md) studieren** - Integration mit
   externen Systemen
4. **[Backup](admin-guide.md#backup) einrichten** - Datenschutz

---

**🎉 Herzlichen Glückwunsch! ERNI-KI ist erfolgreich installiert und
einsatzbereit!**
