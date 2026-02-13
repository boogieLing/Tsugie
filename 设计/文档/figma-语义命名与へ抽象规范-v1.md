# Figma 语义命名与「へ」抽象规范 v1

## 1. 目标

- 统一元素命名、组件命名、状态命名。
- 将“花火大会”从业务实体中抽象为通用「へ」。
- 为未来扩展到更多地点类型预留清晰分类结构。

## 2. 核心抽象

- `へ`：可前往地点（Place Entity），是统一业务对象。
- `へType`：地点类型（如 `hanabi`、`music`、`night-view`、`food`、`onsen`）。
- `へ` 是平台通用概念，`hanabi` 仅是初始垂类，不应在通用组件命名中硬编码。
- `へ` 只用于语义层与数据层，不强制进入 UI 展示名称。

## 3. 命名规则

### 3.1 Frame 命名
- 格式：`tsu-{screen}-{state}-{version}`
- 示例：
  - `tsu-home-map-idle-v1`
  - `tsu-home-map-fast-guide-v1`

### 3.2 组件命名
- 格式：`cmp-{domain}-{role}`
- 示例：
  - `cmp-he-marker`
  - `cmp-fast-guide-card`
  - `cmp-brand-badge`

### 3.3 元素命名
- 格式：`elm-{area}-{semantic}`
- 示例：
  - `elm-map-he-label-01`
  - `elm-top-logo-primary`
  - `elm-fast-guide-cta`

## 4. 状态语义

- `idle`：地图全屏，无底卡
- `fast-guide`：显示“最速攻略”卡片
- `detail`：详情态（非本次 schema 主态）

## 5. 「花火大会」语义下沉策略

- 通用层仅使用 `へ` / `he` 命名。
- 垂类信息进入数据字段，不进入组件主命名：
  - `heType: hanabi`
  - `heTheme: summer-firework`
- UI 展示名称直接使用地点真实名称（如活动名、祭典名、樱花地点名），不使用“xxxへ”后缀。
- UI 文案可显示“花火大会”，但组件命名不得绑定“花火”。

## 6. 颜色与命名联动

- 颜色体系源：`设计/figma-json-bridge/schema/color-system.tsugie-he.v1.json`
- marker 命名建议带颜色组后缀：
  - `cmp-he-marker-blue`
  - `cmp-he-marker-rose`
