"""
Custom LiteLLM provider for PublicAI Apertus models.

LiteLLM treats unknown providers as OpenAI-compatible, but PublicAI blocks the
official OpenAI SDK user-agent. This handler issues raw HTTP requests with the
same JSON schema while avoiding the blocked client fingerprint. It also keeps
streaming compatible with Server-Sent Events (SSE).
"""

from __future__ import annotations

import errno
import json
import logging
import os
import threading
import time
from typing import Any, AsyncIterator, Dict, Iterator, Optional, Tuple, Union

import httpx
from litellm import CustomLLM, ModelResponse
from litellm.llms.custom_llm import CustomLLMError
from litellm.litellm_core_utils.llm_response_utils.convert_dict_to_response import (
    convert_to_model_response_object,
)
from litellm.types.utils import GenericStreamingChunk

METRICS_STORAGE_DIR = os.getenv("LITELLM_PUBLICAI_METRICS_DIR", "/tmp/litellm-publicai-prom")
os.makedirs(METRICS_STORAGE_DIR, exist_ok=True)
os.environ.setdefault("PROMETHEUS_MULTIPROC_DIR", METRICS_STORAGE_DIR)

try:
    from prometheus_client import (
        CollectorRegistry,
        Counter,
        Histogram,
        multiprocess,
        start_http_server,
    )
except Exception:  # pragma: no cover - optional dependency fallback
    CollectorRegistry = Counter = Histogram = multiprocess = start_http_server = None

LOGGER = logging.getLogger("erni_ki.publicai")
DEFAULT_BASE_URL = "https://api.publicai.co/v1"
USER_AGENT = "erni-ki-litellm-publicai/1.0"
METRICS_PORT = int(os.getenv("LITELLM_PUBLICAI_METRICS_PORT", "9109"))
METRICS_ENABLED = (
    Counter is not None
    and CollectorRegistry is not None
    and multiprocess is not None
    and start_http_server is not None
    and os.getenv("LITELLM_PUBLICAI_METRICS_DISABLED", "0").lower() not in {"1", "true"}
)

_METRICS_STARTED = False
_METRICS_LOCK = threading.Lock()
_METRICS_REGISTRY: Optional[CollectorRegistry] = None

if METRICS_ENABLED:
    LOGGER.info(
        "PublicAI metrics enabled (port=%s, dir=%s)", METRICS_PORT, METRICS_STORAGE_DIR
    )
    REQUEST_COUNTER = Counter(
        "litellm_publicai_requests_total",
        "Total requests routed to PublicAI",
        ["status", "stream"],
    )
    ERROR_COUNTER = Counter(
        "litellm_publicai_request_errors_total",
        "Error responses from PublicAI",
        ["status", "stream"],
    )
    LATENCY_HISTOGRAM = Histogram(
        "litellm_publicai_request_latency_seconds",
        "Upstream PublicAI latency",
        ["stream"],
        buckets=(0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 15),
    )
else:  # pragma: no cover - disabled metrics fallback
    REQUEST_COUNTER = ERROR_COUNTER = LATENCY_HISTOGRAM = None


def _start_metrics_server() -> None:
    global _METRICS_STARTED, METRICS_ENABLED, _METRICS_REGISTRY
    if not METRICS_ENABLED or start_http_server is None:
        return
    with _METRICS_LOCK:
        if _METRICS_STARTED:
            return
        try:
            registry = CollectorRegistry()
            multiprocess.MultiProcessCollector(registry)
            start_http_server(METRICS_PORT, registry=registry)
            _METRICS_REGISTRY = registry
            LOGGER.info(
                "PublicAI metrics exporter listening on 0.0.0.0:%s", METRICS_PORT
            )
            _METRICS_STARTED = True
        except OSError as exc:
            if exc.errno == errno.EADDRINUSE:
                LOGGER.debug(
                    "PublicAI metrics server already running on port %s", METRICS_PORT
                )
            else:
                LOGGER.warning("Failed to start PublicAI metrics server: %s", exc)
                METRICS_ENABLED = False


_start_metrics_server()

# Fields we forward verbatim if the upstream request included them.
FORWARDED_PARAMS = {
    "temperature",
    "top_p",
    "presence_penalty",
    "frequency_penalty",
    "max_tokens",
    "max_output_tokens",
    "context_window",
    "seed",
    "stop",
    "response_format",
    "tools",
    "tool_choice",
    "metadata",
    "logit_bias",
    "user",
    "stream_options",
}


