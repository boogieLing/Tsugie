# Tsugi e 项目管理与协作规范

## 1. 项目开发目标（以 `需求/tsugihe_mvp_start_v0.1.md` 为准）

> 进入正式 iOS 开发阶段后，执行基线同时以 `需求/tsugie-ios-dev-handoff-v1.md` 为准。

### 1.1 产品定位
- 产品：つぎへ（Tsugi e）
- 目标：在当前时间与地点下，给用户一个“下一站值得去的へ”决策
- 原则：打开即用、无需登录、地图优先、决策优先、表达克制

### 1.2 MVP 目标
- 用最小可用功能验证核心价值
- 快速上线并收集真实反馈
- 严格控制范围，不追求复杂和完整

### 1.3 MVP 核心范围
- 首页地图：定位、附近「へ」标记、首屏全屏地图（默认不弹卡片）
- 今日推荐：今日优先、距离优先、规模优先，仅输出一个最速攻略へ
- 地图交互：标记点击“快速查看”半屏卡片、上滑进入详情
- 自动触发：进入一定时间后自动弹出“最速攻略”卡片
- 详情页：活动关键信息与导航入口
- 时间维度日历：右上角入口进入全屏“時めぐり”，按日展示最近且最快开始的 2 条并支持按天侧栏分类浏览
- 收藏与打卡联动：地图点位气泡可执行收藏/打卡，地点卡片统一输出状态 logo，收藏入口改为“右侧菜单 + 左侧收藏抽屉（含已打卡/未打卡筛选）”
- 时间筛选：Today / This Week
- 本地通知：开始前提醒（无需登录）

### 1.4 MVP 明确不做
- 账号/登录、社交/评论、复杂算法、摄影增强、路径优化、支付订阅、多语言

## 2. 项目目录组织方式（强制）

根目录固定按以下 5 个模块组织：

- `设计/`：产品与交互设计资产
- `ios开发/`：iOS 客户端代码（Swift/SwiftUI）与测试
- `数据端/`：数据处理、接口、推荐排序相关实现
- `需求/`：需求文档、版本需求说明
- `记录/`：过程记录、决策记录、变更记录，历史材料放 `记录/归档/`

当前建议子结构：

- `设计/figma/`：Figma 导出或链接说明
- `设计/原型/`：原型代码（HTML/CSS/交互稿）
- `设计/文档/`：设计检查清单、设计说明
- `记录/归档/`：已结项或废弃方案归档

新增文件时必须归档到以上模块，不再使用 `src/`、`docs/`、`demand/` 这类旧结构。

## 3. 工作流程（需求 -> 设计 -> 开发 -> 记录）

1. 需求阶段：
- 先更新 `需求/` 中对应版本文档，再开始实现。

2. 设计阶段：
- 设计稿、线框图、交互说明统一进入 `设计/`。
- 影响开发的设计结论必须可追溯。

3. 开发阶段：
- iOS 代码只放 `ios开发/`。
- 数据相关实现只放 `数据端/`。
- 接口/字段/排序规则变更必须同步更新需求或记录。
- 正式 iOS 开发前，必须先对齐 `需求/tsugie-ios-dev-handoff-v1.md` 的页面语义、组件语义、交互状态机与关联逻辑。

4. 联调与验收阶段：
- 以 MVP 范围为边界，不扩功能。
- 验收以“可用且可验证”优先。

5. 记录与归档阶段：
- 关键决策、里程碑、风险与结论写入 `记录/`。
- 完成阶段性任务后，将历史材料移入 `记录/归档/`。

## 4. 大变动同步更新机制（必须执行）

出现以下任一情况，必须在同一次工作中同步更新 `AGENTS.md` 与 `记录/项目变更记录.md`：

- MVP 范围变更（新增/删除功能）
- 目录结构调整
- 推荐逻辑或关键业务规则变化
- 技术栈或端到端流程变化
- 里程碑计划变化（如 8 周节奏调整）

更新要求：
- 写清“变更内容、原因、影响范围、执行时间”。
- 若变更影响需求，必须同步更新 `需求/` 下对应文档版本。

## 5. 协作与命名规范

