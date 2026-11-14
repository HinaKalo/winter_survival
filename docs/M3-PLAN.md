# M3 实施计划：模拟核心（无画面跑完 30 天）

上位文档：`PLAN.md §0/§4.1/§4.4/§6/§7`、`CONTENT.md §1–§6.5/§10`、`GDD.md §1.2–§1.7`、`NARRATIVE.md §2.6/§2.9`。
本文只补 M3 的落地裁定；数值一律以 `CONTENT.md` 为准，M10 调优。

## 0. 目标与验收

| # | 验收项 | 怎么验 |
|---|---|---|
| G1 | 纯 Lua 模型（`sim/`、`data/`）不 require 任何引擎库；`data/` 不含面向玩家的字面文本 | `luatest` 的 `test_layering` + `test_data` |
| G2 | `sim.new(seed)` 能建局：抽 4 名角色、生成寒潮日程、初始化家园/物品/科技 | `test_sim_state` |
| G3 | 1 游戏分钟步长的时钟、需求、伤病、温湿度、电力、制作/研究、天气全部推进 | 各 `test_sim_*`；数值断言按 CONTENT 表 |
| G4 | 机器人用**命令**跑完第 1–30 天，无 Lua 报错 | `zig build balance -Dbackend=headless` 输出 `day 30 ... alive > 0` 且 `PROBE SUMMARY` 全过 |
| G5 | 同种子两次运行状态序列化逐字节相同 | `test_sim_30d.deterministic_30_days` + balance 报告 `determinism.ok=true` |
| G6 | 存读档往返后继续跑，结果与不读档一致（在任意时段边界） | `test_sim_30d.save_roundtrip_day5_and_15`，序列化文本逐字节比较 |
| G7 | `zig build`、`zig build test`、`luatest`、`balance`、`timeout 8` 全过 | 见 §7 |

## 1. 依赖与本分支裁定

M3 分支从 M2 波次 1 的提交开始，M2 的 `core/layout.lua`（L3）尚未落地，而 `sim/home.lua`、`sim/thermal.lua` 需要房间划分。裁定：

1. **M3 在本分支实现 `core/layout.lua` 的纯解析部分**（模板解析、内外墙判定、房间连通划分、每房间的外墙/窗/门/相邻房间统计），不 require 引擎库。M2 的 L3 落地时直接复用本文件，`view/mapbuild.plan()` 在其输出上加高度/屋顶/模式规则。
2. `sim/home.lua` 只消费 `layout` 结果，不 require `view/`。M4 的家园地图与 M3 的热模型共用同一份房间划分。
3. 夜间外出、世界生成、副本、叙事不在 M3；`sim/expedition.lua` 是**明确标记的临时接缝**（`PLACEHOLDER = true`），按 CONTENT §9 的预算给机器人一条抽象的夜间补给路径。M5/M6 用真实 `worldgen`/`raid_*` 替换它，接口不变。
4. `sim/psyche.lua`、`facts/deeds/reactors/story` 属 M8；M3 只保留状态根字段（空表）与 `mood` 字段，不实现压力条目。
5. 不修改 `delve-framework`，不新增 Zig 代码（M3 是纯 Lua 里程碑）；只改 `build.zig` 增加 `balance` 步骤。

## 2. 约定

| 项 | 裁定 |
|---|---|
| 时间 | `clock.minute` = 当日 0..1439；第 1 天 06:00 开局。一个"游戏日"= 06:00 → 次日 05:59，`clock.day` 在 06:00 递增 |
| 时段 | day 06:00–18:59，dusk 19:00–20:59，night 21:00–04:59，dawn 05:00–05:59；第 30 天结束（06:00）后 `phase="ending"` |
| 步长 | `sim.step(state, minutes)` 以 1 分钟为步；`sim.advance_phase(state)` 在时段边界结算 |
| 随机 | 只用 `core/rng.lua` 的具名流：`story`、`loot`、`combat`、`worldgen`，以及 `health`、`weather`（§9.1 追加）；流状态在 `state.rng`，进存档 |
| 确定性 | 逻辑不依赖 `pairs()` 顺序（需要遍历时用 `core.util.sorted_keys`）；状态只含数字/字符串/布尔/表 |
| 存档 | `core/serialize.lua` 编码整棵 `state`；读档后先跑 `state.validate`，坏档返回错误不崩溃 |
| 单位 | 温度 °C；功率 W；热量 kWh；时间分钟；物品重量 kg；价值点 VP |
| 文本 | `data/` 只放 i18n 键（`item.<id>.name`、`tech.<id>.name`、`room.<id>.name`），不出现面向玩家的句子 |

