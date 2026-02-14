# つぎへ (Tsugi e)

最聪明的へ导航。

Tsugi e 的目标是：在「当前时间 + 当前地点」条件下，给用户一个下一站值得去的「へ（可前往地点）」决策。

![Tsugie 品牌视觉](设计/tsugie-logo.png)

## 当前产品基线（MVP）

- 打开即用，无需登录
- 首屏默认全屏地图，不自动弹卡
- 普通模式默认清新渐变色地图
- 进入一定时间后自动弹出“最速攻略”卡片
- 点击地图标记后弹出“快速查看”卡片（非详情）
- 上滑快速查看卡片进入详情页
- 推荐排序：今日优先 > 距离优先 > 规模优先

详细需求以 `需求/tsugihe_mvp_start_v0.1.md` 为准。

进入正式 iOS 开发阶段的执行总纲：`需求/tsugie-ios-dev-handoff-v1.md`。

## 当前研发进度（基于记录）

- 已完成项目结构重构与管理基线落地（`设计/`、`ios开发/`、`数据端/`、`需求/`、`记录/`）。
- 首页交互已切换为地图优先：默认全屏地图，点击点位进入“快速查看”，再上滑到详情。
- `Figma JSON Bridge` 已从初版升级到覆盖增强版，支持更多节点类型、图片填充、实例节点与主题色批量应用。
- 已建立两套执行 SOP：`记录/figma-json-bridge研发接入SOP.md` 与 `记录/ui-html-first-figma-batch-sop.md`。
- Node `0:1` 已完成 v1~v8 阶段归档（地图链路、详情状态、日历独立页、进度一致性、收藏打卡、主题调节）。
- 已完成 iOS 开发阶段交接总纲：统一历史需求、语义、页面、组件、交互状态机与关联逻辑。
- 当前阶段目标：按交接总纲进入 SwiftUI 正式实现。

可追溯明细见：`记录/项目变更记录.md`。

## 仓库结构

- `设计/`：Figma 资产、原型、设计文档
- `ios开发/`：iOS 客户端实现与测试
- `数据端/`：数据处理与接口相关实现
- `需求/`：需求文档
- `记录/`：过程记录与变更记录

## iOS 开发入口（当前阶段）

1. 需求基线：`需求/tsugihe_mvp_start_v0.1.md`
2. iOS 交接总纲：`需求/tsugie-ios-dev-handoff-v1.md`
3. 协作规范：`AGENTS.md`
4. 变更追踪：`记录/项目变更记录.md`

## iOS 研发统一流程（默认）

从当前阶段开始，iOS 迭代统一按三段执行：

1. 研发实现：功能落地与主链路可用（不扩 MVP 边界）
2. UI 优化：视觉层级、动效反馈、可访问性达标
3. 安全/提审审查：代码质量门禁 + App Store 高压线预检

阶段启动门禁（强制）：

- 每个阶段开始前，先主动检索可用 skill，再进入该阶段执行。
- UI 相关迭代必须按“已封板原型 + CSS”1:1 复刻，不做主观再设计。
- 本地检索默认命令：
  - `python3 /Users/r0/.codex/skills/local-skill-finder/scripts/list_local_skills.py --query ios swiftui`
  - `python3 /Users/r0/.codex/skills/local-skill-finder/scripts/list_local_skills.py --query design ui animation`
  - `python3 /Users/r0/.codex/skills/local-skill-finder/scripts/list_local_skills.py --query review security privacy`

对应执行文档：

- UI 技能编排流程：`记录/tsugie-ios-ui美化技能编排流程-v1.md`
- App Store 预检清单：`ios开发/tsugie/tsugie/APP_STORE_PRECHECK.md`

## Figma 自动化子项目

本仓库已内置独立子项目：`设计/figma-json-bridge/`

目标流程：

`Codex -> ui-schema.json -> Figma Plugin -> 自动创建/更新节点`

快速入口：

1. 阅读：`设计/figma-json-bridge/README.md`
2. 导入插件：`设计/figma-json-bridge/plugin/manifest.json`
3. 示例 schema：`设计/figma-json-bridge/schema/ui-schema.example.node-1-2.json`
4. schema 规范：`设计/figma-json-bridge/schema/ui-schema.v1.schema.json`

## 常用文件

- 项目协作规范：`AGENTS.md`
- 项目变更记录：`记录/项目变更记录.md`
- Node `1:2` 调整方案：`设计/文档/node-1-2-figma-adjustment-v2.md`
- Node `1:18` 调整方案：`设计/文档/node-1-18-ui优化执行单-v1.md`
- Node `2:29` 调整方案：`设计/文档/node-2-29-ui优化执行单-v1.md`
- へ抽象与命名规范：`设计/文档/figma-语义命名与へ抽象规范-v1.md`
- iOS 开发交接总纲：`需求/tsugie-ios-dev-handoff-v1.md`
- Figma 节点参考：`设计/figma/node-1-2-reference.md`
- Figma 节点参考（2:29）：`设计/figma/node-2-29-reference.md`
