#!/bin/bash
# ERNI-KI Elasticsearch Index Retention Management
# Управление retention policy для индексов Elasticsearch

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Конфигурация
ELASTICSEARCH_URL="http://localhost:9200"
INDEX_PREFIX="erni-ki"
RETENTION_DAYS=7
CRITICAL_RETENTION_DAYS=30

echo "🗄️  Управление retention policy Elasticsearch - $(date)"

# Проверка доступности Elasticsearch
check_elasticsearch() {
    if ! curl -s "$ELASTICSEARCH_URL/_cluster/health" >/dev/null; then
        echo "❌ Elasticsearch недоступен по адресу $ELASTICSEARCH_URL"
        exit 1
    fi
    
    local status=$(curl -s "$ELASTICSEARCH_URL/_cluster/health" | jq -r '.status')
    echo "✅ Elasticsearch доступен, статус: $status"
}

# Получение списка индексов
get_indices() {
    curl -s "$ELASTICSEARCH_URL/_cat/indices/${INDEX_PREFIX}-*?h=index,creation.date.string,docs.count,store.size&s=creation.date" | \
    while read index creation_date docs_count store_size; do
        echo "$index|$creation_date|$docs_count|$store_size"
    done
}

# Удаление старых индексов
cleanup_old_indices() {
    local retention_days=$1
    local cutoff_date=$(date -d "$retention_days days ago" +%Y.%m.%d)
    
    echo "🧹 Очистка индексов старше $retention_days дней (до $cutoff_date)..."
    
    local deleted_count=0
    local total_size="0"
    
    get_indices | while IFS='|' read index creation_date docs_count store_size; do
        # Извлечь дату из имени индекса (формат: erni-ki-YYYY.MM.DD)
        local index_date=$(echo "$index" | grep -oE '[0-9]{4}\.[0-9]{2}\.[0-9]{2}$' || echo "")
        
        if [ -n "$index_date" ] && [ "$index_date" \< "$cutoff_date" ]; then
            echo "   🗑️  Удаление индекса: $index ($creation_date, $docs_count docs, $store_size)"
            
            if curl -s -X DELETE "$ELASTICSEARCH_URL/$index" | jq -r '.acknowledged' | grep -q true; then
                echo "      ✅ Удален успешно"
                deleted_count=$((deleted_count + 1))
            else
                echo "      ❌ Ошибка удаления"
            fi
        fi
    done
    
    if [ $deleted_count -eq 0 ]; then
        echo "   ℹ️  Нет индексов для удаления"
    else
        echo "   📊 Удалено индексов: $deleted_count"
    fi
}

# Оптимизация индексов
optimize_indices() {
    echo "⚡ Оптимизация текущих индексов..."
    
    # Форсировать merge для индексов старше 1 дня
    local yesterday=$(date -d "1 day ago" +%Y.%m.%d)
    
    get_indices | while IFS='|' read index creation_date docs_count store_size; do
        local index_date=$(echo "$index" | grep -oE '[0-9]{4}\.[0-9]{2}\.[0-9]{2}$' || echo "")
        
        if [ -n "$index_date" ] && [ "$index_date" \< "$yesterday" ]; then
            echo "   🔧 Оптимизация индекса: $index"
            curl -s -X POST "$ELASTICSEARCH_URL/$index/_forcemerge?max_num_segments=1" >/dev/null || true
        fi
    done
}

# Статистика индексов
show_statistics() {
    echo ""
    echo "📊 Статистика индексов Elasticsearch:"
    echo "   🔗 URL: $ELASTICSEARCH_URL"
    echo "   📅 Retention: $RETENTION_DAYS дней (обычные), $CRITICAL_RETENTION_DAYS дней (критические)"
    echo ""
    
    local total_indices=0
    local total_docs=0
    local total_size_mb=0
    
    echo "   📋 Текущие индексы:"
    get_indices | while IFS='|' read index creation_date docs_count store_size; do
        echo "      📁 $index: $docs_count docs, $store_size ($creation_date)"
        total_indices=$((total_indices + 1))
        total_docs=$((total_docs + docs_count))
    done
    
    # Общая статистика кластера
    local cluster_stats=$(curl -s "$ELASTICSEARCH_URL/_cluster/stats")
    local total_size=$(echo "$cluster_stats" | jq -r '.indices.store.size_in_bytes // 0')
    local total_size_mb=$((total_size / 1024 / 1024))
    
    echo ""
    echo "   📈 Общая статистика:"
    echo "      🗂️  Всего индексов: $(echo "$cluster_stats" | jq -r '.indices.count // 0')"
    echo "      📄 Всего документов: $(echo "$cluster_stats" | jq -r '.indices.docs.count // 0')"
    echo "      💾 Общий размер: ${total_size_mb}MB"
    echo "      🖥️  Узлов в кластере: $(echo "$cluster_stats" | jq -r '.nodes.count.total // 0')"
}

# Основная логика
main() {
    check_elasticsearch
    
    case "${1:-cleanup}" in
        "cleanup")
            cleanup_old_indices $RETENTION_DAYS
            ;;
        "optimize")
            optimize_indices
            ;;
        "stats")
            show_statistics
            ;;
        "full")
            cleanup_old_indices $RETENTION_DAYS
            optimize_indices
            show_statistics
            ;;
        *)
            echo "Использование: $0 [cleanup|optimize|stats|full]"
            echo "  cleanup  - Удалить старые индексы (по умолчанию)"
            echo "  optimize - Оптимизировать индексы"
            echo "  stats    - Показать статистику"
            echo "  full     - Выполнить все операции"
            exit 1
            ;;
    esac
}

main "$@"

echo ""
echo "✅ Управление retention policy завершено - $(date)"
