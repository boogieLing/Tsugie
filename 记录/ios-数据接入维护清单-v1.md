# iOS 数据接入维护清单 v1

## 1. 目标

将 `HANABI + OMATSURI` 最新 fused 数据稳定更新到 iOS 资源包：

- 输入：`数据端/HANABI/data/latest_run.json`、`数据端/OMATSURI/data/latest_run.json`
- 输出：
  - `ios开发/tsugie/tsugie/Resources/he_places.index.json`
  - `ios开发/tsugie/tsugie/Resources/he_places.payload.bin`

## 2. 一次更新只用这条命令

```bash
bash 数据端/scripts/update_ios_payload.sh --pretty
```

脚本会自动输出：

- `record_counts`（hanabi/matsuri/total）
- `spatial_index`（scheme/precision/bucket_count）
- `index_size_bytes/index_sha256`
- `payload_size_bytes/payload_sha256`
- `codec`（compression/obfuscation/encoding）

## 3. 编解码基线（不可改顺序）

1. JSON UTF-8
2. `zlib` 无损压缩
3. `xor_sha256_stream_v1` 混淆
4. `binary_frame_v1` 分片编码（由 index 提供 `offset/length`）

iOS 端逆向顺序必须一致：

1. 按 `offset/length` 读取 payload 分片
2. 去混淆
3. zlib 解压
4. JSON decode

## 4. 预提交检查（最小集）

1. 确认 `latest_run.json` 指向正确批次
2. 执行更新命令并记录脚本输出
3. `git status --short` 仅包含本次预期变更
4. 在 iOS 里至少确认地图页可加载数据（资源包优先，失败回退 Mock）

## 5. 推荐提交文件清单

```text
数据端/scripts/export_ios_seed.py
数据端/scripts/update_ios_payload.sh
ios开发/tsugie/tsugie/Infrastructure/EncodedHePlaceRepository.swift
ios开发/tsugie/tsugie/Resources/he_places.index.json
ios开发/tsugie/tsugie/Resources/he_places.payload.bin
ios开发/tsugie/tsugie/Presentation/HomeMap/HomeMapViewModel.swift
ios开发/README.md
数据端/README.md
AGENTS.md
记录/项目变更记录.md
记录/ios-数据接入维护清单-v1.md
```

## 6. 提交信息模板

```text
feat: 接入 iOS 内置数据包并固化更新脚本

- source runs: hanabi=<run_id> omatsuri=<run_id>
- record counts: hanabi=<n> matsuri=<n> total=<n>
- index size: <bytes> bytes
- payload size: <bytes> bytes
- codec: zlib + xor_sha256_stream_v1 + binary_frame_v1
- app loading: EncodedHePlaceRepository first, fallback Mock
```
