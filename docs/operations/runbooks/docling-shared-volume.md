# Политика доступа и очистки Docling Shared Volume

Shared volume `./data/docling/shared` используется сервисами Docling и OpenWebUI
для обмена файлами, которые проходят OCR/экстракцию. Том может содержать PII,
поэтому требуется формализованный контроль доступа и стратегия хранения.

## 1. Категории данных

| Каталог       | Источник                              | Содержимое                                              | Retention по умолчанию   |
| ------------- | ------------------------------------- | ------------------------------------------------------- | ------------------------ |
| `uploads/`    | OpenWebUI (пользовательские загрузки) | Исходные документы, pdf, изображения.                   | 2 дня                    |
| `processed/`  | Docling pipeline                      | Нормализованные chunk-и, JSON, промежуточные артефакты. | 14 дней                  |
| `exports/`    | Docling/OpenWebUI                     | Готовые ответы, zip, отчёты.                            | 30 дней                  |
| `quarantine/` | Docling                               | Файлы с ошибками/подозрениями на malware/PII.           | 60 дней, ручная проверка |
| `tmp/`        | Обе службы                            | Краткоживущие временные файлы, дампы.                   | 1 день                   |

> Структура создаётся автоматически скриптом
> `scripts/maintenance/docling-shared-cleanup.sh`. Если каталога нет — он будет
> создан с корректными правами.

## 2. RBAC и права на хосте

- Базовый владелец: системный пользователь, под которым запускается docker
  compose (`$USER`).
- Создаём группу `docling-data` (однократно): `sudo groupadd -f docling-data`.
- Назначаем владельца каталога:
  `sudo chgrp -R docling-data ./data/docling/shared`.
- Права на корень и подкаталоги:
  `chmod 770 ./data/docling/shared{,/uploads,/processed,/exports,/quarantine,/tmp}`.
- В группу `docling-data` включаем админов AI-платформы и сервисные аккаунты,
  которые должны читать/писать файлы с хоста.
- Для read-only аудиторов создаём группу `docling-readonly` и выдаём `chmod 750`
  на `exports/`.

Контейнеры Docling/OpenWebUI обращаются к тому же каталогу по UID 1000 (по
умолчанию). При необходимости более строгого разграничения используйте ACL:

```bash
sudo setfacl -m g:docling-readonly:rx ./data/docling/shared/exports
sudo setfacl -m g:docling-data:rwx ./data/docling/shared
```

## 3. Очистка и контроль объёма

Скрипт `scripts/maintenance/docling-shared-cleanup.sh` реализует ретеншн.
Поведение настраивается переменными:

| Переменная                             | Значение по умолчанию   | Назначение                        |
| -------------------------------------- | ----------------------- | --------------------------------- |
| `DOC_SHARED_ROOT`                      | `./data/docling/shared` | Путь до тома                      |
| `DOC_SHARED_INPUT_RETENTION_DAYS`      | 2                       | Срок хранения raw загрузок        |
| `DOC_SHARED_PROCESSED_RETENTION_DAYS`  | 14                      | Срок хранения обработанных данных |
| `DOC_SHARED_EXPORT_RETENTION_DAYS`     | 30                      | Хранение экспортов                |
| `DOC_SHARED_QUARANTINE_RETENTION_DAYS` | 60                      | Карантин                          |
| `DOC_SHARED_TMP_RETENTION_DAYS`        | 1                       | Временные файлы                   |
| `DOC_SHARED_MAX_SIZE_GB`               | 20                      | Софт-лимит для alert-логирования  |

### 3.1 Manual / dry-run

```bash
./scripts/maintenance/docling-shared-cleanup.sh          # dry-run (по умолчанию)
DOC_SHARED_INPUT_RETENTION_DAYS=1 ./scripts/maintenance/docling-shared-cleanup.sh
```

### 3.2 Применение и cron

```bash
./scripts/maintenance/docling-shared-cleanup.sh --apply \
  >> logs/docling-shared-cleanup.log 2>&1
```

Рекомендуемый cron (ежедневно в 02:10):

```cron
10 2 * * * cd /home/konstantin/Documents/augment-projects/erni-ki && \
  ./scripts/maintenance/docling-shared-cleanup.sh --apply >> logs/docling-shared-cleanup.log 2>&1
```

Добавьте мониторинг лога (Fluent Bit → Loki) и алерт, если в выходе появится
`WARNING: shared volume size ... exceeds`.

## 4. Инцидентные процедуры

1. **Обнаружен подозрительный файл** — переместите его в `quarantine/` и
   зафиксируйте в тикете (добавьте дату/автора в имени файла), выполните
   `chmod 640`.
2. **Переполнен том** — запустите скрипт с уменьшенными ретеншн параметрами либо
   удалите вручную после согласования с владельцем данных.
3. **Запрос на восстановление** — данные старше Retention не гарантируются;
   используйте Backrest/Backups, если нужно восстановить удалённый файл.

## 5. Документация

- Основной справочник: `docs/architecture/service-inventory.md` (раздел
  «Политика Docling shared volume»).
- Archon документ `ERNI-KI Минимальное описание проекта` — содержит summary и
  риски.
- Скрипт очистки: `scripts/maintenance/docling-shared-cleanup.sh`.
