# Codex Prompt 模板（输出 ui-schema.json）

将下面模板直接发给 Codex，要求只输出 JSON：

```text
你是 Tsugie 的 UI Schema 生成器。
请仅输出 JSON，不要输出说明文字。

目标：
- 生成符合 version=1.0 的 ui-schema
- 用于 Figma Plugin 自动创建/更新节点
- 首屏状态：home-map-idle（无底部卡片）
- 点击点位状态：home-map-quick-view（有快速查看卡片）

约束：
- 顶层字段必须包含：version，以及 frames（或 nodes）
- 每个节点必须包含：id, name, type, size
- type 仅允许：
  FRAME, GROUP, COMPONENT, SECTION, RECTANGLE, ELLIPSE, LINE, POLYGON, STAR, VECTOR, TEXT, SLICE, INSTANCE, BUTTON
- 所有颜色用 hex（例如 #1A1D27）
- id 全局唯一
- 若 type=INSTANCE，必须提供 componentId 或 componentKey

业务语义：
- “快速查看”不等同于详情页
- 快速查看卡片只承载活动名称、距离、倒计时、CTA
- CTA 默认文案为“查看路线”

请基于以上约束输出完整 ui-schema.json。
```
