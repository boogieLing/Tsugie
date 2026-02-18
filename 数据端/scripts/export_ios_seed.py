#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import tempfile
import uuid
import zlib
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_KEY = "tsugie-ios-seed-v1"
DEFAULT_GEOHASH_PRECISION = 5
DEFAULT_IMAGE_MAX_PX = 1280
DEFAULT_IMAGE_QUALITY = 68
GEOHASH_ALPHABET = "0123456789bcdefghjkmnpqrstuvwxyz"


@dataclass(frozen=True)
class SourceConfig:
    category: str
    latest_run_path: Path
    fused_dir: Path
    content_dir: Path


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(
        description="Export latest HANABI/OMATSURI fused data to iOS geospatial package"
    )
    parser.add_argument(
        "--index-output",
        type=Path,
        default=repo_root / "ios开发/tsugie/tsugie/Resources/he_places.index.json",
        help="Output spatial index JSON path",
    )
    parser.add_argument(
        "--payload-output",
        type=Path,
        default=repo_root / "ios开发/tsugie/tsugie/Resources/he_places.payload.bin",
        help="Output payload binary path",
    )
    parser.add_argument(
        "--image-payload-output",
        type=Path,
        default=repo_root / "ios开发/tsugie/tsugie/Resources/he_images.payload.bin",
        help="Output image payload binary path",
    )
    parser.add_argument(
        "--key",
        default=DEFAULT_KEY,
        help="Obfuscation key seed (same key must be used by iOS decoder)",
    )
    parser.add_argument(
        "--geohash-precision",
        type=int,
        default=DEFAULT_GEOHASH_PRECISION,
        help="Geohash precision used for spatial buckets",
    )
    parser.add_argument(
        "--image-max-px",
        type=int,
        default=DEFAULT_IMAGE_MAX_PX,
        help="Resize longest side of image to this max pixel size",
    )
    parser.add_argument(
        "--image-quality",
        type=int,
        default=DEFAULT_IMAGE_QUALITY,
        help="JPEG quality for image payload (1-100)",
    )
    parser.add_argument(
        "--pretty",
        action="store_true",
        help="Pretty-print index JSON",
    )
    return parser.parse_args()


def load_latest_fused_records(source: SourceConfig) -> tuple[list[dict[str, Any]], str]:
    with source.latest_run_path.open("r", encoding="utf-8") as f:
        latest = json.load(f)
    run_id = str(latest["fused_run_id"])
    fused_file = source.fused_dir / run_id / "events_fused.jsonl"
    if not fused_file.exists():
        raise FileNotFoundError(f"fused data not found: {fused_file}")

    rows: list[dict[str, Any]] = []
    with fused_file.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rows.append(json.loads(line))
    return rows, run_id


def nonempty(raw: Any) -> str | None:
    if raw is None:
        return None
    text = str(raw).strip()
    return text or None


def normalize_string_list(raw: Any) -> list[str]:
    if isinstance(raw, list):
        return [value for item in raw if (value := nonempty(item))]
    if isinstance(raw, str):
        if "|" in raw:
            return [part for part in (x.strip() for x in raw.split("|")) if part]
        value = raw.strip()
        return [value] if value else []
    return []


def is_generic_image_url(url: str) -> bool:
    low = url.lower()
    if low.endswith("/img/header.jpg") or low.endswith("/img/header.jpeg") or low.endswith("/img/header.png"):
        return True
    if "ogp0.png" in low:
        return True
    return False


