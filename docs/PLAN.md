# 《零下三十 / Thirty Below / 영하 삼십》（暂名）总计划 v1

工程目录 `~/dev/winter_survival`（包名 `winter_survival`）。基于 Delve Framework（Zig 0.16 + Sokol + Lua 5.4），由 `~/dev/delve-starter` 脚手架生成，遵循 `delve-dev` 技能的全部约定。

## Context（为什么做、做成什么）

要做一款俯视等距 2.5D 的寒冬末日生存游戏：一场史无前例的寒潮在半年内摧毁了现代文明，舞台是美国中西部的一座虚构小镇。玩家带 4 名各有特长与缺点的幸存者（人数会动态增减），白天在半毁的房子里整理、修设备、做饭、交易，夜晚派 1–2 人去别处偷窃或掠夺，在 30 天里熬过数次小寒潮和最后的大寒潮。游戏的核心不是战斗，而是**稀缺逼出来的道德抉择以及世界对这些抉择的记忆**。

本计划于 2026-11-14 获批。工程已由脚手架生成（M0），各章节已拆分为下表中的文档，之后按 §6 的里程碑实施。

探查结论（决定了计划的形状）：

- 脚手架给了等距地图、实体、A* 寻路、相机、点击拾取、Lua 热重载、音频、headless 探针测试和 CI，这些直接复用。
- 脚手架**没有**：中/韩文文本（只有 8×8 ASCII 调试字体）、UI 控件、存档、光照/视野、多图块高亮、手柄、鼠标滚轮；地形单批 1 万 quad 上限；Lua VM 用 Arena 分配器（长时间运行内存只增不减）。这些是 M1–M2 的引擎扩展。
- 美术管线：genai 只出单张静帧；多方向行走表靠脚本生成（`sprites/walk.py`、`gen_assets.py`）。音频管线可直接用。

---

## 文档索引

| 文档 | 内容 | 读者 |
|---|---|---|
| `docs/PLAN.md`（本文） | 总计划：背景、核心决策、技术架构、里程碑、验证、风险 | 所有人；子代理接任务前必读 §0 |
| `docs/GDD.md` | 游戏设计：世界观、单局结构、角色、家园、科技、交易、大地图、潜行、战斗、哨站、结局；输入系统 | 玩法与 UI 实现者 |
| `docs/NARRATIVE.md` | 叙事与道德系统：设计原理与 Lua 架构（事实黑板 / 行为账本 / 反应规则 / 故事片段 / 导演） | `sim/` 叙事模块实现者、内容作者 |
| `docs/CONTENT.md` | 经济与数值目录：物品、配方、科技节点、设施、模拟常数、潜行战斗数值、交易、战利品预算 | `sim/` 与 `data/` 实现者、平衡调优 |
| `docs/WORLD.md` | 人物与世界：时间线、三维价值观、10 张角色卡与三段式个人线、19 个具名 NPC、势力、18 个地点原型、哨站主线、事实键、反应规则、首批 42 个片段、结局 | 叙事实现者、内容作者 |
| `docs/UI-UX.md` | 界面与交互规格：屏幕清单、HUD 布局、控件与焦点导航、三种输入方式的操作流 | UI 实现者 |
| `docs/ART-AUDIO.md` | 美术与音频规格：色卡、尺寸、人物生成器、资产清单、音频清单 | 美术与音频管线 |
| `docs/ENGINE-PLAN.md` | 引擎扩展设计（Zig 侧）：接口、Lua API、单元测试、子任务 X1–X18 | Zig 实现者 |
| `docs/ENGINE-BASE.md` | 脚手架继承的 iso-base 引擎原始计划（现有 Zig 代码的出处） | Zig 实现者 |
| `docs/CI-PLAN.md` | Jenkins 流水线 | CI 维护 |

文中 §N 指本文章节；跨文档引用写作 `GDD §1.9`、`NARRATIVE §2.4`、`ENGINE-PLAN §A3` 等。

---

## 0. 核心设计决策（已确认，子代理不得更改）

