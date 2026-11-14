# PANEL 实施计划：控件与面板（M4 的界面部分）

上位文档：`PARALLEL-PLAN.md §2 C4/C5、§3.2、§4、§5`；`UI-UX.md §4（控件库）、§5（焦点）、§7.1（动作）、§9（按键提示）、§8（三输入流程）`。本文只负责 PANEL 线；契约以 `PARALLEL-PLAN.md §2` 为准，本文不新增、不改写契约。

## 0. 目标与验收

把 UI-UX §4 里 M1 未做的控件补齐，并在 P0 完成后实现背包、制作、科技、日志、角色详情五个面板与开发面板外壳。

| # | 验收项 | 怎么验 |
|---|---|---|
| P1 | UI-UX §4 的 9 个控件全部可绘制、可聚焦、可激活：`IconButton`、`List`、`ItemGrid`、`ProgressBar`、`Tooltip`、`Modal`、`Confirm`、`Radial`、`Stepper` | `tests/probe/panel_widgets.lua`（焦点可达性 + 控件状态机 + 三语断言） |
| P2 | 提示栏按当前上下文与最近输入设备生成，最多 6 项，键位/手柄图标来自查表 | 探针切换 `last_device` 与上下文，断言项数与图标类型；三语截图 |
| P3 | 三语（zh/en/ko）与标准/大字两档下，控件文字不越界、`quad_count()` 不超预算 | `tests/probe/panel_widgets.lua` + `tools/shot.sh` 截图 |
| P4 | 每个控件在纯键盘、纯鼠标、纯手柄下可完成 UI-UX §8 对应步骤 | `tests/probe/panel_input.lua`（按设备分别驱动；P0 的 `core/input.lua` 动作补齐后接入） |
| P5 | 五个面板按 C5 接口接入，只经 C4 查询取数，只经 `ctx.on_command` 下命令 | P0 后 `tests/probe/panel_flow.lua` 用四个夹具逐面板跑通 |
| P6 | 焦点可达性校验（UI-UX §5.7）对每个面板通过；无“进得去出不来” | `focus.audit()` 断言 |

**分阶段交付**：P1–P3 现在就能做（只依赖 M1）；P4–P6 等 P0。P4 的控件部分可以先做，面板流程部分等 P0 的输入动作表与夹具。

## 1. 依赖与开工条件

| 工作 | 最早开工 | 原因 |
|---|---|---|
| 控件 9 个 + `ui/hintbar.lua` + `ui/glyphs.lua` | **现在** | 不读模拟状态，只用 `ui/*`、M1 的 `core/input.lua` 与 `ui/theme.lua` |
| 面板（背包/制作/科技/日志/角色详情） | P0-4、P0-5、P0-6 合入 main 后 | 需要 C4 查询层、P0 夹具与场景空壳 |
| 开发面板 `ui/devpanel.lua` 外壳 | P0-6 后 | 需要场景跳转；STORY 线之后往里加页签 |
| 三输入面板流程验收（P4–P6） | P0-3 后 | 需要 §7.1 的完整动作表 |

P0 未完成时**不得**创建 `ui/inventory.lua`、`ui/craft.lua`、`ui/tech.lua`、`ui/journal.lua`、`ui/character.lua`、`ui/devpanel.lua` 的空壳，也不得在 PANEL 分支里预读 `sim/state` 或 `sim/query`；否则会把未冻结的结构带进面板。

## 2. 控件部分（现在做）

### 2.1 通用约定

- 沿用 M1 的立即模式风格：`_draw()` 期间注册焦点元素，`_update()` 只读动作、不读按键。所有控件返回“新值 + 变化标志”，由调用方持有状态。
- 控件对象字段与 UI-UX §4.1 一致：`{id, rect, enabled, focusable, on_activate, tooltip_key, nav}`；禁用控件仍可聚焦，激活时只发 `sfx/ui_deny`。
- 所有坐标按 8 px 网格；宽度用 `ui.text_measure` 实测，不写死；单行放不下用 `widgets.ellipsize()`。
- 新增文本一律 `i18n.t("ui.*")` / `i18n.t("hint.*")`，不出现面向玩家的字面量。

### 2.2 任务表

