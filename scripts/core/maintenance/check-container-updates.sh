#!/bin/bash
# Скрипт проверки обновлений Docker контейнеров в ERNI-KI
# Автор: Альтэон Шульц, Tech Lead
# Дата: 29 августа 2025

set -euo pipefail

# === КОНФИГУРАЦИЯ ===
COMPOSE_FILE="compose.yml"
REPORT_FILE="container-updates-report-$(date +%Y%m%d_%H%M%S).md"

# === ЦВЕТА ДЛЯ ЛОГИРОВАНИЯ ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# === ФУНКЦИИ ЛОГИРОВАНИЯ ===
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
}

# === ПРОВЕРКА ПРЕДВАРИТЕЛЬНЫХ УСЛОВИЙ ===
check_prerequisites() {
    log "Проверка предварительных условий..."

    # Проверка Docker
    if ! command -v docker &> /dev/null; then
        error "Docker не установлен"
        exit 1
    fi

    # Проверка docker-compose
    if ! command -v docker-compose &> /dev/null; then
        error "docker-compose не установлен"
        exit 1
    fi

    # Проверка jq
    if ! command -v jq &> /dev/null; then
        error "jq не установлен. Установите: sudo apt install jq"
        exit 1
    fi

    # Проверка curl
    if ! command -v curl &> /dev/null; then
        error "curl не установлен"
        exit 1
    fi

    # Проверка compose файла
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        error "Файл $COMPOSE_FILE не найден"
        exit 1
    fi

    success "Предварительные условия выполнены"
}

# === ПОЛУЧЕНИЕ ТЕКУЩИХ ВЕРСИЙ ===
get_current_versions() {
    log "Получение текущих версий контейнеров..."

    # Извлечение образов из compose файла
    declare -gA CURRENT_IMAGES

    # Парсинг compose.yml для получения образов
    while IFS= read -r line; do
        if [[ $line =~ image:[[:space:]]*(.+) ]]; then
            image="${BASH_REMATCH[1]}"
            # Удаление кавычек если есть
            image=$(echo "$image" | sed 's/["'"'"']//g')

            # Разделение на repository и tag
            if [[ $image =~ (.+):(.+) ]]; then
                repo="${BASH_REMATCH[1]}"
                tag="${BASH_REMATCH[2]}"
            else
                repo="$image"
                tag="latest"
            fi

            CURRENT_IMAGES["$repo"]="$tag"
        fi
    done < "$COMPOSE_FILE"

    success "Найдено ${#CURRENT_IMAGES[@]} образов в compose файле"
}

# === ПРОВЕРКА ДОСТУПНЫХ ВЕРСИЙ ===
check_available_versions() {
    log "Проверка доступных версий в registry..."

    declare -gA LATEST_VERSIONS
    declare -gA UPDATE_AVAILABLE

    for repo in "${!CURRENT_IMAGES[@]}"; do
        current_tag="${CURRENT_IMAGES[$repo]}"
        log "Проверка $repo:$current_tag..."

        # Определение registry и метода проверки
        if [[ $repo =~ ^ghcr\.io/ ]]; then
            # GitHub Container Registry
            check_ghcr_version "$repo" "$current_tag"
        elif [[ $repo =~ ^quay\.io/ ]]; then
            # Quay.io Registry
            check_quay_version "$repo" "$current_tag"
        elif [[ $repo =~ / ]]; then
            # Docker Hub (с namespace)
            check_dockerhub_version "$repo" "$current_tag"
        else
            # Docker Hub (official images)
            check_dockerhub_official_version "$repo" "$current_tag"
        fi
    done
}

# === ПРОВЕРКА GITHUB CONTAINER REGISTRY ===
check_ghcr_version() {
    local repo="$1"
    local current_tag="$2"

    # Извлечение owner/repo из ghcr.io/owner/repo
    local github_repo
    github_repo=$(echo "$repo" | sed 's|ghcr\.io/||')

    # Получение latest release через GitHub API
    local latest_tag
    latest_tag=$(curl -s "https://api.github.com/repos/$github_repo/releases/latest" | jq -r '.tag_name // empty' 2>/dev/null || echo "")

    if [[ -n "$latest_tag" ]]; then
        LATEST_VERSIONS["$repo"]="$latest_tag"
        if [[ "$current_tag" != "$latest_tag" && "$current_tag" != "latest" ]]; then
            UPDATE_AVAILABLE["$repo"]="yes"
        else
            UPDATE_AVAILABLE["$repo"]="no"
        fi
    else
        LATEST_VERSIONS["$repo"]="unknown"
        UPDATE_AVAILABLE["$repo"]="unknown"
        warning "Не удалось получить версию для $repo"
    fi
}