- 根目录使用上述固定中文模块名。
- 模块内新增目录建议使用 `kebab-case`。
- 测试文件与实现文件保持一一映射。
- 提交信息建议使用 Conventional Commits（如 `feat:`、`fix:`、`docs:`）。

## 6. 当前里程碑基线（8 周）

- Week 1: 初始化、定位与地图基础
- Week 2: 地图标记与 Mock 数据
- Week 3: 推荐排序与推荐卡片
- Week 4: 详情页与导航跳转
- Week 5: 时间筛选与本地通知
- Week 6: Bug 修复与性能优化
- Week 7: TestFlight 内测
- Week 8: 上架准备与提审

## 7. Figma 自动化基线（新增）

- 新增独立项目：`设计/figma-json-bridge/`
- 目标流程：`Codex -> ui-schema.json -> Figma Plugin -> 自动创建/更新节点`
- 适用范围：Figma 侧结构化批量改稿，不直接替代产品需求评审与交互验收
- 产物要求：
  - schema 版本化（当前 `version: 1.0`）
  - 节点 `id` 全局唯一，支持幂等更新
  - 大改稿优先使用 `校验 -> 应用` 两步流程
  - 节点覆盖按“能更新尽量更新”原则扩展（不限于 Frame/AutoLayout/Text/Button）

## 8. Figma JSON Bridge 研发流程（强制）

- 研发流程文档：`记录/figma-json-bridge研发接入SOP.md`
- UI 研发节奏文档：`记录/ui-html-first-figma-batch-sop.md`
- 适用范围：涉及 Figma 结构化改稿的需求与交互调整
- 执行要求：
  - 默认先在 `设计/原型/` 完成 HTML 迭代，封板后再一次性落 Figma
  - 先明确需求目标，再生成 schema
  - schema 先本地校验，再插件应用
  - 支持 `color-system` 模式：可对当前页面或当前文件全部页面的托管节点执行批量主题上色
  - 小改默认不启用 prune；全量重建可启用 prune
  - 完成后必须更新 `记录/项目变更记录.md`
- 交付门禁：
  - schema 校验通过
  - 插件应用成功
  - 视觉与交互验收通过

## 9. へ抽象与设计资产治理（强制）

- `へ` 为统一业务实体，花火大会仅是首个垂类，不得在通用组件命名中硬编码。
- 普通模式颜色管理统一使用：`设计/figma-json-bridge/schema/color-system.tsugie-he.v2.fresh.json`
- 元素/组件语义命名统一使用：`设计/文档/figma-语义命名与へ抽象规范-v1.md`
- UI 展示名称使用地点真实名称，不使用“xxxへ”后缀（`へ` 仅作为语义层概念）。
- 胶囊类高亮（chip/pill/tag/segmented-active）统一强制规则：`无边框 + 渐变发光背景 + 朦胧立体感`，发光颜色必须跟随当前配色方案，不允许使用固定色或纯描边高亮。
- 收藏语义固定为“想要访问”，打卡语义固定为“已经访问”；所有地点卡片中的两种状态统一使用 logo，不使用状态文字。
- Node `1:18` 优化执行参考：`设计/文档/node-1-18-ui优化执行单-v1.md`
- Node `2:29` 优化执行参考：`设计/文档/node-2-29-ui优化执行单-v1.md`

## 10. iOS 开发阶段基线（强制）

- iOS 研发统一入口文档：`需求/tsugie-ios-dev-handoff-v1.md`
- iOS 阶段必须遵循以下强约束：
  - 地图页与日历页语义独立：地图是位置维度，日历是时间维度。
  - 时间状态计算同源：所有卡片/列表场景统一使用同一状态模型（`upcoming / ongoing / ended / unknown`）。
  - 进度条语义同源：详情、quick、nearby、日历抽屉、收藏抽屉保持一致规则。
  - 收藏/打卡语义固定：收藏=想访问，打卡=已访问，统一 logo 表达，不用状态文字。
  - 打卡时间门禁固定：`upcoming`（未到开始时间）活动不允许打卡，统一显示“顶部中间下落提示气泡”并自动销毁。
  - 胶囊高亮统一：无边框 + 渐变发光 + 朦胧立体感，并跟随当前主题。
  - UI 复刻强制 1:1：以“已封板原型 + CSS”为唯一视觉基线，结构层级、尺寸间距、颜色、文案顺序、状态显隐、动效节奏必须对齐；除缺陷修复外不得擅自改视觉语义。
  - MVP 不扩边界：不引入账号/社交/支付/复杂算法等非 MVP 能力。
