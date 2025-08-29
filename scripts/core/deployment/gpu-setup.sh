#!/bin/bash
# Скрипт настройки GPU ускорения для ERNI-KI
# Установка NVIDIA Container Toolkit и настройка Ollama

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции логирования
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Проверка наличия NVIDIA GPU
check_nvidia_gpu() {
    log "Проверка наличия NVIDIA GPU..."
    
    if ! command -v nvidia-smi &> /dev/null; then
        error "NVIDIA драйверы не установлены. Установите драйверы NVIDIA перед запуском этого скрипта."
    fi
    
    local gpu_count=$(nvidia-smi --list-gpus | wc -l)
    if [ "$gpu_count" -eq 0 ]; then
        error "NVIDIA GPU не обнаружены"
    fi
    
    success "Обнаружено GPU: $gpu_count"
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader,nounits
}

# Определение дистрибутива Linux
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
    else
        error "Не удалось определить дистрибутив Linux"
    fi
    
    log "Обнаружен дистрибутив: $DISTRO $VERSION"
}

# Установка NVIDIA Container Toolkit для Ubuntu/Debian
install_nvidia_toolkit_debian() {
    log "Установка NVIDIA Container Toolkit для Ubuntu/Debian..."
    
    # Добавление репозитория
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    
    # Обновление пакетов и установка
    sudo apt-get update
    sudo apt-get install -y nvidia-container-toolkit
    
    success "NVIDIA Container Toolkit установлен"
}

# Установка NVIDIA Container Toolkit для CentOS/RHEL/Fedora
install_nvidia_toolkit_rhel() {
    log "Установка NVIDIA Container Toolkit для CentOS/RHEL/Fedora..."
    
    # Добавление репозитория
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \
        sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo
    
    # Установка
    if command -v dnf &> /dev/null; then
        sudo dnf install -y nvidia-container-toolkit
    else
        sudo yum install -y nvidia-container-toolkit
    fi
    
    success "NVIDIA Container Toolkit установлен"
}

# Установка NVIDIA Container Toolkit
install_nvidia_container_toolkit() {
    detect_distro
    
    case $DISTRO in
        ubuntu|debian)
            install_nvidia_toolkit_debian
            ;;
        centos|rhel|fedora)
            install_nvidia_toolkit_rhel
            ;;
        *)
            error "Неподдерживаемый дистрибутив: $DISTRO"
            ;;
    esac
}

# Настройка Docker для использования NVIDIA runtime
configure_docker_nvidia() {
    log "Настройка Docker для использования NVIDIA runtime..."
    
    # Настройка NVIDIA Container Runtime
    sudo nvidia-ctk runtime configure --runtime=docker
    
    # Перезапуск Docker
    sudo systemctl restart docker
    
    # Проверка конфигурации
    if docker run --rm --gpus all nvidia/cuda:11.0.3-base-ubuntu20.04 nvidia-smi; then
        success "Docker успешно настроен для использования GPU"
    else
        error "Ошибка настройки Docker для GPU"
    fi
}

# Обновление compose.yml для включения GPU
update_compose_gpu() {
    log "Обновление compose.yml для включения GPU поддержки..."
    
    local compose_file="compose.yml"
    
    # Проверка существования файла
    if [ ! -f "$compose_file" ]; then
        if [ -f "compose.yml.example" ]; then
            cp "compose.yml.example" "$compose_file"
            log "Создан compose.yml из примера"
        else
            error "Файл compose.yml не найден"
        fi
    fi
    
    # Раскомментирование GPU deploy для Ollama
    if grep -q "# deploy: \*gpu-deploy" "$compose_file"; then
        sed -i 's/# deploy: \*gpu-deploy/deploy: *gpu-deploy/' "$compose_file"
        success "GPU deploy включен для Ollama"
    else
        warning "GPU deploy уже включен или не найден в конфигурации"
    fi
    
    # Раскомментирование GPU deploy для Open WebUI (если есть)
    if grep -q "# deploy: \*gpu-deploy" "$compose_file"; then
        sed -i 's/# deploy: \*gpu-deploy/deploy: *gpu-deploy/' "$compose_file"
        success "GPU deploy включен для Open WebUI"
    fi
}

# Создание оптимизированной конфигурации Ollama
create_ollama_config() {
    log "Создание оптимизированной конфигурации Ollama..."
    
    local ollama_env="env/ollama.env"
    
    # Создание или обновление конфигурации
    cat > "$ollama_env" << 'EOF'
# Ollama GPU Configuration
OLLAMA_DEBUG=0
OLLAMA_HOST=0.0.0.0:11434
OLLAMA_ORIGINS=*

# GPU настройки
OLLAMA_GPU_LAYERS=-1
OLLAMA_NUM_PARALLEL=4
OLLAMA_MAX_LOADED_MODELS=3

# Производительность
OLLAMA_FLASH_ATTENTION=1
OLLAMA_KV_CACHE_TYPE=f16
OLLAMA_NUM_THREAD=0

# Память
OLLAMA_MAX_VRAM=0.9
OLLAMA_KEEP_ALIVE=5m

# Логирование
OLLAMA_LOG_LEVEL=INFO
EOF
    
    success "Создана оптимизированная конфигурация Ollama"
}

