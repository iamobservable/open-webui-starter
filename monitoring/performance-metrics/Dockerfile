# Dockerfile для Performance Metrics Exporter ERNI-KI

FROM python:3.11-slim

# Метаданные
LABEL maintainer="ERNI-KI Team"
LABEL description="Performance metrics exporter for ERNI-KI monitoring"
LABEL version="1.0.0"

# Установка системных зависимостей
RUN apt-get update && apt-get install -y \
    curl \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Создание пользователя для безопасности
RUN groupadd -r metrics && useradd -r -g metrics metrics

# Создание рабочей директории
WORKDIR /app

# Копирование requirements.txt
COPY requirements.txt .

# Установка Python зависимостей
RUN pip install --no-cache-dir -r requirements.txt

# Копирование исходного кода
COPY performance-exporter.py .

# Создание директории для логов
RUN mkdir -p /logs && chown metrics:metrics /logs

# Переключение на непривилегированного пользователя
USER metrics

# Открытие порта для метрик
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/metrics || exit 1

# Запуск приложения
CMD ["python", "performance-exporter.py"]