- iOS 开发交付顺序建议（默认）：
  1. 地图主页骨架（点位 + quickCard 基础链路）
  2. 详情页与手势闭环
  3. 日历独立页与日历日抽屉
  4. 收藏/打卡联动与收藏抽屉
  5. 主题调节、本地通知与稳定性回归

## 11. iOS 研发统一三段流程（强制）

- 从正式 iOS 开发阶段起，单次迭代默认按以下三段执行，不跳段：
  1. 研发实现
  2. UI 优化
  3. 安全/提审审查
- 阶段启动门禁（新增，强制）：
  - 每个阶段开始前，必须先主动检索“当前阶段可用 skill”，完成选型后再执行阶段任务。
  - 默认使用本地 skill 扫描脚本：
    - `python3 /Users/r0/.codex/skills/local-skill-finder/scripts/list_local_skills.py --query ios swiftui`
    - `python3 /Users/r0/.codex/skills/local-skill-finder/scripts/list_local_skills.py --query design ui animation`
    - `python3 /Users/r0/.codex/skills/local-skill-finder/scripts/list_local_skills.py --query review security privacy`
  - 若本地无匹配，再检索可安装 skill，并在记录中注明“新增原因与适用阶段”。

### 11.1 第一段：研发实现

- 目标：先保证功能链路可运行、可验证。
- 要求：
  - 进入本段前先完成 skill 预检，优先选择实现与工程质量相关 skill。
  - 严格遵守 MVP 边界，不在实现阶段扩功能。
  - 地图/日历、收藏/打卡、时间状态同源等语义不得被破坏。
  - 研发实现必须落在 `ios开发/`。

### 11.2 第二段：UI 优化

- 目标：提升视觉层级、交互反馈与可读性，不改业务语义。
- 要求：
  - 进入本段前先完成 skill 预检，优先选择 UI/动效/可访问性相关 skill。
  - UI 验收必须逐项对照原型 CSS，按 1:1 复刻标准执行，不做主观“再设计”。
  - 优化顺序：结构 -> 样式 -> 交互 -> 动效。
  - 必做可访问性检查（字体缩放、点击热区、VoiceOver 基础语义）。
  - 参考执行流程：`记录/tsugie-ios-ui美化技能编排流程-v1.md`。

### 11.3 第三段：安全/提审审查

- 目标：在提测/提审前完成质量与合规门禁。
- 要求：
  - 进入本段前先完成 skill 预检，优先选择 review/安全/合规相关 skill。
  - 先做代码审查与风险收敛，再进入提审准备。
  - 必跑 App Store 高压线预检（完整性、隐私、权限、元数据一致性）。
  - 使用清单：`ios开发/tsugie/tsugie/APP_STORE_PRECHECK.md`。

### 11.4 iOS 测试执行并发规范（强制）

- 目标：避免 xcode test 自动拉起多 Clone 模拟器造成资源抖动与调试噪音。
- 要求：
  - 本地默认使用“单模拟器、禁并行 clone”执行 iOS 测试。
  - `xcodebuild test` 必须显式带以下参数：
    - `-parallel-testing-enabled NO`
    - `-maximum-concurrent-test-simulator-destinations 1`
  - 非用户明确要求，不得使用并行测试配置（包括多个 simulator destination 或默认并行 clone）。

## 12. 数据端子项目落位（新增）

- 新增祭典抓取独立目录：`数据端/OMATSURI/`（与 `数据端/HANABI/` 同级）。
- 祭典（お祭り）相关的站点清单、抓取配置、字段融合与后续实现，统一放在 `数据端/OMATSURI/`。
- 花火（HANABI）与祭典（OMATSURI）保持目录与代码解耦，避免在同一子项目内混放不同垂类逻辑。
- 数据端统一运维脚本入口固定为：`数据端/scripts/`（如 `start_ops_console.sh`、`ops_console.sh`）；`HANABI/` 与 `OMATSURI/` 内仅保留兼容转发入口，不再作为主入口维护。

## 13. iOS 内置数据包接入基线（新增）

