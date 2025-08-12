#!/usr/bin/env python3
"""
Ollama Prometheus Exporter
Экспортирует метрики Ollama API в формате Prometheus
"""

import json
import logging
import os
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

import requests

# Настройка логирования
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class OllamaExporter:
    def __init__(self, ollama_url=None):
        self.ollama_url = ollama_url or os.getenv(
            "OLLAMA_URL", "http://localhost:11434"
        )

    def get_metrics(self):
        """Получение метрик от Ollama API"""
        metrics = []

        try:
            # Версия Ollama
            version_resp = requests.get(f"{self.ollama_url}/api/version", timeout=5)
            if version_resp.status_code == 200:
                version_data = version_resp.json()
                metrics.append(
                    f'ollama_info{{version="{version_data.get("version", "unknown")}"}} 1'
                )

            # Список моделей
            tags_resp = requests.get(f"{self.ollama_url}/api/tags", timeout=5)
            if tags_resp.status_code == 200:
                tags_data = tags_resp.json()
                models = tags_data.get("models", [])

                metrics.append(f"ollama_models_total {len(models)}")

                total_size = 0
                for model in models:
                    model_name = model.get("name", "unknown").replace(":", "_")
                    model_size = model.get("size", 0)
                    total_size += model_size

                    metrics.append(
                        f'ollama_model_size_bytes{{model="{model_name}"}} {model_size}'
                    )

                metrics.append(f"ollama_models_total_size_bytes {total_size}")

            # Запущенные процессы
            ps_resp = requests.get(f"{self.ollama_url}/api/ps", timeout=5)
            if ps_resp.status_code == 200:
                ps_data = ps_resp.json()
                models = ps_data.get("models", [])
                metrics.append(f"ollama_running_models {len(models)}")

                for model in models:
                    model_name = model.get("name", "unknown").replace(":", "_")
                    size_vram = model.get("size_vram", 0)
                    metrics.append(
                        f'ollama_model_vram_bytes{{model="{model_name}"}} {size_vram}'
                    )

            # Статус доступности
            metrics.append("ollama_up 1")

        except Exception as e:
            logger.error(f"Ошибка получения метрик: {e}")
            metrics.append("ollama_up 0")

        return "\n".join(metrics) + "\n"


class MetricsHandler(BaseHTTPRequestHandler):
    def __init__(self, exporter, *args, **kwargs):
        self.exporter = exporter
        super().__init__(*args, **kwargs)

    def do_GET(self):
        if self.path == "/metrics":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()

            metrics = self.exporter.get_metrics()
            self.wfile.write(metrics.encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        # Отключаем стандартное логирование HTTP запросов
        pass


def main():
    exporter = OllamaExporter()

    def handler(*args, **kwargs):
        return MetricsHandler(exporter, *args, **kwargs)

    server = HTTPServer(("0.0.0.0", 9778), handler)
    logger.info("Ollama Exporter запущен на порту 9778")
    logger.info("Метрики доступны на http://localhost:9778/metrics")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Остановка Ollama Exporter")
        server.shutdown()


if __name__ == "__main__":
    main()
