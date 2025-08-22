#!/bin/bash
# Elasticsearch Password Setup Script for ERNI-KI
# Version: 1.0 - Simplified approach
# Updated: 2025-08-14

set -e

echo "🔐 НАСТРОЙКА ПАРОЛЕЙ ELASTICSEARCH"
echo "================================="
echo ""

# Загрузка переменных окружения
if [ -f "env/elasticsearch-security.env" ]; then
    source env/elasticsearch-security.env
    echo "✅ Переменные окружения загружены"
    echo "   ELASTIC_PASSWORD: ${ELASTIC_PASSWORD:0:5}..."
    echo "   FLUENT_PASSWORD: ${FLUENT_PASSWORD:0:5}..."
else
    echo "❌ Файл env/elasticsearch-security.env не найден!"
    exit 1
fi

echo ""
echo "🔧 Настройка паролей через elasticsearch-setup-passwords..."

# Использование auto режима для автоматической установки паролей
echo "y" | docker exec -i erni-ki-elasticsearch /usr/share/elasticsearch/bin/elasticsearch-setup-passwords auto > /tmp/es-passwords.txt 2>&1

if [ $? -eq 0 ]; then
    echo "✅ Пароли установлены автоматически"
    echo ""
    echo "📋 Сгенерированные пароли:"
    cat /tmp/es-passwords.txt | grep -E "(elastic|kibana|logstash_system)" || echo "Пароли сохранены в /tmp/es-passwords.txt"
    
    # Извлечение пароля elastic пользователя
    GENERATED_ELASTIC_PASSWORD=$(cat /tmp/es-passwords.txt | grep "PASSWORD elastic" | awk '{print $4}')
    
    if [ ! -z "$GENERATED_ELASTIC_PASSWORD" ]; then
        echo ""
        echo "🔑 Обновление env файла с сгенерированным паролем elastic:"
        sed -i "s/ELASTIC_PASSWORD=.*/ELASTIC_PASSWORD=$GENERATED_ELASTIC_PASSWORD/" env/elasticsearch-security.env
        echo "✅ Пароль elastic обновлен в env файле"
        
        # Обновление переменной для дальнейшего использования
        ELASTIC_PASSWORD=$GENERATED_ELASTIC_PASSWORD
    fi
else
    echo "⚠️ Автоматическая установка не удалась, пробуем интерактивный режим..."
    
    # Интерактивная установка с предустановленными паролями
    docker exec -i erni-ki-elasticsearch /usr/share/elasticsearch/bin/elasticsearch-setup-passwords interactive <<EOF
y
$ELASTIC_PASSWORD
$ELASTIC_PASSWORD
$FLUENT_PASSWORD
$FLUENT_PASSWORD
$FLUENT_PASSWORD
$FLUENT_PASSWORD
$FLUENT_PASSWORD
$FLUENT_PASSWORD
$FLUENT_PASSWORD
$FLUENT_PASSWORD
$FLUENT_PASSWORD
$FLUENT_PASSWORD
EOF
    
    if [ $? -eq 0 ]; then
        echo "✅ Пароли установлены интерактивно"
    else
        echo "❌ Ошибка установки паролей"
        exit 1
    fi
fi

echo ""
echo "🔍 Проверка аутентификации..."
AUTH_TEST=$(curl -s -u "elastic:$ELASTIC_PASSWORD" "http://localhost:9200/_xpack/security/_authenticate" 2>/dev/null || echo "failed")

if [[ "$AUTH_TEST" == *"username"* ]]; then
    echo "✅ Аутентификация работает!"
    echo ""
    echo "👤 Создание пользователя fluent-bit..."
    
    # Создание роли для Fluent Bit
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
         }' >/dev/null 2>&1 && echo "✅ Роль fluent-bit-role создана"
    
    # Создание пользователя для Fluent Bit
    curl -X POST "localhost:9200/_security/user/fluent-bit" \
         -u "elastic:$ELASTIC_PASSWORD" \
         -H "Content-Type: application/json" \
         -d "{
           \"password\": \"$FLUENT_PASSWORD\",
           \"roles\": [\"fluent-bit-role\"],
           \"full_name\": \"Fluent Bit Service User\",
           \"email\": \"fluent-bit@erni-ki.local\"
         }" >/dev/null 2>&1 && echo "✅ Пользователь fluent-bit создан"
    
    echo ""
    echo "✅ ELASTICSEARCH SECURITY НАСТРОЕН УСПЕШНО!"
    echo ""
    echo "📋 Информация для подключения:"
    echo "   URL: http://localhost:9200"
    echo "   Admin user: elastic"
    echo "   Admin password: $ELASTIC_PASSWORD"
    echo "   Fluent Bit user: fluent-bit"
    echo "   Fluent Bit password: $FLUENT_PASSWORD"
    echo ""
    echo "🔐 Пароли сохранены в: env/elasticsearch-security.env"
    
    # Очистка временного файла
    rm -f /tmp/es-passwords.txt
    
else
    echo "❌ Аутентификация не работает"
    echo "Ответ: $AUTH_TEST"
    exit 1
fi
