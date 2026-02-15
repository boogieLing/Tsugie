# Tsugie iOS 全量内置 + 实时附近检索 技术方案（v1，完整实现版）

## 0. 文档目的

本文在现有 `v1` 方案基础上，给出“数据端 -> iOS 端”的完整技术实现说明，覆盖：

- 端到端数据链路
- 数据结构设计
- 核心算法与复杂度
- 启动加载与定位策略
- 性能画像（当前资源实测）
- 测试覆盖与风险清单
- 后续演进建议

> 适用代码基线：
> - `数据端/scripts/export_ios_seed.py`
> - `数据端/scripts/update_ios_payload.sh`
> - `ios开发/tsugie/tsugie/Infrastructure/EncodedHePlaceRepository.swift`
> - `ios开发/tsugie/tsugie/Infrastructure/AppLocationProvider.swift`
> - `ios开发/tsugie/tsugie/Presentation/HomeMap/HomeMapViewModel.swift`

---

## 1. 目标与约束

### 1.1 目标

实现“**App 内置全量数据，但首屏只加载定位附近数据**”，避免启动阶段全量解码导致的内存与时延开销。

### 1.2 约束

- 数据必须离线内置（无首屏网络依赖）
- 必须保留数据保护链路（混淆 + 无损压缩 + 编解码）
- 接入与更新流程必须脚本化
- 开发阶段允许固定定位桩点（天空树），正式阶段支持动态定位

### 1.3 当前默认参数

- 开发桩点：`35.7101, 139.8107`（东京天空树）
- 默认检索半径：`30km`
- 默认返回上限：`700`
- 当前总记录：`4102`（hanabi: `630`，matsuri: `3472`）

---

## 2. 端到端架构总览

### 2.1 逻辑架构

1. 数据端读取 `HANABI/OMATSURI` 的 `latest_run.json` 指向 fused 产物。
2. 导出脚本将全量记录转换为 iOS seed entry，并按 Geohash 分桶。
3. 每个桶做 `zlib + xor` 编码后顺序写入 `payload.bin`。
4. `index.json` 记录每个桶的 `offset/length` 与校验信息。
5. iOS 启动时读取 `index.json`，按定位实时算附近桶，只读相关分片并解码。
6. 结果映射到 `HePlace`，按距离/优先级排序后供地图页渲染。

### 2.2 关键文件

- 数据端
  - `数据端/scripts/export_ios_seed.py`
  - `数据端/scripts/update_ios_payload.sh`
- iOS 资源
  - `ios开发/tsugie/tsugie/Resources/he_places.index.json`
  - `ios开发/tsugie/tsugie/Resources/he_places.payload.bin`
- iOS 运行时
  - `ios开发/tsugie/tsugie/Infrastructure/EncodedHePlaceRepository.swift`
  - `ios开发/tsugie/tsugie/Infrastructure/AppLocationProvider.swift`
  - `ios开发/tsugie/tsugie/Presentation/HomeMap/HomeMapViewModel.swift`

---

## 3. 数据端链路实现

## 3.1 输入源

导出脚本从两个垂类读取最新 fused 结果：

- `数据端/HANABI/data/latest_run.json` -> `fused_run_id`
- `数据端/OMATSURI/data/latest_run.json` -> `fused_run_id`
- 实际读取：`.../data/fused/<run_id>/events_fused.jsonl`

脚本函数：`load_latest_fused_records(...)`。

## 3.2 记录标准化与派生字段

每条 fused 记录会被转换为一个 iOS seed entry，关键处理如下：

1. 主键
- `ios_place_id = uuid5("tsugie:{category}:{canonical_id}")`

2. 日期/时间提取
- `extract_date` 支持 `YYYY-MM-DD`、`YYYY/MM/DD`、`YYYY年M月D日` 等
- `extract_time` 支持 `HH:MM`、`HH時MM分`

3. 评分派生
- `scale_score` / `heat_score` / `surprise_score`
- 输入特征：`source_count`、`launch_count`、`expected_visitors`、`update_priority`

4. 坐标与 Geohash
- 坐标来自 fused 的 `lat/lng`
- 默认 Geohash 精度：`5`
- 非法坐标会被丢弃 geohash（会进入 `_unknown` 桶）

