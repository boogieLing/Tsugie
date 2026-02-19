from __future__ import annotations

import argparse
import subprocess
import sys
from datetime import datetime
from pathlib import Path

from omatsuri_crawler.config import load_config
from omatsuri_crawler.crawler import SiteCrawler
from omatsuri_crawler.fusion import fuse_records
from omatsuri_crawler.run_logger import RunLogger, SiteSummary


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Omatsuri multi-site crawler")
    parser.add_argument(
        "--config",
        default="research/sources/matsuri_2026_crawl_site_configs.yaml",
        help="Path to crawl site config yaml",
    )
    parser.add_argument(
        "--sites",
        default="jalan_event,matsuri_no_hi,omatsurijapan,omatsuri_com,kankomie_event,japan47go_event",
        help="Comma-separated site ids",
    )
    parser.add_argument("--max-list-pages", type=int, default=80)
    parser.add_argument("--max-detail-pages", type=int, default=300)
    parser.add_argument(
        "--qps-multiplier",
        type=float,
        default=1.0,
        help="Multiply per-site configured QPS to speed up crawling",
    )
    parser.add_argument("--out-dir", default="data/raw")
    parser.add_argument("--log-dir", default="data/logs")
    parser.add_argument("--fused-dir", default="data/fused")
    parser.add_argument(
        "--geocode-cache",
        default="data/geo/geocode_cache.csv",
        help="Path to persistent geocode cache CSV",
    )
    parser.add_argument(
        "--geocode-qps",
        type=float,
        default=1.0,
        help="Geocoder request QPS limit",
    )
    parser.add_argument(
        "--geocode",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Enable geocoding fallback for missing lat/lng in fused output",
    )
    parser.add_argument(
        "--alias-map",
        default="research/sources/event_name_alias_map.csv",
        help="Path to event-name alias mapping CSV",
    )
    parser.add_argument(
        "--target-year",
        type=int,
        default=datetime.now().year,
        help="Target event year used in fusion filter and dedup",
    )
    parser.add_argument(
        "--strict-year",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="When enabled, fuse stage keeps only target-year records",
    )
    parser.add_argument("--run-id", default="")
    parser.add_argument("--no-fuse", action="store_true")
    parser.add_argument(
        "--content-enrich",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Run low-frequency content enrichment after fuse",
    )
    parser.add_argument("--content-run-id", default="", help="Override content enrichment run_id")
    parser.add_argument("--content-min-refresh-days", type=int, default=45)
    parser.add_argument("--content-qps", type=float, default=0.12)
    parser.add_argument("--content-max-images", type=int, default=1)
    parser.add_argument(
        "--content-polish-mode",
        choices=["auto", "openai", "codex", "none"],
        default="auto",
    )
    parser.add_argument("--content-codex-timeout-sec", type=int, default=25)
    return parser.parse_args()


def run_content_enrich(args: argparse.Namespace, run_id: str) -> None:
    repo_root = Path(__file__).resolve().parents[2]
    enrich_script = repo_root / "scripts" / "enrich_event_content.py"
    if not enrich_script.exists():
        raise RuntimeError(f"content enrich script not found: {enrich_script}")

    content_run_id = args.content_run_id.strip() or f"{run_id}_content"
    cmd = [
        sys.executable,
        str(enrich_script),
        "--project",
        "omatsuri",
        "--run-id",
        content_run_id,
        "--min-refresh-days",
        str(args.content_min_refresh_days),
        "--qps",
        str(args.content_qps),
        "--max-images",
        str(max(args.content_max_images, 1)),
        "--polish-mode",
        args.content_polish_mode,
        "--codex-timeout-sec",
        str(max(args.content_codex_timeout_sec, 1)),
        "--download-images",
        "--update-latest-run",
    ]
    print(f"[content] start run_id={content_run_id}")
    subprocess.run(cmd, cwd=str(repo_root), check=True)
    print(f"[content] done run_id={content_run_id}")


