# ERNI-KI Webhook Receiver Dockerfile
FROM python:3.11-slim

# Метаданные
LABEL maintainer="ERNI-KI Team"
LABEL description="Webhook receiver for ERNI-KI monitoring alerts"
LABEL version="1.0.0"

# Рабочая директория
WORKDIR /app

# Установка системных зависимостей
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Копирование requirements
COPY requirements.txt .

# Установка Python зависимостей
RUN pip install --no-cache-dir -r requirements.txt

# Копирование приложения
COPY webhook-receiver.py .
COPY scripts/ ./scripts/

# Создание директорий
RUN mkdir -p /app/logs /app/scripts

# Права доступа
RUN chmod +x webhook-receiver.py
RUN chmod +x scripts/*.sh 2>/dev/null || true

# Пользователь без root прав
RUN useradd -r -s /bin/false webhook && \
    chown -R webhook:webhook /app
USER webhook

# Переменные окружения
ENV WEBHOOK_PORT=9093
ENV PYTHONUNBUFFERED=1
ENV FLASK_ENV=production

# Порт
EXPOSE 9093

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:9093/health || exit 1

# Запуск
CMD ["python", "webhook-receiver.py"]
