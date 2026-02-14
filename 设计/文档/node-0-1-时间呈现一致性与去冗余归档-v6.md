# Node 0:1 时间呈现一致性与去冗余归档 v6

## 1. 阶段目标
- 将 quickcard、nearbyTrack、日历某日抽屉三处的时间表达统一到同一语义模型（与详情页同源）。
- 降低时间信息冗余，保证重点信息在不同模块的主次一致。

## 2. 本阶段需求（最终口径）
1. quickcard 中“活动持续时间范围”放到标题同一行最右侧（地点名在最左）。
2. nearbyTrack 的倒数逻辑与详情页保持一致。
3. 日历某日抽屉列表增加倒数逻辑，且与详情页一致。
4. 日历抽屉中已有时间范围时，不再重复显示开始/结束时间文案。

## 3. 功能落地（当前实现）
### 3.1 quickcard 标题行重构
- 新增 `quick-title-row`：左侧 `quickTitle`，右侧 `quickDuration`。
- `quickDuration` 使用统一状态输出：`startLabel - endLabel`。
- `quickMeta` 收敛为：`距离 + 日期语义`，移除时间范围冗余。

### 3.2 nearbyTrack 倒数同源
- nearby 不再使用旧的 `formatStartCountdown` 逻辑。
- 改为使用 `resolveEventStatus(place)` 的：
- `leftLabel`（如“開始までxx / 残りxx / 終了済み”）
- `rightLabel`（如“開始 HH:MM / 終了 HH:MM”）
- 从而与详情页时间语义保持同源。

### 3.3 日历抽屉倒数同源
- 每个 `drawer-day-item` 增加倒数行：
- 左侧展示 `leftLabel`。
- 原先右侧 `rightLabel` 在最终版移除，避免与上方已展示的时间范围重复。
- 保留上方时间范围行：`距离 ・ 开始-结束`。

## 4. 设计注意点（后续必须遵守）
1. 时间同源原则：
- 列表与卡片中的时间/倒数必须来自 `resolveEventStatus`，避免再次分叉。

2. 信息分层：
- quickcard 标题行右侧只放“时间范围”这一高优先信息。
- 次级信息（距离、日期语义）放在 `quickMeta`。

3. 去冗余原则：
- 同一条目中若已出现完整时间范围，不再重复“开始/结束”句式。
- 日历抽屉优先保证“地点 + 距离 + 时间范围 + 倒数状态”四要素。

4. 动态一致性：
- 详情、nearby、日历抽屉若出现状态冲突，优先检查状态源而非文案层。

## 5. 关键实现点
- quickcard 标题右侧时间：`quickDuration`
- quickcard 元信息收敛：`quickMetaText(place, status)`
- nearby 倒数同源：`renderNearbyCarousel` 中使用 `status.leftLabel/rightLabel`
- 日历抽屉倒数：`renderCalendarDayDrawerContent` 中 `drawer-day-item-countdown`

## 6. 验收清单
1. quickcard：标题左侧地点名、右侧时间范围同一行。
2. nearbyTrack：倒数文案与详情页状态一致（未开始/进行中/已结束）。
3. 日历抽屉：有时间范围 + 倒数状态，但不重复显示开始/结束说明。
4. 页面刷新后结构不丢失、样式不抖动。

## 7. 关联文件
- `设计/原型/main-screen.html`
- `设计/原型/main-screen.css`
- `记录/项目变更记录.md`
- `记录/归档/2026-02-14-node-0-1-时间呈现一致性与去冗余阶段归档-v6.md`

## 8. 本地前端快照（不入库）
- `记录/归档/frontend-code-snapshots/2026-02-14-node-0-1-time-presentation-v6/`
