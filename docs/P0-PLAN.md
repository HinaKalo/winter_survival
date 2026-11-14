# P0 实施计划：接口冻结（main 上，M2、M3 合入之后）

上位文档：`PARALLEL-PLAN.md §1、§2、§4、§5`（P0-1..P0-6 与契约 C1–C9 的定义，**本文不重复契约原文，子代理必须直接读原文**）；`PLAN.md §4`；`UI-UX.md §2.1、§2.2、§7`；`NARRATIVE.md §2.4、§2.9`；`WORLD.md §1.3、§6`；`M2-PLAN.md §5`；`M3-PLAN.md §4、§5、§9`；`PANEL-PLAN.md §4`；`CI-PLAN.md`（verify 任务）。

本文把 P0 落到文件、签名和验收命令。凡标 **待确认** 的条目由主代理裁决后才开工对应部分；其余裁定子代理照做，不再自行决策。P0 不做玩法。

## 0. 目标与验收

| # | 验收项 | 怎么验 |
|---|---|---|
| G1 | 文本表拆成 `assets/i18n/<lang>/<area>.lua`，16 个区；同一语言内重复键在运行时和静态检查两处都报错；字体图集逐字节不变 | 本地 `python3 tools/assets.py check`、`python3 -m unittest discover -s tests/tools -t .`；重新烘焙后 `git status assets/fonts` 无改动；CI luatest `test_i18n_split` |
| G2 | 命令改为注册式，带域前缀；旧名作为别名可用到 M4 结束；参数按 spec 先校验后写入；预留命令返回 `not_implemented` 且不改状态 | CI luatest `test_commands`；CI full 档 `balance` 摘要（§1.3 定义）与基线一致 |
| G3 | `core/input.lua` 的动作表与 UI-UX §7.1 逐项一致（65 个动作 + `dev.*`），默认绑定除白名单外无冲突，支持长按/短按 | CI luatest `test_input_actions`；CI 探针 `p0_inputs.lua` |
| G4 | C1、C3、C4、C6、C7、C8、C9 的文件与函数全部存在，返回值形状正确；`sim/expedition.lua` 删除 | CI luatest `test_contracts`、`test_layering`（覆盖新目录） |
| G5 | 四个夹具由参考机器人生成，可读档、通过 `state.validate`，版本与 `state.VERSION` 一致 | CI luatest `test_fixtures` |
| G6 | 8 个场景空壳 + UI-UX §2.2 的跳转；`--dev --scene <s> --fixture <f>` 可直达任一场景 | CI 探针 `p0_scenes.lua`；CI 截图（`--shots`） |
| G7 | 全部合入后 PLAN §7 全绿 | `tools/ci_verify.sh --name p0-final --profile full --shots docs/p0_shots.txt` 结果 SUCCESS |

## 1. 前提、基线与测试规则

### 1.1 开工前提（主代理在 main 上确认）

1. M2、M3 的返工都已审查通过并合入 main。合并时要处理的已知冲突（不属于 P0 任务，但 P0 依赖其结果）：
   - `tools/i18n_check.py`：main 上已有带 `-- i18n:keep` 的版本（已接进 `tools/assets.py`）；M2 工作树里是一份未跟踪的旧版本。**保留 main 的版本**，删掉 M2 的。
   - `tests/lua/runner.lua`：M2、M3 各自维护一份显式文件列表，合并时取并集。P0-0 之后改为自动发现。
   - `assets/i18n/{zh,en,ko}.lua`：M2 新增了 `act.move_dir.*`、`demo.*` 等键，合并后跑一次 `python3 tools/i18n_check.py` 确认无未使用键。
2. PANEL 控件部分（PANEL-PLAN §2，提交 `45b4b0e` 及之后）是否在 P0-1 之前合入：**待确认 Q5**。本文默认“先合入 PANEL 控件，再做 P0-1”，这样 P0-1 一次迁走全部平铺文本。
3. main 上 CI verify 跑通 full 档，记下基线（§1.3）。

### 1.2 测试规则（本计划起执行）

- **本地 Linux 只做编辑和快速 Python 检查**：`python3 tools/assets.py check`、`python3 -m unittest discover -s tests/tools -t .`、`python3 tools/i18n_check.py`、`python3 tools/bake_font.py --check`。本地不跑 `zig build`、luatest、探针、balance。
- **重测试一律走 Windows CI verify 任务**：`tools/ci_verify.sh --name <标签> --profile quick|full [--probes 列表] [--shots 文件]`。quick 档 = `zig build test` + luatest + `tests/probe/*.lua`（去掉 `soak_heap`）；full 档再加 `zig build balance`。标签统一用 `p0-<任务号>-<次数>`，如 `p0-2-1`。
- 每个子任务交审前，编码代理必须附上 ci_verify 的摘要输出（JUnit 计数与失败项）；看画面的任务附 `--shots` 下载的截图路径。审查代理按摘要和截图审，不在本地重跑。
- 文件所有权以 §4 任务表为准；共享文件只在表里写明的任务中修改。
- **测试先行（CI-PLAN §8）**：§4 每个任务的“验收”列由主代理在派工前写成测试（Lua 单测 / 探针 / Python 单测 / 截图行），文件头标注“验收测试，编码代理不得修改”，提交到任务分支，用 `ci_verify.sh --profile quick` 确认为红后才派工。编码代理只负责让它们变绿，可另加自己的单测；认为验收测试有误时停下报告，由主代理裁定。
- **审查**：CI 全绿后交 `codex-review:codex-reviewer`（Codex gpt-6.1-sol，medium），附 §4 对应行和 ci_verify 摘要。FAIL 的每一条须指向失败测试或缺测试的验收项；主代理先补失败测试再派返工。

### 1.3 基线与“balance 摘要”

- 基线：P0 开工前在 main 上跑 `tools/ci_verify.sh --name p0-baseline --profile full`，保存下载目录里的 `out/balance/report.json`（**依赖 CI 线：verify 任务需归档 `out/balance/report.json`，待确认 Q13**）。
- “balance 摘要” = `report.json` 去掉所有 `checksum` 字段后的内容。P0 全程摘要必须与基线逐字节相同；`checksum` 只允许在 §3.2 阶段 B 和 §3.4 的 C1 改动处变化，变化后重新记基线并写进本文 §9 记录。`determinism.ok` 全程为 `true`。

## 2. 总则裁定

| 项 | 裁定 |
|---|---|
| 目录列举 | Lua 侧没有列目录的手段，M3 的 `test_layering` 用 `io.popen("find …")` 在 Windows 上不可用。P0-0 新增 Zig 绑定 `sys.list_files(rel_dir, suffix)`，i18n 加载、luatest 自动发现、分层检查都用它 |
| 启动参数 | Lua 目前不知道 `--dev`。P0-0 新增 `sys.launch_opts()`，P0-6 用它 |
| 状态版本 | `state.VERSION` 1 → 2（C1 新子树），同时补上 PLAN §4.5 要求的迁移表 `state.MIGRATIONS` |
| 命令日志 | `command_failed` 日志里的 `kind` 记**调用方提交的名字**（别名期间旧名照记），保证 P0-2 阶段 A 的状态逐字节不变 |
| 错误码 | 只用 `[a-z_]+` 短键，对应 i18n 键 `err.<code>`。M3 的 `"unknown_command:" .. kind` 改为 `"unknown_command"` |
| 事件 | `sim/` 继续用 `state.log` 记内部日志；对外通知走 C3 的 `events.emit`，处理函数不得写状态（STORY 的反应器另议） |
| 代理分配 | 与 PARALLEL-PLAN §1 不同处：P0-3 改为 sonnet（新增长按/短按和摇杆方向绑定，haiku 不适合）；新增 P0-0（sonnet）与 P0-7（haiku） |

## 3. 各任务细则

### 3.0 P0-0 基础设施（新增，Zig + Lua 测试入口）

**Zig（`src/main.zig`、`src/kit/sys.zig`）**

- 参数：在现有 `--probe/--script/--save-dir/--no-audio/--dev` 之外加 `--scene <name>`、`--fixture <name>`。两者都要求同时给 `--dev`，否则打印用法并 `error.BadArguments`。名字用 `save_name.isValid` 的白名单（`[a-z0-9_-]{1,32}`）校验。用法串同步更新。
- `sys.launch_opts() -> { dev = bool, scene = string|nil, fixture = string|nil }`。
- `sys.list_files(rel_dir, suffix) -> { "rel/path/a.lua", ... }`：只列普通文件，**递归**，结果按字节序排序，路径用 `/`。`rel_dir` 必须是相对路径、以 `assets/` 或 `tests/` 开头、不含 `..` 和反斜杠，否则返回 `nil, "bad_dir"`；目录不存在返回空表；其他枚举失败（打开失败但不是“不存在”、遍历中途出错、分配失败）一律返回 `nil, "io_error"`，不得返回部分结果。`suffix` 可为 nil。
- Zig 单测：参数解析（缺参数、未给 `--dev`、非法名字）、`list_files` 的路径校验与排序（纯逻辑部分拆成可测函数）。

**Lua**

