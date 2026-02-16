from __future__ import annotations

import argparse
from datetime import datetime
from pathlib import Path

from hanabi_crawler.config import load_config
from hanabi_crawler.crawler import SiteCrawler
from hanabi_crawler.fusion import fuse_records
from hanabi_crawler.run_logger import RunLogger, SiteSummary


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Hanabi multi-site crawler")
    parser.add_argument(
        "--config",
        default="research/sources/hanabi_crawl_site_configs.yaml",
        help="Path to crawl site config yaml",
    )
    parser.add_argument(
        "--sites",
        default="hanabi_cloud,sorahanabi,jorudan,weathernews,hanabeat,hanabi_navi,jalan,hanabeam",
        help="Comma-separated site ids",
    )
    parser.add_argument("--max-list-pages", type=int, default=80)
    parser.add_argument("--max-detail-pages", type=int, default=200)
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
    return parser.parse_args()


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
            try:
                crawler = SiteCrawler(
                    site=site,
                    out_dir=args.out_dir,
                    logger=run_logger,
                    qps_multiplier=args.qps_multiplier,
                )
            except ValueError as exc:
                print(f"[skip] {site_id}: {exc}")
                continue
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
    print(f"[run] run_id={run_id}, logs={args.log_dir}/{run_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
