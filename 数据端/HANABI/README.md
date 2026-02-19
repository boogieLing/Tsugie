# HANABI Crawler

当前已接入 8 个站点并统一到同一套抓取 + 融合 + 去重流水线：
- 主数据源：`hanabi_cloud`（融合字段选择时优先级最高）
- `sorahanabi`
- `hanabi_cloud`
- `jorudan`
- `weathernews`
- `hanabeat`
- `hanabi_navi`
- `jalan`
- `hanabeam`

站点抓取计划与配置：
- 计划文档：`research/analysis/hanabi_crawl_plan_by_site.md`
- 配置文件：`research/sources/hanabi_crawl_site_configs.yaml`

## 快速开始

1. 使用 conda 创建环境并安装依赖

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

2. 启动数据管理系统（推荐）

```bash
../scripts/start_ops_console.sh
```

默认行为：
- 自动检查 `conda` 是否可用
- 自动检查/创建环境 `hanabi-ops`
- 后台启动管理系统到 `http://127.0.0.1:8788`
- 运行日志写入 `../ops/console.out.log`（数据端根目录）

运维命令：

```bash
scripts/ops_console.sh status
scripts/ops_console.sh logs
scripts/ops_console.sh stop
scripts/ops_console.sh restart
```

等价的根目录入口（推荐在 `数据端/` 下使用）：

```bash
./scripts/start_ops_console.sh
./scripts/ops_console.sh status
```

可选：通过环境变量覆盖默认值（环境名/端口/主机）：

```bash
HANABI_CONDA_ENV=hanabi-ops HANABI_OPS_HOST=127.0.0.1 HANABI_OPS_PORT=8789 ../scripts/start_ops_console.sh
```

打开 `http://127.0.0.1:8788` 后可直接操作：
- 全量更新（支持年份隔离）
- 不完整信息高频更新
- 当前数据统计（含 `latest_metrics.json`）
- 当前数据结构分析（字段覆盖率）
- 任务与日志查看（`data/ops/*.log`）

核心 API：
- `GET /api/overview`
- `GET /api/structure?project=hanabi|omatsuri`
- `GET /api/jobs`
- `GET /api/job_log?job_id=...`
- `POST /api/run/full`
- `POST /api/run/highfreq`

3. 运行抓取（默认 8 站）

```bash
conda activate hanabi-ops
python3 -m hanabi_crawler \
  --config research/sources/hanabi_crawl_site_configs.yaml \
  --sites hanabi_cloud,sorahanabi,jorudan,weathernews,hanabeat,hanabi_navi,jalan,hanabeam \
  --max-list-pages 80 \
  --max-detail-pages 200 \
  --qps-multiplier 1.0 \
  --target-year 2026 \
  --strict-year \
  --out-dir data/raw \
  --log-dir data/logs \
  --fused-dir data/fused \
  --alias-map research/sources/event_name_alias_map.csv
```

默认行为：
- `fuse` 结束后会自动执行内容增强（`enrich_event_content.py`），输出介绍/一句话/图片（默认每活动最多 1 张图）。
- 如需临时关闭自动内容增强，可追加 `--no-content-enrich`。

4. 输出

- 每个站点输出一个 JSONL 文件，例如：`data/raw/sorahanabi.jsonl`
- 每次运行都会生成 URL 级 CSV 日志（稳定性与失败记录）：
  - `data/logs/<run_id>/request_log.csv`
  - `data/logs/<run_id>/failed_urls.csv`
  - `data/logs/<run_id>/site_summary.csv`
- 抓取结束后自动做跨站融合与去重：
  - 融合主表：`data/fused/<run_id>/events_fused.jsonl`
  - 融合 CSV：`data/fused/<run_id>/events_fused.csv`
  - 去重映射日志：`data/logs/<run_id>/dedup_log.csv`
  - 信息不完整队列：`data/logs/<run_id>/incomplete_events.csv`
  - 地理编码日志：`data/logs/<run_id>/geocode_log.csv`
  - 重叠坐标修复日志：`data/logs/<run_id>/geo_overlap_repair_log.csv`
  - 异名候选日志：`data/logs/<run_id>/name_alias_candidates.csv`
  - 别名映射配置：`research/sources/event_name_alias_map.csv`（持久化维护）

地理坐标质量说明：
- `fuse_records` 在常规 geocode 后会自动执行“同坐标重叠脏数据二次联网重查”。
- 默认规则仅处理低置信度来源重叠（`network_geocode*` / `pref_center_fallback` / `missing`）。
- 导出 iOS 数据包前必须通过统一门禁：`bash 数据端/scripts/update_ios_payload.sh --pretty`（内置 `geo_overlap_quality_gate.py`）。

5. 高频更新（仅针对信息不完整记录）

```bash
conda activate hanabi-ops
PYTHONPATH=. python scripts/refresh_incomplete_events.py \
  --run-id 20260215_hanabi_highfreq_01 \
  --priority high \
  --max-events 300 \
  --no-geocode
```

默认行为：
- 高频补充在 `fuse` 结束后同样会自动执行内容增强。
- 如需临时关闭自动内容增强，可追加 `--no-content-enrich`。

输出：
- 刷新日志：`data/logs/<run_id>/refresh_incomplete_log.csv`
- 最新高频队列：`data/reports/latest_high_freq_update_queue.csv`

6. 低频内容增强（图片 + 活动介绍润色）

```bash
python3 ../scripts/enrich_event_content.py \
  --project hanabi \
  --run-id 20260217_hanabi_content_01 \
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

- `hanabi.cloud` 已按浏览器 UA 抓取策略实现（普通 curl UA 会出现 403）。
- 可通过 `--run-id` 指定运行批次号。
- 可通过 `--no-fuse` 跳过融合阶段（默认开启）。
- 可通过 `--qps-multiplier` 按倍数提升各站 QPS（建议 1.2~2.0 之间逐步调优）。
- 默认启用严格年份隔离：`--strict-year`，仅保留 `--target-year` 的数据参与融合与去重（未识别年份的记录会被过滤掉）。
- 如需临时关闭年份过滤，可使用 `--no-strict-year`。
- 每次运行都会生成 CSV 日志（请求、失败、汇总、去重、异名候选）。
- 融合结果会自动打标：`is_info_incomplete`、`incomplete_fields`、`update_priority`，用于后续高频更新。