## 3. 数据表（`assets/scripts/data/`）

| 文件 | 内容 | 来源 |
|---|---|---|
| `balance.lua` | 需求衰减、阈值、伤势/疾病、导热系数、湿度、电力、天气、效率、开局物资、抽象外出参数 | CONTENT §5–§6、§10 |
| `items.lua` | 104 件物品：`cat/tags/kg/stack/vp/use/spoil_h`（另有 `poison/wear/capacity` 等可选字段） | CONTENT §2 |
| `recipes.lua` | 烹饪、水、制作、建造/修理、医疗共 50+ 条：材料、设施、工时、科技、特长加成 | CONTENT §3 |
| `tech.lua` | 40 个科技节点：前置、材料、工时、工作台、图纸、专属、解锁 | CONTENT §4 |
| `characters.lua` | 10 张角色卡：价值观、特长/缺点数值、载重、关系倾向、开局随身物品 | WORLD §3、CONTENT §6.4.3 |
| `values.lua` | 三维价值观 + 行为权重表（M8 使用，M3 只做完整性校验） | WORLD §2 |
| `weather.lua` | 寒潮日程参数（开始日区间、持续、强度分布、核心温度） | CONTENT §6.5.2 |
| `homes/ranch_a.lua` | 家园模板：字符网格、图例覆盖、房间内固定设施（灶、坏电暖器、坏发电机、床、储物）与开局破损 | GDD §1.5；格律同 M2-PLAN §2.1 |
| `legend.lua` | 通用图例：`#` 墙、`=` 内墙、`.` 室内、`,` 室外、`+` 内门、`D` 外门、`w` 窗、空格 void | M2-PLAN §2.1 |

`core/layout.lua` 输出（纯表，可序列化）：

```lua
{ width, height, cells = { {kind, material, prop, room} ... },  -- 行优先
  rooms = { [id] = { id, cells, area, envelope = {wall=n, window=n, hole=n, door=n},
                     openings = { {kind, x, y} }, links = { {room, kind="door"|"wall", count} } } },
  props = { {x, y, prop, slot, room} } }
```

## 4. 模拟模块（`assets/scripts/sim/`）