class PublicAICustomLLM(CustomLLM):
    """LiteLLM handler that calls the PublicAI REST API directly."""

    def completion(
        self,
        model: str,
        messages: list,
        api_base: str,
        custom_prompt_dict: Dict[str, Any],
        model_response: ModelResponse,
        print_verbose,
        encoding,
        api_key,
        logging_obj,
        optional_params: Dict[str, Any],
        acompletion=None,
        litellm_params=None,
        logger_fn=None,
        headers=None,
        timeout: Optional[Union[float, httpx.Timeout]] = None,
        client=None,
    ) -> ModelResponse:
        payload, request_headers, url, resolved_timeout = self._prepare_payload(
            model=model,
            messages=messages,
            api_base=api_base,
            api_key=api_key,
            optional_params=optional_params,
            litellm_params=litellm_params,
            headers=headers,
            stream=False,
        )

        data, response_headers = self._sync_post(
            url=url,
            headers=request_headers,
            payload=payload,
            timeout=resolved_timeout or timeout,
        )
        return self._to_model_response(data, response_headers, model_response)

    async def acompletion(
        self,
        model: str,
        messages: list,
        api_base: str,
        custom_prompt_dict: Dict[str, Any],
        model_response: ModelResponse,
        print_verbose,
        encoding,
        api_key,
        logging_obj,
        optional_params: Dict[str, Any],
        acompletion=None,
        litellm_params=None,
        logger_fn=None,
        headers=None,
        timeout: Optional[Union[float, httpx.Timeout]] = None,
        client=None,
    ) -> ModelResponse:
        payload, request_headers, url, resolved_timeout = self._prepare_payload(
            model=model,
            messages=messages,
            api_base=api_base,
            api_key=api_key,
            optional_params=optional_params,
            litellm_params=litellm_params,
            headers=headers,
            stream=False,
        )

        data, response_headers = await self._async_post(
            url=url,
            headers=request_headers,
            payload=payload,
            timeout=resolved_timeout or timeout,
        )
        return self._to_model_response(data, response_headers, model_response)

    def streaming(
        self,
        model: str,
        messages: list,
        api_base: str,
        custom_prompt_dict: Dict[str, Any],
        model_response: ModelResponse,
        print_verbose,
        encoding,
        api_key,
        logging_obj,
        optional_params: Dict[str, Any],
        acompletion=None,
        litellm_params=None,
        logger_fn=None,
        headers=None,
        timeout: Optional[Union[float, httpx.Timeout]] = None,
        client=None,
    ) -> Iterator[GenericStreamingChunk]:
        payload, request_headers, url, resolved_timeout = self._prepare_payload(
            model=model,
            messages=messages,
            api_base=api_base,
            api_key=api_key,
            optional_params=optional_params,
            litellm_params=litellm_params,
            headers=headers,
            stream=True,
        )

        yield from self._sync_stream(
            url=url,
            headers=request_headers,
            payload=payload,
            timeout=resolved_timeout or timeout,
        )

    async def astreaming(
        self,
        model: str,
        messages: list,
        api_base: str,
        custom_prompt_dict: Dict[str, Any],
        model_response: ModelResponse,
        print_verbose,
        encoding,
        api_key,
        logging_obj,
        optional_params: Dict[str, Any],
        acompletion=None,
        litellm_params=None,
        logger_fn=None,
        headers=None,
        timeout: Optional[Union[float, httpx.Timeout]] = None,
        client=None,
    ) -> AsyncIterator[GenericStreamingChunk]:
        payload, request_headers, url, resolved_timeout = self._prepare_payload(
            model=model,
            messages=messages,
            api_base=api_base,
            api_key=api_key,
            optional_params=optional_params,
            litellm_params=litellm_params,
            headers=headers,
            stream=True,
        )

        async for chunk in self._async_stream(
            url=url,
            headers=request_headers,
            payload=payload,
            timeout=resolved_timeout or timeout,
        ):
            yield chunk

    # --------------------------------------------------------------------- #
    # Internal helpers
    # --------------------------------------------------------------------- #

    def _prepare_payload(
        self,
        *,
        model: str,
        messages: list,
        api_base: Optional[str],
        api_key: Optional[str],
        optional_params: Dict[str, Any],
        litellm_params: Optional[Dict[str, Any]],
        headers: Optional[Dict[str, str]],
        stream: bool,
    ) -> Tuple[Dict[str, Any], Dict[str, str], str, Optional[httpx.Timeout]]:
        merged_params = {**(litellm_params or {}), **(optional_params or {})}
        resolved_api_key = self._resolve_api_key(api_key, merged_params)

        payload: Dict[str, Any] = {
            "model": self._resolve_upstream_model(model, optional_params, litellm_params),
            "messages": messages,
            "stream": stream,
        }
        for key in FORWARDED_PARAMS:
            if key in merged_params and merged_params[key] is not None:
                payload[key] = merged_params[key]

        if "mode" not in payload and "mode" in merged_params:
            payload["mode"] = merged_params["mode"]

        resolved_base = self._resolve_api_base(api_base, merged_params)
        url = f"{resolved_base}/chat/completions"

        request_headers = {
            "Authorization": f"Bearer {resolved_api_key}",
            "Accept": "text/event-stream" if stream else "application/json",
            "Content-Type": "application/json",
            "User-Agent": USER_AGENT,
        }
        if headers:
            request_headers.update(headers)

        resolved_timeout = self._resolve_timeout(
            merged_params.get("timeout") or merged_params.get("stream_timeout")
        )
        return payload, request_headers, url, resolved_timeout

    def _resolve_upstream_model(
        self,
        requested_model: str,
        optional_params: Dict[str, Any],
        litellm_params: Optional[Dict[str, Any]],
    ) -> str:
        explicit = (
            optional_params.get("model")
            or (litellm_params or {}).get("model")
            or requested_model
        )
        return str(explicit)

    def _resolve_api_key(
        self, provided_key: Optional[str], merged_params: Dict[str, Any]
    ) -> str:
        key_candidate = merged_params.get("api_key") or provided_key
        if isinstance(key_candidate, str) and key_candidate.startswith("os.environ/"):
            env_name = key_candidate.split("/", 1)[1]
            key_candidate = os.getenv(env_name)

        if not key_candidate:
            key_candidate = os.getenv("PUBLICAI_API_KEY")

        if not key_candidate:
            raise CustomLLMError(
                status_code=401,
                message="PublicAI api_key is required. Configure PUBLICAI_API_KEY secret.",
            )
        return key_candidate

    def _resolve_api_base(
        self, api_base: Optional[str], merged_params: Dict[str, Any]
    ) -> str:
        base_candidate = api_base or merged_params.get("api_base") or DEFAULT_BASE_URL
        if isinstance(base_candidate, str) and base_candidate.startswith("os.environ/"):
            env_name = base_candidate.split("/", 1)[1]
            base_candidate = os.getenv(env_name, DEFAULT_BASE_URL)
        return str(base_candidate).rstrip("/")

    def _resolve_timeout(
        self, timeout_value: Optional[Union[float, httpx.Timeout]]
    ) -> Optional[httpx.Timeout]:
        if timeout_value is None:
            return None
        if isinstance(timeout_value, httpx.Timeout):
            return timeout_value
        try:
            numeric = float(timeout_value)
        except (TypeError, ValueError):
            LOGGER.warning("Invalid timeout value %s, falling back to httpx default", timeout_value)
            return None
        return httpx.Timeout(numeric)

    def _sync_post(
        self,
        *,
        url: str,
        headers: Dict[str, str],
        payload: Dict[str, Any],
        timeout: Optional[Union[float, httpx.Timeout]],
    ) -> Tuple[Dict[str, Any], Dict[str, str]]:
        start = time.perf_counter()
        try:
            with httpx.Client(timeout=timeout) as client:
                response = client.post(url, headers=headers, json=payload)
        except httpx.HTTPError as exc:
            self._record_metrics("exception", time.perf_counter() - start, stream=False)
            raise CustomLLMError(status_code=502, message=f"PublicAI request failed: {exc}") from exc

        duration = time.perf_counter() - start
        try:
            data, response_headers = self._handle_response(response)
        except CustomLLMError:
            self._record_metrics(response.status_code, duration, stream=False)
            raise
        self._record_metrics(response.status_code, duration, stream=False)
        return data, response_headers

    async def _async_post(
        self,
        *,
        url: str,
        headers: Dict[str, str],
        payload: Dict[str, Any],
        timeout: Optional[Union[float, httpx.Timeout]],
    ) -> Tuple[Dict[str, Any], Dict[str, str]]:
        start = time.perf_counter()
        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                response = await client.post(url, headers=headers, json=payload)
        except httpx.HTTPError as exc:
            self._record_metrics("exception", time.perf_counter() - start, stream=False)
            raise CustomLLMError(status_code=502, message=f"PublicAI request failed: {exc}") from exc

        duration = time.perf_counter() - start
        try:
            data, response_headers = self._handle_response(response)
        except CustomLLMError:
            self._record_metrics(response.status_code, duration, stream=False)
            raise
        self._record_metrics(response.status_code, duration, stream=False)
        return data, response_headers

    def _handle_response(
        self, response: httpx.Response
    ) -> Tuple[Dict[str, Any], Dict[str, str]]:
        if response.status_code >= 400:
            detail = self._extract_error_detail(response)
            raise CustomLLMError(status_code=response.status_code, message=detail)
        return response.json(), dict(response.headers)

    def _extract_error_detail(self, response: httpx.Response) -> str:
        try:
            data = response.json()
        except ValueError:
            return response.text

        detail = data.get("error") or data.get("detail") or data
        return json.dumps(detail, ensure_ascii=False)

    def _to_model_response(
        self,
        payload: Dict[str, Any],
        headers: Dict[str, str],
        template: Optional[ModelResponse] = None,
    ) -> ModelResponse:
        return convert_to_model_response_object(
            response_object=payload,
            model_response_object=template,
            response_type="completion",
            stream=False,
            hidden_params=payload.get("hidden_params"),
            _response_headers=headers,
        )

    def _sync_stream(
        self,
        *,
        url: str,
        headers: Dict[str, str],
        payload: Dict[str, Any],
        timeout: Optional[Union[float, httpx.Timeout]],
    ) -> Iterator[GenericStreamingChunk]:
        start = time.perf_counter()
        try:
            with httpx.Client(timeout=timeout) as client:
                with client.stream("POST", url, headers=headers, json=payload) as response:
                    if response.status_code >= 400:
                        detail = self._extract_error_detail(response)
                        raise CustomLLMError(status_code=response.status_code, message=detail)
                    self._record_metrics(
                        response.status_code, time.perf_counter() - start, stream=True
                    )
                    yield from self._iterate_sse(response.iter_lines())
        except httpx.HTTPError as exc:
            self._record_metrics("exception", time.perf_counter() - start, stream=True)
            raise CustomLLMError(status_code=502, message=f"PublicAI stream failed: {exc}") from exc

    async def _async_stream(
        self,
        *,
        url: str,
        headers: Dict[str, str],
        payload: Dict[str, Any],
        timeout: Optional[Union[float, httpx.Timeout]],
    ) -> AsyncIterator[GenericStreamingChunk]:
        start = time.perf_counter()
        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                async with client.stream("POST", url, headers=headers, json=payload) as response:
                    if response.status_code >= 400:
                        detail = self._extract_error_detail(response)
                        raise CustomLLMError(status_code=response.status_code, message=detail)
                    self._record_metrics(
                        response.status_code, time.perf_counter() - start, stream=True
                    )
                    async for chunk in self._aiterate_sse(response.aiter_lines()):
                        yield chunk
        except httpx.HTTPError as exc:
            self._record_metrics("exception", time.perf_counter() - start, stream=True)
            raise CustomLLMError(status_code=502, message=f"PublicAI stream failed: {exc}") from exc

    def _iterate_sse(self, lines: Iterator[str]) -> Iterator[GenericStreamingChunk]:
        for raw_line in lines:
            line = (raw_line or "").strip()
            if not line or not line.startswith("data:"):
                continue
            payload = line[len("data:") :].strip()
            if payload == "[DONE]":
                break
            try:
                chunk = json.loads(payload)
            except json.JSONDecodeError:
                LOGGER.debug("Skipping malformed SSE chunk: %s", payload)
                continue
            yield self._chunk_from_stream(chunk)

    async def _aiterate_sse(
        self, lines: AsyncIterator[str]
    ) -> AsyncIterator[GenericStreamingChunk]:
        async for raw_line in lines:
            line = (raw_line or "").strip()
            if not line or not line.startswith("data:"):
                continue
            payload = line[len("data:") :].strip()
            if payload == "[DONE]":
                break
            try:
                chunk = json.loads(payload)
            except json.JSONDecodeError:
                LOGGER.debug("Skipping malformed SSE chunk: %s", payload)
                continue
            yield self._chunk_from_stream(chunk)

    def _chunk_from_stream(self, chunk_payload: Dict[str, Any]) -> GenericStreamingChunk:
        choices = chunk_payload.get("choices") or []
        choice = choices[0] if choices else {}
        delta = choice.get("delta") or {}
        text = delta.get("content") or ""
        finish_reason = choice.get("finish_reason")

        return {
            "text": text,
            "is_finished": bool(finish_reason),
            "finish_reason": finish_reason or "streaming",
            "usage": None,
            "index": choice.get("index", 0),
            "provider_specific_fields": choice.get("provider_specific_fields"),
        }

    def _record_metrics(
        self, status_code: Union[int, str], duration: Optional[float], stream: bool
    ) -> None:
        if not METRICS_ENABLED or REQUEST_COUNTER is None:
            return

        status_label = str(status_code)
        stream_label = "true" if stream else "false"
        try:
            REQUEST_COUNTER.labels(status=status_label, stream=stream_label).inc()
            if status_label.startswith(("4", "5")) or status_label == "exception":
                if ERROR_COUNTER is not None:
                    ERROR_COUNTER.labels(status=status_label, stream=stream_label).inc()
            if duration is not None and LATENCY_HISTOGRAM is not None:
                LATENCY_HISTOGRAM.labels(stream=stream_label).observe(duration)
        except Exception:  # pragma: no cover - metrics are best effort
            LOGGER.debug("Failed to record PublicAI metrics", exc_info=True)


publicai_handler = PublicAICustomLLM()
