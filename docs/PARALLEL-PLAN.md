# M4 起的并行开发计划

上位文档：`PLAN.md §4、§6`；`M2-PLAN.md`、`M3-PLAN.md`（两者是本计划的前提）。本文规定 M4–M9 怎样拆成可以在独立工作树里同时推进的几条线：先冻结哪些接口、每条线拥有哪些文件、共享文件怎么改、什么时候合并。

各条线开工时由该线的会话写自己的 `docs/<线>-PLAN.md`（格式同 M2/M3），主代理审核它是否遵守本文的契约和文件归属，审核通过后再开工。

## 0. 总览

```
 M2（地图表现）──┐
                 ├─► P0 接口冻结（main 上，约 1 个波次）─┬─► HOME  家园可玩（M4）
 M3（模拟核心）──┘                                      ├─► PANEL 面板与控件（M4 的界面部分）
                                                        ├─► WORLD 世界生成、大地图、交易（M5）
                                                        ├─► RAID  潜行、战斗、伤亡（M6 → M7）
                                                        └─► STORY 叙事引擎（M8）
                                         ART 美术批量（M2 的 A5 风格评审通过后，任何时候）

 汇合：HOME + PANEL ─► M4 试玩检查点
       HOME + WORLD + RAID ─► M6 试玩检查点（完整昼夜循环）
       STORY + WORLD + RAID ─► M9 哨站线与结局 ─► M10 内容与平衡 ─► M12
```

可以提前开工的部分：

| 线 | 最早开工条件 | 原因 |
|---|---|---|
| PANEL 的控件部分（§3.2 第 1 项） | 现在（只依赖 M1） | `ui/widgets.lua` 的新控件不读模拟状态 |
| STORY | M3 合入 main + P0 的 C1、C2、C6、C9 | 纯 Lua 模型层，不依赖地图 |
| 其余各线 | P0 全部完成 | 需要 M2 的 `view/` 和 M3 的 `sim/` |

## 1. P0：接口冻结（主代理负责，在 main 上做）

M2、M3 都合入 main 后立即进行。P0 的产出是**契约**和**拆开的共享文件**，不做玩法。P0 合入后，§2 的契约只能按 §5 的变更流程修改。

| # | 任务 | 代理 | 产出 | 验收 |
|---|---|---|---|---|
| P0-1 | **文本表拆分**：`assets/i18n/<lang>.lua` 改为目录 `assets/i18n/<lang>/<area>.lua`（area 见 §4 的归属表）；`core/i18n.lua` 合并同一语言的全部文件，**同一个键出现在两个文件里就报错**；`tools/bake_font.py` 递归扫描；`tools/i18n_check.py` 按目录比较三语（若 i18n-check 工作树已在做这个工具，在它的基础上改） | haiku | 新目录结构，现有键原样迁移 | luatest 新增重复键用例；`assets.py check` 全过；字体图集与拆分前逐字节相同 |
| P0-2 | **命令注册式**：`sim/commands.lua` 改为 `commands.register(kind, fn, spec)`，现有处理函数按领域搬到 `sim/cmd/{home,needs,craft,tech,night}.lua`；`commands.run` 不变 | sonnet | 见 C2 | M3 的全部测试和 `balance` 结果逐字节不变 |
| P0-3 | **输入动作补齐**：把 UI-UX §7.1 里还没实现的动作一次补完（`select`、`select_all`、`select_1..6`、`select_next/prev`、`move_to`、`move_dir`、`camera_pan`、`quick_1..4`、`squad_follow/hold/lookout/carry`、`focus_next/prev`、`cursor_click_l/r`、`system_menu`、`dev_panel`、`fullscreen`、`screenshot`），连同默认绑定、冲突检测和改键界面条目 | haiku | `core/input.lua`、改键界面 | `m1_inputs` 探针扩展到全部动作；之后各条线**不再修改** `core/input.lua` 的动作表 |
| P0-4 | **契约代码骨架**：C1、C3、C4、C6、C7、C8、C9 的接口按 §2 落成文件（函数体可以是最小实现或返回空），并把 §2 的表抄进对应文件头注释 | sonnet | 见 §2 各条 | luatest：每个契约函数可调用、返回值形状正确；`test_layering` 覆盖新目录 |
| P0-5 | **测试夹具**：用 M3 的机器人生成 `tests/fixtures/{day1_0600,day3_1900,day10_1200,day28_2100}.sav`，外加 `tests/fixtures/make.lua` 可重新生成；状态版本变化时由 `make.lua` 重建 | haiku | 夹具文件 | 四个夹具都能读档并通过 `state.validate` |
| P0-6 | **场景外壳**：`scenes/` 下为 §2.1 屏幕清单里每个场景建空壳（只画场景名和返回按钮），并接好 UI-UX §2.2 的跳转；用夹具可直接进入任一场景（`--dev --scene <name> --fixture <name>`） | haiku | 场景空壳、`--scene`/`--fixture` 参数 | 探针：从夹具进入每个场景再返回，无报错 |

