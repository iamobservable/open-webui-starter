# ERNI-KI Log Audit – 2025-11-14 (Repeat)

## Область и методика

- Репозиторий: `erni-ki`, каталог
  `/home/konstantin/Documents/augment-projects/erni-ki`
- Источники: `logs/`, `logs/nginx`, `.config-backup/logs/`,
  `.config-backup/monitoring/cron.log`, `scripts/infrastructure/logs/`
- Подход: сравнение свежих записей с отчётом от 14.11 (утро), фиксация
  изменений/отсутствия прогресса.

## Ключевые наблюдения

### Critical

1. **Docling cleanup всё ещё требует sudo**
   (`logs/docling-shared-cleanup.log:1`)
   - Cron по-прежнему падает с `Permission denied`; только ручной запуск через
     sudo c 08:26:32 заканчивается успехом.
   - _Новое_: автоматизация (cron/systemd) не обновлена.
   - _Действия_: применить инструкцию из runbook (sudo -E / user docling-maint).

2. **HTTPS через ki.erni-gruppe.ch периодически недоступен**
   (`logs/ssl-monitor.log:1-2`)
   - Предупреждения в 00:24 и 02:00 всё ещё есть; авто-перезапуск Nginx не
     устранил корневую причину.
   - _Действия_: проверить внешние проверки (PRTG, Cloudflare); добавить alert
     на повтор >N раз.

3. **Redis fragmentation не снижается**
   (`logs/redis-fragmentation-watchdog.log`)
   - Новая версия watchdog пишет state, но логи продолжают фиксировать purge
     каждые 5 минут в течение всего дня 13.11-14.11.
   - _Действия_: увеличить `maxmemory`, включить active defrag в конфиге
     контейнера, проверить workload (keys/TTL).

4. **Alertmanager queue: всплеск до 1 226 сообщений**
   (`.config-backup/logs/alertmanager-queue.log`)
   - Авто-ресет в 08:20 восстановил очередь до 0, но flood
     HTTPErrors/HighLatency продолжается.
   - _Действия_: добавить rate limit/WARN уровни на blackbox алерты.

5. **CriticalServiceLogsMissing остаётся активным >24h**
   (`.config-backup/monitoring/cron.log`, `alerts.log`)
   - Health monitor фиксирует десятки тысяч критических записей; remediation не
     проведено.

### High

6. **Docker compose status и Nginx proxy health всё ещё FAIL/WARN**
   (`.config-backup/monitoring/cron.log`)
   - Скрипт проверки контейнеров не может выполнить `docker compose ps`; Nginx
     health не возвращает `ok`.
   - _Действия_: добавить DOCKER_HOST/права для cron пользователя, настроить
     /healthz на прокси.

7. **Alertmanager предупреждения без изменений**
   (`.config-backup/logs/alerts.log`)
   - Состав alert-стека идентичен отчёту 10:00–12:00 13.11
     (FluentBitHighMemoryUsage, HTTPErrors, RedisHTTPErrors).
   - _Действия_: устранить первопричины, иначе queue снова переполнится.

### Medium

8. **Rate-limiting монитор то видит, то не видит логи**
   (`logs/rate-limiting-monitor.log`)
   - После bind mount появились отчёты с `Всего блокировок: 0`, но через 5 минут
     снова «Нет логов nginx».
   - _Действия_: добавить systemd timer либо docker exec, чтобы снабжать монитор
     актуальным access.log без ручных копий.

9. **Ротация логов по-прежнему не измеряет Fluent Bit DB** (`logs/rotation.log`)
   - Прогон 14.11 не вывел размер Fluent Bit DB.
   - _Действия_: зафиксировать путь и добавить метрику в мониторинг.

10. **Rate-limiting state**
    (`scripts/infrastructure/logs/rate-limiting-state.json`)
    - Последний snapshot показывает `total_blocks: 0`; без автоматического
      доступа к логам метрика не репрезентативна.

## Сравнение с прошлым аудитом

- Разрешённых проблем нет: все critical из отчёта 14.11 остались.
- Alertmanager queue теперь auto-restarts, но flood сохраняется.
- Rate-limiting монитор частично ожил благодаря bind mount, но не
  автоматизирован.

## Рекомендации

1. Завершить внедрение sudo/systemd для docling-cleanup + обновить runbook.
2. Настроить внешний мониторинг HTTPS и устранить недоступность домена.
3. Провести Redis/Alertmanager постморем: снять метрики, уменьшить шум, добавить
   auto-scaling.
4. Автоматизировать доступ к nginx access log (systemd timer или docker exec) и
   добавить мониторинг Fluent Bit DB.
