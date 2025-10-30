# Настройка локального DNS для ERNI-KI системы

**Дата**: 2025-10-27 **Статус**: ✅ ЗАВЕРШЕНО **Цель**: Настроить локальный DNS
сервер для резолвинга ki.erni-gruppe.ch в корпоративной сети

---

## РЕЗЮМЕ

**Проблема**: После изменения IP сервера с 192.168.62.140 на 192.168.62.153,
система ERNI-KI стала недоступна по адресу `ki.erni-gruppe.ch` с других
компьютеров в локальной сети.

**Решение**: Установлен и настроен DNSMasq на сервере ERNI-KI для резолвинга
`ki.erni-gruppe.ch → 192.168.62.153` в локальной сети.

**Результат**:

- ✅ DNS сервер работает на 192.168.62.153:53
- ✅ Резолвинг ki.erni-gruppe.ch → 192.168.62.153 работает
- ✅ Форвардинг других доменов на корпоративные DNS работает
- ✅ HTTPS доступ к системе работает

---

## ЧТО БЫЛО СДЕЛАНО

### 1. Отключен DNS stub listener в systemd-resolved

Создан конфигурационный файл `/etc/systemd/resolved.conf.d/dnsmasq.conf`:

```ini
[Resolve]
# Отключить DNS stub listener (освободить порт 53)
DNSStubListener=no

# Использовать dnsmasq как локальный DNS
DNS=192.168.62.153

# Fallback DNS серверы
FallbackDNS=192.168.62.32 185.242.202.231
```

### 2. Установлен DNSMasq на хост

```bash
sudo apt-get update
sudo apt-get install -y dnsmasq
```

### 3. Настроен DNSMasq

Конфигурация скопирована из `conf/dnsmasq/dnsmasq.conf` в `/etc/dnsmasq.conf`:

**Ключевые настройки**:

- Слушает только на интерфейсе eno1 (192.168.62.153)
- Локальная запись: `ki.erni-gruppe.ch → 192.168.62.153`
- Upstream DNS: 192.168.62.32, 185.242.202.231, 8.8.8.8
- Кэш: 1000 записей
- Логирование запросов включено

### 4. Проверена работа

```bash
# Порт 53 слушает dnsmasq
$ sudo netstat -tulnp | grep :53
tcp  0  0 192.168.62.153:53  0.0.0.0:*  LISTEN  729392/dnsmasq

# DNS резолвинг работает
$ nslookup ki.erni-gruppe.ch 192.168.62.153
Name:	ki.erni-gruppe.ch
Address: 192.168.62.153

# HTTPS доступ работает
$ curl -I https://ki.erni-gruppe.ch/
HTTP/2 200
server: nginx/1.28.0
```

---

## СЛЕДУЮЩИЕ ШАГИ - НАСТРОЙКА КЛИЕНТОВ

**ВАЖНО**: Сейчас DNS сервер работает на 192.168.62.153, но клиенты в сети ещё
не знают о нём. Нужно настроить клиентские компьютеры или DHCP сервер для
использования нового DNS.

### Вариант A: Настроить DHCP на роутере LANCOM (РЕКОМЕНДУЕТСЯ)

**Преимущества**: Автоматическая настройка всех клиентов, централизованное
управление

**Шаги**:

1. Войти в WEBconfig роутера: `https://192.168.62.1/`
2. Найти настройки DHCP сервера
3. Изменить Primary DNS с `192.168.62.32` на `192.168.62.153`
4. Сохранить изменения
5. Клиенты автоматически получат новый DNS при следующем DHCP lease (обычно 24
   часа)

**Для немедленного применения на клиентах**:

- Linux: `sudo dhclient -r && sudo dhclient`
- Windows: `ipconfig /release && ipconfig /renew`
- macOS: Системные настройки → Сеть → Продлить аренду DHCP

### Вариант B: Ручная настройка на клиентских компьютерах

**Преимущества**: Быстрое тестирование, не требует доступа к роутеру

**Linux (NetworkManager)**:

```bash
# Узнать имя подключения
nmcli connection show

# Настроить DNS
sudo nmcli connection modify <connection-name> ipv4.dns "192.168.62.153 192.168.62.32"
sudo nmcli connection up <connection-name>

# Проверить
nslookup ki.erni-gruppe.ch
```

**Windows**:

1. Панель управления → Сеть и Интернет → Сетевые подключения
2. Правой кнопкой на адаптере → Свойства
3. IPv4 → Свойства → Использовать следующие адреса DNS-серверов
4. Предпочитаемый DNS: `192.168.62.153`
5. Альтернативный DNS: `192.168.62.32`
6. OK → OK

**macOS**:

1. Системные настройки → Сеть
2. Выбрать активное подключение → Дополнительно
3. DNS → Добавить `192.168.62.153`
4. Применить

### Вариант C: Настроить корпоративный DNS сервер (192.168.62.32)

**Преимущества**: Профессиональное решение, интеграция с существующей
инфраструктурой

**Требуется**: Доступ к корпоративному DNS серверу (вероятно Windows Server)

**Шаги**:

1. Подключиться к DNS серверу 192.168.62.32
2. Открыть DNS Manager
3. Создать новую зону прямого просмотра для `erni-gruppe.ch` (если не
   существует)
4. Добавить A-запись: `ki.erni-gruppe.ch → 192.168.62.153`
5. Обновить кэш DNS на клиентах: `ipconfig /flushdns` (Windows) или
   `sudo systemd-resolve --flush-caches` (Linux)

---

## ПРОВЕРКА РАБОТЫ НА КЛИЕНТАХ

После настройки DNS на клиентах, проверить доступ:

```bash
# 1. Проверить DNS резолвинг
nslookup ki.erni-gruppe.ch
# Ожидается: Address: 192.168.62.153

# 2. Проверить HTTPS доступ
curl -I https://ki.erni-gruppe.ch/
# Ожидается: HTTP/2 200

# 3. Открыть в браузере
# https://ki.erni-gruppe.ch/
# Ожидается: Интерфейс OpenWebUI
```

---

## ТЕХНИЧЕСКАЯ ДОКУМЕНТАЦИЯ

### Архитектура DNS

```
Клиент в сети 192.168.62.0/24
    ↓
    DNS запрос ki.erni-gruppe.ch
    ↓
DNSMasq на 192.168.62.153:53
    ↓
    Локальная запись: ki.erni-gruppe.ch → 192.168.62.153
    ↓
Nginx на 192.168.62.153:443
    ↓
OpenWebUI
```

### Конфигурация DNSMasq

**Файл**: `/etc/dnsmasq.conf`

**Ключевые параметры**:

```conf
# Интерфейс
interface=eno1
bind-interfaces
except-interface=lo

# Upstream DNS
server=192.168.62.32
server=185.242.202.231
server=8.8.8.8

# Локальная запись
address=/ki.erni-gruppe.ch/192.168.62.153

# Кэш
cache-size=1000
```

### Конфигурация systemd-resolved

**Файл**: `/etc/systemd/resolved.conf.d/dnsmasq.conf`

```ini
[Resolve]
DNSStubListener=no
DNS=192.168.62.153
FallbackDNS=192.168.62.32 185.242.202.231
```

---

## МОНИТОРИНГ И ОБСЛУЖИВАНИЕ

### Проверка статуса DNSMasq

```bash
# Статус сервиса
sudo systemctl status dnsmasq

# Логи
sudo journalctl -u dnsmasq -f

# Статистика запросов
sudo kill -USR1 $(pidof dnsmasq)
sudo journalctl -u dnsmasq | tail -20
```

### Перезапуск после изменений

```bash
# Проверить конфигурацию
sudo dnsmasq --test

# Перезапустить сервис
sudo systemctl restart dnsmasq

# Проверить работу
nslookup ki.erni-gruppe.ch 192.168.62.153
```

### Откат изменений

Если что-то пошло не так:

```bash
# 1. Остановить dnsmasq
sudo systemctl stop dnsmasq
sudo systemctl disable dnsmasq

# 2. Восстановить systemd-resolved
sudo rm /etc/systemd/resolved.conf.d/dnsmasq.conf
sudo systemctl restart systemd-resolved

# 3. Восстановить оригинальную конфигурацию dnsmasq
sudo cp /etc/dnsmasq.conf.backup /etc/dnsmasq.conf
```

---

## ПРИЛОЖЕНИЕ: ПОЛНАЯ ПРОЦЕДУРА НАСТРОЙКИ

Для справки, полная процедура настройки DNSMasq на сервере ERNI-KI:

### Шаг 1: Отключить systemd-resolved DNS stub listener