| # | 决策 | 来源 |
|---|---|---|
| D1 | 夜间外出 1–2 人小队，副本内可切换操控，另一人跟随/待命/望风 | 用户确认 |
| D2 | 战斗为实时 + 可暂停，近战为主，枪械稀有且噪音巨大 | 用户确认 |
| D3 | 10 名幸存者的角色池，每局随机抽 4 人开局，其余以访客/可招募者/NPC 出现 | 用户确认 |
| D4 | Hi-bit 高精度像素：地块顶面贴图 64×64，屏幕上呈 128×64 菱形；人物 64×96；图标 32×32；头像 96×96；约 56 色废土色卡；最近邻采样 | 用户确认 |
| D5 | 人物 4 朝向，定义为屏幕四个斜向（东南/西南/东北/西北），西侧两向由东侧镜像，实际只画 2 向；行走表由脚本生成 | 用户纠正后确定 |
| D6 | 相机 yaw 锁定 45°、pitch 30°，不提供旋转（家具与人物只有一个视角的美术） | 本计划 |
| D7 | 时间：现实 1 秒 = 游戏 1 分钟。白天 06:00–19:00（可提前结束），夜晚 21:00–05:00，05:00 前未到家有受伤惩罚 | 用户指定 |
| D8 | 三种输入方式各自都能完整通关：键鼠（完整可改键快捷键）、纯鼠标、纯手柄 | 用户指定 |
| D9 | 语言：中文 / English / 한국어，运行时可切换；所有文本走键值表，代码和数据里不出现面向玩家的字面文本 | 用户指定 |
| D10 | 模拟核心是**纯 Lua、不依赖引擎 API** 的确定性模型；场景只是它的视图和输入。存档 = 序列化模型状态 | 本计划 |
| D11 | 叙事用"事实黑板 + 行为账本 + 反应规则 + 故事片段"的数据驱动架构（NARRATIVE §2），条件和效果用可校验的表 DSL，不用散落的 if | 本计划 |
| D12 | 不修改 `delve-framework`。引擎扩展全部写在游戏仓库的 `src/` 里 | delve-dev 技能 |
| D13 | 这是原创作品：原创的世界观、人物、地点、美术和文本，不复刻任何现有游戏的名称、角色、关卡或外观 | 本计划 |
| D14 | 自杀、抑郁等内容只以文字和离屏方式呈现，不做画面描写；设置里提供"温和叙述"开关 | 本计划 |

---

## 4. 技术架构

### 4.1 分层

```
Zig   delve-framework（只读）
        ▲
      src/iso  世界：地图、实体、寻路、视线、光照、分块渲染、自建 Lua VM
      src/kit  界面与外设：文本、UI 绘制、输入边沿、手柄、音频、存档、探针
        ▲  Lua 绑定：iso / ui / audio / sys / kit_input / pad / kit_probe
Lua   core    基础设施：随机流、序列化、存档、i18n、场景栈、输入动作、事件总线
      data    内容表：物品、配方、科技、角色、地点模板、片段、规则、数值
      sim     纯模型：只依赖 core 和 data，不 require 任何引擎库（D10）
      view / ai / ui / scenes   表现、NPC 行为、界面、场景：依赖 sim，反向不允许
```

依赖方向由测试强制：`tests/lua/test_layering.lua` 扫描 `sim/` 和 `data/` 下的 `require`，出现 `iso`、`ui`、`audio`、`sys`、`pad`、`kit_*` 即失败。

### 4.2 引擎扩展（Zig）

完整的接口定义、Lua API 表、单元测试清单和 X1–X18 子任务见 `ENGINE-PLAN.md`。要点：

| 缺口 | 方案 |
|---|---|
| Lua 内存只增不减 | 游戏自建 Lua VM（`src/iso/vm.zig`），用计数分配器，照搬框架的库绑定逻辑；不改框架 |
| 中/韩文文本 | `tools/bake_font.py` 离线扫描 i18n 表烘焙字形图集 + 二进制度量文件；运行时只做 UTF-8 解码、度量、换行（含中文禁则、韩文按空格断行）和出四边形 |
| UI | 新 Lua 库 `ui`：带透明度的矩形、图片、九宫格、文本、CPU 裁剪；控件和焦点导航在 Lua 里做 |
| 地形 1 万 quad 上限 | 16×16 分块批次，按块置脏和剔除；地图上限 128×128 |
| 光照与视野 | 每格光照（环境光 + 最多 64 个带遮挡的点光源）乘进顶点色，角点平均做平滑；统一的视线函数 `los`；16 个可见性掩码承载 FOV、战争迷雾和可达区域 |
| 多图块高亮 | 16 组覆盖层（视锥、选中、噪音圈、可达范围） |
| 实体 | 带代数的 id（旧 id 永久失效）、可见性、点击拾取、自动受光、路径上限 256 |
| 像素基准 | 相机改为固定每世界单位 90.51 px：顶面菱形 128×64 px，每级高度 32 px，人物 64×96 px 按 1:1 显示；相机和精灵吸附到整数像素；缩放只取整数倍 |
| 手柄 | `src/kit/gamepad.zig`：Linux 读 `/dev/input/js*`，Windows 动态加载 XInput，探针可注入虚拟手柄 |
| 输入边沿 | 自算按键/鼠标的"松开"、"本帧按下了哪个键"、"最近使用的设备" |
| 环境音 | 音频扩为 4 个通道：1 条音乐 + 3 层环境音，新增 `amb` 总线 |
| 存档 | Lua 库 `sys`：建目录、原子写、列表、删除 |
| Lua 单元测试 | `zig build luatest`：headless 下不启动游戏，直接跑 `tests/lua/test_*.lua` |

墙体约定（由像素基准推出）：每级高度 32 px，人物高 96 px 即 3 级。夜间室内用"剖面墙"2 级（64 px，到人物胸口，不遮挡），白天外观用 6 级实墙加屋顶。同一份地点模板按 `exterior` / `cutaway` 两种模式生成地图。墙占满一格；门是墙线上的 0 高度格加一个门实体（关 = `blocked` + `opaque`）；窗是不可通行但不挡视线的墙格。

