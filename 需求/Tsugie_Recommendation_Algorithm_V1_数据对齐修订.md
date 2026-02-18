# Tsugie Recommendation Algorithm V1 数据对齐修订（iOS 接入版）

更新日期：2026-02-19  
适用范围：`ios开发/tsugie` 当前内置数据包链路（`he_places.index.json` + `he_places.payload.bin` + `he_images.payload.bin`）

## 1. 原始 V1 算法（来自 docx）

原文档：`需求/Tsugie_Recommendation_Algorithm_V1.docx`

原始输入字段分三类：

1. 位置：`user_lat`、`user_lng`、`event_lat`、`event_lng`、`distance_km`
2. 时间：`now_ts`、`start_ts`、`end_ts`、`delta_start`
3. 活动属性：`event_type`、`estimated_people(可选)`、`scale_level(可选)`

原始排序核心：

1. 先过滤已结束（`now_ts < end_ts`）
2. 计算 `SpaceScore + TimeScore + HeatScore`
3. 乘 `CategoryWeight`
4. 按 `FinalScore` 降序取 Top N

## 2. 当前 App 已接入数据结构（事实基线）

### 2.1 iOS 端解码后的核心结构

- 业务模型：`HePlace`（`ios开发/tsugie/tsugie/Domain/Models/HePlace.swift:11`）
- 二进制条目：`EncodedHePlaceItem`（`ios开发/tsugie/tsugie/Infrastructure/EncodedHePlaceRepository.swift:692`）
- 数据导出来源：`build_entry()`（`数据端/scripts/export_ios_seed.py:218`）

当前条目核心字段：

- 一级字段：`category`、`ios_place_id`、`distance_meters`、`scale_score`、`heat_score`、`surprise_score`、`normalized_*`、`record`
- record 子字段（关键）：`event_name`、`event_date_start`、`event_date_end`、`event_time_start`、`event_time_end`、`lat`、`lng`、`launch_scale`、`expected_visitors`、`geo_source` 等

### 2.2 当前包体覆盖率（基于 2026-02-16 最新资源包实测）

样本总量：1419 条（hanabi 630 + matsuri 789）

1. `lat/lng`：1264/1419（89.08%）
2. `normalized_start_date`：1201/1419（84.64%）
3. `normalized_start_time`：46/1419（3.24%）
4. `normalized_end_date`：80/1419（5.64%）
5. `normalized_end_time`：29/1419（2.04%）
6. `expected_visitors`：18/1419（1.27%）
7. `launch_scale`：271/1419（19.10%）

结论：时间“日期”可用性尚可，时间“时分”稀疏；人数与规模等级原始字段明显不足，不能作为主排序依赖。

## 3. 字段对齐分析（需求字段 vs 现状）

| 原需求字段 | 当前接入字段 | 对齐状态 | 说明 |
|---|---|---|---|
| `user_lat` | `currentCoordinate.latitude` | 同义改名 | 来自定位服务，运行时提供（`ios开发/tsugie/tsugie/Infrastructure/AppLocationProvider.swift:25`） |
| `user_lng` | `currentCoordinate.longitude` | 同义改名 | 同上 |
| `event_lat` | `record.lat` -> `HePlace.coordinate.latitude` | 同义改名 | 解码映射见 `mapToHePlace` |
| `event_lng` | `record.lng` -> `HePlace.coordinate.longitude` | 同义改名 | 解码映射见 `mapToHePlace` |
| `distance_km` | `HePlace.distanceMeters / 1000` | 同义改名 | App 实际使用米，且会按用户位置实时重算距离 |
| `now_ts` | `Date()` | 同义改名 | 运行时当前时间 |
| `start_ts` | `startAt` | 同义改名 | 由 `normalized_start_date(+time)` 解析 |
| `end_ts` | `endAt` | 同义改名 | 由 `normalized_end_date(+time)` 解析，不足时回退 `startAt+2h` |
| `delta_start` | `startAt - now`（派生） | 语义存在但非落库字段 | 当前不落库，运行时可计算 |
| `event_type` | `category` / `heType` | 同义改名 | 当前主数据仅 `hanabi`/`matsuri` |
| `estimated_people` | `record.expected_visitors` | 部分可用 | 覆盖率仅 1.27%，且未进入强类型主模型 |
| `scale_level` | 无稳定等价字段 | 缺失 | 仅有 `launch_scale`（19.10%，值域不统一）和 `scale_score`（已数值化） |