# === ПРОВЕРКА DOCKER HUB ===
check_dockerhub_version() {
    local repo="$1"
    local current_tag="$2"

    # Получение тегов через Docker Hub API
    local api_url="https://registry.hub.docker.com/v2/repositories/$repo/tags/"
    local latest_tag

    # Попытка получить latest tag
    latest_tag=$(curl -s "$api_url" | jq -r '.results[] | select(.name == "latest") | .name' 2>/dev/null || echo "")

    if [[ -n "$latest_tag" ]]; then
        LATEST_VERSIONS["$repo"]="latest"
        if [[ "$current_tag" != "latest" ]]; then
            UPDATE_AVAILABLE["$repo"]="maybe"
        else
            UPDATE_AVAILABLE["$repo"]="no"
        fi
    else
        LATEST_VERSIONS["$repo"]="unknown"
        UPDATE_AVAILABLE["$repo"]="unknown"
        warning "Не удалось получить версию для $repo"
    fi
}

# === ПРОВЕРКА ОФИЦИАЛЬНЫХ ОБРАЗОВ DOCKER HUB ===
check_dockerhub_official_version() {
    local repo="$1"
    local current_tag="$2"

    # Для официальных образов используем library/ prefix
    check_dockerhub_version "library/$repo" "$current_tag"

    # Копируем результат без library/ prefix
    if [[ -n "${LATEST_VERSIONS["library/$repo"]:-}" ]]; then
        LATEST_VERSIONS["$repo"]="${LATEST_VERSIONS["library/$repo"]}"
        UPDATE_AVAILABLE["$repo"]="${UPDATE_AVAILABLE["library/$repo"]}"
        unset LATEST_VERSIONS["library/$repo"]
        unset UPDATE_AVAILABLE["library/$repo"]
    fi
}

# === ПРОВЕРКА QUAY.IO ===
check_quay_version() {
    local repo="$1"
    local current_tag="$2"

    # Quay.io API для получения тегов
    local quay_repo
    quay_repo=$(echo "$repo" | sed 's|quay\.io/||')

    local api_url="https://quay.io/api/v1/repository/$quay_repo/tag/"
    local latest_tag

    latest_tag=$(curl -s "$api_url" | jq -r '.tags[] | select(.name == "latest") | .name' 2>/dev/null || echo "")

    if [[ -n "$latest_tag" ]]; then
        LATEST_VERSIONS["$repo"]="latest"
        if [[ "$current_tag" != "latest" ]]; then
            UPDATE_AVAILABLE["$repo"]="maybe"
        else
            UPDATE_AVAILABLE["$repo"]="no"
        fi
    else
        LATEST_VERSIONS["$repo"]="unknown"
        UPDATE_AVAILABLE["$repo"]="unknown"
        warning "Не удалось получить версию для $repo"
    fi
}

