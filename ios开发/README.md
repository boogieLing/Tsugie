# iOS 开发

本目录用于 Swift/SwiftUI 客户端实现与测试。

## 当前实现入口

- 第一阶段骨架（地图首页 + 点位 + quickCard 基础链路）：
  - `ios开发/tsugie/tsugie/`

## 数据接入（HANABI + OMATSURI）

- iOS 内置数据资源：
  - `ios开发/tsugie/tsugie/Resources/he_places.index.json`（空间索引）
  - `ios开发/tsugie/tsugie/Resources/he_places.payload.bin`（二进制分片 payload）
- 维护入口脚本：`数据端/scripts/update_ios_payload.sh`
- 底层导出脚本：`数据端/scripts/export_ios_seed.py`
- 推荐更新命令：

```bash
bash 数据端/scripts/update_ios_payload.sh --pretty
```

- App 侧默认加载链路：
  - `Infrastructure/EncodedHePlaceRepository.swift` 解包（按 offset/length 读取二进制分片 -> 去混淆 -> zlib 解压 -> JSON 解码）
  - 启动时按当前位置实时计算附近 Geohash 桶，仅读取并解码附近桶（不全量解码）
  - `HomeMapViewModel` 默认优先使用资源包数据；资源缺失或解码失败时回退到 `MockHePlaceRepository`

## 技术方案与内存优化

- 完整技术文档：`记录/tsugie-ios-全量内置实时附近检索技术方案-v1.md`
- 当前内存画像（天空树 + 30km，数据链路）：
  - 命中 bucket：`75`
  - 读取 payload 分片：约 `179KB`
  - 解码记录：`746` 条
  - 解压后 JSON：约 `1.07MB`
  - 启动阶段内存峰值估算：约 `8MB ~ 20MB`（不含地图渲染）

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
