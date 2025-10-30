# Port Forwarding Setup для ERNI-KI

**Дата**: 2025-10-27  
**Роутер**: LANCOM (192.168.62.1)  
**Назначение**: Настройка внешнего доступа к ERNI-KI через прямое подключение

---

## ТРЕБУЕМАЯ КОНФИГУРАЦИЯ

### Сетевые параметры

| Параметр              | Значение              |
| --------------------- | --------------------- |
| Внешний IP            | 185.242.201.210       |
| Внутренний IP сервера | 192.168.62.153        |
| Роутер/Шлюз           | 192.168.62.1 (LANCOM) |
| Домен                 | ki.erni-gruppe.ch     |

### Port Forwarding Rules

#### Rule 1: HTTP (порт 80)

```
Name: ERNI-KI-HTTP
Description: ERNI-KI Web Interface HTTP
External Interface: WAN
External IP: 185.242.201.210 (или Any)
External Port: 80
Protocol: TCP
Internal IP: 192.168.62.153
Internal Port: 80
Enabled: Yes
```

#### Rule 2: HTTPS (порт 443)

```
Name: ERNI-KI-HTTPS
Description: ERNI-KI Web Interface HTTPS
External Interface: WAN
External IP: 185.242.201.210 (или Any)
External Port: 443
Protocol: TCP
Internal IP: 192.168.62.153
Internal Port: 443
Enabled: Yes
```

---

## ИНСТРУКЦИЯ ПО НАСТРОЙКЕ LANCOM ROUTER

### Шаг 1: Доступ к WEBconfig

1. Открыть браузер и перейти по адресу: `https://192.168.62.1/`
2. Ввести учетные данные администратора
3. Принять SSL сертификат роутера (если требуется)

### Шаг 2: Навигация к Port Forwarding

**Возможные пути в меню** (зависит от версии LANCOM):

**Вариант A**:

```
Configuration → Firewall/QoS → Port Forwarding
```

**Вариант B**:

```
IPv4 → Firewall → Port Forwarding Rules
```

**Вариант C**:

```
Advanced Settings → NAT → Port Forwarding
```

### Шаг 3: Добавление правил

#### Для HTTP (порт 80):

1. Нажать "Add" или "New Rule"
2. Заполнить поля:
   - **Rule Name**: `ERNI-KI-HTTP`
   - **External Interface**: `WAN` или `Internet`
   - **Protocol**: `TCP`
   - **External Port**: `80`
   - **Internal IP Address**: `192.168.62.153`
   - **Internal Port**: `80`
   - **Enabled**: `Yes` или `On`
3. Нажать "Save" или "Apply"

#### Для HTTPS (порт 443):

1. Нажать "Add" или "New Rule"
2. Заполнить поля:
   - **Rule Name**: `ERNI-KI-HTTPS`
   - **External Interface**: `WAN` или `Internet`
   - **Protocol**: `TCP`
   - **External Port**: `443`
   - **Internal IP Address**: `192.168.62.153`
   - **Internal Port**: `443`
   - **Enabled**: `Yes` или `On`
3. Нажать "Save" или "Apply"

### Шаг 4: Применение изменений

1. Нажать "Apply Changes" или "Save & Activate"
2. Подождать 10-30 секунд для применения правил
3. Проверить статус правил (должны быть Active/Enabled)

### Шаг 5: Проверка Firewall

**Важно**: Убедиться, что firewall роутера НЕ блокирует порты 80/443

1. Перейти в раздел Firewall Rules
2. Проверить, что НЕТ правил, блокирующих:
   - Входящие подключения на порт 80 TCP
   - Входящие подключения на порт 443 TCP
3. Если есть блокирующие правила - создать исключения для IP 192.168.62.153

---

## ПРОВЕРКА НАСТРОЕК

### Тест 1: Проверка с сервера

```bash
# Проверить, что порты слушают на всех интерфейсах
netstat -tlnp | grep -E ":80 |:443 "

# Ожидаемый результат:
# tcp6  0  0 :::80   :::*  LISTEN  <pid>/docker-proxy
# tcp6  0  0 :::443  :::*  LISTEN  <pid>/docker-proxy
```

### Тест 2: Проверка с другого компьютера в локальной сети

```bash
# С компьютера в той же подсети (192.168.62.x)
curl -I -k https://192.168.62.153/

# Ожидаемый результат:
# HTTP/2 200
# server: nginx/1.28.0
```

### Тест 3: Проверка внешнего доступа

