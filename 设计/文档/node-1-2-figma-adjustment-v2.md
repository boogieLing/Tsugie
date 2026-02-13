# Node 1:2 Figma 调整方案（v2）

## 目标
- 首次进入页面：地图占满可视主区域，不出现底部卡片。
- 点击地图标记后：弹出底部“快速查看”卡片。
- 快速查看只承载关键信息，不等同于详情页；上滑才进入详情。

## 适用节点
- `fileKey`: `TTJqxbWWwwBUhj08iLj3aO`
- `nodeId`: `1:2`
- 参考：`设计/figma/node-1-2-reference.md`

## 交互状态拆分（Figma 内）
1. 新建两个 Frame（都为 `390 x 844`）：
   - `home-map-idle`：默认态（无底部卡片）
   - `home-map-quick-view`：点击标记后态（有快速查看卡片）
2. 将原 `1:2` 中底部卡片相关层（`1:9` ~ `1:16`）编组为 `quick-view-sheet`。
3. 在 `home-map-idle` 隐藏 `quick-view-sheet`；在 `home-map-quick-view` 显示。

## 视觉规范（快速查看卡片）
- 卡片位置：`x=16, y=560, w=358, h=220`
- 圆角：`20`
- 背景：`#1A1D27`
- 图片位：`326 x 100`，圆角 `12`
- 信息层级：
  - 标题（活动名）
  - 距离 / 步行时间
  - 开始倒计时
  - 一行推荐语（可选）
- CTA 文案避免“详情”语义，建议改为：
  - `查看路线`
  - `稍后提醒`

## 原型连线（Prototype）
1. `home-map-idle` 的标记（如 `1:8`）：
   - `On tap` -> `home-map-quick-view`
   - 动画：`Smart Animate`, `200ms`, `Ease out`
2. `home-map-quick-view`：
   - 点击地图空白处 -> 返回 `home-map-idle`
   - 卡片上滑手势 -> 详情页节点（保持现有详情流）

## 验收标准
- 首屏默认无卡片遮挡地图。
- 点击任一标记后 200ms 内出现快速查看卡片。
- 快速查看信息可在 3 秒内完成阅读。
- 卡片文案不出现“详情”误导入口。
