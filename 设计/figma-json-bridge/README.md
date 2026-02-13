# Figma JSON Bridge（独立项目）

这个子项目用于实现你提出的流程：

`Codex -> ui-schema.json -> Figma Plugin -> 自动创建/更新 UI 节点`

## 目录

- `plugin/manifest.json`：Figma 插件清单
- `plugin/code.js`：插件主逻辑（解析 schema、创建/更新节点）
- `plugin/ui.html`：插件 UI（粘贴 JSON、校验、应用）
- `schema/ui-schema.v1.schema.json`：schema 规范定义
- `schema/ui-schema.example.node-1-2.json`：Node `1:2` 示例 schema
- `prompts/codex-ui-schema-prompt.md`：给 Codex 的生成提示词模板
- `scripts/validate-ui-schema.js`：本地 schema 基础校验脚本

## 使用步骤

1. 在 Figma Desktop 中导入插件：
   - `Plugins` -> `Development` -> `Import plugin from manifest...`
   - 选择：`设计/figma-json-bridge/plugin/manifest.json`

2. 运行插件并加载示例：
   - 打开任意 Figma 文件页
   - `Plugins` -> `Development` -> `Tsugie UI Schema Bridge`
   - 点击 `加载示例` -> `校验` -> `应用到 Figma`

3. 用 Codex 生成 schema 并应用：
   - 参考：`prompts/codex-ui-schema-prompt.md`
   - 将 Codex 输出粘贴到插件输入框
   - 点击 `校验`，通过后点击 `应用到 Figma`

## 幂等更新机制

- 每个节点通过 `id` 做唯一定位。
- 同一个 `id` 重复应用会更新已有节点，而不是重复创建。
- 勾选 `删除 schema 中不存在的托管节点` 时会清理托管旧节点（prune 模式）。

## 支持的节点类型（v1）

- `FRAME`
- `RECTANGLE`
- `TEXT`
- `ELLIPSE`
- `BUTTON`（会自动生成按钮文字子节点）

## 本地校验

```bash
node 设计/figma-json-bridge/scripts/validate-ui-schema.js \
  设计/figma-json-bridge/schema/ui-schema.example.node-1-2.json
```

## 当前限制（v1）

- 原型连线（Prototype interactions）未自动写入。
- 仅支持纯色填充（SOLID）。
- 复杂组件（Instance、Variant、Image Fill）暂未纳入。

## 下一步建议

1. 增加 prototype 自动连线字段并实现写入。
2. 增加图片填充与组件实例映射能力。
3. 增加 schema diff 输出（仅更新变化节点）。