def main() -> int:
    args = parse_args()
    cfg = load_config(args.config)
    selected = [x.strip() for x in args.sites.split(",") if x.strip()]
    crawl_enabled = args.max_list_pages > 0 and args.max_detail_pages > 0

    run_id = args.run_id or datetime.now().strftime("%Y%m%d_%H%M%S")
    Path(args.out_dir).mkdir(parents=True, exist_ok=True)
    run_logger = RunLogger(run_id=run_id, log_root=args.log_dir)

    if not crawl_enabled:
        print(
            "[skip] crawl disabled: "
            f"max_list_pages={args.max_list_pages}, max_detail_pages={args.max_detail_pages}. "
            "existing raw files are preserved."
        )
    else:
        for site_id in selected:
            site = cfg.sites.get(site_id)
            if not site:
                print(f"[skip] unknown site: {site_id}")
                continue
            if not site.enabled:
                print(f"[skip] disabled site: {site_id}")
                continue

            crawler = SiteCrawler(
                site=site,
                out_dir=args.out_dir,
                logger=run_logger,
                qps_multiplier=args.qps_multiplier,
                target_year=args.target_year,
            )
            try:
                list_visited, detail_found, detail_written = crawler.crawl(
                    max_list_pages=args.max_list_pages,
                    max_detail_pages=args.max_detail_pages,
                )
                run_logger.log_site_summary(
                    SiteSummary(
                        site_id=site_id,
                        list_visited=list_visited,
                        detail_discovered=detail_found,
                        detail_written=detail_written,
                    )
                )
                print(
                    f"[done] {site_id}: list_visited={list_visited}, "
                    f"details_discovered={detail_found}, "
                    f"records_written={detail_written}"
                )
            finally:
                crawler.close()

    if not args.no_fuse:
        fusion = fuse_records(
            raw_dir=args.out_dir,
            site_ids=selected,
            run_id=run_id,
            fused_root=args.fused_dir,
            log_root=args.log_dir,
            alias_map_path=args.alias_map,
            target_year=args.target_year,
            strict_year=args.strict_year,
            geocode_enabled=args.geocode,
            geocode_cache_path=args.geocode_cache,
            geocode_qps=args.geocode_qps,
        )
        print(
            "[fuse] "
            f"input_rows_raw={fusion['input_rows_raw']}, "
            f"input_rows_after_year_filter={fusion['input_rows_after_year_filter']}, "
            f"year_filter_enabled={fusion['year_filter_enabled']}, "
            f"target_year={fusion['target_year']}, "
            f"year_dropped_rows={fusion['year_dropped_rows']}, "
            f"group_count={fusion['group_count']}, "
            f"fused_jsonl={fusion['fused_jsonl']}, "
            f"dedup_log={fusion['dedup_log']}, "
            f"geocode_log={fusion['geocode_log']}, "
                f"geocode_attempted={fusion['geocode_attempted']}, "
                f"geocode_resolved={fusion['geocode_resolved']}, "
                f"geocode_cache_hits={fusion['geocode_cache_hits']}, "
                f"overlap_groups_detected={fusion['overlap_groups_detected']}, "
                f"overlap_rows_considered={fusion['overlap_rows_considered']}, "
                f"overlap_repair_attempted={fusion['overlap_repair_attempted']}, "
                f"overlap_repair_resolved={fusion['overlap_repair_resolved']}, "
                f"overlap_repair_cache_hits={fusion['overlap_repair_cache_hits']}, "
                f"overlap_repair_skipped_no_query={fusion['overlap_repair_skipped_no_query']}, "
                f"overlap_repair_log={fusion['overlap_repair_log']}, "
                f"incomplete_log={fusion['incomplete_log']}, "
                f"incomplete_count={fusion['incomplete_count']}, "
                f"alias_candidates={fusion['alias_candidates_count']}, "
            f"alias_map_entries={fusion['alias_map_entries']}"
        )
        if args.content_enrich:
            run_content_enrich(args, run_id)
    print(f"[run] run_id={run_id}, logs={args.log_dir}/{run_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
