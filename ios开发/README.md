# iOS 开发

本目录用于 Swift/SwiftUI 客户端实现与测试。

## 当前实现入口

- 第一阶段骨架（地图首页 + 点位 + quickCard 基础链路）：
  - `ios开发/tsugie/tsugie/`

## 约束

- 仅在 `ios开发/` 内进行 iOS 代码实现。
- MVP 阶段不扩边界，不引入账号/社交/支付等能力。
- 地图页（位置维度）与日历页（时间维度）语义必须分离。
- UI 必须按“已封板原型 + CSS”做 1:1 复刻，不允许主观偏离视觉语义。

## 研发统一流程（三段）

1. 研发实现：功能可用与链路闭环（不扩 MVP 边界）
2. UI 优化：视觉、交互、动效、可访问性优化
3. 安全/提审审查：代码质量门禁与 App Store 高压线预检

## 阶段启动门禁（强制）

- 每个阶段开始前，先主动检索适用 skill，再执行阶段任务。
- 默认检索命令：
  - `python3 /Users/r0/.codex/skills/local-skill-finder/scripts/list_local_skills.py --query ios swiftui`
  - `python3 /Users/r0/.codex/skills/local-skill-finder/scripts/list_local_skills.py --query design ui animation`
  - `python3 /Users/r0/.codex/skills/local-skill-finder/scripts/list_local_skills.py --query review security privacy`

## 参考文档

- 全局协作规范：`AGENTS.md`
- UI 技能编排流程：`记录/tsugie-ios-ui美化技能编排流程-v1.md`
- 发光效果复用规范：`记录/tsugie-ios-发光效果复用规范-v1.md`
- i18n 文案维护规范：`记录/tsugie-ios-i18n文案系统规范-v1.md`
- 提审预检清单：`ios开发/tsugie/tsugie/APP_STORE_PRECHECK.md`
- 高压线定期检查记录：`记录/高压线检查/`
