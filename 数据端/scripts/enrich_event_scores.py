#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import time
from dataclasses import dataclass
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any
from urllib import error as urlerror
from urllib import request as urlrequest


DEFAULT_TIMEOUT_SEC = 45.0
DEFAULT_QPS = 0.2
DEFAULT_DEEPSEEK_MODEL = "deepseek-chat"
DEFAULT_DEEPSEEK_BASE_URL = "https://api.deepseek.com/chat/completions"
DEFAULT_MAX_REASON_CHARS = 80


@dataclass(frozen=True)
class SourceProject:
    name: str
    category: str
    root: Path
    latest_run_path: Path
    fused_dir: Path
    content_dir: Path
    score_dir: Path


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


class DeepSeekScoreAnalyzer:
    def __init__(self, *, api_key: str, model: str, base_url: str, timeout_sec: float, prompt_template: str) -> None:
        self.model = clean_text(model) or DEFAULT_DEEPSEEK_MODEL
        self.base_url = clean_text(base_url) or DEFAULT_DEEPSEEK_BASE_URL
        self.prompt_template = prompt_template
        self.timeout_sec = timeout_sec
        self.headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        }

    def close(self) -> None:
        return

    def analyze(self, payload: dict[str, Any]) -> dict[str, Any]:
        prompt = self.prompt_template.replace(
            "{输入JSON}",
            json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True),
        )
        req = {
            "model": self.model,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.2,
            "response_format": {"type": "json_object"},
        }
        body = json.dumps(req, ensure_ascii=False).encode("utf-8")
        request = urlrequest.Request(
            self.base_url.rstrip("/"),
            data=body,
            headers=self.headers,
            method="POST",
        )
        try:
            with urlrequest.urlopen(request, timeout=self.timeout_sec) as resp:
                raw = resp.read()
        except urlerror.HTTPError as exc:
            err_body = ""
            try:
                err_body = exc.read().decode("utf-8", errors="replace")
            except Exception:  # noqa: BLE001
                err_body = ""
            raise RuntimeError(f"HTTP {exc.code}: {err_body[:260]}") from exc
        except Exception as exc:  # noqa: BLE001
            raise RuntimeError(f"request failed: {exc}") from exc

        data = json.loads(raw.decode("utf-8"))
        text = extract_chat_completion_text(data)
        parsed = parse_json_object(text)
        if not isinstance(parsed, dict):
            raise ValueError("model output is not a valid JSON object")
        return parsed


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description="AI score enrichment (initial heat + surprise) for fused events.")
    parser.add_argument("--project", choices=["hanabi", "omatsuri"], required=True)
    parser.add_argument("--run-id", default="")
    parser.add_argument("--fused-run-id", default="")
    parser.add_argument("--content-run-id", default="")
    parser.add_argument("--deepseek-api-key", default=os.getenv("DEEPSEEK_API_KEY", ""))
    parser.add_argument("--deepseek-model", default=os.getenv("DEEPSEEK_SCORE_MODEL", DEFAULT_DEEPSEEK_MODEL))
    parser.add_argument("--deepseek-base-url", default=os.getenv("DEEPSEEK_BASE_URL", DEFAULT_DEEPSEEK_BASE_URL))
    parser.add_argument(
        "--prompt-file",
        type=Path,
        default=repo_root / "数据端/文档/event-heat-surprise-analysis.prompt.md",
    )
    parser.add_argument("--timeout-sec", type=float, default=DEFAULT_TIMEOUT_SEC)
    parser.add_argument("--qps", type=float, default=DEFAULT_QPS)
    parser.add_argument("--max-events", type=int, default=0, help="0 means no limit")
    parser.add_argument(
        "--failed-only",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Only process failed/unprocessed items; reuse successful previous scores.",
    )
    parser.add_argument(
        "--prioritize-near-start",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Process events by nearest start date first.",
    )
    parser.add_argument(
        "--update-latest-run",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Write score run metadata to data/latest_run.json",
    )
    return parser.parse_args()


def clean_text(raw: Any) -> str:
    if raw is None:
        return ""
    return str(raw).strip()


