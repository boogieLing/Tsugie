# Node 1:18 UI 优化执行单 v1

## 目标

1. 首屏地图全屏，不遮挡核心地图区域。  
2. 地图上直接显示附近可用「へ」点位（不限定花火）。  
3. 进入一段时间后自动弹出底部“最速攻略”卡片。  
4. 补充品牌 logo 与颜表情氛围元素。  

## 对应 schema

- `设计/figma-json-bridge/schema/ui-schema.node-1-18.map-first-fast-guide.v1.json`

## 状态帧

- `tsu-home-map-idle-v1`：默认全屏地图态
- `tsu-home-map-fast-guide-v1`：自动弹出“最速攻略”态

## 原型连线（在 Figma Prototype 手动设置）

1. `tsu-home-map-idle-v1` -> `tsu-home-map-fast-guide-v1`
- Trigger: `After delay`
- Delay: `1600ms`（可在 1200~2200ms 区间调）
- Animation: `Smart Animate`
- Duration: `260ms`
- Easing: `Ease Out`

2. 点位点击到快速查看
- `cmp-he-marker-*`（任意 marker） -> `tsu-home-map-fast-guide-v1`
- Trigger: `On tap`
- Animation: `Smart Animate`

## 验收点

- 首屏进入 0~1s 内无底卡遮挡地图。
- “へ”点位至少 4 个，命名不包含硬编码“花火大会”。
- 自动弹卡后标题明确为“最速攻略”。
- 顶栏和卡片内至少出现 2 个品牌/颜文字元素。