- `tests/lua/runner.lua`：去掉显式列表，改为 `sys.list_files("tests/lua", ".lua")` 中文件名匹配 `^test_.*%.lua$` 的全部套件，按名字排序执行。
- `tests/lua/test_layering.lua`：`file_list` 改用 `sys.list_files`，删除 `io.popen`；检查目录加上 `sim/cmd`、`sim/query`、`sim/schema`（递归已覆盖，断言里写明）。
- `assets/main.lua`：起始场景取 `sys.launch_opts().scene`，没有时再读 `WS_SCENE`（`--scene` 优先）；保留 `WS_SCENE` 环境变量作为 `--scene` 的旧别名，直到 M4 结束（`tools/shot.sh` 仍在用）。

### 3.1 P0-1 文本表拆分

**区（area）清单**（`tools/i18n_check.py` 里的 `AREAS` 常量，同时写进 `core/i18n.lua` 文件头）：

| 区 | 归属 | P0 迁入的键 |
|---|---|---|
| `core` | 主代理 | `title.*`、`settings.*`、`rebind.*`、`ctx.*`、`act.*`（含 P0-3 新增）；P0-6 的 `scene.*`；P0-7 的通用 `err.*` |
| `ui_common` | 主代理 | M1 的 10 个 `ui.*`：`ui.back ok cancel confirm reset_default reset_all on off close none` |
| `dev` | 主代理 | M2 的 `demo.*`；之后的 `dev.*` 标签 |
| `ui` | PANEL | PANEL 新增的 `ui.*`（除上面 10 个）与 `hint.*` |
| `home`、`dusk`、`dawn` | HOME | `home` 区放 P0-7 的 HOME 域 `err.*`；其余空 |
| `items`、`tech` | HOME（**待确认 Q6**） | 空（物品/配方/设施/科技名称的归属待定） |
| `world`、`trade`、`loc` | WORLD | 空 |
| `raid`、`combat` | RAID | 空 |
| `story`、`char` | STORY | 空（`char.<id>` 名字的归属见 Q6） |

- 文件名 = 区名，三语各 16 个文件，空区写 `return {\n}\n`。一个键属于哪个区由所在文件决定，**不按前缀强制**（`ui.*` 同时出现在 `ui_common` 与 `ui` 就是这种情况）。
- 迁移是纯搬运：值、`-- i18n:keep` 标记、键的相对顺序原样保留；不改译文。

**运行时加载（`core/i18n.lua`）**

- `load_lang(code)`：`sys.list_files("assets/i18n/" .. code, ".lua")`，逐个 `loadfile(path, "t", {})`（空环境，不执行任意代码），返回值不是表就 `error`；合并时键已存在就 `error(string.format("i18n: duplicate key %q in %s and %s", key, first_path, path))`。语法错误、目录为空都 `error`，不再像 M1 那样静默得到空表。
- 记录 `M.sources[code][key] = path` 供测试与开发面板使用；`init/set_lang/get_lang/t` 签名不变。
- 新增 `M.load_dir(root, code)`（`load_lang` 的内部实现，root 默认 `assets/i18n`），测试用它加载 `tests/lua/fixtures/i18n_dup/` 下的固定样例（`zh/a.lua`、`zh/b.lua` 含同一个键）。

**`tools/i18n_check.py`（在 main 的带 keep 版本上改）**

- 发现：`assets/i18n/<lang>/*.lua`；`assets/i18n/<lang>.lua` 平铺文件仍存在时报错 `flat table no longer supported`。
- 新增检查：① 文件名不在 `AREAS` → 报错；② 某语言缺某区文件 → 报错；③ 同一语言里一个键出现在两个文件 → `zh: duplicate key "x" in core.lua and ui.lua`；④ 同一个键在三语中必须位于同名区文件 → 否则报错。
- 原有检查不变：三语键一致、占位符一致、未使用键（keep 豁免）。扫描引用时排除整个 `assets/i18n/` 目录树。
- `tests/tools/test_i18n_check.py`：夹具改为目录布局；新增 ①–④ 与平铺文件残留的用例。

**`tools/bake_font.py`**：`collect_codepoints` 的 `glob("*.lua")` 改为 `sorted(rglob("*.lua"))`；`tests/tools/test_bake_font.py` 加嵌套目录用例。字符集不变，所以图集应逐字节不变。

### 3.2 P0-2 命令注册式

**模块**

- `sim/commands.lua`（主代理所有）：注册表、别名表、参数类型、`run`、`can`、`spec`、`list`、`error_key`。按固定顺序加载域文件：`DOMAINS = { "home", "needs", "craft", "tech", "night", "raid", "trade", "travel", "story" }`，对应 `sim/cmd/<域>.lua`。新增域 = 改这张表，属于契约变更。
- `sim/cmd/<域>.lua` 的写法：

```lua
local commands = require("sim.commands")
local reg = commands.domain("needs")        -- 只能注册 "needs.*"，前缀不符直接 error
reg("eat", function(state, cmd) ... end, {
  args = { { "char", "char" }, { "item", "item?" } },   -- 有序列表：{ 字段名, 类型 }，"?" 结尾表示可选
  phase = nil,                                          -- 或 { "dusk", "night" }
  phase_err = nil,                                      -- 时段不符时的错误码，默认 "wrong_phase"
})
```

- **spec 用有序列表，不用 PARALLEL-PLAN C2 示例里的映射表**：校验顺序必须确定，且要与 M3 处理函数里的检查顺序一致，保证错误码不变。
- `commands.run(state, cmd) -> ok, err, extra`（保留 M3 的第三返回值）。顺序：① `cmd` 是表、`kind` 是字符串（兼容 `cmd[1]`），否则 `bad_command`；② 旧名查别名表；未注册 → `unknown_command`；③ 时段检查；④ 按 spec 逐个校验参数，首个失败即返回；⑤ `pcall` 调处理函数，异常 → `state.error` + `internal_error`；⑥ 失败时 `state.log(state, "command_failed", { kind = 提交的名字, err = err })`。
- `sim.command` 里 `end_day` 的特判删除，统一走 `commands.run`；`home.end_day` 的处理函数在函数体内 `require("sim.sim")`（延迟加载，避免循环依赖）。
- 名字规则：`^[a-z]+%.[a-z_]+$`；重复注册 `error`。

**参数类型**（都是只读查询，失败返回的错误码沿用 M3 现有码）

| 类型 | 规则 | 错误码 |
|---|---|---|
| `char` | 字符串，`state.party.chars[id].status == "alive"` | `no_char` |
| `char_list` | 1..N 个互不相同的 `char`，N 由 spec 的 `max` 给出 | `bad_squad`（成员不在则 `no_char`） |
| `item` / `recipe` / `tech` | 在 `data.items` / `data.recipes` / `data.tech` 中 | `unknown_item` / `unknown_recipe` / `unknown_tech` |
| `room` | `state.home.rooms[id]` 存在 | `bad_room` |
| `station` | `state.home.stations[id]` 存在 | `no_station` |
| `job` | `state.jobs` 中存在该作业 id | `no_job` |
| `loc` | `[a-z0-9_]+` 字符串；`state.world.locations` 非空时还必须存在 | `bad_loc` |
| `npc` | `[a-z0-9_.]+` 字符串（WORLD 之前不查存在性） | `bad_npc` |
| `item_counts` | `{ [item_id] = 正整数 }` | `bad_items` |
| `number` / `int` / `boolean` / `string` / `table` | 有限数 / 有限整数 / 布尔 / 字符串 / 表 | `bad_arg` |
| `{ "a", "b" }` | 枚举 | spec 的 `enum_err`，默认 `bad_arg` |

**先校验后写入**：spec 覆盖参数层；处理函数内部规则是“所有检查在第一次写状态之前完成”。用模糊测试兜底（见验收）。

**迁移表**（M3 → 新名；旧名进别名表，M4 结束时删除）

| M3 | 新名 | 文件 | args（有序） | 备注 |
|---|---|---|---|---|
| `eat` | `needs.eat` | needs | char:char, item:item? | |
| `drink` | `needs.drink` | needs | char:char, item:item? | |
| `use` | `needs.use` | needs | char:char, item:item | M3 缺 item 时返回 `no_item`，保留 |
| `sleep` / `wake` | `needs.sleep` / `needs.wake` | needs | char:char | |
| `treat` | `needs.treat` | needs | patient:char, actor:char?, item:item? | 伤病归 needs 域 |
| `equip` | `home.equip` | home | char:char, item:item | |
| `unequip` | `home.unequip` | home | char:char, slot:string | |
| `assign` | `home.assign` | home | char:char, room:room | |
| `activity` | `home.set_activity` | home | char:char, value:{idle,work,sleep,guard,out} | `enum_err = "bad_activity"` |
| `toggle` | `home.toggle` | home | station:station, on:boolean | |
| `set_level` | `home.set_level` | home | station:station, level:{low,high} | `enum_err = "bad_level"` |
| `set_door` | `home.set_door` | home | x:int, y:int, open:boolean | |
| `board` | `home.board` | home | room:room?, what:{window,hole}? | |
| `end_day` | `home.end_day` | home | — | phase `{day}`，`phase_err = "not_day"` |
| `craft` | `craft.start` | craft | char:char, recipe:recipe, room:room? | |
| `cancel_job` | `craft.cancel` | craft | job:job | |
| `research` | `tech.start` | tech | char:char, tech:tech | |
| `cancel_research` | `tech.cancel` | tech | — | |
| `learn_blueprint` | `tech.learn_blueprint` | tech | char:char, item:item | |
| `night_roles` | `night.set_roles` | night | roles:table?, target:loc? | phase `{dusk,night}`，`phase_err = "not_dusk"`；日志事件名仍是 `night_roles`。**待确认 Q7** |
| `expedition` | `raid.autoresolve` | raid | squad:char_list(max 2), hours:number? | phase `{night}`，`phase_err = "not_night"`；P0-2 内部仍调 `expedition.night`，P0-4 换成 `sim/raid.lua` |