def clean_text_block(raw: Any) -> str:
    text = clean_text(raw)
    if not text:
        return ""
    text = text.replace("\u00a0", " ")
    text = re.sub(r"\r\n?", "\n", text)
    text = re.sub(r"[ \t]+\n", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def nonempty(raw: Any) -> str | None:
    text = clean_text(raw)
    return text or None


def normalize_string_list(raw: Any) -> list[str]:
    if isinstance(raw, list):
        return [x for item in raw if (x := nonempty(item))]
    if isinstance(raw, str):
        if "|" in raw:
            return [x for x in (part.strip() for part in raw.split("|")) if x]
        value = raw.strip()
        return [value] if value else []
    return []


def extract_date(raw: Any) -> str | None:
    if raw is None:
        return None
    text = str(raw)
    m = re.search(r"(20\d{2})[-/年\.](\d{1,2})[-/月\.](\d{1,2})", text)
    if not m:
        return None
    y, mo, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
    if mo < 1 or mo > 12 or d < 1 or d > 31:
        return None
    return f"{y:04d}-{mo:02d}-{d:02d}"


def parse_number(raw: Any) -> int | None:
    if raw is None:
        return None
    text = str(raw)
    chunks = re.findall(r"\d[\d,]*", text)
    if not chunks:
        return None
    merged = "".join(chunks).replace(",", "")
    try:
        return int(merged)
    except ValueError:
        return None


def normalize_name_for_match(raw: Any) -> str:
    text = nonempty(raw) or ""
    if not text:
        return ""
    text = text.lower()
    text = re.sub(r"\s+", "", text)
    text = re.sub(r"[【】\[\]（）()「」『』・,，。.!！?？:：/／\\\-~〜～]", "", text)
    return text


def build_name_date_key(event_name: Any, event_date_start: Any) -> str:
    name_key = normalize_name_for_match(event_name)
    if not name_key:
        return ""
    date_key = extract_date(event_date_start) or (nonempty(event_date_start) or "")
    return f"{name_key}|{date_key}"


def source_url_set(row: dict[str, Any]) -> set[str]:
    urls = set(normalize_string_list(row.get("source_urls")))
    description_source = nonempty(row.get("description_source_url"))
    if description_source:
        urls.add(description_source)
    return urls


def rows_look_same_event(base_row: dict[str, Any], candidate_row: dict[str, Any]) -> bool:
    base_sources = source_url_set(base_row)
    candidate_sources = source_url_set(candidate_row)
    if base_sources and candidate_sources and base_sources.intersection(candidate_sources):
        return True

    base_key = build_name_date_key(base_row.get("event_name"), base_row.get("event_date_start"))
    candidate_key = build_name_date_key(candidate_row.get("event_name"), candidate_row.get("event_date_start"))
    return bool(base_key and candidate_key and base_key == candidate_key)


def clamp(v: int, lo: int, hi: int) -> int:
    return max(lo, min(hi, v))


def parse_iso_date(raw: str) -> date | None:
    text = clean_text(raw)
    if not text:
        return None
    try:
        return datetime.strptime(text, "%Y-%m-%d").date()
    except ValueError:
        return None


def extract_chat_completion_text(data: dict[str, Any]) -> str:
    choices = data.get("choices")
    if not isinstance(choices, list):
        return ""
    for choice in choices:
        if not isinstance(choice, dict):
            continue
        message = choice.get("message")
        if not isinstance(message, dict):
            continue
        content = message.get("content")
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            parts: list[str] = []
            for item in content:
                if isinstance(item, dict):
                    t = item.get("text")
                    if isinstance(t, str) and t:
                        parts.append(t)
            if parts:
                return "\n".join(parts)
    return ""


def parse_json_object(text: str) -> dict[str, Any] | None:
    raw = clean_text_block(text)
    if not raw:
        return None
    fenced = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", raw, flags=re.S | re.I)
    if fenced:
        raw = fenced.group(1).strip()
    if raw.startswith("{") and raw.endswith("}"):
        try:
            data = json.loads(raw)
            if isinstance(data, dict):
                return data
        except json.JSONDecodeError:
            pass

    start = raw.find("{")
    end = raw.rfind("}")
    if start >= 0 and end > start:
        candidate = raw[start : end + 1]
        try:
            data = json.loads(candidate)
            if isinstance(data, dict):
                return data
        except json.JSONDecodeError:
            return None
    return None


def make_source(project: str) -> SourceProject:
    repo_root = Path(__file__).resolve().parents[2]
    if project == "hanabi":
        root = repo_root / "数据端/HANABI"
        category = "hanabi"
    else:
        root = repo_root / "数据端/OMATSURI"
        category = "matsuri"
    return SourceProject(
        name=project,
        category=category,
        root=root,
        latest_run_path=root / "data/latest_run.json",
        fused_dir=root / "data/fused",
        content_dir=root / "data/content",
        score_dir=root / "data/scores",
    )


def load_latest_meta(source: SourceProject) -> dict[str, Any]:
    if not source.latest_run_path.exists():
        return {}
    try:
        return json.loads(source.latest_run_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def load_fused_rows(source: SourceProject, fused_run_id: str) -> list[dict[str, Any]]:
    path = source.fused_dir / fused_run_id / "events_fused.jsonl"
    if not path.exists():
        raise FileNotFoundError(f"fused file not found: {path}")
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return rows


def score_content_entry(row: dict[str, Any]) -> tuple[int, int, int, str]:
    status_rank = {"ok": 4, "cached": 3, "partial": 2, "empty": 1}.get(clean_text(row.get("status")).lower(), 0)
    polished = clean_text_block(row.get("polished_description"))
    one_liner = clean_text_block(row.get("one_liner"))
    i18n_ready = int(
        bool(clean_text_block(row.get("polished_description_zh")))
        and bool(clean_text_block(row.get("one_liner_zh")))
        and bool(clean_text_block(row.get("polished_description_en")))
        and bool(clean_text_block(row.get("one_liner_en")))
    )
    fetched_at = clean_text(row.get("fetched_at"))
    return (status_rank, int(bool(polished)), int(bool(one_liner)) + i18n_ready, fetched_at)


def _put_if_better(bucket: dict[str, dict[str, Any]], row: dict[str, Any], key: str) -> None:
    if not key:
        return
    existing = bucket.get(key)
    if existing is None or score_content_entry(row) >= score_content_entry(existing):
        bucket[key] = row


def load_content_index(source: SourceProject, preferred_run_id: str) -> tuple[dict[str, dict[str, dict[str, Any]]], list[str]]:
    by_canonical: dict[str, dict[str, Any]] = {}
    by_source_url: dict[str, dict[str, Any]] = {}
    by_name_date: dict[str, dict[str, Any]] = {}
    if not source.content_dir.exists():
        return {"by_canonical": by_canonical, "by_source_url": by_source_url, "by_name_date": by_name_date}, []

    run_dirs = sorted([p for p in source.content_dir.iterdir() if p.is_dir()], key=lambda p: p.name)
    if preferred_run_id:
        run_dirs = sorted(run_dirs, key=lambda p: (p.name != preferred_run_id, p.name))
    run_ids: list[str] = []
    for run_dir in run_dirs:
        jsonl_path = run_dir / "events_content.jsonl"
        if not jsonl_path.exists():
            continue
        run_ids.append(run_dir.name)
        with jsonl_path.open("r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    row = json.loads(line)
                except json.JSONDecodeError:
                    continue
                canonical_id = nonempty(row.get("canonical_id"))
                if canonical_id:
                    _put_if_better(by_canonical, row, canonical_id)
                for source_url in normalize_string_list(row.get("source_urls")):
                    _put_if_better(by_source_url, row, source_url)
                description_source_url = nonempty(row.get("description_source_url"))
                if description_source_url:
                    _put_if_better(by_source_url, row, description_source_url)
                name_date_key = build_name_date_key(row.get("event_name"), row.get("event_date_start"))
                if name_date_key:
                    _put_if_better(by_name_date, row, name_date_key)
    return {"by_canonical": by_canonical, "by_source_url": by_source_url, "by_name_date": by_name_date}, run_ids


def resolve_content_row(row: dict[str, Any], index: dict[str, dict[str, dict[str, Any]]]) -> dict[str, Any] | None:
    canonical = nonempty(row.get("canonical_id")) or ""
    candidates: list[dict[str, Any]] = []
    seen: set[int] = set()

    if canonical and canonical in index["by_canonical"]:
        candidate = index["by_canonical"][canonical]
        if rows_look_same_event(row, candidate):
            candidates.append(candidate)
            seen.add(id(candidate))
    for source_url in normalize_string_list(row.get("source_urls")):
        matched = index["by_source_url"].get(source_url)
        if not matched:
            continue
        if id(matched) in seen:
            continue
        if not rows_look_same_event(row, matched):
            continue
        candidates.append(matched)
        seen.add(id(matched))
    key = build_name_date_key(row.get("event_name"), row.get("event_date_start"))
    if key:
        matched = index["by_name_date"].get(key)
        if matched and id(matched) not in seen and rows_look_same_event(row, matched):
            candidates.append(matched)
            seen.add(id(matched))
    if not candidates:
        return None
    candidates.sort(key=score_content_entry, reverse=True)
    return candidates[0]


def score_score_row(row: dict[str, Any]) -> tuple[int, str]:
    status = clean_text(row.get("status")).lower()
    source = clean_text(row.get("score_source")).lower()
    rank = 0
    if status == "ok" and source == "ai":
        rank = 4
    elif status == "ok":
        rank = 3
    elif status.startswith("cached"):
        rank = 2
    elif status:
        rank = 1
    generated_at = clean_text(row.get("generated_at"))
    return (rank, generated_at)


def _put_score_if_better(bucket: dict[str, dict[str, Any]], row: dict[str, Any], key: str) -> None:
    if not key:
        return
    existing = bucket.get(key)
    if existing is None or score_score_row(row) >= score_score_row(existing):
        bucket[key] = row


def load_previous_score_index(source: SourceProject, current_run_id: str) -> tuple[dict[str, dict[str, dict[str, Any]]], list[str]]:
    by_canonical: dict[str, dict[str, Any]] = {}
    by_source_url: dict[str, dict[str, Any]] = {}
    by_name_date: dict[str, dict[str, Any]] = {}
    if not source.score_dir.exists():
        return {"by_canonical": by_canonical, "by_source_url": by_source_url, "by_name_date": by_name_date}, []

    run_dirs = sorted([p for p in source.score_dir.iterdir() if p.is_dir()], key=lambda p: p.name)
    run_ids: list[str] = []
    for run_dir in run_dirs:
        if current_run_id and run_dir.name == current_run_id:
            continue
        jsonl_path = run_dir / "events_scores.jsonl"
        if not jsonl_path.exists():
            continue
        run_ids.append(run_dir.name)
        with jsonl_path.open("r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    row = json.loads(line)
                except json.JSONDecodeError:
                    continue
                canonical_id = nonempty(row.get("canonical_id"))
                if canonical_id:
                    _put_score_if_better(by_canonical, row, canonical_id)
                for source_url in normalize_string_list(row.get("source_urls")):
                    _put_score_if_better(by_source_url, row, source_url)
                name_date_key = build_name_date_key(row.get("event_name"), row.get("event_date_start"))
                if name_date_key:
                    _put_score_if_better(by_name_date, row, name_date_key)
    return {"by_canonical": by_canonical, "by_source_url": by_source_url, "by_name_date": by_name_date}, run_ids


def resolve_previous_score_row(row: dict[str, Any], index: dict[str, dict[str, dict[str, Any]]]) -> dict[str, Any] | None:
    canonical = nonempty(row.get("canonical_id")) or ""
    candidates: list[dict[str, Any]] = []
    seen: set[int] = set()

    if canonical and canonical in index["by_canonical"]:
        candidate = index["by_canonical"][canonical]
        if rows_look_same_event(row, candidate):
            candidates.append(candidate)
            seen.add(id(candidate))
    for source_url in normalize_string_list(row.get("source_urls")):
        matched = index["by_source_url"].get(source_url)
        if not matched:
            continue
        if id(matched) in seen:
            continue
        if not rows_look_same_event(row, matched):
            continue
        candidates.append(matched)
        seen.add(id(matched))
    key = build_name_date_key(row.get("event_name"), row.get("event_date_start"))
    if key:
        matched = index["by_name_date"].get(key)
        if matched and id(matched) not in seen and rows_look_same_event(row, matched):
            candidates.append(matched)
            seen.add(id(matched))
    if not candidates:
        return None
    candidates.sort(key=score_score_row, reverse=True)
    return candidates[0]


def fallback_scores(row: dict[str, Any], category: str) -> tuple[int, int, str]:
    source_count = parse_number(row.get("source_count")) or 1
    launch_count = parse_number(row.get("launch_count")) or 0
    visitors = parse_number(row.get("expected_visitors")) or 0
    base = 42 + min(source_count * 7, 22)
    if category == "hanabi":
        base += 5
    if launch_count > 0:
        base += min(int(launch_count**0.5 / 3), 18)
    if visitors > 0:
        base += min(int(visitors**0.5 / 9), 18)
    initial_heat = clamp(base, 20, 95)
    surprise = clamp(45 + ((initial_heat * 29) % 41), 12, 96)
    return initial_heat, surprise, "heuristic"


def parse_score_value(raw: Any) -> int | None:
    if raw is None:
        return None
    if isinstance(raw, (int, float)):
        return clamp(int(round(float(raw))), 0, 100)
    text = clean_text(raw)
    if not text:
        return None
    m = re.search(r"-?\d+(?:\.\d+)?", text)
    if not m:
        return None
    try:
        return clamp(int(round(float(m.group(0)))), 0, 100)
    except ValueError:
        return None


def build_model_input(row: dict[str, Any], content_row: dict[str, Any] | None, category: str) -> dict[str, Any]:
    description = ""
    one_liner = ""
    if content_row:
        description = clean_text_block(content_row.get("polished_description")) or clean_text_block(content_row.get("raw_description"))
        one_liner = clean_text_block(content_row.get("one_liner"))

    source_urls = normalize_string_list(row.get("source_urls"))
    return {
        "category": category,
        "event_name": clean_text(row.get("event_name")),
        "event_date_start": clean_text(row.get("event_date_start")),
        "event_date_end": clean_text(row.get("event_date_end")),
        "event_time_start": clean_text(row.get("event_time_start")),
        "event_time_end": clean_text(row.get("event_time_end")),
        "prefecture": clean_text(row.get("prefecture")),
        "city": clean_text(row.get("city")),
        "venue_name": clean_text(row.get("venue_name")),
        "venue_address": clean_text(row.get("venue_address")),
        "launch_count": clean_text(row.get("launch_count")),
        "launch_scale": clean_text(row.get("launch_scale")),
        "paid_seat": clean_text(row.get("paid_seat")),
        "organizer": clean_text(row.get("organizer")),
        "festival_type": clean_text(row.get("festival_type")),
        "admission_fee": clean_text(row.get("admission_fee")),
        "expected_visitors": clean_text(row.get("expected_visitors")),
        "access_text": clean_text(row.get("access_text")),
        "parking_text": clean_text(row.get("parking_text")),
        "traffic_control_text": clean_text(row.get("traffic_control_text")),
        "description_jp": description[:2000],
        "one_liner_jp": one_liner[:240],
        "source_urls": source_urls[:3],
    }


def input_hash(payload: dict[str, Any]) -> str:
    raw = json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def estimate_start_distance_days(event_date_start: Any) -> tuple[int, int]:
    d = parse_iso_date(extract_date(event_date_start) or "")
    if d is None:
        return (1, 10_000_000)
    today = date.today()
    delta = (d - today).days
    return (0, abs(delta))


def upsert_latest_run(source: SourceProject, *, run_id: str, summary_rel: str, jsonl_rel: str) -> None:
    latest = load_latest_meta(source)
    latest["score_run_id"] = run_id
    latest["score_generated_at"] = datetime.now(timezone.utc).isoformat()
    latest["score_summary"] = summary_rel
    latest["score_events_jsonl"] = jsonl_rel
    source.latest_run_path.parent.mkdir(parents=True, exist_ok=True)
    source.latest_run_path.write_text(json.dumps(latest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    source = make_source(args.project)
    latest_meta = load_latest_meta(source)

    fused_run_id = clean_text(args.fused_run_id) or clean_text(latest_meta.get("fused_run_id"))
    if not fused_run_id:
        raise RuntimeError("fused_run_id is missing; provide --fused-run-id or set data/latest_run.json")
    content_run_id = clean_text(args.content_run_id) or clean_text(latest_meta.get("content_run_id"))

    run_id = clean_text(args.run_id) or datetime.now().strftime("%Y%m%d_%H%M%S_score")
    run_dir = source.score_dir / run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    prompt_file = args.prompt_file
    if not prompt_file.exists():
        raise FileNotFoundError(f"prompt file not found: {prompt_file}")
    prompt_template = prompt_file.read_text(encoding="utf-8")

    fused_rows = load_fused_rows(source, fused_run_id)
    content_index, content_runs = load_content_index(source, content_run_id)
    previous_index, previous_runs = load_previous_score_index(source, run_id)

    items: list[tuple[dict[str, Any], dict[str, Any] | None, dict[str, Any] | None, dict[str, Any], str]] = []
    for row in fused_rows:
        content_row = resolve_content_row(row, content_index)
        prev_row = resolve_previous_score_row(row, previous_index)
        model_input = build_model_input(row, content_row, source.category)
        sig = input_hash(model_input)
        items.append((row, content_row, prev_row, model_input, sig))

    if args.prioritize_near_start:
        items.sort(
            key=lambda item: (
                *estimate_start_distance_days(item[0].get("event_date_start")),
                clean_text(item[0].get("event_name")),
            )
        )

    deepseek_key = clean_text(args.deepseek_api_key)
    analyzer: DeepSeekScoreAnalyzer | None = None
    if deepseek_key:
        try:
            analyzer = DeepSeekScoreAnalyzer(
                api_key=deepseek_key,
                model=args.deepseek_model,
                base_url=args.deepseek_base_url,
                timeout_sec=max(10.0, float(args.timeout_sec)),
                prompt_template=prompt_template,
            )
        except Exception as exc:  # noqa: BLE001
            print(f"[warn] DeepSeek analyzer init failed, fallback mode enabled: {exc}")
            analyzer = None
    else:
        print("[warn] DEEPSEEK API key is empty; scores will use heuristic fallback")

    limiter = RateLimiter(max(0.0, float(args.qps)))
    max_events = max(0, int(args.max_events))
    api_calls = 0

    out_rows: list[dict[str, Any]] = []
    stats = {
        "total": len(items),
        "ai_ok": 0,
        "ai_failed": 0,
        "reused_ok": 0,
        "fallback": 0,
        "skipped_max_events": 0,
    }

    for row, _content_row, prev_row, model_input, sig in items:
        canonical_id = clean_text(row.get("canonical_id"))
        event_name = clean_text(row.get("event_name"))
        event_date_start = clean_text(row.get("event_date_start"))
        source_urls = normalize_string_list(row.get("source_urls"))
        reused = False

        if prev_row:
            prev_status = clean_text(prev_row.get("status")).lower()
            prev_hash = clean_text(prev_row.get("input_hash"))
            if prev_status == "ok":
                if args.failed_only:
                    reused = True
                elif prev_hash and prev_hash == sig:
                    reused = True
            elif prev_status.startswith("cached"):
                if prev_hash and prev_hash == sig:
                    reused = True

        if reused and prev_row is not None:
            reused_row = dict(prev_row)
            reused_row["status"] = "cached_ok"
            reused_row["generated_at"] = datetime.now(timezone.utc).isoformat()
            out_rows.append(reused_row)
            stats["reused_ok"] += 1
            continue

        if max_events > 0 and api_calls >= max_events:
            initial_heat, surprise, reason = fallback_scores(row, source.category)
            out_rows.append(
                {
                    "canonical_id": canonical_id,
                    "event_name": event_name,
                    "event_date_start": event_date_start,
                    "source_urls": source_urls,
                    "initial_heat_score": initial_heat,
                    "surprise_score": surprise,
                    "reason": reason,
                    "status": "fallback_max_events",
                    "score_source": "fallback",
                    "score_provider": "local",
                    "score_model": "",
                    "input_hash": sig,
                    "error": "max_events_reached",
                    "generated_at": datetime.now(timezone.utc).isoformat(),
                }
            )
            stats["fallback"] += 1
            stats["skipped_max_events"] += 1
            continue

        if analyzer is None:
            initial_heat, surprise, reason = fallback_scores(row, source.category)
            out_rows.append(
                {
                    "canonical_id": canonical_id,
                    "event_name": event_name,
                    "event_date_start": event_date_start,
                    "source_urls": source_urls,
                    "initial_heat_score": initial_heat,
                    "surprise_score": surprise,
                    "reason": reason,
                    "status": "fallback_no_api_key",
                    "score_source": "fallback",
                    "score_provider": "local",
                    "score_model": "",
                    "input_hash": sig,
                    "error": "missing_api_key",
                    "generated_at": datetime.now(timezone.utc).isoformat(),
                }
            )
            stats["fallback"] += 1
            continue

        limiter.wait()
        api_calls += 1
        error = ""
        try:
            data = analyzer.analyze(model_input)
            initial_heat = parse_score_value(data.get("initial_heat_score"))
            surprise = parse_score_value(data.get("surprise_score"))
            reason = clean_text_block(data.get("reason"))[:DEFAULT_MAX_REASON_CHARS]
            if initial_heat is None or surprise is None:
                raise ValueError("missing initial_heat_score/surprise_score in model output")
            out_rows.append(
                {
                    "canonical_id": canonical_id,
                    "event_name": event_name,
                    "event_date_start": event_date_start,
                    "source_urls": source_urls,
                    "initial_heat_score": initial_heat,
                    "surprise_score": surprise,
                    "reason": reason,
                    "status": "ok",
                    "score_source": "ai",
                    "score_provider": "deepseek",
                    "score_model": clean_text(args.deepseek_model) or DEFAULT_DEEPSEEK_MODEL,
                    "input_hash": sig,
                    "error": "",
                    "generated_at": datetime.now(timezone.utc).isoformat(),
                }
            )
            stats["ai_ok"] += 1
        except Exception as exc:  # noqa: BLE001
            error = clean_text(str(exc))[:300]
            initial_heat, surprise, reason = fallback_scores(row, source.category)
            out_rows.append(
                {
                    "canonical_id": canonical_id,
                    "event_name": event_name,
                    "event_date_start": event_date_start,
                    "source_urls": source_urls,
                    "initial_heat_score": initial_heat,
                    "surprise_score": surprise,
                    "reason": reason,
                    "status": "fallback_ai_error",
                    "score_source": "fallback",
                    "score_provider": "local",
                    "score_model": "",
                    "input_hash": sig,
                    "error": error,
                    "generated_at": datetime.now(timezone.utc).isoformat(),
                }
            )
            stats["ai_failed"] += 1
            stats["fallback"] += 1

    if analyzer:
        analyzer.close()

    # Stable output ordering by canonical id for downstream diff-friendliness.
    out_rows.sort(key=lambda x: (clean_text(x.get("canonical_id")), clean_text(x.get("event_name"))))

    jsonl_path = run_dir / "events_scores.jsonl"
    with jsonl_path.open("w", encoding="utf-8") as f:
        for row in out_rows:
            f.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")

    csv_path = run_dir / "events_scores.csv"
    fieldnames = [
        "canonical_id",
        "event_name",
        "event_date_start",
        "source_urls",
        "initial_heat_score",
        "surprise_score",
        "reason",
        "status",
        "score_source",
        "score_provider",
        "score_model",
        "input_hash",
        "error",
        "generated_at",
    ]
    with csv_path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in out_rows:
            csv_row = dict(row)
            if isinstance(csv_row.get("source_urls"), list):
                csv_row["source_urls"] = "|".join(str(x) for x in csv_row["source_urls"])
            writer.writerow(csv_row)

    summary = {
        "project": source.name,
        "category": source.category,
        "run_id": run_id,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "fused_run_id": fused_run_id,
        "content_run_id": content_run_id,
        "score_model": clean_text(args.deepseek_model) or DEFAULT_DEEPSEEK_MODEL,
        "score_base_url": clean_text(args.deepseek_base_url),
        "qps": float(args.qps),
        "max_events": int(args.max_events),
        "failed_only": bool(args.failed_only),
        "prioritize_near_start": bool(args.prioritize_near_start),
        "stats": stats,
        "content_runs_seen": content_runs,
        "previous_score_runs_seen": previous_runs,
        "files": {
            "events_scores_jsonl": str(jsonl_path),
            "events_scores_csv": str(csv_path),
        },
    }
    summary_path = run_dir / "score_summary.json"
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    if args.update_latest_run:
        upsert_latest_run(
            source,
            run_id=run_id,
            summary_rel=str(summary_path.relative_to(source.root)),
            jsonl_rel=str(jsonl_path.relative_to(source.root)),
        )

    print(f"[ok] score run complete: project={source.name} run_id={run_id}")
    print(f"[ok] output jsonl: {jsonl_path}")
    print(f"[ok] output csv: {csv_path}")
    print(f"[ok] summary: {summary_path}")
    print(
        f"[ok] stats: total={stats['total']} ai_ok={stats['ai_ok']} ai_failed={stats['ai_failed']} "
        f"reused_ok={stats['reused_ok']} fallback={stats['fallback']} skipped_max_events={stats['skipped_max_events']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
