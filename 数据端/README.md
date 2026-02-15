# 数据端

本目录用于活动数据处理、接口设计与推荐排序实现。

## 统一管理系统（HANABI + OMATSURI）

一键启动：

```bash
./scripts/start_ops_console.sh
```

地址：`http://127.0.0.1:8788`

运维命令：

```bash
./scripts/ops_console.sh status
./scripts/ops_console.sh logs
./scripts/ops_console.sh stop
./scripts/ops_console.sh restart
```

说明：
- 首次运行会自动检查/创建 conda 环境 `hanabi-ops`（基于 `HANABI/environment.yml`）。
- 可通过环境变量覆盖：`HANABI_CONDA_ENV`、`HANABI_OPS_HOST`、`HANABI_OPS_PORT`。

## iOS 数据包导出（HANABI + OMATSURI）

当 `data/latest_run.json` 指向新的 fused 批次后，可直接执行：

```bash
bash 数据端/scripts/update_ios_payload.sh --pretty
```

产物默认输出到：

- `ios开发/tsugie/tsugie/Resources/he_places.index.json`（空间索引）
- `ios开发/tsugie/tsugie/Resources/he_places.payload.bin`（二进制分片 payload）

编码链路（可逆）：

- 无损压缩：`zlib`
- 混淆：`xor_sha256_stream_v1`
- 编码：`binary_frame_v1`（按索引偏移读取分片）

维护建议：

1. 先确认两个子项目 `latest_run.json` 指向期望 `fused_run_id`
2. 执行统一脚本：`bash 数据端/scripts/update_ios_payload.sh --pretty`
3. 关注脚本输出中的 `record_counts`、`spatial_index`（precision/bucket_count）、`index_size_bytes/index_sha256`、`payload_size_bytes/payload_sha256`
4. 在 iOS 工程构建后验证地图与日历数据是否刷新

补充：

- `数据端/scripts/update_ios_payload.sh` 是维护入口，会调用 `数据端/scripts/export_ios_seed.py`。
- 默认导出为 Geohash 空间分桶，iOS 端按当前位置实时检索附近桶并解码。
- 需要自定义输出或 key 时，可直接调用 `export_ios_seed.py`。

## 技术文档入口（含内存优化）

- `记录/tsugie-ios-全量内置实时附近检索技术方案-v1.md`
- 文档包含：数据包结构设计、编解码链路、iOS 运行时检索流程、当前内存实测画像与后续优化路线。