| # | 任务 | 文件 | 验收 |
|---|---|---|---|
| W1 | `IconButton`：44/48/32 方形按钮，图标居中，角标（红点/数字），工具提示 | `ui/widgets.lua` | 鼠标/键盘/手柄激活，焦点环与禁用态；角标两种形态 |
| W2 | `List`：40 px 行，奇偶底差，选中 `accent` 左条，16 px 滚动条（轨道/拇指/翻页箭头），不嵌套 clip | `ui/widgets.lua` | 行选择、翻页、Home/End、聚焦行自动可见；三语长文本省略 |
| W3 | `ItemGrid`：48×48 格 + 4 间距，图标/数量/超重描边；拖放与点击-点击两套操作；快速转移、拆分入口 | `ui/widgets.lua` | 两种操作都能移动物品；Esc/右键取消；满载拒绝事件 |
| W4 | `ProgressBar`：皮肤 `bar`，整数像素填充，可带百分比文字、可中断取消提示、撬锁噪音图标 | `ui/widgets.lua` | 0/50/100% 像素数正确；不聚焦（除容器是按钮） |
| W5 | `Tooltip`：悬停/聚焦 0.4 s，宽 ≤ 360，自动换行，越界翻转，全屏内，唯一实例，clip 外绘制 | `ui/widgets.lua` | 四角定位不越界；三语换行；`ui_info` 立即显示 |
| W6 | `Modal`：暗幕 α0.55，480–720 宽，标题/正文/按钮行，焦点捕获与恢复，Esc/B 取消，同刻仅一个、其余入队 | `ui/widgets.lua` | 打开后下层不可聚焦；关闭后恢复 `remember`；队列顺序 |
| W7 | `Confirm`：`取消` 默认聚焦，危险操作 `danger` 描边；长按替代（0.4–1.5 s）与进度反馈 | `ui/widgets.lua` | 点暗幕不取消危险操作；长按/松开/移走三态正确 |
| W8 | `Radial`：2–8 扇区，北=1 顺时针，半径 112/内环 40，中心选中名；键盘/鼠标/手柄选择与取消 | `ui/widgets.lua` | 三设备都能选；>8 项拒绝并提示用列表 |
| W9 | `Stepper`：`[−10][−] 数字 [＋][＋10]`，40×40 钮，范围与步长，按住连续，键盘/手柄 Home/End 与 ±10 | `ui/widgets.lua` | 边界夹紧；鼠标按住连续；Enter/A 确认、B/Esc 取消 |
| W10 | `ui/glyphs.lua`：三套按键图标的查表与绘制；`last_device` 选套件；`pad.connected()` 为假时不选手柄套件 | `ui/glyphs.lua` | 键名↔图标、鼠标键、全部 17 个手柄逻辑按钮都有条目；无图集时用程序占位 |
| W11 | `ui/hintbar.lua`：上下文栈、每项 = 图标 + `hint.<action>` 文本，最多 6 项、超出丢弃末尾；设备切换立即更新；长按项画圆环 | `ui/hintbar.lua` | UI-UX §9.2 八个上下文的预设；探针断言项数/顺序/图标 |
| W12 | 文本：`ui.*` 控件词条与 `hint.*` 提示词条（zh/en/ko） | `assets/i18n/{zh,en,ko}.lua` | 三语键齐全；`bake_font.py --check` 通过 |
| W13 | 控件演示脚本（只用于截图与探针）：`main` 视图展示常驻控件，`modal`/`confirm`/`radial` 视图展示三个模态控件 | `assets/scripts/ui/panel_demo.lua` | `tools/shot.sh` 三语截图 + 覆盖层视图可见全部 9 个控件与提示栏 |

### 2.3 控件 API 形状（本计划裁定）

写成可组合的模块函数，不引入类与全局单例：

```lua
widgets.icon_button(id, rect, glyph, opts) -> clicked
widgets.list(id, rect, items, selected, opts) -> selected, activated
widgets.item_grid(id, rect, cols, rows, items, cursor, opts) -> cursor, event
widgets.progress_bar(rect, value, max, opts)
widgets.tooltip(id, anchor_rect, spec, opts)
widgets.modal(id, spec) -> button_id
widgets.confirm(id, spec) -> "confirm" | "cancel" | nil
widgets.radial(id, spec) -> { action, item_id } | nil
widgets.stepper(id, rect, value, min, max, step, opts) -> value, changed, done
```

