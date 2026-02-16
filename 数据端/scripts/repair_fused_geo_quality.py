#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from pathlib import Path
from typing import Any

TOKYO_STATION_DEFAULT = (35.681236, 139.767125)
EPSILON = 1e-6

PREFECTURE_CENTER: dict[str, tuple[float, float]] = {
    "北海道": (43.06417, 141.34694),
    "青森県": (40.82444, 140.74),
    "岩手県": (39.70361, 141.1525),
    "宮城県": (38.26889, 140.87194),
    "秋田県": (39.71861, 140.1025),
    "山形県": (38.24056, 140.36333),
    "福島県": (37.75, 140.46778),
    "茨城県": (36.34139, 140.44667),
    "栃木県": (36.56583, 139.88361),
    "群馬県": (36.39111, 139.06083),
    "埼玉県": (35.85694, 139.64889),
    "千葉県": (35.60472, 140.12333),
    "東京都": (35.68944, 139.69167),
    "神奈川県": (35.44778, 139.6425),
    "新潟県": (37.90222, 139.02361),
    "富山県": (36.69528, 137.21139),
    "石川県": (36.59444, 136.62556),
    "福井県": (36.06528, 136.22194),
    "山梨県": (35.66389, 138.56833),
    "長野県": (36.65139, 138.18111),
    "岐阜県": (35.39111, 136.72222),
    "静岡県": (34.97694, 138.38306),
    "愛知県": (35.18028, 136.90667),
    "三重県": (34.73028, 136.50861),
    "滋賀県": (35.00444, 135.86833),
    "京都府": (35.02139, 135.75556),
    "大阪府": (34.68639, 135.52),
    "兵庫県": (34.69139, 135.18306),
    "奈良県": (34.68528, 135.83278),
    "和歌山県": (34.22611, 135.1675),
    "鳥取県": (35.50361, 134.23833),
    "島根県": (35.47222, 133.05056),
    "岡山県": (34.66167, 133.935),
    "広島県": (34.39639, 132.45944),
    "山口県": (34.18583, 131.47139),
    "徳島県": (34.06583, 134.55944),
    "香川県": (34.34028, 134.04333),
    "愛媛県": (33.84167, 132.76611),
    "高知県": (33.55972, 133.53111),
    "福岡県": (33.60639, 130.41806),
    "佐賀県": (33.24944, 130.29889),
    "長崎県": (32.74472, 129.87361),
    "熊本県": (32.78972, 130.74167),
    "大分県": (33.23806, 131.6125),
    "宮崎県": (31.91111, 131.42389),
    "鹿児島県": (31.56028, 130.55806),
    "沖縄県": (26.2125, 127.68111),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Repair fused geo quality: add geo_source and remove unknown Tokyo-station fallback points."
    )
    parser.add_argument("--input", type=Path, required=True, help="Input events_fused.jsonl")
    parser.add_argument("--output", type=Path, required=True, help="Output events_fused.jsonl")
    parser.add_argument("--metrics-output", type=Path, default=None, help="Optional metrics json output")
    return parser.parse_args()


def _clean(value: Any) -> str:
    if value is None:
        return ""
    return re.sub(r"\s+", " ", str(value)).strip()


def _extract_prefecture(row: dict[str, Any]) -> str:
    pref = _clean(row.get("prefecture"))
    if pref in PREFECTURE_CENTER:
        return pref

    text = _clean(row.get("venue_address")) or _clean(row.get("venue_name")) or _clean(row.get("event_name"))
    if not text:
        return ""
    matched = re.search(r"(北海道|東京都|京都府|大阪府|.{2,3}県)", text)
    if not matched:
        return ""
    candidate = matched.group(1)
    return candidate if candidate in PREFECTURE_CENTER else ""


def _to_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _is_valid_coord(lat: float | None, lng: float | None) -> bool:
    if lat is None or lng is None:
        return False
    return -90 <= lat <= 90 and -180 <= lng <= 180


def _is_same_coord(a: tuple[float, float], b: tuple[float, float]) -> bool:
    return abs(a[0] - b[0]) <= EPSILON and abs(a[1] - b[1]) <= EPSILON


def repair_row(row: dict[str, Any], counters: Counter[str]) -> dict[str, Any]:
    out = dict(row)
    pref = _extract_prefecture(out)
    lat = _to_float(out.get("lat"))
    lng = _to_float(out.get("lng"))

    geo_source = _clean(out.get("geo_source"))

    if not _is_valid_coord(lat, lng):
        out["lat"] = ""
        out["lng"] = ""
        out["geo_source"] = "missing"
        counters["set_missing_invalid_coord"] += 1
        return out

    assert lat is not None and lng is not None
    coord = (lat, lng)

    # Historical bad fallback: unresolved region collapsed to Tokyo Station.
    if _is_same_coord(coord, TOKYO_STATION_DEFAULT) and not pref:
        out["lat"] = ""
        out["lng"] = ""
        out["geo_source"] = "missing"
        counters["removed_tokyo_default_unresolved"] += 1
        return out

    if geo_source:
        out["geo_source"] = geo_source
        counters["keep_existing_geo_source"] += 1
        return out

    if pref:
        pref_center = PREFECTURE_CENTER[pref]
        if _is_same_coord(coord, pref_center):
            out["geo_source"] = "pref_center_fallback"
            counters["derive_pref_center_fallback"] += 1
            return out

    out["geo_source"] = "source_exact"
    counters["derive_source_exact"] += 1
    return out


def main() -> int:
    args = parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)

    counters: Counter[str] = Counter()
    rows_in = 0
    rows_out = 0

    with args.input.open("r", encoding="utf-8") as fin, args.output.open("w", encoding="utf-8") as fout:
        for line in fin:
            text = line.strip()
            if not text:
                continue
            rows_in += 1
            row = json.loads(text)
            repaired = repair_row(row, counters)
            fout.write(json.dumps(repaired, ensure_ascii=False) + "\n")
            rows_out += 1

    metrics = {
        "input": str(args.input),
        "output": str(args.output),
        "rows_in": rows_in,
        "rows_out": rows_out,
        "stats": dict(sorted(counters.items())),
    }
    print(json.dumps(metrics, ensure_ascii=False, indent=2))

    if args.metrics_output:
        args.metrics_output.parent.mkdir(parents=True, exist_ok=True)
        args.metrics_output.write_text(json.dumps(metrics, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