### 4.3 Lua 目录结构

```
assets/
  main.lua                    引导：读设置、装载字体与 i18n、启动场景栈
  i18n/{zh,en,ko}.lua         文本表（zh 为源语言）
  scripts/
    core/   rng.lua serialize.lua save.lua i18n.lua scene.lua bus.lua input.lua log.lua util.lua
    data/   balance.lua items.lua recipes.lua tech.lua characters.lua values.lua
            loot.lua traders.lua factions.lua weather.lua endings.lua
            locations/<原型>.lua      布局模板（字符网格 + 图例 + 容器/NPC 槽位）
            homes/<布局>.lua
            storylets/<类别>.lua      片段
            reactors/{psyche,social,world}.lua
    sim/    sim.lua state.lua clock.lua commands.lua
            chars.lua needs.lua health.lua psyche.lua relations.lua
            inventory.lua craft.lua tech.lua home.lua thermal.lua power.lua
            weather.lua worldgen.lua locations.lua households.lua trade.lua factions.lua rumor.lua
            facts.lua deeds.lua cond.lua effects.lua reactors.lua story.lua director.lua
            raid_rules.lua raid_resolve.lua night_home.lua militia.lua endings.lua
            bot.lua lint.lua
    view/   mapbuild.lua actors.lua facing.lua camera_ctl.lua select.lua interact.lua
            lightfov.lua fx.lua weather_fx.lua
    ai/     npc_fsm.lua perception.lua squadmate.lua home_tasks.lua
    ui/     widgets.lua focus.lua theme.lua glyphs.lua hintbar.lua radial.lua
            hud_home.lua hud_raid.lua inventory.lua craft.lua tech.lua trade.lua
            dialog.lua journal.lua tooltip.lua settings.lua rebind.lua devpanel.lua
    scenes/ title.lua newrun.lua home.lua dusk.lua worldmap.lua raid.lua trade.lua
            dawn.lua ending.lua
tests/
  lua/    test_*.lua mc_balance.lua runner.lua main.lua
  probe/  smoke.lua loop_keyboard.lua loop_mouse.lua loop_pad.lua save_roundtrip.lua
          engine_ext.lua ui_text.lua soak_heap.lua
```

### 4.4 模型核心接口

**状态根**（`sim/state.lua`，整棵树只含数字、字符串、布尔和表，可直接序列化）：

```lua
state = {
  version = 1, seed = 0, rng = { story = {...}, loot = {...}, combat = {...}, worldgen = {...} },
  clock   = { day = 1, minute = 360, phase = "day" },          -- phase: day/dusk/night/dawn/ending
  party   = { order = {...}, chars = { [id] = Char } },
  home    = { layout = "ranch_a", rooms = { [id] = Room }, stations = { [id] = Station },
              humidity = 45, power = {...}, stash = Inventory },
  weather = { outdoor_temp = -15, snaps = { { start_day, days, severity, announced } }  -- severity 1..4，4 = 大寒潮, forecast = {...} },
  world   = { locations = { [id] = Location }, npcs = { [id] = Npc }, factions = { [id] = { rep } }, notoriety = 0 },
  tech    = { unlocked = {...}, blueprints = {...} },
  story   = { facts = {...}, deeds = {...}, scheduled = {...}, cooldowns = {...}, tension = 0 },
  night   = { roles = { [char] = "out"|"guard"|"sleep" }, target = nil, loadout = {...} },
  stats   = {...},
}
```

**驱动接口**（`sim/sim.lua`）：

| 接口 | 说明 |
|---|---|
| `sim.new(seed, opts) -> state` | 抽角色、生成世界、排寒潮日程 |
| `sim.step(state, minutes)` | 以 1 游戏分钟为步长推进：时钟、需求、任务、温湿度、电力、疾病、心理衰减 |
| `sim.command(state, cmd) -> ok, err` | 玩家对模型的**所有**改动都走命令（派活、吃喝、制作、交易、定夜间角色、选片段选项）。场景和机器人用同一套命令 |
| `sim.advance_phase(state)` | 时段切换：黄昏结算、夜间结算、黎明推进住户/传闻/排期 |
| `sim.raid_begin(state, loc, squad) -> raid` | 建立副本的临时状态（NPC、容器、门） |
| `sim.raid_commit(state, raid, result)` | 把战利品、伤亡、行为记录、耗时写回模型 |
| `sim.raid_autoresolve(state, loc, squad, policy)` | 不进副本的抽象结算，供机器人和批量模拟用，与实际副本共用同一批容器和风险参数 |
| `bus.on(evt, fn)` / `bus.emit(evt, data)` | 模型向外通知（`char_died`、`storylet_ready`、`snap_warning` 等） |

副本的实时部分（移动、视线、噪音）必须调用引擎，放在 `scenes/raid.lua` 和 `ai/`；判定公式（被发现的概率、噪音半径、伤害、威吓判定）是 `sim/raid_rules.lua` 里的纯函数，可单测。

### 4.5 存档