- `spec` / `opts` 里的文本一律传 i18n 键或已翻译字符串；控件自身不拼面向玩家的文本。
- 状态（滚动位置、拖拽源、长按计时、工具提示计时、轮盘选中项）按 `id` 存在 `widgets` 内部表里，跨帧保持；面板关闭时调用方调 `widgets.reset(id)`。
- `ItemGrid` 的 `event.kind ∈ {"select", "activate", "move", "transfer", "secondary", "cancel"}`；搬物品、校验重量、发命令由调用方做，控件不碰 `sim`。

## 3. 提示栏与图标（现在做）

- `ui/glyphs.lua` 的查表键：`key:<name>`、`mouse:<left|right|middle|move|drag>`、`pad:<a|b|x|y|lb|rb|lt|rt|dpad_*|l3|r3|ls|rs|start|back>`。
- 绘制：键帽用现有 `skin.png` 的 `btn_normal` 九宫格 + `f_s` 标签；鼠标/手柄用程序占位（圆键用色块 + 字母/方向符），ART 线交付 `assets/ui/glyphs.png` 后只替换 `glyphs.draw()` 的图集分支，调用方不变。
- `ui/hintbar.lua` 不改 `core/input.lua`；只读 `input.get_binding(device, action, 1)` 与 `input.last_device()`。P0-3 补齐动作后自动覆盖新动作。
- 上下文预设：`home_idle`、`home_focus`、`raid`、`combat`、`menu`、`dialog`、`drag`、`cursor`，与 UI-UX §9.2 表一一对应。

## 4. 面板部分（P0 后做）

### 4.1 统一接口（C5）

每个面板实现：

```lua
panel.open(ctx)      -- ctx = { state, on_command(cmd), focus_group, fixture }
panel.update(dt)
panel.draw()
panel.close()
```

- 面板只通过 C4 查询函数取视图模型：`query.inv.grid`、`query.craft.list`、`query.tech.tree`、`query.clock.hud`、`query.party.cards/detail` 等。
- 面板不直接调用 `sim.command`；一律 `ctx.on_command({ kind = "...", ... })`，由场景决定暂停与排队（UI-UX §6.8）。
- `ui/theme.lua` 的 `layout` 表由 PANEL 维护（C5）；HOME/RAID 只读。控件尺寸与锚点进 `layout`，不散落在各面板。
- 打开面板时压入自己的焦点组，关闭时 `pop_group`；所有按钮走 `widgets.button` / `icon_button`，焦点可达性由 `focus.audit()` 验收。

### 4.2 任务表（P0 完成后）

| # | 面板 | 文件 | 数据来源 | 验收 |
|---|---|---|---|---|
| P-1 | 背包 | `ui/inventory.lua` | `query.inv.grid` | 网格移动/转移/拆分/使用；重量条；三输入 §8.6 步骤 |
| P-2 | 制作 | `ui/craft.lua` | `query.craft.list` | 配方列表、数量 Stepper、材料不足灰显、进度条与取消 |
| P-3 | 科技 | `ui/tech.lua` | `query.tech.tree` | 树形/分层列表，锁定项显示原因，解锁命令走 `ctx.on_command` |
| P-4 | 日志 | `ui/journal.lua` | C3 事件/日志查询（P0 若未预置，走 §5 变更流程申请） | 倒序、筛选页签、暂停可读开关 |
| P-5 | 角色详情 | `ui/character.lua` | `query.party.detail` | 特长/缺点、关系、全部心理条目、疾病、干预按钮 |
| P-6 | 开发面板外壳 | `ui/devpanel.lua` | 只读调试数据 | 520 宽右侧覆盖层，页签容器留给 STORY 追加；仅 `--dev` |

## 5. 文件归属

| 归属 | 文件 |
|---|---|
| PANEL 拥有（可改） | `assets/scripts/ui/widgets.lua`、`ui/focus.lua`（仅补模态注册目标）、`ui/theme.lua`（仅 `layout` 表）、`ui/glyphs.lua`、`ui/hintbar.lua`、`ui/inventory.lua`、`ui/craft.lua`、`ui/tech.lua`、`ui/journal.lua`、`ui/character.lua`、`ui/devpanel.lua`、`ui/panel_demo.lua`；新增的 `assets/scripts/ui/*.lua` |
| PANEL 只读 | `ui/rebind.lua`、`ui/settings.lua`（只加 `focus.set_target` 一行）、`core/*`、`sim/*`、`scenes/*`；`ui/dialog.lua`、`ui/hud_home.lua`、`ui/hud_raid.lua` |
| 文本（临时） | `assets/i18n/{zh,en,ko}.lua` 的 `ui.*`、`hint.*` 键。P0-1 拆成目录后整体迁到 `assets/i18n/<lang>/ui.lua`，迁移前不新增别的区 |
| 测试 | 新增 `tests/probe/panel_*.lua`、`tests/lua/test_panel_*.lua`（新文件，带 `panel_` 前缀）；不改 `tests/lua/runner.lua` 等共享文件 |
| 不改 | `build.zig`、`ci/`、`README.md`、`docs/PLAN.md`、`core/input.lua` 的动作表、`sim/` 任何文件 |

