# OMATSURI

日本祭典（お祭り）抓取独立项目。

## 目录
- `omatsuri_crawler/`：抓取与融合代码
- `research/sources/matsuri_2026_sites_inventory.json`：2026 祭典候选站点清单
- `research/sources/matsuri_2026_crawl_site_configs.yaml`：抓取配置（严格 2026）
- `research/sources/event_name_alias_map.csv`：名称映射（去重别名）
- `research/analysis/matsuri_2026_crawl_plan_by_site.md`：分站抓取计划
- `research/analysis/matsuri_2026_field_mapping.md`：统一字段融合映射
- `data/raw`：原始抓取数据
- `data/logs`：抓取日志
- `data/fused`：融合去重结果

## 快速开始

1) 安装依赖（使用 conda）

```bash
conda env create -f environment.yml
conda activate hanabi-ops
```

或手动创建：

```bash
conda create -n hanabi-ops python=3.11 -y
conda activate hanabi-ops
pip install -r requirements.txt
```

2) 启动统一数据管理系统（HANABI + OMATSURI）

```bash
../scripts/start_ops_console.sh
```

打开 `http://127.0.0.1:8788` 后可直接：
- 触发 OMATSURI 全量更新
- 触发 OMATSURI 不完整信息高频更新
- 查看 OMATSURI 当前统计
- 查看 OMATSURI 字段结构覆盖率
- 查看任务执行日志

3) 运行抓取（默认 6 站）

```bash
conda activate hanabi-ops
python -m omatsuri_crawler \
  --config research/sources/matsuri_2026_crawl_site_configs.yaml \
  --sites jalan_event,matsuri_no_hi,omatsurijapan,omatsuri_com,kankomie_event,japan47go_event \
  --max-list-pages 120 \
  --max-detail-pages 500 \
  --qps-multiplier 1.5 \
  --target-year 2026 \
  --strict-year \
  --out-dir data/raw \
  --log-dir data/logs \
  --fused-dir data/fused \
  --alias-map research/sources/event_name_alias_map.csv \
  --run-id 20260215_full_omatsuri_01
```

4) 查看进度

```bash
scripts/progress_report.py 20260215_full_omatsuri_01
```

5) 高频更新（仅针对信息不完整记录）

```bash
conda activate hanabi-ops
PYTHONPATH=. python scripts/refresh_incomplete_events.py \
  --run-id 20260215_omatsuri_highfreq_01 \
  --priority high \
  --max-events 500 \
  --no-geocode
```

输出：
- 刷新日志：`data/logs/<run_id>/refresh_incomplete_log.csv`
- 信息不完整队列：`data/logs/<run_id>/incomplete_events.csv`
- 最新高频队列：`data/reports/latest_high_freq_update_queue.csv`

6) 低频内容增强（图片 + 活动介绍润色）

```bash
python3 ../scripts/enrich_event_content.py \
  --project omatsuri \
  --run-id 20260217_omatsuri_content_01 \
  --min-refresh-days 45 \
  --qps 0.12 \
  --download-images
```

说明：
- 输入基于 `data/latest_run.json` 中的 `fused_run_id`。
- 默认提示词模板在 `../文档/` 下：
  - `../文档/event-description-polish.prompt.md`
  - `../文档/event-one-liner.prompt.md`
- 输出到：
  - `data/content/<run_id>/events_content.jsonl`
  - `data/content/<run_id>/events_content.csv`
  - `data/content/<run_id>/content_enrich_log.csv`

## 说明
- 祭典抓取与花火抓取完全解耦，独立维护。
- 当前已实现站点：`jalan_event`、`matsuri_no_hi`、`omatsurijapan`、`omatsuri_com`、`kankomie_event`、`japan47go_event`。
- 融合结果会自动打标：`is_info_incomplete`、`incomplete_fields`、`update_priority`，用于后续高频更新。
- 融合过程会自动输出地理日志：
  - `data/logs/<run_id>/geocode_log.csv`
  - `data/logs/<run_id>/geo_overlap_repair_log.csv`（同坐标重叠脏数据二次联网重查）
- 导出 iOS 数据包前必须通过统一门禁：`bash 数据端/scripts/update_ios_payload.sh --pretty`（内置 `geo_overlap_quality_gate.py`）。
