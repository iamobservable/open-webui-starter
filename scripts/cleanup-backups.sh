#!/bin/bash
# Автоматическая очистка старых backup ERNI-KI
# Запускается еженедельно в воскресенье в 2:00 через cron

PROJECT_DIR="/home/konstantin/Documents/augment-projects/erni-ki"
BACKUP_DIR="$PROJECT_DIR/.config-backup"
LOG_FILE="$BACKUP_DIR/cleanup.log"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Начало очистки backup" >> "$LOG_FILE"

# Список критических директорий, которые НЕ удаляем
EXCLUDE_DIRS=("env" "conf" "secrets" "monitoring")

# Подсчёт размера до очистки
SIZE_BEFORE=$(du -sh "$BACKUP_DIR" | awk '{print $1}')
echo "$(date '+%Y-%m-%d %H:%M:%S') - Размер backup до очистки: $SIZE_BEFORE" >> "$LOG_FILE"

# Удаление backup старше 30 дней (кроме критических)
DELETED_COUNT=0
for dir in "$BACKUP_DIR"/*; do
  if [ -d "$dir" ]; then
    DIR_NAME=$(basename "$dir")

    # Проверка, не входит ли директория в список исключений
    SKIP=0
    for exclude in "${EXCLUDE_DIRS[@]}"; do
      if [[ "$DIR_NAME" == "$exclude" ]]; then
        SKIP=1
        break
      fi
    done

    if [ $SKIP -eq 0 ]; then
      # Проверка возраста директории (старше 30 дней)
      if [ $(find "$dir" -maxdepth 0 -type d -mtime +30 2>/dev/null | wc -l) -gt 0 ]; then
        DIR_SIZE=$(du -sh "$dir" 2>/dev/null | awk '{print $1}')
        rm -rf "$dir" 2>/dev/null
        if [ $? -eq 0 ]; then
          echo "$(date '+%Y-%m-%d %H:%M:%S') - Удалён: $DIR_NAME ($DIR_SIZE)" >> "$LOG_FILE"
          ((DELETED_COUNT++))
        else
          echo "$(date '+%Y-%m-%d %H:%M:%S') - ОШИБКА при удалении: $DIR_NAME (требуется sudo?)" >> "$LOG_FILE"
        fi
      fi
    fi
  fi
done

# Подсчёт размера после очистки
SIZE_AFTER=$(du -sh "$BACKUP_DIR" | awk '{print $1}')
echo "$(date '+%Y-%m-%d %H:%M:%S') - Размер backup после очистки: $SIZE_AFTER" >> "$LOG_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Удалено директорий: $DELETED_COUNT" >> "$LOG_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Очистка backup завершена" >> "$LOG_FILE"
echo "---" >> "$LOG_FILE"
