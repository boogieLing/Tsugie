# Tsugie App Store Precheck

最后更新：2026-02-22  
适用范围：`ios开发/tsugie/tsugie` 提审前自检（App Store Connect + App Review）

## 0. 使用方式（门禁）

- 规则：任意一项 `❌` 都不提交审核。
- 执行节奏：每次准备提审前完整走一遍；版本冻结后再复检一次。

---

## 1. 高压线总览（先看）

1. `2.1 App Completeness`：崩溃、空页面、占位文案、假链接、后端不可用，直接高风险拒审。  
2. `2.5.1`：只能用公开 API，且要兼容当前正式系统版本。  
3. `3.1.1 In-App Purchase`：App 内解锁数字内容/功能必须用 IAP。  
4. `4.2 Minimum Functionality / 4.3 Spam`：壳应用、模板化堆量、链接聚合、营销页化，风险极高。  
5. `5.1.1 / 5.1.2 / 5.1.5`：隐私政策、数据使用透明、定位权限理由和行为不匹配会被拒。  
6. Privacy Manifest / Required Reason APIs：配置无效或缺失会触发上传/审核阻断。  
7. `2.3.1(a)`：禁止隐藏、休眠、未文档化功能；“敏感动作 + 隐藏触发”高风险。  
8. `2.1(b)`：App Review 必须可验证你在 App Store Connect 配置的能力（含 IAP/订阅）。  
9. `5.6.2 / 5.6.3`：开发者信息与应用行为必须真实，不得操纵评分、刷评、误导用户。  

---

## 2. 提审清单（勾选）

### A. 完整性与稳定性（Guideline 2.1）

- [ ] 真机 + 模拟器回归通过，无崩溃、无阻断主流程 bug。  
- [ ] 所有按钮、链接、导航入口有效，无占位文案/占位图。  
- [ ] App Review 可完整体验核心链路（地图 -> 点位 -> quickCard）。  
- [ ] 若存在受限功能，已在 Review Notes 提供复现路径/说明。  

### B. 元数据一致性（Guideline 2.3）

- [ ] App 名称/副标题/截图/预览与实际功能一致，不夸大。  
- [ ] “What’s New”准确描述本次实质变化。  
- [ ] 无与功能无关关键词堆砌。  
- [ ] 无“官方/认证/合作”等无法举证的误导性词汇。  
- [ ] App 名称、图标、文案不碰瓷第三方品牌/商标。  

### C. 软件要求（Guideline 2.5）

- [ ] 未使用私有 API（仅 public APIs）。  
- [ ] 未动态下载并执行改变功能的代码。  
- [ ] 若含 Web 浏览能力，使用合规 WebKit 路径。  
- [ ] 录音/摄像/屏幕记录行为（如有）具备明确用户同意与可见提示。  
- [ ] 无隐藏/休眠/未文档化功能；敏感能力入口必须可见、可说明。  
- [ ] 非显式手势（如多击/长按）不承载敏感动作，若存在需在 Review Notes 说明。  

### D. 商业与支付（Guideline 3.1.1）

- [ ] App 内数字内容/功能解锁（如未来订阅/会员）全部走 IAP。  
- [ ] 未在不适用地区放置绕过 IAP 的外链 CTA。  
- [ ] 若存在“外部购买链接资格”相关能力，已确认 entitlement 与地区限制。  
- [ ] 若当前版本无付费能力，App Store Connect 中无“已配置但 App 内不可达”的 IAP/订阅项。  
- [ ] 价格、周期、自动续费与取消路径在元数据与 App 内描述一致。  

### E. 最低功能与反垃圾（Guideline 4.2 / 4.3）

- [ ] App 不是纯营销页/链接集合/模板壳。  
- [ ] 核心价值可独立成立，不依赖外部 App 才能使用主功能。  
- [ ] 本版本有明确用户价值，不是空更新。  

### F. 隐私与权限（Guideline 5.1）

- [ ] App Store Connect 已填写隐私政策链接；App 内也可直达隐私政策。  
- [ ] 数据采集、用途、共享范围与隐私说明一致。  
- [ ] 权限弹窗文案与真实用途一致（尤其定位、通知）。  
- [ ] 仅在必要时请求权限，不提前/过度索取。  

### G. Privacy Manifest / SDK 合规

- [ ] `PrivacyInfo.xcprivacy`（如使用）结构有效、键值合法。  
- [ ] Required Reason APIs 的类别与 reason code 匹配。  
- [ ] 若使用苹果列管第三方 SDK，已满足 manifest + 签名要求。  

### H. Tsugie 专项（当前 MVP）

- [ ] 地图位置权限文案准确反映“附近へ推荐”用途。  
- [ ] 通知权限仅用于“开始前提醒”，且用户可拒绝后继续使用核心流程。  
- [ ] 无账号体系时，审核员不需要登录即可体验 MVP 主链路。  
- [ ] 收藏/打卡状态仅本地持久化，不产生未声明的数据上传行为。  

### I. 审核沟通物料

- [ ] Review Notes 提供：核心路径、测试点、若有特殊开关/数据则附说明。  
- [ ] 联系方式有效，Support URL 可访问。  
- [ ] 若存在区域性能力差异，已说明 storefront 范围。  

### J. 账号与运营合规（易漏项）

- [ ] App Store Connect 的能力配置与本次二进制一致（尤其 IAP/订阅/外链资格）。  
- [ ] 仅使用合规主体账号提审，不共享证书/企业签名，不使用马甲账号规避处罚。  
- [ ] 不诱导评分、不组织刷评，不以奖励换取好评。  
- [ ] 上线后的推送、宣传页、客服话术与实际功能一致，不承诺未上线能力。  
- [ ] 外链仅用于必要场景（隐私政策、地图导航、来源链接），不引导站外支付。  