**预留命令**（`commands.reserve(kind, spec)`：注册签名，处理函数恒为 `false, "not_implemented"`，不写状态也不写日志）。签名暂定如下，是否就此冻结 **待确认 Q18**：

| 命令 | args | 文件（P0 建空域文件，之后归该线） |
|---|---|---|
| `trade.offer` | trader:npc, give:item_counts, want:item_counts | `sim/cmd/trade.lua`（WORLD） |
| `trade.accept` / `trade.leave` | trader:npc | 同上 |
| `travel.go` | loc:loc, squad:char_list | `sim/cmd/travel.lua`（WORLD） |
| `raid.begin` | loc:loc, squad:char_list | `sim/cmd/raid.lua`（RAID） |
| `raid.commit` | result:table | 同上 |
| `story.choose` | instance:string, option:int | `sim/cmd/story.lua`（STORY） |
| `night.set_role` | char:char, role:{out,guard,sleep} | `sim/cmd/night.lua`（HOME） |
| `night.set_target` | loc:loc? | 同上 |
| `night.set_loadout` | char:char, items:item_counts | 同上 |

**分两个阶段提交**

- 阶段 A：注册表 + 域文件 + 别名 + 预留命令；`sim/bot.lua` 与全部测试**不改**，仍用旧名。验收：balance 报告（含 checksum）与基线逐字节相同。
- 阶段 B：`sim/bot.lua` 与 `tests/lua/test_sim_*.lua` 全部改用新名；`test_sim_craft` 中“`sleep_until_dawn` 已删除”的断言保留。验收：balance 摘要不变，checksum 允许变化（日志里的 `kind` 变成新名），记新基线。

### 3.3 P0-3 输入动作补齐

**现状**：M2 的 `core/input.lua` 有 40 个非开发动作 + 6 个 `dev.*`。PARALLEL-PLAN 列出的 `select`、`move_to`、`move_dir`、`system_menu` 已由 M2 做完。对照 UI-UX §7.1，**缺 25 个**：

| 动作 | 上下文 | 键盘 | 鼠标 | 手柄 |
|---|---|---|---|---|
| `select_1`..`select_6` | W | 1–6 | 屏上（头像） | na |
| `select_next` / `select_prev` | W | Tab / Shift+Tab | 屏上（头像） | RB / LB |
| `select_all` | H | Ctrl+A | 屏上（全选钮） | 长按 LB |
| `focus_next` / `focus_prev` | W | `.` / `,` | na | RB / LB |
| `cursor_click_l` / `cursor_click_r` | F（新：自由光标） | Enter / Backspace | na | A / X |
| `squad_follow` / `squad_hold` / `squad_lookout` / `squad_carry` | R | 屏上 → `squad_wheel` | 屏上（指令钮） | 十字键 上/左/右/下 |
| `quick_1`..`quick_4` | W | 5–8（**与 `select_5/6` 冲突，待确认 Q4**） | 屏上（快捷栏） | LT+十字键 上/右/下/左 |
| `camera_pan` | W | 命名槽 up/left/down/right = 方向键 | 屏上（边缘滚屏/中键拖） | 命名槽 `rs` = 右摇杆整轴 |
| `screenshot` / `fullscreen` / `dev_panel` | G | F12 / F11 / F1（保留，不可改） | na | na |

**同时修正的现有条目**（与 §7.1 不符，P0 后各线不再能改动作表，必须这次改）：

| 动作 | M2 现状 | 改为 | 原因 |
|---|---|---|---|
| `end_day` | 键盘 E、手柄 Back | 键盘长按 E、手柄长按 Back | 与 `open_wheel`（Back，W）冲突；§7.1 写的是长按 |
| `intimidate` | 手柄 LT+Y | 手柄长按 Y | §7.1 |
| `evacuate` | 手柄 B | 手柄长按 B | §7.1 |
| `camera_center` | 手柄无（屏上） | 手柄长按 R3 | §7.1 |
| `system_menu` | 手柄屏上 `open_wheel` | 手柄长按 Start（保留键） | §7.1 |
| `ui_page_prev/next` | 手柄 LB / RB | 右摇杆 上 / 下 | 与 `ui_tab_prev/next`（LB/RB，同在 U）冲突 |
| `dev.time_prev/next`、`dev.map_toggle`、`dev.mode_toggle`、`dev.roof_toggle`、`dev.flashlight` | `,` `.` Tab C R L | F5 F6 F7 F8 F9 F10 | 与新的 `focus_*`、`select_next`、`sneak_toggle`、`intimidate` 同键，演示里会一键两用；`scenes/m2_demo.lua` 的提示同步 |

**新增机制（本计划裁定）**

1. **长按**：动作字段 `hold = { keyboard = true, pad = true }`，表示该动作在该设备上的绑定都是长按型。长按属于动作，不属于玩家选择；改键只换键位，长按属性保留，所以 `settings.sav` 的绑定格式不变。阈值 `input.HOLD_S`：读设置 `acc.hold_duration`，没有就用 0.5 s。
2. **短按/长按配对**：同一设备、同一物理输入，一个动作是短按、另一个是长按，并且两者的上下文按 `CTX_CONFLICTS` 互斥（即可能同时生效）时，二者互为配对。有配对的短按动作改为**松开时**触发（按住不到 `HOLD_S`）；长按动作在按满 `HOLD_S` 时触发一次。没有配对的短按动作仍在按下时触发（M2 行为不变）。比较绑定时 `same_binding` 把长按属性算进去。
3. **摇杆方向绑定**：`{ axis = "rs", dir = "up"|"down"|"left"|"right" }`，阈值 0.5，按边沿触发并参与 `ui_dir_repeat` 式重复。整轴绑定 `{ axis = "ls"|"rs" }` 只允许放在命名槽里（沿用 M2 的 `binding_fits`）。
4. **新上下文 F**（自由光标）：`CTX_CONFLICTS.F = { F = true, G = true }`，其余上下文的表里不加 F。
5. **默认冲突白名单** `input.SHARED_DEFAULTS`（§7.1 有意的一键多用）：手柄 A = `select`/`interact`；手柄 X = `context`/`attack`；手柄 RB/LB = `select_next/prev` 与 `focus_next/prev`；鼠标右键 = `interact`/`context`/`move_to`；键盘 Esc = `cancel`/`system_menu`。不在白名单的默认冲突一律视为缺陷。
6. `dev_panel` 只在 `sys.launch_opts().dev` 为真时可触发；`fullscreen` 调用与设置页同一个接口；`screenshot` 如果引擎尚无截图接口，P0 只登记动作并在 `main.lua` 里记日志“未实现”，接口留给 M12。

**文本与界面**：每个新动作加 `act.<id>`（三语，`core` 区）；`camera_pan` 的四个命名槽加 `act.camera_pan.up/left/down/right`；长按绑定在改键界面显示前缀 `rebind.hold`（“长按 {key}”）。`ui/rebind.lua` 只改：命名槽通用化（`camera_pan` 与 `move_dir` 同一套）、长按前缀显示、隐藏 `dev.*` 与 G 区保留动作的编辑按钮。

### 3.4 P0-4 契约骨架

文件头注释抄写 PARALLEL-PLAN §2 对应契约的表格，注明“契约，修改走 PARALLEL-PLAN §5”。

**C1 状态树**

- `sim/state.lua`：`VERSION = 2`；`state.new` 新增 `world = { locations = {}, npcs = {}, factions = {}, notoriety = 0, traders = {} }`、`outpost = {}`、`endings = {}`。
- `state.MIGRATIONS = { [1] = function(s) ... 补上述三个子树 ... s.version = 2 end }`；`state.decode` 在 `validate` 之前按版本依次迁移。
- 校验拆分：`sim/schema/<子树>.lua` 各返回 `function(sub, state) -> ok, err`，`state.validate` 按固定顺序 `clock, party, home, weather, tech, jobs, night, story, world, outpost, endings, stats` 调用。M3 现有的检查**原样搬运**（报错文本不改），新子树的校验只查类型。版本、种子、随机流、日志长度仍在 `state.lua` 里查。
- `state.raid` 必须为 nil（C1：副本不进存档），否则 `validate` 报 `raid state must not be saved`。
- 归属：子树文件的所有者照 C1 表；C1 表没列出的顶层字段（`jobs`、`opts`、`model_acc`、`job_seq`、`log`、`errors`、`rng`、`seed`、`version`）**待确认 Q10**，本文暂定 `jobs`、`opts`、`model_acc`、`job_seq` 归 HOME，其余归主代理。

