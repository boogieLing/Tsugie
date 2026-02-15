# Tsugie iOS 全量内置 + 实时附近检索 技术方案（v1）

## 1. 背景与目标

### 1.1 业务目标

在保持 App 内置全量数据的前提下，实现“启动仅加载当前位置附近数据”，避免首屏将全部活动数据解码进内存。

### 1.2 工程目标

- 数据离线内置（无首屏网络依赖）
- 启动可快速出图，数据后台加载
- 支持开发阶段固定定位桩点（天空树）
- 支持生产阶段动态定位
- 编码链路可维护、可校验、可脚本化

### 1.3 当前场景约束

- 开发阶段定位桩点：东京天空树 `35.7101, 139.8107`
- 默认检索半径：`30km`
- 默认返回上限：`700`
- 数据总量：`4102` 条（HANABI + OMATSURI）

---

## 2. 方案总览

### 2.1 核心设计

采用“轻索引 + 二进制分片 payload + Geohash 空间检索”的离线数据方案：

1. 全量数据仍随 App 打包。
2. 启动时只解析轻量索引。
3. 根据当前定位实时计算附近 Geohash key。
4. 仅按 `offset/length` 读取命中 bucket 分片并解码。
5. 映射为 `HePlace` 后按距离/优先级排序，最后截断到 `limit`。

### 2.2 数据包结构

- 索引文件：`ios开发/tsugie/tsugie/Resources/he_places.index.json`
- 分片文件：`ios开发/tsugie/tsugie/Resources/he_places.payload.bin`

索引内包含：

- `spatial_index`：`scheme/precision/bucket_count`
- `payload_file`：payload 文件名
- `payload_sha256/payload_size_bytes`：整体校验
- `payload_buckets`：每个 bucket 的 `record_count/payload_offset/payload_length/payload_sha256`

### 2.3 编解码链路

编码（数据端导出）：

1. JSON UTF-8
2. `zlib` 无损压缩
3. `xor_sha256_stream_v1` 混淆
4. `binary_frame_v1` 分片写入（索引记录偏移）

解码（iOS 运行时）：

1. 按 `offset/length` 读取二进制分片
2. 去混淆
3. `zlib` 解压
4. JSON 解码

---

## 3. 关键实现位置

### 3.1 数据端导出与维护脚本

- 导出脚本：`数据端/scripts/export_ios_seed.py`
- 维护入口：`数据端/scripts/update_ios_payload.sh`

标准更新命令：

```bash
bash 数据端/scripts/update_ios_payload.sh --pretty
```

### 3.2 iOS 仓储层

- 文件：`ios开发/tsugie/tsugie/Infrastructure/EncodedHePlaceRepository.swift`

能力点：

- 读取索引并解析空间元信息
- 动态生成附近 Geohash 候选 key
- 基于 `FileHandle.seek + read(upToCount:)` 随机读取分片
- 分片级解码并映射 `HePlace`
- 排序、半径过滤和 limit 截断
- 附近无结果时兜底全桶扫描

### 3.3 启动加载与定位抽象

- 启动加载：`ios开发/tsugie/tsugie/Presentation/HomeMap/HomeMapViewModel.swift`
- 定位抽象：`ios开发/tsugie/tsugie/Infrastructure/AppLocationProvider.swift`

策略：

- 首屏先渲染地图骨架，后台异步加载附近数据
- Debug 默认固定桩点定位（天空树）
- Release 默认动态定位（`CLLocationManager`）

---

## 4. 内存优化设计（详细）

### 4.1 优化目标

- 避免“全量解码 + 全量对象化”造成的启动峰值内存抖动
- 将启动加载内存成本与“附近数据规模”而非“全量规模”绑定

### 4.2 已落地优化项

1. **包结构拆分优化**
- 从单大 JSON 改为 `index + payload.bin`
- 启动不再先完整解析大 JSON 文档

2. **空间分桶优化**
- 全量数据按 Geohash bucket 组织
- 仅读取命中 bucket 的分片

3. **随机读分片优化**
- 通过 `offset/length` 读取小块数据
- 避免将整个 payload 文件搬入内存后再切片

4. **启动异步化优化**
- 数据加载从主线程剥离到后台任务
- 减少首屏主线程阻塞与卡顿

5. **开发/生产定位分离**
- 开发态固定桩点便于稳定复现
- 生产态动态定位避免静态分区导致覆盖不足

### 4.3 当前实测内存画像（天空树 + 30km）

基于当前资源和仓储算法复算：

- 资源体积（磁盘）：
  - `index`: 约 `324KB`
  - `payload.bin`: 约 `1.9MB`

- 启动场景读取规模：
  - 候选 key：`255`
  - 命中 bucket：`75`
  - 读取分片总量：约 `179KB`（压缩+混淆后）
  - 解码记录：`746` 条
  - 解压后 JSON 总量：约 `1.07MB`

- 对比全量解码：
  - 全量记录：`4102` 条
  - 全量解压 JSON：约 `6.17MB`

### 4.4 启动内存估算（数据链路维度）

说明：以下仅为数据接入链路估算，不包含地图 SDK 渲染、纹理、系统缓存等图形开销。

- 当前方案（天空树 + 30km）
  - 峰值：约 `8MB ~ 20MB`
  - 稳态增量：约 `4MB ~ 12MB`

- 触发全桶兜底时
  - 峰值可能上升至约 `25MB ~ 60MB`

### 4.5 当前剩余优化空间

1. **提前停止解码**
- 现状：当前逻辑是先把命中 bucket 全部解码，再过滤/截断。
- 影响：`limit=700` 时实际可能先解码 >700（当前为 746）。
- 建议：按 bucket 优先级逐批解码，达到 `limit + buffer` 后停止。

2. **半径动态分层**
- 现状：固定 30km。
- 建议：冷启动先 10km，结果不足再扩到 20/30km，减少首批分片读取量。

3. **兜底策略改为“环扩张”**
- 现状：附近空时会全桶扫描。
- 建议：按 geohash ring 逐环扩张，避免一次性全量扫描。

4. **分片元信息预过滤**
- 可在索引加入更细粒度统计（如时间窗、类型计数），先做元数据过滤再解码正文。

5. **缓存策略**
- 引入短生命周期内存缓存（最近一次定位附近 buckets）与轻量 LRU，减少重复进入地图页的重复解码。

### 4.6 观测建议

建议每次数据包更新后至少执行一次：

- Instruments `Allocations` / `VM Tracker`（冷启动）
- 首次进入地图页的主线程耗时与内存峰值采样
- 记录如下指标：
  - `hit_buckets`
  - `decoded_items`
  - `decoded_json_bytes`
  - `load_duration_ms`

---

## 5. 可维护性与运维流程

### 5.1 固化维护入口

统一入口：`bash 数据端/scripts/update_ios_payload.sh --pretty`

脚本输出包含：

- `record_counts`
- `spatial_index`
- `index_size/index_sha256`
- `payload_size/payload_sha256`
- `codec`

### 5.2 变更同步要求

当编解码链路、资源路径、检索策略或定位策略发生变化时，必须同步更新：

- `AGENTS.md`
- `记录/项目变更记录.md`
- 相关 README 与维护清单

---

## 6. 当前结论

当前方案已满足“内置全量 + 启动仅附近加载 + 实时定位检索”的目标，且在开发定位桩点下已显著降低启动数据加载成本。

下一步优先级建议：

1. 落地“limit 提前停止解码”
2. 落地“分层半径扩张”
3. 落地“环扩张兜底替代全桶扫描”

完成以上三项后，启动内存峰值和首屏耗时会进一步下降。
