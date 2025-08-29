# ERNI-KI SSL Setup - Быстрый старт

## 🚀 Быстрая установка Let's Encrypt

### 1. Получите Cloudflare API токен
1. Войдите в [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. **My Profile** → **API Tokens** → **Create Token**
3. **Custom token** с правами:
   - `Zone:Zone:Read`
   - `Zone:DNS:Edit`
   - Зона: `erni-gruppe.ch`

### 2. Установите сертификат
```bash
# Установите API токен
export CF_Token="your_cloudflare_api_token_here"

# Запустите установку
./scripts/ssl/setup-letsencrypt.sh
```

### 3. Проверьте результат
```bash
# Тест конфигурации
./scripts/ssl/test-nginx-config.sh

# Проверка сертификата
curl -I https://ki.erni-gruppe.ch/
```

## 📋 Доступные скрипты

| Скрипт | Описание |
|--------|----------|
| `setup-letsencrypt.sh` | Автоматическая установка Let's Encrypt |
| `monitor-certificates.sh` | Мониторинг и обновление сертификатов |
| `test-nginx-config.sh` | Тестирование SSL конфигурации |
| `setup-ssl-monitoring.sh` | Настройка автомониторинга |
| `check-ssl-now.sh` | Быстрая проверка сертификатов |

## 🔧 Команды мониторинга

```bash
# Проверка сертификата
./scripts/ssl/monitor-certificates.sh check

# Принудительное обновление
./scripts/ssl/monitor-certificates.sh renew

# Генерация отчета
./scripts/ssl/monitor-certificates.sh report

# Тест HTTPS доступности
./scripts/ssl/monitor-certificates.sh test
```

## 📊 Статус автомониторинга

```bash
# Статус systemd timer
systemctl --user status erni-ki-ssl-monitor.timer

# Просмотр логов
journalctl --user -u erni-ki-ssl-monitor.service

# Ручной запуск проверки
./scripts/ssl/check-ssl-now.sh
```

## 🆘 Устранение неполадок

### Проблема: Ошибка Cloudflare API
```bash
# Проверьте токен
curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
     -H "Authorization: Bearer $CF_Token"
```

### Проблема: Ошибка nginx
```bash
# Проверьте конфигурацию
docker compose exec nginx nginx -t

# Перезапустите nginx
docker compose restart nginx
```

### Проблема: DNS propagation
```bash
# Проверьте DNS записи
dig TXT _acme-challenge.ki.erni-gruppe.ch

# Подождите 2-5 минут и повторите
```

## 📚 Документация

- **Полное руководство**: [docs/ssl-letsencrypt-setup.md](../docs/ssl-letsencrypt-setup.md)
- **Итоговый отчет**: [docs/ssl-setup-complete.md](../docs/ssl-setup-complete.md)
- **Конфигурация**: [conf/ssl/monitoring.conf](../conf/ssl/monitoring.conf)

## ⚡ Экстренное восстановление

```bash
# Откат к предыдущим сертификатам
BACKUP_DIR=".config-backup/ssl-setup-20250811-134107"
cp "$BACKUP_DIR/nginx.crt" conf/nginx/ssl/
cp "$BACKUP_DIR/nginx.key" conf/nginx/ssl/
docker compose restart nginx
```

## 🎯 Ожидаемые результаты

После успешной установки:
- ✅ Валидный SSL сертификат от Let's Encrypt
- ✅ A+ рейтинг на SSL Labs
- ✅ Автоматическое обновление каждые 60 дней
- ✅ HTTP/2 и TLS 1.3 поддержка
- ✅ Все 25+ сервисов ERNI-KI работают через HTTPS
