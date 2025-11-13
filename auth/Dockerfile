# Multi-stage Dockerfile для auth сервиса проекта erni-ki
# Оптимизированная сборка с кэшированием зависимостей

# Этап 1: Сборка приложения
FROM golang:1.24.10-alpine3.21 AS builder

# Устанавливаем необходимые пакеты для сборки
RUN apk add --no-cache \
  git \
  ca-certificates \
  tzdata

# Создаем пользователя для безопасности
RUN adduser -D -s /bin/sh -u 1001 appuser

# Устанавливаем рабочую директорию
WORKDIR /build

# Копируем файлы зависимостей для кэширования слоев
COPY go.mod go.sum ./

# Загружаем зависимости (кэшируется при неизменных go.mod/go.sum)
RUN go mod download && go mod verify

# Копируем исходный код
COPY . .

# Запускаем тесты (опционально, можно отключить через build arg)
ARG SKIP_TESTS=false
RUN if [ "$SKIP_TESTS" = "false" ]; then go test -v ./...; fi

# Собираем приложение с оптимизациями
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
  -ldflags='-w -s -extldflags "-static"' \
  -a -installsuffix cgo \
  -o main .

# Этап 2: Финальный образ
FROM gcr.io/distroless/static-debian12:nonroot

# Копируем сертификаты для HTTPS запросов
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Копируем информацию о временных зонах
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo

# Копируем скомпилированное приложение
COPY --from=builder /build/main /app/main

# Distroless образ уже использует непривилегированного пользователя nonroot

# Открываем порт
EXPOSE 9090

# Настраиваем health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["/app/main", "--health-check"]

# Метаданные образа
LABEL maintainer="erni-ki-team" \
  version="1.0.0" \
  description="JWT Authentication service for erni-ki project" \
  org.opencontainers.image.source="https://github.com/DIZ-admin/erni-ki" \
  org.opencontainers.image.documentation="https://github.com/DIZ-admin/erni-ki/blob/main/README.md"

# Запускаем приложение
ENTRYPOINT ["/app/main"]
