# Tsugie iOS 文案与 i18n 维护规范（v1）

## 1. 目标与范围
- 目标：将 Tsugie iOS 所有通用文案统一接入可维护的 i18n 系统，减少硬编码与重复翻译成本。
- 语言范围：`zh-Hans / en / ja`。
- 语义硬约束：
  - 地图页 = 位置维度。
  - 日历页 = 时间维度。
  - 收藏 = 想访问；打卡 = 已访问。
  - 时间状态同源：`upcoming / ongoing / ended / unknown`。
- 地点名规则：地点名仅保留日本原名，不做翻译。

## 2. 代码结构
- 统一入口：`ios开发/tsugie/tsugie/App/Localization/L10n.swift`
- 语言资源：
  - `ios开发/tsugie/tsugie/Localization/zh-Hans.lproj/Localizable.strings`
  - `ios开发/tsugie/tsugie/Localization/en.lproj/Localizable.strings`
  - `ios开发/tsugie/tsugie/Localization/ja.lproj/Localizable.strings`

## 3. 使用规则
- 禁止在 View/ViewModel/Resolver 中新增硬编码用户文案，统一走 `L10n`。
- 静态文案使用 `L10n.xxx.yyy`。
- 带变量文案使用 `L10n.format` 封装（例如时间、倒计时、百分比）。
- 时间状态文案必须通过 `EventStatusResolver` + `L10n.EventStatus` 同源输出，避免多处拼接漂移。

## 4. Key 命名约定
- 按模块分组：`common.* / event.* / home.* / quickcard.* / nearby.* / detail.* / drawer.* / calendar.* / placeholder.* / mock.*`
- 命名稳定优先，不要把视觉字眼写进 key（例如颜色、位置、动画词）。
- 同语义跨模块复用同一 key（例如未知时间、开始未知、关闭）。

## 5. 新增文案流程（必须）
1. 在 `L10n.swift` 增加 typed API（属性或函数）。
2. 在三语 `Localizable.strings` 同步加 key。
3. 业务代码改为调用 `L10n`，不直接写字符串。
4. 执行编译校验：
   - `xcodebuild -project ios开发/tsugie/tsugie.xcodeproj -scheme tsugie -configuration Debug -sdk iphonesimulator -derivedDataPath /tmp/tsugie-derived CODE_SIGNING_ALLOWED=NO build`
5. 扫描回归：
   - 确认未新增硬编码文案（允许符号/图标字符）。

## 6. 验收清单
- 功能：所有页面可正常展示，交互链路不变。
- UI 一致性：文案替换不改变组件结构与视觉层级（1:1 原型复刻约束保持）。
- 语义一致性：地图/日历语义、收藏/打卡语义、时间状态语义保持一致。
- i18n 一致性：三语 key 完整，无缺失、无拼接歧义。