- 数据到 iOS 的默认接入流程固定为：
  1. 数据端运行完成并更新 `数据端/HANABI/data/latest_run.json` 与 `数据端/OMATSURI/data/latest_run.json`
  2. 执行统一维护脚本：`bash 数据端/scripts/update_ios_payload.sh --pretty`
  3. 产物写入：
     - `ios开发/tsugie/tsugie/Resources/he_places.index.json`（空间索引）
     - `ios开发/tsugie/tsugie/Resources/he_places.payload.bin`（二进制分片 payload）
     - `ios开发/tsugie/tsugie/Resources/he_images.payload.bin`（活动单图二进制 payload）
  4. iOS 端通过 `ios开发/tsugie/tsugie/Infrastructure/EncodedHePlaceRepository.swift` 读取索引并按 `offset/length` 随机读取附近 bucket 的 payload；通过 `ios开发/tsugie/tsugie/Infrastructure/HePlaceImageRepository.swift` 按活动图片偏移按需解码单图；启动按当前位置实时检索附近 Geohash 桶并解码

- 数据包编解码基线（强制）：
  - 无损压缩：`zlib`
  - 混淆：`xor_sha256_stream_v1`
  - 帧编码：`binary_frame_v1`（索引记录分片偏移，payload 以二进制存储；活动数据与图片 payload 一致）
  - 解码顺序必须与编码顺序完全逆向一致（`按 offset/length 读取二进制分片 -> 去混淆 -> zlib 解压 -> JSON decode/图片二进制`）

- 维护要求：
  - 编解码算法、密钥策略、资源路径、脚本入口任一变化，必须在同一次工作中同步更新 `AGENTS.md` 与 `记录/项目变更记录.md`。
  - iOS 默认数据源优先读取资源包；仅在资源缺失或解码失败时允许回退 Mock 数据。
  - 开发阶段可用天空树（`35.7101, 139.8107`）作为定位桩点；正式场景必须接入动态定位后实时检索。

## 14. 数据端坐标脏数据修复基线（新增）

- 每次抓取后的融合（`fuse_records`）必须自动执行“重叠坐标脏数据联网重查”二次流程，不允许仅做一次性人工修补。
- 二次流程最小要求：
  - 先分组识别同坐标重叠记录（经纬度按 `6` 位小数聚类）。
  - 仅对低置信度来源组执行重查（`network_geocode*`、`pref_center_fallback`、`missing`）。
  - 对组内每条记录基于 `prefecture/city/venue_name/venue_address/event_name` 组合查询逐条重查。
  - 命中后仅在“新坐标与原坐标不同”时覆盖写回，避免无效抖动。
- 字段与日志规范（强制）：
  - 覆盖后的 `geo_source` 必须标识重查来源（例如 `network_geocode_overlap_repair*`）。
  - 每个 run 必须产出独立重查日志（例如 `geo_overlap_repair_log.csv`），包含：原坐标、查询策略、查询词、缓存命中、返回坐标、错误信息。
- 导出门禁（强制）：
  - iOS 资源包导出前必须先通过 `数据端/scripts/geo_overlap_quality_gate.py`。
  - 默认统一入口：`bash 数据端/scripts/update_ios_payload.sh --pretty`（脚本内已内置门禁，失败即阻断导出）。
- 交付约束：
  - 该流程属于数据质量基线，不得依赖 iOS 端渲染过滤兜底替代。

## 15. 推荐算法数据对齐基线（新增）

