"""
title: RAGFlow CHAT ASSISTANT pipe function
author: Per Morten Sandstad (refined by ChatGPT)
version: 1.5.2 (Context via invisible zero-width marker; OWUI 0.6.25)
"""

from pydantic import BaseModel, Field
import requests
import uuid
import re
from urllib.parse import urljoin, quote
from typing import Optional, Any, Dict, List


# ============================== PIPE =========================================
class Pipe:
    class Valves(BaseModel):
        # --- Connection ---
        RAGFLOW_API_BASE_URL: str = Field(
            default="http://192.168.62.140:8090",
            description="Base URL to your RAGFlow instance. With or without '/api' suffix.",
        )
        RAGFLOW_API_KEY: str = Field(
            default="",
            description="API key for RAGFlow.",
        )
        RAGFLOW_CHAT_ASSISTANT: str = Field(
            default="Johnny Mnemonic",
            description="RAGFlow CHAT ASSISTANT name to use.",
        )

        # --- Context persistence marker ---
        MARKER_METHOD: str = Field(
            default="zw",  # "zw" | "comment" | "both"
            description="How to embed session marker: zero-width (zw), HTML comment, or both.",
        )
        CONTEXT_MARKER_KEY: str = Field(
            default="RAGFLOW_SESSION_ID",
            description="Marker key name used in comment mode.",
        )
        CONTEXT_MARKER_TURNS_KEY: str = Field(
            default="RAGFLOW_TURNS",
            description="Turns counter key used in comment mode.",
        )
        SHOW_SESSION_FOOTER: bool = Field(
            default=False,
            description="Tiny visible debug footer (not recommended).",
        )
        AUTO_RESET_TURNS: int = Field(
            default=50,
            description="Auto-reset after this many turns (0 = unlimited).",
        )

        # --- References & links ---
        RAGFLOW_REFERENCE: str = Field(
            default="Yes",
            description="Include references from RAGFlow in response (Yes/No).",
        )
        RAGFLOW_REFERENCE_STYLE: str = Field(
            default="full",
            description="Reference formatting: none | compact | full",
        )
        RAGFLOW_DOC_VIEW_PATH: str = Field(
            default="/document/{doc_id}?ext=pdf&prefix=document",
            description="UI path to view a document by ID; '{doc_id}' placeholder is required.",
        )
        RAGFLOW_ADD_PAGE_ANCHOR: bool = Field(
            default=True,
            description="Append #page=N to document links when page number is known.",
        )

        # --- Rendering (OWUI 0.6.25 friendly) ---
        RAGFLOW_RENDER_MODE: str = Field(
            default="auto",
            description="auto | html | markdown. 'auto' -> safe Markdown; 'html' -> <details>; 'markdown' -> pure Markdown.",
        )
        RAGFLOW_CHUNK_MAX_LEN: int = Field(
            default=2000,
            description="Soft limit for chunk text length (chars); 0 = no limit.",
        )
        SHOW_KEY_FACTS: bool = Field(
            default=True,
            description="Render small Key Facts table extracted from answer (best-effort).",
        )

        # --- Commands ---
        RESET_COMMANDS: List[str] = Field(
            default=["/reset", "reset", "reset context", "новый чат", "сброс", "/new"],
            description="User messages that trigger context reset.",
        )

    def __init__(self):
        self.type = "pipe"
        self.id = "ragflow_pipe"
        self.name = "RAGFlow Pipe"
        self.valves = self.Valves()
        self.CHAT_ID: str = ""

    # -------------------------------------------------------------------------
    # Internal helpers
    # -------------------------------------------------------------------------
    def _headers(self) -> dict:
        return {
            "Authorization": f"Bearer {self.valves.RAGFLOW_API_KEY}",
            "Content-Type": "application/json",
        }

    def _api_base(self) -> str:
        base = self.valves.RAGFLOW_API_BASE_URL.rstrip("/")
        if "/api" not in base:
            return base + "/api/v1"
        if base.endswith("/api"):
            return base + "/v1"
        if base.endswith("/api/"):
            return base + "v1"
        if base.endswith("/api/v1/"):
            return base.rstrip("/")
        if base.endswith("/api/v1"):
            return base
        idx = base.rfind("/api")
        root = base[:idx]
        return root + "/api/v1"

    def _root_base(self) -> str:
        base = self.valves.RAGFLOW_API_BASE_URL.rstrip("/")
        return re.split(r"/api\b", base)[0].rstrip("/")

    def _doc_view_url(self, doc_id: Optional[str]) -> str:
        if not doc_id:
            return ""
        path = (self.valves.RAGFLOW_DOC_VIEW_PATH or "/document/{doc_id}").format(
            doc_id=doc_id
        )
        root = self._root_base() + "/"
        return urljoin(root, path.lstrip("/"))

    def _append_page_anchor(self, url: str, page: Optional[int]) -> str:
        if not url or not self.valves.RAGFLOW_ADD_PAGE_ANCHOR:
            return url
        if page is not None:
            try:
                p = int(page)
                if p > 0:
                    return f"{url}#page={p}"
            except Exception:
                pass
        return url

    def _deep_find_first_id(self, obj: Any) -> Optional[str]:
        KEYS = ("doc_id", "document_id", "id")
        stack = [obj]
        seen = set()
        while stack:
            cur = stack.pop()
            oid = id(cur)
            if oid in seen:
                continue
            seen.add(oid)

            if isinstance(cur, dict):
                for k in KEYS:
                    v = cur.get(k)
                    if isinstance(v, str) and v.strip():
                        return v.strip()
                stack.extend(cur.values())
            elif isinstance(cur, (list, tuple)):
                stack.extend(cur)
        return None

    def _clean_answer(self, text: Optional[str]) -> str:
        if not text:
            return ""
        text = re.sub(r"##\d{1,2}\$\$", "", text)  # remove '##12$$'
        text = re.sub(r"\s*\[ID:\s*\d+\]\s*", "", text)  # remove [ID:5]
        text = re.sub(r"[ \t]+\n", "\n", text)
        return text.strip()

    def _truncate(self, s: str) -> str:
        ml = self.valves.RAGFLOW_CHUNK_MAX_LEN
        if ml and ml > 0 and len(s) > ml:
            return s[:ml].rstrip() + " …"
        return s

    # -------------------------------------------------------------------------
    # Zero-width marker codec (invisible)
    # -------------------------------------------------------------------------
    # Map 2-bit chunks to zero-width chars:
    _ZW_MAP = {
        0b00: "\u200b",  # ZWSP
        0b01: "\u200c",  # ZWNJ
        0b10: "\u200d",  # ZWJ
        0b11: "\u2060",  # WJ
    }
    _ZW_REV = {v: k for k, v in _ZW_MAP.items()}
    # Unique sentinels unlikely to appear naturally:
    _ZW_START = "\u2060\u200d\u200c\u200b\u2060\u200d"  # 6 chars
    _ZW_END = "\u200b\u200c\u200d\u2060\u200b\u200c"  # 6 chars

    def _zw_encode(self, sid: str, turns: int) -> str:
        payload = f"{sid}|{turns}"
        b = payload.encode("utf-8")
        out = [self._ZW_START]
        for byte in b:
            # 4 chunks of 2 bits each, from high to low
            for shift in (6, 4, 2, 0):
                two = (byte >> shift) & 0b11
                out.append(self._ZW_MAP[two])
        out.append(self._ZW_END)
        return "".join(out)

    def _zw_decode_from_text(self, text: str) -> Optional[Dict[str, str]]:
        # Find sentinel boundaries
        s = text.find(self._ZW_START)
        if s == -1:
            return None
        e = text.find(self._ZW_END, s + len(self._ZW_START))
        if e == -1:
            return None
        chunk = text[s + len(self._ZW_START) : e]
        # Convert zero-width sequence back to bytes
        bits = []
        for ch in chunk:
            if ch not in self._ZW_REV:
                # Ignore non-encoded chars (robustness)
                continue
            val = self._ZW_REV[ch]
            bits.append(
                (val >> 1) & 1
            )  # not needed; we will reconstruct by pairs below
        # Re-decode by reading chars in groups of 4 zero-widths = 8 bits = 1 byte
        # Simpler: iterate again and assemble bytes directly
        byte_vals = []
        acc = 0
        count = 0
        for ch in chunk:
            if ch not in self._ZW_REV:
                continue
            two = self._ZW_REV[ch]
            acc = (acc << 2) | two
            count += 1
            if count == 4:
                byte_vals.append(acc)
                acc = 0
                count = 0
        if count != 0:
            # dangling bits → ignore
            pass
        try:
            decoded = bytes(byte_vals).decode("utf-8", errors="strict")
        except Exception:
            return None
        if "|" not in decoded:
            return None
        sid, turns = decoded.split("|", 1)
        if not sid:
            return None
        return {"sid": sid, "turns": turns}

    # -------------------------------------------------------------------------
    # Comment-based marker (optional/legacy)
    # -------------------------------------------------------------------------
    def _extract_comment_marker(self, content: str) -> Optional[Dict[str, str]]:
        key = self.valves.CONTEXT_MARKER_KEY
        tkey = self.valves.CONTEXT_MARKER_TURNS_KEY
        pattern = rf"<!--\s*{re.escape(key)}\s*:\s*([a-zA-Z0-9\-]+)\s*;\s*{re.escape(tkey)}\s*:\s*(\d+)\s*-->"
        m = re.search(pattern, content)
        if m:
            return {"sid": m.group(1), "turns": m.group(2)}
        # Fallback: visible footer form (debug)
        pattern2 = rf"{re.escape(key)}\s*=\s*([a-zA-Z0-9\-]+)\s*;\s*{re.escape(tkey)}\s*=\s*(\d+)"
        m2 = re.search(pattern2, content)
        if m2:
            return {"sid": m2.group(1), "turns": m2.group(2)}
        return None

    def _extract_marker(self, messages: List[Dict]) -> Dict[str, str]:
        """
        Try zero-width marker first, then comment marker.
        Scan last ~10 assistant/system messages.
        """
        # Search latest to older
        for msg in reversed(messages[-10:]):
            if msg.get("role") not in ("assistant", "system"):
                continue
            content = msg.get("content") or ""
            # zero-width
            mk = self._zw_decode_from_text(content)
            if mk and mk.get("sid"):
                return {"sid": mk["sid"], "turns": mk.get("turns", "0")}
            # comment
            mk2 = self._extract_comment_marker(content)
            if mk2 and mk2.get("sid"):
                return {"sid": mk2["sid"], "turns": mk2.get("turns", "0")}
        return {}

    def _embed_marker(self, text: str, sid: str, turns: int) -> str:
        method = (self.valves.MARKER_METHOD or "zw").lower()
        out = text.rstrip()

        add_comment = method in ("comment", "both")
        add_zw = method in ("zw", "both")

        parts = [out]

        if add_zw:
            parts.append(self._zw_encode(sid, turns))

        if add_comment:
            key = self.valves.CONTEXT_MARKER_KEY
            tkey = self.valves.CONTEXT_MARKER_TURNS_KEY
            hidden = f"<!-- {key}: {sid}; {tkey}: {turns} -->"
            parts.append(hidden)
            if self.valves.SHOW_SESSION_FOOTER:
                parts.append(f"<sub><sup>{key}={sid}; {tkey}={turns}</sup></sub>")

        return ("\n\n".join(parts)).strip()

    # -------------------------------------------------------------------------
    # RAGFlow API calls
    # -------------------------------------------------------------------------
    def get_chat_assistant_id(self) -> str:
        url = f"{self._api_base()}/chats?page=1&page_size=50&name={quote(self.valves.RAGFLOW_CHAT_ASSISTANT)}"
        r = requests.get(url, headers=self._headers(), timeout=15)
        if r.status_code == 200:
            data = r.json() or {}
            for assistant in data.get("data", []) or []:
                if assistant.get("name") == self.valves.RAGFLOW_CHAT_ASSISTANT:
                    a_id = assistant.get("id")
                    if a_id:
                        return a_id
        raise RuntimeError(
            f"Assistant '{self.valves.RAGFLOW_CHAT_ASSISTANT}' not found or API error. "
            f"HTTP {r.status_code}: {r.text}"
        )

    def create_chat_session(self, chat_assistant_id: str, session_name: str) -> str:
        url = f"{self._api_base()}/chats/{chat_assistant_id}/sessions"
        payload = {"name": session_name}
        r = requests.post(url, json=payload, headers=self._headers(), timeout=20)
        if r.status_code == 200:
            j = r.json() or {}
            sid = (j.get("data") or {}).get("id")
            if sid:
                return sid
        raise RuntimeError(f"Failed to create session. HTTP {r.status_code}: {r.text}")

    def chat_session(
        self, chat_assistant_id: str, chat_id: str, chat_message: str
    ) -> dict:
        url = f"{self._api_base()}/chats/{chat_assistant_id}/completions"
        payload = {"question": chat_message, "stream": False, "session_id": chat_id}
        r = requests.post(url, json=payload, headers=self._headers(), timeout=60)
        if r.status_code == 200:
            return r.json() or {}
        raise RuntimeError(f"Failed to get completion. HTTP {r.status_code}: {r.text}")

    def delete_chat_session(
        self, chat_assistant_id: str, session_id: Optional[str]
    ) -> None:
        if not session_id:
            return
        url = f"{self._api_base()}/chats/{chat_assistant_id}/sessions"
        payload = {"ids": [session_id]}
        try:
            requests.delete(url, json=payload, headers=self._headers(), timeout=15)
        except Exception:
            pass

    # -------------------------------------------------------------------------
    # Pretty formatting (OWUI 0.6.25 friendly)
    # -------------------------------------------------------------------------
    def _render_docs_list(self, doc_aggs: List[Dict]) -> str:
        if not doc_aggs:
            return ""
        lines = []
        for d in doc_aggs:
            doc_name = d.get("doc_name") or d.get("document_name") or "Document"
            doc_id = (
                d.get("doc_id") or d.get("document_id") or self._deep_find_first_id(d)
            )
            href = self._doc_view_url(doc_id) if doc_id else ""
            icon = "📄"
            if href:
                lines.append(f"- {icon} [{doc_name}]({href})")
            else:
                lines.append(f"- {icon} {doc_name}")
        return "**Sources**\n" + "\n".join(lines)

    def _chunk_title_bits(self, c: Dict):
        doc_name = c.get("document_name") or c.get("doc_name") or "Document"
        doc_id = c.get("document_id") or c.get("doc_id") or self._deep_find_first_id(c)
        page = c.get("page_no") or c.get("page") or c.get("page_number")
        try:
            page = int(page) if page is not None else None
        except Exception:
            page = None
        link = self._doc_view_url(doc_id) if doc_id else ""
        link = self._append_page_anchor(link, page)
        page_suffix = f" (p.{page})" if page else ""
        return doc_name, link, page_suffix

    # HTML accordions (<details>) — requires HTML render enabled in OpenWebUI
    def _format_chunks_html(self, chunks: List[Dict]) -> str:
        if not chunks:
            return ""
        items = []
        for i, c in enumerate(chunks):
            doc_name, link, page_suffix = self._chunk_title_bits(c)
            title_plain = f"[#{i}] {doc_name}{page_suffix}"
            content = self._truncate((c.get("content") or "").strip())
            quoted = f"> {content}" if content else "> —"
            items.append(
                f"<details>\n<summary>{title_plain}</summary>\n\n{quoted}\n\n</details>"
            )
        return "\n\n**Context snippets**\n\n" + "\n\n".join(items)

    # Markdown “pseudo-accordions” (safe)
    def _format_chunks_markdown(self, chunks: List[Dict]) -> str:
        if not chunks:
            return ""
        items = []
        for i, c in enumerate(chunks):
            doc_name, link, page_suffix = self._chunk_title_bits(c)
            arrow = "▶️"
            head = f"{arrow} **[#${i}] {doc_name}{page_suffix}**"
            if link:
                head = f"{arrow} **[#${i}] [{doc_name}{page_suffix}]({link})**"
            content = self._truncate((c.get("content") or "").strip())
            body = f"> {content}" if content else "> —"
            items.append(f"{head}\n{body}")
        return "\n\n**Context snippets**\n\n" + "\n\n".join(items)

    def _format_references_block(self, data: dict) -> str:
        try:
            ref = (data or {}).get("data", {}).get("reference", {}) or {}
            doc_aggs = ref.get("doc_aggs", []) or []
            chunks = ref.get("chunks", []) or []

            if (
                self.valves.RAGFLOW_REFERENCE.lower() != "yes"
                or self.valves.RAGFLOW_REFERENCE_STYLE == "none"
            ):
                return ""

            parts = []
            parts.append(self._render_docs_list(doc_aggs))

            if self.valves.RAGFLOW_REFERENCE_STYLE != "compact":
                mode = (self.valves.RAGFLOW_RENDER_MODE or "auto").lower()
                if mode == "html":
                    parts.append(self._format_chunks_html(chunks))
                else:
                    parts.append(self._format_chunks_markdown(chunks))

            return "\n\n".join([p for p in parts if p]).strip()

        except Exception:
            return ""

    def _extract_key_facts(self, answer: str) -> List[List[str]]:
        facts = []
        for line in answer.splitlines():
            m = re.match(
                r"\s*([A-ZÄÖÜa-zäöüßA-Za-z][^:]{1,60})\s*:\s*(.{1,120})$", line.strip()
            )
            if m:
                k, v = m.group(1).strip(), m.group(2).strip()
                if len(k) >= 3 and len(v) >= 1:
                    facts.append([k, v])
            if len(facts) >= 4:
                break
        return facts

    def _render_key_facts_table(self, facts: List[List[str]]) -> str:
        if not facts:
            return ""
        rows = ["| Key | Value |", "|---|---|"]
        for k, v in facts:
            k2 = k.replace("|", "\\|")
            v2 = v.replace("|", "\\|")
            rows.append(f"| {k2} | {v2} |")
        return "\n".join(rows)

    def _compose_header(self, answer: str) -> str:
        header_parts = []
        if answer:
            header_parts.append(f"### ✅ Summary\n\n{answer}")
            if self.valves.SHOW_KEY_FACTS:
                facts = self._extract_key_facts(answer)
                if facts:
                    header_parts.append("\n**Key Facts**\n")
                    header_parts.append(self._render_key_facts_table(facts))
        return ("\n".join(header_parts)).strip()

    # -------------------------------------------------------------------------
    # Reset handling
    # -------------------------------------------------------------------------
    def _handle_reset(self, chat_assistant_id: str, messages: List[Dict]) -> str:
        # If we can read an existing marker, try to delete remote session
        mk = self._extract_marker(messages)
        sid = mk.get("sid")
        if sid:
            try:
                self.delete_chat_session(chat_assistant_id, sid)
            except Exception:
                pass
        return "🔁 Chat context has been reset."

    # -------------------------------------------------------------------------
    # Main entry
    # -------------------------------------------------------------------------
    def pipe(self, body: dict, __user__: dict):
        messages = body.get("messages", [])
        user_question = messages[-1]["content"] if messages else ""
        cmd = (user_question or "").strip().lower()

        try:
            CHAT_ASSISTANT_ID = self.get_chat_assistant_id()

            # 1) Handle manual reset commands
            if any(cmd == c.lower() for c in self.valves.RESET_COMMANDS):
                return self._handle_reset(CHAT_ASSISTANT_ID, messages)

            # 2) Try to reuse existing session from markers
            mk = self._extract_marker(messages)
            sid = mk.get("sid")
            turns = int(mk.get("turns") or 0)

            # Auto-reset by turns if configured
            if self.valves.AUTO_RESET_TURNS and turns >= self.valves.AUTO_RESET_TURNS:
                sid = None
                turns = 0

            # 3) Ensure session
            if sid:
                self.CHAT_ID = sid
            else:
                unique_id = str(uuid.uuid4())[:8]
                session_name = f"OpenWebUI-{unique_id}"
                self.CHAT_ID = self.create_chat_session(CHAT_ASSISTANT_ID, session_name)
                turns = 0  # new session

            # 4) Ask the assistant
            resp = self.chat_session(CHAT_ASSISTANT_ID, self.CHAT_ID, user_question)

            # 5) Compose output
            answer_raw = (resp.get("data") or {}).get("answer", "")
            answer = self._clean_answer(answer_raw)
            header = self._compose_header(answer)
            refs_md = self._format_references_block(resp)

            final_parts = [p for p in [header, refs_md] if p]
            out_text = "\n\n---\n\n".join(final_parts) if final_parts else answer

            # 6) Embed invisible marker with same session id
            turns += 1
            out_text = self._embed_marker(out_text, self.CHAT_ID, turns)

            return out_text

        except Exception as e:
            return f"Error: {e}"