**C3 事件**：`sim/events.lua` 返回事件目录（按域分段，只追加）：

```lua
return {
  -- clock
  phase_changed    = { "from", "to", "day" },
  day_started      = { "day" },
  -- char
  char_died        = { "id", "cause", "day" },
  char_wounded     = { "id", "amount", "cause" },
  char_left_party  = { "id", "reason" },
  char_joined_party = { "id" },
  -- home
  station_changed  = { "id", "on", "hp" },
  room_temp_alert  = { "room", "temp", "level" },
  -- weather
  snap_warning     = { "start_day", "severity" },
  -- story
  storylet_ready   = { "slot", "id" },
  -- raid
  raid_ended       = { "loc", "exit" },
}
```

事件名一律扁平 snake_case，匹配 `^[a-z]+(_[a-z]+)*$`，全局唯一，分段注释不进名字（PARALLEL-PLAN C3，已由 §9.5 取代旧的域前缀写法）。

`sim/emit.lua`：`emit(name, data)` 查目录，未知事件或缺必填字段直接 `error`，否则 `bus.emit(name, data)`。P0 只接线四处：`sim.advance_phase` 发 `phase_changed`，`sim.on_new_day` 发 `day_started`，`chars.kill` 发 `char_died`，`health.add_wound` 发 `char_wounded`；其余事件只登记。发事件不写状态，所以 balance 不受影响。

**C4 查询层**：`sim/query/{party,home,inv,craft,tech,clock,night}.lua`。纯函数、只读，返回值只含数字/字符串/布尔/表，文本一律是 i18n 键或 id/枚举。P0 给出真实的最小实现（夹具上有数据可显示），形状如下：

| 函数 | 返回 |
|---|---|
| `party.cards(state)` | 按 `party.order`：`{ id, name_key, hp_band = "ok"|"light"|"heavy"|"critical", needs = { food, water, energy, temp, mood }（取整）, activity, room, job = { recipe|tech, progress 0..1 } | nil, flags = { "cold", "sick", ... } }` |
| `party.detail(state, id)` | `{ id, name_key, age, role, traits = { key... }, needs, health = { hp_band, diseases = { { id, left } } }, wear = { [slot] = item_id }, relations = { { id, value } }, psyche = {} }`；人不在返回 `nil, "no_char"` |
| `home.rooms(state)` | 按 id 排序：`{ id, name_key, temp（一位小数）, area, occupants = { id... }, insulation }` |
| `home.stations(state)` | 按 id 排序：`{ id, kind, name_key = "station." .. kind .. ".name", room, hp, on, level, usable }` |
| `inv.grid(state, bag_ref)` | `bag_ref = "stash" | "char:<id>"`；`{ ref, slots, slots_used, kg, kg_cap, entries = { { item, name_key, count, kg, cat, spoil_left, spoiled } } }`，按 `(cat, item)` 排序（M3 背包没有格位顺序，见 Q14） |
| `craft.list(state, station_id|nil)` | `{ { recipe, name_key, station_kind, minutes, can, reason, inputs = { { item, need, have } }, outputs = { { item, n } } } }`；`can/reason` 来自 `craft.can`（须确认其不写状态，写则在查询里改用副本） |
| `tech.tree(state)` | `{ { id, name_key, prereqs, status = "unlocked"|"available"|"locked"|"researching", progress, reason } }` |
| `clock.hud(state)` | `{ day, days_total, minute, hh, mm, phase, outdoor_temp, forecast_level, snap_warning }` |
| `night.plan(state)` | `{ roles = { { id, role } }, target, loadout = {}, editable }` |

**C6 行为记录**：`sim/deeds.lua`：`deeds.record(state, t) -> deed_id`（校验顶层字段后追加到 `state.story.deeds`，id 取 `state.story.deed_seq` 自增）、`deeds.query(state, filter) -> list`（按 `verb`/`actor`/`loc`/`day` 过滤，按 id 升序）。`data/deed_kinds.lua` 只追加。**字段表以 PARALLEL-PLAN C6 为准（已由 §9.5 取代旧的 `kind/accomplices/target{type,id}/witnessed/evidence/severity/data`）**：`verb`（含 `die`；无 `break_in`/`intimidate`，用标签 `break_in`/`armed_threat`）、`actor`、`squad`、`target`（`npc.<id>` / 角色 id / `faction.<id>` / `loc.<id>` / nil）、`target_kind`、`loc`、`tags`、`witnesses`、`magnitude`；`id`、`day`、`phase` 由 `record` 填。`deeds.query` 的过滤键用 `verb`/`actor`/`loc`/`day`（不再是 `kind`）。P0-4 的 C6 不再等待裁决。

**C7 副本接口**：`sim/raid.lua`：

- `raid.autoresolve(state, loc_id, squad, policy) -> result`：M3 `expedition.night` 的逻辑原样搬入（`policy.hours` 代替 `hours`；`loc_id` 记入日志但 P0 不影响结算），仍直接写状态，返回 C7 的 `result` 形状并带 `applied = true, placeholder = true`。是否改成“只算不写 + `commit` 写回”由 RAID 决定，**待确认 Q8**。
- `raid.begin` 返回 `nil, "not_implemented"`；`raid.commit` 先用 `raid.validate_result(result)`（真实实现，查 `loot/wounds/deaths/deeds/minutes_used/exit`）再返回 `false, "not_implemented"`。
- 命令 `raid.autoresolve` 改调 `raid.autoresolve`；删除 `sim/expedition.lua`；`data/balance.lua` 的 `expedition` 分节名不变（M10 再改）。验收：balance 摘要与 checksum 都与阶段 B 基线相同（纯搬运）。

**C8 地点数据**：`sim/locations.lua`：`locations.validate(loc) -> ok, err`（按 C8 字段查类型与枚举）、`locations.get(state, id)`、`locations.list(state)`（按 id 排序）。`tests/fixtures/locations/suburb_house_a.lua` 手写一份通过校验的地点（`archetype = "suburb_house"`、`variant = "A"`，容器槽取 `data/locations/suburb_house.lua` 的道具槽）。字段名已按 WORLD 回改（§9.5）：`occ`、`travel_min`、`raid_difficulty`、字母 `variant`、`state` 只含 unknown/known/visited/friendly/burned、独立布尔 `alert`；`world.locations` 是唯一数据源，`loc.*` 事实由它派生。

**C9 片段挂点**：`sim/story.lua`：`story.SLOTS`（C9 的 11 个名字：`door_day, radio, dawn, dusk, home_idle, raid_enter, raid_found, travel, dream, talk, crisis`）、`story.pick(slot, ctx)`（未知挂点 `error`，否则恒返回 nil）、`story.choose(state, inst, idx)` 返回 `false, "not_implemented"`。文件头列出每个挂点的 `ctx` 附加字段。挂点名已按 NARRATIVE §2.7 回改（§9.5）。

### 3.5 P0-5 测试夹具

- 生成脚本 `tests/fixtures/make.lua`，以探针方式运行（不在 `tests/probe/` 下，所以不会被 CI 默认跑到）。种子 `20261114`（balance 默认首种子），`sim.new(seed)` 不加 `kit`，与 balance 相同。

| 夹具 | 生成方式 | 是否时段边界 |
|---|---|---|
| `day1_0600` | `sim.new` 后立即写出 | 是（开局） |
| `day3_1900` | `bot.play_day` 跑完第 1–2 天，第 3 天 `stop_phase = "dusk"` | 是 |
| `day10_1200` | 跑完第 1–9 天，第 10 天 `stop_minute = 720`（`sim/bot.lua` 新增选项：当天时钟到该分钟即返回） | **否**，只供界面开发，不能拿来续跑机器人（**待确认 Q3**） |
| `day28_2100` | 跑完第 1–27 天，第 28 天 `stop_phase = "night"` | 是（夜间角色已定，外出尚未结算） |

- 文件内容 = `state.encode(state)`，即普通存档文本，`state.decode` 可直接读。同时写 `tests/fixtures/manifest.lua`：`{ { name, seed, day, minute, version, boundary, checksum } ... }`，checksum 为 `state.checksum` 的值。
- **确定性**：同一二进制、同一种子，结果逐字节相同。跨平台浮点可能不同（M3-PLAN §8），所以夹具只在 Windows CI 上生成；校验用“读档后重新编码的 checksum”，读同一份文本在任何平台上都得到相同的值。
- **重新生成**：`tools/ci_verify.sh --name p0-fixtures-N --profile quick --probes tests/fixtures/make.lua`，make.lua 用 `io.open` 写进工作区的 `tests/fixtures/`；verify 任务把 `tests/fixtures/*.sav` 与 `manifest.lua` 归档（**依赖 CI 线，待确认 Q13**），下载后拷回本地提交。触发条件：`state.VERSION` 变化（PARALLEL-PLAN §6），或主代理要求。
- `tests/lua/test_fixtures.lua`（luatest，快）：四个文件都存在；`state.decode` 成功；`version == state.VERSION`，否则报“夹具过期，按 P0-PLAN §3.5 重新生成”；时钟与 manifest 一致；checksum 一致；每个夹具至少 1 人存活。