- 推荐算法文档基线：`需求/Tsugie_Recommendation_Algorithm_V1.docx`（原始）+ `需求/Tsugie_Recommendation_Algorithm_V1_数据对齐修订.md`（字段落地）（2026-02-19）。
- iOS 推荐逻辑在“数据字段定义、时间解析回退、过滤规则、评分权重”四部分，默认以以上两份文档共同约束为准。
- 评分权重默认回调为 V1：`0.45 * SpaceScore + 0.45 * TimeScore + 0.10 * HeatScore`；类别权重默认：`hanabi=1.2`、`matsuri=1.0`、`nature=0.8`、`other=1.0`。
- `upcoming` 的 `TimeScore` 在 `<24h` 保持阶梯规则，`>24h` 必须按 `delta_start` 连续衰减，禁止固定常数，避免“微小距离差”压过“显著时间差”。
- 在数据覆盖率未达标前，`expected_visitors` 与 `launch_scale` 不得作为主排序强依赖；优先使用 `distance/时间状态/scale_score/heat_score`。
- nearby 轮播推荐粗排阶段必须过滤 `ended` 活动，不允许过期活动进入轮播候选池。
- nearby 轮播推荐精排阶段必须保证“已知时刻优先”：`unknown` 不得排在 `ongoing/upcoming` 之前（仅在没有已知时刻候选时可上浮）。
- nearby 轮播推荐当前阶段默认优先 `hanabi`（花火大会），并通过类别权重与同分排序共同保证优先级。
- nearby 重排触发策略固定为：仅用户手势移动结束后触发；地图移动过程中不得连续触发推荐重排。
- marker 点击/quickCard 聚焦/定位重置等程序化相机变化，不得触发 nearby 重排。
- 若推荐逻辑规则发生变化（字段、权重、过滤、排序优先级），必须在同一次工作中同步更新：
  - `需求/tsugie-ios-dev-handoff-v1.md`
  - `记录/项目变更记录.md`
  - `AGENTS.md`

## 16. 数据端活动内容抓取与润色基线（新增）

- 每个活动的“图片 + 活动介绍”增强链路默认使用统一脚本：`数据端/scripts/enrich_event_content.py`。
- 链路定位为“低频长跑”任务，默认低 QPS、允许长时间运行，避免高频重复抓取。
- 默认时间过滤规则：仅按 `event_date_start` 判断，`start_date < (today - 31d)` 的历史活动跳过；其余（未开始与已过期 31 天内）继续处理。
- 默认重跑策略：`failed-only`（仅处理失败/未处理），历史成功记录直接复用，减少重复请求与模型调用。
- 默认处理优先级：按 `event_date_start` 近期开场优先（未开始优先、其次为已过期 31 天内），并优先处理“仍需请求”的记录。
- 默认低 token 策略：`codex_model=auto` 启动时先探测可用模型（在独立临时目录探测，避免仓库上下文额外 token），按候选顺序优先使用轻量模型（默认 `gpt-5-mini,gpt-4.1-mini,gpt-4o-mini,o4-mini,o3-mini,gpt-5`）；若轻量模型不可用则自动回退 `gpt-5`。可用 `CODEX_MODEL_CANDIDATES` 覆盖候选顺序；并要求日/中/英介绍与一句话在单次模型调用内返回（不走二次翻译补调），`codex_timeout_sec` 默认按 `120s` 运行。
- 抓取收尾串接基线（新增）：
  - `hanabi_crawler/cli.py`、`omatsuri_crawler/cli.py` 的全量抓取在 `fuse` 完成后默认自动触发内容增强（可用 `--no-content-enrich` 临时关闭）。
  - `HANABI/scripts/refresh_incomplete_events.py`、`OMATSURI/scripts/refresh_incomplete_events.py` 的高频补充在 `fuse` 完成后默认自动触发内容增强（可用 `--no-content-enrich` 临时关闭）。
  - 默认内容增强参数基线：低 QPS、`max_images=1`、回写 `latest_run.json` 的 `content_run_id`。
- iOS 接入收尾基线（新增）：
  - 统一数据管理系统 `POST /api/run/full` 与 `POST /api/run/highfreq` 在任务成功后默认自动执行 `bash 数据端/scripts/update_ios_payload.sh --pretty`，将最新内容同步到 iOS 资源包。
  - 统一数据管理系统新增 `POST /api/run/content_regen`：用于“内容增强历史重跑”任务纳管（支持 `only_past_days` 等过滤），任务进度与日志统一纳入 `/api/jobs` 与 `/api/job_log` 监控。
  - 若自动导出失败，任务状态必须标记为失败并在 job 日志中输出失败原因。
- 默认输入基于两个子项目最新融合批次：
  - `数据端/HANABI/data/latest_run.json` 的 `fused_run_id`
  - `数据端/OMATSURI/data/latest_run.json` 的 `fused_run_id`
- 提示词模板固定本地化管理（可直接改文档，不改代码）：
  - `数据端/文档/event-description-polish.prompt.md`（多段正文润色）
  - `数据端/文档/event-one-liner.prompt.md`（一句话简述）
