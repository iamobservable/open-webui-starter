import logging
import os
import signal
import sys
import threading
import time
from typing import Optional

import requests
from prometheus_client import Gauge, start_http_server

OLLAMA_URL = os.getenv("OLLAMA_URL", "http://ollama:11434").rstrip("/")
EXPORTER_PORT = int(os.getenv("EXPORTER_PORT", "9778"))
POLL_INTERVAL = int(os.getenv("OLLAMA_EXPORTER_INTERVAL", "15"))
REQUEST_TIMEOUT = float(os.getenv("OLLAMA_REQUEST_TIMEOUT", "5"))

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s | %(levelname)s | %(message)s",
)
LOGGER = logging.getLogger("ollama_exporter")

OLLAMA_UP = Gauge("ollama_up", "Ollama health status (1=up, 0=down)")
OLLAMA_VERSION_INFO = Gauge("ollama_version_info", "Current Ollama version", ["version"])
OLLAMA_INSTALLED_MODELS = Gauge("ollama_installed_models", "Number of installed Ollama models")
OLLAMA_REQUEST_LATENCY = Gauge("ollama_request_latency_seconds", "Latency for Ollama version endpoint")

_STOP_EVENT = threading.Event()


def fetch_json(path: str) -> Optional[dict]:
    url = f"{OLLAMA_URL}{path}"
    try:
        start = time.perf_counter()
        response = requests.get(url, timeout=REQUEST_TIMEOUT)
        response.raise_for_status()
        OLLAMA_REQUEST_LATENCY.set(time.perf_counter() - start)
        return response.json()
    except Exception as exc:  # pylint: disable=broad-except
        LOGGER.warning("Request failed for %s: %s", url, exc)
        return None


def poll_forever() -> None:
    LOGGER.info(
        "Starting poller (url=%s, interval=%ss, timeout=%ss)",
        OLLAMA_URL,
        POLL_INTERVAL,
        REQUEST_TIMEOUT,
    )
    while not _STOP_EVENT.is_set():
        version = fetch_json("/api/version")
        if version:
            OLLAMA_UP.set(1)
            version_str = version.get("version") or "unknown"
            OLLAMA_VERSION_INFO.labels(version=version_str).set(1)
        else:
            OLLAMA_UP.set(0)

        tags = fetch_json("/api/tags") or {}
        models = tags.get("models")
        if isinstance(models, list):
            OLLAMA_INSTALLED_MODELS.set(len(models))
        elif isinstance(models, dict):
            OLLAMA_INSTALLED_MODELS.set(len(models.keys()))

        _STOP_EVENT.wait(POLL_INTERVAL)


def shutdown(signum: int, frame) -> None:  # pylint: disable=unused-argument
    LOGGER.info("Received signal %s, stopping exporter", signum)
    _STOP_EVENT.set()


def main() -> None:
    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    start_http_server(EXPORTER_PORT)
    poller = threading.Thread(target=poll_forever, name="ollama-exporter", daemon=True)
    poller.start()

    while not _STOP_EVENT.is_set():
        time.sleep(1)

    poller.join(timeout=2)
    LOGGER.info("Exporter stopped")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        shutdown(signal.SIGINT, None)
        sys.exit(0)
