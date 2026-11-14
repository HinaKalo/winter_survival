# 叙事与道德系统 v1

本文先讲原理，再给 Lua 实现。它是本作 Lua 逻辑的核心，由主代理定稿并逐项验收。玩法背景见 `GDD.md`，内容目录见 `CONTENT.md`。

## 2. 叙事与道德系统：原理与 Lua 设计

这一节先讲原理，再给实现。它是本作 Lua 逻辑的核心，由主代理亲自定稿并逐项验收。

### 2.1 "伪开放世界"靠什么成立

这类游戏没有大地图，玩家却觉得自由、觉得世界是活的，靠的是三件事：

1. **有限的行动额度**。每天只有一个白天、一个夜晚、4 个人。去药房就去不了农场，派两个人出去家里就少人守夜。自由感来自"每个选择都放弃了别的选择"，不来自地图面积。
2. **同一个地点有多种对待方式**。同一户人家，可以白天去交易、夜里去偷、持械去抢、放过不动、送东西去帮。地点少，但每个地点的可能性多。
3. **世界会记账**。你做过的事被记下来，过几天以别的形式回来。玩家一旦发现"上周那件事居然有后续"，就会把整个世界当成活的。

所以我们不模拟一个大世界，只模拟一个**小而深的状态集合**：十几个地点、几十个具名 NPC、几个势力，每个都带着"它对你的记忆"。

### 2.2 道德抉择的八条设计原则

| # | 原则 | 在本作里的做法 |
|---|---|---|
| 1 | 抉择来自系统压力，不来自对话选项 | 不弹"你要做好人还是坏人"。是队友发烧而药只在一户有孩子的人家里，玩家自己走到这一步 |
| 2 | 两难 = 两个都正当的需求相撞 | 每个高价值目标都绑一个正当的主人；每次求助都要付出自己也缺的东西 |
| 3 | 作恶在数值上必须划算 | 抢比换拿得多。代价付在别处：心理、关系、世界变危险。否则不是抉择 |
| 4 | 行善必须有成本，回报不保证 | 帮人要付物资和时间。多数没回报，少数回报丰厚，玩家无法事先分辨 |
| 5 | 不显示善恶数值 | 系统只记录行为。评价来自队友（每人价值观不同）和世界（受害者、邻居、士兵的反应） |
| 6 | 后果要延迟，但能追溯 | 后果在 2–5 天后出现，出现时文本明确点出起因，让玩家认出因果 |
| 7 | 受害者要具体 | 有住户的地点里每个人有名字、一句台词、一件个人物品。偷走的不是"3 个罐头"，是"米勒家最后的存粮" |
| 8 | 灰度和退路 | 用标签区分轻重（偷空屋 ≠ 偷有人家 ≠ 抢 ≠ 杀；有无目击；对象是谁）。提供归还、照料、坦白等修复途径，避免心理崩溃变成无解的死亡螺旋 |

还有一条贯穿的规则：**不作为也记账**。不开门、路过不救、听见求救不回应，都是行为。

### 2.3 架构：四层

```
  玩法层（家园 / 副本 / 交易）
        │ 发出"行为"
        ▼
 ┌──────────────┐   ┌──────────────┐
 │ 行为账本 Deeds │──▶│ 反应规则 Reactors │── 改写 ──┐
 └──────────────┘   └──────────────┘          ▼
                                        ┌──────────────┐
        ┌──── 查询 ─────────────────────│ 事实黑板 Facts │
        ▼                               └──────────────┘
 ┌──────────────┐   挑选   ┌──────────────┐      ▲
 │ 导演 Director │────────▶│ 故事片段 Storylets │── 效果 ─┘
 └──────────────┘          └──────────────┘
```

- **事实黑板（Facts）**：世界当前状态的唯一出处。扁平的"键 → 值"表，键带命名空间。
- **行为账本（Deeds）**：只增不改的列表，记录"谁、在哪、对谁、做了什么、谁看见了"。
- **反应规则（Reactors）**：把一条行为翻译成后果的规则。分三族：心理、社会、世界。
- **故事片段（Storylets）**：带触发条件的小段内容（文本 + 选项 + 效果）。不排成固定的树，放在一个池子里，条件满足的才有资格出现。
- **导演（Director）**：在每个时机从有资格的片段里挑一个，并控制节奏。

这个结构的好处：加内容只是往池子里加片段和规则，不用改流程代码；片段之间通过事实间接联系，组合出作者没有逐条写过的情节。