需要 `core/` 或 `build.zig` 的改动（例如把 `panel_widgets` 探针加进 CI、或 P0-3 的动作表）先在合并请求里列出，由主代理在 main 上做。

## 6. 截图与探针

控件部分用 M2 的 `tools/shot.sh` 验证三语画面：

```bash
tools/shot.sh /tmp/opencode/panel_zh.png --script assets/scripts/ui/panel_demo.lua --lang zh --at 1
tools/shot.sh /tmp/opencode/panel_en.png --script assets/scripts/ui/panel_demo.lua --lang en --at 1
tools/shot.sh /tmp/opencode/panel_ko.png --script assets/scripts/ui/panel_demo.lua --lang ko --at 1
```

演示脚本只依赖 `ui/*`，展示 9 个控件、提示栏在键盘/鼠标/手柄三种设备下的图标，以及标准/大字两档。模态类控件用 `PANEL_DEMO_VIEW=modal|confirm|radial` 单独截图：

```bash
PANEL_DEMO_VIEW=modal  tools/shot.sh /tmp/opencode/panel_modal_zh.png  --script assets/scripts/ui/panel_demo.lua --lang zh --at 1
PANEL_DEMO_VIEW=confirm tools/shot.sh /tmp/opencode/panel_confirm_zh.png --script assets/scripts/ui/panel_demo.lua --lang zh --at 1
PANEL_DEMO_VIEW=radial tools/shot.sh /tmp/opencode/panel_radial_zh.png --script assets/scripts/ui/panel_demo.lua --lang zh --at 1
PANEL_DEMO_DEVICE=keyboard tools/shot.sh /tmp/opencode/panel_hint_keyboard_zh.png --script assets/scripts/ui/panel_demo.lua --lang zh --at 1
```

截图要求：

- 三语文字都在容器内，无溢出、无缺字（缺字会显示 fallback `?`）。
- 手柄图标与键帽/手柄套件随 `last_device` 切换。
- 面板、控件、提示栏的像素边缘清晰，无半透明渐变。

探针 `tests/probe/panel_widgets.lua` 断言：

1. 每个控件注册后 `focus.audit().ok`。
2. `List` 的翻页/Home/End 后选中行始终可见。
3. `Stepper` 在 0、max 处夹紧，±10 与 ±1 正确。
4. `Radial` 的 8 个扇区方向与北=1 顺时针一致，9 项被拒绝。
5. `Modal` / `Confirm` 打开时下层控件不可聚焦，关闭后恢复 `remember`。
6. `hintbar` 八个上下文的项数 ≤ 6、顺序与设备图标类型正确。
7. 三语 + 大字下 `ui.quad_count()` 在预算内。

## 7. 合并与风险

- 合并顺序按 `PARALLEL-PLAN §5`：P0 → PANEL → HOME → …。PANEL 每次向 main 合并前跑完 PLAN §7 全部命令并附三语截图。
- 控件部分可以先合入（只动 `ui/*` 与新增 i18n 键），面板部分等 P0 后再发第二个合并请求。
- 风险与对策：

| 风险 | 对策 |
|---|---|
| 控件 API 与 HOME/RAID 的用法不一致 | 控件 API 在本计划 §2.3 冻结；HOME/RAID 只读使用，改动走契约变更 |
| 提示栏读不到 P0-3 的新动作 | 控件部分只依赖已有动作；P0-3 后提示栏自动读取新绑定，不改代码 |
| 三语文本挤爆固定宽控件 | 全部宽度用 `text_measure`；截图三种语言 + 大字模式逐屏检查 |
| 手柄图标没有正式图集 | 先程序占位并保留 `glyphs.draw()` 的图集分支；ART 交付后只换绘制 |
| 面板在夹具上正常、真实游玩出错 | P0 夹具由机器人真实跑出；HOME 合入前用真实流程重跑 PANEL 探针（§6 风险表） |
| `ui.clip` 嵌套 | 列表只在自己的可视区 clip，行内不 clip；工具提示/下拉在 `clip_off()` 之后画 |