def score_content_entry(row: dict[str, Any]) -> tuple[int, int, int, int, str]:
    status_rank = {
        "ok": 4,
        "cached": 3,
        "partial": 2,
        "empty": 1,
    }.get(str(row.get("status", "")).lower(), 0)

    polished_desc = nonempty(row.get("polished_description")) or ""
    one_liner = nonempty(row.get("one_liner")) or ""
    raw_desc = nonempty(row.get("raw_description")) or ""
    image_urls = normalize_string_list(row.get("image_urls"))
    local_images = normalize_string_list(row.get("downloaded_images"))

    def has_bad_text(text: str) -> bool:
        return "\uFFFD" in text

    def looks_generic_description(text: str) -> bool:
        low = text.lower()
        if "今日は何の祭り" in text:
            return True
        if "一覧形式で紹介" in text:
            return True
        if "お祭り日程" in text and "スケジュール" in text:
            return True
        return "festival schedule" in low

    desc_quality = 0
    if polished_desc:
        desc_quality = 2
        if has_bad_text(polished_desc) or looks_generic_description(polished_desc):
            desc_quality = 1
    elif raw_desc:
        desc_quality = 1
        if has_bad_text(raw_desc) or looks_generic_description(raw_desc):
            desc_quality = 0

    one_liner_quality = 0
    if one_liner:
        one_liner_quality = 2
        if has_bad_text(one_liner) or looks_generic_description(one_liner):
            one_liner_quality = 1

    has_non_generic_image = 0
    if local_images:
        if image_urls:
            has_non_generic_image = 1 if any(not is_generic_image_url(u) for u in image_urls) else 0
        else:
            has_non_generic_image = 1

    fetched_at = nonempty(row.get("fetched_at")) or ""
    return (status_rank, desc_quality, one_liner_quality, has_non_generic_image, fetched_at)