P0 完成的标志：以上全部合入 main，主代理在 PLAN §6 记一笔“P0 已完成”，各线据此建工作树。

## 2. 契约

每条契约写明**谁拥有**（只有拥有者能改实现）、**谁使用**、**冻结的是什么**。冻结指函数签名、表结构和语义；拥有者可以在自己的子树里加字段，但不得改名、删除或改变已有字段的含义。

### C1 状态树（拥有者：各子树的线；结构定义在 `sim/state.lua`）

在 M3 的状态根上划定各线的子树：

| 子树 | 拥有者 | 说明 |
|---|---|---|
| `clock`、`party`、`home`、`weather`、`tech`、`stats` | M3 已有；之后由 HOME 维护 | |
| `world.locations`、`world.npcs`、`world.factions`、`world.notoriety`、`world.traders` | WORLD | |
| `night`（出发前的安排）| HOME（黄昏界面写入） | RAID 只读 |
| `raid`（副本临时状态） | RAID | **不进存档**（§4.5 只在时段边界存档），撤离时经 C7 写回 |
| `story.*`、`party.chars[id].psyche` | STORY | |
| `outpost`、`endings` | M9（之后再定） | P0 只占位为空表 |

规则：别的线只能通过 C4 查询函数读其他子树，通过 C2 命令写。`state.validate` 由各子树拥有者提供自己那部分的校验函数，`state.lua` 汇总调用。

### C2 命令（拥有者：命令所在文件的线）

- 入口不变：`sim.command(state, cmd) -> ok, err`，`cmd = { kind = "<域>.<动作>", ... }`。P0 把 M3 现有命令改为带域名的写法（如 `home.repair`），并保留旧名作为别名直到 M4 结束。
- 注册：`commands.register(kind, fn, spec)`，`spec = { args = { name = "char"|"item"|"room"|"loc"|"number"|"string", ... }, phase = { "day", ... } }`；`commands.run` 先按 spec 校验参数类型和时段，再调用处理函数。错误码统一为短字符串键，同时作为 i18n 键 `err.<code>`。
- 每条线的命令放 `sim/cmd/<域>.lua`，域名即线名：`home.*`、`trade.*`、`travel.*`、`raid.*`、`story.*`。
- 预留命令名（P0 只注册签名，处理函数返回 `false, "not_implemented"`）：`trade.offer`、`trade.accept`、`trade.leave`、`travel.go`、`raid.begin`、`raid.commit`、`story.choose`、`night.set_role`、`night.set_target`、`night.set_loadout`。

### C3 事件（拥有者：发出方）

- `core/bus.lua` 不变。事件名以设计文档（PLAN §4.4）为准：`char_died`、`storylet_ready`、`snap_warning`。设计文档尚未定名的事件，暂沿用 `<域>.<动作>` 写法（`clock.*`、`home.*`、`raid.*`、`world.*`），待设计文档补定后按设计文档改名（走 §5 流程）。
- 目录 `sim/events.lua`：每个事件一行 `name = { fields... }`，按域分段；**只追加**，追加时写在自己域的段末尾（这样合并冲突只会是相邻行，手工解决很简单）。
- P0 预置：`clock.phase_changed`、`clock.day_started`、`char_died`、`char.wounded`、`char.left_party`、`char.joined_party`、`home.station_changed`、`home.room_temp_alert`、`snap_warning`、`storylet_ready`、`raid.ended`。