5. 其它派生
- `hint`
- `distance_meters`（当前通过哈希生成，用于 seed 占位；iOS 运行时会改算真实距离）

## 3.3 空间分桶与二进制封包

函数：`build_spatial_payload(entries, key_seed)`

步骤：

1. 以 `entry.geohash` 作为桶键分组（缺失用 `_unknown`）
2. 每桶按 `ios_place_id` 排序，保证导出稳定性
3. 每桶 payload 编码：
   - JSON UTF-8
   - `zlib.compress(level=9)`
   - `xor_sha256_stream_v1`
4. 将编码后 bytes 顺序 append 到一个 `payload` 大字节数组
5. 在索引记录每个桶：
   - `record_count`
   - `payload_sha256`（对原始 JSON 计算）
   - `payload_offset`
   - `payload_length`

## 3.4 输出结构

### 3.4.1 索引文件 `he_places.index.json`

关键字段：

- `version`：当前 `3`
- `codec`
  - `compression = zlib`
  - `obfuscation = xor_sha256_stream_v1`
  - `encoding = binary_frame_v1`
- `source_runs`
- `record_counts`
- `spatial_index`
  - `scheme = geohash_prefix_v1`
  - `precision`
  - `bucket_count`
- `payload_file`
- `payload_sha256`
- `payload_size_bytes`
- `payload_buckets`

### 3.4.2 负载文件 `he_places.payload.bin`

- 仅包含按桶拼接后的混淆压缩二进制流
- 不含分隔符，完全依赖 `index.json` 的偏移长度读取

## 3.5 维护脚本入口

命令：

```bash
bash 数据端/scripts/update_ios_payload.sh --pretty
```

输出校验摘要：

- `index_size_bytes/index_sha256`
- `payload_size_bytes/payload_sha256`
- `record_counts`
- `spatial_index`
- `codec`

---

## 4. iOS 端加载链路实现

## 4.1 启动链路入口

`RootView` 中初始化 `HomeMapViewModel`：

- `ios开发/tsugie/tsugie/App/RootView.swift`

`HomeMapView` 生命周期触发：

- `.onAppear -> viewModel.onViewAppear()`
- `.onDisappear -> viewModel.onViewDisappear()`

## 4.2 ViewModel 启动策略

在 `HomeMapViewModel` 中：

1. 初始化时 `places` 可为空（不阻塞首屏）
2. `onViewAppear()` 调用 `bootstrapNearbyPlacesIfNeeded()`
3. 后台任务执行 `reloadNearbyPlacesAroundCurrentLocation(...)`
4. 定位完成后，通过 `Task.detached` 调用仓储层加载附近数据
5. 加载成功后 `replacePlaces(...)` 替换数据源并刷新地图 marker 缓存

这实现了“首屏先出地图骨架，数据异步补齐”。

## 4.3 定位策略抽象

文件：`AppLocationProvider.swift`

接口：

```swift
protocol AppLocationProviding {
    func currentCoordinate(fallback: CLLocationCoordinate2D) async -> CLLocationCoordinate2D
}
```

默认实现 `DefaultAppLocationProvider`：

- `Mode.developmentFixed`
- `Mode.live`

当前阶段默认：

- `stageDefaultMode = .developmentFixed`
- 固定返回天空树坐标

`live` 模式行为：

- 使用 `CLLocationManager`
- 处理授权状态
- `requestLocation()` 单次请求
- 2 秒超时回退

## 4.4 仓储加载主流程

文件：`EncodedHePlaceRepository.swift`

公开入口：

- `load()`（默认中心 + 半径 + limit）
- `loadNearby(center:radiusKm:limit:)`
- 测试入口：`loadNearby(from indexData:payloadData:center:radiusKm:limit:)`

流程：

1. 定位 index 资源（支持多 bundle 搜索）
2. 解析 `HePlacesSpatialIndexEnvelope`
3. 定位 payload 资源（优先 `index.payload_file`）
4. 计算附近候选 geohash keys
5. 遍历命中桶，按 `offset/length` 随机读取分片
6. 分片解码 -> item 数组 -> `HePlace`
7. 排序 + 半径过滤 + `limit` 截断
8. 若附近结果为空，执行全桶兜底扫描

