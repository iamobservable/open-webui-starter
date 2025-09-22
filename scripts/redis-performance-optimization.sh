#!/bin/bash
# Redis Performance Optimization для ERNI-KI
# Оптимизация производительности и мониторинга

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Redis Performance Optimization для ERNI-KI ===${NC}"

# Функция логирования
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Проверка, что мы в правильной директории
if [[ ! -f "compose.yml" ]]; then
    error "compose.yml не найден. Запустите скрипт из корневой директории ERNI-KI"
    exit 1
fi

# Создание резервной копии
log "Создание резервной копии конфигурации..."
mkdir -p .config-backup/redis-performance-$(date +%Y%m%d-%H%M%S)
cp compose.yml .config-backup/redis-performance-$(date +%Y%m%d-%H%M%S)/
cp -r env/ .config-backup/redis-performance-$(date +%Y%m%d-%H%M%S)/ 2>/dev/null || true

# 1. Оптимизация настроек Redis Main
log "Оптимизация настроек Redis Main..."

# Добавляем дополнительные параметры производительности
if ! grep -q "tcp-keepalive" compose.yml; then
    sed -i '/redis:/,/command: >/{
        /--maxmemory 512mb/a\
      --tcp-keepalive 300\
      --timeout 0\
      --tcp-backlog 511\
      --databases 16
    }' compose.yml
fi

# 2. Создание конфигурационного файла Redis
log "Создание оптимизированного redis.conf..."
mkdir -p conf/redis

cat > conf/redis/redis.conf << 'EOF'
# Redis Configuration для ERNI-KI Production
# Оптимизированная конфигурация для кэширования и сессий

# === СЕТЕВЫЕ НАСТРОЙКИ ===
bind 0.0.0.0
port 6379
tcp-backlog 511
timeout 0
tcp-keepalive 300

# === ОБЩИЕ НАСТРОЙКИ ===
daemonize no
supervised no
pidfile /var/run/redis_6379.pid
loglevel notice
logfile ""
databases 16

# === СНАПШОТЫ (отключены для производительности) ===
save ""

# === РЕПЛИКАЦИЯ ===
# Настройки мастера (по умолчанию)

# === БЕЗОПАСНОСТЬ ===
requirepass ErniKiRedisSecurePassword2024
# Отключаем опасные команды
rename-command FLUSHDB ""
rename-command FLUSHALL ""
rename-command DEBUG ""
rename-command CONFIG "CONFIG_b835c3f8a5d9e7f2a1b4c6d8e9f0a2b3"

# === ЛИМИТЫ КЛИЕНТОВ ===
maxclients 10000

# === УПРАВЛЕНИЕ ПАМЯТЬЮ ===
maxmemory 512mb
maxmemory-policy allkeys-lru
maxmemory-samples 5

# === APPEND ONLY MODE ===
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
aof-load-truncated yes
aof-use-rdb-preamble yes

# === LUA SCRIPTING ===
lua-time-limit 5000

# === МЕДЛЕННЫЕ ЛОГИ ===
slowlog-log-slower-than 10000
slowlog-max-len 128

# === УВЕДОМЛЕНИЯ О СОБЫТИЯХ KEYSPACE ===
notify-keyspace-events ""

# === ДОПОЛНИТЕЛЬНЫЕ НАСТРОЙКИ ===
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
list-max-ziplist-size -2
list-compress-depth 0
set-max-intset-entries 512
zset-max-ziplist-entries 128
zset-max-ziplist-value 64
hll-sparse-max-bytes 3000
stream-node-max-bytes 4096
stream-node-max-entries 100
activerehashing yes
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit replica 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60
hz 10
dynamic-hz yes
aof-rewrite-incremental-fsync yes
rdb-save-incremental-fsync yes
EOF

# 3. Обновление compose.yml для использования конфигурационного файла
log "Обновление compose.yml для использования redis.conf..."
if ! grep -q "conf/redis/redis.conf" compose.yml; then
    # Добавляем volume для конфигурации
    sed -i '/redis:/,/volumes:/{
        /- \.\/data\/redis:\/data/a\
      - ./conf/redis/redis.conf:/usr/local/etc/redis/redis.conf:ro
    }' compose.yml

    # Обновляем команду для использования конфигурационного файла
    sed -i '/redis:/,/command: >/{
        /command: >/,/--databases 16/{
            s/redis-server.*/redis-server \/usr\/local\/etc\/redis\/redis.conf/
        }
    }' compose.yml
fi

# 4. Создание скрипта мониторинга производительности
log "Создание скрипта мониторинга производительности..."
cat > scripts/redis-monitor.sh << 'EOF'
#!/bin/bash
# Redis Performance Monitor для ERNI-KI

set -euo pipefail

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Redis Performance Monitor ===${NC}"
echo "Время: $(date)"
echo

# Функция получения метрик
get_redis_metric() {
    local container=$1
    local password=$2
    local metric=$3

    if [[ -n "$password" ]]; then
        docker exec "$container" redis-cli -a "$password" info 2>/dev/null | grep "^$metric:" | cut -d: -f2 | tr -d '\r'
    else
        docker exec "$container" redis-cli info 2>/dev/null | grep "^$metric:" | cut -d: -f2 | tr -d '\r'
    fi
}

