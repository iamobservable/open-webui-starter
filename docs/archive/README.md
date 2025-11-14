# ERNI-KI Archive Overview

Архив содержит исторические документы (аудиты, диагностика, инциденты) и
резервные конфигурации. Используйте его для ретроспекции и ссылок в
runbook’ах/отчётах.

## Структура

| Каталог                  | Содержание                                                                                |
| ------------------------ | ----------------------------------------------------------------------------------------- |
| `archive/audits/`        | Compliance и процессные аудиты (документация, best practices, comprehensive audits).      |
| `archive/diagnostics/`   | Полные диагностические отчёты (full server, RAG tests, log analysis).                     |
| `archive/incidents/`     | Postmortem/ремедиации (Phase 1/2, docx fix, системные ремонты).                           |
| `archive/config-backup/` | Конфигурационные слепки и cron мониторинг (update execution/analysis, monitoring report). |

## Быстрый навигатор

- **Аудиты** — см. `archive/audits/README.md`
- **Диагностика** — см. `archive/diagnostics/README.md`
- **Инциденты** — см. `archive/incidents/README.md`

> При ссылках в операционных документах используйте краткие summary из README
> соответствующего раздела, чтобы инженеры быстро понимали выводы.
