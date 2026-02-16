#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

LOW_CONFIDENCE_GEO_SOURCES = {"missing", "pref_center_fallback"}
PREF_PATTERN = re.compile(r"(北海道|東京都|京都府|大阪府|.{2,3}県)")


@dataclass(frozen=True)
class ProjectConfig:
    project: str
    latest_run_path: Path
    fused_root: Path


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(
        description="Geo overlap quality gate for latest HANABI/OMATSURI fused data."
    )
    parser.add_argument(
        "--project",
        choices=["hanabi", "omatsuri", "all"],
        default="all",
        help="Target project for gate check",
    )
    parser.add_argument(
        "--max-high-risk-groups",
        type=int,
        default=0,
        help="Gate threshold: max allowed high-risk overlap groups",
    )
    parser.add_argument(
        "--high-risk-min-group-size",
        type=int,
        default=4,
        help="High-risk rule: minimum overlap group size",
    )
    parser.add_argument(
        "--high-risk-min-unique-venues",
        type=int,
        default=3,
        help="High-risk rule: minimum unique venues in one overlap group",
    )
    parser.add_argument(
        "--high-risk-min-low-confidence-ratio",
        type=float,
        default=0.8,
        help="High-risk rule: minimum low-confidence geo_source ratio",
    )
    parser.add_argument(
        "--top-n",
        type=int,
        default=20,
        help="Top suspicious groups kept in report",
    )
    parser.add_argument(
        "--report-output",
        type=Path,
        default=repo_root / "数据端/reports/latest_geo_overlap_quality_gate.json",
        help="Report JSON output path",
    )
    return parser.parse_args()


def _clean(value: Any) -> str:
    if value is None:
        return ""
    return re.sub(r"\s+", " ", str(value)).strip()


def _to_float(value: Any) -> float | None:
    text = _clean(value)
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def _is_low_confidence_geo_source(value: Any) -> bool:
    text = _clean(value)
    if not text:
        return True
    return text in LOW_CONFIDENCE_GEO_SOURCES or text.startswith("network_geocode")


def _extract_prefecture(row: dict[str, Any]) -> str:
    pref = _clean(row.get("prefecture"))
    if pref:
        return pref
    text = _clean(row.get("venue_address")) or _clean(row.get("venue_name")) or _clean(row.get("event_name"))
    matched = PREF_PATTERN.search(text)
    return matched.group(1) if matched else ""


def _load_latest_fused_rows(project: ProjectConfig) -> tuple[str, list[dict[str, Any]]]:
    latest = json.loads(project.latest_run_path.read_text(encoding="utf-8"))
    run_id = str(latest.get("fused_run_id") or "").strip()
    if not run_id:
        raise RuntimeError(f"[{project.project}] fused_run_id is missing: {project.latest_run_path}")
    fused_file = project.fused_root / run_id / "events_fused.jsonl"
    if not fused_file.exists():
        raise FileNotFoundError(f"[{project.project}] fused file not found: {fused_file}")
    rows: list[dict[str, Any]] = []
    with fused_file.open("r", encoding="utf-8") as f:
        for line in f:
            text = line.strip()
            if not text:
                continue
            rows.append(json.loads(text))
    return run_id, rows


