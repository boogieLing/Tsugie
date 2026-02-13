# Figma JSON Bridge（独立子项目说明）

本目录是 Tsugie 的 Figma 自动化桥接层，实现：

`Codex -> ui-schema.json -> Figma Plugin -> 自动创建/更新 Figma 节点`

目标是把“口头改稿”变成“结构化可重复执行”的流程。

## 1. 目录结构

- `plugin/manifest.json`：Figma 插件清单
- `plugin/code.js`：插件执行引擎（解析 schema、幂等同步）
- `plugin/ui.html`：插件面板（粘贴 JSON、校验、应用、prune）
- `schema/ui-schema.v1.schema.json`：JSON Schema 规范
- `schema/ui-schema.example.node-1-2.json`：可直接演示的示例
- `prompts/codex-ui-schema-prompt.md`：让 Codex 产出 schema 的提示模板
- `scripts/validate-ui-schema.js`：本地结构校验脚本
- `package.json`：本目录脚本入口

## 2. 快速开始（5 分钟）

1. 导入插件
- 打开 Figma Desktop
- 进入 `Plugins` -> `Development` -> `Import plugin from manifest...`
- 选择：`设计/figma-json-bridge/plugin/manifest.json`

2. 跑通示例
- 运行插件：`Tsugie UI Schema Bridge`
- 点击 `加载示例`
- 点击 `校验`
- 点击 `应用到 Figma`

3. 使用 Codex 产出 schema
- 参考：`prompts/codex-ui-schema-prompt.md`
- 将输出 JSON 粘贴到插件面板
- 按 `校验 -> 应用到 Figma` 执行

## 3. 核心机制

### 3.1 幂等更新
- 每个节点靠 `id` 唯一识别
- 同一 `id` 多次应用会更新同一节点，不会重复创建

### 3.2 托管清理（Prune）
- 勾选 `删除 schema 中不存在的托管节点`
- 会删除“由本插件管理”且这次 schema 未声明的节点

### 3.3 顶层入口
- 可使用 `frames`（推荐）
- 或使用 `nodes`（兼容）

## 4. 支持能力（v1.1）

### 4.1 节点类型
- `FRAME`
- `GROUP`
- `COMPONENT`
- `SECTION`
- `RECTANGLE`
- `ELLIPSE`
- `LINE`
- `POLYGON`
- `STAR`
- `VECTOR`
- `TEXT`
- `SLICE`
- `INSTANCE`（需要 `componentId` 或 `componentKey`）
- `BUTTON`（语义快捷类型，自动生成 label 子节点）

### 4.2 可更新属性
- 几何：`position`、`size`、`rotation`
- 显示：`visible`、`locked`、`opacity`、`blendMode`
- 视觉：`fills`、`strokes`、`effects`、圆角、描边参数
- 布局：`constraints`、`layout`（Auto Layout）、`layoutSelf`
- 文本：`characters`、字体、字号、行高、字间距、对齐、自动尺寸
- 图片填充：`imageHash`、`imageUrl`、`imageBytesBase64`

## 5. Schema 最小示例

```json
{
  "version": "1.0",
  "frames": [
    {
      "id": "demo-root",
      "name": "demo-root",
      "type": "FRAME",
      "position": { "x": 0, "y": 0 },
      "size": { "width": 390, "height": 844 },
      "fills": ["#0F1115"],
      "children": []
    }
  ]
}
```

## 6. 本地校验命令

```bash
node 设计/figma-json-bridge/scripts/validate-ui-schema.js \
  设计/figma-json-bridge/schema/ui-schema.example.node-1-2.json
```

或在本目录执行：

```bash
npm run validate:example
```

## 7. 常见问题

### Q1: 为什么有些节点没有按预期被替换？
- 如果目标节点不是插件托管节点，且类型不匹配，插件会保留原节点并给出 warning。

### Q2: INSTANCE 创建失败怎么办？
- 确保 schema 中提供 `componentId` 或 `componentKey`。
- 组件必须在当前文件可访问，或 key 可被导入。

### Q3: 图片填充失败怎么办？
- 检查 `imageUrl` 可访问性，或直接提供 `imageBytesBase64` / `imageHash`。

## 8. 当前限制

- Prototype 连线还未自动写入
- Component Set / Variant 编排还未自动化
- 复杂矢量路径（vector network）暂不做 schema 层全面描述

## 9. 推荐工作流

1. 先在 Figma 明确要改的节点范围与命名
2. 用 Codex 产出 schema（带稳定 id）
3. 在插件先 `校验` 再 `应用`
4. 大改时开启 prune，小改时关闭 prune
5. 调整后把 schema 归档到 `schema/` 便于复用