### 2.4 行为与反应

**行为记录**（`sim/deeds.lua`）：

```lua
-- deeds.record{} 写入的一条记录
{
  id = 137, day = 7, phase = "night",
  verb = "steal",            -- steal / rob / assault / knockout / kill / spare / help / give
                             -- trade_fair / trade_cheat / refuse_help / abandon / betray
                             -- rescue / bury / confess / return_goods / inform / die
                             -- die = 病、冻、事故致死，无动手者（WORLD §2.4）；没有 break_in、intimidate 动词：
                             -- 撬门入户 = steal/rob + 标签 break_in，持械威吓 = 标签 armed_threat（WORLD §2.2）
  actor = "sam",             -- 动手的人；squad 列出同行者
  squad = { "sam", "tasha" },
  target = "npc.miller_ruth", target_kind = "civilian",   -- civilian/raider/soldier/trader/teammate/nobody
                             -- target 格式：具名 NPC "npc.<id>"；队友 = 角色 id（如 "grace"）；势力 "faction.<id>"
                             -- （id ∈ civilians/st_mark/traders/raiders/kilo，同 rep.<faction>）；整户 "loc.<地点 id>"；无对象 nil
  loc = "suburb_house",      -- 地点 id = 原型 id（WORLD §1.3，每原型一处）
  tags = { occupied = true, victim_vulnerable = true, took_essentials = true, lethal = false },
                             -- 标签表见 WORLD §2.2；break_in 只是标记（无权重行），armed_threat 有权重行
  witnesses = { "npc.miller_ruth" },   -- 活着的目击者
  magnitude = 0.6,           -- 0..1，被拿走的东西对受害方有多要紧
}
```

**价值观**：每名角色有一个三维价值观向量，例如 `{ compassion = 0.9, pragmatism = 0.2, order = 0.6 }`（PLAN §10.6 S5）。三维对应玩家在台词里能分辨出的三种态度：

| 维度 | 含义 | 典型反应 |
|---|---|---|
| `compassion` 同情 | 对他人受苦的敏感、底线 | 伤害弱者时最难受，帮助他人时最慰藉 |
| `pragmatism` 务实 | 生存优先、自保 | 弄到物资时慰藉，为陌生人付出时不满 |
| `order` 守序 | 规矩、信用、诚实 | 欺骗、背信、违背承诺时难受，坦白、归还时慰藉 |

没有"忠诚"维度。涉及队友的行为（抛弃、背叛、救援）走关系规则：受害队友对动手者的关系值按行为轻重下降；其余队友的心理影响 = 与受害者的关系系数 × 自身 `compassion`。所以同一次抛弃，和受害者亲近的人反应激烈，疏远的人无所谓。

**心理反应**（Reactor 第一族）：一条行为对某个角色的心理影响 =

```
影响 = Σ(行为标签权重 × 该角色对应价值观) × 行为轻重 × 参与系数 × 角色特质系数（见 WORLD §3）
参与系数：亲手做 1.5；同行 1.0；留守、事后得知 0.6；不知情 0
```

同一件事，elena 可能 −25，dale 可能 −3（一次严重事件的量级；单次偷窃的算例见 WORLD §2），甚至有人因为"终于有吃的了"而 +5。反应会生成三样东西：一条带来源的压力条目（见 §2.6）、一句该角色的台词、关系值的变化（例如 elena 对动手的 sam 降低好感）。

**社会反应**（第二族）：有活着的目击者，消息才会传开。传开有延迟：先是该地点自己知道，1–3 天后传到相关势力，再变成全镇的"恶名"。没有目击者、没有幸存者的行为，世界不知道，只有小队自己知道，良心照样记。

**世界反应**（第三族）：改变地点状态并安排后续。例如：

```lua
-- data/reactors/world.lua 里的一条规则
{
  id = "robbed_household_starves",
  on = { verb = { "steal", "rob" }, tags = { occupied = true, took_essentials = true } },
  effects = {
    { "loc_add", "$loc", "food_days", -3 },
    { "schedule", "beggar_at_door", { after_days = { 2, 4 }, bind = { victim = "$target" } } },
  },
}
```

### 2.5 活的地点：住户小模拟

每个有人的地点带一份很小的状态：成员（具名、存活、伤病）、存粮可撑天数、防备等级、对玩家的态度、对玩家的记忆。每天黎明推进一次：