### 3.6 P0-6 场景外壳与启动参数

- 新建 8 个空壳：`scenes/{newrun,home,dusk,worldmap,trade,raid,dawn,ending}.lua`。`title` 已有；`ui/settings` 已有；`ui/dialog`、面板、`ui/slots` 不在本任务（分别归 STORY、PANEL，`slots` 留到 HOME）。
- `scenes/shell.lua`（主代理所有）：`shell.make(name, edges) -> scene`。画 `i18n.t("scene." .. name)` 和每条出边一个 `widgets.button`；`edges = { { label_key, op = "push"|"replace"|"pop"|"reset", target, args = fn(state) } }`，`reset` = 清空栈后压入。场景 `enter(args)` 收 `args.state`，沿跳转原样传下去；空壳不调用 `sim`（`newrun` 的“开始”除外：`sim.new(seed)`，种子取固定值 1，选择器留给 HOME）。
- 跳转（UI-UX §2.2）：

| 从 | 出边 |
|---|---|
| title | 新局 → push newrun（替换 M1 的占位提示）；继续/读档仍为占位 |
| newrun | 开始 → reset home；取消 → pop |
| home | 地图 → push worldmap{mode="day"}；交易 → push trade；结束白天 → replace dusk；系统菜单 → `scene.push_modal(settings)` |
| worldmap | 返回 → pop |
| trade | 离开 → pop |
| dusk | 选目的地 → push worldmap{mode="night"}；出发（有人外出）→ replace raid；无人外出 → replace dawn |
| raid | 撤离 → replace dawn |
| dawn | 继续 → replace home；结局 → reset ending |
| ending | 回标题 → reset title |

- `scenes/registry.lua`：`{ title=…, newrun=…, home=…, dusk=…, worldmap=…, trade=…, raid=…, dawn=…, ending=…, m2_demo=… }`，按名取模块。
- `scenes/launch.lua`：`launch.load_fixture(name)`（`io.open("tests/fixtures/" .. name .. ".sav")` + `state.decode`，失败 `error` 带原因）；`launch.enter(scene_name, fixture_name)`（未知场景 `error`）。`assets/main.lua` 的 `_init` 读 `sys.launch_opts()`，有 `scene` 时调用 `launch.enter`，否则照旧进标题。
- 文本：`scene.<name>` 与出边标签 `scene.edge.<id>`，三语，`core` 区。
- 归属：`home/dusk/dawn` 归 HOME，`worldmap/trade` 归 WORLD，`raid` 归 RAID，`newrun`、`ending` **待确认 Q15**（暂定 HOME、M9），`shell/registry/launch` 归主代理。各线之后整文件替换空壳，`registry.lua` 不需要改。
- 截图清单 `docs/p0_shots.txt`（`--shots` 格式 `名字|环境变量|游戏参数`），每个场景一行，例如 `home_day3|WS_LANG=zh|--dev --scene home --fixture day3_1900`，三语各取 home 一张。

### 3.7 P0-7 错误码文本（新增）

- 收集 `sim/` 里所有处理函数可能返回的错误码（M3 现约 60 个）+ P0-2 新增的 `wrong_phase`、`unknown_command`、`not_implemented`、`bad_arg`、`bad_loc`、`bad_npc`、`bad_items`。
- 通用码（`bad_command`、`unknown_command`、`internal_error`、`not_implemented`、`wrong_phase`、`bad_arg`、`no_char`）放 `core` 区，其余放 `home` 区。三语，玩家可读的短句。
- `commands.error_key(code)` 返回 `"err." .. code`，这一拼接让 `i18n_check` 把 `err.*` 视为已引用。
- `tests/lua/test_cmd_errors.lua`：用 `sys.list_files` 读 `sim/**/*.lua`，抓 `return false, "<code>"` 与 `return nil, "<code>"`，断言每个码在 zh 表里有 `err.<code>`。

## 4. 任务表

| # | 任务 | 代理 | 依赖 | 文件 | 验收 |
|---|---|---|---|---|---|
| P0-0 | 启动参数、`sys.launch_opts`、`sys.list_files`；runner 自动发现；`test_layering` 去掉 `popen` | sonnet | §1.1 | `src/main.zig`、`src/kit/sys.zig`、`src/kit/tests.zig`、`tests/lua/runner.lua`、`tests/lua/test_layering.lua`、`assets/main.lua`（仅 WS_SCENE 别名注释） | CI quick：`zig build test` 新用例过；luatest 套件数 ≥ 合并前（runner 打印的套件清单与 `tests/lua/test_*.lua` 一致）；`test_layering` 在 Windows 上通过 |
| P0-1 | 文本表拆分（§3.1） | haiku | P0-0、P0-3、（PANEL 控件，Q5） | `assets/i18n/**`、`core/i18n.lua`、`tools/i18n_check.py`、`tools/bake_font.py`、`tests/tools/test_i18n_check.py`、`tests/tools/test_bake_font.py`、`tests/lua/test_i18n_split.lua`、`tests/lua/fixtures/i18n_dup/**` | 本地：`assets.py check` 与 Python 单测全过；`python3 tools/bake_font.py` 后 `git status assets/fonts` 无改动。CI quick：`test_i18n_split`（三语键数与拆分前相同、重复键样例报错且报出两个文件名）、`ui_text` 探针过 |
| P0-2 | 命令注册式（§3.2），阶段 A、B 两次提交 | sonnet | §1.3 基线 | `sim/commands.lua`、`sim/cmd/*.lua`（9 个）、`sim/sim.lua`（仅 `command`）、阶段 B：`sim/bot.lua`、`tests/lua/test_sim_*.lua`；新增 `tests/lua/test_commands.lua` | 阶段 A：CI full，balance 报告与基线逐字节相同。阶段 B：CI full，摘要不变。`test_commands`：重复注册/前缀不符报错；每个别名指向已注册命令；10 个预留命令返回 `not_implemented` 且状态 checksum 不变；每种参数类型的正反例；**模糊测试**：在 `sim.new(1)` 和跑完 1 天的状态上，对每个命令的每个参数代入坏值，断言 `ok == false` 且去掉 `log`/`errors` 后的编码与调用前逐字节相同 |
| P0-3 | 输入动作补齐（§3.3） | sonnet | — | `core/input.lua`、`ui/rebind.lua`、`scenes/m2_demo.lua`（仅 dev 键提示）、`assets/main.lua`（fullscreen/screenshot/dev_panel 处理）、`assets/i18n/{zh,en,ko}.lua`（P0-1 之前的平铺文件）、`tests/lua/test_input_actions.lua`、`tests/probe/p0_inputs.lua` | CI quick：`test_input_actions`（动作 id 集合与 §7.1 的 65 个逐一相等；`validate()` 通过；默认绑定除 `SHARED_DEFAULTS` 外无冲突；短按/长按配对与触发时机；摇杆方向边沿；每个动作有 `act.<id>`）；`p0_inputs` 对每个动作 × 每个有绑定的设备注入默认输入（`probe.key/click/pad_button/pad_axis`），断言在 `HOLD_S` + 2 帧内触发且只触发该动作及其白名单伙伴；`m1_inputs` 仍过 |
| P0-4 | 契约骨架（§3.4）；C6 已定（§9.5） | sonnet | P0-2 | `sim/state.lua`、`sim/schema/*.lua`、`sim/events.lua`、`sim/emit.lua`、`sim/query/*.lua`、`sim/deeds.lua`、`data/deed_kinds.lua`、`sim/raid.lua`、`sim/locations.lua`、`sim/story.lua`、`sim/cmd/raid.lua`、`sim/sim.lua`、`sim/chars.lua`、`sim/health.lua`（各一行 emit）；删除 `sim/expedition.lua`；`tests/fixtures/locations/suburb_house_a.lua`；`tests/lua/test_contracts.lua` | CI full：C1 改动后摘要不变（checksum 变化，记基线）；C7 搬运后 checksum 也不变。`test_contracts`：v1 状态迁移到 v2 并通过校验；`state.raid` 非空被拒；目录里每个事件名匹配 `^[a-z]+(_[a-z]+)*$`（扁平 snake_case）且唯一，未知事件/缺字段报错；9 个查询在 `sim.new(1)` 与跑完 3 天的状态上返回规定形状、调用前后 checksum 相同、返回值里的字符串全是 id/枚举/i18n 键；`deeds.record` 坏字段被拒、id 递增；`raid.validate_result` 正反例；`locations.validate` 接受夹具地点、拒绝缺字段；`story.pick` 对 11 个挂点返回 nil、未知挂点报错 |
| P0-5 | 夹具（§3.5） | haiku | P0-4 | `tests/fixtures/make.lua`、`tests/fixtures/*.sav`、`tests/fixtures/manifest.lua`、`sim/bot.lua`（仅 `stop_minute`）、`tests/lua/test_fixtures.lua` | CI 用 `--probes tests/fixtures/make.lua` 生成并下载；再跑 CI quick，`test_fixtures` 全过；balance 摘要不变（`stop_minute` 不影响正常路径） |
| P0-6 | 场景外壳与 `--scene/--fixture`（§3.6） | haiku | P0-0、P0-1、P0-5 | `scenes/{newrun,home,dusk,worldmap,trade,raid,dawn,ending,shell,registry,launch}.lua`、`scenes/title.lua`（仅“新局”出边）、`assets/main.lua`、`assets/i18n/*/core.lua`（`scene.*`）、`tests/probe/p0_scenes.lua`、`docs/p0_shots.txt` | CI quick：`p0_scenes` 对 4 个夹具 × 8 个场景调用 `launch.enter`，跑 3 帧，逐条触发出边，无 Lua 错误、栈深度符合预期；再用纯键盘走一遍 title→newrun→home→dusk→raid→dawn→home。CI `--shots docs/p0_shots.txt`：每张截图有场景名和按钮，三语无缺字 |
| P0-7 | 错误码文本（§3.7） | haiku | P0-1、P0-2 | `assets/i18n/*/core.lua`、`assets/i18n/*/home.lua`、`sim/commands.lua`（仅 `error_key`）、`tests/lua/test_cmd_errors.lua` | 本地 `assets.py check` 过；CI quick `test_cmd_errors` 过 |