- `core/serialize.lua` 把状态树写成确定性的 Lua 字面量文本（键排序），经 `sys.save_write` 原子写入 `saves/`。
- 文件：`run_1..3.sav`（3 个存档位，备份为 `run_N_prev.sav`）、`settings.sav`（含语言、音量、改键）、`meta.sav`（局外进度）。
- 只在时段边界自动存档（黎明、黄昏），每个存档位同时保留上一个边界的备份一份。中途退出，回来从最近的边界继续，不提供时段内读档，也不做挂起存档（R-U9）。
- 带 `version` 字段和迁移表；读档后跑一遍结构校验，坏档给出提示而不崩溃。

### 4.6 多语言

- `T(key, vars)` 取文本，占位符 `{name}`；英文复数规则单独处理。
- 中文是源语言；英文和韩文由子代理翻译，M12 做一轮人工可读性复查。
- `tools/i18n_check.py`：三语键完全一致、占位符一致、无未使用键；`tools/bake_font.py --check`：三语用到的字符都在图集里。两者都接进 `assets.py check` 和 CI。
- 界面布局按最长语言留量，控件用自动换行文本框，不写死宽度。

### 4.7 测试体系

| 层 | 命令 | 覆盖 |
|---|---|---|
| Zig 纯逻辑 | `mise exec -- zig build test` | 相机、地图、寻路、视线、光照、网格、文本、UI 几何、手柄逻辑（ENGINE-PLAN §A5） |
| Lua 单元 | `mise exec -- zig build luatest -Dbackend=headless` | `sim/` 各模块、DSL、序列化往返、分层约束、`lint.run()` |
| 探针 | `mise exec -- zig build probe -Dbackend=headless -Dprobe=tests/probe/<x>.lua` | 冒烟、三种输入各走完整一天、存读档、引擎扩展模糊测试、内存浸泡 |
| 批量模拟 | `mise exec -- zig build balance -Dbackend=headless` | 500 局机器人对局，输出 `out/balance/report.json` 与网页报告 |
| 静态校验 | `python3 tools/assets.py check` | 资产、音频 id、i18n、字体覆盖、输入覆盖 |
| 画面 | Windows GPU 运行器上 `ci/smoke.py` 截图 | 像素尺寸、三语文本、界面叠放（headless 测不了像素） |

**平衡目标**（普通难度，M10 调到位；数值都在 `data/balance.lua`）：

| 指标 | 目标 |
|---|---|
| 谨慎型机器人（交易 + 只偷空屋和敌对据点）活到第 30 天 | 35–55% |
| 消极型（夜里从不外出） | 低于 5% |
| 冷酷型（见谁抢谁）活到第 30 天 | 55–75%，但 80% 以上的局出现至少一次心理危机，终局平均人数更少 |
| 每幕每类资源总量 | 各种子之间偏差 ±10% 以内 |
| 第 10、20 天的食物存量中位数 | 1–3 天的量 |
| 第 10、20 天的燃料存量中位数 | 1–3 天的量 |
| 每个结局 | 至少被一种机器人在 5% 以上的局达成 |
| 每个片段 | 500 局里至少触发 1 次 |
| 单局内重复出现的有选项片段 | 0 个（导演冷却保证） |
| 随机两局有选项片段的重合率 | 低于 50%；达不到时才补写片段，不预先铺量 |

---

## 6. 里程碑

实施流程按全局约定：主代理出子任务计划片段和验收标准 → `coder-sonnet`（核心、跨文件）或 `coder-haiku`（机械、单文件）编码 → `code-reviewer` 审查 → 最多两次返工，仍不过则主代理亲自修或请用户决策。所有子代理用 medium 思考强度。每个里程碑结束时主代理跑 §7 的验收清单并向用户报告。