```
未接触 → 已到访 ─┬→ 友好（交易过、帮过）──→ 可能来报信 / 送东西 / 请求加入
                ├→ 被偷 ─┬→ 加强戒备（下次更难）
                │        ├→ 断粮 → 上门乞讨 → 饿死（之后再去会看到）
                │        └→ 投靠掠夺者 → 带人报复
                ├→ 被抢 / 有人被杀 → 幸存者逃亡 / 报复 / 向哨站告发
                └→ 无人幸存 → 空屋（之后可能被别人占据）
```

"世界有反应"的大部分内容就出自这张小图加上 §2.4 的规则，不需要逐条手写剧情。

### 2.6 心理状态

每个角色的心理值由"压力条目"和"慰藉条目"汇总而来。每个条目带来源、数值和衰减速度，所以界面能告诉玩家**他为什么难受**（"三天前在米勒家的事""两天没吃饱""Walt 死了"）。

- 状态带滞回：稳定 → 动摇 → 低落 → 抑郁 → 崩溃，下行和回升的阈值不同，避免来回抖动。具体阈值见 CONTENT §6.4.4（回升阈值比下行阈值高 5 点）。
- 低落：工作变慢。抑郁：拒绝部分工作、吃得少、影响周围人。
- 崩溃时触发危机片段：离队、偷走物资出走、轻生意图。队友可以干预（谈话、陪伴、给慰藉品），干预是否成功看关系值和干预者特质。全程文字、离屏处理。
- 慰藉来源：热饭、暖和的房间、咖啡/酒/烟（酒和烟有依赖风险）、书、谈话、做了好事、修复行为（归还、坦白、照料受害者）。
- 刹车：角色崩溃前必有至少一天的明显预警；导演在队伍整体心理过低时降低坏事件的权重（§2.8）。

### 2.7 故事片段与两套 DSL

**片段**（`data/storylets/*.lua`）：

```lua
{
  id = "beggar_at_door",
  slot = "door_day",                 -- 出现的时机：door_day / radio / dawn / dusk / home_idle
                                     -- raid_enter / raid_found / travel / dream / talk / crisis
  tier = "scheduled",                -- scheduled > arc > ambient，高层优先
  when = { "all",
    { "npc_alive", "$victim" },
    { "fact", "loc.$victim_loc.food_days", "<=", 0 } },
  cast = { opener = { "pick_char", { at_home = true }, prefer = { trait = "compassion" } } },
  text = "st.beggar_at_door.body",   -- i18n 键；文本里可引用 $victim、$opener 和起因
  text_soft = "st.beggar_at_door.soft", -- 可选：温和叙述（设置键 soft_narration）开启时替换 text
  choices = {
    { text = "st.beggar.give", when = { "has_item", "food_any", 2 },
      effects = { { "item", "-", "food_any", 2 }, { "deed", { verb = "give", target = "$victim" } },
                  { "loc_add", "$victim_loc", "food_days", 2 } } },
    { text = "st.beggar.refuse",
      effects = { { "deed", { verb = "refuse_help", target = "$victim" } } } },
    { text = "st.beggar.return_all", when = { "deed_exists", { verb = "steal", target = "$victim" } },
      effects = { { "deed", { verb = "return_goods", target = "$victim" } }, { "goto", "beggar_forgiven" } } },
  },
}
```

**条件 DSL**（`sim/cond.lua`）：`all / any / not`、`fact`（比较）、`has_item`、`char`（特质、状态）、`npc_alive`、`deed_exists`（可限定最近 N 天、动词、对象、地点）、`rep`、`day_between`、`phase`、`chance`（用剧情随机流）。加载时编译成函数。

**效果 DSL**（`sim/effects.lua`）：`item`、`fact`、`morale`（带原因键）、`rep`、`relation`、`wound`、`heal`、`join`、`leave`、`die`、`deed`（写入账本并触发反应规则）、`schedule`、`loc_state`（只写接触进度 `loc.<id>.state`）、`loc_occ`（写占用 `occ`）、`loc_alert`（写布尔 `alert`）、`loc_add`、`unlock_loc`、`unlock_recipe`、`goto`。

各条件与效果的完整参数形式见 WORLD §8–§10 与 PLAN §10 W1，M8 由 lint 校验。

**为什么用表 DSL 而不直接写 Lua 函数**：

- 能在加载时校验：引用的事实、物品、角色、文本键是否存在。
- 能存档：排了期的后续事件只存 id 和绑定值，不存闭包。
- 能解释：调试面板可以显示"这个片段为什么没触发，卡在哪个条件"。
- 能统计：批量模拟后报告哪些片段从未触发。

