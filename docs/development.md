# 💻 Руководство разработчика ERNI-KI

> **Версия документа:** 2.0  
> **Дата обновления:** 2025-07-04  
> **Аудитория:** Разработчики

## 🎯 Обзор для разработчиков

ERNI-KI построен на современном технологическом стеке с акцентом на контейнеризацию, безопасность и масштабируемость. Система использует микросервисную архитектуру с четким разделением ответственности.

## 🛠️ Технологический стек

### Backend
- **Go 1.23+** - Auth сервис (JWT аутентификация)
- **Python 3.11+** - Open WebUI, SearXNG, обработка документов
- **PostgreSQL 16** - основная база данных с pgvector для векторного поиска
- **Redis Stack** - кэширование и сессии
- **Nginx** - reverse proxy и балансировщик нагрузки

### AI/ML компоненты
- **Ollama** - локальный сервер языковых моделей
- **CUDA 11.8+** - GPU ускорение для AI вычислений
- **Docling** - AI-powered обработка документов
- **Apache Tika** - извлечение метаданных

### DevOps
- **Docker & Docker Compose** - контейнеризация
- **GitHub Actions** - CI/CD пайплайны
- **Watchtower** - автоматические обновления

## 🏗️ Структура проекта

```
erni-ki/
├── auth/                     # Go JWT сервис
│   ├── main.go              # Основной файл сервиса
│   ├── main_test.go         # Unit тесты
│   ├── Dockerfile           # Docker образ
│   └── go.mod               # Go зависимости
├── conf/                    # Конфигурации сервисов
│   ├── nginx/               # Nginx конфигурация
│   ├── cloudflare/          # Cloudflare туннель
│   ├── backrest/            # Настройки бэкапов
│   └── mcposerver/          # MCP серверы
├── env/                     # Переменные окружения
│   ├── *.env               # Конфигурации сервисов
│   └── *.example           # Примеры конфигураций
├── data/                    # Persistent данные
│   ├── postgres/           # База данных
│   ├── redis/              # Redis данные
│   ├── openwebui/          # OpenWebUI данные
│   └── ollama/             # Модели Ollama
├── docs/                    # Документация
├── tests/                   # TypeScript тесты
├── types/                   # TypeScript типы
├── monitoring/              # Конфигурации мониторинга
├── scripts/                 # Утилиты и скрипты
├── compose.yml              # Docker Compose конфигурация
├── package.json             # Node.js зависимости
├── tsconfig.json            # TypeScript конфигурация
└── README.md                # Основная документация
```

## 🚀 Настройка среды разработки

### Предварительные требования
```bash
# Установка Node.js 20+
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Установка Go 1.23+
wget https://go.dev/dl/go1.23.6.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.23.6.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin

# Установка Docker и Docker Compose
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
```

### Клонирование и настройка
```bash
# Клонирование репозитория
git clone https://github.com/DIZ-admin/erni-ki.git
cd erni-ki

# Установка Node.js зависимостей
npm install

# Установка Go зависимостей для auth сервиса
cd auth
go mod download
go mod tidy
cd ..

# Копирование конфигураций для разработки
cp compose.yml.example compose.yml
for file in env/*.example; do
  cp "$file" "${file%.example}"
done
```

### Настройка переменных для разработки
```bash
# Генерация тестовых ключей
export JWT_SECRET="test-jwt-secret-key-for-development"
export WEBUI_SECRET_KEY="test-webui-secret-key-for-development"

# Обновление env файлов для разработки
sed -i "s/CHANGE_BEFORE_GOING_LIVE/$JWT_SECRET/g" env/auth.env
sed -i "s/89f03e7ae86485051232d47071a15241ae727f705589776321b5a52e14a6fe57/$WEBUI_SECRET_KEY/g" env/openwebui.env
```

## 🧪 Тестирование