---

## 3. 提交阻断条件（任一命中即停止提审）

- 核心链路崩溃或卡死。  
- 元数据与功能明显不一致。  
- 隐私政策缺失或权限用途不匹配。  
- 涉及数字内容付费但未使用 IAP（且不满足例外）。  
- Privacy Manifest 无效或 Required Reason APIs 声明错误。  
- App Store Connect 配置与 App 实际能力不一致（如配置订阅但 App 内不可达）。  
- 存在隐藏/休眠/未文档化敏感功能触发入口。  

---

## 4. 参考（苹果官方）

- App Review Guidelines  
  - https://developer.apple.com/app-store/review/guidelines/
- App Review 常见问题（2.1 高频）  
  - https://developer.apple.com/app-store/review/
- Privacy Manifest Files  
  - https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
- App Privacy Configuration  
  - https://developer.apple.com/documentation/bundleresources/app-privacy-configuration
- TN3181: Debugging an invalid privacy manifest  
  - https://developer.apple.com/documentation/technotes/tn3181-debugging-invalid-privacy-manifest
- Third-party SDK requirements  
  - https://developer.apple.com/support/third-party-SDK-requirements/

---

## 5. App Store Connect 提交话术模板（可直接使用）

### A. Review Notes（中文）

```
本版本核心说明：
1) Tsugie 当前版本为“单机本地优先”应用，核心推荐链路在设备端完成；
2) 不提供基于互联网的信息发布、复制、传播或互动服务；
3) 除用户主动点击“导航”跳转至 Apple 地图或 Google 地图，或主动打开活动来源链接外，不向第三方共享可识别个人信息；
4) 无账号体系，不接入第三方广告/统计/归因 SDK；
5) 当前版本为 App Store 付费下载（买断）模式，支付、兑换码与退款流程由 Apple 官方规则处理；
6) 定位权限仅用于附近推荐，通知权限仅用于开始前提醒；拒绝权限后仍可继续浏览核心功能（定位回退默认地点、通知提醒不可用）。

审核路径：
打开 App -> 地图首页 -> 点击任一点位 -> quickCard -> 详情页。
隐私政策：
App 内路径：侧栏「联系我们」->「查看隐私政策」
网页链接：https://www.shyr0.com/idea/tsugie/privacy
```

### B. Review Notes（English）

```
Release notes for App Review:
1) Tsugie (current version) is a local-first standalone app; core recommendation flows run on-device.
2) It does not provide internet-based information publishing, replication, dissemination, or interactive information services.
3) Except when a user intentionally launches navigation to Apple Maps or Google Maps, or opens event source links, no personally identifiable information is shared with third parties.
4) No account system and no third-party ad/analytics/attribution SDKs.
5) The current release is a paid-download (one-time purchase) app on the App Store; payment, promo-code redemption, and refund flows are handled under Apple's official rules.
6) Location permission is used only for nearby recommendations, and notification permission is used only for before-start reminders. If denied, core browsing remains available (location falls back to default area; reminders are unavailable).

Reviewer path:
Launch app -> map home -> tap any marker -> quick card -> detail page.
Privacy policy:
In-app path: Side drawer "Contact" -> "Privacy policy"
Web URL: https://www.shyr0.com/idea/tsugie/privacy
```

### C. Review Notes（日本語）

```
本バージョンの審査向け補足：
1) Tsugie（現行版）はローカル優先のスタンドアロンアプリで、主要な推薦処理は端末内で完結します。
2) インターネットを通じた情報の発信・複製・伝達・相互交流サービスは提供しません。
3) 利用者が自ら Apple マップ / Google マップへのナビ起動を行う場合、またはイベント情報ソースリンクを開く場合を除き、個人を識別できる情報を第三者へ共有しません。
4) アカウント機能はなく、第三者広告/解析/アトリビューション SDK は未導入です。
5) 現行版は App Store の有料ダウンロード（買い切り）方式であり、決済・Promo Code 交換・返金は Apple 公式ルールに従って処理されます。
6) 位置情報権限は近傍おすすめ表示のためのみ、通知権限は開始前リマインドのためのみ利用します。拒否時も閲覧の主要機能は利用可能です（位置は既定地点表示、通知は無効）。

審査動線：
アプリ起動 -> 地図ホーム -> 任意マーカーをタップ -> quickCard -> 詳細。
プライバシーポリシー：
アプリ内導線：サイドメニュー「ことばの便り」->「プライバシーポリシー」
Web URL：https://www.shyr0.com/idea/tsugie/privacy
```

### D. App Privacy（建议填写口径）

- `Tracking`: `No`
- `NSPrivacyCollectedDataTypes`: `None`（以当前代码和 manifest 为准）
- 判断前提：
  - App 不向自有服务端上传个人数据；
  - 无第三方广告/统计/归因 SDK；
  - 用户主动跳转外部地图服务后的数据处理由对应地图服务负责，不属于 App 内部持续收集行为。

### E. 上架前最后核对（2026-02-22 建议）

- [ ] `PrivacyInfo.xcprivacy` 已纳入版本控制并随构建产物打包。
- [ ] App Store Connect 的 `Privacy Policy URL` 与 App 内链接完全一致：`https://www.shyr0.com/idea/tsugie/privacy`
- [ ] Review Notes 使用上面模板之一，不再临时改写。
