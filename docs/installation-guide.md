# 🚀 Подробное руководство по установке ERNI-KI

> **Версия документа:** 3.0
> **Дата обновления:** 2025-07-15
> **Время установки:** 30-60 минут

## 📋 Системные требования

### Минимальные требования
- **ОС**: Ubuntu 20.04+ / CentOS 8+ / Debian 11+ / RHEL 8+
- **CPU**: 4 ядра (Intel/AMD x86_64)
- **RAM**: 8GB (минимум для базовой работы)
- **Диск**: 50GB свободного места (SSD рекомендуется)
- **Сеть**: Стабильное интернет-соединение

### Рекомендуемые требования
- **CPU**: 8+ ядер с поддержкой AVX2
- **RAM**: 32GB (для больших языковых моделей)
- **GPU**: NVIDIA GPU с 8GB+ VRAM (RTX 3070/4060 или выше)
- **Диск**: 200GB+ NVMe SSD
- **Сеть**: 100 Mbps+ для загрузки моделей

### Поддерживаемые GPU
- **NVIDIA**: RTX 20/30/40 серии, Tesla, Quadro с CUDA 11.8+
- **Минимальная VRAM**: 6GB для моделей 7B параметров
- **Рекомендуемая VRAM**: 12GB+ для моделей 13B+ параметров

## 🔧 Предварительная подготовка системы

### 1. Обновление системы

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

### 2. Установка Docker и Docker Compose

#### Автоматическая установка (рекомендуется)
```bash
# Установка Docker через официальный скрипт
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Добавление пользователя в группу docker
sudo usermod -aG docker $USER

# Перезагрузка для применения изменений группы
newgrp docker

# Проверка установки
docker --version
docker compose version
```

#### Ручная установка Docker (Ubuntu)
```bash
# Удаление старых версий
sudo apt remove docker docker-engine docker.io containerd runc

# Установка зависимостей
sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release

# Добавление официального GPG ключа Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Добавление репозитория Docker
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Установка Docker Engine
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

### 3. Настройка NVIDIA GPU (опционально)

#### Установка NVIDIA драйверов
```bash
# Проверка наличия GPU
lspci | grep -i nvidia

# Установка драйверов (Ubuntu)
sudo apt install -y nvidia-driver-535 nvidia-utils-535

# Перезагрузка системы
sudo reboot
```

#### Установка NVIDIA Container Toolkit
```bash
# Добавление репозитория NVIDIA
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list

# Установка nvidia-container-toolkit
sudo apt update
sudo apt install -y nvidia-container-toolkit

# Перезапуск Docker
sudo systemctl restart docker

# Проверка GPU в Docker
docker run --rm --gpus all nvidia/cuda:11.8-base-ubuntu20.04 nvidia-smi
```

## 📦 Установка ERNI-KI

### 1. Клонирование репозитория
```bash
# Клонирование проекта
git clone https://github.com/DIZ-admin/erni-ki.git
cd erni-ki

# Проверка структуры проекта
ls -la
```

### 2. Настройка конфигурационных файлов

#### Копирование примеров конфигураций
```bash
# Копирование основного compose файла
cp compose.yml.example compose.yml