| 里程碑 | 目标 | 主要任务（负责代理） | 验收 |
|---|---|---|---|
| **M0 脚手架** | 可构建、可测试的空工程 | `python3 tools/new_game.py winter_survival --dest ../winter_survival --title "Thirty Below" --git`；把计划拆存为"文档索引"中的各文档，补写 `CONTENT.md`、`UI-UX.md`、`ART-AUDIO.md`；git-daemon 导出本仓库并建 Jenkins 任务 `winter_survival`。代码保持脚手架示例，冒烟探针沿用脚手架的 `tests/probe/smoke.lua`，M1 换掉示例场景时一并改写（**已完成，2026-11-14**） | 构建、测试、冒烟探针全过；`timeout 8` 运行无 panic、无 Lua 错误、无泄漏 |
| **M1 引擎 A + Lua 基础设施** | 能显示三语界面，三种设备能操作，能存档 | ENGINE-PLAN 的 X1、X10–X12、X14–X17（sonnet/haiku）；`core/` 全部模块（sonnet）；`ui/widgets.lua` + `ui/focus.lua` + `core/input.lua` + 改键界面（sonnet）；标题与设置场景（haiku）（**已完成，2026-11-14**；验收时用 Xvfb 截图发现并修复了 UI 贴图上下颠倒和绘制段串纹理两个问题） | 截图里中/英/韩文正确显示；纯键盘、纯鼠标、纯手柄都能从标题进设置、改语言、改键并保存；内存浸泡探针通过 |
| **M2 引擎 B + 地图表现** | 能把模板变成带光照和视野的等距场景 | X2–X9、X13、X18（sonnet/haiku）；`view/mapbuild.lua`、`view/actors.lua`、`view/facing.lua`、`view/lightfov.lua`（sonnet）；最终尺寸的占位美术（haiku）；正式美术试点：色卡、1 名角色全套精灵表、约 12 个地块格、约 6 个 genai 规格（详见 `M2-PLAN.md`） | 截图量得菱形 128×64、人物 64×96；64×64 带墙地图无 quad 超限警告；夜间光照、视锥覆盖层、战争迷雾可见；用户确认美术试点风格 |
| **M3 模拟核心** | 无画面跑完 30 天 | `sim/` 的时钟、命令、角色、需求、伤病、物品、制作、科技、家园温湿度电力、天气寒潮（sonnet）；`data/` 首批内容表（haiku）；`sim/bot.lua` 与 `zig build balance`（sonnet） | `luatest` 全过；机器人跑完 30 天无报错；同种子两次结果逐字节相同；存读档往返后继续跑结果一致 |
| **M4 家园可玩** | 垂直切片一：在家过 3 天 | `scenes/home.lua`、选人与寻路与直接移动、交互与任务队列、`ai/home_tasks.lua`、HUD、背包/制作/科技界面、清理瓦砾与挖掘、黄昏与黎明界面（sonnet 为主） | 三种输入的"白天"探针通过；能清理房间、修好加热器、做饭、睡觉，室温随操作变化 |
| **M5 大地图、世界生成、交易** | 能出门、能换东西 | `sim/worldgen.lua`（预算制）、`sim/locations.lua`、`scenes/worldmap.lua`、`scenes/trade.lua`、`sim/trade.lua`、上门商贩（sonnet）；6 个地点原型的模板（haiku） | 100 个种子的每幕资源总量都在 ±10% 内；白天能去交易点完成一笔交换，声望差时被赶走 |
| **M6 夜间潜行** | 垂直切片二：完整的昼夜循环 | `scenes/raid.lua`、`ai/perception.lua`、`ai/npc_fsm.lua`、`ai/squadmate.lua`、`sim/raid_rules.lua`、撬锁/搜刮/撤离、迟归惩罚、`ui/hud_raid.lua`（sonnet） | 三份完整循环探针（GDD §3.5）全过；NPC 的视锥显示与实际发现判定一致；超时回家会受伤 |
| **M7 战斗与伤亡** | 打得起来，也死得了人 | 实时可暂停的近战与枪械、制服与威吓、伤势与救援、死亡、打击反馈（sonnet） | 探针：背后制服不惊动他人；枪声惊动全图；队员死亡后模型状态和界面正确 |
| **M8 叙事引擎** | 世界会记账 | `sim/` 的 facts、deeds、cond、effects、reactors、psyche、households、rumor、story、director、lint；开发面板；首批 40 个片段和三族规则（sonnet；主代理亲审设计与样例） | `lint.run()` 无错；剧本化测试：偷有人家 → 3 天内出现后续 → 角色反应因价值观而异 → 归还后心理回升；片段"为何未触发"可在面板查看 |
| **M9 哨站线与结局** | 一局能打完 | `sim/militia.lua`、哨站地点与任务、四类结局与逐角色尾声、局外进度（sonnet） | 机器人能分别达成四类结局；尾声文本正确引用本局发生过的事 |
| **M10 内容与平衡** | 内容量和数值到位 | 18 个地点原型 × 2–3 套模板、片段池约 80 个（§10.6）、全部配方与科技、10 条三段式角色线（haiku 铺量，sonnet 审逻辑）；数值调优 | §4.7 的平衡目标全部达标；无从未触发的片段 |
| **M11 正式美术与音频** | 换掉占位 | M2 试点定风格后，按资产清单一次写齐全部规格、一次批量生成，从 M3 起并行；M11 负责补缺、替换与评审：地块、人物、道具、图标、头像、UI 皮肤、音频清单 | `assets.py check` 全过；主代理逐场景截图检查辨识度：人物与地面、可交互物与背景、敌我区分 |
| **M12 打磨与发布** | 可交付 | 新手引导提示、难度修正项、温和叙述开关、性能、三语复查、Windows 构建 | Windows 运行器上冒烟与截图通过；连续 2 小时运行内存稳定；三语无缺字、无溢出 |

M4 和 M6 结束时各有一次给用户试玩的检查点。

---

## 7. 验证（每次改动后与每个里程碑结束时）

```bash
cd ~/dev/winter_survival
mise exec -- zig build                                   # 无错误无警告
mise exec -- zig build test                              # Zig 纯逻辑
mise exec -- zig build luatest -Dbackend=headless        # Lua 单元 + lint + 分层约束
mise exec -- zig build probe -Dbackend=headless -Dprobe=tests/probe/smoke.lua
mise exec -- zig build probe -Dbackend=headless -Dprobe=tests/probe/loop_mouse.lua     # 以及 loop_keyboard / loop_pad
mise exec -- zig build balance -Dbackend=headless        # M3 起；M10 对照平衡目标
python3 tools/assets.py check                            # 资产、i18n、字体、输入覆盖
timeout 8 ./zig-out/bin/winter_survival --no-audio       # 无 panic、无 Lua error、无泄漏报告
```

