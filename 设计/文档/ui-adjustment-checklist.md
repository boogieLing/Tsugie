# Tsugie UI 调整清单

## 当前基线
- 线框来源：`设计/figma/tsugihe_main_screen_wireframe.svg`
- Figma 对齐节点：`设计/figma/node-1-2-reference.md`
- 节点改稿方案：`设计/文档/node-1-2-figma-adjustment-v2.md`
- 节点改稿方案（地图优先版）：`设计/文档/node-1-18-ui优化执行单-v1.md`
- 节点改稿方案（清新渐变版）：`设计/文档/node-2-29-ui优化执行单-v1.md`
- 语义命名与へ抽象：`设计/文档/figma-语义命名与へ抽象规范-v1.md`
- Figma 自动化工具：`设计/figma-json-bridge/README.md`
- 节点参考（2:29）：`设计/figma/node-2-29-reference.md`
- 可调页面：`设计/原型/main-screen.html`
- 样式变量：`设计/原型/main-screen.css`

## 快速调整入口
- 主色：`--brand-blue`
- 页面背景：`--bg-base`
- 顶栏背景：`--bg-topbar`
- 卡片背景：`--bg-card`
- 圆角：`--card-radius`、`--inner-radius`
- 屏幕尺寸：`--screen-width`、`--screen-height`

## 下一步（接入 Figma）
1. 锁定下一个节点（例如详情页卡片）并补充到 `设计/figma/`。
2. 用 MCP 拉取 `get_design_context` + `get_screenshot`。
3. 在 Figma 内完成视觉调整并更新节点说明。
4. 输出仅包含 Figma 侧改动清单与验收项。
