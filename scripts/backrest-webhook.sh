#!/bin/bash

# Backrest Webhook для интеграции с системой мониторинга
# Получает уведомления от Backrest и отправляет их в систему мониторинга

WEBHOOK_DATA="$1"
MONITORING_LOG="/home/konstantin/Documents/augment-projects/erni-ki/logs/backrest-notifications.log"

# Создание директории для логов
mkdir -p "$(dirname "$MONITORING_LOG")"

# Логирование уведомления
echo "[$(date -Iseconds)] Backrest notification: $WEBHOOK_DATA" >> "$MONITORING_LOG"

# Отправка в систему мониторинга rate limiting (если настроена)
if [[ -f "/home/konstantin/Documents/augment-projects/erni-ki/scripts/monitor-rate-limiting.sh" ]]; then
    # Интеграция с системой мониторинга
    echo "Backrest notification: $WEBHOOK_DATA" | logger -t "erni-ki-backrest"
fi

exit 0
