# Tsugie iOS App Store 高压线定期检查（2026-02-15, v1）

## 1. 记录目的
- 当前阶段为初期开发，尚未进入提审。
- 本记录用于“定期体检 + 后续复查对照”，不作为本轮开发阻断结论。

## 2. 检查范围与口径
- 范围：
  - `ios开发/tsugie/tsugie.xcodeproj/project.pbxproj`
  - `ios开发/tsugie/tsugie/**/*.swift`
  - `ios开发/tsugie/tsugie/APP_STORE_PRECHECK.md`
- 口径（高压线优先）：
  - `2.1 App Completeness`
  - `2.3 Accurate Metadata`
  - `2.5.1 Public APIs`
  - `4.2 Minimum Functionality`
  - `5.1 Privacy`

## 3. 检查结果（本轮）

### 3.1 高优先级风险（后续需先收敛）
1. `high`：当前地按钮语义与实现不一致（可能触发 `2.1/2.3`）
- 现象：UI 文案为“現在地へ戻る”，但实际逻辑是回到固定坐标。
- 证据：
  - `ios开发/tsugie/tsugie/Presentation/HomeMap/HomeMapView.swift:183`
  - `ios开发/tsugie/tsugie/Presentation/HomeMap/HomeMapViewModel.swift:263`
  - `ios开发/tsugie/tsugie/Presentation/HomeMap/HomeMapViewModel.swift:42`
- 影响：审核体验中可能被判断为“功能语义不实”。

2. `high`：通知设置仅 UI 开关，未接权限与调度链路（可能触发 `2.1`）
- 现象：侧栏存在“开始前提醒/附近通知”交互，但 ViewModel 仅切换本地布尔值。
- 证据：
  - `ios开发/tsugie/tsugie/Presentation/HomeMap/Components/SideDrawerLayerView.swift:286`
  - `ios开发/tsugie/tsugie/Presentation/HomeMap/Components/SideDrawerLayerView.swift:289`
  - `ios开发/tsugie/tsugie/Presentation/HomeMap/HomeMapViewModel.swift:255`
  - `ios开发/tsugie/tsugie/Presentation/HomeMap/HomeMapViewModel.swift:259`
- 影响：若提审前不收敛，易被视为占位功能或“承诺功能未实现”。

### 3.2 中优先级风险（元数据/阶段边界需控制）
1. `medium`：主数据源为 Mock，若元数据宣称“实时附近推荐”可能触发 `2.3/4.2`
- 证据：
  - `ios开发/tsugie/tsugie/Presentation/HomeMap/HomeMapViewModel.swift:51`
  - `ios开发/tsugie/tsugie/Infrastructure/MockHePlaceRepository.swift:5`
- 影响：需在提审物料中避免超出现阶段能力的描述。

2. `medium`：隐私合规模板尚未补齐（后续接权限时风险会升高）
- 现状：
  - 代码中尚无定位/通知权限请求链路。
  - 工程中未看到 `PrivacyInfo.xcprivacy`。
  - 已存在本地数据存储与剪贴板操作。
- 证据：
  - `ios开发/tsugie/tsugie/Infrastructure/PlaceStateStore.swift:6`
  - `ios开发/tsugie/tsugie/Presentation/HomeMap/Components/SideDrawerLayerView.swift:310`
  - `ios开发/tsugie/tsugie/APP_STORE_PRECHECK.md:67`
- 影响：进入权限接入阶段后，需要同步补齐隐私声明与用途说明。

### 3.3 低优先级风险
1. `low`：`mailto` 链接使用强制解包，存在低概率崩溃点
- 证据：`ios开发/tsugie/tsugie/Presentation/HomeMap/Components/SideDrawerLayerView.swift:298`

## 4. 本轮未发现的高压线信号
- 未发现私有 API / 动态执行代码 / 越权能力迹象（静态扫描口径）。
- 未发现账号、支付、社交等超 MVP 边界能力被引入。

## 5. 复查触发条件（建议）
- 触发 A：接入真实定位能力前后（`CLLocationManager` 相关）。
- 触发 B：接入本地通知能力前后（`UNUserNotificationCenter` 相关）。
- 触发 C：准备 TestFlight / 提审前，按 `APP_STORE_PRECHECK.md` 完整复跑。

## 6. 复查结论标签（本次）
- 结论：`阶段性可继续开发（需保留风险台账）`
- 标签：`初期开发/非提审态/定期检查`