```bash
# С компьютера вне локальной сети или через мобильный интернет
curl -I https://ki.erni-gruppe.ch/

# Ожидаемый результат:
# HTTP/2 200
# server: nginx/1.28.0
```

### Тест 4: Проверка портов извне

```bash
# С внешнего компьютера
nc -zv 185.242.201.210 80
nc -zv 185.242.201.210 443

# Ожидаемый результат:
# Connection to 185.242.201.210 80 port [tcp/http] succeeded!
# Connection to 185.242.201.210 443 port [tcp/https] succeeded!
```

---

## TROUBLESHOOTING

### Проблема 1: Connection Refused

**Симптомы**:

```bash
$ nc -zv 185.242.201.210 80
nc: connect to 185.242.201.210 port 80 (tcp) failed: Connection refused
```

**Возможные причины**:

1. Port forwarding не настроен
2. Firewall блокирует порты
3. Nginx не слушает на порту

**Решение**:

1. Проверить правила port forwarding в роутере
2. Проверить firewall rules
3. Проверить статус nginx: `docker ps --filter name=nginx`

### Проблема 2: Connection Timeout

**Симптомы**:

```bash
$ curl -I https://ki.erni-gruppe.ch/
curl: (28) Connection timed out after 30000 milliseconds
```

**Возможные причины**:

1. Firewall блокирует подключения
2. ISP блокирует порты 80/443
3. DNS не резолвится

**Решение**:

1. Проверить firewall на роутере
2. Связаться с ISP для проверки блокировок
3. Проверить DNS: `nslookup ki.erni-gruppe.ch`

### Проблема 3: SSL Certificate Error

**Симптомы**:

```
SSL certificate problem: unable to get local issuer certificate
```

**Возможные причины**:

1. SSL сертификат не валиден для домена
2. Сертификат самоподписанный

**Решение**:

1. Проверить сертификат: `openssl s_client -connect ki.erni-gruppe.ch:443`
2. Обновить сертификат Let's Encrypt (если истёк)
3. Использовать `-k` флаг для curl (только для тестирования)

---

## DNS НАСТРОЙКИ

После настройки port forwarding необходимо настроить DNS.

### Вариант A: Через регистратора домена

1. Войти в панель управления регистратора `erni-gruppe.ch`
2. Перейти в раздел DNS Management
3. Добавить A запись:
   ```
   Type: A
   Name: ki
   Value: 185.242.201.210
   TTL: 3600
   ```
4. Сохранить изменения
5. Подождать 5-60 минут для распространения DNS

### Вариант B: Через Cloudflare (без Tunnel)

1. Добавить домен `erni-gruppe.ch` в Cloudflare
2. Обновить NS записи у регистратора на Cloudflare NS
3. В Cloudflare Dashboard → DNS → Records:
   ```
   Type: A
   Name: ki
   IPv4 address: 185.242.201.210
   Proxy status: DNS only (серое облако)
   TTL: Auto
   ```
4. Сохранить

### Проверка DNS

```bash
# Проверить с публичного DNS
nslookup ki.erni-gruppe.ch 8.8.8.8

# Ожидаемый результат:
# Server:		8.8.8.8
# Address:	8.8.8.8#53
#
# Non-authoritative answer:
# Name:	ki.erni-gruppe.ch
# Address: 185.242.201.210
```

---

## БЕЗОПАСНОСТЬ

### Рекомендации

1. **Ограничить доступ по IP** (если возможно):
   - Разрешить доступ только с IP адресов ERNI офисов
   - Использовать whitelist в firewall роутера

2. **Включить rate limiting**:
   - Ограничить количество подключений с одного IP
   - Защита от DDoS атак

3. **Мониторинг**:
   - Настроить логирование подключений на роутере
   - Регулярно проверять логи на подозрительную активность

4. **Обновления**:
   - Регулярно обновлять firmware роутера LANCOM
   - Обновлять SSL сертификаты

### Альтернатива: VPN

Для повышенной безопасности рассмотреть использование VPN вместо прямого
доступа:

- Настроить VPN сервер на роутере LANCOM
- Пользователи подключаются через VPN
- Доступ к ERNI-KI только через VPN туннель

---

## КОНТАКТЫ

**IT Отдел ERNI**: [ТРЕБУЕТСЯ УТОЧНИТЬ]

**Ответственный за ERNI-KI**: [ТРЕБУЕТСЯ УТОЧНИТЬ]

**Документация LANCOM**: https://www.lancom-systems.com/support/

---

**Автор**: Augment Agent  
**Дата**: 2025-10-27  
**Версия**: 1.0
