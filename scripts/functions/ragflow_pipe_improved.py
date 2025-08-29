"""
title: RAGFlow CHAT ASSISTANT pipe function
author: ERNI-KI Team (based on Per Morten Sandstad version)
version: 1.1
"""

import re
import uuid

import requests
from pydantic import BaseModel, Field


class Pipe:
    class Valves(BaseModel):
        RAGFLOW_API_BASE_URL: str = Field(
            default="http://ragflow-server:80/api",
            description="Base URL for RAGFlow API (direct connection to RAGFlow container).",
        )
        RAGFLOW_PUBLIC_WEB_URL: str = Field(
            default="https://ki.erni-gruppe.ch/ragflow",
            description="Public web URL for building document links (optional).",
        )
        RAGFLOW_API_KEY: str = Field(
            default="ragflow-llMGM2NzU2ODI5NjExZjA4MjAyMzIwNz",
            description="API key for authenticating requests to the RAGFlow API.",
        )
        RAGFLOW_CHAT_ASSISTANT: str = Field(
            default="Erni",
            description="Exact RAGFlow Chat Assistant name to access via the API.",
        )
        INCLUDE_REFERENCES: str = Field(
            default="Yes",
            description="Include references from RAGFlow in response (Yes/No/True/False).",
        )
        REFERENCE_CHUNK_LIMIT: int = Field(
            default=5,
            description="Max number of reference chunks to display.",
        )
        TIMEOUT: int = Field(
            default=15,
            description="HTTP timeout (seconds).",
        )

    def __init__(self):
        self.type = "pipe"
        self.id = "ragflow_pipe"
        self.name = "RAGFlow Pipe"
        self.valves = self.Valves()

    # ---------- helpers ----------
    def _headers(self):
        return {
            "Authorization": f"Bearer {self.valves.RAGFLOW_API_KEY}",
            "Content-Type": "application/json",
        }

    def _api_url(self, path: str) -> str:
        return f"{self.valves.RAGFLOW_API_BASE_URL.rstrip('/')}{path}"

    def _refs_on(self) -> bool:
        return str(self.valves.INCLUDE_REFERENCES).strip().lower() in {
            "yes",
            "true",
            "1",
            "y",
        }

    def _cleanup_markers(self, text: str) -> str:
        if not text:
            return ""
        # Преобразовать ##1$$ → #1, затем удалить остаточные маркеры
        text = re.sub(r"##(\d{1,2})\$\$", r"#\1", text)
        text = re.sub(r"##\d{1,2}\$\$", "", text)
        return text

    def _doc_link(self, doc_id: str, doc_name: str) -> str:
        public = self.valves.RAGFLOW_PUBLIC_WEB_URL.strip()
        if not public:
            # Без публичного URL хотя бы покажем id
            return f"- {doc_name} (id: {doc_id})"
        href = f"{public.rstrip('/')}/document/{doc_id}?ext=pdf&prefix=document"
        return f"- [{doc_name}]({href})"

    # ---------- RAGFlow API ----------
    def get_chat_assistant_id(self) -> str:
        from requests.utils import quote

        url = self._api_url(
            f"/v1/chats?page=1&page_size=10&name={quote(self.valves.RAGFLOW_CHAT_ASSISTANT)}"
        )
        r = requests.get(url, headers=self._headers(), timeout=self.valves.TIMEOUT)
        if r.ok:
            for a in (r.json() or {}).get("data", []):
                if a.get("name") == self.valves.RAGFLOW_CHAT_ASSISTANT:
                    return a.get("id")
        raise RuntimeError(
            f"Assistant '{self.valves.RAGFLOW_CHAT_ASSISTANT}' not found "
            f"or API error: {r.status_code} {r.text}"
        )

    def create_chat_session(self, chat_assistant_id: str, session_name: str) -> str:
        url = self._api_url(f"/v1/chats/{chat_assistant_id}/sessions")
        r = requests.post(
            url,
            json={"name": session_name},
            headers=self._headers(),
            timeout=self.valves.TIMEOUT,
        )
        if r.ok:
            sid = (r.json() or {}).get("data", {}).get("id")
            if sid:
                return sid
        raise RuntimeError(f"Failed to create session: {r.status_code} {r.text}")

    def chat_completion(
        self, chat_assistant_id: str, session_id: str, question: str
    ) -> dict:
        url = self._api_url(f"/v1/chats/{chat_assistant_id}/completions")
        payload = {"question": question, "stream": False, "session_id": session_id}
        r = requests.post(
            url, json=payload, headers=self._headers(), timeout=self.valves.TIMEOUT
        )
        if r.ok:
            return r.json() or {}
        raise RuntimeError(f"Completion failed: {r.status_code} {r.text}")

    def delete_chat_session(self, chat_assistant_id: str, session_id: str):
        url = self._api_url(f"/v1/chats/{chat_assistant_id}/sessions")
        try:
            requests.delete(
                url,
                json={"ids": [session_id]},
                headers=self._headers(),
                timeout=self.valves.TIMEOUT,
            )
        except Exception:
            # Без шумных падений — попытались и ладно
            pass

    # ---------- entry point ----------
    def pipe(self, body: dict, __user__: dict):
        messages = body.get("messages") or []
        if not messages:
            return "Ошибка: пустой запрос."
        question = messages[-1].get("content", "").strip()
        if not question:
            return "Ошибка: не удалось извлечь текст запроса."

        assistant_id = None
        session_id = None

        try:
            assistant_id = self.get_chat_assistant_id()
            session_id = self.create_chat_session(
                assistant_id, f"OpenWebUI-{uuid.uuid4().hex[:8]}"
            )
            resp = self.chat_completion(assistant_id, session_id, question)

            data = resp.get("data", {}) if isinstance(resp, dict) else {}
            answer_raw = data.get("answer", "")
            answer = self._cleanup_markers(answer_raw) or "(пустой ответ)"
            reference = data.get("reference") or {}

            # Документы
            docs_lines = []
            for d in reference.get("doc_aggs") or []:
                docs_lines.append(
                    self._doc_link(d.get("doc_id", ""), d.get("doc_name", "document"))
                )
            docs_block = "\n".join(docs_lines)

            # Чанки
            chunks_block = ""
            if self._refs_on():
                chunks = reference.get("chunks") or []
                lim = max(0, int(self.valves.REFERENCE_CHUNK_LIMIT))
                lines = []
                for i, ch in enumerate(chunks[:lim], start=1):
                    dn = ch.get("document_name", "document")
                    ct = (ch.get("content") or "").strip()
                    lines.append(f"**#{i}** — {dn}\n{ct}")
                chunks_block = "\n\n".join(lines)

            parts = [answer]
            if docs_lines:
                parts.append("**Documents referenced:**\n" + docs_block)
            if self._refs_on() and chunks_block:
                parts.append("**Chunks used from knowledge base:**\n" + chunks_block)

            return "\n\n".join(parts)

        except Exception as e:
            return f"Ошибка RAGFlow интеграции: {e}"
        finally:
            if assistant_id and session_id:
                self.delete_chat_session(assistant_id, session_id)
