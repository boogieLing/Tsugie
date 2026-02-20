#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import shutil
import subprocess
import time
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urljoin, urlparse

import httpx
from bs4 import BeautifulSoup


DEFAULT_TIMEOUT_SEC = 25.0
DEFAULT_MIN_REFRESH_DAYS = 45
DEFAULT_QPS = 0.12
DEFAULT_MAX_IMAGES = 6
DEFAULT_MAX_SOURCE_URLS = 3
DEFAULT_MAX_DESC_CHARS = 1800
DEFAULT_MAX_IMAGE_BYTES = 5 * 1024 * 1024
DEFAULT_CODEX_MODEL = "auto"
DEFAULT_CODEX_MODEL_CANDIDATES = [
    "gpt-5-mini",
    "gpt-4.1-mini",
    "gpt-4o-mini",
    "o4-mini",
    "o3-mini",
    "gpt-5",
]
CODEX_UNSUPPORTED_HINT = "not supported when using Codex with a ChatGPT account"

DESCRIPTION_SELECTORS = [
    "article p",
    "main p",
    ".entry-content p",
    ".post-content p",
    ".article-body p",
    ".event-detail p",
    ".event-content p",
    ".content p",
]

IMAGE_SELECTORS = [
    "article img[src]",
    "article img[data-src]",
    "main img[src]",
    "main img[data-src]",
    ".entry-content img[src]",
    ".post-content img[src]",
    ".event-detail img[src]",
    "img[src]",
    "img[data-src]",
]

META_DESCRIPTION_KEYS = [
    ("property", "og:description"),
    ("name", "description"),
    ("name", "twitter:description"),
]

META_IMAGE_KEYS = [
    ("property", "og:image"),
    ("name", "twitter:image"),
    ("itemprop", "image"),
]

SKIP_IMAGE_PATTERNS = [
    "sprite",
    "icon",
    "logo",
    "blank",
    "spacer",
    "tracking",
    "avatar",
]

DIRTY_IMAGE_FINGERPRINTS = [
    "banner1_069a0e3420",
]


@dataclass(frozen=True)
class SourceProject:
    name: str
    category: str
    root: Path


@dataclass
class PageExtract:
    url: str
    final_url: str
    raw_description: str
    image_urls: list[str]


class RateLimiter:
    def __init__(self, qps: float) -> None:
        self.min_interval = 0.0 if qps <= 0 else 1.0 / qps
        self._next_at = 0.0

    def wait(self) -> None:
        if self.min_interval <= 0:
            return
        now = time.monotonic()
        if now < self._next_at:
            time.sleep(self._next_at - now)
        self._next_at = time.monotonic() + self.min_interval


class OpenAITextPolisher:
    def __init__(
        self,
        *,
        api_key: str,
        model: str,
        base_url: str,
        timeout_sec: float,
        description_template: str,
        one_liner_template: str,
        one_liner_api_key: str = "",
        one_liner_model: str = "",
        one_liner_base_url: str = "",
        translation_api_key: str = "",
        translation_model: str = "",
        translation_base_url: str = "",
    ) -> None:
        self.model = clean_text(model)
        self.base_url = clean_text(base_url)
        self._primary_client = self._build_client(api_key=api_key, timeout_sec=timeout_sec)

        self.one_liner_model = clean_text(one_liner_model) or self.model
        self.one_liner_base_url = clean_text(one_liner_base_url) or self.base_url
        one_liner_key = clean_text(one_liner_api_key) or clean_text(api_key)
        self._one_liner_client = self._build_client(api_key=one_liner_key, timeout_sec=timeout_sec)

        self.translation_model = clean_text(translation_model) or self.model
        self.translation_base_url = clean_text(translation_base_url) or self.base_url
        translation_key = clean_text(translation_api_key) or clean_text(api_key)
        self._translation_client = self._build_client(api_key=translation_key, timeout_sec=timeout_sec)

        self.model_tag = f"description:{self.model};one_liner:{self.one_liner_model}"
        self.description_template = description_template
        self.one_liner_template = one_liner_template

    def close(self) -> None:
        seen: set[int] = set()
        for client in (self._primary_client, self._one_liner_client, self._translation_client):
            if id(client) in seen:
                continue
            seen.add(id(client))
            client.close()

    def polish_description(self, raw_text: str) -> str:
        bundle = self.polish_bundle(raw_text)
        return bundle.get("polished_description", "") or raw_text

    def one_liner(self, raw_text: str) -> str:
        bundle = self.polish_bundle(raw_text)
        return bundle.get("one_liner", "") or ""

    def polish_bundle(self, raw_text: str) -> dict[str, str]:
        desc_prompt = self.description_template.replace("{原始文本}", raw_text)
        one_liner_prompt = self.one_liner_template.replace("{原始文本}", raw_text)
        polished_description = clean_text_block(self._call(desc_prompt, target="description"))
        one_liner = clean_text_block(self._call(one_liner_prompt, target="one_liner"))
        return {
            "polished_description": polished_description,
            "one_liner": one_liner,
            "polished_description_zh": "",
            "one_liner_zh": "",
            "polished_description_en": "",
            "one_liner_en": "",
        }

    def translate_pair(self, polished_description: str, one_liner: str) -> dict[str, str]:
        prompt = (
            "请把下面的日文活动文案翻译成简体中文和英文，并仅返回 JSON。\n"
            "保持信息完整，不添加原文没有的信息。\n\n"
            f"日文介绍：{polished_description}\n"
            f"日文一句话：{one_liner}\n\n"
            "JSON 格式：\n"
            "{\"polished_description_zh\":\"...\",\"one_liner_zh\":\"...\","
            "\"polished_description_en\":\"...\",\"one_liner_en\":\"...\"}\n"
            "不要输出额外说明、不要输出 markdown 代码块。"
        )
        out = self._call(prompt, target="translation")
        data = parse_json_object(out)
        if not isinstance(data, dict):
            return {}
        return {
            "polished_description_zh": clean_text_block(str(data.get("polished_description_zh") or "")),
            "one_liner_zh": clean_text_block(str(data.get("one_liner_zh") or "")),
            "polished_description_en": clean_text_block(str(data.get("polished_description_en") or "")),
            "one_liner_en": clean_text_block(str(data.get("one_liner_en") or "")),
        }

    @staticmethod
    def _build_client(*, api_key: str, timeout_sec: float) -> httpx.Client:
        return httpx.Client(
            timeout=timeout_sec,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
        )

    def _call(self, prompt: str, *, target: str = "description") -> str:
        if target == "one_liner":
            endpoint = self.one_liner_base_url.rstrip("/")
            model = self.one_liner_model
            client = self._one_liner_client
        elif target == "translation":
            endpoint = self.translation_base_url.rstrip("/")
            model = self.translation_model
            client = self._translation_client
        else:
            endpoint = self.base_url.rstrip("/")
            model = self.model
            client = self._primary_client

        if endpoint.endswith("/chat/completions"):
            payload = {
                "model": model,
                "messages": [{"role": "user", "content": prompt}],
                "temperature": 0.2,
            }
        else:
            payload = {
                "model": model,
                "input": prompt,
                "reasoning": {"effort": "low"},
            }
        resp = client.post(endpoint, json=payload)
        resp.raise_for_status()
        data = resp.json()
        text = extract_openai_output_text(data) or extract_chat_completion_text(data)
        return clean_text_block(text)


