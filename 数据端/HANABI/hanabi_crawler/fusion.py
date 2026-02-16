from __future__ import annotations

import csv
import difflib
import html
import json
import re
from collections import defaultdict
from datetime import datetime, timezone
from itertools import combinations
from pathlib import Path
from typing import Any

from hanabi_crawler.geocode import GeocodeClient


def _clean(s: str | None) -> str:
    if not s:
        return ""
    s = html.unescape(s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def _normalize_name_raw(name: str | None) -> str:
    s = _clean(name)
    if not s:
        return ""
    patterns = [
        r"の日程・開催情報.*$",
        r"の開催情報.*$",
        r"\s*-\s*ウェザーニュース.*$",
        r"\s*-\s*花火大会.*$",
        r"^【\d{4}年?】",
        r"^\[\d{4}\]",
        r"^[【\[]?(20\d{2})[】\]]",
        r"[（(\[【].{0,24}(市|区|町|村).*[)）\]】]$",
        r"\(?(北海道|東京都|京都府|大阪府|.{2,3}県).*$",
    ]
    for p in patterns:
        s = re.sub(p, "", s)
    s = re.sub(r"^第\d+回\s*", "", s)
    s = re.sub(r"[・･·\-_−\s]+", " ", s)
    return _clean(s).lower()


def _load_alias_map(alias_map_path: str | None) -> dict[str, str]:
    if not alias_map_path:
        return {}
    path = Path(alias_map_path)
    if not path.exists():
        return {}

    mapping: dict[str, str] = {}
    with path.open("r", encoding="utf-8") as f:
        peek = f.read(1024)
        f.seek(0)
        has_header = "alias_name" in peek and "canonical_name" in peek
        if has_header:
            reader = csv.DictReader(f)
            for row in reader:
                alias = _normalize_name_raw(row.get("alias_name"))
                canonical = _normalize_name_raw(row.get("canonical_name"))
                if alias and canonical:
                    mapping[alias] = canonical
        else:
            reader = csv.reader(f)
            for row in reader:
                if len(row) < 2:
                    continue
                alias = _normalize_name_raw(row[0])
                canonical = _normalize_name_raw(row[1])
                if alias and canonical:
                    mapping[alias] = canonical
    return mapping


def _normalize_name(name: str | None, alias_map: dict[str, str]) -> tuple[str, str, bool]:
    raw = _normalize_name_raw(name)
    canonical = alias_map.get(raw, raw)
    return raw, canonical, canonical != raw


def _extract_date_token(text: str | None) -> str:
    s = _clean(text)
    if not s:
        return ""
    m = re.search(r"(20\d{2})-(\d{2})-(\d{2})", s)
    if m:
        return f"{m.group(1)}-{m.group(2)}-{m.group(3)}"
    m = re.search(r"(20\d{2})年(\d{1,2})月(\d{1,2})日", s)
    if m:
        return f"{m.group(1)}-{int(m.group(2)):02d}-{int(m.group(3)):02d}"
    return ""


def _extract_year_token(text: str | None) -> str:
    s = _clean(text)
    if not s:
        return ""
    m = re.search(r"(20\d{2})-(\d{2})-(\d{2})", s)
    if m:
        return m.group(1)
    m = re.search(r"(20\d{2})年", s)
    if m:
        return m.group(1)
    m = re.search(r"(20\d{2})", s)
    return m.group(1) if m else ""


def _extract_event_year(row: dict[str, Any]) -> str:
    for field in ("event_date_start", "event_name", "source_url"):
        year = _extract_year_token(row.get(field))
        if year:
            return year
    return ""


def _extract_pref(text: str | None) -> str:
    s = _clean(text)
    if not s:
        return ""
    m = re.search(r"(北海道|東京都|京都府|大阪府|.{2,3}県)", s)
    return m.group(1) if m else ""


def _score_value(field: str, value: Any, source_site: str) -> int:
    if value is None:
        return 0
    val = _clean(str(value))
    if not val:
        return 0
    if val in {"--", "---", "未定", "非公表", "調査中"}:
        return 1
    base = min(len(val), 200)
    site_weight = {
        "hanabi_cloud": 8,
        "jorudan": 6,
        "sorahanabi": 4,
        "weathernews": 4,
        "hanabeat": 4,
        "hanabi_navi": 4,
        "jalan": 3,
        "hanabeam": 2,
    }.get(source_site, 1)
    if field == "event_name":
        return site_weight * 10 + max(0, 80 - base)
    if field in {"lat", "lng"}:
        return site_weight * 100 + 100
    return site_weight * 10 + base


def _to_coord(value: Any) -> float | None:
    if value is None:
        return None
    s = _clean(str(value))
    if not s:
        return None
    try:
        return float(s)
    except ValueError:
        return None


def _normalize_event_name_for_geocode(text: str | None) -> str:
    s = _clean(text)
    if not s:
        return ""
    s = re.sub(r"【[^】]*】", " ", s)
    s = re.sub(r"\[[^\]]*\]", " ", s)
    s = re.sub(r"（[^）]*）", " ", s)
    s = re.sub(r"\([^)]*\)", " ", s)
    s = re.sub(r"\s*-\s*.*$", " ", s)
    s = re.sub(r"で開催[^\s]*", " ", s)
    s = re.sub(r"[「」『』]", " ", s)
    return _clean(s)


def _build_geocode_queries(row: dict[str, Any]) -> list[tuple[str, str]]:
    queries: list[tuple[str, str]] = []
    venue_address = _clean(row.get("venue_address"))
    prefecture = _clean(row.get("prefecture"))
    city = _clean(row.get("city"))
    venue_name = _clean(row.get("venue_name"))
    event_name = _clean(row.get("event_name"))
    event_name_norm = _normalize_event_name_for_geocode(event_name)

    if venue_address:
        queries.append((venue_address, "venue_address"))
    if prefecture or city or venue_name:
        queries.append((f"{prefecture}{city}{venue_name}", "pref_city_venue"))
    if prefecture and venue_name:
        queries.append((f"{prefecture}{venue_name}", "pref_venue"))
    if city and venue_name:
        queries.append((f"{city}{venue_name}", "city_venue"))
    if venue_name:
        queries.append((venue_name, "venue_name"))
    if prefecture and event_name:
        queries.append((f"{prefecture}{event_name}", "pref_event_name"))
    if event_name_norm and prefecture:
        queries.append((f"{prefecture}{event_name_norm}", "pref_event_name_normalized"))
    if event_name_norm:
        queries.append((event_name_norm, "event_name_normalized"))
    if event_name:
        queries.append((event_name, "event_name"))

    out: list[tuple[str, str]] = []
    seen: set[str] = set()
    for q, strategy in queries:
        q = _clean(q)
        if not q or len(q) < 4:
            continue
        if q in seen:
            continue
        seen.add(q)
        out.append((q, strategy))
    return out


LOW_CONFIDENCE_GEO_SOURCES = {"missing", "pref_center_fallback"}
COORD_EPSILON = 1e-6


def _is_low_confidence_geo_source(source: Any) -> bool:
    text = _clean(str(source))
    if not text:
        return True
    return text in LOW_CONFIDENCE_GEO_SOURCES or text.startswith("network_geocode")


def _build_overlap_repair_queries(row: dict[str, Any]) -> list[tuple[str, str]]:
    queries: list[tuple[str, str]] = []
    prefecture = _clean(row.get("prefecture"))
    city = _clean(row.get("city"))
    venue_name = _clean(row.get("venue_name"))
    venue_address = _clean(row.get("venue_address"))
    event_name = _clean(row.get("event_name"))
    event_name_norm = _normalize_event_name_for_geocode(event_name)

    if prefecture or city or venue_name or venue_address:
        queries.append((f"{prefecture}{city}{venue_name}{venue_address}", "repair_pref_city_venue_address"))
    if prefecture and city and event_name_norm:
        queries.append((f"{prefecture}{city}{event_name_norm}", "repair_pref_city_event_name_normalized"))
    if prefecture and event_name_norm and venue_name:
        queries.append((f"{prefecture}{event_name_norm}{venue_name}", "repair_pref_event_name_venue"))
    if prefecture and event_name:
        queries.append((f"{prefecture}{event_name}", "repair_pref_event_name_raw"))
    if event_name_norm and venue_name:
        queries.append((f"{event_name_norm}{venue_name}", "repair_event_name_venue"))
    if venue_address and event_name_norm:
        queries.append((f"{venue_address}{event_name_norm}", "repair_venue_address_event_name"))
    if venue_address:
        queries.append((venue_address, "repair_venue_address_only"))
    if prefecture and venue_name:
        queries.append((f"{prefecture}{venue_name}", "repair_pref_venue"))
    if event_name_norm:
        queries.append((event_name_norm, "repair_event_name_normalized"))
    if event_name:
        queries.append((event_name, "repair_event_name_raw"))

    out: list[tuple[str, str]] = []
    seen: set[str] = set()
    for query, strategy in queries:
        q = _clean(query)
        if not q or len(q) < 4:
            continue
        if q in seen:
            continue
        seen.add(q)
        out.append((q, strategy))
    return out


def _repair_overlap_coordinates(
    fused_rows: list[dict[str, Any]],
    geocoder: GeocodeClient | None,
    run_id: str,
) -> tuple[list[list[str | float]], dict[str, int]]:
    entries: list[list[str | float]] = []
    stats = {
        "overlap_groups_detected": 0,
        "overlap_rows_considered": 0,
        "overlap_repair_attempted": 0,
        "overlap_repair_resolved": 0,
        "overlap_repair_cache_hits": 0,
        "overlap_repair_skipped_no_query": 0,
    }
    if not geocoder:
        return entries, stats

    grouped: dict[tuple[float, float], list[tuple[int, dict[str, Any]]]] = defaultdict(list)
    for idx, row in enumerate(fused_rows):
        lat = _to_coord(row.get("lat"))
        lng = _to_coord(row.get("lng"))
        if lat is None or lng is None:
            continue
        grouped[(round(lat, 6), round(lng, 6))].append((idx, row))

    suspicious_groups: list[tuple[float, float, list[tuple[int, dict[str, Any]]]]] = []
    for (lat, lng), members in grouped.items():
        if len(members) < 2:
            continue
        if not all(_is_low_confidence_geo_source(member[1].get("geo_source")) for member in members):
            continue
        suspicious_groups.append((lat, lng, members))

    stats["overlap_groups_detected"] = len(suspicious_groups)
    for old_lat, old_lng, members in suspicious_groups:
        for row_index, row in members:
            stats["overlap_rows_considered"] += 1
            canonical_id = str(row.get("canonical_id", ""))
            queries = _build_overlap_repair_queries(row)
            if not queries:
                stats["overlap_repair_skipped_no_query"] += 1
                entries.append(
                    [
                        run_id,
                        canonical_id,
                        "overlap_repair",
                        "skipped_no_query",
                        "",
                        "",
                        "0",
                        old_lat,
                        old_lng,
                        "",
                        "",
                        "",
                        "",
                    ]
                )
                continue

            repaired = False
            for query, strategy in queries:
                stats["overlap_repair_attempted"] += 1
                resp = geocoder.geocode(query)
                stats["overlap_repair_cache_hits"] += int(resp.cache_hit)
                entries.append(
                    [
                        run_id,
                        canonical_id,
                        "overlap_repair",
                        resp.status,
                        strategy,
                        resp.query,
                        "1" if resp.cache_hit else "0",
                        old_lat,
                        old_lng,
                        resp.lat if resp.lat is not None else "",
                        resp.lng if resp.lng is not None else "",
                        resp.title,
                        resp.error,
                    ]
                )
                if resp.status not in {"ok", "cached_ok"} or resp.lat is None or resp.lng is None:
                    continue
                if abs(resp.lat - old_lat) <= COORD_EPSILON and abs(resp.lng - old_lng) <= COORD_EPSILON:
                    continue

                repaired_source = (
                    "network_geocode_overlap_repair_title"
                    if "event_name" in strategy
                    else "network_geocode_overlap_repair"
                )
                if resp.status == "cached_ok":
                    repaired_source = f"{repaired_source}_cache"
                fused_rows[row_index]["lat"] = resp.lat
                fused_rows[row_index]["lng"] = resp.lng
                fused_rows[row_index]["geo_source"] = repaired_source
                stats["overlap_repair_resolved"] += 1
                repaired = True
                break

            if not repaired:
                continue

    return entries, stats


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
def _resolve_prefecture_center(row: dict[str, Any]) -> tuple[float, float] | None:
    pref = _clean(row.get("prefecture"))
    if not pref:
        pref = _extract_pref(row.get("venue_address") or row.get("venue_name") or row.get("event_name"))
    if pref in PREFECTURE_CENTER:
        return PREFECTURE_CENTER[pref]
    # Unknown prefecture should remain unresolved; do not collapse to Tokyo Station.
    return None


MISSING_TOKENS = {"", "-", "--", "---", "na", "n/a", "none", "null", "nan", "不明", "未定", "非公表", "調査中"}
UNCERTAIN_HINTS = ("未定", "調査中", "確認中", "未発表", "未公表", "未確定", "予定", "見込み", "予測", "頃")
HANABI_INCOMPLETE_CHECK_FIELDS = [
    "launch_count",
    "event_time_start",
    "event_date_start",
    "venue_name",
    "venue_address",
]


def _is_missing_like(value: Any) -> bool:
    text = _clean(str(value)) if value is not None else ""
    if not text:
        return True
    return text.lower() in MISSING_TOKENS or text in MISSING_TOKENS


def _field_incomplete_reason(field: str, value: Any) -> str:
    text = _clean(str(value)) if value is not None else ""
    if _is_missing_like(text):
        return "missing"
    if any(hint in text for hint in UNCERTAIN_HINTS):
        return "uncertain"
    if field == "launch_count" and not re.search(r"\d", text):
        return "missing_numeric"
    if field == "event_time_start":
        if not re.search(r"\d{1,2}:\d{2}", text) and not re.search(r"\d{1,2}時", text):
            return "unparsed_time"
    return ""


def _compute_incomplete_tags(row: dict[str, Any], fields: list[str]) -> tuple[list[str], str]:
    tags: list[str] = []
    missing_field_names: list[str] = []
    for field in fields:
        reason = _field_incomplete_reason(field, row.get(field))
        if not reason:
            continue
        tags.append(f"{field}:{reason}")
        missing_field_names.append(field)

    if not missing_field_names:
        return tags, "none"
    if "launch_count" in missing_field_names or "event_time_start" in missing_field_names:
        return tags, "high"
    if "event_date_start" in missing_field_names or "venue_name" in missing_field_names:
        return tags, "medium"
    return tags, "low"


def _site_weight(site: str) -> int:
    return {
        "hanabi_cloud": 8,
        "jorudan": 6,
        "sorahanabi": 4,
        "weathernews": 4,
        "hanabeat": 4,
        "hanabi_navi": 4,
        "jalan": 3,
        "hanabeam": 2,
    }.get(site, 1)


def _pick_primary_source(members: list[dict[str, Any]]) -> tuple[str, str]:
    best_site = ""
    best_url = ""
    best_score = -1
    for row in members:
        site = _clean(row.get("source_site"))
        url = _clean(row.get("source_url"))
        score = _site_weight(site)
        if url:
            score += 2
        if score > best_score:
            best_score = score
            best_site = site
            best_url = url
    return best_site, best_url


def _infer_refresh_method(primary_url: str) -> str:
    url = _clean(primary_url).lower()
    if not url:
        return "site_list_recrawl"
    if any(x in url for x in ["/event/", "/spot/", "/detail/", "hanabi"]):
        return "detail_url_refetch"
    if any(x in url for x in ["list", "calender", "calendar", "scheduled", "dayevent"]):
        return "list_page_recrawl"
    return "detail_url_refetch"


def _dedup_key(row: dict[str, Any]) -> str:
    name = row.get("_name_norm_canonical", "")
    date = _extract_date_token(row.get("event_date_start"))
    year = row.get("_event_year", "")
    pref = _extract_pref(row.get("venue_address") or row.get("venue_name") or row.get("event_name"))
    if name and date and year:
        return f"{name}|{year}|{date}|{pref}"
    if name and year:
        return f"{name}|{year}|{pref}"
    if name:
        return f"{name}|unknown|{pref}"
    return f"url|{year or 'unknown'}|{row.get('source_url', '')}"


def _load_rows(raw_dir: str, site_ids: list[str]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    base = Path(raw_dir)
    for site in site_ids:
        path = base / f"{site}.jsonl"
        if not path.exists():
            continue
        with path.open("r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                obj = json.loads(line)
                if "source_site" not in obj:
                    obj["source_site"] = site
                rows.append(obj)
    return rows


def _name_similarity(a: str, b: str) -> float:
    if not a or not b:
        return 0.0
    return difflib.SequenceMatcher(a=a, b=b).ratio()


def _write_alias_candidates(rows: list[dict[str, Any]], run_id: str, out_path: Path) -> int:
    buckets: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        date = _extract_date_token(row.get("event_date_start"))
        pref = _extract_pref(row.get("venue_address") or row.get("venue_name") or row.get("event_name"))
        name = row.get("_name_norm_raw", "")
        if date and pref and name:
            buckets[f"{date}|{pref}"].append(row)

    entries: list[list[str | float]] = []
    for bucket, members in buckets.items():
        unique_names: dict[str, dict[str, str]] = {}
        for m in members:
            key = m.get("_name_norm_raw", "")
            if not key or key in unique_names:
                continue
            unique_names[key] = {
                "display": _clean(m.get("event_name")),
                "site": _clean(m.get("source_site")),
                "url": _clean(m.get("source_url")),
            }

        if len(unique_names) < 2:
            continue

        date, pref = bucket.split("|", 1)
        for a, b in combinations(sorted(unique_names.keys()), 2):
            sim = _name_similarity(a, b)
            if sim < 0.45:
                continue
            ai = unique_names[a]
            bi = unique_names[b]
            entries.append(
                [
                    run_id,
                    date,
                    pref,
                    a,
                    ai["display"],
                    ai["site"],
                    ai["url"],
                    b,
                    bi["display"],
                    bi["site"],
                    bi["url"],
                    round(sim, 3),
                ]
            )

    with out_path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(
            [
                "run_id",
                "event_date",
                "prefecture",
                "name_norm_a",
                "name_display_a",
                "source_site_a",
                "source_url_a",
                "name_norm_b",
                "name_display_b",
                "source_site_b",
                "source_url_b",
                "name_similarity",
            ]
        )
        writer.writerows(entries)

    return len(entries)


def fuse_records(
    raw_dir: str,
    site_ids: list[str],
    run_id: str,
    fused_root: str = "data/fused",
    log_root: str = "data/logs",
    alias_map_path: str = "research/sources/event_name_alias_map.csv",
    target_year: int | None = None,
    strict_year: bool = True,
    geocode_enabled: bool = True,
    geocode_cache_path: str = "data/geo/geocode_cache.csv",
    geocode_qps: float = 1.0,
) -> dict[str, Any]:
    rows = _load_rows(raw_dir, site_ids)
    input_rows_raw = len(rows)
    alias_map = _load_alias_map(alias_map_path)

    for row in rows:
        row["_event_year"] = _extract_event_year(row)
        raw_name, canonical_name, alias_applied = _normalize_name(row.get("event_name"), alias_map)
        row["_name_norm_raw"] = raw_name
        row["_name_norm_canonical"] = canonical_name
        row["_alias_applied"] = "1" if alias_applied else "0"

    target_year_str = str(target_year) if target_year is not None else ""
    year_filter_enabled = bool(strict_year and target_year_str)
    if year_filter_enabled:
        rows = [row for row in rows if row.get("_event_year") == target_year_str]
    input_rows_after_year_filter = len(rows)
    year_dropped_rows = input_rows_raw - input_rows_after_year_filter

    groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        groups[_dedup_key(row)].append(row)

    fused_dir = Path(fused_root) / run_id
    fused_dir.mkdir(parents=True, exist_ok=True)
    fused_jsonl = fused_dir / "events_fused.jsonl"
    fused_csv = fused_dir / "events_fused.csv"

    dedup_log = Path(log_root) / run_id / "dedup_log.csv"
    dedup_log.parent.mkdir(parents=True, exist_ok=True)
    alias_candidates_log = Path(log_root) / run_id / "name_alias_candidates.csv"
    geocode_log = Path(log_root) / run_id / "geocode_log.csv"
    overlap_repair_log = Path(log_root) / run_id / "geo_overlap_repair_log.csv"
    incomplete_log = Path(log_root) / run_id / "incomplete_events.csv"

    fused_rows: list[dict[str, Any]] = []
    dedup_entries: list[list[str]] = []
    geocode_entries: list[list[str | float]] = []
    incomplete_entries: list[list[str]] = []
    geocode_attempted = 0
    geocode_resolved = 0
    geocode_cache_hits = 0
    geocoder = GeocodeClient(cache_path=geocode_cache_path, qps=geocode_qps) if geocode_enabled else None
    overlap_repair_entries: list[list[str | float]] = []
    overlap_repair_stats: dict[str, int] = {}

    all_fields = [
        "event_name",
        "event_date_start",
        "event_date_end",
        "event_time_start",
        "event_time_end",
        "venue_name",
        "venue_address",
        "prefecture",
        "city",
        "lat",
        "lng",
        "launch_count",
        "launch_scale",
        "paid_seat",
        "access_text",
        "parking_text",
        "traffic_control_text",
        "rainout_policy",
        "contact",
        "weather_summary",
    ]

    for idx, (key, members) in enumerate(groups.items(), start=1):
        canonical_id = f"E{idx:06d}"
        merged: dict[str, Any] = {
            "canonical_id": canonical_id,
            "dedup_key": key,
            "event_year": "",
            "geo_source": "",
            "source_sites": sorted({m.get("source_site", "") for m in members if m.get("source_site")}),
            "source_urls": sorted({m.get("source_url", "") for m in members if m.get("source_url")}),
            "source_count": len(members),
            "fused_at": datetime.now(timezone.utc).isoformat(),
        }
        merged["event_year"] = next((m.get("_event_year", "") for m in members if m.get("_event_year")), "")

        for field in all_fields:
            best_val = None
            best_score = -1
            for m in members:
                score = _score_value(field, m.get(field), m.get("source_site", ""))
                if score > best_score:
                    best_score = score
                    best_val = m.get(field)
            merged[field] = best_val

        lat = _to_coord(merged.get("lat"))
        lng = _to_coord(merged.get("lng"))
        if lat is not None and lng is not None:
            merged["lat"] = lat
            merged["lng"] = lng
            merged["geo_source"] = "source_exact"
            geocode_entries.append(
                [run_id, canonical_id, "existing", "existing_coord", "", "", "0", lat, lng, "", ""]
            )
        elif geocoder:
            queries = _build_geocode_queries(merged)
            resolved = False
            if not queries:
                geocode_entries.append(
                    [run_id, canonical_id, "geocoder", "skipped_no_query", "", "", "0", "", "", "", ""]
                )
            for query, query_strategy in queries:
                geocode_attempted += 1
                resp = geocoder.geocode(query)
                geocode_cache_hits += int(resp.cache_hit)
                geocode_entries.append(
                    [
                        run_id,
                        canonical_id,
                        "geocoder",
                        resp.status,
                        query_strategy,
                        resp.query,
                        "1" if resp.cache_hit else "0",
                        resp.lat if resp.lat is not None else "",
                        resp.lng if resp.lng is not None else "",
                        resp.title,
                        resp.error,
                    ]
                )
                if resp.status in {"ok", "cached_ok"} and resp.lat is not None and resp.lng is not None:
                    merged["lat"] = resp.lat
                    merged["lng"] = resp.lng
                    if "event_name" in query_strategy:
                        merged["geo_source"] = "network_geocode_title"
                    else:
                        merged["geo_source"] = "network_geocode"
                    if resp.status == "cached_ok":
                        merged["geo_source"] = f"{merged['geo_source']}_cache"
                    geocode_resolved += 1
                    resolved = True
                    break
            if not resolved:
                pref_center = _resolve_prefecture_center(merged)
                if pref_center:
                    merged["lat"] = pref_center[0]
                    merged["lng"] = pref_center[1]
                    merged["geo_source"] = "pref_center_fallback"
                    geocode_entries.append(
                        [
                            run_id,
                            canonical_id,
                            "pref_center",
                            "fallback_pref_center",
                            "",
                            "",
                            "0",
                            pref_center[0],
                            pref_center[1],
                            "",
                            "",
                        ]
                    )
                else:
                    merged["lat"] = ""
                    merged["lng"] = ""
                    merged["geo_source"] = "missing"
        else:
            if lat is not None and lng is not None:
                merged["lat"] = lat
                merged["lng"] = lng
                merged["geo_source"] = "source_exact"
            else:
                pref_center = _resolve_prefecture_center(merged)
                if pref_center:
                    merged["lat"] = pref_center[0]
                    merged["lng"] = pref_center[1]
                    merged["geo_source"] = "pref_center_fallback"
                    geocode_entries.append(
                        [
                            run_id,
                            canonical_id,
                            "pref_center",
                            "fallback_pref_center",
                            "",
                            "",
                            "0",
                            pref_center[0],
                            pref_center[1],
                            "",
                            "",
                        ]
                    )
                else:
                    merged["lat"] = ""
                    merged["lng"] = ""
                    merged["geo_source"] = "missing"

        incomplete_tags, update_priority = _compute_incomplete_tags(merged, HANABI_INCOMPLETE_CHECK_FIELDS)
        merged["is_info_incomplete"] = "1" if incomplete_tags else "0"
        merged["incomplete_field_count"] = str(len(incomplete_tags))
        merged["incomplete_fields"] = "|".join(incomplete_tags)
        merged["update_priority"] = update_priority

        if incomplete_tags:
            primary_site, primary_url = _pick_primary_source(members)
            incomplete_entries.append(
                [
                    run_id,
                    canonical_id,
                    merged.get("event_year", ""),
                    _clean(merged.get("event_name")),
                    merged["incomplete_field_count"],
                    merged["incomplete_fields"],
                    merged["update_priority"],
                    primary_site,
                    primary_url,
                    _infer_refresh_method(primary_url),
                    "|".join(merged.get("source_sites", [])),
                    "|".join(merged.get("source_urls", [])),
                ]
            )

        fused_rows.append(merged)

        for i, m in enumerate(members):
            dedup_entries.append(
                [
                    run_id,
                    canonical_id,
                    key,
                    m.get("source_site", ""),
                    m.get("source_url", ""),
                    m.get("_event_year", ""),
                    m.get("_name_norm_raw", ""),
                    m.get("_name_norm_canonical", ""),
                    m.get("_alias_applied", "0"),
                    "canonical" if i == 0 else "merged",
                ]
            )

    overlap_repair_entries, overlap_repair_stats = _repair_overlap_coordinates(
        fused_rows=fused_rows,
        geocoder=geocoder,
        run_id=run_id,
    )

    with fused_jsonl.open("w", encoding="utf-8") as f:
        for row in fused_rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")

    csv_fields = [
        "canonical_id",
        "event_year",
        "source_count",
        "event_name",
        "event_date_start",
        "event_date_end",
        "event_time_start",
        "event_time_end",
        "venue_name",
        "venue_address",
        "prefecture",
        "city",
        "lat",
        "lng",
        "geo_source",
        "launch_count",
        "launch_scale",
        "paid_seat",
        "access_text",
        "parking_text",
        "traffic_control_text",
        "rainout_policy",
        "contact",
        "weather_summary",
        "is_info_incomplete",
        "incomplete_field_count",
        "incomplete_fields",
        "update_priority",
        "source_sites",
        "source_urls",
    ]
    with fused_csv.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=csv_fields)
        writer.writeheader()
        for row in fused_rows:
            out = dict(row)
            out["source_sites"] = "|".join(row.get("source_sites", []))
            out["source_urls"] = "|".join(row.get("source_urls", []))
            writer.writerow({k: out.get(k) for k in csv_fields})

    with dedup_log.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(
            [
                "run_id",
                "canonical_id",
                "dedup_key",
                "source_site",
                "source_url",
                "event_year",
                "name_norm_raw",
                "name_norm_canonical",
                "alias_applied",
                "action",
            ]
        )
        writer.writerows(dedup_entries)

    with geocode_log.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(
            [
                "run_id",
                "canonical_id",
                "source",
                "status",
                "query_strategy",
                "query",
                "cache_hit",
                "lat",
                "lng",
                "title",
                "error",
            ]
        )
        writer.writerows(geocode_entries)

    with overlap_repair_log.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(
            [
                "run_id",
                "canonical_id",
                "source",
                "status",
                "query_strategy",
                "query",
                "cache_hit",
                "old_lat",
                "old_lng",
                "new_lat",
                "new_lng",
                "title",
                "error",
            ]
        )
        writer.writerows(overlap_repair_entries)

    with incomplete_log.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(
            [
                "run_id",
                "canonical_id",
                "event_year",
                "event_name",
                "incomplete_field_count",
                "incomplete_fields",
                "update_priority",
                "primary_source_site",
                "primary_source_url",
                "refresh_method",
                "source_sites",
                "source_urls",
            ]
        )
        writer.writerows(incomplete_entries)

    if geocoder:
        geocoder.save_cache()

    candidate_count = _write_alias_candidates(rows, run_id=run_id, out_path=alias_candidates_log)

    return {
        "input_rows": len(rows),
        "input_rows_raw": input_rows_raw,
        "input_rows_after_year_filter": input_rows_after_year_filter,
        "year_filter_enabled": int(year_filter_enabled),
        "target_year": target_year_str,
        "year_dropped_rows": year_dropped_rows,
        "group_count": len(groups),
        "fused_jsonl": str(fused_jsonl),
        "fused_csv": str(fused_csv),
        "dedup_log": str(dedup_log),
        "geocode_log": str(geocode_log),
        "geocode_attempted": geocode_attempted,
        "geocode_resolved": geocode_resolved,
        "geocode_cache_hits": geocode_cache_hits,
        "overlap_repair_log": str(overlap_repair_log),
        "overlap_groups_detected": overlap_repair_stats.get("overlap_groups_detected", 0),
        "overlap_rows_considered": overlap_repair_stats.get("overlap_rows_considered", 0),
        "overlap_repair_attempted": overlap_repair_stats.get("overlap_repair_attempted", 0),
        "overlap_repair_resolved": overlap_repair_stats.get("overlap_repair_resolved", 0),
        "overlap_repair_cache_hits": overlap_repair_stats.get("overlap_repair_cache_hits", 0),
        "overlap_repair_skipped_no_query": overlap_repair_stats.get("overlap_repair_skipped_no_query", 0),
        "incomplete_log": str(incomplete_log),
        "incomplete_count": len(incomplete_entries),
        "alias_candidates": str(alias_candidates_log),
        "alias_candidates_count": candidate_count,
        "alias_map_entries": len(alias_map),
    }
