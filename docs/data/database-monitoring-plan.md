# Database Monitoring Plan

- Используйте PostgreSQL Exporter (`9188`) и LVM metrics.
- Установите alert rules: `PostgreSQLDown`, `PostgreSQLHighConnections`.
- Сравните с `docs/operations/monitoring-guide.md` и `conf/prometheus/alerts.yml`.