class CodexTextPolisher:
    def __init__(
        self,
        *,
        repo_root: Path,
        model: str,
        timeout_sec: float,
        description_template: str,
        one_liner_template: str,
    ) -> None:
        self.repo_root = repo_root
        self.model = clean_text(model)
        self.timeout_sec = max(20.0, float(timeout_sec))
        self.description_template = description_template
        self.one_liner_template = one_liner_template
        resolved = resolve_codex_model(self.model, timeout_sec=self.timeout_sec)
        if resolved != self.model:
            requested = self.model or DEFAULT_CODEX_MODEL
            print(f"[codex] model resolved requested={requested} using={resolved}")
        self.model = resolved

    def close(self) -> None:
        return

    def polish_bundle(self, raw_text: str) -> dict[str, str]:
        desc_prompt = self.description_template.replace("{原始文本}", raw_text)
        one_liner_prompt = self.one_liner_template.replace("{原始文本}", raw_text)
        prompt = (
            f"{desc_prompt}\n\n"
            f"{one_liner_prompt}\n\n"
            "同时请基于同一原始文本，补充以下 4 个字段：\n"
            "1) polished_description_zh（简体中文介绍）\n"
            "2) one_liner_zh（简体中文一句话）\n"
            "3) polished_description_en（英文介绍）\n"
            "4) one_liner_en（英文一句话）\n\n"
            "请仅返回 JSON，格式如下：\n"
            "{\"polished_description\":\"...\",\"one_liner\":\"...\","
            "\"polished_description_zh\":\"...\",\"one_liner_zh\":\"...\","
            "\"polished_description_en\":\"...\",\"one_liner_en\":\"...\"}\n"
            "不要输出额外说明、不要输出 markdown 代码块。"
        )
        out = self._call(prompt)
        data = parse_json_object(out)
        if not isinstance(data, dict):
            return {}
        return {
            "polished_description": clean_text_block(str(data.get("polished_description") or "")),
            "one_liner": clean_text_block(str(data.get("one_liner") or "")),
            "polished_description_zh": clean_text_block(str(data.get("polished_description_zh") or "")),
            "one_liner_zh": clean_text_block(str(data.get("one_liner_zh") or "")),
            "polished_description_en": clean_text_block(str(data.get("polished_description_en") or "")),
            "one_liner_en": clean_text_block(str(data.get("one_liner_en") or "")),
        }

    def polish_pair(self, raw_text: str) -> tuple[str, str]:
        bundle = self.polish_bundle(raw_text)
        return bundle.get("polished_description", ""), bundle.get("one_liner", "")

    def translate_pair(self, polished_description: str, one_liner: str) -> dict[str, str]:
        prompt = (
            "请把下面的日文活动文案翻译成简体中文和英文，并仅返回 JSON。\n"
            "保持信息完整，不添加原文没有的信息。\n\n"
            f"日文介绍：{polished_description}\n"
            f"日文一句话：{one_liner}\n\n"
            "JSON 格式：\n"
            "{\"polished_description_zh\":\"...\",\"one_liner_zh\":\"...\","
            "\"polished_description_en\":\"...\",\"one_liner_en\":\"...\"}\n"
            "不要输出额外说明、不要输出 markdown 代码块。"
        )
        out = self._call(prompt)
        data = parse_json_object(out)
        if not isinstance(data, dict):
            return {}
        return {
            "polished_description_zh": clean_text_block(str(data.get("polished_description_zh") or "")),
            "one_liner_zh": clean_text_block(str(data.get("one_liner_zh") or "")),
            "polished_description_en": clean_text_block(str(data.get("polished_description_en") or "")),
            "one_liner_en": clean_text_block(str(data.get("one_liner_en") or "")),
        }

    def _call(self, prompt: str) -> str:
        import tempfile

        with tempfile.NamedTemporaryFile(delete=False) as tmp:
            output_path = tmp.name
        try:
            models_to_try: list[str] = []
            preferred = clean_text(self.model)
            if preferred:
                models_to_try.append(preferred)
            # ChatGPT-account Codex sessions may reject lightweight variants; keep a stable fallback.
            if "gpt-5" not in models_to_try:
                models_to_try.append("gpt-5")

            last_error = "unknown codex error"
            for model_name in models_to_try:
                for attempt in range(1, 3):
                    cmd = [
                        "codex",
                        "exec",
                        "--skip-git-repo-check",
                        "-C",
                        str(self.repo_root),
                        "--sandbox",
                        "read-only",
                        "--output-last-message",
                        output_path,
                        "-m",
                        model_name,
                        prompt,
                    ]

                    proc = subprocess.run(
                        cmd,
                        capture_output=True,
                        text=True,
                        timeout=self.timeout_sec,
                        check=False,
                    )
                    output_text = ""
                    if Path(output_path).exists():
                        output_text = Path(output_path).read_text(encoding="utf-8").strip()
                    if proc.returncode == 0 and output_text:
                        return output_text

                    combined = "\n".join([proc.stdout or "", proc.stderr or "", output_text or ""]).strip()
                    if combined:
                        last_error = combined[:500]
                    else:
                        last_error = f"codex_empty_response(model={model_name}, attempt={attempt})"

                    unsupported = CODEX_UNSUPPORTED_HINT in combined
                    if unsupported and model_name != "gpt-5":
                        break
                    if attempt < 2:
                        time.sleep(1.0 * attempt)

            raise RuntimeError(last_error)
        finally:
            try:
                Path(output_path).unlink(missing_ok=True)
            except Exception:  # noqa: BLE001
                pass


def extract_openai_output_text(data: dict[str, Any]) -> str:
    direct = data.get("output_text")
    if isinstance(direct, str) and direct.strip():
        return direct.strip()

    chunks: list[str] = []
    output = data.get("output")
    if not isinstance(output, list):
        return ""

    for item in output:
        if not isinstance(item, dict):
            continue
        content = item.get("content")
        if not isinstance(content, list):
            continue
        for c in content:
            if not isinstance(c, dict):
                continue
            if c.get("type") == "output_text":
                txt = c.get("text")
                if isinstance(txt, str) and txt.strip():
                    chunks.append(txt.strip())
            elif c.get("type") == "text":
                txt_obj = c.get("text")
                if isinstance(txt_obj, str) and txt_obj.strip():
                    chunks.append(txt_obj.strip())
                elif isinstance(txt_obj, dict):
                    val = txt_obj.get("value")
                    if isinstance(val, str) and val.strip():
                        chunks.append(val.strip())
    return "\n".join(chunks).strip()


def extract_chat_completion_text(data: dict[str, Any]) -> str:
    choices = data.get("choices")
    if not isinstance(choices, list):
        return ""
    chunks: list[str] = []
    for choice in choices:
        if not isinstance(choice, dict):
            continue
        message = choice.get("message")
        if not isinstance(message, dict):
            continue
        content = message.get("content")
        if isinstance(content, str) and content.strip():
            chunks.append(content.strip())
            continue
        if not isinstance(content, list):
            continue
        for item in content:
            if isinstance(item, str) and item.strip():
                chunks.append(item.strip())
                continue
            if not isinstance(item, dict):
                continue
            text = item.get("text")
            if isinstance(text, str) and text.strip():
                chunks.append(text.strip())
                continue
            if isinstance(text, dict):
                value = text.get("value")
                if isinstance(value, str) and value.strip():
                    chunks.append(value.strip())
    return "\n".join(chunks).strip()


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def clean_text(text: str | None) -> str:
    if not text:
        return ""
    return re.sub(r"\s+", " ", text).strip()


def parse_codex_model_candidates(raw: str | None) -> list[str]:
    parts = [clean_text(x) for x in str(raw or "").split(",")]
    unique: list[str] = []
    for item in parts:
        if item and item not in unique:
            unique.append(item)
    return unique


def probe_codex_model_support(model: str, timeout_sec: float) -> bool:
    import tempfile

    candidate = clean_text(model)
    if not candidate:
        return False
    probe_timeout = max(8.0, min(float(timeout_sec), 20.0))
    with tempfile.TemporaryDirectory(prefix="codex_model_probe_") as probe_dir:
        output_path = Path(probe_dir) / "probe_output.txt"
        cmd = [
            "codex",
            "exec",
            "--skip-git-repo-check",
            "-C",
            probe_dir,
            "--sandbox",
            "read-only",
            "--output-last-message",
            str(output_path),
            "-m",
            candidate,
            "Reply with exactly OK.",
        ]
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=probe_timeout,
            check=False,
        )
        output_text = output_path.read_text(encoding="utf-8").strip() if output_path.exists() else ""
        combined = "\n".join([proc.stdout or "", proc.stderr or "", output_text]).strip()
        if CODEX_UNSUPPORTED_HINT in combined:
            return False
        return proc.returncode == 0 and bool(output_text)


def resolve_codex_model(requested_model: str, *, timeout_sec: float) -> str:
    requested = clean_text(requested_model)
    requested_lower = requested.lower()
    if requested and requested_lower not in {"auto", "cheapest", "lite"}:
        return requested

    candidates = parse_codex_model_candidates(os.getenv("CODEX_MODEL_CANDIDATES"))
    if not candidates:
        candidates = list(DEFAULT_CODEX_MODEL_CANDIDATES)
    if "gpt-5" not in candidates:
        candidates.append("gpt-5")

    for candidate in candidates:
        try:
            if probe_codex_model_support(candidate, timeout_sec=timeout_sec):
                return candidate
        except Exception:  # noqa: BLE001
            continue
    return "gpt-5"


def clean_text_block(text: str | None) -> str:
    if not text:
        return ""
    lines = [clean_text(line) for line in str(text).splitlines()]
    lines = [x for x in lines if x]
    return "\n".join(lines)


def parse_iso_datetime(raw: str | None) -> datetime | None:
    if not raw:
        return None
    text = str(raw).strip()
    if not text:
        return None
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(text)
    except ValueError:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def parse_event_date(raw: Any) -> date | None:
    if raw is None:
        return None
    text = str(raw).strip()
    if not text:
        return None
    m = re.search(r"(20\d{2})\D{0,3}(\d{1,2})\D{0,3}(\d{1,2})", text)
    if not m:
        return None
    y = int(m.group(1))
    mo = int(m.group(2))
    d = int(m.group(3))
    try:
        return date(y, mo, d)
    except ValueError:
        return None


def is_start_date_older_than_cutoff(row: dict[str, Any], cutoff: date) -> bool:
    start_date = parse_event_date(row.get("event_date_start"))
    if start_date is None:
        return False
    return start_date < cutoff


def is_start_date_not_older_than_cutoff(row: dict[str, Any], cutoff: date) -> bool:
    start_date = parse_event_date(row.get("event_date_start"))
    if start_date is None:
        return True
    return start_date >= cutoff


def parse_source_urls(row: dict[str, Any]) -> list[str]:
    urls: list[str] = []

    source_urls = row.get("source_urls")
    if isinstance(source_urls, list):
        urls.extend(str(x).strip() for x in source_urls if str(x).strip())
    elif isinstance(source_urls, str):
        urls.extend(x.strip() for x in source_urls.split("|") if x.strip())

    source_url = str(row.get("source_url") or "").strip()
    if source_url:
        urls.append(source_url)

    deduped: list[str] = []
    seen: set[str] = set()
    for u in urls:
        if u in seen:
            continue
        seen.add(u)
        deduped.append(u)
    return deduped


def source_signature(urls: list[str]) -> str:
    digest = hashlib.sha256()
    for url in sorted(urls):
        digest.update(url.encode("utf-8"))
        digest.update(b"\n")
    return digest.hexdigest()