每个任务派工前，主代理先把“验收”列写成测试并在 CI 上确认为红（§1.2）；完成后 CI 全绿才交 `codex-review:codex-reviewer`，附本节对应行、§3 对应小节和 ci_verify 摘要。返工上限按 CLAUDE.md。

## 5. 波次

```
W0  主代理：§1.1 合并、§1.3 基线（ci_verify full）；每个波次开始前，主代理先为该波任务写验收测试并确认为红
W1  P0-0 ‖ P0-2（A→B）‖ P0-3          文件互不重叠；P0-3 暂改平铺 i18n 文件
W2  P0-1 ‖ P0-4                        P0-1 迁移含 P0-3 新键的平铺文件；P0-4 不碰 i18n
W3  P0-5 ‖ P0-7                        P0-5 只碰 bot.lua 的一个选项与 tests/fixtures；P0-7 只碰 i18n 与 commands.error_key
W4  P0-6
W5  主代理：ci_verify --profile full --shots docs/p0_shots.txt；Codex 总审；PLAN §6 记“P0 已完成”；通知各线建工作树
```

P0-4 的 C6 部分若 Q1 未裁定，可从 W2 拆出，等裁定后单独做，不阻塞 P0-5、P0-6。

## 6. 风险

| 风险 | 应对 |
|---|---|
| P0-2 改名导致 balance 漂移，又说不清是改名还是逻辑变化 | 阶段 A 只加别名不改调用方，要求含 checksum 的逐字节一致；之后每一步只允许在本文指定处改 checksum |
| 本地不能跑 luatest，编码代理盲改 Lua | 每次交审必须附 ci_verify 摘要；quick 档一次约十几分钟，按波次批量提交 snapshot，不逐行试错 |
| 长按/短按改变现有手感（短按改成松开触发） | 只有存在配对的输入才延迟；`test_input_actions` 断言无配对的动作仍在按下帧触发 |
| `sys.list_files` 在 Windows 上路径分隔符或排序不同 | Zig 侧统一 `/` 与字节序排序，单测覆盖；runner 打印套件清单，便于比对 |
| 夹具过期后各线各自重生成，产生冲突 | 只有 main 上的主代理按 §3.5 重生成；`test_fixtures` 报过期时各线先合入 main |
| PANEL 控件分支仍在改平铺 i18n 文件 | Q5 定合并顺序；P0-1 合入后通知 PANEL 把新增键改写到 `assets/i18n/<lang>/ui.lua` |
| C6/C9 与 NARRATIVE 不一致却已冻结 | 不裁定不开工（Q1、Q2），其余契约照常推进 |

## 7. 待确认（主代理裁决）

| # | 问题 | 本文默认 |
|---|---|---|
| Q1（已裁决，见 §9.1） | C6 记录格式（`kind/accomplices/target{type,id}/witnessed/evidence/severity/data`）与 NARRATIVE §2.4（`verb/squad/target + target_kind/tags/witnesses/magnitude/phase`）不同，以哪个为准 | （已由 §9.5 取代）C6 按 PARALLEL-PLAN 现行字段做 |
| Q2 | C9 挂点名（`dawn, day_start, door, radio, talk, dusk, raid_enter, raid_container, raid_npc, raid_after, trade_open, crisis`）与 NARRATIVE（`door_day, radio, dawn, dusk, home_idle, raid_enter, raid_found, travel, dream, talk, crisis`）及 WORLD 片段里的 `door_day` 不一致 | （已由 §9.5 取代）SLOTS 用 NARRATIVE §2.7 的 11 个名字 |
| Q3 | `day10_1200` 不在时段边界（PLAN §4.5 只在边界存档，机器人不能从段内续跑）：保留为“仅界面”夹具，还是改为 `day10_0600` | 保留，manifest 标 `boundary = false` |
| Q4 | UI-UX §7.1 自相矛盾：`select_1..6` 用 1–6，`quick_1..4` 用 5–8，5、6 冲突 | 建议 `quick_1..4` 改 7、8、9、0，并回改 UI-UX |
| Q5 | PANEL 控件（改平铺 i18n）先于还是晚于 P0-1 合入 | 先合 PANEL 控件 |
| Q6 | 物品/配方/设施/科技/房间名称（M3 `data/` 已引用但 i18n 表里没有）以及 `char.<id>` 名字归哪个区、谁负责翻译；`char` 区归 STORY，但 HOME/PANEL 在 M4 先要用 | `items`、`tech` 区归 HOME；`char.<id>` 名字由 HOME 在 M4 补到 `char` 区，经主代理合并 |
| Q7 | `night_roles` 映射为批量的 `night.set_roles`，同时保留 C2 的 `night.set_role/set_target` 为桩，是否接受两套 | 接受；HOME 线把单项命令做实后删批量命令 |
| Q8 | `raid.autoresolve` 直接写状态（M3 行为）还是只返回 result 再由 `raid.commit` 写回 | P0 直接写，RAID 线定终态 |
| Q9 | C8 与 WORLD 的出入：`distance_min` vs `travel_min`；`danger 0..3` vs 夜袭难度 1–5；地点 id 是否等于原型 id（WORLD §1.3 是，NARRATIVE 例子是 `suburb_02`）；`occupancy` 没有“官方”（checkpoint_kilo） | （已由 §9.5 取代）按 PARALLEL-PLAN C8 现行字段写校验：地点 id = 原型 id、`travel_min`、`raid_difficulty 1..5`、`occ`、字母 `variant`、`state` 与 `alert` 分开；checkpoint_kilo 的 `occ = "hostile"` |
| Q10 | C1 表未列的顶层字段归属；`VERSION` 升到 2 并引入迁移表 | 见 §3.4 |
| Q11 | 输入层新增长按、配对、摇杆方向与上下文 F（P0-3 改派 sonnet） | 照 §3.3 |
| Q12 | 新增 Zig 绑定 `sys.list_files`（替代 i18n 清单文件和 `popen`） | 照 §3.0 |
| Q13 | CI verify 任务需归档 `out/balance/report.json`、`tests/fixtures/*.sav`、`tests/fixtures/manifest.lua`（CI 线正在做 `tools/ci_verify.sh`） | 请 CI 线加进归档规则 |
| Q14 | M3 背包是 `{ [item_id] = { count } }`，没有格位顺序；PANEL 的 `ItemGrid` 拖放后的位置无处保存 | P0 按 `(cat, item)` 排序显示；要持久顺序需改 C1 的 `home`/角色背包结构，HOME 线提出 |
| Q15 | `newrun`、`ending` 场景归属 | HOME、M9 |
| Q16 | PLAN §4.4 写 `sim.raid_begin/commit/autoresolve`，C7 写 `raid.*`；NARRATIVE 的随机流有 `fx`，M3 有 `health`、`weather`；PLAN §4.4 的事件名 `char_died/storylet_ready/snap_warning` 与 C3 不同 | （已由 §9.5 取代）PLAN §4.4 用 `raid.*`；随机流以代码 `STREAMS` 六个为准（`fx` 以后再加）；事件名全部扁平 snake_case（`char_died/storylet_ready/snap_warning/phase_changed/...`） |
| Q17 | P0 新增 P0-0、P0-7 两个任务，P0-3 改派 sonnet | 照本文 |
| Q18 | 预留命令的参数签名（§3.2 表）是现在冻结，还是由各线计划定稿后再冻结 | 现在冻结，变更走 §5 流程 |
| Q19 | ~60 个错误码的三语文本现在写（P0-7）还是等界面显示错误时再写 | 现在写 |

## 8. PARALLEL-PLAN 与现有代码的出入（供主代理回改 PARALLEL-PLAN）

