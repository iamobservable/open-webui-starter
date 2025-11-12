# 🚀 Быстрый старт: Настройка SSL для ki.erni-gruppe.ch и www.ki.erni-gruppe.ch

## ⚡ Краткая инструкция (5 минут)

### Шаг 1: Получите Cyon API credentials

1. Откройте https://my.cyon.ch
2. Перейдите: **Einstellungen → API**
3. Создайте новый API Token с правами **DNS-Verwaltung**
4. Сохраните Username и API Token

### Шаг 2: Установите переменные окружения

```bash
export CY_Username='ваш_cyon_username' # pragma: allowlist secret
export CY_Password='ваш_cyon_api_token' # pragma: allowlist secret
```

**Пример:**

```bash
export CY_Username='kontakt@erni-gruppe.ch' # pragma: allowlist secret
export CY_Password='abc123def456...' # pragma: allowlist secret
```

### Шаг 3: Запустите скрипт

```bash
cd /home/konstantin/Documents/augment-projects/erni-ki
./scripts/infrastructure/security/setup-ssl-dual-domain.sh
```

### Шаг 4: Перезапустите Cloudflare Tunnel

```bash
docker compose restart cloudflared
```

### Шаг 5: Проверьте работу

```bash
# Проверка сертификата
openssl x509 -in conf/nginx/ssl/nginx-fullchain.crt -noout -text | grep DNS

# Проверка HTTPS
curl -I https://ki.erni-gruppe.ch
curl -I https://www.ki.erni-gruppe.ch

# Проверка сервисов
docker compose ps
```

---

## ✅ Что делает скрипт

1. ✅ Создает backup текущих сертификатов
2. ✅ Получает SSL-сертификат от Let's Encrypt для обоих доменов
3. ✅ Устанавливает сертификат в nginx
4. ✅ Проверяет корректность
5. ✅ Перезагружает nginx
6. ✅ Настраивает автообновление (каждый день в 02:00)
7. ✅ Создает отчет

---

## 📋 Что уже подготовлено

- ✅ Скрипт установки:
  `scripts/infrastructure/security/setup-ssl-dual-domain.sh`
- ✅ Cloudflare Tunnel конфигурация обновлена: `conf/cloudflare/config.yml`
- ✅ Nginx конфигурация обновлена: `conf/nginx/conf.d/default.conf`
- ✅ Backup текущих сертификатов:
  `.config-backup/ssl-cert-renewal-20251111-075048/`

---

## 🔍 Проверка после установки

### Сертификат должен содержать оба домена:

```bash
openssl x509 -in conf/nginx/ssl/nginx-fullchain.crt -noout -text | grep -A 2 "Subject Alternative Name"
```

**Ожидаемый результат:**

```
X509v3 Subject Alternative Name:
    DNS:ki.erni-gruppe.ch, DNS:www.ki.erni-gruppe.ch
```

### HTTPS должен работать без ошибок:

```bash
curl -I https://ki.erni-gruppe.ch
curl -I https://www.ki.erni-gruppe.ch
```

**Ожидаемый результат:** `HTTP/2 200` без SSL ошибок

### Все сервисы должны быть healthy:

```bash
docker compose ps | grep -E "(healthy|Up)"
```

**Ожидаемый результат:** Все 14+ сервисов в статусе `healthy`

---

## 🆘 Если что-то пошло не так

### Восстановление из backup:

```bash
# Найти последний backup
BACKUP_DIR=$(ls -td .config-backup/ssl-* | head -1)
echo "Восстановление из: $BACKUP_DIR"

# Восстановить сертификаты
cp $BACKUP_DIR/nginx-fullchain.crt conf/nginx/ssl/
cp $BACKUP_DIR/nginx.key conf/nginx/ssl/
cp $BACKUP_DIR/nginx.crt conf/nginx/ssl/

# Перезапустить nginx
docker compose restart nginx
```

### Проверка логов:

```bash
# Лог установки
tail -f logs/ssl-dual-domain-setup.log

# Лог nginx
docker compose logs nginx --tail 50

# Лог cloudflared
docker compose logs cloudflared --tail 50
```

---

## 📚 Подробная документация

Полная инструкция:
[docs/ssl-setup-instructions.md](docs/ssl-setup-instructions.md)

---

## 🎯 Критерии успеха

- ✅ SSL-сертификат получен и установлен для обоих доменов
- ✅ ki.erni-gruppe.ch работает по HTTPS
- ✅ www.ki.erni-gruppe.ch работает по HTTPS
- ✅ Cloudflare Tunnel настроен для обоих доменов
- ✅ Все 14+ сервисов ERNI-KI в статусе healthy
- ✅ Автообновление настроено
- ✅ Время простоя < 5 минут

---

**Готовы начать? Выполните Шаг 1!** 🚀
