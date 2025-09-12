#!/bin/bash

# ERNI-KI Network Optimization Script
# Скрипт для оптимизации сетевой производительности системы

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция логирования
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Проверка прав администратора
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Этот скрипт должен быть запущен с правами администратора (sudo)"
        exit 1
    fi
}

# Создание резервной копии текущих настроек
backup_current_settings() {
    log "Создание резервной копии текущих сетевых настроек..."

    local backup_dir=".config-backup/network-settings-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"

    # Сохраняем текущие настройки ядра
    sysctl -a > "$backup_dir/sysctl-current.conf" 2>/dev/null || true

    # Сохраняем настройки Docker
    if command -v docker &> /dev/null; then
        docker network ls > "$backup_dir/docker-networks.txt" 2>/dev/null || true
        docker system info > "$backup_dir/docker-info.txt" 2>/dev/null || true
    fi

    # Сохраняем настройки сети
    ip addr show > "$backup_dir/ip-addr.txt" 2>/dev/null || true
    ip route show > "$backup_dir/ip-route.txt" 2>/dev/null || true

    log "Резервная копия создана в $backup_dir"
}

# Оптимизация параметров ядра для сетевой производительности
optimize_kernel_parameters() {
    log "Оптимизация параметров ядра для сетевой производительности..."

    # Создаем файл конфигурации для sysctl
    cat > /etc/sysctl.d/99-erni-ki-network.conf << 'EOF'
# ERNI-KI Network Optimization Settings
# Оптимизация сетевых параметров для высокой производительности

# TCP/IP Stack Optimization
# Оптимизация TCP/IP стека
net.core.rmem_default = 262144
net.core.rmem_max = 536870912
net.core.wmem_default = 262144
net.core.wmem_max = 536870912
net.core.netdev_max_backlog = 30000
net.core.netdev_budget = 600

# TCP Buffer Sizes
# Размеры TCP буферов
net.ipv4.tcp_rmem = 4096 87380 536870912
net.ipv4.tcp_wmem = 4096 65536 536870912
net.ipv4.tcp_mem = 786432 1048576 26777216

# TCP Connection Optimization
# Оптимизация TCP соединений
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_slow_start_after_idle = 0

# TCP Keepalive Settings
# Настройки TCP keepalive
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 3

# Connection Limits
# Лимиты соединений
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1

# Network Security (не влияет на производительность, но важно)
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# IPv6 Optimization (если используется)
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0

# File System Optimization for Network I/O
# Оптимизация файловой системы для сетевого I/O
fs.file-max = 2097152
fs.nr_open = 2097152

# Virtual Memory Optimization
# Оптимизация виртуальной памяти
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.vfs_cache_pressure = 50
EOF

    # Применяем настройки
    sysctl -p /etc/sysctl.d/99-erni-ki-network.conf

    log "Параметры ядра оптимизированы"
}

# Оптимизация Docker для сетевой производительности
optimize_docker_settings() {
    log "Оптимизация настроек Docker..."

    # Создаем или обновляем daemon.json
    local docker_config="/etc/docker/daemon.json"
    local temp_config="/tmp/docker-daemon.json"

    # Читаем существующую конфигурацию или создаем новую
    if [[ -f "$docker_config" ]]; then
        cp "$docker_config" "$temp_config"
    else
        echo '{}' > "$temp_config"
    fi

    # Добавляем оптимизации с помощью jq
    if command -v jq &> /dev/null; then
        jq '. + {
            "default-address-pools": [
                {
                    "base": "172.20.0.0/16",
                    "size": 24
                },
                {
                    "base": "172.21.0.0/16",
                    "size": 24
                },
                {
                    "base": "172.22.0.0/16",
                    "size": 24
                },
                {
                    "base": "172.23.0.0/16",
                    "size": 24
                }
            ],
            "bip": "172.17.0.1/16",
            "mtu": 1500,
            "live-restore": true,
            "max-concurrent-downloads": 10,
            "max-concurrent-uploads": 10,
            "storage-driver": "overlay2",
            "storage-opts": [
                "overlay2.override_kernel_check=true"
            ],
            "log-driver": "json-file",
            "log-opts": {
                "max-size": "10m",
                "max-file": "3"
            }
        }' "$temp_config" > "$docker_config"
    else
        warn "jq не установлен, создаем конфигурацию вручную"
        cat > "$docker_config" << 'EOF'
{
    "default-address-pools": [
        {
            "base": "172.20.0.0/16",
            "size": 24
        },
        {
            "base": "172.21.0.0/16",
            "size": 24
        },
        {
            "base": "172.22.0.0/16",
            "size": 24
        },
        {
            "base": "172.23.0.0/16",
            "size": 24
        }
    ],
    "bip": "172.17.0.1/16",
    "mtu": 1500,
    "live-restore": true,
    "max-concurrent-downloads": 10,
    "max-concurrent-uploads": 10,
    "storage-driver": "overlay2",
    "storage-opts": [
        "overlay2.override_kernel_check=true"
    ],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    }
}
EOF
    fi

    rm -f "$temp_config"

    log "Настройки Docker оптимизированы"
}