1. **P0-3 列表**：`select`、`move_to`、`move_dir`、`system_menu` 已在 M2 实现；实际缺的 25 个见 §3.3。M2 的默认绑定还有 4 处与 §7.1 冲突或不符（`end_day`/`open_wheel` 同为 Back；`ui_page_*` 与 `ui_tab_*` 同为 LB/RB；`intimidate` 写成 LT+Y；没有长按机制）。
2. **§4 “runner 自动发现”**：M2、M3 的 `tests/lua/runner.lua` 都是显式列表；M3 的 `test_layering` 用 `io.popen("find …")`，在 Windows CI 上不可用。
3. **P0-1**：Lua 无法列目录，“合并同一语言的全部文件”需要新绑定或清单（本文用 `sys.list_files`）；`bake_font.py` 只扫一层；M2 工作树有一份未跟踪的旧 `tools/i18n_check.py`，与 main 版本冲突。
4. **C2**：M3 的 `commands.run` 返回三个值（`expedition` 的结果在第三个），`sim.command` 对 `end_day` 特判；`unknown_command:<kind>` 不是合法的 i18n 键；“域名即线名”与 P0-2 自己列的 `needs/craft/tech/night` 域不符，`equip/treat/activity` 也不在所列域中；spec 写成映射表，校验顺序不确定。
5. **C1**：M3 的 `state.new` 没有 `world`、`outpost`、`endings`；顶层还有 `jobs/opts/model_acc/job_seq/log/errors` 未列归属；`VERSION = 1` 且没有迁移表（PLAN §4.5 要求有）。
6. **C3**（事件名现为扁平 snake_case，见 §9.5）：M3 的 `sim/` 不用 `core/bus`，内部事件在 `state.log` 和 `clock.tick` 的返回值里（`new_day/phase/ending`）。
7. **C6、C9、C8、C7**：分别与 NARRATIVE §2.4、NARRATIVE §2.7/WORLD §10、WORLD §1.3/§6.1、PLAN §4.4 不一致（Q1、Q2、Q9、Q16；均已由 §9.5 回改，新名以 PARALLEL-PLAN §2 为准）。M3 的 `expedition.night(state, squad, hours)` 没有地点参数，机器人传的目标 `"suburb_house"` 在 `world.locations` 里不存在。
8. **P0-5**：`day10_1200` 不是时段边界，`bot.play_day` 只支持 `stop_phase`，需要新增 `stop_minute`；`sys.save_*` 只能读写存档目录且名字限 `[a-z0-9_-]`，夹具读写只能用 `io.open`。
9. **P0-6**：Lua 拿不到 `--dev`（`dev_mode` 只传给了热重载和开发控制台）；M2 用环境变量 `WS_SCENE` 进演示场景。
10. **PANEL**：PANEL-PLAN 的 `ctx` 多一个 `fixture` 字段（是 C5 的超集，无害）；PANEL 新增的 `hint.*` 前缀不在 PARALLEL-PLAN 的区表里（本文归入 `ui` 区）；PANEL 的 `ui.*` 与主代理 `ui_common` 区共用前缀，所以区按文件归属而不按前缀。
11. **i18n 覆盖**：M3 的 `data/` 引用了 `char.<id>`、`item.*`、`recipe.*`、`tech.*`、`room.*` 等键，但三语表里都没有；`i18n_check` 只查“定义了没用”，不查“用了没定义”（Q6）。

## 9. 记录

（各阶段 balance 基线 checksum、裁决结果在此追加。）

### 9.1 待确认项裁决（2026-11-14）

| # | 裁决 | 来源 |
|---|---|---|
| Q1、Q2、Q9、Q16 | **设计文档优先**：C6 记录字段、C9 挂点名、C8 地点字段、PLAN §4.4 的突袭与事件名，一律改用 NARRATIVE.md / WORLD.md 的名字（例如 `verb/squad/target_kind/tags/witnesses/magnitude/phase`、`door_day`、`raid_found`、`travel_min`）。主代理在 P0-4 派工前回改 PARALLEL-PLAN 的契约原文。设计文档自身前后矛盾的地方由主代理统一，并记在本节 | 用户 |
| Q4 | `quick_1..4` 绑定 7、8、9、0；`select_1..6` 保持 1–6。回改 UI-UX §7.1 | 用户 |
| Q5 | PANEL 控件先合入 main，再做 P0-1 | 主代理（采用默认） |
| Q3、Q6、Q7、Q8、Q10–Q12、Q14、Q15、Q17–Q19 | 采用 §7 表中的默认值 | 主代理 |
| Q13 | CI verify 任务的归档规则增加 `out/balance/report.json`、`tests/fixtures/*.sav`、`tests/fixtures/manifest.lua`，作为 W0 的一项 CI 改动（先写失败测试） | 主代理 |
| 流程 | 测试先行、CI 全绿、Codex 审查（见 §1.2） | 用户（2026-11-14） |

### 9.2 P0-0 验收第 1 轮（2026-11-14）

实现 bb92952。Windows CI #8（full）403/403 绿，luatest 在 Windows 上自动发现全部套件（229/229）。Codex（gpt-6.1-sol medium）FAIL，裁决：

| 编号 | 问题 | 裁决 | 测试 |
|---|---|---|---|
| R1 | `list_files` 打开失败（非不存在）返回空表、`walker.next` 出错当作结束、分配失败静默丢文件 → runner 可能少跑套件仍报绿 | 接受（P1）。改为 `nil, "io_error"` | `test_p0_sys.list_files_io_failure_is_not_empty_success`（打开一个文件当目录）；中途出错与分配失败无法稳定构造，靠审查核对 |
| R2 | `--scene` 解析了但 `main.lua` 没读 | 接受（主代理测试漏项） | `test_p0_sys.main_lua_reads_launch_scene` |
| R3 | `assets/`、`tests/` 下的 junction 可指向仓库外 | 不接受：这两个目录受版本控制，`list_files` 只给本仓库脚本用，没有 mod，不在威胁模型内 | — |
| R4 | Lua 分配失败 longjmp 时漏释放原生路径表和目录句柄 | 不阻塞合并（P3）：只在 Lua 堆达到 512 MiB 上限时发生，此时游戏已不可用；记入技术债 | — |

### 9.3 W0 Q13 归档审查（2026-11-14）

实现 ecd17c8（coder-haiku）。Codex FAIL 1 条，裁决：

| 编号 | 问题 | 裁决 | 测试 |
|---|---|---|---|
| A1 | `verify_steps.main` 在 zig 不存在 / 没有 `build.zig` 时 `return 2`，不归档 | 不接受：两者是基础设施错误，发生在任何步骤之前，本轮不可能产出报告或夹具 | `test_ci_archive` 注释说明 |
| A2 | 探针选择失败分支的归档无测试 | 接受（缺测试，实现已覆盖） | `test_ci_archive.test_main_collects_on_probe_selection_error` |

### 9.4 P0-3 验收测试补充裁决（2026-11-14）

| 项 | 裁决 |
|---|---|
| dev 键 | 引擎在 dev 模式用 F5 热重载（`src/iso/script_host.zig`），§3.3 的 F5–F10 改为 **F2 F3 F4 F6 F7 F8**（依次 `dev.time_prev/time_next/map_toggle/mode_toggle/roof_toggle/flashlight`）；F5 加入键盘保留键 |
| 白名单 | `SHARED_DEFAULTS` 增加鼠标右键 = `cancel`/`ui_secondary`（M2 起即同键，§7.1 两处都写右键；U 内悬停物品时为 `ui_secondary`） |
| 新接口 | `input.update(dt)`（main.lua 每帧在 `scene.update` 前调用）、`input.set_hold_s`、`input.set_dev`、`input.pan_vec`、`input.find_conflicts`、公开 `CTX_CONFLICTS`；详见 `tests/lua/test_input_actions.lua` 文件头 |
| 测试位置 | 逐动作 × 设备的触发判定在 luatest（模拟设备）与探针 `p0_inputs`（真实注入）两处做，规则共用 `tests/lua/p0_input_cases.lua` |
### 9.5 契约回改（2026-11-14）

依 §9.1 “设计文档优先”（Q1、Q2、Q9、Q16）就地回改了 PARALLEL-PLAN §2 的 C3、C6、C7、C8、C9 与 PLAN §4.4。此后 P0-4 以 PARALLEL-PLAN §2 为准；本文 §3.4 的 C3、C6–C9 段、§7 的 Q1、Q2、Q9、Q16 行与 §8 第 4–7 条里的旧名字已作废。

