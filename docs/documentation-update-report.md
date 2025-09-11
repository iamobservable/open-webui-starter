# Отчет об актуализации документации ERNI-KI (2025-09-05)

## Резервное копирование

- Создана копия: `.config-backup/docs-backup-20250905-102817/` (README.md,
  docs/\*)

## Анализ текущего состояния

- Активные сервисы (фрагмент `docker ps`): OpenWebUI, Ollama, LiteLLM, Nginx,
  db, redis, SearXNG, Docling, Tika, EdgeTTS, MCP, Prometheus, Grafana,
  Alertmanager, Loki, Fluent Bit, Blackbox, Node Exporter, cAdvisor,
  PostgreSQL/Redis/Nginx/NVIDIA/Ollama exporters, Webhook Receiver, Cloudflared,
  Watchtower, RAG Exporter.
- Конфиги изучены: `env/*`, `conf/*` (включая Cloudflare, Prometheus, Grafana,
  Alertmanager, Fluent Bit).
- Архитектурные изменения: добавлен RAG Exporter; уточнен путь Prometheus‑метрик
  Fluent Bit (`/api/v1/metrics/prometheus`); добавлены панели Grafana для RAG
  SLA.

## Обновленные файлы

- README.md — обновлены команды (`docker compose`), Monitoring (Fluent Bit + RAG
  Exporter), ссылки.
- docs/installation.md — добавлены эндпоинты Fluent Bit Prometheus и RAG
  Exporter; раздел про RAG SLA и горячую перезагрузку.
- docs/user-guide.md — добавлен раздел о RAG панелях Grafana.
- docs/admin-guide.md — добавлен раздел о RAG SLA Exporter.
- docs/api-reference.md — добавлен раздел «Системные сервисы и метрики» с
  эндпоинтами (Prometheus/Alertmanager/Loki/Fluent Bit/Exporters, RAG Exporter).
- docs/architecture.md — актуализирован обзор; в диаграмму добавлен `RAG_EXP` и
  связь с Prometheus и OpenWebUI.
- docs/de/architecture.md — синхронизация терминологии (Fluent Bit), добавлен
  RAG Exporter и Prometheus‑метрики.
- docs/development.md — создано руководство разработчика.

## Проверка консистентности RU/DE

- Архитектурные разделы согласованы: упоминаются
  Prometheus/Grafana/Alertmanager/Loki/Fluent Bit/Blackbox/Exporters и RAG
  Exporter.
- Терминология: «Fluent Bit», «RAG Exporter», «Prometheus‑метрики» —
  унифицированы.

## Рекомендации

- Расширить DE‑локализацию (installation/user/admin) в следующей итерации.
- Поддерживать актуальность доменных имён Cloudflare в README и installation.
- Вынести дашборд «RAG SLA» в отдельный файл для дальнейшего развития.