| 文件 | 职责 | 主要接口（以代码为准） |
|---|---|---|
| `state.lua` | 状态根、校验、序列化、日志 | `state.new(seed)`, `state.validate(s) -> ok, err`, `state.encode(s)`, `state.decode(txt) -> s \| nil, err`（内部 pcall，坏档不崩溃）, `state.checksum(s)`, `state.stream(s, name)`, `state.log(s, event, data)`, `state.error(s, msg)` |
| `clock.lua` | 时间与时段 | `clock.phase_at(minute)`, `clock.tick(state)`（1 分钟，返回事件）, `clock.advance(state, n)`, `clock.abs_minute(state)`, `clock.hour/clock_text/is_night/is_work_time` |
| `weather.lua` | 寒潮日程、日/时温度、预报 | `weather.generate(state)`, `weather.outdoor_temp(state)`, `weather.update_outdoor(state)`, `weather.snap_on(state, day)`, `weather.is_big_snap_day`, `weather.wind_chill`, `weather.radio_level`, `weather.forecast_spec`, `weather.refresh_forecast(state)` |
| `chars.lua` | 抽人、角色派生值、关系、穿戴 | `chars.draw(state, n)`, `chars.create(state, id)`, `chars.setup_relations(state)`, `chars.alive(state)`, `chars.alive_ids`, `chars.efficiency(state, id\|ch)`, `chars.speed`, `chars.capacity`, `chars.slots`, `chars.wound/morale_state`, `chars.equip/unequip`, `chars.relation/add_relation`, `chars.kill` |
| `needs.lua` | 饱食/水分/体温/精力、进食饮水 | `needs.tick(state, dt)`, `needs.eat(state, ch, item?)`, `needs.drink(state, ch, item?)`, `needs.consume_item(state, ch, item)`, `needs.sleep(state, ch)`, `needs.wake(state, ch)` |
| `health.lua` | hp、三级伤势、四种疾病、用药/治疗、死亡 | `health.tick(state, dt)`, `health.daily(state)`, `health.add_wound(state, ch, amount, cause)`, `health.heal`, `health.add_disease/remove_disease`, `health.treat(state, patient, actor, item)` |
| `inventory.lua` | 背包/储物、标签统计、按 VP 扣除、载重 | `inventory.new`, `add(bag, id, n, opts)`, `remove(bag, id, n)`, `count`, `count_tag(bag, tag)`, `team_count(state, tag)`, `consume_tag(state, tag, n)`, `consume_tag_from(bag, tag, n)`, `burn_fuel`, `weight(bag)`, `slots_used(bag)`, `spoil_tick`, `move`, `validate(bag, where)` |
| `home.lua` | 家园状态：房间、设施、破损、房间归属 | `home.init(state, opts)`, `home.add_station(state, id, kind, room, hp, on)`, `home.usable_station(state, kind)`, `home.assign(state, cid, room)`, `home.set_toggle(state, id, on)`, `home.set_insulation`, `home.board_window/board_hole`, `home.repair_station`, `home.add_cold_cell`, `home.rebuild`, `home.room_temp`, `home.tick` |
| `thermal.lua` | 逐房间温度节点、体热、热源、结霜 | `thermal.tick(state, dt)`, `thermal.room_temp`, `thermal.room_g`, `thermal.link_g`, `thermal.station_heat`, `thermal.effective_temp` |
| `power.lua` | 发电机/蓄电池/用电设备/燃料 | `power.tick(state, dt)`, `power.load(state)`, `power.burn`, `power.burn_heat`, `power.available(state)` |
| `craft.lua` | 制作/建造作业队列 | `craft.can(state, recipe_id, cid, opts) -> ok, err`, `craft.start(state, recipe_id, cid, opts) -> ok, job`, `craft.tick(state, dt)`, `craft.cancel(state, job_id)`（研究作业转 `tech.cancel`；进度 < 1 分钟全额退料否则不退）, `craft.available`, `craft.bench_level` |
| `tech.lua` | 研究队列、图纸、解锁设施 | `tech.can(state, node_id, actor_id)`, `tech.start(state, node_id, actor_id)`, `tech.tick(state, dt)`, `tech.cancel(state, reason)`, `tech.learn_blueprint(state, actor_id, item_id)`, `tech.cost_for/work_for/exclusive_missing`, `tech.available` |
| `expedition.lua` | **临时**夜间抽象补给（M5/M6 替换） | `expedition.night(state, squad, hours) -> result` |
| `commands.lua` | 玩家对模型的唯一入口（校验全部输入，坏输入返回 `false, err`） | `commands.run(state, cmd) -> ok, err, extra`（`eat/drink/use/equip/unequip/sleep/wake/assign/activity/craft/cancel_job/research/cancel_research/toggle/set_level/set_door/board/treat/learn_blueprint/night_roles/expedition`；`expedition` 的结果在第三返回值）；`commands.can(state, kind)` |
| `sim.lua` | 建局与驱动 | `sim.new(seed, opts)`（`opts.kit = "bot"` 在建局时放入参考物资）, `sim.step(state, minutes)`, `sim.advance_phase(state, to, from)`, `sim.end_day(state)`（逐分钟推进到 19:00，不取消作业）, `sim.run(seed, days, opts)`, `sim.command(state, cmd)`（含 `end_day`，其余转 `commands.run`）, `sim.audit(state)`/`sim.audit_into(state)`（validate + 台账 + NaN 扫描）, `sim.summary(state)`, `sim.food_days/fuel_days` |
| `bot.lua` | 参考机器人（只用 `sim.command`，不直接写状态，不加物资） | `bot.play_day(state, opts)`（`opts.stop_phase` 供存档测试）, `bot.run(state, opts) -> summary`, `bot.morning/dusk/night_start/dawn/manage` |
| `lint.lua` | 数据引用完整性 | 未单独成文件：引用完整性由 `test_data.lua` 覆盖，DSL 校验留给 M8 |

