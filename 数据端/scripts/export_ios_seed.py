#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import uuid
import zlib
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_KEY = "tsugie-ios-seed-v1"
DEFAULT_GEOHASH_PRECISION = 5
GEOHASH_ALPHABET = "0123456789bcdefghjkmnpqrstuvwxyz"


@dataclass(frozen=True)
class SourceConfig:
    category: str
    latest_run_path: Path
    fused_dir: Path


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


def build_entry(category: str, row: dict[str, Any], geohash_precision: int) -> dict[str, Any]:
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

    return {
        "category": category,
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
    )
    omatsuri_source = SourceConfig(
        category="matsuri",
        latest_run_path=repo_root / "数据端/OMATSURI/data/latest_run.json",
        fused_dir=repo_root / "数据端/OMATSURI/data/fused",
    )

    hanabi_rows, hanabi_run_id = load_latest_fused_records(hanabi_source)
    omatsuri_rows, omatsuri_run_id = load_latest_fused_records(omatsuri_source)

    entries: list[dict[str, Any]] = []
    entries.extend(build_entry(hanabi_source.category, row, geohash_precision) for row in hanabi_rows)
    entries.extend(build_entry(omatsuri_source.category, row, geohash_precision) for row in omatsuri_rows)
    entries.sort(key=lambda x: x["ios_place_id"])

    bucket_meta, payload = build_spatial_payload(entries, args.key)

    index_doc = {
        "version": 3,
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
        },
        "record_counts": {
            **count_by_category(entries),
        },
        "spatial_index": {
            "scheme": "geohash_prefix_v1",
            "precision": geohash_precision,
            "bucket_count": len(bucket_meta),
        },
        "payload_file": args.payload_output.name,
        "payload_sha256": hashlib.sha256(payload).hexdigest(),
        "payload_size_bytes": len(payload),
        "payload_buckets": bucket_meta,
    }

    args.index_output.parent.mkdir(parents=True, exist_ok=True)
    args.payload_output.parent.mkdir(parents=True, exist_ok=True)

    with args.index_output.open("w", encoding="utf-8") as f:
        if args.pretty:
            json.dump(index_doc, f, ensure_ascii=False, indent=2)
            f.write("\n")
        else:
            json.dump(index_doc, f, ensure_ascii=False, separators=(",", ":"))

    args.payload_output.write_bytes(payload)

    print(f"[ok] exported spatial index -> {args.index_output}")
    print(f"[ok] exported payload bin -> {args.payload_output}")
    print(f"[ok] runs: hanabi={hanabi_run_id} omatsuri={omatsuri_run_id}")
    print(f"[ok] records: {len(entries)}")
    print(f"[ok] geohash_precision: {geohash_precision}")
    print(f"[ok] bucket_count: {len(bucket_meta)}")
    print(f"[ok] payload_size_bytes: {len(payload)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
