#!/bin/bash

# ERNI-KI Network Creation Script
# Скрипт для создания оптимизированных Docker сетей

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции логирования
log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"; }
info() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"; }

# Создание оптимизированных Docker сетей
create_optimized_networks() {
    log "Создание оптимизированных Docker сетей..."
    
    # Удаляем существующие сети (если они есть)
    info "Удаление существующих сетей..."
    docker network rm erni-ki-backend 2>/dev/null || warn "Сеть erni-ki-backend не найдена"
    docker network rm erni-ki-monitoring 2>/dev/null || warn "Сеть erni-ki-monitoring не найдена"
    docker network rm erni-ki-internal 2>/dev/null || warn "Сеть erni-ki-internal не найдена"
    
    # Создаем backend сеть
    info "Создание backend сети..."
    docker network create \
        --driver bridge \
        --subnet=172.21.0.0/16 \
        --gateway=172.21.0.1 \
        --opt com.docker.network.bridge.name=erni-ki-be0 \
        --opt com.docker.network.driver.mtu=1500 \
        --opt com.docker.network.bridge.enable_icc=true \
        --opt com.docker.network.bridge.enable_ip_masquerade=true \
        erni-ki-backend
    
    # Создаем monitoring сеть
    info "Создание monitoring сети..."
    docker network create \
        --driver bridge \
        --subnet=172.22.0.0/16 \
        --gateway=172.22.0.1 \
        --opt com.docker.network.bridge.name=erni-ki-mon0 \
        --opt com.docker.network.driver.mtu=1500 \
        --opt com.docker.network.bridge.enable_icc=true \
        --opt com.docker.network.bridge.enable_ip_masquerade=true \
        erni-ki-monitoring
    
    # Создаем internal сеть с jumbo frames
    info "Создание internal сети..."
    docker network create \
        --driver bridge \
        --subnet=172.23.0.0/16 \
        --gateway=172.23.0.1 \
        --internal \
        --opt com.docker.network.bridge.name=erni-ki-int0 \
        --opt com.docker.network.driver.mtu=9000 \
        --opt com.docker.network.bridge.enable_icc=true \
        erni-ki-internal
    
    log "Оптимизированные Docker сети созданы"
}

# Проверка созданных сетей
verify_networks() {
    log "Проверка созданных сетей..."
    
    info "Список Docker сетей:"
    docker network ls | grep erni-ki
    
    info "Детали backend сети:"
    docker network inspect erni-ki-backend --format '{{.IPAM.Config}}'
    
    info "Детали monitoring сети:"
    docker network inspect erni-ki-monitoring --format '{{.IPAM.Config}}'
    
    info "Детали internal сети:"
    docker network inspect erni-ki-internal --format '{{.IPAM.Config}}'
    
    log "Проверка сетей завершена"
}

# Основная функция
main() {
    log "Запуск создания оптимизированных Docker сетей..."
    
    # Проверяем, что Docker запущен
    if ! docker info >/dev/null 2>&1; then
        error "Docker не запущен или недоступен"
        exit 1
    fi
    
    create_optimized_networks
    verify_networks
    
    log "Создание оптимизированных Docker сетей завершено!"
    info "Теперь можно запустить ERNI-KI с новой сетевой архитектурой"
    info "Выполните: docker-compose up -d"
}

# Запуск основной функции
main "$@"
