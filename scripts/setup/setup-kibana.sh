#!/bin/bash
# ERNI-KI Kibana Setup Script
# Автоматическая настройка Kibana для анализа логов системы ERNI-KI

set -e

KIBANA_URL="http://localhost:5601"
ELASTICSEARCH_URL="http://localhost:9200"
INDEX_PATTERN="erni-ki-*"

echo "🔧 Настройка Kibana для системы ERNI-KI..."

# Проверка доступности Kibana и Elasticsearch
check_services() {
    echo "🔍 Проверка доступности сервисов..."
    
    if ! curl -s "$KIBANA_URL/api/status" >/dev/null; then
        echo "❌ Kibana недоступна по адресу $KIBANA_URL"
        exit 1
    fi
    
    if ! curl -s "$ELASTICSEARCH_URL/_cluster/health" >/dev/null; then
        echo "❌ Elasticsearch недоступен по адресу $ELASTICSEARCH_URL"
        exit 1
    fi
    
    local kibana_status=$(curl -s "$KIBANA_URL/api/status" | jq -r '.status.overall.state')
    local es_status=$(curl -s "$ELASTICSEARCH_URL/_cluster/health" | jq -r '.status')
    
    echo "✅ Kibana статус: $kibana_status"
    echo "✅ Elasticsearch статус: $es_status"
}

# Создание index pattern
create_index_pattern() {
    echo "📋 Создание index pattern '$INDEX_PATTERN'..."
    
    # Проверка существования индексов
    local indices_count=$(curl -s "$ELASTICSEARCH_URL/_cat/indices/$INDEX_PATTERN?h=index" | wc -l)
    if [ "$indices_count" -eq 0 ]; then
        echo "⚠️  Индексы $INDEX_PATTERN не найдены. Убедитесь, что логи поступают в Elasticsearch."
        return 1
    fi
    
    echo "📊 Найдено индексов: $indices_count"
    
    # Создание index pattern через Kibana API
    local response=$(curl -s -X POST "$KIBANA_URL/api/saved_objects/index-pattern/erni-ki-logs" \
        -H "Content-Type: application/json" \
        -H "kbn-xsrf: true" \
        -d '{
            "attributes": {
                "title": "'"$INDEX_PATTERN"'",
                "timeFieldName": "@timestamp",
                "fields": "[{\"name\":\"@timestamp\",\"type\":\"date\",\"searchable\":true,\"aggregatable\":true},{\"name\":\"cluster\",\"type\":\"string\",\"searchable\":true,\"aggregatable\":true},{\"name\":\"container_name\",\"type\":\"string\",\"searchable\":true,\"aggregatable\":true},{\"name\":\"environment\",\"type\":\"string\",\"searchable\":true,\"aggregatable\":true},{\"name\":\"log\",\"type\":\"string\",\"searchable\":true,\"aggregatable\":false},{\"name\":\"log_source\",\"type\":\"string\",\"searchable\":true,\"aggregatable\":true}]"
            }
        }')
    
    if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
        echo "✅ Index pattern создан успешно"
    else
        echo "⚠️  Index pattern возможно уже существует или произошла ошибка"
        echo "Response: $response"
    fi
}