## 4. 需求修订建议（V1.1，按当前数据可执行）

### 4.1 输入字段（修订后）

### A. 运行时字段

1. `user_lat` / `user_lng`（定位）
2. `now_ts`

### B. 事件基础字段（来自 iOS 包）

1. `category`（`hanabi` / `matsuri`）
2. `lat` / `lng`
3. `normalized_start_date` / `normalized_start_time`
4. `normalized_end_date` / `normalized_end_time`
5. `scale_score`（0-100）
6. `heat_score`（0-100）
7. `geo_source`（用于置信度分层）

### C. 派生字段

1. `distance_km = distanceMeters / 1000`
2. `start_ts`、`end_ts`
3. `delta_start_h = (start_ts - now_ts) / 3600`

### 4.2 时间解析规则（修订后）

与当前 iOS 解码逻辑保持一致（`ios开发/tsugie/tsugie/Infrastructure/EncodedHePlaceRepository.swift:826`）：

1. `start_ts`: 有 `normalized_start_date` 才可生成；缺开始时间时默认 `18:00`
2. `end_ts`: 有 `normalized_end_date` 时解析；缺结束时间默认 `21:00`
3. 若 `end_ts < start_ts`，回退为 `start_ts + 2h`
4. 若无 `end_ts` 但有 `start_ts`，回退为 `start_ts + 2h`

### 4.3 过滤规则（修订后）

1. 无坐标（`lat/lng` 缺失）直接过滤
2. 推荐主池使用 `start_ts` 可解析数据；无 `start_ts` 仅保留为兜底候选
3. 低置信度坐标（`geo_source in {missing, pref_center_fallback}`）保留但降权
4. nearby 轮播推荐粗排阶段先过滤 `ended`（避免过期活动进入候选池）
5. 已结束活动在非推荐展示链路可沿用现有保留窗口（当前为 31 天）

### 4.4 评分规则（修订后）

在当前数据质量下，热度建议优先使用已数值化字段，并按原始 V1（docx）回调权重：

1. `SpaceScore = exp(-distance_km / 5)`
2. `TimeScore`：`ongoing=1.0`；`<3h=0.8`；`<12h=0.6`；`<24h=0.3`；`>24h` 按 `delta_start` 连续衰减（不使用固定常数）
3. `HeatScore = clamp(heat_score / 100, 0, 1)`
4. `CategoryWeight` 当前定义：`hanabi=1.2`，`matsuri=1.0`，`nature=0.8`，其他=1.0

建议总分（V1 回调）：

`FinalScore = (0.45 * SpaceScore + 0.45 * TimeScore + 0.10 * HeatScore) * CategoryWeight`

说明：

1. 保留“空间+时间主导”原则
2. 避免依赖稀疏字段（`expected_visitors`、`launch_scale`）
3. 通过 `>24h` 连续衰减避免“微小距离差压过显著时间差”
4. 与当前 iOS 可用字段对齐，可直接落地

### 4.5 排序与输出（修订后）

1. 按 `FinalScore` 降序
2. 输出 Top N（首页默认 Top1 作为最速攻略）
3. 当评分相同：`hanabi` 优先 -> 距离近优先 -> 开始时间早优先 -> `heat_score` 高优先

当前 App（2026-02-19）排序实现说明：

1. 地图主推荐与 nearby 轮播统一使用 `FinalScore` 排序（由 `HomeMapViewModel.nearbyRecommendationSignal` 输出）。
2. 日历日抽屉保持“距离优先 -> 开始时间优先 -> 热度兜底”（`ios开发/tsugie/tsugie/Presentation/Calendar/CalendarPageView.swift:830`）。

### 4.6 触发策略（修订后）

1. nearby 推荐重排仅在用户地图移动结束后触发，不在拖动过程中连续触发。
2. marker 点击、quickCard 聚焦、定位重置等程序化相机变化不触发 nearby 推荐重排。

### 4.7 当前实现快照（2026-02-19，代码真值）

以下以 `ios开发/tsugie/tsugie/Presentation/HomeMap/HomeMapViewModel.swift` 当前实现为准：

#### 4.7.1 候选池与范围

1. 地图渲染池 `renderedPlaces`：
   - 使用 `mapBufferScale = 1.8` 的扩展视野；
   - 上限 `maxRenderedPlaces = 240`；
   - 用于地图 marker 渲染与 `mapPlaces()`。