少数复杂判断允许用按名字注册的函数（`{ "fn", "name", args }`），同样可存档。

### 2.8 导演：节奏与重玩性

- **固定骨架 + 随机血肉**：三幕、寒潮、哨站主线是骨架，每局都在；地点、住户、片段的抽取是血肉，每局不同；角色组合让同一事件有不同反应。
- **曝光预算**：每天最多推出 2 个有选项的片段（危机与排期片段不占预算）；其余时机用无选项的短句或系统消息填充，避免玩家被选项淹没，也让 80 个左右的片段池在单局内不重复（PLAN §10.6 S1–S3）。
- **参数化优先**：片段尽量用 `$victim`、`$loc` 等绑定写成可复用的模板。同一个"上门乞讨"片段适用于任何一户被偷的人家，重玩差异来自绑定对象和前因，而不是篇数。
- **挑选流程**：每个时机先看有没有到期的排期片段，再看角色线/势力线，最后从环境片段里按权重抽。权重 = 基础权重 × 条件命中的具体程度（条件越具体越优先，避免泛泛的片段压过贴合当前处境的）× 张力修正。
- **张力值**（0–100）：由最近的伤亡、饥寒、心理状况算出。张力高时提高喘息类片段的权重，张力低时提高施压类的权重。
- **保底**：每 3 天至少一次交易机会；连续两晚空手而归后提高线索类片段权重；同一片段有冷却。
- **角色线**：每名角色 1 句伏笔台词（无选项）+ 3 段有选项的个人故事（中期冲突、深化或转折、大寒潮前的抉择），用 `arc.<id>.stage`（0..3）推进，条件里混入当前局势，所以同一角色在不同局里走向不同。单局在队的只有 4 人左右，每局能看到的角色线约 12 段。

### 2.9 Lua 模块与接口（叙事部分）

| 文件 | 职责 | 主要接口 |
|---|---|---|
| `sim/facts.lua` | 事实黑板，支持派生事实 | `facts.get(k)`、`facts.set(k,v)`、`facts.add(k,d)`、`facts.derive(prefix, fn)` |
| `sim/deeds.lua` | 行为账本 | `deeds.record(t) -> id`、`deeds.query(filter) -> list`、`deeds.exists(filter)` |
| `sim/cond.lua` | 条件 DSL 编译与求值 | `cond.compile(expr) -> fn(ctx)`、`cond.explain(expr, ctx) -> 逐项结果` |
| `sim/effects.lua` | 效果 DSL 执行 | `effects.run(list, ctx)`、`effects.register(name, fn)` |
| `sim/reactors.lua` | 匹配行为并执行规则 | `reactors.on_deed(deed)` |
| `sim/psyche.lua` | 压力/慰藉条目、状态机 | `psyche.add_stress(char, src, amount, decay)`、`psyche.state(char)`、`psyche.tick(dt)` |
| `sim/households.lua` | 住户小模拟 | `households.tick_day()`、`households.attitude(loc)` |
| `sim/rumor.lua` | 消息传播与恶名 | `rumor.tick_day()`、`rumor.known_by(deed, faction)` |
| `sim/story.lua` | 片段池、排期、导演 | `story.pick(slot, ctx) -> storylet|nil`、`story.choose(inst, idx)`、`story.schedule(id, when, bind)` |
| `sim/lint.lua` | 静态校验 | `lint.run() -> errors`（引用完整性、三语键齐全、无孤立片段） |

约束：以上文件都属于纯模型层（D10），不 `require` 任何引擎库。随机数只用 `core/rng.lua` 的具名随机流（`story`、`loot`、`combat`、`worldgen`、`health`、`weather`、`fx`），流的状态进存档。代码（`sim/state.lua` 的 `STREAMS`）目前只有前六个；`fx`（视觉随机）暂不进 STREAMS，需要时再加，走 PARALLEL-PLAN §5。

### 2.10 调试与验证手段

- **开发面板**（F1，仅开发构建）：查看事实、账本、每个角色的压力条目；对任一片段显示逐条件的命中情况；强制触发片段；跳到指定天。
- **校验**：`lint.run()` 在启动和测试里执行，引用错误直接失败。
- **批量模拟**：策略机器人以无画面方式跑 500 局，输出每个片段的触发次数、每个结局的达成率、每幕资源总量的分布（PLAN §4.7）。从未触发的片段和达不到的结局算缺陷。

---