### C4 查询层（拥有者：被查询子树的线）

界面和场景只通过查询函数读状态，不直接翻状态树。这样 PANEL 可以用夹具开发，子树内部改结构时界面不跟着改。

- 位置：`sim/query/<域>.lua`，纯函数 `fn(state, ...) -> 视图模型表`，视图模型只含显示需要的字段与 i18n 键，不含面向玩家的字面文本。
- P0 预置：`query.party.cards(state)`（头像卡，UI-UX §3.4）、`query.party.detail(state, id)`（§3.5）、`query.home.rooms(state)`、`query.home.stations(state)`、`query.inv.grid(state, bag_ref)`、`query.craft.list(state, station_id)`、`query.tech.tree(state)`、`query.clock.hud(state)`、`query.night.plan(state)`。WORLD、RAID、STORY 的查询在各自线计划里定，加在自己的文件里。

### C5 场景与界面约定（拥有者：PANEL）

- 场景切换只用 `core/scene.lua` 的 push/replace/pop，规则按 UI-UX §2.2。
- 面板的统一接口：`panel.open(ctx)`、`panel.update(dt)`、`panel.draw()`、`panel.close()`；`ctx` 至少含 `state`、`on_command(cmd)`、`focus_group`。面板不直接调用 `sim.command`，经 `ctx.on_command` 交给场景，便于场景决定是否暂停、是否排队（UI-UX §6.8）。
- HUD 的布局常量（锚点、边距、头像卡尺寸）集中在 `ui/theme.lua` 的 `layout` 表，PANEL 维护；HOME、RAID 只读。

### C6 行为记录（拥有者：STORY；RAID、WORLD、HOME 都会写）

叙事的输入是行为账本。RAID、WORLD 在 STORY 完成前就要开始记录，所以 P0 先落定记录格式和一个只追加的最小实现。字段、取值以 NARRATIVE §2.4 为准，权重与标签以 WORLD §2.2 为准：

```lua
deeds.record(state, {
  verb = "steal" | "rob" | "assault" | "knockout" | "kill" | "spare" | "help" | "give"
       | "trade_fair" | "trade_cheat" | "refuse_help" | "abandon" | "betray"
       | "rescue" | "bury" | "confess" | "return_goods" | "inform" | "die" | ...,  -- 动词表在 data/deed_kinds.lua，只追加；die 无动手者（WORLD §2.4）
  actor = char_id,                         -- 动手的人
  squad = { char_id... },                  -- 同行者（NARRATIVE §2.4 样例含 actor 自己）
  target = "npc.<id>" | char_id | nil, target_kind = "civilian"|"raider"|"soldier"|"trader"|"teammate"|"nobody",
  loc = location_id,
  tags = { occupied = true, victim_vulnerable = true, took_essentials = true, lethal = false, ... },  -- 标签表见 WORLD §2.2，只追加
  witnesses = { "npc.<id>"... },           -- 活着的目击者
  magnitude = 0..1,                        -- 被拿走的东西对受害方有多要紧
  -- id、day、phase 由 record 填：id 递增（返回值）；day、phase 取 state.clock，phase ∈ day|dusk|night|dawn
}) -> deed_id
```

字段语义以 NARRATIVE §2.4、WORLD §2.2/§2.4/§9 的反应规则为准；P0 的实现只做校验和追加，`reactors` 在 STORY 线实现。STORY 线可以给 `verb` 表追加动词、给 `tags` 追加标签，但不得改上面的顶层字段。

### C7 副本接口（拥有者：RAID；WORLD 提供输入）

替换 M3 的临时 `sim/expedition.lua`（函数名即 PLAN §4.4 的突袭接口，不再有 `sim.raid_*`）：