### 4.1 温湿度与电力（CONTENT §6.2/§6.3/§5）

- 房间热容 `C = 12 Wh/°C × 格数`；每分钟 `T += (Qin − Qout)/(C × 60)`。
- 围护 G：完好墙 2.0、墙洞 9.0、完好窗 3.0、破窗 7.0、封板 3.0、外门关 3.0/开 14.0、屋顶+地面 0.6/格；内墙 0.5、内门关 0.9/开 7.0。
- 保温 I ×0.7、II ×0.5（只乘墙/封板/屋顶，不乘门窗）；结霜时保温降一级。
- 热源与体热、湿度、发电机/电池按 CONTENT §5.1/§5.2/§6.3 的数值；开局电暖器、发电机、加湿器损坏，只有灶可用。
- 燃料按件的小数累计：设施维护 `fuel_frac`，凑满 1 件才扣 1 件。

### 4.2 效率与伤病

- `chars.efficiency` 按 CONTENT §6.4.3 乘：特长（配方级）、伤势、疾病、心理、精力、体温、饥渴、止痛药、工作台。
- 伤势由隐藏 `hp` 推出；疾病用 `char.disease = { cold={left,med}, pneumonia={days,doses}, frostbite={left,treated}, food_poison={left} }`。
- 死亡：从 `party.order` 移除（保留 `party.chars[id].dead=true` 供叙事/尾声查询）。

## 5. 机器人与 `zig build balance`

`sim/bot.lua` 的每日循环（全部走 `commands.run`）：

1. 06:00 起床：叫醒、装备、供暖，进食/饮水到 ≥65；把所有人分配到当前最暖的房间。
2. 供暖：按房间温度与燃料存量开关灶/电暖器/柴火炉；发电机开着时优先电暖器；发电机只给确实需要的设备供电。
3. 白天作业优先级：修电暖器/发电机 → 保温 I/II → 封窗/堵洞 → 研究（工作台/科技）→ 做饭/煮水 → 制作冬装 → 清理废墟。
4. 19:00 晚餐（≥75）、定夜间角色：外勤型 1–2 人外出（`expedition`），其余睡觉，1 人守夜（若 ≥3 人）。
5. 21:00 后睡觉；外勤只结算一次，守夜者整夜值守（M3 简化，M4/M8 再做换班）；夜间每 10 分钟复检供暖与需求。
6. 05:00 黎明：补食水到 ≥55、重新分配工作；第 30 天结束输出报告。

`zig build balance [-Druns=N] [-Ddays=30] [-Dseed=S] [-Dverify=true|false]`：

- 清理 `.zig-cache/test-saves/balance`，以 headless 运行 `tests/lua/balance_main.lua` + `tests/lua/balance_runner.lua`。
- 默认 `N=1`（M3 单局验收；M10 批量用 `-Druns=500`）。每个种子跑满 30 天，输出 `out/balance/report.json` 与 `report.html`：
  - 每局：存活人数、死亡日与死因、最终食物/燃料天数、最低体温、最冷/最暖房间、制作/研究/外勤次数；
  - 全局：平均存活人数/天数、`determinism`（同种子两次序列化 checksum 比较，`-Dverify=false` 可跳过）、`errors` 列表；
  - 任一台账不平衡（负值、NaN、count<0）或存活人数为 0 即 `ok_all=false`，探针检查失败。
- `-Ddays` 可缩短验收，但 CI 默认 30；`-Dseed` 改首种子。

### 5.1 M3 参考开局 / 参考避难所（**调参占位，不是正式数值**）

为了让 30 天验收在固定种子上可重复，`data/balance.lua` 目前带有几组"M3 参考"设定。它们的唯一目的是让参考机器人跑通整条模型链路；**balance 报告里的存活率、食物/燃料天数只用于回归对比，不能当作正式难度或经济数值**。M10 按 `CONTENT.md §10` 重新标定，并移除下表左列的占位：

