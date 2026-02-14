# Node 0:1 进度条强化与多场景一致性归档 v5

## 1. 阶段目标
- 强化进度条在核心决策路径中的存在感，让用户在地图浏览、时间筛选、收藏管理三个入口都能快速理解活动状态。
- 统一进度条语义与视觉实现，确保 `nearbyTrack`、日历日抽屉列表、收藏列表与详情页状态表达一致。
- 修复多轮实现中出现的“端点固定在最左侧”问题，形成可复用、可复现的稳定实现方式。

## 2. 本阶段需求（最终口径）
1. `nearbyTrack` 项底部增加进度条。
2. 日历页点击某天后，抽屉列表 `drawer-day-item` 底部增加进度条。
3. 收藏列表中，若某项为进行中，则展示进度条。
4. 三个场景的进度条应与详情页同源（状态判断、视觉语义一致）。
5. 对于“超过 1 日才开始”的活动，不展示进度条。

## 3. 功能点落地（当前可用）
### 3.1 多场景进度条接入
- `nearbyTrack`：每个卡片底部渲染 mini-progress。
- 日历日抽屉：每条 `drawer-day-item` 底部渲染 mini-progress。
- 收藏列表：仅进行中项渲染 mini-progress（保持列表信息密度）。

### 3.2 统一状态来源
- 所有场景统一使用 `resolveEventStatus(place)` 输出状态。
- 进度百分比统一规则：
- `ongoing`：`status.progress`。
- `upcoming`：`status.waitProgress`。
- `ended`：100%。

### 3.3 统一定位算法（关键）
- mini-progress 不再独立计算端点位置。
- 全部改为调用详情页同一套定位函数：
- `setProgressPosition(track, fill, face, endpoint, pct)`。
- 通过该函数统一完成：
- 轨道进度变量设置。
- 填充宽度设置。
- 端点边缘吸附（`is-edge-left` / `is-edge-right`）。

### 3.4 轨道宽度塌陷修复
- 问题现象：端点始终在最左侧。
- 根因：mini-progress 轨道在列表上下文中可能塌陷为 0 宽，导致定位正确但可视位置错误。
- 修复措施：
- 将 `mini-progress-track` 从 `span` 改为块级容器。
- 强制 `display: block; width: 100%; box-sizing: border-box;`。

### 3.5 进度条显示策略补充
- 新增 `shouldShowMiniProgress(status)`：
- 当 `status.mode === 'upcoming'` 且 `status.countdownSec > 24 * 60 * 60` 时，不渲染进度条。
- 该规则对 `nearbyTrack`、日历抽屉、收藏（若未来扩展至 upcoming）保持一致。

## 4. 当前交互语义
1. 地图页（位置维度）：
- `nearbyTrack` 用于“更远一点仍可去哪里”，进度条补充状态感知而非替代名称/距离信息。

2. 日历抽屉（时间维度 -> 某日列表）：
- 进度条用于快速区分“进行中/即将开始/已结束”，提升日内决策效率。

3. 收藏列表（用户偏好维度）：
- 仅进行中显示进度条，避免常驻信息噪声。

## 5. 设计注意点（后续必须遵守）
1. 同源原则：
- 列表类进度条必须复用详情页同一定位链路，不允许再做“平行实现”。

2. 组件约束：
- mini-progress 轨道必须是块级 + 满宽，避免布局环境变化导致长度塌陷。

3. 视觉一致性：
- 状态类应沿用详情页视觉语义：
- `ongoing` 使用高亮渐变强调。
- `upcoming/ended` 使用低调语义。

4. 信息克制：
- 收藏只对进行中显示进度条。
- 超过 1 日未开始不显示进度条，避免制造无效紧迫感。

5. 复现优先：
- 若后续新增新的列表场景（例如通知列表），直接复用当前 mini-progress 渲染 + `applyMiniProgressNode`，不要再新起一套计算和样式。

## 6. 关键实现点（代码锚点）
- 多场景进度渲染模板：`设计/原型/main-screen.html`
- mini-progress 应用入口：`applyMiniProgressNode`
- 统一定位函数（与详情同源）：`setProgressPosition`
- 日历抽屉渲染接入：`renderCalendarDayDrawerContent`
- 收藏渲染接入：`renderFavoritesContent`
- nearby 渲染接入：`renderNearbyCarousel`
- 超过 1 日隐藏规则：`shouldShowMiniProgress`
- 轨道样式防塌陷：`设计/原型/main-screen.css` 中 `.mini-progress .status-track`

## 7. 验收清单（本阶段）
1. 浅草（进行中）在详情页、nearby、收藏的端点位置一致。
2. 隅田川（即将开始）在详情页与 nearby 的进度语义一致。
3. 超过 1 日才开始的项（如 `jingu-icho`）在 nearby 不显示进度条。
4. 日历某日抽屉列表中，进度条可见且端点不固定在左侧。
5. 刷新页面后表现稳定，不因重渲染丢失端点位置。

## 8. 关联文件
- `设计/原型/main-screen.html`
- `设计/原型/main-screen.css`
- `记录/项目变更记录.md`
- `记录/归档/2026-02-14-node-0-1-进度条强化与一致性修复阶段归档-v5.md`

## 9. 本地前端快照（不入库）
- `记录/归档/frontend-code-snapshots/2026-02-14-node-0-1-progress-visibility-v5/`