# Загрузка рекомендуемых моделей
download_models() {
    log "Загрузка рекомендуемых моделей..."
    
    # Проверка, что Ollama запущен
    if ! docker compose ps ollama | grep -q "Up"; then
        log "Запуск Ollama сервиса..."
        docker compose up -d ollama
        
        # Ожидание запуска
        local retries=30
        while [ $retries -gt 0 ]; do
            if docker compose exec ollama ollama list &>/dev/null; then
                break
            fi
            sleep 2
            ((retries--))
        done
        
        if [ $retries -eq 0 ]; then
            error "Ollama не запустился в течение 60 секунд"
        fi
    fi
    
    # Список моделей для загрузки
    local models=(
        "nomic-embed-text:latest"
        "llama3.2:3b"
    )
    
    for model in "${models[@]}"; do
        log "Загрузка модели: $model"
        if docker compose exec ollama ollama pull "$model"; then
            success "Модель $model загружена"
        else
            warning "Не удалось загрузить модель $model"
        fi
    done
}

# Тестирование GPU производительности
test_gpu_performance() {
    log "Тестирование GPU производительности..."
    
    # Простой тест генерации
    local test_prompt="Hello, how are you?"
    
    log "Тестирование с моделью llama3.2:3b..."
    local start_time=$(date +%s.%N)
    
    if docker compose exec ollama ollama run llama3.2:3b "$test_prompt" &>/dev/null; then
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc -l)
        success "Тест завершен за ${duration} секунд"
        
        if (( $(echo "$duration < 1.0" | bc -l) )); then
            success "Отличная производительность GPU! (<1s)"
        elif (( $(echo "$duration < 3.0" | bc -l) )); then
            success "Хорошая производительность GPU! (<3s)"
        else
            warning "Производительность GPU может быть улучшена (>3s)"
        fi
    else
        warning "Не удалось выполнить тест производительности"
    fi
}

# Создание мониторинга GPU
create_gpu_monitoring() {
    log "Создание конфигурации мониторинга GPU..."
    
    # Создание docker-compose override для мониторинга
    cat > "docker-compose.gpu-monitoring.yml" << 'EOF'
version: '3.8'

services:
  nvidia-exporter:
    image: mindprince/nvidia_gpu_prometheus_exporter:0.1
    restart: unless-stopped
    ports:
      - "9445:9445"
    volumes:
      - /usr/lib/x86_64-linux-gnu/libnvidia-ml.so.1:/usr/lib/x86_64-linux-gnu/libnvidia-ml.so.1:ro
      - /usr/bin/nvidia-smi:/usr/bin/nvidia-smi:ro
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
EOF
    
    success "Создана конфигурация мониторинга GPU"
    log "Для запуска мониторинга используйте: docker compose -f compose.yml -f docker-compose.gpu-monitoring.yml up -d"
}

# Основная функция
main() {
    log "Запуск настройки GPU ускорения для ERNI-KI..."
    
    # Проверка, что мы в корне проекта
    if [ ! -f "compose.yml.example" ]; then
        error "Скрипт должен запускаться из корня проекта ERNI-KI"
    fi
    
    # Проверка прав sudo
    if [ "$EUID" -eq 0 ]; then
        error "Не запускайте скрипт от root. Используйте sudo при необходимости."
    fi
    
    check_nvidia_gpu
    install_nvidia_container_toolkit
    configure_docker_nvidia
    update_compose_gpu
    create_ollama_config
    create_gpu_monitoring
    
    success "Настройка GPU завершена!"
    
    echo ""
    log "Следующие шаги:"
    echo "1. Перезапустите сервисы: docker compose down && docker compose up -d"
    echo "2. Дождитесь запуска Ollama сервиса"
    echo "3. Загрузите модели: $0 --download-models"
    echo "4. Протестируйте производительность: $0 --test-performance"
    
    # Обработка аргументов командной строки
    case "${1:-}" in
        --download-models)
            download_models
            ;;
        --test-performance)
            test_gpu_performance
            ;;
        --help)
            echo "Использование: $0 [--download-models|--test-performance|--help]"
            echo "  --download-models   Загрузить рекомендуемые модели"
            echo "  --test-performance  Протестировать производительность GPU"
            echo "  --help             Показать эту справку"
            ;;
    esac
}

# Запуск скрипта
main "$@"