| 占位 | 当前值 | 用途 | M10 处理 |
|---|---|---|---|
| `thermal.reference_insulation` | 2 | 所有房间开局按保温 II 计算，避免第一晚直接冻死 | 改为 0，让玩家从修房/封窗开始 |
| `humidity.frost_loss_per_hour` | 0 | 关闭"结霜掉保温"的长期惩罚 | 恢复 1.5/h 与结霜降级 |
| `start_stash` | 26 种、明显宽于 CONTENT §10.2 | 保证首周能完成修电暖器/保温 I | 按 CONTENT §10.2 收紧 |
| `start_blueprints` | `t_insulation_2`, `t_wood_stove` | 让参考机器人有明确的冬季路线 | 改为 CONTENT §4.3 的图纸掉落 |
| `bot_kit` | 额外建材/燃料/蓝图 | 只在 `sim.new(seed, {kit="bot"})` 建局时放入，`bot.run` 与玩家流程默认不使用 | 删除 |
| `expedition` | `PLACEHOLDER = true` | 夜间抽象补给，替代 M5/M6 的世界生成与突袭 | 用真实 `worldgen` + `raid_autoresolve` 替换 |
| `balance.expedition.risk` | 固定受伤概率 | 让外勤有代价，避免抽象补给变成无风险刷物资 | 由 M5/M6 战斗与天气结算取代 |

判读报告时请同时看：`runs`、每局 `alive`/`deaths`、`determinism.ok`、`errors`。同种子两次 checksum 不同、或 `errors` 非空，说明是模型/序列化 bug，而不是数值问题，先修代码再谈调参。

## 6. 测试

| 文件 | 覆盖 |
|---|---|
| `test_layering.lua` | `sim/`、`data/` 不 require 引擎库；`data/` 无玩家文本 |
| `test_data.lua` | 物品 id/标签/堆叠/VP 全部合法；配方与科技引用的物品/科技存在；角色 10 人、价值观三维；模板行等长、字母有定义 |
| `test_sim_clock.lua` | 时段边界、日递增、第 30 天结束 |
| `test_sim_inventory.lua` | 堆叠、载重、标签统计、按 VP 扣除、变质 |
| `test_sim_needs.lua` | 各活动衰减、阈值效率、进食饮水 |
| `test_sim_health.lua` | 伤势分级、愈合、饥饿/失温伤害、疾病触发与治疗、死亡 |
| `test_sim_thermal.lua` | G 计算、保温、门窗开闭、稳态温度、结霜 |
| `test_sim_power.lua` | 负载、发电机油耗、电池充放、设备停机、柴/煤热源切换 |
| `test_sim_craft.lua` | 材料/设施/科技门禁、工时、产出、特长加成、跨时段长作业不取消 |
| `test_sim_tech.lua` | 前置、图纸、专属 ×1.5、★ 首件设施 |
| `test_sim_bot.lua` | 参考机器人启用已修好的电暖器/发电机；暖房自动停机 |
| `test_sim_weather.lua` | 寒潮日期/强度/形状、日温曲线、预报等级 |
| `test_sim_state.lua` | 建局、校验、坏档、序列化往返 |
| `test_sim_30d.lua` | 同种子 30 天两次逐字节相同；第 5/15 天存读档后继续一致；无 NaN/负库存 |

## 7. 验收命令

```bash
mise exec -- zig build
mise exec -- zig build test
mise exec -- zig build luatest -Dbackend=headless
mise exec -- zig build balance -Dbackend=headless
mise exec -- zig build probe -Dbackend=headless -Dprobe=tests/probe/smoke.lua
python3 tools/assets.py check
timeout 8 ./zig-out/bin/winter_survival --no-audio
```

## 8. 风险与交接

| 风险 | 应对 |
|---|---|
| 30 天 × 1440 分钟 × 500 局的 Lua 性能 | 分钟步内只做必要计算；热/电按 5 分钟聚合（`balance.model.step_minutes = 5`），需求/伤病按分钟；M3 默认单局验收，M10 再上 500 |
| `pairs` 顺序破坏确定性 | 序列化键排序；逻辑遍历一律 `util.sorted_keys`；测试用两次运行逐字节比对兜底 |
| 浮点跨平台差异 | 不比较不同平台的字节；CI 的确定性断言在同一二进制内做 |
| M2 的 `core/layout.lua` 与 M3 版本冲突 | M3 只实现纯解析 + 测试；M2 的 `mapbuild.plan` 在其输出上加高度，不重复解析 |
| 临时 `expedition` 被误当正式设计 | 文件头 `PLACEHOLDER = true`；M5 计划删除并替换为 `worldgen` + `raid_autoresolve`；balance 报告标注 |