# Мониторинг Redis Main
echo -e "${GREEN}=== Redis Main (erni-ki-redis-1) ===${NC}"
if docker ps --filter "name=erni-ki-redis-1" --format "{{.Status}}" | grep -q "healthy"; then
    echo "Статус: ✅ Здоров"

    # Основные метрики
    connected_clients=$(get_redis_metric "erni-ki-redis-1" "ErniKiRedisSecurePassword2024" "connected_clients")
    used_memory_human=$(get_redis_metric "erni-ki-redis-1" "ErniKiRedisSecurePassword2024" "used_memory_human")
    total_commands_processed=$(get_redis_metric "erni-ki-redis-1" "ErniKiRedisSecurePassword2024" "total_commands_processed")
    keyspace_hits=$(get_redis_metric "erni-ki-redis-1" "ErniKiRedisSecurePassword2024" "keyspace_hits")
    keyspace_misses=$(get_redis_metric "erni-ki-redis-1" "ErniKiRedisSecurePassword2024" "keyspace_misses")

    echo "Подключенные клиенты: $connected_clients"
    echo "Использование памяти: $used_memory_human"
    echo "Обработанные команды: $total_commands_processed"
    echo "Попадания в кэш: $keyspace_hits"
    echo "Промахи кэша: $keyspace_misses"

    # Расчет hit ratio
    if [[ $keyspace_hits -gt 0 || $keyspace_misses -gt 0 ]]; then
        hit_ratio=$(echo "scale=2; $keyspace_hits * 100 / ($keyspace_hits + $keyspace_misses)" | bc -l 2>/dev/null || echo "0")
        echo "Hit Ratio: ${hit_ratio}%"
    fi

    # Количество ключей
    dbsize=$(docker exec erni-ki-redis-1 redis-cli -a 'ErniKiRedisSecurePassword2024' dbsize 2>/dev/null)
    echo "Количество ключей: $dbsize"

else
    echo "Статус: ❌ Нездоров"
fi

echo

# Мониторинг Redis LiteLLM
echo -e "${GREEN}=== Redis LiteLLM (erni-ki-redis-litellm-1) ===${NC}"
if docker ps --filter "name=erni-ki-redis-litellm-1" --format "{{.Status}}" | grep -q "healthy"; then
    echo "Статус: ✅ Здоров"

    # Пробуем без пароля, потом с паролем
    if connected_clients=$(get_redis_metric "erni-ki-redis-litellm-1" "" "connected_clients" 2>/dev/null); then
        password_status="Без пароля"
    elif connected_clients=$(get_redis_metric "erni-ki-redis-litellm-1" "ErniKiRedisLiteLLMPassword2024" "connected_clients" 2>/dev/null); then
        password_status="С паролем"
    else
        echo "❌ Не удается подключиться"
        connected_clients="N/A"
        password_status="Неизвестно"
    fi

    echo "Аутентификация: $password_status"
    echo "Подключенные клиенты: $connected_clients"

    if [[ "$connected_clients" != "N/A" ]]; then
        if [[ "$password_status" == "С паролем" ]]; then
            used_memory_human=$(get_redis_metric "erni-ki-redis-litellm-1" "ErniKiRedisLiteLLMPassword2024" "used_memory_human")
            dbsize=$(docker exec erni-ki-redis-litellm-1 redis-cli -a 'ErniKiRedisLiteLLMPassword2024' dbsize 2>/dev/null)
        else
            used_memory_human=$(get_redis_metric "erni-ki-redis-litellm-1" "" "used_memory_human")
            dbsize=$(docker exec erni-ki-redis-litellm-1 redis-cli dbsize 2>/dev/null)
        fi
        echo "Использование памяти: $used_memory_human"
        echo "Количество ключей: $dbsize"
    fi
else
    echo "Статус: ❌ Нездоров"
fi

echo

# Системные ресурсы
echo -e "${GREEN}=== Системные ресурсы ===${NC}"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}" | grep redis

echo
echo -e "${BLUE}Мониторинг завершен: $(date)${NC}"
EOF

chmod +x scripts/redis-monitor.sh

# 5. Создание cron задачи для мониторинга
log "Создание задачи мониторинга..."
cat > scripts/setup-redis-monitoring.sh << 'EOF'
#!/bin/bash
# Настройка автоматического мониторинга Redis

# Создание директории для логов мониторинга
mkdir -p logs/redis-monitoring

# Добавление cron задачи (каждые 5 минут)
(crontab -l 2>/dev/null; echo "*/5 * * * * cd $(pwd) && ./scripts/redis-monitor.sh >> logs/redis-monitoring/redis-monitor-$(date +\%Y\%m\%d).log 2>&1") | crontab -

echo "✅ Мониторинг Redis настроен (каждые 5 минут)"
echo "📊 Логи: logs/redis-monitoring/"
echo "🔍 Ручной запуск: ./scripts/redis-monitor.sh"
EOF

chmod +x scripts/setup-redis-monitoring.sh

log "Оптимизация производительности завершена!"

echo -e "${GREEN}=== Резюме оптимизации ===${NC}"
echo "✅ Создан оптимизированный redis.conf"
echo "✅ Обновлена конфигурация compose.yml"
echo "✅ Добавлены параметры производительности"
echo "✅ Создан скрипт мониторинга"
echo "✅ Настроена автоматизация мониторинга"

echo -e "${YELLOW}Следующие шаги:${NC}"
echo "1. Перезапустите Redis: docker compose restart redis"
echo "2. Проверьте конфигурацию: docker exec erni-ki-redis-1 redis-cli -a 'ErniKiRedisSecurePassword2024' config get '*'"
echo "3. Запустите мониторинг: ./scripts/redis-monitor.sh"
echo "4. Настройте автоматический мониторинг: ./scripts/setup-redis-monitoring.sh"
