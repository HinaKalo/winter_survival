# 03 世界回响、哨站主线与心理危机分镜集

上位设计：`NARRATIVE.md §2.2 / §2.5 / §2.7`、`WORLD.md §7 / §10`、`PARALLEL-PLAN.md §2 C6/C9`。
本篇将首批核心片段串联为三条可追溯的**因果分镜链**，供 M8（规则/导演校验）与 M9/M10（内容编写）直接参照。

---

## A. 道德抉择与延迟回响弧

### A1. 邻居求药链（`neighbor_plea_sick_child`）
- **slot**：`door_day` ｜ **tier**：`ambient` ｜ **地点**：自家门口
- **画面调度**：清晨雪雾未散，44 岁的 `npc.hendry_carl` 站在台阶下没敢进院，双手缩在旧呢大衣袖口里；背景可隐约看见他家方向没有烟囱冒烟。
- **台词方向**：`"我女儿莉莉烧了一整夜。你们要是有多余的退烧药或抗生素，我拿家里剩下的工具换——什么都行。"`
- **分支与 C6 落点**：
  1. **给药**：`item - antibiotics 1`；`deed { verb = "give", target = "npc.hendry_carl", tags = { victim_vulnerable = true, victim_child = true, cost_paid = true }, magnitude = 0.7 }`；`loc.suburb_house.attitude +2`。
  2. **拒绝**：`deed { verb = "refuse_help", target = "npc.hendry_carl", tags = { victim_vulnerable = true, victim_child = true }, magnitude = 0.6 }`；埋下数日后 `elena` 心理重压与 `npc.hendry_lily` 病危伏笔。
  3. **换情报**：`deed { verb = "trade_fair", target = "npc.hendry_carl", tags = { cost_paid = true }, magnitude = 0.4 }`；换得附近空屋/仓库线索。

### A2. 被偷住户上门乞讨与修复链（`beggar_at_door` → `beggar_forgiven` / `revenge_party`）
```
[夜晚] steal / rob（occupied=true, took_essentials=true）
   │
   ├─► 2–4 天后 [door_day] beggar_at_door（$victim 上门，food_days ≤ 0）
   │      ├─ 给 2 份食物 ──► give（loc_add food_days +2）
   │      ├─ 拒绝 ────────► refuse_help ──► 2–4 天后 [dawn] revenge_party（带掠夺者夜袭）
   │      └─ 归还全部 ────► return_goods ─► goto beggar_forgiven（rep civilians +3，给情报）
   │
   └─► 1–3 天后 [dream] dream_victim_returns（无选项，写入原因键 dream_<victim>）
```
- **`beggar_at_door`（`slot = "door_day"`，`tier = "scheduled"`）**：
  - **画面**：参数化绑定 `$victim` 站在门外，大衣空荡、眼神直盯门缝。文本必须明确点出“那天夜里”的起因（原则 6）。
  - **台词方向**：`"那天夜里你们翻过我家后窗以后，橱柜就空了。我不是来吵架的，家里还剩一口气，分两份吃的就行。"`
- **`beggar_forgiven`（`slot = "door_day"`，`tier = "scheduled"`）**：
  - **画面**：对方接过整包退回的罐头，沉默几秒后低声说出邻近一处未被搜刮的线索，转身没再回头。
- **`revenge_party`（`slot = "dawn"`，`tier = "scheduled"`）**：
  - **画面**：黎明报告页配低光雪院剪影——被害住户引着两名掠夺者撬过院门木栏。守夜人数与防备等级决定是击退还是被抢走 `food_any` 并致伤（`wound`）。
- **`dream_victim_returns`（`slot = "dream"`，`tier = "scheduled"`，无选项）**：
  - **画面**：极简黑底淡入一格“雪地门廊”冷蓝剪影。`compassion` 高的角色梦见孩子空碗；`pragmatism` 高的角色梦见门锁被撬开；`order` 高的角色梦见账本上的空页。

### A3. 学校链（`school_garza_door` → `school_after_raid`）
- **`school_garza_door`（`slot = "door_day"`，`tier = "ambient"`）**：
  - **画面**：`npc.garza` 站在学校铁门内侧，身后隐约可见体育馆玻璃窗贴满旧报纸与蜡笔画。若队中有 `elena`/`grace`（`medical`），她的防备明显放低。
  - **C6 落点**：给柴火 `give`（`victim_child, cost_paid`）/ 以工换粮 `trade_fair` / 压价 `trade_cheat`（`victim_vulnerable, victim_child, took_essentials`）/ 拒绝 `refuse_help`（`victim_child`）。
- **`school_after_raid`（`slot = "door_day"`，`tier = "scheduled"`）**：
  - **被偷分支**：`garza` 独自站在你家门口，眼眶通红但不喊不叫（最小的孩子因断粮发烧）。可选 `return_goods` / `confess` / 否认（`lied`，tags 记入账本，3 天后学校转空并可能被掠夺者占领）。
  - **放过分支（`spare`）**：清晨门口放着一袋麦片和一幅孩子用蜡笔画的“暖和的房子”。可选收下 / `give` 回礼 / 婉拒（`helped_stranger`）。

---

## B. 基洛哨站主线弧（Checkpoint Kilo）