## 9. 返工 1（2026-11-14，主代理核验）

验收命令全过（luatest 85/85、balance 第 30 天 4 人存活且确定性一致、两种构建、assets、timeout 8），但三路代码审查均 FAIL。按 CLAUDE.md 进入第 1 次返工。

### 9.1 裁定（子代理照做，不再自行决策）

| 项 | 裁定 |
|---|---|
| 效率组合（CONTENT §6.4.3） | 伤势与疾病两类惩罚：只有一项时取该值；多项时取最小一项 × 0.9。其余因子（特长、心理、精力、体温、饥渴、工作台）照乘。止痛药使伤病惩罚减半（`1 - (1-x)/2`） |
| 载重（§6.4.1） | 轻伤 ×0.9、重伤 ×0.6、肺炎 ×0.7；装备背包后同步更新背包 `kg_cap`/`slots` |
| 濒死 | 饱食 0 满 72 h、水分 0 满 36 h：hp 夹到 ≤ 10（进入濒死档），不只记 `critical_cause` |
| 删除无出处机制 | `health` 中“≥45 伤害 25% 夹到 40 hp”删除；抗生素每天最多 1 剂 |
| 作业与活动 | 只在 `activity == "work"` 且效率 > 0 时推进；睡觉/外出/守夜时暂停并保留 `ch.job`，黎明恢复 `work`；改活动不取消作业；去掉 0.05 下限 |
| 取消作业 | 只能显式 `cancel_job`；进度 < 1 游戏分钟全额退料，否则不退；研究作业走 `tech.cancel` |
| `end_day` | 移到 `sim.lua`，用 `sim.step` 逐分钟推进到 19:00，不取消作业；删除 `sleep_until_dawn` |
| 设施档位（CONTENT §3.1） | `hearth` 配方可用 简易灶/改良灶/柴火炉；`benchN` 配方可用 ≥ N 级工作台；工作台速度只作用于“台” |
| 机器人 | 删除 `bot.apply_kit` 的直接写状态与 `state._bot_kit`；参考开局物资改由 `sim.new(seed, {kit="bot"})` 在建局时放入，`bot.run` 默认不加料 |
| 冷格（cold cell） | 双向链接；G 由 `balance.thermal` 与围护统计算，`cold_cell_mult` 生效 |
| 灶的湿度 | 只在做饭/煮水作业进行中 +1.5/h |
| 冻伤 | 只在室外判定（照 §6.2.3 文字） |
| 寒潮日程 | 第 2、3 次寒潮开始日在 13–17、21–24 内用 `rng` 抽取并满足间隔约束；linwei 预报修正照 §6.5.3 |
| RNG 流 | 接受 `health`、`weather` 两条额外具名流；§2 表格以此为准 |
| 疾病字段位置 | 保持 `char.health.disease`；死亡时同时设 `dead = true` 与 `status = "dead"` |
| `layout` 输出 | 照 §3：`rooms[id].cells` 为格子列表（数量用 `area`），删除 `cell_list`；`links` 按 kind 分条（door / wall 各一条）；新增顶层 `props` 列表（含 `room`）；外墙格同时邻接多房间时按 DIRS 顺序取第一个；内墙每对房间都建链接；锚点重复返回 `nil, err`；任何畸形模板返回 `nil, err` 不崩溃 |
| 台账检查 | balance 与 `test_sim_30d` 每天跑 `state.validate` + 台账/NaN/负数扫描，失败写入 `state.errors`，`ok_all` 依赖它 |
| 调参占位 | 修完物理后若参考机器人第 30 天全灭，只允许改 §5.1 表里已标注的占位值，并在 §5.1 记录新值 |

### 9.2 分工（文件互不重叠；`data/balance.lua` 只在自己的分节内做小范围编辑，不整体重写）