# Создание сохраненных поисков
create_saved_searches() {
    echo "🔍 Создание сохраненных поисков..."
    
    # OpenWebUI Errors
    curl -s -X POST "$KIBANA_URL/api/saved_objects/search/openwebui-errors" \
        -H "Content-Type: application/json" \
        -H "kbn-xsrf: true" \
        -d '{
            "attributes": {
                "title": "OpenWebUI Errors",
                "description": "Ошибки OpenWebUI сервиса",
                "hits": 0,
                "columns": ["@timestamp", "container_name", "log"],
                "sort": [["@timestamp", "desc"]],
                "kibanaSavedObjectMeta": {
                    "searchSourceJSON": "{\"index\":\"erni-ki-logs\",\"query\":{\"match\":{\"container_name\":\"/erni-ki-openwebui-1\"}},\"filter\":[{\"query\":{\"bool\":{\"should\":[{\"wildcard\":{\"log\":\"*error*\"}},{\"wildcard\":{\"log\":\"*ERROR*\"}}]}}}]}"
                }
            }
        }' >/dev/null
    
    # nginx Access Logs
    curl -s -X POST "$KIBANA_URL/api/saved_objects/search/nginx-access-logs" \
        -H "Content-Type: application/json" \
        -H "kbn-xsrf: true" \
        -d '{
            "attributes": {
                "title": "nginx Access Logs",
                "description": "Логи доступа nginx (без ошибок)",
                "hits": 0,
                "columns": ["@timestamp", "container_name", "log"],
                "sort": [["@timestamp", "desc"]],
                "kibanaSavedObjectMeta": {
                    "searchSourceJSON": "{\"index\":\"erni-ki-logs\",\"query\":{\"match\":{\"container_name\":\"/erni-ki-nginx-1\"}},\"filter\":[{\"query\":{\"bool\":{\"must_not\":[{\"wildcard\":{\"log\":\"*error*\"}}]}}}]}"
                }
            }
        }' >/dev/null
    
    # Database Slow Queries
    curl -s -X POST "$KIBANA_URL/api/saved_objects/search/db-slow-queries" \
        -H "Content-Type: application/json" \
        -H "kbn-xsrf: true" \
        -d '{
            "attributes": {
                "title": "Database Slow Queries",
                "description": "Медленные запросы PostgreSQL",
                "hits": 0,
                "columns": ["@timestamp", "container_name", "log"],
                "sort": [["@timestamp", "desc"]],
                "kibanaSavedObjectMeta": {
                    "searchSourceJSON": "{\"index\":\"erni-ki-logs\",\"query\":{\"match\":{\"container_name\":\"/erni-ki-db-1\"}},\"filter\":[{\"query\":{\"wildcard\":{\"log\":\"*duration*\"}}}]}"
                }
            }
        }' >/dev/null
    
    # All Container Errors
    curl -s -X POST "$KIBANA_URL/api/saved_objects/search/all-container-errors" \
        -H "Content-Type: application/json" \
        -H "kbn-xsrf: true" \
        -d '{
            "attributes": {
                "title": "All Container Errors",
                "description": "Все ошибки контейнеров",
                "hits": 0,
                "columns": ["@timestamp", "container_name", "log"],
                "sort": [["@timestamp", "desc"]],
                "kibanaSavedObjectMeta": {
                    "searchSourceJSON": "{\"index\":\"erni-ki-logs\",\"query\":{\"exists\":{\"field\":\"container_name\"}},\"filter\":[{\"query\":{\"bool\":{\"should\":[{\"wildcard\":{\"log\":\"*error*\"}},{\"wildcard\":{\"log\":\"*ERROR*\"}},{\"wildcard\":{\"log\":\"*exception*\"}}]}}}]}"
                }
            }
        }' >/dev/null
    
    echo "✅ Сохраненные поиски созданы"
}

# Проверка данных в индексах
verify_data() {
    echo "📊 Проверка данных в индексах..."
    
    # Общая статистика
    local total_docs=$(curl -s "$ELASTICSEARCH_URL/$INDEX_PATTERN/_count" | jq '.count')
    echo "📄 Всего документов: $total_docs"
    
    # Статистика по контейнерам
    echo "🐳 Статистика по контейнерам:"
    curl -s "$ELASTICSEARCH_URL/$INDEX_PATTERN/_search" \
        -H "Content-Type: application/json" \
        -d '{
            "size": 0,
            "aggs": {
                "containers": {
                    "terms": {
                        "field": "container_name.keyword",
                        "size": 20
                    }
                }
            }
        }' | jq -r '.aggregations.containers.buckets[] | "   🔹 " + .key + ": " + (.doc_count | tostring) + " логов"'
    
    # Проверка метаданных
    echo "🏷️  Проверка метаданных:"
    local sample=$(curl -s "$ELASTICSEARCH_URL/$INDEX_PATTERN/_search?size=1" | jq '.hits.hits[0]._source')
    
    if echo "$sample" | jq -e '.cluster' >/dev/null; then
        echo "   ✅ cluster: $(echo "$sample" | jq -r '.cluster')"
    else
        echo "   ❌ cluster: отсутствует"
    fi
    
    if echo "$sample" | jq -e '.environment' >/dev/null; then
        echo "   ✅ environment: $(echo "$sample" | jq -r '.environment')"
    else
        echo "   ❌ environment: отсутствует"
    fi
    
    if echo "$sample" | jq -e '.log_source' >/dev/null; then
        echo "   ✅ log_source: $(echo "$sample" | jq -r '.log_source')"
    else
        echo "   ❌ log_source: отсутствует"
    fi
}

# Основная функция
main() {
    check_services
    create_index_pattern
    create_saved_searches
    verify_data
    
    echo ""
    echo "🎉 Настройка Kibana завершена!"
    echo ""
    echo "📋 Доступные ресурсы:"
    echo "   🌐 Kibana: $KIBANA_URL"
    echo "   📊 Index Pattern: $INDEX_PATTERN"
    echo "   🔍 Discover: $KIBANA_URL/app/discover"
    echo ""
    echo "🔍 Созданные сохраненные поиски:"
    echo "   • OpenWebUI Errors"
    echo "   • nginx Access Logs"
    echo "   • Database Slow Queries"
    echo "   • All Container Errors"
    echo ""
    echo "📖 Следующие шаги:"
    echo "   1. Откройте Kibana в браузере: $KIBANA_URL"
    echo "   2. Перейдите в Discover для анализа логов"
    echo "   3. Используйте созданные сохраненные поиски"
    echo "   4. Создайте дашборды для визуализации"
}

main "$@"
