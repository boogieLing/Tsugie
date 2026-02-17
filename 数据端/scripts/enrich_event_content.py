#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import shutil
import time
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
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
    ) -> None:
        self.model = model
        self.description_template = description_template
        self.one_liner_template = one_liner_template
        self.client = httpx.Client(
            timeout=timeout_sec,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
        )
        self.base_url = base_url

    def close(self) -> None:
        self.client.close()

    def polish_description(self, raw_text: str) -> str:
        prompt = self.description_template.replace("{原始文本}", raw_text)
        out = self._call(prompt)
        return out or raw_text

    def one_liner(self, raw_text: str) -> str:
        prompt = self.one_liner_template.replace("{原始文本}", raw_text)
        out = self._call(prompt)
        return out or ""

    def _call(self, prompt: str) -> str:
        payload = {
            "model": self.model,
            "input": prompt,
            "reasoning": {"effort": "low"},
        }
        resp = self.client.post(self.base_url, json=payload)
        resp.raise_for_status()
        data = resp.json()
        text = extract_openai_output_text(data)
        return clean_text_block(text)


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


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def clean_text(text: str | None) -> str:
    if not text:
        return ""
    return re.sub(r"\s+", " ", text).strip()


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


def read_jsonl(path: Path, max_rows: int) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as f:
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
            rows.append(row)
            if max_rows > 0 and len(rows) >= max_rows:
                break
    return rows


def load_previous_records(project: SourceProject, latest_run: dict[str, Any]) -> dict[str, dict[str, Any]]:
    run_id = str(latest_run.get("content_run_id") or "").strip()
    candidate = project.root / "data" / "content" / run_id / "events_content.jsonl" if run_id else None
    if not candidate or not candidate.exists():
        fallback = project.root / "data" / "content" / "latest" / "events_content.jsonl"
        candidate = fallback if fallback.exists() else None

    if not candidate:
        return {}

    out: dict[str, dict[str, Any]] = {}
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
            if not canonical_id:
                continue
            out[canonical_id] = row
    return out