- 文本润色模式基线：
  - `--polish-mode auto|openai|codex|none`（默认 `auto`）
  - `openai` 模式支持 OpenAI Responses 与 OpenAI 兼容 Chat Completions 两种端点（通过 `OPENAI_BASE_URL` 切换），可接入 Kimi/DeepSeek 等兼容供应商。
  - `openai` 模式支持“介绍与一句话分模型/分端点”：
    - 介绍默认使用 `OPENAI_MODEL/OPENAI_BASE_URL/OPENAI_API_KEY`
    - 一句话可选覆盖 `OPENAI_ONE_LINER_MODEL/OPENAI_ONE_LINER_BASE_URL/OPENAI_ONE_LINER_API_KEY`
    - 中英补全翻译可选覆盖 `OPENAI_TRANSLATION_MODEL/OPENAI_TRANSLATION_BASE_URL/OPENAI_TRANSLATION_API_KEY`
  - `codex` 模式允许本地逐条生成（通过本机 Codex CLI），用于无 OpenAI API key 场景的一次性批处理。
  - 历史活动回刷支持：`--only-past-days N` 仅处理 `event_date_start < (today - N)` 的活动，适合脏数据清洗重跑。
- 抓取质量基线（新增）：
  - 对 `text/html` 且未声明 charset 的页面，必须执行编码探测（含 `Shift_JIS/CP932`）后再解析，避免日文乱码落盘。
  - 对 `omatsuri.com/sch/*.html#...` 月历锚点页，必须优先抽取“活动行级文本”；若仅能命中页面通用头图/OGP 图（如 `header.jpg`），则该活动视为无图，不写入通用图占位。
  - 对已识别脏图指纹 `banner1_069a0e3420`（含 `01_banner1_069a0e3420.jpg` 及哈希后缀变体）必须统一视为无图，不得写入内容结果与 iOS 资源包。
- 输出基线：
  - `数据端/HANABI/data/content/<run_id>/`、`数据端/OMATSURI/data/content/<run_id>/`
  - 必须产出 `events_content.jsonl`、`events_content.csv`、`content_enrich_log.csv`、`content_summary.json`
  - 可选图片本地落盘目录：`data/content_assets/<run_id>/`
- 运行后允许回写 `latest_run.json` 的内容增强指针（如 `content_run_id`、`content_summary` 等），用于后续导出与运营追溯。
- 维护要求（强制）：
  - 若内容抓取脚本入口、提示词路径、润色策略（模型/开关）、输出结构发生变化，必须在同一次工作中同步更新 `AGENTS.md` 与 `记录/项目变更记录.md`。

## 17. 数据端管理系统监控与质量分析基线（新增）

- 统一管理系统默认入口：`数据端/scripts/ops_console.sh`（后端实现：`数据端/HANABI/scripts/data_ops_console.py`）。
- 管理系统必须覆盖两类能力：
  1. 抓取进度监控：任务列表、阶段状态、进度百分比、日志查看。
  2. 数据质量分析：按项目输出可追溯缺口清单与计数。
- 质量分析最小口径（强制）：
  - 未抓取：`failed_urls.csv` + `refresh_incomplete_log.csv` 失败项汇总。
  - 开始时间未确定：`event_date_start/event_time_start` 任一缺失即计入“待后续继续抓”。
  - 无图片：活动内容条目缺失或条目内无图片，均计入缺口。
  - 无介绍：活动内容条目缺失或 `polished_description` 为空，均计入缺口。
  - 无一句话：活动内容条目缺失或 `one_liner` 为空，均计入缺口。
- 运行批次对齐规则（强制）：
  - 总览与质量分析默认优先以 `data/latest_run.json` 的 `fused_run_id/content_run_id` 为同一批次基线，避免 `latest` 软链接漂移导致口径不一致。
- UI 风格要求：
  - 管理系统页面默认对齐 macOS 视觉风格（窗口标题栏、玻璃拟态、轻量卡片层级），但不改变既有运维入口与 API 路径。
- 维护要求（强制）：
  - 若管理系统 API 结构、质量口径定义、任务进度推断规则、页面入口发生变化，必须在同一次工作中同步更新 `AGENTS.md` 与 `记录/项目变更记录.md`。