# Создание оптимизированных Docker сетей
create_optimized_networks() {
    log "Создание оптимизированных Docker сетей..."

    # Удаляем существующие сети (если они есть)
    docker network rm erni-ki-backend erni-ki-monitoring erni-ki-internal 2>/dev/null || true

    # Создаем backend сеть
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

# Проверка и установка необходимых пакетов
install_dependencies() {
    log "Проверка и установка необходимых пакетов..."

    # Обновляем список пакетов
    apt-get update -qq

    # Устанавливаем необходимые пакеты
    apt-get install -y \
        net-tools \
        iptables-persistent \
        ethtool \
        tcpdump \
        iftop \
        nethogs \
        jq \
        curl \
        wget

    log "Необходимые пакеты установлены"
}

# Оптимизация сетевых интерфейсов
optimize_network_interfaces() {
    log "Оптимизация сетевых интерфейсов..."

    # Получаем список активных интерфейсов
    local interfaces=$(ip link show | grep -E '^[0-9]+:' | grep -v 'lo:' | cut -d: -f2 | tr -d ' ')

    for interface in $interfaces; do
        if [[ "$interface" =~ ^(eth|ens|enp) ]]; then
            info "Оптимизация интерфейса $interface"

            # Увеличиваем размеры буферов (если поддерживается)
            ethtool -G "$interface" rx 4096 tx 4096 2>/dev/null || warn "Не удалось изменить размеры буферов для $interface"

            # Включаем offloading (если поддерживается)
            ethtool -K "$interface" gso on tso on gro on lro on 2>/dev/null || warn "Не удалось включить offloading для $interface"

            # Оптимизируем настройки прерываний
            ethtool -C "$interface" rx-usecs 50 tx-usecs 50 2>/dev/null || warn "Не удалось оптимизировать прерывания для $interface"
        fi
    done

    log "Сетевые интерфейсы оптимизированы"
}

# Проверка результатов оптимизации
verify_optimization() {
    log "Проверка результатов оптимизации..."

    info "Текущие настройки TCP буферов:"
    sysctl net.core.rmem_max net.core.wmem_max net.ipv4.tcp_rmem net.ipv4.tcp_wmem

    info "Настройки соединений:"
    sysctl net.core.somaxconn net.ipv4.tcp_max_syn_backlog

    info "Docker сети:"
    docker network ls | grep erni-ki

    info "Статус Docker:"
    systemctl is-active docker

    log "Проверка завершена"
}

# Основная функция
main() {
    log "Запуск оптимизации сетевой производительности ERNI-KI..."

    check_root
    backup_current_settings
    install_dependencies
    optimize_kernel_parameters
    optimize_docker_settings

    # Перезапускаем Docker для применения настроек
    log "Перезапуск Docker для применения настроек..."
    systemctl restart docker
    sleep 10

    create_optimized_networks
    optimize_network_interfaces
    verify_optimization

    log "Оптимизация сетевой производительности завершена!"
    warn "Рекомендуется перезагрузить систему для полного применения всех настроек"
    info "Для применения изменений в ERNI-KI выполните: docker-compose down && docker-compose up -d"
}

# Запуск основной функции
main "$@"
