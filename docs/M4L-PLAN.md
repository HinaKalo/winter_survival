# M4-lite 实施计划：家园可玩（当日试玩版）

上位：`PLAN.md §6 M4`、`PARALLEL-PLAN.md §3.1`、`UI-UX.md §3.2 / §6`。2026-11-14 用户要求“今天之内可玩”，主代理裁决：
P0 只完成 P0-2（已合入）与 P0-3（输入层），其余 P0 项（P0-1/4/5/6/7）延后到 M4-lite 之后；先交付可试玩的“在家过 3 天”。

## 1. 范围

做：
- `game/home_session.lua`（新目录 `game/`，纯模型层，不碰 iso/view/ui）：把 sim 状态包装成可玩会话——实时推进（速度档）、白天/黄昏/黎明流程、按角色列出可执行动作、HUD 数据、存读档。
- `scenes/home.lua`：用 `view/mapbuild` 把 `data/homes/ranch_a` 搭成等距地图（cutaway），`view/actors` 放出队员；站点（station）以占位道具画在所属房间内；选人、交互菜单、速度、结束白天；队员有任务时走到该任务站点所在房间（纯表现，模型以 sim 为准）。
- `ui/hud_home.lua`：顶栏（第 N 天、HH:MM、相位、室外温度、食物天数、燃料天数、瓦砾%、速度档），左侧队伍卡（名字、活动/任务、饥饿/口渴/体力/体温条），选中角色高亮；各房间温度标签画在房间上方。
- `scenes/dusk.lua`（模态）：逐人选择夜间角色 sleep/guard/out，确认提交；`scenes/dawn.lua`（模态）：显示 `s.report.lines`，确认进入新一天。
- 标题“新游戏”→ `scene.replace(home)`。
- i18n：`home.`/`dusk.`/`dawn.` 前缀键，zh/en/ko（ko 可先用英文占位但键必须存在）。

不做（留给完整 M4）：点击寻路、直接移动、手柄焦点目标自动选择、背包/制作/科技面板、挖掘、三设备完整探针、正式美术。

## 2. 关键规则

- 所有模型改动经 `sim.command`（用 P0-2 新名：`needs.eat`、`craft.start`、`home.toggle`、`night.set_roles`、`raid.autoresolve` …）。会话层的 `act` 先校验，失败不改状态。
- 动作列表：`craft:<recipe>`（遍历 `data/recipes`，`enabled = craft.can(...)`；需要 room 的配方用角色当前房间）、`research:<tech>`、`eat`、`drink`、`sleep`/`wake`、`toggle:<station>`（站点 hp>0 才 enabled）。
- 时间：`MIN_PER_SEC = 2`，`SPEEDS = {0,1,2,4}`；白天一天（06:00–19:00）在 1× 下约 6.5 分钟。
- 黄昏确认：`night.set_roles` → 推进到夜间，出门者用 `raid.autoresolve`（参照 `sim/bot.lua` 的 `night_start`）→ 推进到黎明，生成 report（夜间日志、外出收获、伤病、温度、食物/燃料），`mode = "dawn"`；黎明确认推进到 06:00。
- 每个相位边界不得丢 sim 的 phase 处理（参照 `bot.play_day` 的推进方式，用 `sim.step`）。

## 3. 验收测试（主代理编写，编码代理不得修改）

- `tests/lua/test_home_session.lua`（luatest 自动发现）：接口冻结在文件头。
- `tests/probe/home_play.lua`：纯键盘端到端（标题→家园→选人→交互菜单→加速→长按结束白天→黄昏→黎明→第 2 天）。
- 既有全部测试保持绿；平衡基线摘要不变（不改 sim/ 与 data/balance.lua 的数值）。
- 运行：`tools/ci_verify.sh --name <n> --profile quick --probes home_play --max-wait 12000`。
- 人工：截图 `--shots`（白天家园、黄昏面板、黎明报告）由主代理检查。

## 4. 分工

| 子任务 | 文件 | 代理 |
|---|---|---|
| A 会话层 | `game/home_session.lua` | coder-opencode（Sonnet medium） |
| B 场景+HUD+黄昏/黎明+标题入口+i18n | `scenes/home.lua`、`ui/hud_home.lua`、`scenes/dusk.lua`、`scenes/dawn.lua`、`scenes/title.lua`、`assets/i18n/{zh,en,ko}.lua`（键前缀 home./dusk./dawn.；P0-1 拆分前仍是单文件） | coder-sonnet（依赖 A 的接口，可先按冻结接口并行） |

## 5. 待办（审查 P3 与已知外观问题，试玩后统一精修）

- 选中角色死亡后 `M.selected` 不重选，F 无反应（按 1–6/Tab 可恢复）（`scenes/home.lua:196-218`）。
- 死亡角色的人物仍留在房间里（`sync_actors` 只遍历存活者）。
- `select_N` 超过队伍人数时回绕，应忽略。
- `recipe.insulate_I/II.name` 三语缺键（可制作时显示原始键名）。
- 提示栏 ui_up / ui_left 显示裸 “U” “L” 字形；室内墙为大块灰色；房间温度标签贴近站点标记。
- 测试 `wake_resumes_the_job` 的 `j == nil` 分支偏宽（任务完成也算过）。
- 菜单打开时时间暂停（有意为之，试玩后决定是否保留）。