def _analyze_project(
    project: str,
    run_id: str,
    rows: list[dict[str, Any]],
    *,
    high_risk_min_group_size: int,
    high_risk_min_unique_venues: int,
    high_risk_min_low_confidence_ratio: float,
    top_n: int,
) -> dict[str, Any]:
    groups: dict[tuple[float, float], list[dict[str, Any]]] = defaultdict(list)
    valid_coord_rows = 0
    for row in rows:
        lat = _to_float(row.get("lat"))
        lng = _to_float(row.get("lng"))
        if lat is None or lng is None:
            continue
        valid_coord_rows += 1
        groups[(round(lat, 6), round(lng, 6))].append(row)

    overlap_groups = [(coord, members) for coord, members in groups.items() if len(members) >= 2]
    suspicious: list[dict[str, Any]] = []
    high_risk_count = 0

    for (lat, lng), members in overlap_groups:
        group_size = len(members)
        geo_counter = Counter(_clean(m.get("geo_source")) or "missing" for m in members)
        low_conf_count = sum(1 for m in members if _is_low_confidence_geo_source(m.get("geo_source")))
        low_conf_ratio = low_conf_count / group_size

        venue_set = set()
        prefecture_set = set()
        for row in members:
            venue = _clean(row.get("venue_name")) or _clean(row.get("venue_address")) or _clean(row.get("event_name"))
            if venue:
                venue_set.add(venue)
            pref = _extract_prefecture(row)
            if pref:
                prefecture_set.add(pref)

        reason: list[str] = []
        if len(prefecture_set) >= 2:
            reason.append("cross_prefecture")
        if (
            group_size >= high_risk_min_group_size
            and len(venue_set) >= high_risk_min_unique_venues
            and low_conf_ratio >= high_risk_min_low_confidence_ratio
        ):
            reason.append("multi_venue_low_conf")
        is_high_risk = bool(reason)
        if is_high_risk:
            high_risk_count += 1

        samples = []
        for row in members[: min(5, group_size)]:
            samples.append(
                {
                    "canonical_id": _clean(row.get("canonical_id")),
                    "event_name": _clean(row.get("event_name")),
                    "venue_name": _clean(row.get("venue_name")),
                    "prefecture": _extract_prefecture(row),
                    "geo_source": _clean(row.get("geo_source")) or "missing",
                }
            )

        suspicious.append(
            {
                "lat": lat,
                "lng": lng,
                "group_size": group_size,
                "unique_venues": len(venue_set),
                "unique_prefectures": len(prefecture_set),
                "low_confidence_ratio": round(low_conf_ratio, 4),
                "geo_source_breakdown": dict(geo_counter.most_common()),
                "is_high_risk": is_high_risk,
                "risk_reasons": reason,
                "samples": samples,
            }
        )

    suspicious.sort(
        key=lambda x: (
            1 if x["is_high_risk"] else 0,
            x["group_size"],
            x["unique_venues"],
            x["low_confidence_ratio"],
        ),
        reverse=True,
    )

    return {
        "project": project,
        "run_id": run_id,
        "total_rows": len(rows),
        "valid_coordinate_rows": valid_coord_rows,
        "overlap_group_count": len(overlap_groups),
        "overlap_record_count": sum(len(members) for _, members in overlap_groups),
        "high_risk_group_count": high_risk_count,
        "top_suspicious_groups": suspicious[: max(1, top_n)],
    }


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[2]
    configs = [
        ProjectConfig(
            project="hanabi",
            latest_run_path=repo_root / "数据端/HANABI/data/latest_run.json",
            fused_root=repo_root / "数据端/HANABI/data/fused",
        ),
        ProjectConfig(
            project="omatsuri",
            latest_run_path=repo_root / "数据端/OMATSURI/data/latest_run.json",
            fused_root=repo_root / "数据端/OMATSURI/data/fused",
        ),
    ]
    if args.project != "all":
        configs = [cfg for cfg in configs if cfg.project == args.project]

    project_reports: list[dict[str, Any]] = []
    for cfg in configs:
        run_id, rows = _load_latest_fused_rows(cfg)
        report = _analyze_project(
            cfg.project,
            run_id,
            rows,
            high_risk_min_group_size=args.high_risk_min_group_size,
            high_risk_min_unique_venues=args.high_risk_min_unique_venues,
            high_risk_min_low_confidence_ratio=args.high_risk_min_low_confidence_ratio,
            top_n=args.top_n,
        )
        project_reports.append(report)

    total_high_risk_groups = sum(r["high_risk_group_count"] for r in project_reports)
    gate_passed = total_high_risk_groups <= args.max_high_risk_groups

    gate_report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "thresholds": {
            "max_high_risk_groups": args.max_high_risk_groups,
            "high_risk_min_group_size": args.high_risk_min_group_size,
            "high_risk_min_unique_venues": args.high_risk_min_unique_venues,
            "high_risk_min_low_confidence_ratio": args.high_risk_min_low_confidence_ratio,
        },
        "summary": {
            "projects_checked": [r["project"] for r in project_reports],
            "total_high_risk_groups": total_high_risk_groups,
            "gate_passed": gate_passed,
        },
        "projects": project_reports,
    }

    args.report_output.parent.mkdir(parents=True, exist_ok=True)
    args.report_output.write_text(
        json.dumps(gate_report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print(
        "[geo-gate] "
        f"projects={','.join(gate_report['summary']['projects_checked'])} "
        f"high_risk_groups={total_high_risk_groups} "
        f"threshold={args.max_high_risk_groups} "
        f"passed={gate_passed}"
    )
    print(f"[geo-gate] report={args.report_output}")

    if gate_passed:
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
