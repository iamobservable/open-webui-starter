#!/bin/bash
# Мониторинг безопасности LiteLLM

LOG_FILE="/var/log/litellm-security.log"
ALERT_EMAIL="admin@example.com"

# Проверка подозрительных запросов
check_suspicious_requests() {
    echo "$(date): Проверка подозрительных запросов" >> $LOG_FILE

    # Анализ логов nginx
    tail -1000 /var/log/nginx/access.log | grep -E "(sql|script|exec|union|select)" | while read line; do
        echo "ALERT: Подозрительный запрос: $line" >> $LOG_FILE
        # Отправка уведомления (если настроена почта)
        # echo "$line" | mail -s "Security Alert: Suspicious Request" $ALERT_EMAIL
    done
}

# Проверка неудачных аутентификаций
check_auth_failures() {
    echo "$(date): Проверка неудачных аутентификаций" >> $LOG_FILE

    # Анализ логов LiteLLM
    docker-compose logs litellm | grep -i "unauthorized\|forbidden\|invalid.*key" | tail -50 | while read line; do
        echo "ALERT: Неудачная аутентификация: $line" >> $LOG_FILE
    done
}

# Проверка аномальной активности
check_anomalies() {
    echo "$(date): Проверка аномальной активности" >> $LOG_FILE

    # Высокая частота запросов от одного IP
    tail -1000 /var/log/nginx/access.log | awk '{print $1}' | sort | uniq -c | sort -nr | head -10 | while read count ip; do
        if [ "$count" -gt 100 ]; then
            echo "ALERT: Высокая активность от IP $ip: $count запросов" >> $LOG_FILE
        fi
    done
}

# Основная функция
main() {
    check_suspicious_requests
    check_auth_failures
    check_anomalies

    # Ротация логов
    if [ -f "$LOG_FILE" ] && [ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE") -gt 10485760 ]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
        touch "$LOG_FILE"
    fi
}

main
