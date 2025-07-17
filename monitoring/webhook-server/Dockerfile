# Dockerfile для webhook-сервера ERNI-KI
# Обработка уведомлений от Alertmanager

FROM python:3.11-slim

# Метаданные
LABEL maintainer="ERNI-KI Team"
LABEL description="Webhook server for ERNI-KI monitoring alerts"
LABEL version="1.0.0"

# Установка системных зависимостей
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Создание пользователя для безопасности
RUN groupadd -r webhook && useradd -r -g webhook webhook

# Создание рабочей директории
WORKDIR /app

# Копирование requirements.txt
COPY requirements.txt .

# Установка Python зависимостей
RUN pip install --no-cache-dir -r requirements.txt

# Копирование исходного кода
COPY webhook-server.py .

# Создание директории для логов
RUN mkdir -p /logs && chown webhook:webhook /logs

# Переключение на непривилегированного пользователя
USER webhook

# Открытие порта
EXPOSE 9093

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:9093/health || exit 1

# Запуск приложения
CMD ["python", "webhook-server.py"]