| 函数 | 说明 |
|---|---|
| `raid.begin(state, loc_id, squad) -> raid` | 由 C8 的地点数据实例化副本：布局变体、容器内容、NPC 位置与日程、门锁 |
| `raid.commit(state, raid, result)` | `result = { loot = {...}, wounds = {...}, deaths = {...}, deeds = {...}, minutes_used = n, exit = "evac"|"timeout"|"wiped" }` 写回模型；`deeds` 经 C6 记录 |
| `raid.autoresolve(state, loc_id, squad, policy) -> result` | 不进副本的抽象结算，与 `begin` 用同一批容器和风险参数；机器人和批量模拟用它 |

P0 用 M3 `expedition` 的逻辑实现 `autoresolve` 的第一版，`begin/commit` 只定形状。M3 的机器人改为调用 `raid.autoresolve`，`expedition.lua` 删除。

### C8 地点数据（拥有者：WORLD）

```lua
world.locations[id] = {
  id, archetype, variant,                 -- id = 原型 id（WORLD §1.3）；布局变体（data/locations/<原型>.lua，格式见 M2-PLAN §2.1）
  occ = "empty"|"civilian"|"trader"|"hostile",   -- 占用，WORLD §6.1、§8 的 loc.<id>.occ
  state = "unknown"|"known"|"visited"|"hostile"|"empty"|"friendly"|"burned",   -- WORLD §8 的 loc.<id>.state
  unlocked = bool, unlock_day = n | nil, travel_min = n,   -- 单程分钟，WORLD §1.3；条件解锁（线索）的 unlock_day 为 nil
  raid_difficulty = 1..5,                 -- 夜袭难度，WORLD §6.1
  guard = 0..3, attitude = -3..3, food_days = n, members_alive = n, visits = n, looted = n,   -- WORLD §8 的 loc.<id>.*
  containers = { [slot_id] = { items = {...}, locked = bool, searched = bool } },
  households = { household_id... }, npcs = { npc_id... },
  doors = { [door_id] = { locked = bool, broken = bool } },
  last_raided_day = n | nil,
}
```

RAID 只读这张表（加上 `raid.commit` 写回 `containers`、`doors`、`last_raided_day`）。RAID 在 WORLD 完成前用 `tests/fixtures/locations/*.lua` 手写的地点开发。

### C9 片段挂点（拥有者：STORY；各场景调用）

- 场景在固定时机调用 `story.pick(slot, ctx) -> instance | nil`，返回非空时压入 `ui/dialog` 模态。STORY 完成前 `story.pick` 恒返回 nil。
- 挂点名冻结（NARRATIVE §2.7）：`door_day`、`radio`、`dawn`、`dusk`、`home_idle`、`raid_enter`、`raid_found`、`travel`、`dream`、`talk`、`crisis`（共 11 个）。`ctx` 至少含 `state`、`loc`、`chars`；各挂点的附加字段写在 `sim/story.lua` 的文件头里。
- `ui/dialog.lua` 归 STORY（UI-UX §8.8 的选项、灰显原因）。

## 3. 各线的范围与文件归属

“拥有”的文件只有本线修改；“使用”的文件只读。不在表里的新文件按目录归属判断。

### 3.1 HOME — 家园可玩（M4）

- 范围：`scenes/home.lua`、`scenes/dusk.lua`、`scenes/dawn.lua`；选人、点击寻路、直接移动、交互与任务队列（UI-UX §6.1–§6.8）；`ai/home_tasks.lua`；清理瓦砾与挖掘；家园 HUD（`ui/hud_home.lua`）；`view/select.lua`、`view/interact.lua`、`view/camera_ctl.lua`；`sim/cmd/home.lua`、`sim/cmd/night.lua`（黄昏安排）。
- 拥有：上面的文件；`data/homes/`；i18n 的 `home`、`dusk`、`dawn` 区。
- 使用：`view/mapbuild/actors/facing/lightfov`（M2）；`sim/` 的 M3 模块；PANEL 的面板（未完成时用 P0 的空壳占位）。
- 验收：PLAN §6 的 M4 行；三种输入的“白天”探针（`loop_keyboard/mouse/pad.lua` 的白天部分）。

