import os
import time
import threading
import requests
from flask import Flask, Response
from prometheus_client import CollectorRegistry, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST


app = Flask(__name__)
registry = CollectorRegistry()

rag_latency = Histogram(
    'erni_ki_rag_response_latency_seconds',
    'RAG end-to-end response latency in seconds',
    buckets=(0.25, 0.5, 1, 2, 3, 5, 10),
    registry=registry,
)

rag_sources = Gauge(
    'erni_ki_rag_sources_count',
    'Number of sources used in last RAG answer',
    registry=registry,
)

OPENWEBUI_TEST_URL = os.getenv('RAG_TEST_URL', 'http://openwebui:8080/health')
RAG_TEST_INTERVAL = float(os.getenv('RAG_TEST_INTERVAL', '30'))


def probe_loop():
    while True:
        start = time.time()
        sources_count = None
        try:
            r = requests.get(OPENWEBUI_TEST_URL, timeout=10)
            # If an application endpoint returns JSON with sources, extract it here.
            # For now, we default to 0 when not present.
            if r.headers.get('content-type', '').startswith('application/json'):
                try:
                    data = r.json()
                    # Example: data may contain {'sources': [...]} from app integration later
                    if isinstance(data, dict) and 'sources' in data and isinstance(data['sources'], list):
                        sources_count = len(data['sources'])
                except Exception:
                    pass
            r.raise_for_status()
            elapsed = time.time() - start
            rag_latency.observe(elapsed)
        except Exception:
            # On failure, record large latency bucket (e.g., 10s) to reflect SLA breach
            rag_latency.observe(10.0)
        finally:
            if sources_count is None:
                sources_count = 0
            rag_sources.set(sources_count)
        time.sleep(RAG_TEST_INTERVAL)


@app.route('/metrics')
def metrics():
    return Response(generate_latest(registry), mimetype=CONTENT_TYPE_LATEST)


def main():
    t = threading.Thread(target=probe_loop, daemon=True)
    t.start()
    port = int(os.getenv('PORT', '9808'))
    app.run(host='0.0.0.0', port=port)


if __name__ == '__main__':
    main()

