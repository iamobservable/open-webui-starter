#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Performance Metrics Exporter для ERNI-KI
Сбор и экспорт метрик производительности для Prometheus
"""

import os
import sys
import time
import json
import logging
import requests
import psutil
import subprocess
from datetime import datetime
from prometheus_client import start_http_server, Gauge, Counter, Histogram, Info
from logging.handlers import RotatingFileHandler

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        RotatingFileHandler('/logs/performance-exporter.log', maxBytes=10485760, backupCount=5),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger('performance-exporter')

# Конфигурация из переменных окружения
METRICS_PORT = int(os.environ.get('METRICS_PORT', '8000'))
SCRAPE_INTERVAL = int(os.environ.get('SCRAPE_INTERVAL', '15'))
OPENWEBUI_URL = os.environ.get('OPENWEBUI_URL', 'http://openwebui:8080')
OLLAMA_URL = os.environ.get('OLLAMA_URL', 'http://ollama:11434')
SEARXNG_URL = os.environ.get('SEARXNG_URL', 'http://searxng:8080')
NGINX_URL = os.environ.get('NGINX_URL', 'http://nginx:80')
AUTH_URL = os.environ.get('AUTH_URL', 'http://auth:9090')

# Prometheus метрики
# Общие метрики производительности
response_time_histogram = Histogram(
    'erni_ki_response_time_seconds',
    'Response time for ERNI-KI services',
    ['service', 'endpoint', 'method']
)

request_counter = Counter(
    'erni_ki_requests_total',
    'Total requests to ERNI-KI services',
    ['service', 'endpoint', 'method', 'status']
)

# RAG метрики
rag_response_time = Histogram(
    'erni_ki_rag_response_time_seconds',
    'RAG query response time',
    ['query_type', 'source_count']
)

rag_requests_total = Counter(
    'erni_ki_rag_requests_total',
    'Total RAG requests',
    ['status', 'query_type']
)

# OpenWebUI метрики
openwebui_active_sessions = Gauge(
    'erni_ki_openwebui_active_sessions',
    'Number of active OpenWebUI sessions'
)

openwebui_chat_response_time = Histogram(
    'erni_ki_openwebui_chat_response_time_seconds',
    'OpenWebUI chat response time',
    ['model']
)

# Ollama метрики
ollama_model_load_time = Histogram(
    'erni_ki_ollama_model_load_time_seconds',
    'Time to load Ollama models',
    ['model']
)

ollama_generation_time = Histogram(
    'erni_ki_ollama_generation_time_seconds',
    'Ollama text generation time',
    ['model', 'tokens']
)

ollama_active_models = Gauge(
    'erni_ki_ollama_active_models',
    'Number of active Ollama models'
)

# SearXNG метрики
searxng_search_time = Histogram(
    'erni_ki_searxng_search_time_seconds',
    'SearXNG search response time',
    ['engine', 'category']
)

searxng_results_count = Histogram(
    'erni_ki_searxng_results_count',
    'Number of search results returned',
    ['engine', 'category']
)

# GPU метрики
gpu_utilization = Gauge(
    'erni_ki_gpu_utilization_percent',
    'GPU utilization percentage',
    ['gpu_id']
)

gpu_memory_usage = Gauge(
    'erni_ki_gpu_memory_usage_bytes',
    'GPU memory usage in bytes',
    ['gpu_id', 'type']
)

gpu_temperature = Gauge(
    'erni_ki_gpu_temperature_celsius',
    'GPU temperature in Celsius',
    ['gpu_id']
)

# Nginx метрики
nginx_request_rate = Gauge(
    'erni_ki_nginx_request_rate_per_second',
    'Nginx request rate per second'
)

nginx_response_time = Histogram(
    'erni_ki_nginx_response_time_seconds',
    'Nginx response time',
    ['status_code', 'upstream']
)

# Системные метрики
system_cpu_usage = Gauge(
    'erni_ki_system_cpu_usage_percent',
    'System CPU usage percentage'
)

system_memory_usage = Gauge(
    'erni_ki_system_memory_usage_bytes',
    'System memory usage in bytes',
    ['type']
)

system_disk_usage = Gauge(
    'erni_ki_system_disk_usage_bytes',
    'System disk usage in bytes',
    ['mountpoint', 'type']
)

# Информационные метрики
system_info = Info(
    'erni_ki_system_info',
    'System information'
)

# Функции для сбора метрик
def collect_system_metrics():
    """Сбор системных метрик"""
    try:
        # CPU
        cpu_percent = psutil.cpu_percent(interval=1)
        system_cpu_usage.set(cpu_percent)
        
        # Память
        memory = psutil.virtual_memory()
        system_memory_usage.labels(type='total').set(memory.total)
        system_memory_usage.labels(type='used').set(memory.used)
        system_memory_usage.labels(type='available').set(memory.available)
        
        # Диск
        for partition in psutil.disk_partitions():
            try:
                usage = psutil.disk_usage(partition.mountpoint)
                system_disk_usage.labels(mountpoint=partition.mountpoint, type='total').set(usage.total)
                system_disk_usage.labels(mountpoint=partition.mountpoint, type='used').set(usage.used)
                system_disk_usage.labels(mountpoint=partition.mountpoint, type='free').set(usage.free)
            except PermissionError:
                continue
                
        logger.debug("Системные метрики собраны")
        
    except Exception as e:
        logger.error(f"Ошибка сбора системных метрик: {e}")

def collect_gpu_metrics():
    """Сбор метрик GPU"""
    try:
        # Проверка доступности nvidia-smi
        result = subprocess.run(
            ['nvidia-smi', '--query-gpu=index,utilization.gpu,memory.used,memory.total,temperature.gpu', '--format=csv,noheader,nounits'],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode == 0:
            for line in result.stdout.strip().split('\n'):
                if line:
                    parts = line.split(', ')
                    if len(parts) >= 5:
                        gpu_id = parts[0]
                        utilization = float(parts[1])
                        memory_used = float(parts[2]) * 1024 * 1024  # MB to bytes
                        memory_total = float(parts[3]) * 1024 * 1024  # MB to bytes
                        temperature = float(parts[4])
                        
                        gpu_utilization.labels(gpu_id=gpu_id).set(utilization)
                        gpu_memory_usage.labels(gpu_id=gpu_id, type='used').set(memory_used)
                        gpu_memory_usage.labels(gpu_id=gpu_id, type='total').set(memory_total)
                        gpu_temperature.labels(gpu_id=gpu_id).set(temperature)
            
            logger.debug("GPU метрики собраны")
        else:
            logger.warning("nvidia-smi недоступен")
            
    except subprocess.TimeoutExpired:
        logger.error("Таймаут при выполнении nvidia-smi")
    except Exception as e:
        logger.error(f"Ошибка сбора GPU метрик: {e}")

def collect_service_metrics():
    """Сбор метрик сервисов"""
    services = [
        ('openwebui', OPENWEBUI_URL, '/health'),
        ('ollama', OLLAMA_URL, '/api/tags'),
        ('searxng', SEARXNG_URL, '/healthz'),
        ('nginx', NGINX_URL, '/nginx_status'),
        ('auth', AUTH_URL, '/health')
    ]
    
    for service_name, base_url, endpoint in services:
        try:
            start_time = time.time()
            response = requests.get(f"{base_url}{endpoint}", timeout=5)
            response_time = time.time() - start_time
            
            # Метрики времени ответа
            response_time_histogram.labels(
                service=service_name,
                endpoint=endpoint,
                method='GET'
            ).observe(response_time)
            
            # Счетчик запросов
            request_counter.labels(
                service=service_name,
                endpoint=endpoint,
                method='GET',
                status=str(response.status_code)
            ).inc()
            
            logger.debug(f"Метрики {service_name} собраны: {response.status_code}, {response_time:.3f}s")
            
        except requests.RequestException as e:
            logger.error(f"Ошибка сбора метрик {service_name}: {e}")
            
            # Счетчик неудачных запросов
            request_counter.labels(
                service=service_name,
                endpoint=endpoint,
                method='GET',
                status='error'
            ).inc()

def collect_ollama_specific_metrics():
    """Сбор специфичных метрик Ollama"""
    try:
        # Получение списка моделей
        response = requests.get(f"{OLLAMA_URL}/api/tags", timeout=10)
        if response.status_code == 200:
            data = response.json()
            models = data.get('models', [])
            ollama_active_models.set(len(models))
            
            logger.debug(f"Ollama активных моделей: {len(models)}")
        
        # Тестовый запрос для измерения времени генерации
        test_prompt = {"model": "llama2", "prompt": "Hello", "stream": False}
        start_time = time.time()
        
        response = requests.post(
            f"{OLLAMA_URL}/api/generate",
            json=test_prompt,
            timeout=30
        )
        
        if response.status_code == 200:
            generation_time = time.time() - start_time
            data = response.json()
            
            ollama_generation_time.labels(
                model=test_prompt['model'],
                tokens='small'
            ).observe(generation_time)
            
            logger.debug(f"Ollama время генерации: {generation_time:.3f}s")
            
    except requests.RequestException as e:
        logger.error(f"Ошибка сбора метрик Ollama: {e}")
    except Exception as e:
        logger.error(f"Неожиданная ошибка при сборе метрик Ollama: {e}")

def collect_searxng_metrics():
    """Сбор метрик SearXNG"""
    try:
        # Тестовый поиск
        search_params = {
            'q': 'test query',
            'format': 'json',
            'categories': 'general'
        }
        
        start_time = time.time()
        response = requests.get(
            f"{SEARXNG_URL}/search",
            params=search_params,
            timeout=10
        )
        search_time = time.time() - start_time
        
        if response.status_code == 200:
            data = response.json()
            results_count = len(data.get('results', []))
            
            searxng_search_time.labels(
                engine='general',
                category='general'
            ).observe(search_time)
            
            searxng_results_count.labels(
                engine='general',
                category='general'
            ).observe(results_count)
            
            logger.debug(f"SearXNG поиск: {search_time:.3f}s, результатов: {results_count}")
            
    except requests.RequestException as e:
        logger.error(f"Ошибка сбора метрик SearXNG: {e}")

def collect_nginx_metrics():
    """Сбор метрик Nginx"""
    try:
        # Получение статистики Nginx
        response = requests.get(f"{NGINX_URL}/nginx_status", timeout=5)
        if response.status_code == 200:
            # Парсинг статистики nginx
            lines = response.text.strip().split('\n')
            for line in lines:
                if 'requests' in line:
                    # Извлечение количества запросов
                    parts = line.split()
                    if len(parts) >= 3:
                        requests_count = int(parts[2])
                        # Примерный расчет RPS (за последний интервал)
                        nginx_request_rate.set(requests_count / SCRAPE_INTERVAL)
            
            logger.debug("Nginx метрики собраны")
            
    except requests.RequestException as e:
        logger.error(f"Ошибка сбора метрик Nginx: {e}")

def set_system_info():
    """Установка информационных метрик"""
    try:
        import platform
        
        info_data = {
            'hostname': platform.node(),
            'os': platform.system(),
            'os_version': platform.release(),
            'python_version': platform.python_version(),
            'architecture': platform.machine(),
            'processor': platform.processor(),
            'erni_ki_version': '1.0.0'
        }
        
        system_info.info(info_data)
        logger.debug("Системная информация установлена")
        
    except Exception as e:
        logger.error(f"Ошибка установки системной информации: {e}")

def main():
    """Основная функция"""
    logger.info("Запуск Performance Metrics Exporter для ERNI-KI")
    
    # Установка системной информации
    set_system_info()
    
    # Запуск HTTP сервера для метрик
    start_http_server(METRICS_PORT)
    logger.info(f"Metrics server запущен на порту {METRICS_PORT}")
    
    # Основной цикл сбора метрик
    while True:
        try:
            logger.debug("Начало сбора метрик")
            
            # Сбор всех типов метрик
            collect_system_metrics()
            collect_gpu_metrics()
            collect_service_metrics()
            collect_ollama_specific_metrics()
            collect_searxng_metrics()
            collect_nginx_metrics()
            
            logger.debug("Сбор метрик завершен")
            
        except Exception as e:
            logger.error(f"Ошибка в основном цикле: {e}")
        
        # Ожидание до следующего сбора
        time.sleep(SCRAPE_INTERVAL)

if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        logger.info("Получен сигнал прерывания, завершение работы")
    except Exception as e:
        logger.error(f"Критическая ошибка: {e}")
        sys.exit(1)