# Копирование всех переменных окружения
for file in env/*.example; do
  cp "$file" "${file%.example}"
done

# Копирование конфигураций nginx
cp conf/nginx/nginx.example conf/nginx/nginx.conf
cp conf/nginx/conf.d/default.example conf/nginx/conf.d/default.conf
```

#### Генерация секретных ключей
```bash
# Создание скрипта для генерации ключей
cat > scripts/generate-secrets.sh << 'EOF'
#!/bin/bash

# Генерация случайных ключей
JWT_SECRET=$(openssl rand -hex 32)
WEBUI_SECRET_KEY=$(openssl rand -hex 32)
SEARXNG_SECRET_KEY=$(openssl rand -hex 16)
POSTGRES_PASSWORD=$(openssl rand -base64 32)

# Обновление файлов окружения
sed -i "s/CHANGE_BEFORE_GOING_LIVE/$JWT_SECRET/g" env/auth.env
sed -i "s/89f03e7ae86485051232d47071a15241ae727f705589776321b5a52e14a6fe57/$WEBUI_SECRET_KEY/g" env/openwebui.env
sed -i "s/CHANGE_BEFORE_GOING_LIVE/$SEARXNG_SECRET_KEY/g" env/searxng.env
sed -i "s/CHANGE_BEFORE_GOING_LIVE/$POSTGRES_PASSWORD/g" env/postgres.env

echo "✅ Секретные ключи успешно сгенерированы!"
EOF

chmod +x scripts/generate-secrets.sh
./scripts/generate-secrets.sh
```

### 3. Настройка переменных окружения

#### Основные настройки (env/openwebui.env)
```bash
# Редактирование основных настроек
nano env/openwebui.env
```

Ключевые параметры для настройки:
```env
# URL вашего домена (если используете Cloudflare)
WEBUI_URL=https://your-domain.com

# Настройки GPU (раскомментируйте для использования GPU)
USE_CUDA_DOCKER=true

# Настройки RAG поиска
WEB_SEARCH_ENGINE=searxng
ENABLE_RAG_WEB_SEARCH=true

# Лимиты загрузки файлов (в байтах, 100MB по умолчанию)
FILE_UPLOAD_LIMIT=104857600
```

#### Настройка Cloudflare (опционально)
```bash
# Редактирование настроек туннеля
nano env/cloudflared.env
```

```env
# Токен туннеля Cloudflare (получите в Cloudflare Dashboard)
TUNNEL_TOKEN=your-cloudflare-tunnel-token
```

#### Настройка базы данных
```bash
# Проверка настроек PostgreSQL
nano env/postgres.env
```

```env
# Настройки базы данных (пароль уже сгенерирован)
POSTGRES_DB=openwebui
POSTGRES_USER=openwebui
POSTGRES_PASSWORD=generated-password
```

### 4. Настройка Nginx

#### Обновление доменного имени
```bash
# Замена placeholder на ваш домен
sed -i 's/<domain-name>/your-domain.com/g' conf/nginx/conf.d/default.conf
```

#### Настройка SSL сертификатов (если не используете Cloudflare)
```bash
# Создание самоподписанных сертификатов для тестирования
sudo mkdir -p /etc/nginx/ssl
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/nginx-selfsigned.key \
  -out /etc/nginx/ssl/nginx-selfsigned.crt \
  -subj "/C=RU/ST=Moscow/L=Moscow/O=ERNI-KI/CN=localhost"
```

## 🚀 Запуск системы

### 1. Первый запуск
```bash
# Запуск всех сервисов
docker compose up -d

# Проверка статуса сервисов
docker compose ps

# Просмотр логов (опционально)
docker compose logs -f
```

### 2. Ожидание инициализации
```bash
# Проверка готовности сервисов (может занять 2-5 минут)
watch -n 5 'docker compose ps --format "table {{.Name}}\t{{.Status}}"'

# Ожидание пока все сервисы станут "healthy"
```

### 3. Загрузка первой языковой модели
```bash
# Загрузка легкой модели для тестирования (3B параметров)
docker compose exec ollama ollama pull llama3.2:3b

# Для более мощных систем можно загрузить модель побольше
docker compose exec ollama ollama pull llama3.1:8b

# Проверка загруженных моделей
docker compose exec ollama ollama list
```

## ✅ Проверка установки

### 1. Проверка доступности сервисов
```bash
# Проверка основного интерфейса
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/
# Ожидаемый результат: 200

# Проверка Ollama API
curl -s http://localhost:11434/api/tags
# Ожидаемый результат: JSON со списком моделей

# Проверка SearXNG API
curl -s "http://localhost:8080/api/searxng/search?q=test&format=json" | head -5
# Ожидаемый результат: JSON с результатами поиска
```

### 2. Проверка GPU (если установлен)
```bash
# Проверка доступности GPU в Ollama
docker exec erni-ki-ollama-1 nvidia-smi

# Проверка использования GPU
docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
```

### 3. Первый вход в систему
1. Откройте браузер и перейдите на `http://localhost:8080`
2. Создайте аккаунт администратора
3. Настройте подключение к Ollama: `http://ollama:11434`
4. Протестируйте чат с AI моделью

## 🔧 Настройка после установки

### 1. Настройка автозапуска
```bash
# Создание systemd сервиса для автозапуска
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

# Активация автозапуска
sudo systemctl enable erni-ki.service
sudo systemctl start erni-ki.service
```

### 2. Настройка мониторинга
```bash
# Создание скрипта мониторинга
cat > scripts/health-check.sh << 'EOF'
#!/bin/bash
echo "=== ERNI-KI Health Check ==="
echo "Дата: $(date)"
echo ""

# Проверка статуса контейнеров
echo "📊 Статус сервисов:"
docker compose ps --format "table {{.Name}}\t{{.Status}}"
echo ""

# Проверка использования ресурсов
echo "💾 Использование ресурсов:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
echo ""

# Проверка доступности API
echo "🌐 Проверка API:"
curl -s -o /dev/null -w "OpenWebUI: %{http_code}\n" http://localhost:8080/
curl -s -o /dev/null -w "Ollama: %{http_code}\n" http://localhost:11434/
echo ""
EOF

chmod +x scripts/health-check.sh
```

### 3. Настройка резервного копирования
```bash
# Настройка Backrest через веб-интерфейс
echo "Откройте http://localhost:9898 для настройки бэкапов"
echo "Логин: admin"
echo "Пароль: указан в env/backrest.env"
```

## 🛠️ Устранение неполадок

### Проблемы с запуском
```bash
# Проверка логов проблемного сервиса
docker compose logs service-name

# Перезапуск конкретного сервиса
docker compose restart service-name

# Полная перезагрузка системы
docker compose down && docker compose up -d
```

### Проблемы с GPU
```bash
# Проверка драйверов NVIDIA
nvidia-smi

# Проверка Docker GPU поддержки
docker run --rm --gpus all nvidia/cuda:11.8-base-ubuntu20.04 nvidia-smi

# Раскомментирование GPU настроек в compose.yml
sed -i 's/# deploy: \*gpu-deploy/deploy: *gpu-deploy/g' compose.yml
```

### Проблемы с сетью
```bash
# Проверка Docker сетей
docker network ls
docker network inspect erni-ki_default

# Перезапуск сетевого стека Docker
sudo systemctl restart docker
```

## 📚 Следующие шаги

После успешной установки рекомендуется:

1. **Изучить [Руководство пользователя](user-guide.md)** - основы работы с интерфейсом
2. **Настроить [Мониторинг](admin-guide.md#monitoring)** - отслеживание состояния системы
3. **Изучить [API документацию](api-reference.md)** - интеграция с внешними системами
4. **Настроить [Резервное копирование](admin-guide.md#backup)** - защита данных

---

**🎉 Поздравляем! ERNI-KI успешно установлен и готов к использованию!**