### 3.2 PANEL — 面板与控件

- 范围：
  1. 控件：UI-UX §4 中 M1 未做的 `IconButton`、`List`、`ItemGrid`、`ProgressBar`、`Tooltip`、`Modal`、`Confirm`、`Radial`、`Stepper`；`ui/hintbar.lua`、`ui/glyphs.lua`。**可以现在开工。**
  2. 面板：背包、制作、科技、日志、角色详情（`ui/inventory|craft|tech|journal|character.lua`），全部按 C5 接口，用 P0 夹具和 C4 查询开发；开发面板外壳 `ui/devpanel.lua`（STORY 往里加页签）。
- 拥有：`ui/` 下除 `dialog.lua`、`hud_home.lua`、`hud_raid.lua` 以外的文件；`ui/theme.lua` 的 `layout` 表；i18n 的 `ui` 区。
- 验收：每个控件和面板在纯键盘、纯鼠标、纯手柄下可完成 UI-UX §8 对应流程（探针）；三语截图无溢出；焦点可达性校验（UI-UX §5.7）通过。

### 3.3 WORLD — 世界生成、大地图、交易（M5）

- 范围：`sim/worldgen.lua`（预算制，CONTENT §9）、`sim/locations.lua`、`sim/trade.lua`、`sim/factions.lua`、上门商贩；`scenes/worldmap.lua`、`scenes/trade.lua`；首批 6 个地点原型模板（`data/locations/`）；`sim/cmd/trade.lua`、`sim/cmd/travel.lua`；C8 的正式实现；`raid.autoresolve` 的容器与风险参数改用真实地点。
- 拥有：上面的文件；`data/locations/`、`data/loot.lua`、`data/traders.lua`、`data/factions.lua`；i18n 的 `world`、`trade`、`loc` 区。
- 验收：PLAN §6 的 M5 行（100 个种子每幕资源 ±10%；能完成一笔交换；声望差被赶走）。

### 3.4 RAID — 潜行、战斗、伤亡（M6 → M7）

- 范围：`scenes/raid.lua`（含防守模式）、`ai/perception.lua`、`ai/npc_fsm.lua`、`ai/squadmate.lua`、`sim/raid_rules.lua`、`sim/raid_resolve.lua`、`sim/cmd/raid.lua`、撬锁/搜刮/撤离、迟归惩罚、`ui/hud_raid.lua`；M7 的近战、枪械、制服、威吓、伤势与救援、死亡、打击反馈。C7 的正式实现。
- 拥有：上面的文件；`data/` 里潜行与战斗数值所在段（CONTENT §7，放 `data/raid.lua`，不放进 `balance.lua`）；i18n 的 `raid`、`combat` 区。
- 使用：C8（WORLD 完成前用手写夹具地点）；C6（行为一律经 `deeds.record` 记账）；C9（`raid_enter`、`raid_found` 挂点调用 `story.pick`）。
- 验收：PLAN §6 的 M6、M7 行。

### 3.5 STORY — 叙事引擎（M8）

- 范围：NARRATIVE §2.9 表中全部模块（`facts`、`deeds` 的完整实现、`cond`、`effects`、`reactors`、`psyche`、`households`、`rumor`、`story`、`director`、`lint`）；`ui/dialog.lua`；开发面板的叙事页签；首批 42 个片段与三族规则（`data/storylets/`、`data/reactors/`）；`sim/cmd/story.lua`。
- 拥有：上面的文件；`data/values.lua`、`data/deed_kinds.lua`；i18n 的 `story`、`char` 区。
- 验收：PLAN §6 的 M8 行。剧本化测试用 C6 手写行为序列，不依赖 RAID 完成。

### 3.6 ART — 美术批量