def normalize_name_for_match(raw: Any) -> str:
    text = clean_text(raw).lower()
    if not text:
        return ""
    text = re.sub(r"\s+", "", text)
    text = re.sub(r"[【】\[\]（）()「」『』・,，、。.!！?？:：/／\\\-~〜～]", "", text)
    return text


def build_name_date_key(event_name: Any, event_date_start: Any) -> str:
    name_key = normalize_name_for_match(event_name)
    if not name_key:
        return ""
    date_obj = parse_event_date(event_date_start)
    date_key = date_obj.isoformat() if date_obj else clean_text(event_date_start)
    return f"{name_key}|{date_key}" if date_key else name_key


def source_url_set(row: dict[str, Any]) -> set[str]:
    urls = set(parse_source_urls(row))
    description_source = clean_text(row.get("description_source_url"))
    if description_source:
        urls.add(description_source)
    return urls


def rows_look_same_event(current_row: dict[str, Any], previous_row: dict[str, Any]) -> bool:
    current_sources = source_url_set(current_row)
    previous_sources = source_url_set(previous_row)
    if current_sources and previous_sources and current_sources.intersection(previous_sources):
        return True

    current_key = build_name_date_key(current_row.get("event_name"), current_row.get("event_date_start"))
    previous_key = build_name_date_key(previous_row.get("event_name"), previous_row.get("event_date_start"))
    return bool(current_key and previous_key and current_key == previous_key)


def score_previous_record(row: dict[str, Any]) -> tuple[int, int, int, str]:
    status_rank = {
        "ok": 4,
        "cached": 3,
        "partial": 2,
        "empty": 1,
    }.get(clean_text(row.get("status")).lower(), 0)
    has_desc = int(bool(clean_text_block(row.get("raw_description"))))
    image_urls = row.get("image_urls")
    has_images = int(isinstance(image_urls, list) and len(image_urls) > 0)
    fetched_at = clean_text(row.get("fetched_at"))
    return (status_rank, has_desc, has_images, fetched_at)


def _put_previous_if_better(bucket: dict[str, dict[str, Any]], key: str, row: dict[str, Any]) -> None:
    if not key:
        return
    existing = bucket.get(key)
    if existing is None or score_previous_record(row) >= score_previous_record(existing):
        bucket[key] = row


def extract_meta(soup: BeautifulSoup, keys: list[tuple[str, str]]) -> list[str]:
    values: list[str] = []
    for attr, key in keys:
        for tag in soup.select(f"meta[{attr}='{key}']"):
            content = clean_text(tag.get("content"))
            if content:
                values.append(content)
    return values


def safe_json_loads(raw: str) -> Any:
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return None


def parse_json_object(raw: str) -> dict[str, Any] | None:
    text = clean_text_block(raw)
    if not text:
        return None
    direct = safe_json_loads(text)
    if isinstance(direct, dict):
        return direct

    m = re.search(r"\{[\s\S]*\}", text)
    if not m:
        return None
    candidate = m.group(0).strip()
    parsed = safe_json_loads(candidate)
    if isinstance(parsed, dict):
        return parsed
    return None


def iter_jsonld_objects(soup: BeautifulSoup) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for tag in soup.select('script[type="application/ld+json"]'):
        raw = (tag.string or tag.text or "").strip()
        if not raw:
            continue
        parsed = safe_json_loads(raw)
        if isinstance(parsed, dict):
            out.append(parsed)
        elif isinstance(parsed, list):
            out.extend(x for x in parsed if isinstance(x, dict))
    return out


def collect_jsonld_descriptions(jsonld: list[dict[str, Any]]) -> list[str]:
    values: list[str] = []

    def walk(node: Any) -> None:
        if isinstance(node, dict):
            desc = node.get("description")
            if isinstance(desc, str):
                cleaned = clean_text_block(desc)
                if cleaned:
                    values.append(cleaned)
            for val in node.values():
                walk(val)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(jsonld)
    return values


def collect_jsonld_images(jsonld: list[dict[str, Any]], base_url: str) -> list[str]:
    values: list[str] = []

    def add_url(raw: Any) -> None:
        if isinstance(raw, str):
            u = normalize_url(raw, base_url)
            if u:
                values.append(u)

    def walk(node: Any) -> None:
        if isinstance(node, dict):
            image = node.get("image")
            if isinstance(image, str):
                add_url(image)
            elif isinstance(image, dict):
                add_url(image.get("url"))
            elif isinstance(image, list):
                for x in image:
                    if isinstance(x, str):
                        add_url(x)
                    elif isinstance(x, dict):
                        add_url(x.get("url"))
            for val in node.values():
                walk(val)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(jsonld)
    return values


def normalize_url(raw_url: str | None, base_url: str) -> str:
    text = clean_text(raw_url)
    if not text:
        return ""
    if text.startswith("data:"):
        return ""
    abs_url = urljoin(base_url, text)
    parsed = urlparse(abs_url)
    if parsed.scheme not in {"http", "https"}:
        return ""
    return abs_url


def detect_declared_encoding(raw_html: bytes, content_type: str) -> list[str]:
    candidates: list[str] = []

    def add_encoding(value: str | None) -> None:
        if not value:
            return
        text = clean_text(value).lower()
        if not text:
            return
        mapping = {
            "shift-jis": "cp932",
            "shift_jis": "cp932",
            "sjis": "cp932",
            "x-sjis": "cp932",
            "ms932": "cp932",
            "windows-31j": "cp932",
            "cp932": "cp932",
            "utf8": "utf-8",
        }
        normalized = mapping.get(text, text)
        if normalized not in candidates:
            candidates.append(normalized)

    # HTTP header charset, if present.
    m = re.search(r"charset\s*=\s*([^\s;]+)", content_type or "", flags=re.IGNORECASE)
    if m:
        add_encoding(m.group(1).strip("\"'"))

    head = raw_html[:4096]
    try:
        head_ascii = head.decode("ascii", errors="ignore")
    except Exception:  # noqa: BLE001
        head_ascii = ""

    # XML declaration, e.g. <?xml version="1.0" encoding="Shift_JIS"?>
    m = re.search(r'encoding\s*=\s*["\']\s*([A-Za-z0-9._-]+)\s*["\']', head_ascii, flags=re.IGNORECASE)
    if m:
        add_encoding(m.group(1))

    # HTML meta charset
    m = re.search(r'<meta[^>]+charset\s*=\s*["\']?\s*([A-Za-z0-9._-]+)', head_ascii, flags=re.IGNORECASE)
    if m:
        add_encoding(m.group(1))

    # HTML meta content-type with charset
    m = re.search(r'content\s*=\s*["\'][^"\']*charset\s*=\s*([A-Za-z0-9._-]+)', head_ascii, flags=re.IGNORECASE)
    if m:
        add_encoding(m.group(1))

    return candidates


def decode_response_html(response: httpx.Response) -> str:
    raw = response.content or b""
    if not raw:
        return ""

    candidates = detect_declared_encoding(raw, str(response.headers.get("content-type") or ""))

    # httpx inferred encoding as additional hint.
    if response.encoding:
        candidates.append(response.encoding.lower())

    # Stable fallbacks for JP sites.
    candidates.extend(["utf-8", "cp932", "shift_jis", "euc_jp"])

    tried: set[str] = set()
    for enc in candidates:
        if not enc or enc in tried:
            continue
        tried.add(enc)
        try:
            return raw.decode(enc)
        except Exception:  # noqa: BLE001
            continue

    return raw.decode("utf-8", errors="replace")


def is_schedule_anchor_url(source_url: str) -> bool:
    parsed = urlparse(source_url)
    return parsed.netloc.endswith("omatsuri.com") and "/sch/" in parsed.path and bool(parsed.fragment)


def is_generic_image_url(url: str) -> bool:
    low = url.lower()
    if any(fp in low for fp in DIRTY_IMAGE_FINGERPRINTS):
        return True
    if low.endswith("/img/header.jpg") or low.endswith("/img/header.jpeg") or low.endswith("/img/header.png"):
        return True
    if "ogp0.png" in low:
        return True
    return False


def find_anchor_node(soup: BeautifulSoup, source_url: str) -> Any:
    fragment = clean_text(urlparse(source_url).fragment)
    if not fragment:
        return None
    node = soup.find(id=fragment)
    if node is not None:
        return node
    node = soup.find(attrs={"name": fragment})
    if node is not None:
        return node
    return None


def find_anchor_container(node: Any) -> Any:
    if node is None:
        return None
    for tag in ("tr", "li", "p", "section", "article", "div"):
        parent = node.find_parent(tag)
        if parent is None:
            continue
        txt = clean_text_block(parent.get_text(" "))
        if len(txt) >= 6:
            return parent
    return node


def collect_anchor_description(soup: BeautifulSoup, source_url: str, max_chars: int) -> str:
    node = find_anchor_node(soup, source_url)
    if node is None:
        return ""
    container = find_anchor_container(node)
    if container is None:
        return ""
    text = clean_text_block(container.get_text(" "))
    if not text:
        return ""
    if len(text) > max_chars:
        text = text[:max_chars].rstrip()
    return text


