# Tsugie iOS UI 美化技能编排流程 v1

更新时间：2026-02-15  
适用范围：`ios开发/tsugie/tsugie` 的 SwiftUI UI 优化迭代

## 1. 目标

- 把“界面美化”从临时发挥改为固定流程。
- 每次改 UI 都能复用同一套技能编排，降低返工。
- 在美观提升的同时，不突破 MVP 边界与审核风险。

## 2. 默认技能编排（统一）

1. `r0-ios-agents`：总控编排、分阶段推进。
2. `mobile-ios-design`：页面结构与 iOS 原生体验方向。
3. `apple-hig-designer`：HIG 对齐与交互规范检查。
4. `swiftui-expert-skill`：SwiftUI 代码实现与重构。
5. `swiftui-animation`：转场与微动效。
6. `interaction-design`：交互反馈细节（状态、点击反馈、过渡节奏）。
7. `accessibility-compliance`：动态字体、触控区、语义标签。
8. `r0-review`：提交前质量门禁。

## 3. 执行步骤（每轮 UI 美化都走）

### Step A. 需求对齐（不写代码）

- 明确本轮只优化哪些页面/组件。
- 明确不改哪些业务逻辑（防止 UI 需求膨胀）。
- 输出验收点：视觉、交互、性能、可访问性。

### Step B. 视觉与结构方案

- 使用 `mobile-ios-design` 先给布局/层级方案。
- 使用 `apple-hig-designer` 校验导航、手势、信息密度是否符合 iOS 习惯。
- 锁定 token 策略：颜色、圆角、阴影、间距、字体级别。

### Step C. SwiftUI 实现

- 使用 `swiftui-expert-skill` 进行代码落地。
- 优先小步提交：先结构，再样式，再交互，最后动效。
- 所有新增 UI 仍遵守语义边界：
  - 地图页=位置维度
  - 日历页=时间维度
  - 收藏=想访问，打卡=已访问
  - 状态同源=`upcoming/ongoing/ended/unknown`

### Step D. 动效与交互打磨

- 使用 `swiftui-animation` 处理面板出现/关闭、状态切换动画。
- 使用 `interaction-design` 补充按钮反馈、加载态、过渡节奏。
- 动效门禁：不影响主任务速度，不遮蔽核心信息。

### Step E. 可访问性与可用性

- 使用 `accessibility-compliance` 检查：
  - Dynamic Type
  - VoiceOver 可读性
  - 点击热区
  - 颜色对比
- 不通过则不进入下一步。

### Step F. 审查与收尾

- 使用 `r0-review` 做最终审查（正确性、可维护性、风险点）。
- 通过后再提交/归档。

## 4. Definition of Done（完成门禁）

- [ ] 视觉目标达成（层级、间距、信息密度一致）。
- [ ] 交互路径闭环，无卡死/断链。
- [ ] 不引入非 MVP 新功能。
- [ ] 状态语义未被破坏（同源模型保持一致）。
- [ ] 可访问性检查通过。
- [ ] `r0-review` 无高优先级问题。

## 5. 推荐节奏（单次迭代）

1. 第 1 天：方案与结构调整（无动效）。
2. 第 2 天：交互与动效补齐。
3. 第 3 天：无障碍与回归测试，完成审查与提交。

## 6. 反模式（明确禁止）

- 一次性重写整页导致无法定位回归问题。
- 在 UI 优化里顺手改业务规则。
- 动效优先于可读性。
- 未经检查直接进入提审链路。
