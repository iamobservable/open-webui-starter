#!/bin/bash

# SearXNG Engine Monitoring Script для ERNI-KI
# Мониторинг ошибок поисковых движков и автоматическое отключение проблемных

set -euo pipefail

# === КОНФИГУРАЦИЯ ===
LOG_FILE="/home/konstantin/Documents/augment-projects/erni-ki/logs/searxng-engine-monitor.log"
ERROR_THRESHOLD=5  # Количество ошибок для отключения движка
TIME_WINDOW=300    # Временное окно в секундах (5 минут)
SEARXNG_CONTAINER="erni-ki-searxng-1"

# === ФУНКЦИИ ===
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

check_engine_errors() {
    local engine="$1"
    local error_count

    # Подсчет ошибок за последние TIME_WINDOW секунд
    error_count=$(docker logs --since="${TIME_WINDOW}s" "$SEARXNG_CONTAINER" 2>/dev/null | \
                  grep -c "ERROR:searx.engines.${engine}:" || echo "0")

    echo "$error_count"
}

disable_engine() {
    local engine="$1"
    log_message "WARNING: Отключение проблемного движка: $engine"

    # Создание backup конфигурации
    cp conf/searxng/settings.yml "conf/searxng/settings.yml.backup.$(date +%Y%m%d_%H%M%S)"

    # Отключение движка в конфигурации
    sed -i "/name: $engine/,/disabled:/ s/disabled: false/disabled: true/" conf/searxng/settings.yml

    # Перезапуск SearXNG для применения изменений
    docker-compose restart searxng

    log_message "INFO: Движок $engine отключен и SearXNG перезапущен"
}

# === ОСНОВНАЯ ЛОГИКА ===
main() {
    log_message "INFO: Запуск мониторинга SearXNG движков"

    # Список движков для мониторинга
    engines=("bing" "google" "duckduckgo" "startpage" "brave")

    for engine in "${engines[@]}"; do
        error_count=$(check_engine_errors "$engine")

        if [[ $error_count -gt $ERROR_THRESHOLD ]]; then
            log_message "ALERT: Движок $engine имеет $error_count ошибок за последние $TIME_WINDOW секунд"

            # Проверяем, не отключен ли уже движок
            if grep -A2 "name: $engine" conf/searxng/settings.yml | grep -q "disabled: false"; then
                disable_engine "$engine"
            else
                log_message "INFO: Движок $engine уже отключен"
            fi
        else
            log_message "INFO: Движок $engine: $error_count ошибок (норма)"
        fi
    done

    log_message "INFO: Мониторинг завершен"
}

# === ЗАПУСК ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