# === АНАЛИЗ КРИТИЧНОСТИ ОБНОВЛЕНИЙ ===
analyze_update_criticality() {
    log "Анализ критичности обновлений..."

    declare -gA UPDATE_PRIORITY
    declare -gA UPDATE_RISK
    declare -gA SECURITY_UPDATES

    for repo in "${!CURRENT_IMAGES[@]}"; do
        current_tag="${CURRENT_IMAGES[$repo]}"
        latest_tag="${LATEST_VERSIONS[$repo]:-unknown}"

        # Определение приоритета обновления
        case "$repo" in
            *postgres*|*postgresql*)
                UPDATE_PRIORITY["$repo"]="HIGH"
                UPDATE_RISK["$repo"]="MEDIUM"
                ;;
            *nginx*)
                UPDATE_PRIORITY["$repo"]="HIGH"
                UPDATE_RISK["$repo"]="LOW"
                ;;
            *ollama*)
                UPDATE_PRIORITY["$repo"]="HIGH"
                UPDATE_RISK["$repo"]="MEDIUM"
                ;;
            *open-webui*)
                UPDATE_PRIORITY["$repo"]="HIGH"
                UPDATE_RISK["$repo"]="MEDIUM"
                ;;
            *prometheus*)
                UPDATE_PRIORITY["$repo"]="MEDIUM"
                UPDATE_RISK["$repo"]="LOW"
                ;;
            *grafana*)
                UPDATE_PRIORITY["$repo"]="MEDIUM"
                UPDATE_RISK["$repo"]="LOW"
                ;;
            *redis*|*valkey*)
                UPDATE_PRIORITY["$repo"]="MEDIUM"
                UPDATE_RISK["$repo"]="MEDIUM"
                ;;
            *)
                UPDATE_PRIORITY["$repo"]="LOW"
                UPDATE_RISK["$repo"]="LOW"
                ;;
        esac

        # Проверка на security обновления (упрощенная логика)
        if [[ "$current_tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ "$latest_tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            # Сравнение версий для определения типа обновления
            local current_major current_minor current_patch
            local latest_major latest_minor latest_patch

            IFS='.' read -r current_major current_minor current_patch <<< "$current_tag"
            IFS='.' read -r latest_major latest_minor latest_patch <<< "$latest_tag"

            if [[ $latest_major -gt $current_major ]]; then
                UPDATE_PRIORITY["$repo"]="MAJOR"
            elif [[ $latest_minor -gt $current_minor ]]; then
                UPDATE_PRIORITY["$repo"]="MINOR"
            elif [[ $latest_patch -gt $current_patch ]]; then
                UPDATE_PRIORITY["$repo"]="PATCH"
                SECURITY_UPDATES["$repo"]="possible"
            fi
        fi
    done
}

# === ГЕНЕРАЦИЯ ОТЧЕТА ===
generate_report() {
    log "Генерация отчета обновлений..."

    cat > "$REPORT_FILE" << EOF
# ERNI-KI Container Updates Report

**Дата:** $(date)
**Система:** ERNI-KI
**Анализ:** $(whoami)

## 📊 Сводка обновлений

$(generate_summary_table)

## 📋 Детальный анализ

$(generate_detailed_analysis)

## 🚀 Рекомендуемый план обновления

$(generate_update_plan)

## ⚠️ Риски и предупреждения

$(generate_risk_analysis)

## 🔧 Команды для обновления

$(generate_update_commands)

## 🧪 Процедуры тестирования

$(generate_testing_procedures)

---
*Отчет сгенерирован автоматически скриптом check-container-updates.sh*
EOF

    success "Отчет сохранен: $REPORT_FILE"
}

# === ГЕНЕРАЦИЯ ТАБЛИЦЫ СВОДКИ ===
generate_summary_table() {
    echo "| Сервис | Текущая версия | Доступная версия | Обновление | Приоритет | Риск |"
    echo "|--------|----------------|------------------|------------|-----------|------|"

    for repo in "${!CURRENT_IMAGES[@]}"; do
        current_tag="${CURRENT_IMAGES[$repo]}"
        latest_tag="${LATEST_VERSIONS[$repo]:-unknown}"
        update_available="${UPDATE_AVAILABLE[$repo]:-unknown}"
        priority="${UPDATE_PRIORITY[$repo]:-LOW}"
        risk="${UPDATE_RISK[$repo]:-LOW}"

        # Определение статуса обновления
        local status_icon
        case "$update_available" in
            "yes") status_icon="🔄" ;;
            "no") status_icon="✅" ;;
            "maybe") status_icon="❓" ;;
            *) status_icon="❌" ;;
        esac

        echo "| $repo | $current_tag | $latest_tag | $status_icon $update_available | $priority | $risk |"
    done
}