### Запуск тестов
```bash
# Все тесты
npm test

# Только unit тесты
npm run test:unit

# Только интеграционные тесты
npm run test:integration

# Тесты с покрытием
npm run test:coverage

# Go тесты для auth сервиса
cd auth
go test -v ./...
go test -race ./...
cd ..
```

### Структура тестов
```
tests/
├── unit/                    # Unit тесты
│   ├── auth.test.ts        # Тесты аутентификации
│   ├── api.test.ts         # Тесты API endpoints
│   └── utils.test.ts       # Тесты утилит
├── integration/             # Интеграционные тесты
│   ├── chat.test.ts        # Тесты чатов
│   ├── search.test.ts      # Тесты поиска
│   └── documents.test.ts   # Тесты документов
└── e2e/                     # End-to-end тесты
    ├── user-flow.test.ts   # Пользовательские сценарии
    └── admin-flow.test.ts  # Административные сценарии
```

### Пример unit теста
```typescript
// tests/unit/auth.test.ts
import { describe, it, expect } from 'vitest';
import { validateJWT } from '../src/utils/auth';

describe('Auth Utils', () => {
  it('should validate correct JWT token', () => {
    const token = 'valid-jwt-token';
    const result = validateJWT(token);
    expect(result.valid).toBe(true);
  });

  it('should reject invalid JWT token', () => {
    const token = 'invalid-token';
    const result = validateJWT(token);
    expect(result.valid).toBe(false);
  });
});
```

## 🔧 Разработка компонентов

### Auth сервис (Go)
```go
// auth/main.go
package main

import (
    "encoding/json"
    "log"
    "net/http"
    "time"
    
    "github.com/golang-jwt/jwt/v5"
    "github.com/gorilla/mux"
)

type AuthRequest struct {
    Email    string `json:"email"`
    Password string `json:"password"`
}

type AuthResponse struct {
    Token string `json:"token"`
    User  User   `json:"user"`
}

func generateJWT(user User) (string, error) {
    claims := jwt.MapClaims{
        "user_id": user.ID,
        "email":   user.Email,
        "exp":     time.Now().Add(time.Hour * 24).Unix(),
    }
    
    token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
    return token.SignedString([]byte(os.Getenv("JWT_SECRET")))
}

func authHandler(w http.ResponseWriter, r *http.Request) {
    var req AuthRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, "Invalid request", http.StatusBadRequest)
        return
    }
    
    // Валидация пользователя
    user, err := validateUser(req.Email, req.Password)
    if err != nil {
        http.Error(w, "Invalid credentials", http.StatusUnauthorized)
        return
    }
    
    // Генерация JWT
    token, err := generateJWT(user)
    if err != nil {
        http.Error(w, "Token generation failed", http.StatusInternalServerError)
        return
    }
    
    response := AuthResponse{
        Token: token,
        User:  user,
    }
    
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(response)
}
```

### Nginx конфигурация
```nginx
# conf/nginx/conf.d/default.conf
upstream docsUpstream {
  server openwebui:8080 max_fails=5 fail_timeout=60s weight=1;
  keepalive 32;
  keepalive_requests 100;
  keepalive_timeout 60s;
}

server {
  listen 80;
  server_name localhost;

  # Rate limiting
  limit_req_zone $binary_remote_addr zone=general:10m rate=100r/m;
  limit_req_zone $binary_remote_addr zone=searxng_web:10m rate=10r/m;

  # Основное приложение
  location / {
    limit_req zone=general burst=100 nodelay;
    
    proxy_pass http://docsUpstream;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    
    # WebSocket поддержка
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    
    # Улучшенные таймауты
    proxy_connect_timeout 10s;
    proxy_send_timeout 120s;
    proxy_read_timeout 120s;
  }
}
```

## 🔄 CI/CD Pipeline

