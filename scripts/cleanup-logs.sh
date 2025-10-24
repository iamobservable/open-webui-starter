#!/bin/bash
# Автоматическая очистка старых логов ERNI-KI
# Запускается ежедневно в 3:00 через cron

PROJECT_DIR="/home/konstantin/Documents/augment-projects/erni-ki"
LOG_FILE="$PROJECT_DIR/logs/cleanup.log"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Начало очистки логов" >> "$LOG_FILE"

# Удаление log-monitoring-report старше 7 дней
DELETED_MONITORING=$(find "$PROJECT_DIR/logs/" -name "log-monitoring-report-*.json" -mtime +7 -delete -print | wc -l)
echo "$(date '+%Y-%m-%d %H:%M:%S') - Удалено log-monitoring-report: $DELETED_MONITORING файлов" >> "$LOG_FILE"

# Удаление redis-status-report старше 7 дней
DELETED_REDIS=$(find "$PROJECT_DIR/logs/" -name "redis-status-report-*.md" -mtime +7 -delete -print | wc -l)
echo "$(date '+%Y-%m-%d %H:%M:%S') - Удалено redis-status-report: $DELETED_REDIS файлов" >> "$LOG_FILE"

# Удаление старых диагностических отчётов (старше 30 дней)
DELETED_DIAGNOSTICS=$(find "$PROJECT_DIR/logs/" -name "*-diagnostic-*.log" -mtime +30 -delete -print | wc -l)
echo "$(date '+%Y-%m-%d %H:%M:%S') - Удалено диагностических отчётов: $DELETED_DIAGNOSTICS файлов" >> "$LOG_FILE"

# Статистика
TOTAL_FILES=$(find "$PROJECT_DIR/logs/" -type f | wc -l)
TOTAL_SIZE=$(du -sh "$PROJECT_DIR/logs/" | awk '{print $1}')
echo "$(date '+%Y-%m-%d %H:%M:%S') - Текущее состояние: $TOTAL_FILES файлов, $TOTAL_SIZE" >> "$LOG_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Очистка логов завершена" >> "$LOG_FILE"
echo "---" >> "$LOG_FILE"