# === ГЕНЕРАЦИЯ ДЕТАЛЬНОГО АНАЛИЗА ===
generate_detailed_analysis() {
    for repo in "${!CURRENT_IMAGES[@]}"; do
        current_tag="${CURRENT_IMAGES[$repo]}"
        latest_tag="${LATEST_VERSIONS[$repo]:-unknown}"
        update_available="${UPDATE_AVAILABLE[$repo]:-unknown}"
        priority="${UPDATE_PRIORITY[$repo]:-LOW}"
        risk="${UPDATE_RISK[$repo]:-LOW}"

        echo "### $repo"
        echo ""
        echo "**Текущая версия:** $current_tag  "
        echo "**Доступная версия:** $latest_tag  "
        echo "**Приоритет обновления:** $priority  "
        echo "**Риск обновления:** $risk  "

        if [[ "${SECURITY_UPDATES[$repo]:-}" == "possible" ]]; then
            echo "**⚠️ Возможные security обновления**"
        fi

        # Специфичные рекомендации для каждого сервиса
        case "$repo" in
            *ollama*)
                echo ""
                echo "**Рекомендации:**"
                echo "- Ollama активно развивается, рекомендуется обновление"
                echo "- Проверьте совместимость с текущими моделями"
                echo "- Сделайте backup моделей перед обновлением"
                ;;
            *open-webui*)
                echo ""
                echo "**Рекомендации:**"
                echo "- OpenWebUI часто выпускает обновления с новыми функциями"
                echo "- Проверьте changelog на breaking changes"
                echo "- Сделайте backup базы данных"
                ;;
            *postgres*|*postgresql*)
                echo ""
                echo "**Рекомендации:**"
                echo "- Критически важный сервис, требует осторожного обновления"
                echo "- Обязательно сделайте полный backup базы данных"
                echo "- Тестируйте на staging окружении"
                ;;
            *nginx*)
                echo ""
                echo "**Рекомендации:**"
                echo "- Обычно безопасное обновление"
                echo "- Проверьте конфигурацию после обновления"
                echo "- Мониторьте производительность"
                ;;
        esac

        echo ""
    done
}