- 看画面的项目必须截图确认，不凭日志下结论。
- 纯逻辑 Zig 文件不 import graphics/app/input；`sim/` 与 `data/` 不 require 引擎库。
- 日志含 NUL 字节，检索用 `grep -a`。

---

## 8. 风险

| 风险 | 应对 |
|---|---|
| 范围过大 | 两个垂直切片（M4、M6）先证明核心循环；内容铺量放到 M10，数据驱动使铺量不动代码；任何里程碑可按"少几个地点/片段"收缩而不影响结构 |
| 脚本生成的 64×96 人物不够精细 | M2 先出一名角色的全套动作让用户过目；骨架驱动 + pixelflow 着色；关键帧可用 Aseprite 人工修整；不行就降为更少动作帧换更高单帧质量 |
| 道德系统流于数值 | NARRATIVE §2.2 八条原则作为每个片段的评审清单；M8 的剧本化测试验证"延迟但可追溯"；首批片段由主代理亲审 |
| 心理系统形成死亡螺旋 | 预警期、修复途径、导演的张力修正；批量模拟统计"崩溃后无法挽回"的局占比并设上限 |
| Lua 性能（12 个 NPC + 模型 + 界面） | 视线、FOV、光照、寻路都在 Zig；NPC 感知 10 Hz；界面避免每帧拼接大量字符串 |
| 三语文本量大（§10.6 收缩范围后估计每种语言 8,000–10,000 词） | 中文为源；键值表 + 校验工具；翻译分批随内容里程碑进行 |
| headless 测不了像素 | 画面类验收走 Windows GPU 运行器截图 |
| 字体 | 默认用本机已有的 Noto Sans CJK（OFL）烘焙；M11 评估换成覆盖简中和韩文的像素字体，授权确认后再用 |
| 非 Xbox 布局手柄的键位不同 | 设置里提供校准界面，映射存入设置 |
| 框架内部布局变化 | 分块渲染启动自检（ENGINE-PLAN §A7.1 第 3 条）；CI 固定框架版本 |

---

## 9. 开放项与跨仓库改动

实施到相应步骤时再向用户确认，不阻塞开工：

1. **游戏名**：《零下三十 / Thirty Below》是暂名。
2. **鼠标滚轮**：需要给 `delve-framework` 打约 12 行补丁。本计划不依赖它（纯鼠标玩法用按钮和拖拽）。要不要加，届时再问。
3. **pixel-hero-demo 的改动**（只新增、不改现有行为）：`genai/specs/` 下新增本作的规格文件；`presets.json` 新增一个弱化像素 LoRA 的预设；废土色卡放在本仓库，用 `genai.pixelize --palette` 在本地对归档的原始静帧做像素化，不改 Jenkins 流水线。
4. **难度档位**的数量与差异，M10 定（CONTENT 的数值均为普通档）。
5. **像素字体**：默认用 Noto Sans CJK（OFL 1.1）烘焙。若改用像素字体（候选 Fusion Pixel、Galmuri、Zpix），须先由用户确认并逐个核对许可证；烘焙产物命名为 `ui_*`，不沿用字体名（OFL 保留字体名条款）。
6. **pixel-hero-demo 的其它新增需求**（只新增）：pixelflow 新增雪、冰、霜、混凝土、沥青、地毯、瓷砖、瓦砾、锈斑、保温层、焦痕纹理；`compose` 新增稀疏氛围风格 `ambient_sparse`；音频构建新增可选后处理 `crossfade_loop_s`，让 AI 生成的环境音首尾无缝；验证 `Palette.load` 能读本仓库的 `wasteland.json`。都在 M11 开工时逐项向用户确认。

---

---

## 10. 决策记录（主代理裁决，2026-11-14）

M0 补写的四份文档（CONTENT、WORLD、UI-UX、ART-AUDIO）各自列出了"待主代理裁决"项。以下是裁决结果。**本节是这些问题的唯一权威出处**；各文档的"待裁决"章节改为引用本节编号。冲突时以本节为准，其次以 §0 为准。

### 10.1 通用

| 编号 | 问题 | 裁决 |
|---|---|---|
| R-G1 | 各文档数值的地位 | 全部是普通难度下的初始值，M10 用批量模拟调优。调优只改 `data/balance.lua` 等数据文件，同时回写 CONTENT.md |
| R-G2 | 心理影响数值的量纲 | 以 WORLD §2 的权重表和算例为准（一次偷窃的影响为个位数）。NARRATIVE §2.4 中"elena −25、dale −3"是示意，表示的是一次严重事件（例如杀人）的量级 |
| R-G3 | 叙事条件与效果 DSL 的参数形式 | 采用 WORLD 自拟的完整形式（R-W1）。M8 由 `sim/lint.lua` 校验，NARRATIVE §2.7 只保留示意并指向 WORLD |