def collect_event_context_description(soup: BeautifulSoup, event_name: str, max_chars: int) -> str:
    name = clean_text(event_name)
    if not name:
        return ""

    def norm_for_match(text: str) -> str:
        return re.sub(r"[\s　・･（）()［］\[\]【】「」『』,，、。~〜～\-]", "", text)

    normalized_name = norm_for_match(name)
    if not normalized_name:
        return ""

    lines = [clean_text(line) for line in soup.get_text("\n").splitlines() if clean_text(line)]
    candidates: list[str] = []
    seen: set[str] = set()
    skip_markers = (
        "今日は何の祭り",
        "一覧形式で紹介",
        "ご注意",
        "メルマガ",
        "トップページ",
    )

    for idx, line in enumerate(lines):
        line_norm = norm_for_match(line)
        if normalized_name not in line_norm:
            continue
        if any(marker in line for marker in skip_markers):
            continue

        merged = clean_text_block(re.sub(r"^[■□◆◇●○・]+\s*", "", line))
        if not merged:
            continue
        if merged in seen:
            continue
        seen.add(merged)
        candidates.append(merged)

    if not candidates:
        return ""

    # Prefer concise event lines over large page-level blocks.
    candidates.sort(key=lambda x: (len(x), x))
    best = candidates[0]
    if len(best) > max_chars:
        best = best[:max_chars].rstrip()
    return best


def collect_anchor_image_urls(soup: BeautifulSoup, source_url: str, base_url: str, max_images: int) -> list[str]:
    node = find_anchor_node(soup, source_url)
    if node is None:
        return []
    container = find_anchor_container(node)
    if container is None:
        return []

    urls: list[str] = []
    for img in container.select("img[src], img[data-src]"):
        src = img.get("src") or img.get("data-src")
        u = normalize_url(src, base_url)
        if not u or not looks_like_image_url(u):
            continue
        urls.append(u)

    deduped: list[str] = []
    seen: set[str] = set()
    for u in urls:
        if u in seen:
            continue
        seen.add(u)
        deduped.append(u)
        if len(deduped) >= max_images:
            break
    return deduped


def collect_description_from_selectors(soup: BeautifulSoup, max_chars: int) -> str:
    chunks: list[str] = []
    seen: set[str] = set()
    total_len = 0

    for selector in DESCRIPTION_SELECTORS:
        for node in soup.select(selector):
            txt = clean_text_block(node.get_text(" "))
            if not txt:
                continue
            if len(txt) < 18:
                continue
            if txt in seen:
                continue
            seen.add(txt)
            chunks.append(txt)
            total_len += len(txt)
            if total_len >= max_chars:
                break
        if total_len >= max_chars:
            break

    if not chunks:
        return ""
    joined = "\n".join(chunks)
    if len(joined) > max_chars:
        joined = joined[:max_chars].rstrip()
    return joined


def choose_raw_description(soup: BeautifulSoup, max_chars: int) -> str:
    jsonld = iter_jsonld_objects(soup)
    candidates: list[str] = []
    candidates.extend(extract_meta(soup, META_DESCRIPTION_KEYS))
    candidates.extend(collect_jsonld_descriptions(jsonld))

    paragraph_text = collect_description_from_selectors(soup, max_chars=max_chars)
    if paragraph_text:
        candidates.append(paragraph_text)

    cleaned: list[str] = []
    seen: set[str] = set()
    for c in candidates:
        text = clean_text_block(c)
        if not text:
            continue
        if text in seen:
            continue
        seen.add(text)
        cleaned.append(text)

    if not cleaned:
        return ""

    cleaned.sort(key=lambda x: len(x), reverse=True)
    best = cleaned[0]
    if len(best) > max_chars:
        best = best[:max_chars].rstrip()
    return best


def looks_like_image_url(url: str) -> bool:
    low = url.lower()
    if any(fp in low for fp in DIRTY_IMAGE_FINGERPRINTS):
        return False
    if any(p in low for p in SKIP_IMAGE_PATTERNS):
        return False
    if low.startswith("data:"):
        return False
    return True


def collect_image_urls(soup: BeautifulSoup, base_url: str, max_images: int) -> list[str]:
    jsonld = iter_jsonld_objects(soup)
    urls: list[str] = []
    urls.extend(normalize_url(x, base_url) for x in extract_meta(soup, META_IMAGE_KEYS))
    urls.extend(collect_jsonld_images(jsonld, base_url))

    for selector in IMAGE_SELECTORS:
        for node in soup.select(selector):
            src = node.get("src") or node.get("data-src")
            u = normalize_url(src, base_url)
            if u:
                urls.append(u)

    deduped: list[str] = []
    seen: set[str] = set()
    for url in urls:
        if not url:
            continue
        if url in seen:
            continue
        if not looks_like_image_url(url):
            continue
        seen.add(url)
        deduped.append(url)
        if len(deduped) >= max_images:
            break
    return deduped


def sanitize_filename_fragment(text: str) -> str:
    out = re.sub(r"[^a-zA-Z0-9._-]", "_", text)
    out = re.sub(r"_+", "_", out).strip("_")
    return out[:80] if out else "image"


def infer_extension(url: str, content_type: str) -> str:
    ct = content_type.lower()
    if "image/jpeg" in ct:
        return "jpg"
    if "image/png" in ct:
        return "png"
    if "image/webp" in ct:
        return "webp"
    if "image/gif" in ct:
        return "gif"
    if "image/avif" in ct:
        return "avif"

    path = urlparse(url).path.lower()
    m = re.search(r"\.([a-z0-9]{2,5})$", path)
    if not m:
        return "img"
    ext = m.group(1)
    if ext in {"jpg", "jpeg", "png", "webp", "gif", "avif"}:
        return "jpg" if ext == "jpeg" else ext
    return "img"


def safe_float(value: Any, default: float) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def build_projects(repo_root: Path) -> dict[str, SourceProject]:
    data_root = repo_root / "数据端"
    return {
        "hanabi": SourceProject(name="hanabi", category="hanabi", root=data_root / "HANABI"),
        "omatsuri": SourceProject(name="omatsuri", category="matsuri", root=data_root / "OMATSURI"),
    }


