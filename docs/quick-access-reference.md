# ERNI-KI Quick Access Reference

## 🚀 Основные интерфейсы

| Сервис | URL | Логин | Пароль | Назначение |
|--------|-----|-------|--------|------------|
| **OpenWebUI** | https://diz.zone | diz-admin@proton.me | testpass | AI-интерфейс |
| **Grafana** | http://localhost:3000 | admin | erni-ki-admin-2025 | Мониторинг |
| **Backrest** | http://localhost:9898 | admin | (настроить) | Бэкапы |

## 📊 Мониторинг

| Сервис | URL | Статус | Функция |
|--------|-----|--------|---------|
| Prometheus | http://localhost:9091 | ✅ | Метрики |
| Alertmanager | http://localhost:9093 | ✅ | Алерты |
| Kibana | http://localhost:5601 | ✅ | Логи |
| cAdvisor | http://localhost:8081 | ✅ | Контейнеры |

## 🔧 API и сервисы

| Сервис | URL | Статус | Функция |
|--------|-----|--------|---------|
| LiteLLM | http://localhost:4000 | ✅ | API Gateway |
| Auth Server | http://localhost:9090 | ✅ | Аутентификация |
| Tika | http://localhost:9998 | ✅ | Документы |
| Elasticsearch | http://localhost:9200 | ✅ | Поиск |

## 📈 Exporters

| Exporter | URL | Статус |
|----------|-----|--------|
| Node | http://localhost:9101/metrics | ✅ |
| PostgreSQL | http://localhost:9187/metrics | ✅ |
| Redis | http://localhost:9121/metrics | ✅ |
| NVIDIA GPU | http://localhost:9445/metrics | ✅ |
| Blackbox | http://localhost:9115/metrics | ✅ |

## ⚡ Быстрые команды

```bash
# Проверка всех интерфейсов
./scripts/check-web-interfaces.sh

# Статус системы
docker-compose ps

# Мониторинг
./scripts/monitoring-system-status.sh

# Перезапуск
docker-compose restart [service]
```

## 🔐 Безопасность

⚠️ **Смените пароли по умолчанию!**
- OpenWebUI: testpass → новый пароль
- Grafana: erni-ki-admin-2025 → новый пароль  
- Backrest: установить пароль

---
**Обновлено**: 2025-07-19 | **Статус**: ✅ Все сервисы работают