### 10.2 CONTENT（C1–C11）

| 编号 | 裁决 |
|---|---|
| C1 | 同意：`weather.snaps[].severity` 为 1..4，4 = 大寒潮；温度的升降曲线由 `sim/weather.lua` 生成（已改 §4.4） |
| C2 | 同意：`food_any` 只含可直接食用的食物；生食材用 `food_raw` |
| C3 | 五项新增机制全部采纳：熟食 36 小时变质；发电机与柴火炉的烟柱提高夜袭概率；专属科技在缺人时成本与工时 ×1.5；储水罐在 0 °C 以下冻结；图纸"必出 3 张 + 其余各 65%"。GDD 相应章节补一句引用 |
| C4 | 同意：开局只有灶可用，发电机损坏，前三天靠灶和封窗 |
| C5 | §4.7 的"存粮"指**食物**。另加一条燃料指标：第 10、20 天燃料存量中位数 1–3 天 |
| C6 | 同意 D = 0.8 + 0.2 × 夜袭难度；教堂份额偏高属于设计意图（抢互助会收益高、代价大），M10 观察 |
| C7 | 同意：1 个 `food_days` = 该户人数 × 30 VP |
| C8 | 同意：哨站代价包 144 VP；南行需要修车件 220 VP + 汽油 40 L |
| C9 | 同意：心理阈值以 CONTENT §6.4.4 为准（回升阈值比下行阈值高 5 点） |
| C10 | 夜袭概率与防御分采用建议值，M7 实现后用探针与批量模拟校准 |
| C11 | 难度档位 M10 定，见 §9 第 4 条 |

### 10.3 WORLD（R1–R10）

| 编号 | 裁决 |
|---|---|
| W1 | 同意：WORLD 给出的 DSL 参数形式（`char`、`morale`、`relation`、`rep`、`die` 的延迟参数、派生事实 `rel.<a>.<b>`、`{ "fn", ... }`、`pick_char` 选项）为准，M8 在 `sim/cond.lua`、`sim/effects.lua` 实现并写进 lint |
| W2 | ~~同意五维~~ **已被 §10.6 S5 取代**：价值观改为三维 |
| W3 | 同意：角色特质乘数（elena ×1.4、tasha 杀人 ×2 等）在公式结果之后再乘，NARRATIVE §2.4 公式补"× 特质系数" |
| W4 | 同意：声望范围 −100..+100，五档：敌对 ≤ −60 / 戒备 / 中立 / 友好 / 盟友 ≥ +60（CONTENT 交易表已采用） |
| W5 | 同意：哨站线第 11 天开放，第 21 天决定庇护，第 27 天入住，早于第 28–30 天的大寒潮 |
| W6 | 首批片段里已有的角色线段落保留；角色线改为每人 3 段（§10.6 S4），其余段落在 M10 按 WORLD §3 补齐 |
| W7 | 同意：郊区住宅的两户住户按住宅变体三选一 |
| W8 | 设置键定名 `soft_narration`（布尔，默认关闭）。片段可选字段 `text_soft`，开启时替换 `text` |
| W9 | 修车与南行燃料用 CONTENT 的数值（C8），事实键沿用 WORLD 的 `car.fixed`、`car.fuel` |
| W10 | 同意：grace 不在队时，只能通过巡逻队或短波接触哨站 |

### 10.4 UI-UX（1–14）

| 编号 | 裁决 |
|---|---|
| U1 | 同意：新增 48×48 头像缩略图与 16×16 迷你图标，补入 ART-AUDIO |
| U2 | 同意：UI 缩放 `n = max(1, floor(H/720))`；1080p 时 n = 1，虚拟屏 1920×1080，HUD 贴边锚定；小字可在设置里开大字模式 |
| U3 | 同意：世界缩放两档（base 与 base+1），R3、Z/X、HUD 按钮切换 |
| U4 | 修改采纳：家园速度 ⏸ / 1× / 2× / 4×；**潜行副本只有 ⏸ / 1×**（保持紧张感，且 NPC 感知按真实帧率运行）。D7 的"1 秒 = 1 分钟"指 1× |
| U5 | 同意：Back 短按开轮盘、长按结束白天；Start 为暂停，不可改绑 |
| U6 | 同意：按住 LT 时十字键是快捷物品，不是队友指令 |
| U7 | 同意：新增动作 `cursor_free`（键盘 V），键盘与手柄共用"焦点目标"选择算法；GDD §3.2 补入 |
| U8 | 同意：引擎新增 `kit_input.last_mouse_button()`；`pad.last_button()` 覆盖全部 17 个逻辑按钮，扳机按 `trigger_press` 阈值计入（已改 ENGINE-PLAN §A4.3） |
| U9 | **不采纳**挂起存档和"潜行中退出 = 放弃本夜"。存档规则见 §4.5：只在时段边界存档，中途退出从最近的边界继续 |
| U10 | 同意：不做框选，用 Shift 加选与全选 |
| U11 | 同意：打开轮盘或菜单时自动暂停（潜行与家园都适用） |
| U12 | 同意新增默认键 `.` `,` `V` `N` `H` `-` `=` `Shift+G` `Home`，完整绑定表以 UI-UX §7 为准 |
| U13 | 同意：`ui.clip` 不嵌套，规定绘制顺序为列表内容 → 关闭裁剪 → 工具提示等浮层 |
| U14 | 同意：没有文本输入，种子逐位选择，不支持输入分享 |

