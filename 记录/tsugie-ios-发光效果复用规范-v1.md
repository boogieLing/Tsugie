# Tsugie iOS 发光效果复用规范 v1

## 1. 目标
- 固化本轮已验证的“无边框 + 渐变发光 + 朦胧立体感”实现。
- 让地图页、日历页、侧栏、quickcard、轮播卡片等选中态使用同一发光机制。
- 降低后续 UI 微调成本，避免每个组件重复造轮子。

## 2. 语义边界（不变）
- 地图页 = 位置维度。
- 日历页 = 时间维度。
- 收藏 = 想访问；打卡 = 已访问。
- 时间状态同源：`upcoming / ongoing / ended / unknown`。
- 本规范只做视觉层复用，不扩 MVP 功能边界。

## 3. 核心实现
- 统一入口：`ios开发/tsugie/tsugie/Presentation/HomeMap/Components/TsugieVisualComponents.swift`。
- 核心方法：`View.tsugieActiveGlow(...)`。
- 设计意图：
  - 用 `overlay + blur` 做发光扩散层。
  - 用双层 `shadow` 做近光/远光，增强体积感。
  - 通过 `glowGradient + glowColor` 绑定主题色，避免固定色漂移。

### 3.1 推荐参数档位
- 图标级（状态 logo）：
  - `cornerRadius = size / 2`
  - `blurRadius = 8~16`
  - `primaryRadius = 10~24`
  - `secondaryRadius = 16~34`
- 胶囊按钮级（顶部按钮/筛选/侧栏项）：
  - `cornerRadius = 14~999`
  - `blurRadius = 8~12`
  - `primaryOpacity = 0.70~0.90`
  - `secondaryOpacity = 0.36~0.56`
- 强高亮 CTA（quickcard 主按钮）：
  - `glowOpacity >= 0.80`
  - `scale = 1.02~1.04`
  - `primaryRadius >= 14`
  - `secondaryRadius >= 24`

### 3.2 复用代码模板
```swift
.someView()
    .tsugieActiveGlow(
        isActive: isActive,
        glowGradient: activeGradient,
        glowColor: activeGlowColor,
        cornerRadius: 14,
        blurRadius: 10,
        glowOpacity: 0.82,
        scale: 1.03,
        primaryOpacity: 0.80,
        primaryRadius: 14,
        primaryYOffset: 4,
        secondaryOpacity: 0.44,
        secondaryRadius: 24,
        secondaryYOffset: 8
    )
```

## 4. 本轮已落地接入点
- `ios开发/tsugie/tsugie/Presentation/HomeMap/Components/TsugieVisualComponents.swift`
  - 新增统一发光扩展 `tsugieActiveGlow`。
  - `PlaceStateIconsView` 接入统一发光并支持 `activeGlowColor`、`activeGlowBoost`。
- `ios开发/tsugie/tsugie/Presentation/HomeMap/Components/QuickCardView.swift`
  - 关闭按钮、次按钮、主按钮、状态图标接入统一发光。
- `ios开发/tsugie/tsugie/Presentation/HomeMap/Components/NearbyCarouselView.swift`
  - 轮播卡片状态图标接入主题联动发光。
- `ios开发/tsugie/tsugie/Presentation/HomeMap/Components/MarkerActionBubbleView.swift`
  - 收藏/打卡动作按钮接入统一发光。
- `ios开发/tsugie/tsugie/Presentation/HomeMap/Components/MarkerBubbleView.swift`
  - 点位选中状态（logo、名称胶囊、状态图标）接入统一发光。
- `ios开发/tsugie/tsugie/Presentation/HomeMap/Components/DetailPanelView.swift`
  - 详情页状态图标接入主题联动发光。
- `ios开发/tsugie/tsugie/Presentation/HomeMap/Components/SideDrawerLayerView.swift`
  - 侧栏选中项、筛选胶囊、主题项、收藏项状态图标接入统一发光链路。
- `ios开发/tsugie/tsugie/Presentation/HomeMap/HomeMapView.swift`
  - 顶部按钮、地图交互按钮、点位组件参数透传 `activeGlowColor`。
- `ios开发/tsugie/tsugie/Presentation/Calendar/CalendarPageView.swift`
  - 日历筛选胶囊与列表状态图标接入统一发光。

## 5. SwiftUI 光效参考 case
- Apple 官方：`View.shadow(color:radius:x:y:)`
  - https://developer.apple.com/documentation/swiftui/view/shadow(color:radius:x:y:)
- Apple 官方：`View.blur(radius:opaque:)`
  - https://developer.apple.com/documentation/swiftui/view/blur(radius:opaque:)
- 开源案例：SwiftUI-Glow
  - https://github.com/fluidpixel/SwiftUI-Glow
- 开源案例：iOS18 Glow Animations
  - https://github.com/abdulkarimkhaan/iOS18-Glow-Animations
- 开源案例：SwiftUI-Shimmer（可作为高光扫动叠加层）
  - https://github.com/markiv/SwiftUI-Shimmer

## 6. 验收清单（复用时必查）
- 功能：
  - 仅改视觉反馈，不改变点击行为与状态机。
- UI 一致性：
  - 激活态无边框。
  - 发光颜色随主题切换同步变化。
  - 亮度/范围在 quickcard、轮播、侧栏、日历之间保持同一层级语言。
- 语义一致性：
  - 收藏/打卡仅用 logo 表达，不回退文字状态。
  - 时间状态输出仍使用同源模型，不在 UI 层重复定义。

## 7. 禁止项
- 禁止引入固定发光色，绕开主题系统。
- 禁止只靠描边表达选中态。
- 禁止在 UI 优化中扩展账号/社交/支付/复杂算法能力。
