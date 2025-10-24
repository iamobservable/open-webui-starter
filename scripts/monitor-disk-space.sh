#!/bin/bash
# Мониторинг дискового пространства ERNI-KI
# Запускается ежедневно в 1:00 через cron

PROJECT_DIR="/home/konstantin/Documents/augment-projects/erni-ki"
LOG_FILE="$PROJECT_DIR/logs/disk-monitor.log"
THRESHOLD=80  # Порог предупреждения в %

# Проверка использования диска
USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
AVAILABLE=$(df -h / | awk 'NR==2 {print $4}')

echo "$(date '+%Y-%m-%d %H:%M:%S') - Использование диска: ${USAGE}%, доступно: $AVAILABLE" >> "$LOG_FILE"

# Предупреждение при превышении порога
if [ "$USAGE" -gt "$THRESHOLD" ]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') - ⚠️ WARNING: Disk usage is ${USAGE}% (threshold: ${THRESHOLD}%)" >> "$LOG_FILE"

  # Отправить уведомление через webhook (опционально)
  # WEBHOOK_URL="http://localhost:8080/api/webhook/disk-alert"
  # curl -X POST "$WEBHOOK_URL" -H "Content-Type: application/json" \
  #   -d "{\"message\": \"Disk usage: ${USAGE}%, available: $AVAILABLE\"}" 2>/dev/null
fi

# Логирование размера проекта
PROJECT_SIZE=$(du -sh "$PROJECT_DIR" 2>/dev/null | awk '{print $1}')
echo "$(date '+%Y-%m-%d %H:%M:%S') - Размер проекта ERNI-KI: $PROJECT_SIZE" >> "$LOG_FILE"

# Логирование размера основных директорий
DATA_SIZE=$(du -sh "$PROJECT_DIR/data" 2>/dev/null | awk '{print $1}')
BACKUP_SIZE=$(du -sh "$PROJECT_DIR/.config-backup" 2>/dev/null | awk '{print $1}')
LOGS_SIZE=$(du -sh "$PROJECT_DIR/logs" 2>/dev/null | awk '{print $1}')

echo "$(date '+%Y-%m-%d %H:%M:%S') - data/: $DATA_SIZE, .config-backup/: $BACKUP_SIZE, logs/: $LOGS_SIZE" >> "$LOG_FILE"

# Docker статистика
DOCKER_IMAGES=$(docker images -q | wc -l)
DOCKER_CONTAINERS=$(docker ps -q | wc -l)
DOCKER_VOLUMES=$(docker volume ls -q | wc -l)

echo "$(date '+%Y-%m-%d %H:%M:%S') - Docker: $DOCKER_IMAGES images, $DOCKER_CONTAINERS containers, $DOCKER_VOLUMES volumes" >> "$LOG_FILE"
echo "---" >> "$LOG_FILE"

# Ротация лога мониторинга (хранить только последние 1000 строк)
if [ $(wc -l < "$LOG_FILE") -gt 1000 ]; then
  tail -n 1000 "$LOG_FILE" > "$LOG_FILE.tmp"
  mv "$LOG_FILE.tmp" "$LOG_FILE"
fi