## 8. 返工 1 记录（控件部分审查后）

行为裁定（实现以此为准，API 不变）：

- **模态结果只交付一次**：`modal/confirm/radial` 在绘制路径上返回的结果不再存入 `_modal_results/_radial_results`；只有经 `focus.update` 取消（Esc/B/右键）关闭时才存，下一次同 id 调用交付一次后清除（0.5 s 未取走即丢弃）。内部 `finish_modal/finish_radial` = 关闭但不存结果，`close_modal/close_radial` = 关闭并存结果。
- **模态队列**：模态与轮盘共用一个 FIFO（`widgets._queue`，项 `{kind,id,spec,seen}`）。占用时的请求入队，按序放行；调用方照常每帧调用，返回 `nil` = 尚未显示。0.5 s 内没再提交的排队项自动丢弃。新打开的轮盘首帧忽略输入（关闭上一个模态的那次按键不会立刻选中扇区）。
- **ItemGrid 取消**：持物时 Esc/B/右键 → `{kind="cancel"}`，清空 held，且经 `focus.cancel_capture` 阻止同一次取消再触发面板 `on_cancel`；持物时不产生转移/次级事件；同一帧先到的事件不被覆盖。键盘 `on_activate` 产生的事件经 `st.pending_event` 在下一次绘制返回（原先丢失）。
- **ItemGrid 的 Y**（UI-UX §4.9 与 §4.11 的取舍）：手柄 Y = 物品菜单（`event.kind="secondary"`），键盘 H = 立即显示工具提示（`ui_info`）；X / Shift+Enter = 转移。键盘没有物品菜单键（表里未定义），待 P0-3 动作表补 `ui_menu` 之类再接。
- **ui_info**：`widgets.info_active(id)`——聚焦元素按 `ui_info` 立即显示并常驻其工具提示，再按一次、Esc/B 或焦点移走时撤销；常驻期间其他元素的悬停/聚焦提示被抑制。
- **List**：PageUp/PageDown/Home/End 移动的是聚焦行（`focus.set_focus`），视口随之滚动；只在选中行变化时跟随，因此滚动条仍可把视口拖离；仅绘制可见行，所有行仍注册焦点（视口外的行带 `no_hover`）；空列表返回 `nil`；禁用行激活播 `sfx/ui_deny`；滚动条不超出 `rect`；箭头钮按下即滚一行，按住 0.4 s 后每 60 ms 一行。
- **Stepper**：`enabled=false` 时可聚焦、方向键/Home/End/PageUp/Down/Enter 只播 `sfx/ui_deny`，不改值。鼠标按下 ± 钮不再同时算作 Enter 确认。
- **Radial**：扇区命中以图标为中心（±半个扇区），北=1 顺时针；鼠标悬停选中扇区；左键按下不再按旧的选中项确认（改在松开时按指针扇区）。`widgets.radial_sector(dx,dy,n)` 公开供探针使用。
- **图标名**：`glyphs.spec(name)` 是唯一解析器：`key:*`、`pad:*`、`mouse:left|right|middle|move|drag`（数字 0/1/2 仍可）。
- **提示栏**：鼠标设备下主图标已是键帽时不再画第二个热键；热键宽度计入排版；上限 6 项按“可见项”计；`raid` 预设把潜行/奔跑合成一项（`action2="run_hold"`，新词条 `hint.sneak_run`），撤离出现时共 6 项。`hintbar.layout()` / `hintbar.resolve()` 公开供探针使用。
- **进度条文字**：填充部分用深色 `theme.colors.text_on_fill`，其余部分用浅色（按填充边界分两次裁剪绘制）。
- **工具提示**：物品格 0.3 s（§4.9），其他 0.4 s。
- **拖放**：拖拽中落点格画 `ok`/`danger` 框（`opts.can_drop(from,to)` 可选，默认可放入空格或未禁用格）。

绕过动作表直读按键的清单见 `widgets.lua` 文件头；P0-3 增补动作后逐项替换。

探针：`tests/probe/panel_widgets.lua` 扩为 115 项，覆盖上述各条，并对 zh/en/ko × 标准/大字循环检查quad 预算、焦点可达、全部提示栏预设（三设备）不溢出、模态正文/标题不越界。`panel_demo.lua` 支持 `PANEL_DEMO_LARGE=1`。
