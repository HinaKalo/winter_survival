# M4 实施计划：家园可玩（完整版）

上位：`PLAN.md §6 M4`、`PARALLEL-PLAN.md §3.1`、`UI-UX.md §3.2 / §6`。前置：M4-lite（`docs/M4L-PLAN.md`，分支 `M4L`）——
会话层 `game/home_session.lua`、家园场景、HUD、黄昏/黎明面板、标题“新游戏”。本计划只列 M4-lite 之后剩下的部分。

M4 验收（PLAN §6）：三种输入的“白天”探针通过；能清理房间、修好加热器、做饭、睡觉，室温随操作变化。M4 结束是用户试玩检查点。

## 1. 任务表

| 编号 | 任务 | 文件 | 负责 | 依赖 |
|---|---|---|---|---|
| **U1** | 焦点目标自动选择（UI-UX §6.4 公式） | `view/focus_target.lua`（新，纯函数） | **用户** | 无，可立即开工 |
| **U2** | 家园试玩与手感记录 | `docs/playtest/M4L.md`（新） | **用户** | M4-lite 合入 main |
| **U3** | 手柄实机手感（P0-3 输入层） | 同上，单列一节 | **用户** | P0-3 合入 main |
| **U4** | 站点/瓦砾在地图上的格位 | `data/homes/ranch_a.lua` 增加 `stations[i].at = {x, y}`、`rubble_cells` | **用户**（设计数据） | 无 |
| **U5** | 改键保存后重启不丢（`core/save.lua` 的 `load_settings` 跳过 defaults 为 nil 的 `bindings`） | `core/save.lua` 或 `ui/settings.lua` | **用户** | 无 |
| A1 | 点击寻路移动 + 路径预览（§6.2、§6.7） | `view/select.lua`、`view/camera_ctl.lua` | 用户 | M4-lite |
| A2 | 直接移动（`move_dir`，WASD/左摇杆） | `scenes/home.lua` | 用户 | M4-lite |
| A3 | 世界内交互：悬停高亮、上下文菜单按对象生成（§6.3、§6.6） | `view/interact.lua` | 用户 | U1、U4 |
| A4 | 暂停时指令排队（§6.8） | `game/home_session.lua` 扩展、`ui/hud_home.lua` | 用户 | A3 |
| A5 | 背包/制作/科技面板接入（`open_inventory/craft/tech`） | `scenes/home.lua` 挂接 PANEL 面板 | 用户 | M4-lite |
| A6 | 三设备白天探针 `loop_keyboard/mouse/pad.lua`（白天部分） | `tests/probe/` | 主代理写验收 | A1–A5 |
| A7 | P0 剩余项（P0-1/4/5/6/7） | 见 `P0-PLAN.md` | 用户 | 与上面并行 |

## 2. 用户任务说明

### U1 焦点目标自动选择
- 分支/工作树：`M4-user`（`/home/smile-user/dev/winter_survival-M4-user`）。
- 验收测试：`tests/lua/test_home_focus_target.lua`（文件头冻结接口与规则；不要改测试，觉得有误告诉主代理）。
- 写 `assets/scripts/view/focus_target.lua`：`R`、`PRIO`、`score(actor, cand, f)`、`pick(actor, cands, opts)`。纯 Lua，不调用 `iso`。约 60–90 行。
- 跑测试：`tools/ci_verify.sh --name m4-u1 --profile quick --max-wait 12000`，在 `windows/luatest.log` 里看 `PROBE PASS test_home_focus_target.*`（8 项）。
- 完成后提交到 `M4-user`，告诉主代理；主代理安排审查后合并。

### U2 家园试玩（M4-lite 合入后）
在 Windows 上 `zig build run`（或主代理给的命令）从标题点“新游戏”，玩满 3 天，记录到 `docs/playtest/M4L.md`：
1. 时间节奏：1× 下一个白天约 6.5 分钟，太快/太慢？（会话层 `MIN_PER_SEC`）
2. 动作菜单：找得到想做的事吗？哪些条目看不懂？
3. 温度与生存压力：第 1–3 天冷不冷、饿不饿，有没有“必须做点什么”的感觉？
4. 黄昏/黎明面板：信息够不够、读不读得懂？
5. 卡住、报错、画面错位：截图 + 当时在做什么。
每条写“现象 / 期望 / 严重度（阻断、难受、小问题）”。主代理据此写测试并返工。

### U3 手柄实机
P0-3 合入后用真实手柄过一遍：短按/长按（Back = 轮盘 / 长按结束白天，Start = 暂停 / 长按系统菜单）、右摇杆方向翻页的重复节奏（0.35 s 后每 0.09 s）、LT 组合键、长按时长设置 `acc.hold_duration` 是否生效。记在 `docs/playtest/M4L.md` 的“手柄”节。

### U4 站点与瓦砾格位
`data/homes/ranch_a.lua` 的 `stations` 目前只有所属房间，场景把站点画在房间中心。按你对这栋房子的想象给每个站点定格位，并标出瓦砾堆的格子：
- `stations[i].at = { x, y }`：必须在所属房间内的地板格（网格里的 `.`），不压门、不堵通道。
- `rubble_cells = { {x, y}, ... }`：大致 8–12 格，堵住一部分房间，清理后可通行。
- 只改数据，不改代码；提交到 `M4-user`。主代理会补一条校验测试（格位在房间内、可通行性）。

### U5 改键持久化
- 验收测试：`tests/lua/test_home_bindings_persist.lua`（2 项：改键重启后仍生效；无 version 的旧绑定被丢弃、其余设置照常读入）。
- 修法提示：`load_settings` 只合并 defaults 里存在的键；`bindings` 默认为 nil，所以从未读回。最小改动是在 `load_settings` 里单独处理 `bindings`（table 时原样拷贝），版本校验仍由 `settings.apply` → `input.import_bindings` 负责。`core/` 归主代理，本项已授权修改 `core/save.lua`。

## 3. 规则
- 2026-11-14 起编码任务全部由用户执行；主代理负责计划、验收测试（红灯）、调用审查（Codex / OpenCode 轮流）、合并。已在跑的 M4-lite 两个代理任务（场景、P0-3 返工）跑完为止。
- 合并顺序：M4-lite → P0-3 → U1/U4 → A1…A5 → A6。