### 10.5 ART-AUDIO（13.1–13.10）

| 编号 | 裁决 |
|---|---|
| A1 | 引擎新增 `TileDef.side_cap`：墙最上面一段的侧面用单独的图集格（墙檐、窗楣），见 ENGINE-PLAN §A3.3。门、窗本来就是独立的格类型，不需要按级别分段 |
| A2 | 轴向移动到斜向朝向的映射在 M2 写进 `view/facing.lua` 的单元测试，对照 `entity_last_move` 的坐标系核实 |
| A3 | 同意：关键帧插画改为 320×180（×4 = 1280×720，无黑边） |
| A4 | 同意石膏墙用抖动近似，M11 截图评审；不合格再在色卡里加一阶米白（总数仍 ≤ 64） |
| A5 | 引擎覆盖层支持贴图格 `overlay_add_tex`（取地块图集的一格），用于血迹与脚印贴花，见 ENGINE-PLAN §A1 第 13 条 |
| A6 | 覆盖层组号统一由 ENGINE-PLAN §A1 第 13 条的表规定；UI-UX 与 ART-AUDIO 改为引用该表 |
| A7 | 见 §9 第 5 条 |
| A8 | `fonts.json` 字段以 ART-AUDIO §10.3 为准，X11 实现时如需调整同步回写；`art.json` 增加可选字段 `kind`；`assets.py check` 新规则在 M11 实现；发行构建中半透明像素由警告升级为错误。pixel-hero-demo 侧见 §9 第 6 条 |
| A9 | 见 §9 第 6 条（`crossfade_loop_s`）；在那之前环境音用 `compose` 或手工循环 |
| A10 | 同意新增 NPC 儿童体型（只用于 NPC，D5 的三种体型指可玩角色）；西侧镜像带来的不对称配饰左右互换可以接受，设计时尽量对称 |

### 10.6 内容范围修订（2026-11-14，用户确认）

起因：一局只有 30 天，原计划的内容量（约 170 个片段、每人 4 段角色线、五维价值观、23 个具名 NPC）有相当一部分在单局里感知不到，却要承担三语校对、DSL 校验和平衡测试的成本。修订原则：**重玩性来自参数化片段和系统组合，而不是篇数**；先定曝光预算，再按指标决定是否加内容。

| 编号 | 决定 |
|---|---|
| S1 | **每日曝光预算**：导演每天最多推出 2 个有选项的片段（`balance.story.daily_choice_budget = 2`，危机与排期片段不占预算但计入统计）。其余时机（门前、无线电、谈话、黎明）用无选项的短句或系统消息填充。单局约 40–50 次有选项曝光 |
| S2 | **片段池目标约 80 个**：首批 42 个（原 40 个 + 学校 2 个，见 S6）+ 角色线 30 段（10 人 × 3）+ 结局、哨站、南行衔接 10–15 个，扣除与首批重叠的角色线段落。优先写带 `$victim`、`$loc` 绑定的参数化片段，一个片段覆盖多个地点或住户 |
| S3 | **加内容的门槛**：§4.7 新增两个重玩指标（单局内无重复、两局重合率低于 50%）。M10 先用约 80 个片段跑批量模拟，指标不达标才补写，不预先铺量 |
| S4 | **角色线改为 3 段有选项片段 + 1 句伏笔**：原第 1 段改为无选项的伏笔台词（对白或日志，不进 DSL 与平衡测试）；原第 2–4 段重编号为第 1–3 段，`arc.<id>.stage` 取值 0..3。三拍为：中期冲突、深化或转折、大寒潮前的抉择 |
| S5 | **价值观改为三维** `compassion, pragmatism, order`（取代 W2）。`honesty` 并入 `order`（守规矩、守信用）。`loyalty` 取消，改用关系规则：涉及队友的行为（抛弃、背叛、救援），受害队友对动手者的关系值按行为轻重下降；其余队友的心理影响 = 与受害者的关系系数 × 自身 compassion。维度列表放在 `data/values.lua`，代码不写死维数 |
| S6 | **具名 NPC 准入标准**：每个地点只保留一张"面孔"卡（受害者面孔、交易对象或势力代表）；同一地点的第二位及以后的具名人物，必须有自己的片段、角色线关联或独有机制，否则降为地点通用住户。结果 23 → 19 人：`npc.olaf` 并入 `npc.odell`（`arc_dale` 的关联改挂 odell）；`npc.hollis`、`npc.dot`、`npc.ames` 降级；`npc.garza` 保留，并为学校补 2 个片段进入首批（WORLD §4.0） |