def is_recent_enough(
    previous: dict[str, Any] | None,
    *,
    current_signature: str,
    min_refresh_days: int,
    force: bool,
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


def extract_from_page(url: str, final_url: str, html: str, *, max_desc_chars: int, max_images: int) -> PageExtract:
    soup = BeautifulSoup(html, "lxml")
    raw_description = choose_raw_description(soup, max_chars=max_desc_chars)
    image_urls = collect_image_urls(soup, base_url=final_url or url, max_images=max_images)
    return PageExtract(
        url=url,
        final_url=final_url or url,
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


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = [
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
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            out = dict(row)
            out["image_urls"] = "|".join(row.get("image_urls", []))
            out["downloaded_images"] = "|".join(row.get("downloaded_images", []))
            out["source_urls"] = "|".join(row.get("source_urls", []))
            writer.writerow({k: out.get(k, "") for k in fields})


def read_template(path: Path) -> str:
    if not path.exists():
        raise FileNotFoundError(f"prompt template not found: {path}")
    return path.read_text(encoding="utf-8")


def should_use_openai(mode: str, has_api_key: bool) -> bool:
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

    rows = read_jsonl(fused_jsonl, max_rows=args.max_events)
    previous = load_previous_records(project, latest_run)

    run_dir = project.root / "data" / "content" / args.run_id
    image_root = project.root / "data" / "content_assets" / args.run_id

    api_key = str(args.openai_api_key or "").strip()
    openai_enabled = should_use_openai(args.polish_mode, bool(api_key))
    polisher: OpenAITextPolisher | None = None

    if openai_enabled and api_key:
        polisher = OpenAITextPolisher(
            api_key=api_key,
            model=args.openai_model,
            base_url=args.openai_base_url,
            timeout_sec=safe_float(args.request_timeout_sec, DEFAULT_TIMEOUT_SEC),
            description_template=description_template,
            one_liner_template=one_liner_template,
        )

    timeout = httpx.Timeout(safe_float(args.request_timeout_sec, DEFAULT_TIMEOUT_SEC))
    client = httpx.Client(follow_redirects=True, timeout=timeout, headers={"User-Agent": args.user_agent})
    limiter = RateLimiter(qps=safe_float(args.qps, DEFAULT_QPS))

    content_rows: list[dict[str, Any]] = []
    log_rows: list[list[str]] = []

    for idx, row in enumerate(rows, start=1):
        canonical_id = str(row.get("canonical_id") or "").strip()
        if not canonical_id:
            canonical_id = hashlib.sha1(f"{project.name}:{idx}".encode("utf-8")).hexdigest()[:12]

        event_name = clean_text(str(row.get("event_name") or ""))
        source_urls = parse_source_urls(row)
        sig = source_signature(source_urls)
        old = previous.get(canonical_id)

        if is_recent_enough(
            old,
            current_signature=sig,
            min_refresh_days=int(args.min_refresh_days),
            force=bool(args.force),
        ):
            reused = dict(old)
            reused["fused_run_id"] = fused_run_id
            reused["status"] = "cached"
            reused["error"] = ""
            content_rows.append(reused)
            log_rows.append([project.name, canonical_id, event_name, "cached", "", "0", "0", "0"])
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
                url=url,
                final_url=str(response.url),
                html=response.text,
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
        polish_mode_used = "none"
        polish_model_used = ""

        if raw_description and polisher:
            try:
                polished_description = polisher.polish_description(raw_description)
                one_liner = polisher.one_liner(raw_description)
                polish_mode_used = "openai"
                polish_model_used = args.openai_model
            except Exception as exc:  # noqa: BLE001
                polish_mode_used = "openai_failed"
                fetch_error = f"{fetch_error}; polish_error:{exc}" if fetch_error else f"polish_error:{exc}"

        if not one_liner and raw_description:
            one_liner = fallback_one_liner(raw_description)

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
        content_rows.append(record)
        log_rows.append(
            [
                project.name,
                canonical_id,
                event_name,
                status,
                fetch_error,
                str(len(source_urls)),
                str(len(image_urls)),
                str(len(downloaded_rel)),
            ]
        )

    client.close()
    if polisher:
        polisher.close()

    run_dir.mkdir(parents=True, exist_ok=True)
    jsonl_path = run_dir / "events_content.jsonl"
    csv_path = run_dir / "events_content.csv"
    log_path = run_dir / "content_enrich_log.csv"
    summary_path = run_dir / "content_summary.json"

    write_jsonl(jsonl_path, content_rows)
    write_csv(csv_path, content_rows)

    with log_path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(
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
        writer.writerows(log_rows)

    counts = {
        "total": len(content_rows),
        "ok": sum(1 for r in content_rows if r.get("status") == "ok"),
        "partial": sum(1 for r in content_rows if r.get("status") == "partial"),
        "empty": sum(1 for r in content_rows if r.get("status") == "empty"),
        "cached": sum(1 for r in content_rows if r.get("status") == "cached"),
        "with_description": sum(1 for r in content_rows if clean_text_block(str(r.get("raw_description") or ""))),
        "with_images": sum(1 for r in content_rows if isinstance(r.get("image_urls"), list) and len(r["image_urls"]) > 0),
    }

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
    parser.add_argument("--max-events", type=int, default=0, help="0 means all rows")
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
        "--description-prompt",
        default=str(repo_root / "数据端/文档/event-description-polish.prompt.md"),
    )
    parser.add_argument(
        "--one-liner-prompt",
        default=str(repo_root / "数据端/文档/event-one-liner.prompt.md"),
    )
    parser.add_argument("--polish-mode", choices=["auto", "openai", "none"], default="auto")
    parser.add_argument("--openai-model", default="gpt-5-mini")
    parser.add_argument("--openai-base-url", default="https://api.openai.com/v1/responses")
    parser.add_argument("--openai-api-key", default="")
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

    if args.polish_mode == "openai" and not args.openai_api_key:
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