def load_content_index(source: SourceConfig, fused_run_id: str) -> tuple[dict[str, dict[str, Any]], list[str]]:
    result: dict[str, dict[str, Any]] = {}
    run_ids: list[str] = []
    if not source.content_dir.exists():
        return result, run_ids

    run_dirs = sorted([path for path in source.content_dir.iterdir() if path.is_dir()], key=lambda p: p.name)
    for run_dir in run_dirs:
        jsonl_path = run_dir / "events_content.jsonl"
        summary_path = run_dir / "content_summary.json"
        if not jsonl_path.exists():
            continue

        summary: dict[str, Any] = {}
        if summary_path.exists():
            try:
                summary = json.loads(summary_path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                summary = {}
        summary_fused = nonempty(summary.get("fused_run_id"))
        if summary_fused and summary_fused != fused_run_id:
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
                if not canonical_id:
                    continue
                existing = result.get(canonical_id)
                if existing is None or score_content_entry(row) >= score_content_entry(existing):
                    result[canonical_id] = row

    return result, run_ids


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


def extract_time(raw: Any) -> str | None:
    if raw is None:
        return None
    text = str(raw)
    m = re.search(r"([01]?\d|2[0-3])[:：]([0-5]\d)", text)
    if m:
        return f"{int(m.group(1)):02d}:{int(m.group(2)):02d}"
    m = re.search(r"([01]?\d|2[0-3])\s*時\s*([0-5]?\d)\s*分", text)
    if m:
        return f"{int(m.group(1)):02d}:{int(m.group(2)):02d}"
    return None


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


def clamp(v: int, lo: int, hi: int) -> int:
    return max(lo, min(hi, v))


def derive_scores(row: dict[str, Any], category: str) -> tuple[int, int, int]:
    source_count_raw = row.get("source_count")
    if isinstance(source_count_raw, int):
        source_count = source_count_raw
    else:
        source_count = parse_number(source_count_raw) or 1

    launch_count = parse_number(row.get("launch_count")) or 0
    visitors = parse_number(row.get("expected_visitors")) or 0

    base = 40 + min(source_count * 8, 24)
    if launch_count > 0:
        base += min(int(launch_count**0.5 / 3), 24)
    if visitors > 0:
        base += min(int(visitors**0.5 / 8), 20)
    if str(row.get("update_priority", "")).lower() == "high":
        base -= 4
    if category == "hanabi":
        base += 6

    scale = clamp(base, 25, 99)
    heat = clamp(scale + 6, 20, 100)
    surprise = clamp(52 + ((scale * 37) % 39), 15, 98)
    return scale, heat, surprise


def derive_distance_by_hash(canonical_id: str) -> float:
    digest = hashlib.sha256(canonical_id.encode("utf-8")).digest()
    seed = int.from_bytes(digest[:4], byteorder="big", signed=False)
    return float(280 + (seed % 5200))


def parse_coordinate(row: dict[str, Any]) -> tuple[float, float] | None:
    raw_lat = row.get("lat")
    raw_lng = row.get("lng")
    try:
        lat = float(raw_lat)
        lng = float(raw_lng)
    except (TypeError, ValueError):
        return None
    if not (-90 <= lat <= 90 and -180 <= lng <= 180):
        return None
    return lat, lng


def geohash_encode(lat: float, lng: float, precision: int) -> str:
    lat_lo, lat_hi = -90.0, 90.0
    lng_lo, lng_hi = -180.0, 180.0
    is_lng = True
    bit = 0
    ch = 0
    out: list[str] = []
    bits = (16, 8, 4, 2, 1)

    while len(out) < precision:
        if is_lng:
            mid = (lng_lo + lng_hi) / 2
            if lng >= mid:
                ch |= bits[bit]
                lng_lo = mid
            else:
                lng_hi = mid
        else:
            mid = (lat_lo + lat_hi) / 2
            if lat >= mid:
                ch |= bits[bit]
                lat_lo = mid
            else:
                lat_hi = mid

        is_lng = not is_lng
        if bit < 4:
            bit += 1
        else:
            out.append(GEOHASH_ALPHABET[ch])
            bit = 0
            ch = 0

    return "".join(out)


def derive_hint(row: dict[str, Any], category: str) -> str:
    pref = str(row.get("prefecture") or "").strip()
    city = str(row.get("city") or "").strip()
    source_count = row.get("source_count")
    if not isinstance(source_count, int):
        source_count = parse_number(source_count) or 1
    location = city or pref or "開催地確認中"
    type_hint = "花火" if category == "hanabi" else "祭典"
    return f"{location}・{type_hint}候補（{source_count}ソース統合）"


def build_entry(
    category: str,
    row: dict[str, Any],
    geohash_precision: int,
    content_row: dict[str, Any] | None,
    repo_root: Path,
) -> dict[str, Any]:
    canonical_id = str(row.get("canonical_id") or "").strip() or str(uuid.uuid4())
    place_id = str(uuid.uuid5(uuid.NAMESPACE_URL, f"tsugie:{category}:{canonical_id}"))

    scale_score, heat_score, surprise_score = derive_scores(row, category)
    start_date = extract_date(row.get("event_date_start"))
    end_date = extract_date(row.get("event_date_end"))
    start_time = extract_time(row.get("event_time_start"))
    end_time = extract_time(row.get("event_time_end"))

    geohash: str | None = None
    coord = parse_coordinate(row)
    if coord is not None:
        lat, lng = coord
        geohash = geohash_encode(lat, lng, geohash_precision)

    source_urls = normalize_string_list(row.get("source_urls"))
    content_description = None
    content_one_liner = None
    content_source_url = source_urls[0] if source_urls else None
    content_image_source_url = None
    image_local_abs = None
    image_local_rel = None

    if content_row:
        content_description = nonempty(content_row.get("polished_description")) or nonempty(content_row.get("raw_description"))
        content_one_liner = nonempty(content_row.get("one_liner"))
        description_source = nonempty(content_row.get("description_source_url"))
        content_source_urls = normalize_string_list(content_row.get("source_urls"))
        if content_source_urls:
            source_urls = content_source_urls
        if description_source:
            content_source_url = description_source
        elif source_urls:
            content_source_url = source_urls[0]

        content_image_urls = normalize_string_list(content_row.get("image_urls"))
        downloaded_images = normalize_string_list(content_row.get("downloaded_images"))
        non_generic_indices = [idx for idx, u in enumerate(content_image_urls) if not is_generic_image_url(u)]

        if non_generic_indices:
            content_image_source_url = content_image_urls[non_generic_indices[0]]
        elif content_image_urls:
            content_image_source_url = None

        candidate_rel_paths: list[str] = []
        if non_generic_indices and downloaded_images:
            candidate_rel_paths.extend(
                downloaded_images[idx] for idx in non_generic_indices if 0 <= idx < len(downloaded_images)
            )
        elif not content_image_urls:
            candidate_rel_paths.extend(downloaded_images)

        for rel_path in candidate_rel_paths:
            candidate_roots = [repo_root]
            if category == "hanabi":
                candidate_roots.append(repo_root / "数据端/HANABI")
            elif category == "matsuri":
                candidate_roots.append(repo_root / "数据端/OMATSURI")

            for root in candidate_roots:
                candidate = (root / rel_path).resolve()
                if candidate.exists() and candidate.is_file():
                    image_local_abs = str(candidate)
                    image_local_rel = rel_path
                    break
            if image_local_abs:
                break

    return {
        "category": category,
        "canonical_id": canonical_id,
        "ios_place_id": place_id,
        "distance_meters": derive_distance_by_hash(canonical_id),
        "scale_score": scale_score,
        "heat_score": heat_score,
        "surprise_score": surprise_score,
        "hint": derive_hint(row, category),
        "normalized_start_date": start_date,
        "normalized_end_date": end_date,
        "normalized_start_time": start_time,
        "normalized_end_time": end_time,
        "geohash": geohash,
        "content_description": content_description,
        "content_one_liner": content_one_liner,
        "content_source_urls": source_urls,
        "content_description_source_url": content_source_url,
        "content_image_source_url": content_image_source_url,
        "_image_local_abs": image_local_abs,
        "_image_local_rel": image_local_rel,
        "record": row,
    }


def xor_obfuscate(data: bytes, key_seed: str) -> bytes:
    key = hashlib.sha256(key_seed.encode("utf-8")).digest()
    out = bytearray(len(data))
    for idx, b in enumerate(data):
        mix = (idx * 131 + 17) & 0xFF
        out[idx] = b ^ key[idx % len(key)] ^ mix
    return bytes(out)


def build_payload_bytes(entries: list[dict[str, Any]], key_seed: str) -> tuple[bytes, str]:
    raw = json.dumps(entries, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    compressed = zlib.compress(raw, level=9)
    obfuscated = xor_obfuscate(compressed, key_seed)
    checksum = hashlib.sha256(raw).hexdigest()

    decoded = zlib.decompress(xor_obfuscate(obfuscated, key_seed))
    if decoded != raw:
        raise RuntimeError("payload codec self-check failed")
    return obfuscated, checksum


def count_by_category(entries: list[dict[str, Any]]) -> dict[str, int]:
    hanabi = sum(1 for entry in entries if entry.get("category") == "hanabi")
    matsuri = sum(1 for entry in entries if entry.get("category") == "matsuri")
    return {
        "hanabi": hanabi,
        "matsuri": matsuri,
        "total": len(entries),
    }


def build_spatial_payload(
    entries: list[dict[str, Any]],
    key_seed: str,
) -> tuple[dict[str, dict[str, Any]], bytes]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    for entry in entries:
        key = entry.get("geohash") or "_unknown"
        grouped.setdefault(str(key), []).append(entry)

    payload = bytearray()
    bucket_meta: dict[str, dict[str, Any]] = {}

    for key in sorted(grouped.keys()):
        rows = grouped[key]
        rows.sort(key=lambda x: str(x.get("ios_place_id", "")))
        chunk, checksum = build_payload_bytes(rows, key_seed)

        offset = len(payload)
        payload.extend(chunk)
        bucket_meta[key] = {
            "record_count": len(rows),
            "payload_sha256": checksum,
            "payload_offset": offset,
            "payload_length": len(chunk),
        }

    return bucket_meta, bytes(payload)


def build_binary_payload_bytes(raw: bytes, key_seed: str) -> tuple[bytes, str]:
    compressed = zlib.compress(raw, level=9)
    obfuscated = xor_obfuscate(compressed, key_seed)
    checksum = hashlib.sha256(raw).hexdigest()
    decoded = zlib.decompress(xor_obfuscate(obfuscated, key_seed))
    if decoded != raw:
        raise RuntimeError("binary payload codec self-check failed")
    return obfuscated, checksum


def compress_image_to_jpeg_bytes(image_path: str, max_px: int, quality: int) -> bytes | None:
    safe_quality = clamp(quality, 1, 100)
    safe_max_px = max(200, max_px)
    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
        out_path = Path(tmp.name)
    try:
        cmd = [
            "sips",
            "-s",
            "format",
            "jpeg",
            "-s",
            "formatOptions",
            str(safe_quality),
            "-Z",
            str(safe_max_px),
            image_path,
            "--out",
            str(out_path),
        ]
        proc = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        if proc.returncode != 0 or not out_path.exists() or out_path.stat().st_size == 0:
            return None
        return out_path.read_bytes()
    finally:
        out_path.unlink(missing_ok=True)


def attach_image_payload(
    entries: list[dict[str, Any]],
    key_seed: str,
    image_max_px: int,
    image_quality: int,
) -> tuple[bytes, dict[str, int]]:
    payload = bytearray()
    encoded_by_hash: dict[str, dict[str, Any]] = {}
    encoded_cache_by_path: dict[str, tuple[bytes, str]] = {}
    stats = {
        "with_image_ref": 0,
        "without_image_ref": 0,
        "source_attempted": 0,
        "source_compressed": 0,
        "source_failed": 0,
        "unique_chunks": 0,
    }

    for entry in entries:
        image_local_abs = nonempty(entry.pop("_image_local_abs", None))
        image_local_rel = nonempty(entry.pop("_image_local_rel", None))
        if not image_local_abs:
            stats["without_image_ref"] += 1
            continue

        stats["source_attempted"] += 1
        cached = encoded_cache_by_path.get(image_local_abs)
        if cached is None:
            image_bytes = compress_image_to_jpeg_bytes(image_local_abs, max_px=image_max_px, quality=image_quality)
            if not image_bytes:
                stats["source_failed"] += 1
                stats["without_image_ref"] += 1
                continue
            encoded_chunk, raw_sha = build_binary_payload_bytes(image_bytes, key_seed)
            encoded_cache_by_path[image_local_abs] = (encoded_chunk, raw_sha)
            stats["source_compressed"] += 1
        else:
            encoded_chunk, raw_sha = cached

        ref = encoded_by_hash.get(raw_sha)
        if ref is None:
            offset = len(payload)
            payload.extend(encoded_chunk)
            ref = {
                "payload_offset": offset,
                "payload_length": len(encoded_chunk),
                "payload_sha256": raw_sha,
            }
            encoded_by_hash[raw_sha] = ref
            stats["unique_chunks"] += 1

        entry["image_payload_offset"] = ref["payload_offset"]
        entry["image_payload_length"] = ref["payload_length"]
        entry["image_payload_sha256"] = ref["payload_sha256"]
        entry["content_image_local_path"] = image_local_rel
        stats["with_image_ref"] += 1

    for entry in entries:
        if "_image_local_abs" in entry:
            entry.pop("_image_local_abs", None)
        if "_image_local_rel" in entry:
            entry.pop("_image_local_rel", None)

    return bytes(payload), stats


def count_content_fields(entries: list[dict[str, Any]]) -> dict[str, int]:
    return {
        "with_description": sum(1 for e in entries if nonempty(e.get("content_description"))),
        "with_one_liner": sum(1 for e in entries if nonempty(e.get("content_one_liner"))),
        "with_source_urls": sum(1 for e in entries if normalize_string_list(e.get("content_source_urls"))),
        "with_image_ref": sum(
            1
            for e in entries
            if isinstance(e.get("image_payload_offset"), int) and int(e.get("image_payload_length") or 0) > 0
        ),
    }


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[2]

    geohash_precision = int(args.geohash_precision)
    if geohash_precision < 3 or geohash_precision > 8:
        raise ValueError("--geohash-precision must be between 3 and 8")

    hanabi_source = SourceConfig(
        category="hanabi",
        latest_run_path=repo_root / "数据端/HANABI/data/latest_run.json",
        fused_dir=repo_root / "数据端/HANABI/data/fused",
        content_dir=repo_root / "数据端/HANABI/data/content",
    )
    omatsuri_source = SourceConfig(
        category="matsuri",
        latest_run_path=repo_root / "数据端/OMATSURI/data/latest_run.json",
        fused_dir=repo_root / "数据端/OMATSURI/data/fused",
        content_dir=repo_root / "数据端/OMATSURI/data/content",
    )

    hanabi_rows, hanabi_run_id = load_latest_fused_records(hanabi_source)
    omatsuri_rows, omatsuri_run_id = load_latest_fused_records(omatsuri_source)
    hanabi_content_map, hanabi_content_runs = load_content_index(hanabi_source, hanabi_run_id)
    omatsuri_content_map, omatsuri_content_runs = load_content_index(omatsuri_source, omatsuri_run_id)

    entries: list[dict[str, Any]] = []
    for row in hanabi_rows:
        canonical_id = nonempty(row.get("canonical_id")) or ""
        entries.append(
            build_entry(
                hanabi_source.category,
                row,
                geohash_precision,
                hanabi_content_map.get(canonical_id),
                repo_root,
            )
        )
    for row in omatsuri_rows:
        canonical_id = nonempty(row.get("canonical_id")) or ""
        entries.append(
            build_entry(
                omatsuri_source.category,
                row,
                geohash_precision,
                omatsuri_content_map.get(canonical_id),
                repo_root,
            )
        )
    entries.sort(key=lambda x: x["ios_place_id"])

    image_payload, image_stats = attach_image_payload(
        entries,
        key_seed=args.key,
        image_max_px=max(200, int(args.image_max_px)),
        image_quality=clamp(int(args.image_quality), 1, 100),
    )

    bucket_meta, payload = build_spatial_payload(entries, args.key)
    content_counts = count_content_fields(entries)

    index_doc = {
        "version": 4,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "codec": {
            "compression": "zlib",
            "obfuscation": "xor_sha256_stream_v1",
            "encoding": "binary_frame_v1",
            "charset": "utf-8",
        },
        "source_runs": {
            "hanabi_fused_run_id": hanabi_run_id,
            "omatsuri_fused_run_id": omatsuri_run_id,
            "hanabi_content_runs": hanabi_content_runs,
            "omatsuri_content_runs": omatsuri_content_runs,
        },
        "record_counts": {
            **count_by_category(entries),
        },
        "content_counts": content_counts,
        "spatial_index": {
            "scheme": "geohash_prefix_v1",
            "precision": geohash_precision,
            "bucket_count": len(bucket_meta),
        },
        "payload_file": args.payload_output.name,
        "payload_sha256": hashlib.sha256(payload).hexdigest(),
        "payload_size_bytes": len(payload),
        "payload_buckets": bucket_meta,
        "image_payload": {
            "file": args.image_payload_output.name,
            "sha256": hashlib.sha256(image_payload).hexdigest(),
            "size_bytes": len(image_payload),
            "entry_count": image_stats["with_image_ref"],
            "codec": {
                "compression": "zlib",
                "obfuscation": "xor_sha256_stream_v1",
                "encoding": "binary_frame_v1",
                "image_format": "jpeg",
                "max_px": max(200, int(args.image_max_px)),
                "quality": clamp(int(args.image_quality), 1, 100),
            },
        },
    }

    args.index_output.parent.mkdir(parents=True, exist_ok=True)
    args.payload_output.parent.mkdir(parents=True, exist_ok=True)
    args.image_payload_output.parent.mkdir(parents=True, exist_ok=True)

    with args.index_output.open("w", encoding="utf-8") as f:
        if args.pretty:
            json.dump(index_doc, f, ensure_ascii=False, indent=2)
            f.write("\n")
        else:
            json.dump(index_doc, f, ensure_ascii=False, separators=(",", ":"))

    args.payload_output.write_bytes(payload)
    args.image_payload_output.write_bytes(image_payload)

    print(f"[ok] exported spatial index -> {args.index_output}")
    print(f"[ok] exported payload bin -> {args.payload_output}")
    print(f"[ok] exported image payload bin -> {args.image_payload_output}")
    print(f"[ok] runs: hanabi={hanabi_run_id} omatsuri={omatsuri_run_id}")
    print(f"[ok] records: {len(entries)}")
    print(f"[ok] geohash_precision: {geohash_precision}")
    print(f"[ok] bucket_count: {len(bucket_meta)}")
    print(f"[ok] payload_size_bytes: {len(payload)}")
    print(f"[ok] image_payload_size_bytes: {len(image_payload)}")
    print(
        f"[ok] content_counts: description={content_counts['with_description']} "
        f"one_liner={content_counts['with_one_liner']} "
        f"source_urls={content_counts['with_source_urls']} "
        f"images={content_counts['with_image_ref']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