时间轴对齐 `WORLD.md §7` 与 `§12 R5`：**Day ≥ 11 开放接触 → Day ≥ 21 决定庇护名额 → Day 27 入住掩体**。

```
[接触三入口：Day ≥ 11]
  ├─ radio_kilo_frequency (slot: radio)      ← linwei 短波破译
  ├─ kilo_patrol_stop     (slot: travel)     ← 路上被巡逻队拦停
  └─ arc_grace_1          (slot: talk)       ← grace 认出旧同伴
        │
        ▼
[站队与证明：kilo.stage = 1..2]
  ├─ kilo_marsh_meeting     (slot: travel)   ← 中尉线：守纪、燃料/医护、grace 证词
  └─ kilo_pike_private_deal (slot: travel)   ← 军士线：走私、告密(inform)、掠夺者仓库账本把柄
        │
        ├─► [副本支线] raid_found_ledger (slot: raid_found) ← 拿到 kilo.pike_leverage
        ▼
[名额抉择：Day ≥ 21，slot: dusk]
  └─ kilo_slot_decision
        │
        ▼
[入驻验收：Day 27，slot: dawn]
  └─ kilo_betrayal（仅 sgt 线触发：无 pike_leverage 则 60% 翻脸；有把柄则放行）
```

### B1. 关键分镜卡
1. **`kilo_patrol_stop`（`slot = "travel"`，`tier = "ambient"`）**：
   - **画面**：雪路拐角，两名穿国民警卫队冬大衣的士兵横举步枪示意停下，手电光扫过背包。
   - **抉择**：配合登记（`kilo.contact_via = "patrol"`）/ 塞烟酒贿赂 / 趁雪雾脱身。
2. **`kilo_marsh_meeting`（`slot = "travel"`，`tier = "arc"`）**：
   - **画面**：县政府掩体沙袋岗哨内，36 岁的马什中尉把一份油印名册摊在铁箱上，神色疲惫但脊背笔直。
   - **台词方向**：`"把证件或能顶事的东西拿出来，别跟我绕圈子。掩体里暖气只够三十个人用。"`
3. **`kilo_pike_private_deal`（`slot = "travel"`，`tier = "arc"`）**：
   - **画面**：哨站后门货栈阴影里，42 岁的派克军士晃着行军壶，压低声音。
   - **台词方向**：`"马什那套规矩早晚饿死人。仓库里有些登记不上的边角料，看你们拿什么来换。"`
4. **`raid_found_ledger`（`slot = "raid_found"`，`tier = "arc"`）**：
   - **画面**：仓库铁皮柜底层，手电光束打在一本沾着机油的军需出库单上——派克亲笔签名与哨站编号清晰可见。
   - **效果**：拿走即置 `kilo.pike_leverage = true`，成为第 27 天反制军士翻脸的唯一保险。
5. **`kilo_slot_decision`（`slot = "dusk"`，`tier = "arc"`）**：
   - **画面**：黄昏屋内气氛凝重，哨站发来的手写名单摆在桌心，名额少于全队人数。
   - **抉择**：交额外物资/奢侈品换全员入内（`kilo.shelter = "full"`）/ 只送部分人进去（`partial`）/ 拒绝名额留守或南行。

---

## C. 心理危机与 D14 温和叙述分镜（`slot = "crisis"`）

> **D14 硬性约束**：全程纯文字、离屏处理；严禁描写任何自伤或轻生手段与画面细节；必须同时提供标准版与 `soft_narration = true` 的 `text_soft` 文本。

| id | 触发前提 | 画面/UI 呈现 | 标准文本方向（`text`） | 温和叙述文本方向（`text_soft`） | 分支与结果 |
|---|---|---|---|---|---|
| `crisis_breakdown_warning` | 任意角色进入 `low` 至少 1 天（必先于崩溃） | 暗色纸面板弹窗，配该角色 `depressed` 48×48 头像，背景音降为低风声 | `"他一整天没再开口，晚饭碗原封不动留在桌角。你能看出他心里那根弦快绷断了。"` | `"他看起来非常疲惫，一整天都沉默着，晚饭也没有动。"` | 给慰藉品 / 安排队友谈话 / 强制休息 1 天 → 缓冲 `morale` |
| `crisis_intervene` | 角色进入 `broken`，且有队友 `relation ≥ 15` 或持有慰藉品 | 夜间室内熄灯静帧文字卡，无角色动作演绎 | `"半夜屋里安静得只剩风声。$helper 坐在他门边守了一夜，天亮前他终于接过了那杯热水，暂时撑住了。"` | `"那一夜很难熬，好在 $helper 一直陪在旁边。天亮时他平静下来，决定留下来。"` | 陪伴/谈话成功 → 心理状态回升至 `low`（不再立刻离队） |
| `crisis_runaway` | 角色进入 `broken` 且未被干预 | 黎明前玄关空位提示卡，门虚掩着，雪地上只有一串单向脚印 | `"天亮前他收拾了自己的包，留下一张短纸条，趁换岗时推门走进了风雪里。"` | `"天亮时发现他已经离开了营地，只留下一张字条。"` | 立刻追赶（`rescue` 窗口，高耗时与冻伤风险）/ 放手（`leave`，扣除对应携带物资并留下一件信物） |
