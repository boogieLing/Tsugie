# Node 2:29 UI 优化执行单 v1

## 1. 目标

1. 首屏进入即全屏地图，不默认弹出底卡。
2. 地图默认使用清新渐变，并补齐示例地图元素（道路/水域/区域层）。
3. 点位样式升级为更可读的 marker 结构（halo + core + label）。
4. 点位展示名使用地点真实名称，不使用“xxxへ”后缀。
5. 进入一定时间后自动弹出“最速攻略”底部卡片，该卡片定义为“快速查看（非详情）”。

## 2. 对应产物

- Figma 参考：`设计/figma/node-2-29-reference.md`
- Schema：`设计/figma-json-bridge/schema/ui-schema.node-2-29.map-first-fresh-gradient.v1.json`
- 配色：`设计/figma-json-bridge/schema/color-system.tsugie-he.v2.fresh.json`

## 3. 插件执行步骤

1. 在 Figma 打开 Tsugie 文件并切到目标 page。
2. 打开插件 `Tsugie UI Schema Bridge`。
3. 点击 `导入本地 JSON`，选择 `ui-schema.node-2-29.map-first-fresh-gradient.v1.json`。
4. 点击 `校验`，结果应为通过。
5. 点击 `应用到 Figma`，如需全量覆盖可开启 prune。

## 4. Prototype 设置

1. `tsu-home-map-idle-node-2-29-v1` 作为首帧。
2. 设置延时跳转（如 1.5s~2.5s）到 `tsu-home-map-fast-guide-node-2-29-v1`。
3. 该自动跳转表示“进入一定时间后自动弹出最速攻略”。

## 5. 验收项

1. 首帧可见完整地图，底部无卡片遮挡。
2. 地图存在示例底图层（非纯色底）。
3. 点位样式具备渐变+发光+标签，视觉区分明显。
4. 点位文本为真实地点名（例如：隅田川花火大会、浅草サンバ祭、目黒川さくら並木、神宮外苑いちょう並木）。
5. 快速查看卡片文案明确“非详情”，CTA 保持可点击语义。