---

## 5. 数据结构设计（运行时）

## 5.1 索引模型

```swift
HePlacesSpatialIndexEnvelope {
  version
  spatialIndex: { scheme, precision, bucketCount }
  payloadFile
  payloadSHA256
  payloadSizeBytes
  payloadBuckets: [String: EncodedPayloadBucketMeta]
}

EncodedPayloadBucketMeta {
  recordCount
  payloadSHA256
  payloadOffset
  payloadLength
}
```

## 5.2 seed item 模型

```swift
EncodedHePlaceItem {
  category
  iosPlaceID
  distanceMeters
  scaleScore
  heatScore
  surpriseScore
  hint
  normalizedStartDate
  normalizedEndDate
  normalizedStartTime
  normalizedEndTime
  geohash
  record: FusedEventRecord
}
```

`FusedEventRecord` 内含原始融合字段，支持字符串/数字的宽松解码。

## 5.3 Domain 模型

```swift
HePlace {
  id, name, heType, coordinate,
  startAt, endAt,
  distanceMeters, scaleScore,
  hint, openHours, mapSpot,
  detailDescription,
  imageTag, imageHint,
  heatScore, surpriseScore
}
```

---

## 6. 核心算法说明

## 6.1 Geohash 编码/边界解析

仓储中内置 `GeohashCodec`：

- `encode(lat,lng,precision)`
- `boundingBox(geohash)`

用于：

- 计算中心格子
- 计算中心格子的经纬步长（`latStep/lngStep`）

## 6.2 附近桶候选扩张算法

输入：`center + radiusKm + precision`

步骤：

1. 取中心 hash 与其 bbox
2. 计算一格在纬向/经向对应的米数
3. 计算需要覆盖的格子数：
   - `latCells = ceil(radiusMeters / latMeters)`
   - `lngCells = ceil(radiusMeters / lngMeters)`
4. 双循环采样周边格子并编码成 geohash key
5. 上限保护：`latCells/lngCells <= 32`

特性：

- 覆盖简单稳定
- 不依赖额外地理库
- 在大半径时 key 数增长较快（二维增长）

## 6.3 分片读取算法

对命中桶：

- `seek(toOffset)`
- `read(upToCount: payloadLength)`

时间复杂度近似：

- `O(K + B + N log N)`
- `K` 候选 key 数
- `B` 命中桶数
- `N` 解码后记录数（排序主成本）

空间复杂度近似：

- `O(decoded_bytes + N)`

## 6.4 解码与容错算法

1. `xor` 反混淆
2. 优先 `zlib wrapped inflate`
3. 兼容 `raw deflate`（历史兼容）
4. JSON 解码：
   - 先尝试整数组 decode
   - 失败后逐元素容错 decode（坏数据跳过）

## 6.5 结果排序与过滤

排序规则：

1. `distanceMeters` 升序
2. `scaleScore` 降序
3. `name` 字典序

过滤：

- 距离阈值 `radiusMeters * 1.2`
- 若过滤后非空，截断 `limit`
- 若过滤后空，返回排序后前 `limit`

---

## 7. 当前资源与性能画像（实测）

## 7.1 当前资源快照

来自 `he_places.index.json`：

- `version`: `3`
- `precision`: `5`
- `bucket_count`: `1656`
- `record_counts.total`: `4102`
- `payload_size_bytes`: `2,030,566`
- `index` 文件体积：约 `331,728` bytes
- `payload` 文件体积：约 `2,030,566` bytes

桶分布（按 `record_count`）：

- 最小：`1`
- 最大：`449`
- 平均：`2.48`

## 7.2 天空树场景覆盖统计（按当前算法复算）

中心：`35.7101, 139.8107`

### 半径 10km

- `candidate_keys`: `49`
- `matched_buckets`: `27`
- `matched_records`: `538`
- `matched_payload_bytes`（压缩后）：`113,226`
- 解压后 JSON bytes：`797,459`

### 半径 30km（当前默认）

- `candidate_keys`: `255`
- `matched_buckets`: `75`
- `matched_records`: `746`
- `matched_payload_bytes`（压缩后）：`183,414`
- 解压后 JSON bytes：`1,121,748`

