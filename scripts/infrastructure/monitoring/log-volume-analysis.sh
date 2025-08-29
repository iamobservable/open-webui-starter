#!/bin/bash
# Анализ объемов логов ERNI-KI

echo "=== АНАЛИЗ ОБЪЕМОВ ЛОГОВ ERNI-KI ==="
echo "Дата: $(date)"
echo

# Размеры логов Docker контейнеров
echo "1. Размеры логов Docker контейнеров:"
docker system df

echo
echo "2. Топ-10 контейнеров по объему логов (за последний час):"
for container in $(docker ps --format "{{.Names}}" | grep erni-ki); do
    lines=$(docker logs --since 1h "$container" 2>&1 | wc -l)
    echo "$container: $lines строк"
done | sort -k2 -nr | head -10

echo
echo "3. Анализ ошибок в логах:"
for container in $(docker ps --format "{{.Names}}" | grep erni-ki | head -5); do
    errors=$(docker logs --since 1h "$container" 2>&1 | grep -i -E "(error|critical|fatal)" | wc -l)
    if [[ $errors -gt 0 ]]; then
        echo "$container: $errors ошибок"
    fi
done