```bash
# Создать конфигурационный файл
sudo mkdir -p /etc/systemd/resolved.conf.d/
sudo tee /etc/systemd/resolved.conf.d/dnsmasq.conf << 'EOF'
[Resolve]
# Отключить DNS stub listener (освободить порт 53)
DNSStubListener=no

# Использовать dnsmasq как локальный DNS
DNS=192.168.62.153

# Fallback DNS серверы
FallbackDNS=192.168.62.32 185.242.202.231
EOF

# Перезапустить systemd-resolved
sudo systemctl restart systemd-resolved

# Проверить статус
sudo systemctl status systemd-resolved
resolvectl status
```

### Шаг 2: Обновить /etc/resolv.conf

```bash
# Создать новый resolv.conf
sudo rm /etc/resolv.conf
sudo tee /etc/resolv.conf << 'EOF'
# DNS конфигурация для ERNI-KI с локальным DNSMasq
nameserver 192.168.62.153
nameserver 192.168.62.32
nameserver 185.242.202.231
search intern
EOF

# Сделать файл неизменяемым (чтобы systemd не перезаписал)
sudo chattr +i /etc/resolv.conf
```

### Шаг 3: Перезапустить DNSMasq контейнер

```bash
cd /home/konstantin/Documents/augment-projects/erni-ki

# Перезапустить контейнер
docker restart erni-ki-dnsmasq

# Проверить статус
docker ps --filter name=dnsmasq

# Проверить логи
docker logs --tail 20 erni-ki-dnsmasq
```

### Шаг 4: Проверить работу DNS

```bash
# Проверить что порт 53 слушает dnsmasq
sudo netstat -tulnp | grep :53

# Проверить резолвинг ki.erni-gruppe.ch
nslookup ki.erni-gruppe.ch 192.168.62.153

# Проверить резолвинг других доменов
nslookup google.com 192.168.62.153

# Проверить доступ к ERNI-KI
curl -I https://ki.erni-gruppe.ch/
```

---

## ОЖИДАЕМЫЕ РЕЗУЛЬТАТЫ

### Порт 53

```bash
$ sudo netstat -tulnp | grep :53
udp        0      0 192.168.62.153:53       0.0.0.0:*               <pid>/dnsmasq
tcp        0      0 192.168.62.153:53       0.0.0.0:*               <pid>/dnsmasq
```

### DNS резолвинг

```bash
$ nslookup ki.erni-gruppe.ch 192.168.62.153
Server:		192.168.62.153
Address:	192.168.62.153#53

Name:	ki.erni-gruppe.ch
Address: 192.168.62.153
```

### HTTPS доступ

```bash
$ curl -I https://ki.erni-gruppe.ch/
HTTP/2 200
server: nginx/1.28.0
```

---

## ОТКАТ ИЗМЕНЕНИЙ (если что-то пошло не так)

```bash
# Удалить конфигурацию systemd-resolved
sudo rm /etc/systemd/resolved.conf.d/dnsmasq.conf
sudo systemctl restart systemd-resolved

# Восстановить resolv.conf
sudo chattr -i /etc/resolv.conf
sudo rm /etc/resolv.conf
sudo ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# Остановить dnsmasq
docker stop erni-ki-dnsmasq
```

---

## СЛЕДУЮЩИЕ ШАГИ

После успешной настройки DNSMasq на сервере:

### Вариант A: Настроить DHCP на роутере LANCOM (РЕКОМЕНДУЕТСЯ)

1. Войти в WEBconfig роутера: https://192.168.62.1/
2. Изменить Primary DNS с 192.168.62.32 на 192.168.62.153
3. Клиенты автоматически получат новый DNS при следующем DHCP lease

### Вариант B: Ручная настройка на клиентах

**Linux**:

```bash
sudo nmcli connection modify <connection-name> ipv4.dns "192.168.62.153"
sudo nmcli connection up <connection-name>
```

**Windows**:

1. Панель управления → Сеть и Интернет → Сетевые подключения
2. Правой кнопкой на адаптере → Свойства
3. IPv4 → Свойства → Использовать следующие адреса DNS-серверов
4. Предпочитаемый DNS: 192.168.62.153
5. Альтернативный DNS: 192.168.62.32

**macOS**:

1. Системные настройки → Сеть
2. Выбрать активное подключение → Дополнительно
3. DNS → Добавить 192.168.62.153

---

**Автор**: Augment Agent **Дата**: 2025-10-27