> 解释：当前默认 `limit=700`，但算法在排序前会先解码全部命中桶，所以会解码到 `746` 条，再做截断。

---

## 8. 测试覆盖现状

## 8.1 已有测试

`EncodedHePlaceRepositoryTests` 已覆盖：

- 半径过滤行为
- `limit` 行为
- 非法索引输入行为
- 使用真实资源文件的集成型加载检查（天空树 + 30km，结果 > 50）

`HomeMapViewModelTests` 已覆盖：

- 地图分类筛选对选择态清理
- 收藏/打卡计数
- 分类计数

## 8.2 仍缺少的测试

- `AppLocationProvider` 的 live 授权分支与超时分支
- 仓储层“附近为空触发全桶兜底”路径
- 大半径下候选 key 扩张边界行为
- payload 校验（sha256）失败场景
- 启动异步加载的性能回归测试

---

## 9. 实现核对结论与风险清单

## 9.1 核对结论

当前实现已满足核心目标：

- 全量内置：已实现
- 启动按定位附近检索：已实现
- 启动异步加载：已实现
- 混淆/压缩/编解码：已实现
- 脚本化维护：已实现

## 9.2 关键风险（按优先级）

1. **默认定位模式仍是开发桩点**
- 当前 `DefaultAppLocationProvider.stageDefaultMode = .developmentFixed`
- 若直接用于正式包，定位会固定在天空树

2. **解码前未做早停**
- 命中桶全部解码后才 filter/limit
- 在大半径或热点区域会造成额外 CPU/内存开销

3. **兜底策略是全桶扫描**
- 当附近结果为空时，成本可能接近全量解码

4. **运行时未校验 payload sha256**
- 索引里有校验值，但 iOS 当前未做完整性校验

5. **失败回退 Mock 可能掩盖线上资源问题**
- 用户侧可用性提高，但会降低问题暴露速度

---

## 10. 演进建议（v1 -> v1.1）

## 10.1 立即可做

1. 解码早停
- 以“按距离 ring 扩展 bucket”的顺序解码
- 达到 `limit + buffer` 后停止

2. 分层半径
- 冷启动先 `10km`
- 不足再扩到 `20km/30km`

3. 兜底改环扩张
- 以 ring 逐层扩大
- 替代一次性全桶扫描

4. payload 完整性校验
- 读取文件后校验整体 `payload_sha256`
- 或按桶校验 `payload_sha256`

## 10.2 版本化与兼容

- 维持 `index.version` 作为协议版本
- 导入新编码算法时保留旧版解码兼容窗口
- 脚本与 iOS 解码器必须同版本联动发布

## 10.3 观测与告警

建议增加埋点：

- `candidate_keys_count`
- `matched_buckets_count`
- `decoded_items_count`
- `decode_payload_bytes`
- `load_duration_ms`
- `fallback_to_mock`

---

## 11. 运维与使用手册（简版）

## 11.1 更新数据包

```bash
bash 数据端/scripts/update_ios_payload.sh --pretty
```

## 11.2 验收检查

1. 查看脚本输出的 counts/sha256/size
2. 确认资源文件已更新：
- `he_places.index.json`
- `he_places.payload.bin`
3. iOS 构建并进入地图页，检查附近数据是否出现

## 11.3 最小提交清单

- `数据端/scripts/export_ios_seed.py`
- `数据端/scripts/update_ios_payload.sh`
- `ios开发/tsugie/tsugie/Infrastructure/EncodedHePlaceRepository.swift`
- `ios开发/tsugie/tsugie/Infrastructure/AppLocationProvider.swift`
- `ios开发/tsugie/tsugie/Resources/he_places.index.json`
- `ios开发/tsugie/tsugie/Resources/he_places.payload.bin`
- `记录/tsugie-ios-全量内置实时附近检索技术方案-v1.md`

---

## 12. 一句话结论

当前方案已经完成“全量内置 + 实时附近检索”的工程闭环，性能瓶颈已从“全量加载”转为“命中桶解码策略”；下一阶段应重点优化“早停解码 + 分层半径 + 兜底环扩张 + 校验落地”。
