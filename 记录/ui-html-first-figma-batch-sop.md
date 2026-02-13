# UI HTML First -> Figma Batch SOP

## 1. 目标

将 UI 研发分为两阶段：
- 阶段 A：先输出并迭代 HTML 原型
- 阶段 B：你确认封板后，再一次性批量落到 Figma

该流程用于减少反复改稿导致的 Figma 噪音与节点碎片。

## 2. 适用范围

- 所有 Tsugie 的 UI 调整需求（含首页地图、卡片、状态页）
- 以视觉与交互节奏为主的需求，不要求先改 Figma

## 3. 标准执行步骤

1. 需求输入
- 你提出 UI 目标与改动方向。
- Codex 不先改 Figma，先在 `设计/原型/` 输出 HTML/CSS 版本。

2. HTML 迭代
- 你基于 HTML 连续提出调整意见。
- Codex 持续修改 HTML/CSS，直到你明确“封板/定稿/可以落 Figma”。

3. 封板确认（进入 Figma 阶段前置门禁）
- 触发词示例：`封板`、`定稿`、`可以一次性上 Figma`。
- 未触发前，不执行批量落图。

4. 一次性落 Figma
- Codex 生成对应 `ui-schema`（必要时配套 `color-system`）。
- 在 `Tsugie UI Schema Bridge` 执行：
  - `校验 -> 应用到 Figma`（结构改动）
  - `校验 color-system -> 应用 color-system`（主题改动）

5. 记录与归档
- 更新 `记录/项目变更记录.md`。
- 将最终 schema 归档到 `设计/figma-json-bridge/schema/`。

## 4. 文件落位约束

- HTML/CSS 原型：`设计/原型/`
- Figma 批量落图 schema：`设计/figma-json-bridge/schema/`
- 节点执行单：`设计/文档/`
- 过程记录：`记录/`

## 5. 协作约定

- “へ”是语义抽象，仅用于模型与命名层。
- 点位展示名称使用真实地点名，不使用“xxxへ”后缀。
- 若你未明确封板，Codex 默认继续 HTML 迭代，不提前批量改 Figma。