2. 推荐候选池 `nearbyRecommendationPlaces`：
   - 使用更大推荐包络 `nearbyRecommendationBufferScale = 3.2`；
   - 上限 `maxNearbyRecommendationPlaces = 420`；
   - 当推荐包络无点位时回退到 `sourcePlaces`。
3. nearby 推荐不再被“严格视野内”约束，允许视野外但周边可达点位进入候选。
4. 类别筛选在推荐阶段与地图保持一致：`mapCategoryFilter != all` 时仅保留对应 `heType`。

#### 4.7.2 预过滤与数据质量处理

1. 推荐前统一走 `interactivePlaces`，会过滤“结束超过 31 天”的活动（`interactionRetentionDaysAfterEnded = 31`）。
2. nearby 粗排显式过滤 `ended`：
   - `eventStatus(for: place) != .ended` 才进入打分。
3. 坐标脏数据收敛：
   - 同坐标簇在数量 `>= 6` 且全部低置信度来源时，仅保留代表点；
   - 低置信度来源定义：`missing` / `pref_center_fallback` / `network_geocode*`。

#### 4.7.3 打分公式（当前在线）

1. 空间分：`SpaceScore = exp(-distance_km / 5)`
2. 时间分：
   - `ongoing = 1.0`
   - `upcoming`：
     - `<3h = 0.8`
     - `<12h = 0.6`
     - `<24h = 0.3`
     - `>24h = max(0.03, 0.3 / (1 + (delta_days - 1) / 14))`
   - `ended = 0.05`
   - `unknown = 0.08`
3. 热度分：`HeatScore = clamp(heat_score / 100, 0, 1)`
4. 类别权重：
   - `hanabi = 1.2`
   - `matsuri = 1.0`
   - `nature = 0.8`
   - `other = 1.0`
5. 地理置信度惩罚：
   - `geo_source in {missing, pref_center_fallback}` 时乘 `0.85`，否则乘 `1.0`
6. 最终分：
   - `FinalScore = (0.45 * SpaceScore + 0.45 * TimeScore + 0.10 * HeatScore) * CategoryWeight * GeoPenalty`

#### 4.7.4 排序同分规则（nearby）

按以下顺序比较：

1. `FinalScore` 降序
2. `heType`：`hanabi` 优先
3. 时间阶段：`ongoing(0) < upcoming(1) < ended(2) < unknown(3)`
4. 阶段内 delta（`stageDelta`）升序
5. 距离 `distanceMeters` 升序
6. `scaleScore` 降序
7. `name` 字典序升序

补充：

1. 地图首屏自动推荐（`recommendedPlace`）直接取 `nearbyPlaces(limit: 1)`。
2. 因此地图首推与 nearby 轮播排序完全同源。

#### 4.7.5 触发与生命周期（当前实现）

1. 用户手势相机变更路径：
   - `handleMapCameraChange` -> `scheduleViewportReload(reason: "cameraMove", debounce: 220ms)`。
2. 程序化相机变更抑制：
   - 在中心点/缩放容差窗口内命中 programmatic target 时，直接 `skipViewportReload`。
3. 包络内移动优化：
   - `cameraMove` 且仍在已加载包络内时，走 `cameraMoveContained` 轻量裁剪，不触发完整重载。
4. 生命周期与内存：
   - `onViewDisappear` 会取消相关异步任务，并主动清空 `nearbyRecommendationPlaces`；
   - 推荐池采用上限裁剪与整池替换，避免长会话无界增长。

#### 4.7.6 回归测试锚点

1. 时间权重案例：
   - `ios开发/tsugie/tsugieTests/Presentation/HomeMap/HomeMapViewModelTests.swift`
   - `testNearbyCarouselPrefersSoonerStartWhenDistanceGapIsSmall`
2. 视野外推荐案例：
   - `ios开发/tsugie/tsugieTests/Presentation/HomeMap/HomeMapViewModelTests.swift`
   - `testNearbyCarouselCanIncludePlacesOutsideCurrentViewportEnvelope`

## 5. 待后续数据端补齐后可恢复的 V1 原设定

以下项建议在数据覆盖率达标后再启用：

1. `estimated_people` 人数模型（当前覆盖 1.27%）
2. `scale_level` 离散等级模型（当前无统一字段）
3. `momiji` 等更多 `event_type` 权重（当前 iOS 包仅 hanabi/matsuri）

达标建议阈值：

1. `estimated_people` 覆盖率 >= 60%
2. `scale_level` 可标准化覆盖率 >= 80%
3. 可稳定供给 3 个以上类别类型