def load_latest_run(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def resolve_fused_jsonl(project: SourceProject, latest_run: dict[str, Any]) -> tuple[Path | None, str]:
    run_id = str(latest_run.get("fused_run_id") or "").strip()
    if not run_id:
        return None, ""
    fused = project.root / "data" / "fused" / run_id / "events_fused.jsonl"
    if not fused.exists():
        return None, run_id
    return fused, run_id


def read_jsonl(path: Path, max_rows: int, start_index: int = 0) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    start = max(0, int(start_index))
    idx = 0
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            if idx < start:
                idx += 1
                continue
            text = line.strip()
            if not text:
                idx += 1
                continue
            try:
                row = json.loads(text)
            except json.JSONDecodeError:
                idx += 1
                continue
            if not isinstance(row, dict):
                idx += 1
                continue
            rows.append(row)
            idx += 1
            if max_rows > 0 and len(rows) >= max_rows:
                break
    return rows


def load_previous_records(project: SourceProject, latest_run: dict[str, Any]) -> dict[str, dict[str, dict[str, Any]]]:
    content_root = project.root / "data" / "content"
    if not content_root.exists():
        return {
            "by_canonical": {},
            "by_source_url": {},
            "by_name_date": {},
        }

    candidates: list[Path] = []
    seen: set[Path] = set()

    def add_candidate(path: Path) -> None:
        if not path.exists():
            return
        if path in seen:
            return
        seen.add(path)
        candidates.append(path)

    run_id = str(latest_run.get("content_run_id") or "").strip()
    if run_id:
        add_candidate(content_root / run_id / "events_content.jsonl")

    add_candidate(content_root / "latest" / "events_content.jsonl")

    all_history = sorted(
        (p for p in content_root.glob("*/events_content.jsonl") if p.parent.name != "latest"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    for path in all_history:
        add_candidate(path)

    if not candidates:
        return {
            "by_canonical": {},
            "by_source_url": {},
            "by_name_date": {},
        }

    by_canonical: dict[str, dict[str, Any]] = {}
    by_source_url: dict[str, dict[str, Any]] = {}
    by_name_date: dict[str, dict[str, Any]] = {}

    for candidate in candidates:
        with candidate.open("r", encoding="utf-8") as f:
            for line in f:
                text = line.strip()
                if not text:
                    continue
                try:
                    row = json.loads(text)
                except json.JSONDecodeError:
                    continue
                if not isinstance(row, dict):
                    continue
                canonical_id = str(row.get("canonical_id") or "").strip()
                if canonical_id:
                    _put_previous_if_better(by_canonical, canonical_id, row)

                for source_url in source_url_set(row):
                    _put_previous_if_better(by_source_url, source_url, row)

                name_date_key = build_name_date_key(row.get("event_name"), row.get("event_date_start"))
                if name_date_key:
                    _put_previous_if_better(by_name_date, name_date_key, row)

    return {
        "by_canonical": by_canonical,
        "by_source_url": by_source_url,
        "by_name_date": by_name_date,
    }


def resolve_previous_record(
    current_row: dict[str, Any],
    previous_index: dict[str, dict[str, dict[str, Any]]],
) -> dict[str, Any] | None:
    candidates: list[dict[str, Any]] = []
    seen_ids: set[int] = set()

    by_canonical = previous_index.get("by_canonical", {})
    by_source_url = previous_index.get("by_source_url", {})
    by_name_date = previous_index.get("by_name_date", {})

    canonical_id = clean_text(current_row.get("canonical_id"))
    if canonical_id:
        candidate = by_canonical.get(canonical_id)
        if candidate is not None and rows_look_same_event(current_row, candidate):
            candidates.append(candidate)
            seen_ids.add(id(candidate))

    for source_url in parse_source_urls(current_row):
        candidate = by_source_url.get(source_url)
        if candidate is None:
            continue
        if id(candidate) in seen_ids:
            continue
        if not rows_look_same_event(current_row, candidate):
            continue
        candidates.append(candidate)
        seen_ids.add(id(candidate))

    name_date_key = build_name_date_key(current_row.get("event_name"), current_row.get("event_date_start"))
    if name_date_key:
        candidate = by_name_date.get(name_date_key)
        if candidate is not None and id(candidate) not in seen_ids and rows_look_same_event(current_row, candidate):
            candidates.append(candidate)
            seen_ids.add(id(candidate))

    if not candidates:
        return None

    candidates.sort(key=score_previous_record, reverse=True)
    return candidates[0]


def is_recent_enough(
    previous: dict[str, Any] | None,
    *,
    current_signature: str,
    min_refresh_days: int,
    force: bool,
    desired_polish_mode: str,
) -> bool:
    if force:
        return False
    if not previous:
        return False
    prev_sig = str(previous.get("source_urls_sig") or "")
    if prev_sig != current_signature:
        return False

    fetched_at = parse_iso_datetime(str(previous.get("fetched_at") or ""))
    if fetched_at is None:
        return False

    age = datetime.now(timezone.utc) - fetched_at
    if age > timedelta(days=max(min_refresh_days, 0)):
        return False

    raw_description = clean_text_block(str(previous.get("raw_description") or ""))
    image_urls = previous.get("image_urls")
    has_images = isinstance(image_urls, list) and len(image_urls) > 0
    return bool(raw_description or has_images)


def is_failed_or_incomplete(previous: dict[str, Any] | None) -> bool:
    if not previous:
        return True

    status = clean_text(str(previous.get("status") or "")).lower()
    error_text = clean_text_block(str(previous.get("error") or ""))
    raw_description = clean_text_block(str(previous.get("raw_description") or ""))
    image_urls = previous.get("image_urls")
    has_images = isinstance(image_urls, list) and len(image_urls) > 0

    has_ja = bool(
        clean_text_block(str(previous.get("polished_description") or ""))
        and clean_text_block(str(previous.get("one_liner") or ""))
    )
    has_zh = bool(
        clean_text_block(str(previous.get("polished_description_zh") or ""))
        and clean_text_block(str(previous.get("one_liner_zh") or ""))
    )
    has_en = bool(
        clean_text_block(str(previous.get("polished_description_en") or ""))
        and clean_text_block(str(previous.get("one_liner_en") or ""))
    )

    if status in {"partial", "empty", "openai_failed", "codex_failed"}:
        return True
    if error_text:
        return True
    if not raw_description and not has_images:
        return True
    if raw_description and (not has_ja or not has_zh or not has_en):
        return True
    return False


def should_reuse_success_in_failed_only(
    previous: dict[str, Any] | None,
    *,
    force: bool,
) -> bool:
    if force:
        return False
    if not previous:
        return False
    return not is_failed_or_incomplete(previous)


def fetch_page_with_retries(
    client: httpx.Client,
    limiter: RateLimiter,
    url: str,
    *,
    max_retries: int,
) -> tuple[httpx.Response | None, str]:
    last_error = ""
    for attempt in range(1, max_retries + 1):
        limiter.wait()
        try:
            resp = client.get(url)
            if resp.status_code == 200:
                return resp, ""
            last_error = f"http_{resp.status_code}"
        except Exception as exc:  # noqa: BLE001
            last_error = str(exc)
        if attempt < max_retries:
            time.sleep(min(4.0, 0.5 * attempt))
    return None, last_error


def extract_from_page(
    source_url: str,
    final_url: str,
    html: str,
    *,
    event_name: str,
    max_desc_chars: int,
    max_images: int,
) -> PageExtract:
    soup = BeautifulSoup(html, "lxml")
    event_description = collect_event_context_description(soup, event_name=event_name, max_chars=max_desc_chars)
    anchor_description = collect_anchor_description(soup, source_url=source_url, max_chars=max_desc_chars)
    if event_description:
        raw_description = event_description
    elif is_schedule_anchor_url(source_url):
        # Month schedule pages are generic; if event line cannot be resolved, keep empty.
        raw_description = anchor_description
    else:
        raw_description = anchor_description or choose_raw_description(soup, max_chars=max_desc_chars)

    anchor_images = collect_anchor_image_urls(
        soup,
        source_url=source_url,
        base_url=final_url or source_url,
        max_images=max_images,
    )
    if anchor_images:
        image_urls = anchor_images
    else:
        image_urls = collect_image_urls(soup, base_url=final_url or source_url, max_images=max_images)
        # For omatsuri month-schedule anchors, page-level header/OGP is generic and should not be reused.
        if is_schedule_anchor_url(source_url):
            image_urls = [u for u in image_urls if not is_generic_image_url(u)]
            if image_urls:
                image_urls = image_urls[:max_images]

    return PageExtract(
        url=source_url,
        final_url=final_url or source_url,
        raw_description=raw_description,
        image_urls=image_urls,
    )


def pick_best_page_extract(candidates: list[PageExtract]) -> PageExtract | None:
    if not candidates:
        return None

    def score(item: PageExtract) -> tuple[int, int]:
        return (len(item.raw_description), len(item.image_urls))

    return sorted(candidates, key=score, reverse=True)[0]


def fallback_one_liner(raw_text: str) -> str:
    text = clean_text(raw_text)
    if not text:
        return ""
    if len(text) <= 45:
        return text
    return text[:44].rstrip() + "…"


def download_images(
    *,
    client: httpx.Client,
    limiter: RateLimiter,
    image_urls: list[str],
    target_dir: Path,
    max_images: int,
    max_bytes: int,
) -> list[str]:
    target_dir.mkdir(parents=True, exist_ok=True)
    downloaded: list[str] = []

    for idx, url in enumerate(image_urls[:max_images], start=1):
        limiter.wait()
        try:
            resp = client.get(url)
        except Exception:  # noqa: BLE001
            continue
        if resp.status_code != 200:
            continue
        content_type = str(resp.headers.get("content-type") or "")
        if "image/" not in content_type.lower():
            continue
        raw = resp.content
        if not raw:
            continue
        if max_bytes > 0 and len(raw) > max_bytes:
            continue

        ext = infer_extension(url, content_type)
        stem = sanitize_filename_fragment(Path(urlparse(url).path).stem)
        digest = hashlib.sha1(url.encode("utf-8")).hexdigest()[:10]
        file_name = f"{idx:02d}_{stem}_{digest}.{ext}"
        out = target_dir / file_name
        out.write_bytes(raw)
        downloaded.append(str(out))

    return downloaded


def ensure_relative(path: Path, start: Path) -> str:
    try:
        return str(path.relative_to(start))
    except ValueError:
        return str(path)


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")


CONTENT_CSV_FIELDS = [
    "canonical_id",
    "category",
    "event_name",
    "event_date_start",
    "event_date_end",
    "fused_run_id",
    "description_source_url",
    "raw_description",
    "polished_description",
    "one_liner",
    "polished_description_zh",
    "one_liner_zh",
    "polished_description_en",
    "one_liner_en",
    "image_urls",
    "downloaded_images",
    "source_urls",
    "source_urls_sig",
    "status",
    "error",
    "fetched_at",
    "polish_mode",
    "polish_model",
]


def csv_row_from_record(row: dict[str, Any]) -> dict[str, Any]:
    out = dict(row)
    out["image_urls"] = "|".join(row.get("image_urls", []))
    out["downloaded_images"] = "|".join(row.get("downloaded_images", []))
    out["source_urls"] = "|".join(row.get("source_urls", []))
    return {k: out.get(k, "") for k in CONTENT_CSV_FIELDS}


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=CONTENT_CSV_FIELDS)
        writer.writeheader()
        for row in rows:
            writer.writerow(csv_row_from_record(row))


def read_template(path: Path) -> str:
    if not path.exists():
        raise FileNotFoundError(f"prompt template not found: {path}")
    return path.read_text(encoding="utf-8")


def should_use_openai(mode: str, has_api_key: bool) -> bool:
    if mode == "codex":
        return False
    if mode == "openai":
        return True
    if mode == "none":
        return False
    return has_api_key


def run_project(
    *,
    repo_root: Path,
    project: SourceProject,
    args: argparse.Namespace,
    description_template: str,
    one_liner_template: str,
) -> dict[str, Any]:
    latest_path = project.root / "data" / "latest_run.json"
    latest_run = load_latest_run(latest_path)
    fused_jsonl, fused_run_id = resolve_fused_jsonl(project, latest_run)
    if not fused_jsonl:
        return {
            "project": project.name,
            "status": "skipped_no_fused",
            "fused_run_id": fused_run_id,
            "rows": 0,
        }

    rows = read_jsonl(
        fused_jsonl,
        max_rows=0,
        start_index=0,
    )
    skipped_by_age = 0
    skipped_by_not_old_enough = 0
    cutoff_date: date | None = None
    only_past_cutoff_date: date | None = None
    failed_only = bool(args.failed_only)
    prioritize_near_start = bool(args.prioritize_near_start)
    codex_single_pass_i18n = bool(args.codex_single_pass_i18n)
    only_past_days = int(args.only_past_days)

    if only_past_days >= 0:
        only_past_cutoff_date = datetime.now(timezone.utc).date() - timedelta(days=only_past_days)
        filtered_old: list[dict[str, Any]] = []
        for row in rows:
            if is_start_date_not_older_than_cutoff(row, only_past_cutoff_date):
                skipped_by_not_old_enough += 1
                continue
            filtered_old.append(row)
        rows = filtered_old

    if int(args.skip_past_days) >= 0:
        cutoff_date = datetime.now(timezone.utc).date() - timedelta(days=int(args.skip_past_days))
        filtered: list[dict[str, Any]] = []
        for row in rows:
            if is_start_date_older_than_cutoff(row, cutoff_date):
                skipped_by_age += 1
                continue
            filtered.append(row)
        rows = filtered

    previous = load_previous_records(project, latest_run)

    if prioritize_near_start and rows:
        today = datetime.now(timezone.utc).date()
        indexed_rows = list(enumerate(rows))

        def sort_key(item: tuple[int, dict[str, Any]]) -> tuple[int, int, int, int]:
            idx, row = item
            old = resolve_previous_record(row, previous)
            work_rank = 1 if should_reuse_success_in_failed_only(old, force=bool(args.force)) and failed_only else 0
            start_date = parse_event_date(row.get("event_date_start"))
            if start_date is None:
                return (work_rank, 2, 36500, idx)
            delta = (start_date - today).days
            if delta >= 0:
                return (work_rank, 0, delta, idx)
            return (work_rank, 1, abs(delta), idx)

        indexed_rows.sort(key=sort_key)
        rows = [row for _, row in indexed_rows]

    eligible_rows = len(rows)
    slice_start = max(0, int(args.start_index))
    max_events = int(args.max_events)
    if max_events > 0:
        rows = rows[slice_start : slice_start + max_events]
    else:
        rows = rows[slice_start:]

    print(
        f"[batch] project={project.name} run_id={args.run_id} start_index={args.start_index} "
        f"max_events={args.max_events} selected_rows={len(rows)} eligible_rows={eligible_rows} skipped_by_age={skipped_by_age} "
        f"failed_only={str(failed_only).lower()} prioritize_near_start={str(prioritize_near_start).lower()} "
        f"codex_single_pass_i18n={str(codex_single_pass_i18n).lower()}"
    )
    if cutoff_date is not None:
        print(
            f"[filter] project={project.name} skip_past_days={int(args.skip_past_days)} "
            f"basis=event_date_start cutoff_date={cutoff_date.isoformat()}"
        )
    if only_past_cutoff_date is not None:
        print(
            f"[filter] project={project.name} only_past_days={only_past_days} "
            f"basis=event_date_start older_than={only_past_cutoff_date.isoformat()}"
        )

    run_dir = project.root / "data" / "content" / args.run_id
    image_root = project.root / "data" / "content_assets" / args.run_id

    api_key = str(args.openai_api_key or "").strip()
    openai_enabled = should_use_openai(args.polish_mode, bool(api_key))
    polisher: OpenAITextPolisher | None = None
    codex_polisher: CodexTextPolisher | None = None

    if openai_enabled and api_key:
        polisher = OpenAITextPolisher(
            api_key=api_key,
            model=args.openai_model,
            base_url=args.openai_base_url,
            timeout_sec=safe_float(args.request_timeout_sec, DEFAULT_TIMEOUT_SEC),
            description_template=description_template,
            one_liner_template=one_liner_template,
            one_liner_api_key=str(args.openai_one_liner_api_key or "").strip(),
            one_liner_model=args.openai_one_liner_model,
            one_liner_base_url=args.openai_one_liner_base_url,
            translation_api_key=str(args.openai_translation_api_key or "").strip(),
            translation_model=args.openai_translation_model,
            translation_base_url=args.openai_translation_base_url,
        )
    elif args.polish_mode == "codex":
        codex_polisher = CodexTextPolisher(
            repo_root=repo_root,
            model=args.codex_model,
            timeout_sec=safe_float(args.codex_timeout_sec, 120.0),
            description_template=description_template,
            one_liner_template=one_liner_template,
        )
    desired_polish_mode = "openai" if polisher else ("codex" if codex_polisher else "none")

    timeout = httpx.Timeout(safe_float(args.request_timeout_sec, DEFAULT_TIMEOUT_SEC))
    client = httpx.Client(follow_redirects=True, timeout=timeout, headers={"User-Agent": args.user_agent})
    limiter = RateLimiter(qps=safe_float(args.qps, DEFAULT_QPS))

    run_dir.mkdir(parents=True, exist_ok=True)
    jsonl_path = run_dir / "events_content.jsonl"
    csv_path = run_dir / "events_content.csv"
    log_path = run_dir / "content_enrich_log.csv"
    summary_path = run_dir / "content_summary.json"

    counts = {
        "total": 0,
        "ok": 0,
        "partial": 0,
        "empty": 0,
        "cached": 0,
        "with_description": 0,
        "with_polished_zh": 0,
        "with_one_liner_zh": 0,
        "with_polished_en": 0,
        "with_one_liner_en": 0,
        "with_images": 0,
        "skipped_by_age": skipped_by_age,
        "skipped_by_not_old_enough": skipped_by_not_old_enough,
        "reused_by_failed_only": 0,
    }

    jsonl_fp = jsonl_path.open("w", encoding="utf-8")
    csv_fp = csv_path.open("w", encoding="utf-8", newline="")
    log_fp = log_path.open("w", encoding="utf-8", newline="")
    csv_writer = csv.DictWriter(csv_fp, fieldnames=CONTENT_CSV_FIELDS)
    csv_writer.writeheader()
    log_writer = csv.writer(log_fp)
    log_writer.writerow(
        [
            "project",
            "canonical_id",
            "event_name",
            "status",
            "error",
            "source_url_count",
            "image_url_count",
            "downloaded_image_count",
        ]
    )

    def persist_record(record: dict[str, Any], log_row: list[str]) -> None:
        jsonl_fp.write(json.dumps(record, ensure_ascii=False) + "\n")
        csv_writer.writerow(csv_row_from_record(record))
        log_writer.writerow(log_row)
        jsonl_fp.flush()
        csv_fp.flush()
        log_fp.flush()

        counts["total"] += 1
        status = clean_text(str(record.get("status") or "")).lower()
        if status in {"ok", "partial", "empty", "cached"}:
            counts[status] += 1
        if clean_text_block(str(record.get("raw_description") or "")):
            counts["with_description"] += 1
        if clean_text_block(str(record.get("polished_description_zh") or "")):
            counts["with_polished_zh"] += 1
        if clean_text_block(str(record.get("one_liner_zh") or "")):
            counts["with_one_liner_zh"] += 1
        if clean_text_block(str(record.get("polished_description_en") or "")):
            counts["with_polished_en"] += 1
        if clean_text_block(str(record.get("one_liner_en") or "")):
            counts["with_one_liner_en"] += 1
        if isinstance(record.get("image_urls"), list) and len(record["image_urls"]) > 0:
            counts["with_images"] += 1

    for idx, row in enumerate(rows, start=1):
        canonical_id = str(row.get("canonical_id") or "").strip()
        if not canonical_id:
            canonical_id = hashlib.sha1(f"{project.name}:{idx}".encode("utf-8")).hexdigest()[:12]

        event_name = clean_text(str(row.get("event_name") or ""))
        source_urls = parse_source_urls(row)
        sig = source_signature(source_urls)
        old = resolve_previous_record(row, previous)

        # Failed-only mode: only retry rows that are failed/incomplete or missing previous record.
        # Successful rows are directly reused to avoid unnecessary network/model requests.
        if failed_only and should_reuse_success_in_failed_only(old, force=bool(args.force)):
            counts["reused_by_failed_only"] += 1
            reused = dict(old)
            reused["canonical_id"] = canonical_id
            reused["event_name"] = event_name
            reused["event_date_start"] = str(row.get("event_date_start") or "")
            reused["event_date_end"] = str(row.get("event_date_end") or "")
            reused["fused_run_id"] = fused_run_id
            reused["source_urls"] = source_urls
            reused["source_urls_sig"] = sig
            reused["status"] = "cached"
            reused["error"] = ""
            persist_record(reused, [project.name, canonical_id, event_name, "cached", "", "0", "0", "0"])
            if args.progress_every > 0 and (idx % args.progress_every == 0 or idx == len(rows)):
                print(
                    f"[progress] project={project.name} run_id={args.run_id} "
                    f"processed={idx}/{len(rows)}"
                )
            continue

        if (not failed_only) and is_recent_enough(
            old,
            current_signature=sig,
            min_refresh_days=int(args.min_refresh_days),
            force=bool(args.force),
            desired_polish_mode=desired_polish_mode,
        ):
            reused = dict(old)
            reused["canonical_id"] = canonical_id
            reused["event_name"] = event_name
            reused["event_date_start"] = str(row.get("event_date_start") or "")
            reused["event_date_end"] = str(row.get("event_date_end") or "")
            reused["fused_run_id"] = fused_run_id
            reused["source_urls"] = source_urls
            reused["source_urls_sig"] = sig
            reused["error"] = ""
            reused_mode = str(reused.get("polish_mode") or "").strip().lower()
            raw_cached = clean_text_block(str(reused.get("raw_description") or ""))
            missing_zh = not clean_text_block(str(reused.get("polished_description_zh") or "")) or not clean_text_block(
                str(reused.get("one_liner_zh") or "")
            )
            missing_en = not clean_text_block(str(reused.get("polished_description_en") or "")) or not clean_text_block(
                str(reused.get("one_liner_en") or "")
            )
            should_upgrade_openai = bool(polisher and raw_cached and reused_mode != "openai")
            should_upgrade_codex = bool(codex_polisher and raw_cached and (reused_mode != "codex" or missing_zh or missing_en))

            if should_upgrade_openai:
                try:
                    bundle = polisher.polish_bundle(raw_cached)
                    polished = clean_text_block(bundle.get("polished_description"))
                    one = clean_text_block(bundle.get("one_liner"))
                    if polished:
                        reused["polished_description"] = polished
                    used_one_liner = one or fallback_one_liner(raw_cached)
                    reused["one_liner"] = used_one_liner
                    zh_desc = clean_text_block(bundle.get("polished_description_zh"))
                    zh_one = clean_text_block(bundle.get("one_liner_zh"))
                    en_desc = clean_text_block(bundle.get("polished_description_en"))
                    en_one = clean_text_block(bundle.get("one_liner_en"))
                    if not (zh_desc and zh_one and en_desc and en_one):
                        translated = polisher.translate_pair(
                            polished or clean_text_block(str(reused.get("polished_description") or raw_cached)),
                            used_one_liner,
                        )
                        zh_desc = zh_desc or clean_text_block(translated.get("polished_description_zh"))
                        zh_one = zh_one or clean_text_block(translated.get("one_liner_zh"))
                        en_desc = en_desc or clean_text_block(translated.get("polished_description_en"))
                        en_one = en_one or clean_text_block(translated.get("one_liner_en"))
                    reused["polished_description_zh"] = zh_desc
                    reused["one_liner_zh"] = zh_one
                    reused["polished_description_en"] = en_desc
                    reused["one_liner_en"] = en_one
                    reused["polish_mode"] = "openai"
                    reused["polish_model"] = polisher.model_tag
                    reused["status"] = "ok"
                except Exception as exc:  # noqa: BLE001
                    reused["status"] = "cached"
                    reused["error"] = f"polish_error:{exc}"
            elif should_upgrade_codex:
                try:
                    bundle = codex_polisher.polish_bundle(raw_cached)
                    polished = clean_text_block(bundle.get("polished_description"))
                    one = clean_text_block(bundle.get("one_liner"))
                    if not polished and not one:
                        raise ValueError("empty codex polish response")
                    if polished:
                        reused["polished_description"] = polished
                    used_one_liner = one or fallback_one_liner(raw_cached)
                    reused["one_liner"] = used_one_liner
                    zh_desc = clean_text_block(bundle.get("polished_description_zh"))
                    zh_one = clean_text_block(bundle.get("one_liner_zh"))
                    en_desc = clean_text_block(bundle.get("polished_description_en"))
                    en_one = clean_text_block(bundle.get("one_liner_en"))
                    if not codex_single_pass_i18n and not (zh_desc and zh_one and en_desc and en_one):
                        translated = codex_polisher.translate_pair(
                            polished or clean_text_block(str(reused.get("polished_description") or raw_cached)),
                            used_one_liner,
                        )
                        zh_desc = zh_desc or clean_text_block(translated.get("polished_description_zh"))
                        zh_one = zh_one or clean_text_block(translated.get("one_liner_zh"))
                        en_desc = en_desc or clean_text_block(translated.get("polished_description_en"))
                        en_one = en_one or clean_text_block(translated.get("one_liner_en"))
                    reused["polished_description_zh"] = zh_desc
                    reused["one_liner_zh"] = zh_one
                    reused["polished_description_en"] = en_desc
                    reused["one_liner_en"] = en_one
                    reused["polish_mode"] = "codex"
                    reused["polish_model"] = codex_polisher.model
                    reused["status"] = "ok"
                except Exception as exc:  # noqa: BLE001
                    reused["status"] = "cached"
                    reused["error"] = f"polish_error:{exc}"
            else:
                reused["status"] = "cached"

            persist_record(
                reused,
                [project.name, canonical_id, event_name, str(reused.get("status") or "cached"), "", "0", "0", "0"],
            )
            if args.progress_every > 0 and (idx % args.progress_every == 0 or idx == len(rows)):
                print(
                    f"[progress] project={project.name} run_id={args.run_id} "
                    f"processed={idx}/{len(rows)}"
                )
            continue

        extracts: list[PageExtract] = []
        fetch_error = ""
        selected_urls = source_urls[: max(1, int(args.max_source_urls_per_event))]
        for url in selected_urls:
            response, err = fetch_page_with_retries(
                client,
                limiter,
                url,
                max_retries=max(1, int(args.max_retries)),
            )
            if not response:
                fetch_error = err or fetch_error
                continue
            extract = extract_from_page(
                source_url=url,
                final_url=str(response.url),
                html=decode_response_html(response),
                event_name=event_name,
                max_desc_chars=max(300, int(args.max_description_chars)),
                max_images=max(1, int(args.max_images)),
            )
            extracts.append(extract)

        best = pick_best_page_extract(extracts)
        raw_description = best.raw_description if best else ""
        image_urls = best.image_urls if best else []
        description_source_url = best.final_url if best else (selected_urls[0] if selected_urls else "")

        polished_description = raw_description
        one_liner = ""
        polished_description_zh = ""
        one_liner_zh = ""
        polished_description_en = ""
        one_liner_en = ""
        polish_mode_used = "none"
        polish_model_used = ""

        if raw_description and polisher:
            try:
                bundle = polisher.polish_bundle(raw_description)
                polished = clean_text_block(bundle.get("polished_description"))
                one = clean_text_block(bundle.get("one_liner"))
                if polished:
                    polished_description = polished
                one_liner = one
                polished_description_zh = clean_text_block(bundle.get("polished_description_zh"))
                one_liner_zh = clean_text_block(bundle.get("one_liner_zh"))
                polished_description_en = clean_text_block(bundle.get("polished_description_en"))
                one_liner_en = clean_text_block(bundle.get("one_liner_en"))
                polish_mode_used = "openai"
                polish_model_used = polisher.model_tag
            except Exception as exc:  # noqa: BLE001
                polish_mode_used = "openai_failed"
                fetch_error = f"{fetch_error}; polish_error:{exc}" if fetch_error else f"polish_error:{exc}"
        elif raw_description and codex_polisher:
            try:
                bundle = codex_polisher.polish_bundle(raw_description)
                polished = clean_text_block(bundle.get("polished_description"))
                one = clean_text_block(bundle.get("one_liner"))
                if not polished and not one:
                    raise ValueError("empty codex polish response")
                if polished:
                    polished_description = polished
                one_liner = one
                polished_description_zh = clean_text_block(bundle.get("polished_description_zh"))
                one_liner_zh = clean_text_block(bundle.get("one_liner_zh"))
                polished_description_en = clean_text_block(bundle.get("polished_description_en"))
                one_liner_en = clean_text_block(bundle.get("one_liner_en"))
                polish_mode_used = "codex"
                polish_model_used = codex_polisher.model
            except Exception as exc:  # noqa: BLE001
                polish_mode_used = "codex_failed"
                fetch_error = f"{fetch_error}; polish_error:{exc}" if fetch_error else f"polish_error:{exc}"

        if not one_liner and raw_description:
            one_liner = fallback_one_liner(raw_description)

        if polisher and raw_description and polish_mode_used == "openai":
            has_zh = bool(polished_description_zh and one_liner_zh)
            has_en = bool(polished_description_en and one_liner_en)
            if not (has_zh and has_en):
                try:
                    translated = polisher.translate_pair(polished_description or raw_description, one_liner)
                    polished_description_zh = polished_description_zh or clean_text_block(translated.get("polished_description_zh"))
                    one_liner_zh = one_liner_zh or clean_text_block(translated.get("one_liner_zh"))
                    polished_description_en = polished_description_en or clean_text_block(translated.get("polished_description_en"))
                    one_liner_en = one_liner_en or clean_text_block(translated.get("one_liner_en"))
                except Exception as exc:  # noqa: BLE001
                    fetch_error = f"{fetch_error}; translate_error:{exc}" if fetch_error else f"translate_error:{exc}"

        if codex_polisher and raw_description and polish_mode_used == "codex" and not codex_single_pass_i18n:
            has_zh = bool(polished_description_zh and one_liner_zh)
            has_en = bool(polished_description_en and one_liner_en)
            if not (has_zh and has_en):
                try:
                    translated = codex_polisher.translate_pair(polished_description or raw_description, one_liner)
                    polished_description_zh = polished_description_zh or clean_text_block(translated.get("polished_description_zh"))
                    one_liner_zh = one_liner_zh or clean_text_block(translated.get("one_liner_zh"))
                    polished_description_en = polished_description_en or clean_text_block(translated.get("polished_description_en"))
                    one_liner_en = one_liner_en or clean_text_block(translated.get("one_liner_en"))
                except Exception as exc:  # noqa: BLE001
                    fetch_error = f"{fetch_error}; translate_error:{exc}" if fetch_error else f"translate_error:{exc}"
        elif codex_polisher and raw_description and polish_mode_used == "codex" and codex_single_pass_i18n:
            has_zh = bool(polished_description_zh and one_liner_zh)
            has_en = bool(polished_description_en and one_liner_en)
            if not (has_zh and has_en):
                fetch_error = (
                    f"{fetch_error}; polish_i18n_incomplete(single_pass)"
                    if fetch_error
                    else "polish_i18n_incomplete(single_pass)"
                )

        downloaded_abs: list[str] = []
        if image_urls and args.download_images:
            target = image_root / canonical_id
            downloaded_abs = download_images(
                client=client,
                limiter=limiter,
                image_urls=image_urls,
                target_dir=target,
                max_images=max(1, int(args.max_images)),
                max_bytes=max(0, int(args.max_image_bytes)),
            )

        downloaded_rel = [ensure_relative(Path(p), project.root) for p in downloaded_abs]
        status = "ok"
        if not raw_description and not image_urls:
            status = "empty"
        elif fetch_error:
            status = "partial"

        record = {
            "canonical_id": canonical_id,
            "category": project.category,
            "event_name": event_name,
            "event_date_start": str(row.get("event_date_start") or ""),
            "event_date_end": str(row.get("event_date_end") or ""),
            "fused_run_id": fused_run_id,
            "description_source_url": description_source_url,
            "raw_description": raw_description,
            "polished_description": polished_description,
            "one_liner": one_liner,
            "polished_description_zh": polished_description_zh,
            "one_liner_zh": one_liner_zh,
            "polished_description_en": polished_description_en,
            "one_liner_en": one_liner_en,
            "image_urls": image_urls,
            "downloaded_images": downloaded_rel,
            "source_urls": source_urls,
            "source_urls_sig": sig,
            "status": status,
            "error": fetch_error,
            "fetched_at": now_iso(),
            "polish_mode": polish_mode_used,
            "polish_model": polish_model_used,
        }
        persist_record(
            record,
            [
                project.name,
                canonical_id,
                event_name,
                status,
                fetch_error,
                str(len(source_urls)),
                str(len(image_urls)),
                str(len(downloaded_rel)),
            ],
        )
        if args.progress_every > 0 and (idx % args.progress_every == 0 or idx == len(rows)):
            print(
                f"[progress] project={project.name} run_id={args.run_id} "
                f"processed={idx}/{len(rows)}"
            )

    jsonl_fp.close()
    csv_fp.close()
    log_fp.close()
    client.close()
    if polisher:
        polisher.close()
    if codex_polisher:
        codex_polisher.close()

    summary = {
        "project": project.name,
        "category": project.category,
        "run_id": args.run_id,
        "generated_at": now_iso(),
        "fused_run_id": fused_run_id,
        "fused_jsonl": str(fused_jsonl),
        "counts": counts,
        "output": {
            "jsonl": str(jsonl_path),
            "csv": str(csv_path),
            "log": str(log_path),
        },
        "prompt_paths": {
            "description": str(Path(args.description_prompt)),
            "one_liner": str(Path(args.one_liner_prompt)),
        },
        "filter": {
            "skip_past_days": int(args.skip_past_days),
            "basis": "event_date_start",
            "cutoff_date": cutoff_date.isoformat() if cutoff_date else None,
            "only_past_days": only_past_days,
            "only_past_cutoff_date": only_past_cutoff_date.isoformat() if only_past_cutoff_date else None,
            "failed_only": failed_only,
            "prioritize_near_start": prioritize_near_start,
            "codex_single_pass_i18n": codex_single_pass_i18n,
        },
    }
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    latest_dir = project.root / "data" / "content" / "latest"
    latest_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(jsonl_path, latest_dir / "events_content.jsonl")
    shutil.copy2(csv_path, latest_dir / "events_content.csv")
    shutil.copy2(log_path, latest_dir / "content_enrich_log.csv")
    shutil.copy2(summary_path, latest_dir / "content_summary.json")

    if args.update_latest_run:
        updated = dict(latest_run)
        updated["content_run_id"] = args.run_id
        updated["content_generated_at"] = summary["generated_at"]
        updated["content_summary"] = ensure_relative(summary_path, project.root)
        updated["content_events_jsonl"] = ensure_relative(jsonl_path, project.root)
        updated["content_events_csv"] = ensure_relative(csv_path, project.root)
        latest_path.write_text(json.dumps(updated, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(
        f"[content] project={project.name} run_id={args.run_id} total={counts['total']} "
        f"ok={counts['ok']} partial={counts['partial']} empty={counts['empty']} cached={counts['cached']}"
    )
    print(f"[content] summary={summary_path}")

    return {
        "project": project.name,
        "status": "ok",
        "fused_run_id": fused_run_id,
        "summary": str(summary_path),
        "counts": counts,
    }


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(
        description="Low-frequency long-run event content enrichment: crawl images/descriptions and polish text"
    )
    parser.add_argument("--project", choices=["all", "hanabi", "omatsuri"], default="all")
    parser.add_argument("--run-id", default=datetime.now().strftime("%Y%m%d_%H%M%S") + "_content")
    parser.add_argument("--start-index", type=int, default=0, help="Start index (0-based) in fused JSONL")
    parser.add_argument("--max-events", type=int, default=0, help="0 means all rows")
    parser.add_argument("--progress-every", type=int, default=20, help="Print progress every N events")
    parser.add_argument("--min-refresh-days", type=int, default=DEFAULT_MIN_REFRESH_DAYS)
    parser.add_argument("--qps", type=float, default=DEFAULT_QPS, help="Global request QPS (low by default)")
    parser.add_argument("--request-timeout-sec", type=float, default=DEFAULT_TIMEOUT_SEC)
    parser.add_argument("--max-retries", type=int, default=3)
    parser.add_argument("--max-source-urls-per-event", type=int, default=DEFAULT_MAX_SOURCE_URLS)
    parser.add_argument("--max-images", type=int, default=DEFAULT_MAX_IMAGES)
    parser.add_argument("--max-image-bytes", type=int, default=DEFAULT_MAX_IMAGE_BYTES)
    parser.add_argument("--max-description-chars", type=int, default=DEFAULT_MAX_DESC_CHARS)
    parser.add_argument("--force", action=argparse.BooleanOptionalAction, default=False)
    parser.add_argument("--download-images", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--update-latest-run", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument(
        "--skip-past-days",
        type=int,
        default=31,
        help="Skip events whose start date is older than N days (event_date_start only)",
    )
    parser.add_argument(
        "--only-past-days",
        type=int,
        default=-1,
        help="Only process events whose start date is older than N days (event_date_start only); -1 disables",
    )
    parser.add_argument(
        "--failed-only",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="Only process failed/unprocessed events; successful previous records are reused",
    )
    parser.add_argument(
        "--prioritize-near-start",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="Prioritize events with nearest start date (upcoming first, then recently ended)",
    )
    parser.add_argument(
        "--codex-single-pass-i18n",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="Require JA/ZH/EN generation in one codex pass and skip second translation pass",
    )

    parser.add_argument(
        "--description-prompt",
        default=str(repo_root / "数据端/文档/event-description-polish.prompt.md"),
    )
    parser.add_argument(
        "--one-liner-prompt",
        default=str(repo_root / "数据端/文档/event-one-liner.prompt.md"),
    )
    parser.add_argument("--polish-mode", choices=["auto", "openai", "codex", "none"], default="auto")
    parser.add_argument("--openai-model", default=os.getenv("OPENAI_MODEL", "gpt-5-mini"))
    parser.add_argument("--openai-base-url", default=os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1/responses"))
    parser.add_argument("--openai-api-key", default=os.getenv("OPENAI_API_KEY", ""))
    parser.add_argument(
        "--openai-one-liner-model",
        default=os.getenv("OPENAI_ONE_LINER_MODEL", ""),
        help="Optional one-liner model (falls back to --openai-model)",
    )
    parser.add_argument(
        "--openai-one-liner-base-url",
        default=os.getenv("OPENAI_ONE_LINER_BASE_URL", ""),
        help="Optional one-liner endpoint (falls back to --openai-base-url)",
    )
    parser.add_argument(
        "--openai-one-liner-api-key",
        default=os.getenv("OPENAI_ONE_LINER_API_KEY", ""),
        help="Optional one-liner API key (falls back to --openai-api-key)",
    )
    parser.add_argument(
        "--openai-translation-model",
        default=os.getenv("OPENAI_TRANSLATION_MODEL", ""),
        help="Optional translation model (falls back to --openai-model)",
    )
    parser.add_argument(
        "--openai-translation-base-url",
        default=os.getenv("OPENAI_TRANSLATION_BASE_URL", ""),
        help="Optional translation endpoint (falls back to --openai-base-url)",
    )
    parser.add_argument(
        "--openai-translation-api-key",
        default=os.getenv("OPENAI_TRANSLATION_API_KEY", ""),
        help="Optional translation API key (falls back to --openai-api-key)",
    )
    parser.add_argument("--codex-model", default=DEFAULT_CODEX_MODEL)
    parser.add_argument("--codex-timeout-sec", type=float, default=120.0)
    parser.add_argument(
        "--user-agent",
        default=(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36"
        ),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[2]

    projects = build_projects(repo_root)
    selected_keys = [args.project] if args.project != "all" else ["hanabi", "omatsuri"]

    description_template = read_template(Path(args.description_prompt))
    one_liner_template = read_template(Path(args.one_liner_prompt))

    if args.polish_mode == "openai" and not str(args.openai_api_key or "").strip():
        print("[warn] --polish-mode=openai but --openai-api-key is empty, fallback to none")
        args.polish_mode = "none"

    summaries: list[dict[str, Any]] = []
    for key in selected_keys:
        project = projects[key]
        summary = run_project(
            repo_root=repo_root,
            project=project,
            args=args,
            description_template=description_template,
            one_liner_template=one_liner_template,
        )
        summaries.append(summary)

    print("[done] content enrichment finished")
    print(json.dumps(summaries, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