| 契约 | 旧 → 新 |
|---|---|
| C3 事件名 | `char.died` → `char_died`；`story.ready` → `storylet_ready`；`weather.snap_warning` → `snap_warning`（设计文档 PLAN §4.4 的写法）。“事件名带域前缀”的总则改为“以设计文档为准，未定名的暂沿用 `<域>.<动作>`” |
| C6 `kind` | `kind` → `verb`；取值改为 NARRATIVE §2.4 / WORLD §2.2 的动词表（`steal/rob/assault/knockout/kill/spare/help/give/trade_fair/trade_cheat/refuse_help/abandon/betray/rescue/bury/confess/return_goods/inform/die`）；旧值 `break_in`、`intimidate` 删除（设计文档里是 `steal/rob` 加标签 `armed_threat`），`takedown` → `knockout`，`trade` → `trade_fair`/`trade_cheat` |
| C6 同行者 | `accomplices` → `squad`（样例含 actor 本人） |
| C6 对象 | `target = { type, id }` → `target = "npc.<id>"`（队友为角色 id）+ `target_kind = civilian/raider/soldier/trader/teammate/nobody`（原 `household/npc/faction/party` 删除） |
| C6 目击 | `witnessed` → `witnesses`（活着的目击者 `npc.<id>` 列表） |
| C6 轻重 | `severity = 0..3` → `magnitude = 0..1` |
| C6 其他 | `evidence`、`data`、`minute` 删除；新增 `tags`（WORLD §2.2 标签表）与 `phase`（day/dusk/night/dawn）；`id` 递增、`day`、`phase` 由 `deeds.record` 填，接口不变 |
| C7 | 函数签名不变（`raid.begin/commit/autoresolve`）；注明与 PLAN §4.4 统一。PLAN §4.4 的 `sim.raid_begin/commit/autoresolve` → `raid.begin/commit/autoresolve`，参数 `loc` → `loc_id` |
| C8 `distance_min` | → `travel_min`（WORLD §1.3） |
| C8 `danger = 0..3` | → `raid_difficulty = 1..5`（WORLD §6.1 “夜袭难度”；设计文档只有中文名，英文字段名为本次所取，见下待裁决 #8）；另增 WORLD §8 的 `guard 0..3` |
| C8 占用 | `occupancy` → `occ`（WORLD §8 `loc.<id>.occ`），取值仍为 empty/civilian/trader/hostile |
| C8 其他 | `id` 取原型 id（WORLD §1.3，不再是 `suburb_02` 式）；新增 `state`、`attitude`、`food_days`、`members_alive`、`visits`、`looted`（WORLD §8 `loc.<id>.*`）；`unlock_day` 可为 nil（线索解锁）；`variant` 保留 |
| C9 挂点 | `dawn, day_start, door, radio, talk, dusk, raid_enter, raid_container, raid_npc, raid_after, trade_open, crisis`（12 个）→ `door_day, radio, dawn, dusk, home_idle, raid_enter, raid_found, travel, dream, talk, crisis`（11 个，NARRATIVE §2.7）。删除 `day_start`、`raid_container`、`raid_npc`、`raid_after`、`trade_open`；`door` → `door_day`；新增 `home_idle`、`raid_found`、`travel`、`dream` |
| PLAN §4.4 随机流 | `rng = { story, loot, combat, worldgen }` → 加 `health`、`weather`（与 `sim/state.lua` 的 `STREAMS` 一致）；NARRATIVE §2.9 的 `fx` 代码没有，仅在注释里列出 |
| PLAN §4.4 事件 | `bus` 说明里的名字不变（`char_died`、`storylet_ready`、`snap_warning`），补指向 PARALLEL-PLAN C3 目录 |

**待裁决（设计文档之间的矛盾，不由本节拍板；详见主代理报告）——已于文末“用户裁决（2026-11-14）”表全部裁定，下表“暂行写法”作废**：

| # | 矛盾 | 暂行写法 |
|---|---|---|
| 1 | 地点 id：NARRATIVE §2.4 样例 `loc = "suburb_02"` ↔ WORLD §1.3/§6.1 id = 原型 id、每原型一处 | C8 按 WORLD |
| 2 | 布局编号：WORLD §8 `loc.<id>.layout` 为数字 ↔ WORLD §6.2 / M2 变体为字母 A/B | C8 保留 `variant` |
| 3 | checkpoint_kilo 占用：WORLD §6.1 “敌对 100（官方）”与备注“占用固定为哨站” ↔ §8 `occ` 只有四值 | 按 `hostile` |
| 4 | `loc.<id>.state` 含 hostile/empty，与 `occ` 重叠；§9.3 又用 `loc_state(.., "alert")`，不在 §8 枚举内 | 照 §8 枚举，`alert` 未收 |
| 5 | 随机流：NARRATIVE §2.9 有 `fx` ↔ PLAN §4.4 无 `fx` ↔ 代码有 `health`、`weather` | 取代码，`fx` 待定 |
| 6 | 事件名：PLAN §4.4 扁平 snake_case ↔ PARALLEL-PLAN C3 域前缀 | 三个设计名扁平，其余暂留 |
| 7 | 动词表：NARRATIVE §2.4 列表无 `die`，WORLD §9.1 `psy_teammate_death` 用 `verb=die`；`break_in`/`intimidate`、`target` 的队友/势力格式设计文档未规定 | 加入 `die`；其余按上表 |
| 8 | “夜袭难度”无英文字段名；facts 黑板里的 `loc.*` 与 `world.locations` 字段是派生视图还是各存一份（PLAN §4.4 vs WORLD §8） | `raid_difficulty`；字段同名 |

**用户裁决（2026-11-14）**：以上 8 条全部采纳建议方案，已回改下列文档。此后以 PARALLEL-PLAN §2、NARRATIVE、WORLD 的现行写法为准；本文 §3.4、§7、§8 与上文改动表中的旧名字作废。

| # | 结论 | 落点 |
|---|---|---|
| 1 | 地点 id = 原型 id：NARRATIVE 样例 `loc = "suburb_02"` 改 `"suburb_house"`；NARRATIVE 无其他 `suburb_NN` 写法（已全文检查） | NARRATIVE §2.4；PARALLEL-PLAN C8 |
| 2 | 布局只用字母 `variant`（A/B）；WORLD §8 数字键 `loc.<id>.layout` 删除，改为 `loc.<id>.variant`（S，A/B） | WORLD §8；PARALLEL-PLAN C8 |
| 3 | checkpoint_kilo 的 `occ = "hostile"`，“官方”身份由地点 id 与 `rep.kilo` 表达，不新增枚举；WORLD §6.1 表格“100（官方）”改 100，备注重写 | WORLD §6.1；PARALLEL-PLAN C8 |
| 4 | `state` 只表示接触进度（unknown/known/visited/friendly/burned），hostile/empty 只在 `occ`；`alert` 为独立布尔字段；WORLD §9.3 的 `loc_state(.., "alert")`/`state="empty"` 改为 `loc_alert`/`loc_occ`，新增效果 `loc_occ`、`loc_alert` | WORLD §8、§9.3、文首 DSL 摘要；NARRATIVE §2.7 效果列表；PARALLEL-PLAN C8 |
| 5 | 随机流保持代码的六个（`story/loot/combat/worldgen/health/weather`），`fx` 以后再加 | NARRATIVE §2.9（加注）；PLAN §4.4（上轮已改） |
| 6 | 事件名全部扁平 snake_case，匹配 `^[a-z]+(_[a-z]+)*$`，全局唯一；P0 预置 11 个：`phase_changed day_started char_died char_wounded char_left_party char_joined_party station_changed room_temp_alert snap_warning storylet_ready raid_ended` | PARALLEL-PLAN C3；本文 §3.4 C3 目录与接线句；PLAN §4.4 本已是此写法，NARRATIVE/WORLD/UI-UX 无事件名引用 |
| 7 | 动词表补 `die`；`break_in`、`intimidate` 不设动词：撬门入户 = `steal/rob` + 标签 `break_in`，威吓 = 标签 `armed_threat`；`target` 格式：具名 NPC `npc.<id>`、队友 = 角色 id、势力 `faction.<id>`（id 同 `rep.<faction>`）、整户 `loc.<地点 id>`、无对象 nil | NARRATIVE §2.4；PARALLEL-PLAN C6；本文 §3.4 C6 |
| 8 | 字段名 `raid_difficulty`；`world.locations` 是唯一数据源，`loc.*` 事实由它派生、只读，写入走 `loc_state/loc_occ/loc_alert/loc_add/unlock_loc` | WORLD §8（末尾说明）；PARALLEL-PLAN C8 |

### 9.6 balance 基线（2026-11-14）

- **p0-baseline**：CI #11（full，main 4c0b3f 之前的 W0-ci-archive 快照，游戏代码同 main）。balance 通过，`determinism.ok = true`，checksum `bf553e5f`。报告存于 `ci/baselines/balance_p0.json`。同次 luatest 仅 `test_layering` 3 项失败（Windows 无 `popen`，P0-0 修复）。
- 对比：`python3 tools/balance_diff.py ci/baselines/balance_p0.json <out>/windows/balance/report.json [--exact]`。`--exact` 用于 P0-2 阶段 A 与 P0-4 的 C7 搬运；默认（摘要，去掉 checksum 与 determinism.a/b）用于其余步骤。checksum 获准变化后，新报告覆盖 `ci/baselines/balance_p0.json` 并在此追加一行。

### 9.7 P0-0 验收第 2 轮（2026-11-14）

返工 309685c，CI #13（quick）558/558，luatest 231/231。OpenCode（anthropic/claude-sonnet-5-5#high）复审 PASS：R1、R2 修复完整。新增 P3（不阻塞，记技术债，与 R4 同类）：`src/kit/sys.zig` 遍历子目录时原生分配失败提前返回，`Walker.deinit` 可能不关闭栈上的子目录句柄。R1 的“遍历中途出错 / 分配失败”两条路径无法稳定构造，仍只有代码审查证据（同 §9.2）。
| 旧存档绑定 | P0-3 改了默认键，M2 存下的 `settings.sav` 绑定会带回旧冲突。`export_bindings` 写入 `version = input.BINDINGS_VERSION`（2）；无版本或版本 < 2 的绑定不导入（`import_bindings` 返回 `false, "outdated"`），沿用新默认。测试 `test_input_actions.old_saved_bindings_are_not_imported` |
