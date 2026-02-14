# Tsugie App Store Precheck

最后更新：2026-02-14  
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

### C. 软件要求（Guideline 2.5）

- [ ] 未使用私有 API（仅 public APIs）。  
- [ ] 未动态下载并执行改变功能的代码。  
- [ ] 若含 Web 浏览能力，使用合规 WebKit 路径。  
- [ ] 录音/摄像/屏幕记录行为（如有）具备明确用户同意与可见提示。  

### D. 商业与支付（Guideline 3.1.1）

- [ ] App 内数字内容/功能解锁（如未来订阅/会员）全部走 IAP。  
- [ ] 未在不适用地区放置绕过 IAP 的外链 CTA。  
- [ ] 若存在“外部购买链接资格”相关能力，已确认 entitlement 与地区限制。  

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

---

## 3. 提交阻断条件（任一命中即停止提审）

- 核心链路崩溃或卡死。  
- 元数据与功能明显不一致。  
- 隐私政策缺失或权限用途不匹配。  
- 涉及数字内容付费但未使用 IAP（且不满足例外）。  
- Privacy Manifest 无效或 Required Reason APIs 声明错误。  

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
