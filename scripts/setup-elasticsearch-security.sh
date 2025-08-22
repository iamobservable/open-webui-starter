#!/bin/bash
# Elasticsearch Security Setup Script for ERNI-KI
# Version: 1.0
# Updated: 2025-08-14
# Скрипт для настройки пользователей и ролей Elasticsearch

set -e

echo "🔒 НАСТРОЙКА ELASTICSEARCH SECURITY"
echo "==================================="
echo ""

# Загрузка переменных окружения
if [ -f "env/elasticsearch-security.env" ]; then
    source env/elasticsearch-security.env
    echo "✅ Переменные окружения загружены"
else
    echo "❌ Файл env/elasticsearch-security.env не найден!"
    exit 1
fi

# Проверка доступности Elasticsearch
echo ""
echo "🔍 Проверка доступности Elasticsearch..."
for i in {1..30}; do
    if curl -s -f http://localhost:9200/_cluster/health >/dev/null 2>&1; then
        echo "✅ Elasticsearch доступен"
        break
    fi
    echo "⏳ Ожидание Elasticsearch... ($i/30)"
    sleep 10
done

# Проверка что security включен
echo ""
echo "🔐 Проверка статуса X-Pack Security..."
SECURITY_STATUS=$(curl -s -u "elastic:$ELASTIC_PASSWORD" http://localhost:9200/_xpack/security/_authenticate 2>/dev/null || echo "disabled")

if [[ "$SECURITY_STATUS" == *"username"* ]]; then
    echo "✅ X-Pack Security уже активен"
else
    echo "⚠️ X-Pack Security не активен, требуется настройка паролей"
    
    # Установка паролей для встроенных пользователей
    echo ""
    echo "🔑 Установка паролей для встроенных пользователей..."
    
    # Установка пароля для elastic пользователя
    docker exec erni-ki-elasticsearch /usr/share/elasticsearch/bin/elasticsearch-setup-passwords interactive <<EOF
y
$ELASTIC_PASSWORD
$ELASTIC_PASSWORD
$ELASTIC_PASSWORD
$ELASTIC_PASSWORD
$ELASTIC_PASSWORD
$ELASTIC_PASSWORD
$ELASTIC_PASSWORD
$ELASTIC_PASSWORD
$ELASTIC_PASSWORD
$ELASTIC_PASSWORD
$ELASTIC_PASSWORD
$ELASTIC_PASSWORD
EOF
    
    echo "✅ Пароли установлены"
fi

# Создание роли для Fluent Bit
echo ""
echo "👤 Создание роли fluent-bit-role..."
curl -X POST "localhost:9200/_security/role/fluent-bit-role" \
     -u "elastic:$ELASTIC_PASSWORD" \
     -H "Content-Type: application/json" \
     -d '{
       "cluster": ["monitor", "manage_index_templates"],
       "indices": [
         {
           "names": ["erni-ki-*", "logstash-*"],
           "privileges": ["create_index", "write", "create", "index", "manage"]
         }
       ]
     }' && echo "" && echo "✅ Роль fluent-bit-role создана"

# Создание пользователя для Fluent Bit
echo ""
echo "👤 Создание пользователя fluent-bit..."
curl -X POST "localhost:9200/_security/user/fluent-bit" \
     -u "elastic:$ELASTIC_PASSWORD" \
     -H "Content-Type: application/json" \
     -d "{
       \"password\": \"$FLUENT_PASSWORD\",
       \"roles\": [\"fluent-bit-role\"],
       \"full_name\": \"Fluent Bit Service User\",
       \"email\": \"fluent-bit@erni-ki.local\"
     }" && echo "" && echo "✅ Пользователь fluent-bit создан"

# Проверка созданных пользователей
echo ""
echo "🔍 Проверка созданных пользователей:"
curl -s -u "elastic:$ELASTIC_PASSWORD" "http://localhost:9200/_security/user" | jq '.[] | {username: .username, roles: .roles}' || echo "jq не установлен, используем curl"

echo ""
echo "✅ Elasticsearch Security настроен успешно!"
echo ""
echo "📋 Информация для подключения:"
echo "   URL: http://localhost:9200"
echo "   Admin user: elastic"
echo "   Admin password: $ELASTIC_PASSWORD"
echo "   Fluent Bit user: fluent-bit"
echo "   Fluent Bit password: $FLUENT_PASSWORD"
echo ""
echo "🔐 Пароли сохранены в: env/elasticsearch-security.env"