| # | 代理 | 文件 | 内容 |
|---|---|---|---|
| M3-R1 | sonnet | `core/layout.lua`、`sim/home.lua`、`sim/thermal.lua`、`sim/power.lua`、`tests/lua/test_layout.lua`、`test_layering.lua`、`test_sim_thermal.lua`、`test_sim_power.lua`；`balance.lua` 的 `thermal`/`power`/`humidity` 分节 | 审查 A 1–4、B 1–4/13/14（thermal 部分）；layout 契约按 9.1 调整并修好所有使用方；数值测试（G 值、§6.2.4 算例 G≈53.6、柴火炉 0.4/1.0、发电机 0.2+0.5×负载比、充电 85%） |
| M3-R2 | sonnet | `sim/chars.lua`、`health.lua`、`needs.lua`、`inventory.lua`、`weather.lua` 及对应 `test_sim_*`；`balance.lua` 的 `health`/`needs`/`chars`/`weather` 分节 | 审查 B 5–12、14（除 thermal）、15，A 非阻断 1；全部数值测试 |
| M3-R3 | sonnet | `sim/state.lua`、`sim.lua`、`commands.lua`、`craft.lua`、`tech.lua`、`bot.lua`、`expedition.lua`、`tests/lua/balance_runner.lua`、`test_sim_state/craft/tech/bot/30d.lua`、删除 `tests/probe/{bot_debug,bot_trace,sim_debug,sim_trace,thermal_debug}.lua`、本文 §4 接口表与代码对齐；`balance.lua` 的 `start_stash`/`bot_kit`/`expedition` 分节 | 审查 C 1–10 与非阻断；§4 表改为实际函数名 |

完成后主代理跑 §7 全部命令；之后统一复审。

### 9.3 第 2 次审查 FAIL 的根因与最后一次返工的裁定

根因：
1. 计划只规定了“命令层先校验再修改”，没有覆盖 `craft.start` 内部（燃料检查与实际燃烧规则不一致，先扣材料后烧燃料）。
2. 把参考开局物资移到 `sim.new` 时，没有写明验收跑（balance、30 天测试、bot_days 探针）必须带上它。
3. 按文件拆分后出现跨模块缺口：R2 把开局衣物放进 `wear`，R3 的审计却不查 `wear`。
4. 审查代理无法运行 Lua，只能手推；本轮要求编码代理以实际运行结果为准，凡审查手推与运行结果不符的，以运行为准并在报告中说明。

裁定（本轮只能照做，不再自行决策）：
| 项 | 裁定 |
|---|---|
| 所有会改状态的函数 | 一律“先全部校验、后修改”；`craft.start`、`tech.start` 用与实际燃烧完全相同的燃料规则（`floor(fuel_frac + n × 燃料倍率)` 对比库存整数）预检，任何检查失败都不得已扣材料 |
| 验收跑 | `balance_runner`、`test_sim_30d`、`tests/probe/bot_days.lua` 都用 `sim.new(seed, {kit = "bot"})`，即 §5.1 的参考开局 |
| 开局衣物 | 属于“角色自带、不计预算”（CONTENT §10.2），保留在 `wear`；审计必须检查 `wear`（每个槽位是已知物品），并加库存守恒总账（stash + 背包 + wear，按来源/去向记账，跑完 30 天不平衡即错误） |
| 冷格门 | 按 CONTENT §5.3 的冷格专表取 0.6（`balance.thermal.cold_cell_door_g`）；冷格面积/墙/保温常量全部从 `balance.thermal.cold_cell_room` 读取 |
| 风寒 | 照 §6.2.3 文字：所有寒潮日都算，不只大寒潮 |
| CONTENT 未给出的数值 | 不删机制，移入 `balance.lua` 并注释 `-- M3 占位，非 CONTENT 数值`，同时列入 §5.1 占位表（感染 5 hp/天、体温心情 −0.4、急救后体温 20、超重规则等） |
| 漏实现的 CONTENT 数值 | 加湿器湿度 ≥ 60 时停机不耗电；灶做饭中 +400 W；冻伤治疗需房间 ≥ 12 °C + 绷带 |
| 其它 | `ranch_a` 的开局破窗键统一为 `broken_windows`；冷病传染按同房间病人计；锚点必须是字符串 id、落在开放格、每个锚点只认领一次，否则 `nil, err`；伤势阈值读 `balance.health`；成功的 craft/research 命令返回 `true, nil, job`；`state.validate` 补查 stash、背包、wear、作业表；`garage` 设施的交接说明写入 §8 |