### GitHub Actions
```yaml
# .github/workflows/ci.yml
name: CI/CD Pipeline

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Setup Node.js
      uses: actions/setup-node@v4
      with:
        node-version: '20'
        cache: 'npm'
    
    - name: Setup Go
      uses: actions/setup-go@v4
      with:
        go-version: '1.23'
    
    - name: Install dependencies
      run: npm ci
    
    - name: Run TypeScript tests
      run: npm test
    
    - name: Run Go tests
      run: |
        cd auth
        go test -v ./...
    
    - name: Build Docker images
      run: docker compose build
    
    - name: Run integration tests
      run: |
        docker compose up -d
        npm run test:integration
        docker compose down

  security:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Run security audit
      run: |
        npm audit --audit-level high
        docker run --rm -v "$PWD":/app clair-scanner
```

## 📦 Добавление новых сервисов

### Создание нового сервиса
1. **Создайте директорию сервиса**:
```bash
mkdir services/new-service
cd services/new-service
```

2. **Создайте Dockerfile**:
```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

EXPOSE 8000

CMD ["python", "main.py"]
```

3. **Добавьте в compose.yml**:
```yaml
new-service:
  build:
    context: ./services/new-service
  env_file: env/new-service.env
  ports:
    - "8000:8000"
  restart: unless-stopped
  healthcheck:
    test: ["CMD", "curl", "--fail", "http://localhost:8000/health"]
    interval: 30s
    timeout: 5s
    retries: 3
  depends_on:
    - db
    - redis
```

4. **Создайте env файл**:
```bash
# env/new-service.env
SERVICE_PORT=8000
DATABASE_URL=postgresql://openwebui:password@db:5432/openwebui
REDIS_URL=redis://redis:6379
```

## 🔍 Отладка и профилирование

### Отладка Go сервиса
```bash
# Запуск с отладочной информацией
cd auth
go run -race main.go

# Профилирование
go tool pprof http://localhost:9090/debug/pprof/profile
```

### Мониторинг производительности
```bash
# Мониторинг Docker контейнеров
docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# Анализ логов
docker compose logs -f --tail=100 service-name

# Профилирование базы данных
docker compose exec db psql -U openwebui -d openwebui -c "
SELECT query, calls, total_time, mean_time 
FROM pg_stat_statements 
ORDER BY total_time DESC 
LIMIT 10;
"
```

## 📝 Стандарты кодирования

### TypeScript/JavaScript
```typescript
// Используйте строгую типизацию
interface ChatMessage {
  id: string;
  content: string;
  role: 'user' | 'assistant';
  timestamp: Date;
}

// Предпочитайте async/await
async function sendMessage(message: ChatMessage): Promise<Response> {
  try {
    const response = await fetch('/api/v1/messages', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(message)
    });
    return response;
  } catch (error) {
    console.error('Failed to send message:', error);
    throw error;
  }
}
```

### Go
```go
// Используйте четкие имена и обработку ошибок
func ValidateJWT(tokenString string) (*Claims, error) {
    token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
        if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
            return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
        }
        return []byte(os.Getenv("JWT_SECRET")), nil
    })
    
    if err != nil {
        return nil, fmt.Errorf("failed to parse token: %w", err)
    }
    
    if claims, ok := token.Claims.(*Claims); ok && token.Valid {
        return claims, nil
    }
    
    return nil, fmt.Errorf("invalid token")
}
```

## 🤝 Contribution Guidelines

### Процесс разработки
1. **Fork репозитория** и создайте feature branch
2. **Напишите тесты** для новой функциональности
3. **Убедитесь, что все тесты проходят**
4. **Следуйте стандартам кодирования**
5. **Создайте Pull Request** с описанием изменений

### Commit сообщения
```bash
# Используйте conventional commits
feat: добавить поддержку новых языковых моделей
fix: исправить ошибку аутентификации в auth сервисе
docs: обновить API документацию
test: добавить тесты для RAG поиска
refactor: оптимизировать nginx конфигурацию
```

### Code Review
- Все изменения должны пройти code review
- Минимум 2 approvals для критических изменений
- Автоматические проверки CI/CD должны пройти успешно

---

**🚀 Готовы к разработке? Начните с изучения существующего кода и запуска тестов!**