- 前提：M2 的 A5 风格评审通过。
- 范围：按 ART-AUDIO 资产清单一次写齐 genai 规格和 chargen 角色配置，批量生成，产物替换占位图（文件名、尺寸、格位不变，代码零改动）。
- 拥有：`assets/sprites/`、`assets/textures/`、`assets/ui/`（图片）、`assets_src/`、`tools/art/`；pixel-hero-demo 侧只新增文件。
- 合并：资产文件是二进制，ART 线是唯一修改者，所以不会冲突。其他线需要新资产时，先在 `assets_src/art.json` 登记占位条目并生成程序占位图，ART 线据此出正式图。

## 4. 共享文件规则

| 文件 | 规则 |
|---|---|
| `assets/i18n/<lang>/<area>.lua` | 每个 area 只归一条线（§3）。`core`、`ui_common` 区归主代理，要往里加通用词条的线在合并请求里列出，由主代理合并 |
| `assets/fonts/*` | 二进制，冲突时不手工选版本：合并后运行 `python3 tools/bake_font.py` 重新烘焙（输出是确定性的），再提交 |
| `sim/events.lua`、`data/deed_kinds.lua` | 只追加，写在自己域的段末尾 |
| `data/balance.lua` | 按 M3 的段落归属：需求、温湿度、电力、天气归 HOME；交易归 WORLD；夜袭防御值（CONTENT §5.5）归 RAID。只改自己的段 |
| `core/*.lua` | 归主代理。任何一条线需要改 core，先提出，由主代理在 main 上改再各线合入 |
| `build.zig`、`ci/` | 归主代理。新增构建步骤或探针入口在合并请求里列出 |
| `README.md` 状态行与 API 表 | 各线不改；主代理在每次合入 main 后统一更新 |
| `docs/PLAN.md` | 各线只改自己里程碑那一行的“已完成”标注；其余由主代理改 |
| `tests/probe/*.lua`、`tests/lua/test_*.lua` | 文件名带线名前缀（`home_*.lua`、`raid_*.lua` …），runner 自动发现，互不冲突 |

## 5. 合并与契约变更

- **main 是集成分支**，始终保持 PLAN §7 全绿。各线每天至少把 main 合并进自己的分支一次；向 main 合并必须先在本线跑完 PLAN §7 全部命令，并附截图（看画面的改动）。
- **合并顺序**：同时有多条线要合入时，按 P0 → PANEL → HOME → WORLD → RAID → STORY → ART 的顺序，后合的负责解决冲突。
- **契约变更**：需要改 §2 某条契约时，提出方写一段“改什么、为什么、影响哪些线”，交主代理裁决。批准后由主代理在 main 上改契约代码并通知各线合入，**任何线不得在自己的分支里私自改契约**。只是在自己子树里加字段、给自己域加命令或事件，不算契约变更。
- **试玩检查点**：
  - M4 检查点：HOME + PANEL 合入 main 后，用户试玩“在家过 3 天”。
  - M6 检查点：HOME + WORLD + RAID（M6 部分）合入 main 后，用户试玩完整昼夜循环。
- **M9 之后**：M9（哨站线与结局）同时依赖 STORY、WORLD、RAID，等三者合入后再开线；M10、M12 回到单线推进。

## 6. 风险

| 风险 | 应对 |
|---|---|
| 夹具状态和真实游玩状态不一致，面板在夹具上正常、接进家园后出错 | 夹具由机器人真实跑出来，不手写；状态版本变化时重建；HOME 合入前用真实流程再跑一遍 PANEL 的探针 |
| RAID 用手写地点开发，和 WORLD 生成的地点对不上 | 手写地点也必须通过 C8 的校验函数；WORLD 合入后 RAID 的探针改用生成的地点再跑一遍 |
| STORY 的条件/效果需要别的子树数据而查询层没有 | 走契约变更流程加查询函数，不直接读别的子树 |
| 多线同时改 `data/balance.lua` | 按段归属；M10 调优时由一条线统一改 |
| 契约冻结太早，后面发现不够用 | P0 只冻结签名和顶层字段，内部字段各线自由扩展；变更走 §5 流程，成本可控 |