# === ГЕНЕРАЦИЯ ПЛАНА ОБНОВЛЕНИЯ ===
generate_update_plan() {
    echo "### Фаза 1: Подготовка (0 downtime)"
    echo ""
    echo "1. **Создание backup всех критических данных**"
    echo "   \`\`\`bash"
    echo "   # Backup PostgreSQL"
    echo "   docker-compose exec db pg_dump -U postgres openwebui > backup-$(date +%Y%m%d).sql"
    echo "   "
    echo "   # Backup Ollama моделей"
    echo "   docker-compose exec ollama ollama list > models-backup-$(date +%Y%m%d).txt"
    echo "   "
    echo "   # Backup конфигураций"
    echo "   tar -czf config-backup-$(date +%Y%m%d).tar.gz env/ conf/"
    echo "   \`\`\`"
    echo ""
    echo "2. **Проверка доступности новых образов**"
    echo "   \`\`\`bash"

    for repo in "${!CURRENT_IMAGES[@]}"; do
        latest_tag="${LATEST_VERSIONS[$repo]:-unknown}"
        if [[ "$latest_tag" != "unknown" && "${UPDATE_AVAILABLE[$repo]}" == "yes" ]]; then
            echo "   docker pull $repo:$latest_tag"
        fi
    done

    echo "   \`\`\`"
    echo ""
    echo "### Фаза 2: Обновление низкорискованных сервисов (< 30 сек downtime)"
    echo ""

    # Сортировка по приоритету и риску
    local low_risk_services=()
    for repo in "${!CURRENT_IMAGES[@]}"; do
        if [[ "${UPDATE_RISK[$repo]:-LOW}" == "LOW" && "${UPDATE_AVAILABLE[$repo]}" == "yes" ]]; then
            low_risk_services+=("$repo")
        fi
    done

    if [[ ${#low_risk_services[@]} -gt 0 ]]; then
        echo "**Низкорискованные сервисы:**"
        for service in "${low_risk_services[@]}"; do
            echo "- $service"
        done
        echo ""
        echo "\`\`\`bash"
        for service in "${low_risk_services[@]}"; do
            latest_tag="${LATEST_VERSIONS[$service]:-unknown}"
            echo "docker-compose stop ${service##*/}"
            echo "docker-compose up -d ${service##*/}"
            echo "sleep 10  # Ожидание запуска"
            echo ""
        done
        echo "\`\`\`"
    fi

    echo ""
    echo "### Фаза 3: Обновление критических сервисов (< 2 мин downtime)"
    echo ""

    local high_risk_services=()
    for repo in "${!CURRENT_IMAGES[@]}"; do
        if [[ "${UPDATE_RISK[$repo]:-LOW}" != "LOW" && "${UPDATE_AVAILABLE[$repo]}" == "yes" ]]; then
            high_risk_services+=("$repo")
        fi
    done

    if [[ ${#high_risk_services[@]} -gt 0 ]]; then
        echo "**Критические сервисы (по одному):**"
        for service in "${high_risk_services[@]}"; do
            echo "- $service"
        done
        echo ""
        echo "\`\`\`bash"
        echo "# Обновление по одному сервису с проверкой"
        for service in "${high_risk_services[@]}"; do
            echo "echo 'Обновление $service...'"
            echo "docker-compose stop ${service##*/}"
            echo "docker-compose up -d ${service##*/}"
            echo "sleep 30  # Ожидание полного запуска"
            echo "docker-compose ps ${service##*/}  # Проверка статуса"
            echo "# Проверьте работоспособность перед продолжением"
            echo ""
        done
        echo "\`\`\`"
    fi
}

# === ГЕНЕРАЦИЯ АНАЛИЗА РИСКОВ ===
generate_risk_analysis() {
    echo "### 🔴 Высокорискованные обновления"
    echo ""

    local high_risk_found=false
    for repo in "${!CURRENT_IMAGES[@]}"; do
        if [[ "${UPDATE_RISK[$repo]:-LOW}" == "HIGH" ]]; then
            high_risk_found=true
            echo "**$repo**"
            echo "- Может потребовать изменения конфигурации"
            echo "- Возможны breaking changes в API"
            echo "- Рекомендуется тестирование на staging"
            echo ""
        fi
    done

    if [[ "$high_risk_found" == false ]]; then
        echo "Высокорискованных обновлений не обнаружено."
        echo ""
    fi

    echo "### ⚠️ Общие предупреждения"
    echo ""
    echo "- **Всегда делайте backup перед обновлением**"
    echo "- **Тестируйте обновления на staging окружении**"
    echo "- **Мониторьте логи после обновления**"
    echo "- **Имейте план отката**"
    echo "- **Обновляйте по одному сервису за раз**"
    echo ""

    echo "### 🔄 План отката"
    echo ""
    echo "\`\`\`bash"
    echo "# В случае проблем - откат к предыдущим версиям"
    echo "docker-compose down"
    echo "# Восстановите предыдущие образы в compose.yml"
    echo "docker-compose up -d"
    echo ""
    echo "# Восстановление базы данных (если нужно)"
    echo "# docker-compose exec db psql -U postgres openwebui < backup-YYYYMMDD.sql"
    echo "\`\`\`"
}

# === ГЕНЕРАЦИЯ КОМАНД ОБНОВЛЕНИЯ ===
generate_update_commands() {
    echo "### 🚀 Автоматизированное обновление"
    echo ""
    echo "\`\`\`bash"
    echo "#!/bin/bash"
    echo "# Скрипт автоматического обновления ERNI-KI контейнеров"
    echo ""
    echo "set -euo pipefail"
    echo ""
    echo "# Создание backup"
    echo "echo 'Создание backup...'"
    echo "mkdir -p .backups/$(date +%Y%m%d_%H%M%S)"
    echo "docker-compose exec db pg_dump -U postgres openwebui > .backups/$(date +%Y%m%d_%H%M%S)/db-backup.sql"
    echo ""
    echo "# Обновление образов"
    echo "echo 'Загрузка новых образов...'"

    for repo in "${!CURRENT_IMAGES[@]}"; do
        latest_tag="${LATEST_VERSIONS[$repo]:-unknown}"
        if [[ "$latest_tag" != "unknown" && "${UPDATE_AVAILABLE[$repo]}" == "yes" ]]; then
            echo "docker pull $repo:$latest_tag"
        fi
    done

    echo ""
    echo "# Обновление compose файла"
    echo "echo 'Обновление compose.yml...'"
    echo "cp compose.yml compose.yml.backup"
    echo ""

    # Генерация sed команд для обновления compose файла
    for repo in "${!CURRENT_IMAGES[@]}"; do
        current_tag="${CURRENT_IMAGES[$repo]}"
        latest_tag="${LATEST_VERSIONS[$repo]:-unknown}"
        if [[ "$latest_tag" != "unknown" && "${UPDATE_AVAILABLE[$repo]}" == "yes" ]]; then
            echo "sed -i 's|$repo:$current_tag|$repo:$latest_tag|g' compose.yml"
        fi
    done

    echo ""
    echo "# Перезапуск сервисов"
    echo "echo 'Перезапуск сервисов...'"
    echo "docker-compose down"
    echo "docker-compose up -d"
    echo ""
    echo "# Проверка статуса"
    echo "echo 'Проверка статуса сервисов...'"
    echo "sleep 30"
    echo "docker-compose ps"
    echo ""
    echo "echo 'Обновление завершено!'"
    echo "\`\`\`"
    echo ""
    echo "### 🎯 Выборочное обновление"
    echo ""
    echo "\`\`\`bash"
    echo "# Обновление только конкретного сервиса"
    echo "SERVICE_NAME=openwebui  # Замените на нужный сервис"
    echo "docker-compose stop \$SERVICE_NAME"
    echo "docker-compose pull \$SERVICE_NAME"
    echo "docker-compose up -d \$SERVICE_NAME"
    echo "docker-compose logs -f \$SERVICE_NAME"
    echo "\`\`\`"
}

# === ГЕНЕРАЦИЯ ПРОЦЕДУР ТЕСТИРОВАНИЯ ===
generate_testing_procedures() {
    echo "### ✅ Проверка работоспособности после обновления"
    echo ""
    echo "\`\`\`bash"
    echo "#!/bin/bash"
    echo "# Скрипт проверки работоспособности ERNI-KI после обновления"
    echo ""
    echo "echo '=== Проверка статуса контейнеров ==='"
    echo "docker-compose ps"
    echo ""
    echo "echo '=== Проверка логов на ошибки ==='"
    echo "docker-compose logs --tail=50 | grep -i error || echo 'Ошибок не найдено'"
    echo ""
    echo "echo '=== Проверка доступности сервисов ==='"
    echo "# OpenWebUI"
    echo "curl -f http://localhost:8080/health || echo 'OpenWebUI недоступен'"
    echo ""
    echo "# Ollama"
    echo "curl -f http://localhost:11434/api/tags || echo 'Ollama недоступен'"
    echo ""
    echo "# PostgreSQL"
    echo "docker-compose exec db pg_isready -U postgres || echo 'PostgreSQL недоступен'"
    echo ""
    echo "echo '=== Проверка дискового пространства ==='"
    echo "df -h"
    echo ""
    echo "echo '=== Проверка использования памяти ==='"
    echo "docker stats --no-stream"
    echo ""
    echo "echo 'Проверка завершена!'"
    echo "\`\`\`"
    echo ""
    echo "### 🔍 Мониторинг после обновления"
    echo ""
    echo "**Что мониторить в первые 24 часа:**"
    echo ""
    echo "1. **Логи сервисов**"
    echo "   \`\`\`bash"
    echo "   docker-compose logs -f --tail=100"
    echo "   \`\`\`"
    echo ""
    echo "2. **Производительность**"
    echo "   \`\`\`bash"
    echo "   docker stats"
    echo "   \`\`\`"
    echo ""
    echo "3. **Доступность через браузер**"
    echo "   - OpenWebUI: http://localhost:8080"
    echo "   - Grafana: http://localhost:3000"
    echo "   - Prometheus: http://localhost:9090"
    echo ""
    echo "4. **Функциональность RAG**"
    echo "   - Тестирование поиска документов"
    echo "   - Проверка генерации ответов"
    echo "   - Валидация интеграций (SearXNG, Ollama)"
}

# === ОСНОВНАЯ ФУНКЦИЯ ===
main() {
    echo "🔍 Проверка обновлений Docker контейнеров ERNI-KI"
    echo "================================================="

    check_prerequisites
    get_current_versions
    check_available_versions
    analyze_update_criticality
    generate_report

    echo ""
    success "✅ Анализ обновлений завершен!"
    echo "📄 Отчет: $REPORT_FILE"
    echo ""
    echo "📋 Краткая сводка:"

    local total_images=${#CURRENT_IMAGES[@]}
    local updates_available=0
    local high_priority=0

    for repo in "${!UPDATE_AVAILABLE[@]}"; do
        if [[ "${UPDATE_AVAILABLE[$repo]}" == "yes" ]]; then
            ((updates_available++))
        fi
        if [[ "${UPDATE_PRIORITY[$repo]}" == "HIGH" ]]; then
            ((high_priority++))
        fi
    done

    echo "- Всего образов: $total_images"
    echo "- Доступно обновлений: $updates_available"
    echo "- Высокий приоритет: $high_priority"
}

# === ЗАПУСК ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
