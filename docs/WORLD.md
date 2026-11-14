# 世界、人物与首批故事内容 v1

本文是 `NARRATIVE.md`（机制）与 `GDD.md`（玩法）之上的**内容设计**：人物、地点、势力、哨站主线、事实键、反应规则与首批 42 个故事片段。M8（叙事引擎）和 M10（内容铺量）的实现者据此写 `data/characters.lua`、`data/values.lua`、`data/factions.lua`、`data/locations/*.lua`、`data/storylets/*.lua`、`data/reactors/*.lua`，不需再做设计决定。所有人物、地名、机构名均为原创（PLAN D13）。自杀、抑郁相关内容遵循 PLAN D14（见 §3.0 与 §10 `crisis_*`）。

## 0. 约定

- 物品只用类别标签（`food_any fuel_any med_any luxury_any parts_any weapon_any ammo_any`）或规范 id（`canned_beans bottled_water firewood gasoline propane scrap components antibiotics painkillers bandage coffee whiskey cigarettes book lockpick crowbar handgun handgun_ammo radio_parts heater_parts winter_coat`）。
- 引用 CONTENT 数值时只写名称和方向（如"修理耗时 ×0.7"）；具体数值由 CONTENT 定。
- 时间单位：路程用**游戏分钟**（D7：现实 1 秒 = 游戏 1 分钟）。夜晚共 480 分钟，往返耗时从中扣除。
- DSL 参数形式（NARRATIVE §2.7 未给全，本文按以下形式书写，见 §12 裁决 R1）：
  条件 `{"fact",key,op,val}`、`{"has_item",id,n}`、`{"rep",faction,op,val}`、`{"char",who,"has_trait",t}`、`{"char",who,"state_at_least",s}`（s ∈ steady/shaken/low/depressed/broken）、`{"npc_alive",id}`、`{"deed_exists",{verb=,target=,within_days=,loc=}}`、`{"day_between",a,b}`、`{"phase",p}`、`{"chance",p}`；
  效果 `{"fact","set"|"add",key,val}`、`{"item","+"|"-",id,n}`、`{"morale",who,delta,reason_key}`、`{"rep",faction,delta}`、`{"relation",a,b,delta}`、`{"wound",who,level}`、`{"deed",{...}}`、`{"schedule",id,{after_days={a,b},bind={...}}}`、`{"loc_state"|"loc_occ"|"loc_alert"|"loc_add"|"unlock_loc",loc,...}`（地点写入口，见 §8 末尾）。
- 角色 id：`marcus elena junho linwei dale tasha walt priya sam grace`。NPC id：`npc.<name>`。片段 id 用 snake_case；i18n 键 `st.<片段id>.<字段>`。
- 角色线片段 id：`arc_<char>_<n>`（n = 1..3），推进规则 `arc.<char>.stage`：0 → 1 → 2 → 3，完成第 n 段后 stage = n。每条线另有一句无选项的伏笔台词 `bark_<char>_0`（PLAN §10.6 S4），不进 DSL 与平衡测试，只在播出时置 `flag.bark_<char>_0`。

---

## 1. 世界与时间线

### 1.1 简史（寒潮日 = 前一年 8 月 19 日；游戏第 1 天约为 2 月 3 日）

| 月 | 时间 | 事件 | 对镇子的影响 |
|---|---|---|---|
| 0 | 8 月 19 日 | 一股不明原因的冷空气南下，夜间气温 −2 °C，州气象台称"极端早霜"。至今没有可信的解释 | 玉米与大豆一夜绝收 |
| 1 | 8–9 月 | 连续冰风暴压断输电线，电网反复跳闸；大学与学校停课；超市被抢购一空 | 人们以为几周就会恢复 |
| 2 | 9–10 月 | 州际公路因积雪与事故封闭；联邦通告停止广播；县政府发布"就地避寒"指令，第一批有车的人南逃，多数没走出 200 英里 | 人口开始外流，镇上多出大量空房 |
| 3 | 10–11 月 | 电网永久中断，天然气管线压力归零；取暖燃料耗尽，第一批老人与婴儿冻死；超市、药房被洗劫；锯木厂工头鲁克拉起第一伙掠夺者 | 治安瓦解，"各自为战"开始 |
| 4 | 11–12 月 | 圣马可教堂地下室开设互助会，收留约 120 人；县政府撤出，警察局关闭，最后一名副警长洛威独自留守 | 出现第一个和平社区 |
| 5 | 12–1 月 | 国民警卫队一个连的残部进驻县政府地下民防掩体，立"基洛哨站"，征用全镇汽油与柴油；掠夺者与哨站互有摩擦 | 汽油变成硬通货 |
| 6 | 1–2 月（游戏开始） | 估计存活不足一千人。第 1 次小寒潮预计在第 6–9 天。无线电里偶有一个业余电台的夜间广播 | 玩家小队搬入梧桐巷 41 号 |

### 1.2 哈洛瀑布概述

明尼苏达州南部的河滨小镇，原人口约 9000。哈洛河自北向南穿镇，在镇南跌成一道 11 米高的小瀑布（"Falls"）。冬季瀑布冻成冰柱，河面可步行但冰厚不均。

| 街区 | 描述 | 主要地点 |
|---|---|---|
| 北坡 North Hill | 1970–90 年代的单层住宅区，坡上风大。玩家的家在此（梧桐巷 41 号） | suburb_house, elder_house, school |
| 主街 Main Street | 四个街区的老商业街，沿街建筑玻璃大多已碎 | supermarket, pharmacy, hardware_store, clinic, church（街东端） |
| 县政府广场 Courthouse Square | 红砖县政府大楼、法院、警察局，广场中央的纪念碑 | police_station, checkpoint_kilo（大楼地下） |
| 河滩 River Flats | 河湾低地，旧渡口与码头，夏季是露营地 | river_dock, trailer_market |
| 东工业区 East Works | 锯木厂、仓库、新建商业楼盘的工地 | warehouse, construction_site |
| 14 号公路沿线 | 镇外的国道，通向南方 | gas_station, motel |
| 城外 | 西郊农田、南山顶上的电台塔 | farm, radio_tower |

```
              N
     [school]    [elder_house]
  North Hill:  [HOME] [suburb_house]            [radio_tower]  (南山, 镇外)
 ----------------------------------------------
  [pharmacy][supermarket][hardware][clinic][church]   <- Main St
 [police][KILO(县政府地下)]
                         [warehouse][construction]  <- East Works
  [river_dock][trailer_market]   (River Flats)
 ~~~~~~~~~~ 哈洛河 ~~~~~~~~ Falls(南)
  [farm](西郊)             [gas_station][motel] (14 号公路, 东南)
```

### 1.3 地点方位与离家路程（单程游戏分钟，含积雪与绕行；写入 `data/locations/*.lua` 的 `travel_min`）

| 地点 id | 方位 | 单程 | 往返 | 白天可去 | 开局开放 |
|---|---|---|---|---|---|
| elder_house | 北坡，隔三户 | 8 | 16 | 是 | 是 |
| suburb_house | 北坡，坡下 | 10 | 20 | 是 | 是 |
| pharmacy | 主街西端 | 20 | 40 | 否（夜） | 是 |
| supermarket | 主街中段 | 25 | 50 | 否 | 否（第 2 天） |
| hardware_store | 主街 | 25 | 50 | 否 | 否（第 2 天） |
| church | 主街东端 | 30 | 60 | 是 | 第 3 天 |
| clinic | 主街 | 35 | 70 | 否 | 第 4 天 |
| gas_station | 14 号公路 | 40 | 80 | 否 | 第 5 天 |
| police_station | 县政府广场 | 40 | 80 | 否 | 第 6 天 |
| school | 北坡北端 | 45 | 90 | 否 | 第 4 天 |
| river_dock | 河滩 | 50 | 100 | 是（偶尔有商贩） | 第 7 天 |
| construction_site | 东工业区 | 55 | 110 | 否 | 第 8 天 |
| trailer_market | 河滩 | 60 | 120 | 是 | 第 6 天或商贩线索 |
| checkpoint_kilo | 县政府广场 | 65 | 130 | 是（受盘查） | 第 11 天（GDD：哨站主线开放） |
| warehouse | 东工业区 | 70 | 140 | 否 | 第 9 天 |
| motel | 14 号公路 | 90 | 180 | 是 | 第 10 天或线索 `rumor.motel` |
| farm | 西郊 | 110 | 220 | 是 | 第 12 天或线索 `rumor.farm` |
| radio_tower | 南山 | 120 | 240 | 否 | 线索 `rumor.tower`，且 radio.level ≥ 2 |

提示：farm、radio_tower 往返需 4 小时，夜间只剩约 4 小时搜刮，且迟归惩罚最重；这是它们高收益的代价（GDD §1.8 预算制）。

---

## 2. 价值观维度与行为权重

### 2.1 三个维度（`data/values.lua`，取值 0..1；PLAN §10.6 S5，代码不写死维数）

| 维度 | 键 | 含义 |
|---|---|---|
| 同情 | `compassion` | 对他人痛苦的敏感度；越高，伤害弱者越难受，帮助别人越慰藉 |
| 务实 | `pragmatism` | 以生存结果为准；越高，对"拿到东西"越宽容，对"白白付出"与"留目击者"反而不安 |
| 秩序 | `order` | 对规则、财产、信用的尊重，**含诚实**（守规矩、守信用、不撒谎）；越高，偷抢、说谎、赖账、背信越难受，坦白、归还越慰藉 |

没有"忠诚"维度：对队友的责任感改由 §2.4 的关系规则表达。

### 2.2 行为权重表（`data/values.lua: weights`）

公式（NARRATIVE §2.4）：`影响 = Σ_标签( Σ_维度 权重 × 角色价值观 ) × magnitude × 参与系数`。负 = 压力条目，正 = 慰藉条目。一次行为的权重 = **动词基线 + 其 tags 中为真者的行**。列顺序：同情 / 务实 / 秩序。**对象是队友的行为不查本表，走 §2.4。**

**动词基线**

| verb | 同情 | 务实 | 秩序 |
|---|---|---|---|
| steal | 0 | +3 | −6 |
| rob | −4 | +2 | −9 |
| assault | −8 | 0 | −5 |
| knockout | −4 | 0 | −3 |
| kill | −4 | 0 | −2 |
| spare | +4 | −1 | +1 |
| help / give | +6 | −2 | 0 |
| rescue（对象非队友） | +6 | −1 | 0 |
| trade_fair | 0 | +1 | +2 |
| trade_cheat | −1 | +2 | −6 |
| refuse_help | −5 | +2 | 0 |
| bury | +4 | 0 | +3 |
| confess | +3 | −2 | +10 |
| return_goods | +5 | −3 | +7 |
| inform | −1 | +1 | +3 |

（`abandon`、`betray` 与 `victim_teammate` 标签已移出本表，见 §2.4。）

**标签附加行**

| tag | 同情 | 务实 | 秩序 | 说明 |
|---|---|---|---|---|
| occupied | −3 | 0 | −2 | 有人住的地方（空屋无此项） |
| victim_vulnerable | −6 | 0 | −1 | 老人、孩子、病人、孕妇 |
| victim_child | −8 | 0 | −2 | 对象是未成年人（与上一行叠加） |
| took_essentials | −4 | 0 | 0 | 拿走的是对方的最后存粮/药/燃料 |
| lethal | −6 | 0 | −3 | 造成死亡（kill 之外的间接致死也算） |
| armed_threat | −3 | 0 | −3 | 持械威吓 |
| witnessed | 0 | −2 | −1 | 有活着的目击者（务实者怕后患） |
| silenced | −8 | −3 | −7 | 为灭口而杀/打晕目击者 |
| target_raider | +6 | +2 | +2 | 对象是掠夺者（部分抵消负面） |
| target_soldier | 0 | −2 | −4 | 对象是哨站士兵（后患大） |
| self_defense | +6 | +1 | +3 | 对方先动手 |
| for_team | 0 | +4 | 0 | 这件事是为了团队生存（原忠诚 +3 列删除，务实 +3 → +4 作补偿） |
| helped_stranger | +3 | −1 | 0 | 帮助与己无关的人 |
| cost_paid | +2 | 0 | 0 | 帮助时自己付出了关键物资 |
| lied | 0 | +1 | −4 | 说谎获利 |

**合并规则**：原"诚实"列并入"秩序"列——两列同号（或其一为 0）时直接相加，绝对值封顶 10（如 steal：−4 + −2 = −6，confess：+2 + +8 = +10）；原"忠诚"列整列删除。

特质修正（在公式外，作为乘数，写在角色卡）：elena"良知极重"= 负向影响 ×1.4；tasha"杀人创伤"= 动词 kill 的负向 ×2 并附加一条长期压力；其余角色无乘数。

### 2.3 三个算例（同一行为、不同角色）

行为：sam 撬开米勒家夜里偷窃（NARRATIVE §2.4 样例）：`verb=steal, occupied, victim_vulnerable, took_essentials, witnessed(露丝看见), magnitude=0.6`。小队 sam + tasha，elena 与 dale 留守家中（参与系数 0.6）。

权重合计 = steal + occupied + victim_vulnerable + took_essentials + witnessed：同情 −13、务实 +1、秩序 −10。

| 角色 | 价值观（同/务/秩） | Σ 权重×价值观 | × magnitude 0.6 | × 参与系数 | 影响 |
|---|---|---|---|---|---|
| elena | .95 / .2 / .8 | −12.35 + 0.2 − 8.0 = −20.15 | −12.09 | 0.6（留守） | **−7.3**（×1.4 特质 → −10.2） |
| dale | .3 / .8 / .4 | −3.9 + 0.8 − 4.0 = −7.1 | −4.26 | 0.6（留守） | **−2.6** |
| sam | .5 / .8 / .2 | −6.5 + 0.8 − 2.0 = −7.7 | −4.62 | 1.5（亲手） | **−6.9** |

读法：elena 只是听说就重创，且之后会对 sam 的好感下降（见反应 `psy_relation_shift`）；dale 几乎无感；sam 动手的本人受的压力和留守的 elena 差不多，因为他对秩序几乎无负担。若换成 elena 亲手做同一件事，影响为 −18.1（×1.4 → −25.4），这就是不能指派她下手的原因。

### 2.4 涉及队友的行为（关系规则）

`abandon`、`betray`、`rescue`、对象是队友的 `assault / kill / steal / refuse_help`，以及队友死亡（`die`，无动手者）**不走价值观权重**，走关系规则：

1. **受害队友对动手者的关系值下降**，幅度按行为轻重（再乘 magnitude）；
2. **其余队友的心理影响 = 基础压力 × 关系系数 × 自身 `compassion` × magnitude × 参与系数 × 特质系数**。关系系数取决于该队友与**受害者**的关系值 r（−100..+100）：`k(r) = 0.2 + 1.3 × (r + 100) / 200`，即 r = −100 → 0.2，r = 0 → 0.85，r = +100 → 1.5；
3. 其余队友对动手者的关系变化 = 受害者列 Δ × 0.25 × k(r)，四舍五入且至少 ±1。

| 行为 | 受害者对动手者关系 Δ | 其余队友基础压力 |
|---|---|---|
| abandon（抛弃） | −25 | −8 |
| betray（背叛） | −40 | −10 |
| steal（偷队友） | −15 | −6 |
| assault（打队友） | −30 | −10 |
| kill（杀队友） | −60 | −16 |
| refuse_help（队友求助被拒） | −10 | −4 |
| rescue（救援） | +10（对救援者） | +6（慰藉） |
| die（病、冻、事故，无动手者） | — | −12 |

动手者本人按"亲手"（参与系数 1.5）同样计算。例：dale 抛弃 grace（magnitude 0.8）：grace 对 dale 关系 −20；tasha 与 grace 关系 +40（k = 1.11）、compassion .8，同行 → −8 × 1.11 × .8 × .8 = **−5.7**；priya 与 grace 关系 −5（k = 0.82）、compassion .4，同行 → **−2.1**。同一次抛弃，亲近者反应激烈，疏远者无所谓。

---

## 3. 幸存者角色卡

### 3.0 通用规则

- **价值观**顺序：同情 / 务实 / 秩序。
- **关系初值**：同队开局默认 0；表中给"倾向"（+ 亲近 / − 疏远），由 `data/characters.lua: relation_bias` 实现，幅度 ±5..±15。
- **危机统一写法**：崩溃时的文本一律离屏、不写手段（D14）。`crisis_*` 片段带 `soft_narration` 开关：开启时只写"他/她离开了/再没说话"；关闭时仍然只写文字、不写方式与细节，只多一句明确的心境描述。
- **角色线启动条件**：除另写外，该角色在队中且 `day ≥ 3`，tension 不处于高位。同一时刻最多一个角色线片段在池中排队。
- 每条线的"影响"写作：心理 / 关系 / 结局。
- **角色线结构（PLAN §10.6 S4）**：1 句无选项的伏笔台词（`bark_<char>_0`）+ 3 段有选项片段（`arc_<char>_1..3`，三拍为中期冲突、深化或转折、大寒潮前的抉择）。伏笔台词播出后置 `flag.bark_<char>_0`，作为 `arc_<char>_1` 的前置；下表触发列里的 `stage=` 取值为 0..2，完成第 3 段后 stage = 3。

### 3.1 marcus — 马库斯·黑尔 Marcus Hale（40 岁）

- **小传**：哈洛瀑布高中的暖通维修工，兼修教堂和县政府的锅炉。妻子在寒潮第二个月随岳母南逃，之后没了音信。他抽了二十年烟，兜里还揣着最后几包旧存货，舍不得分人。修东西时闷头干活，修好了能对着接线盒念叨十分钟毛病出在哪。平时脾气稳，唯独遇上怎么折腾都弄不好的事会格外烦躁。
- **价值观**（同情 / 务实 / 秩序）：.5 / .6 / .5
- **特长**：修理加热器与加湿器耗时 ×0.7，零件消耗 ↓。**缺点**：烟瘾，缺烟时每日有持续压力条目；有烟时一支即慰藉。
- **关系倾向**：与 walt +10（同行手艺人）、与 dale −5（嫌吵）。
- **台词**：偷窃——"空屋里随便拿。屋里要是还有人喘气，别进去。"杀人——"……别让我看。把门带上。"帮助——"拿去用吧，放我这儿也是生锈。"

| 段 | 触发 | 梗概 | 选择与走向 | 影响 |
|---|---|---|---|---|
| 0 `bark_marcus_0`（伏笔，无选项） | 在队，day≥3，cigarettes 存量 ≤ 3 | 他蹲在后院，摸着最后一包烟，没点：“最后几包了。抽一支，少一支。” | — | 置 `flag.bark_marcus_0`；缺烟压力条目照常 |
| 1 `arc_marcus_1` | stage=0，已播伏笔，heater 损毁一次或第 1 次小寒潮后 | 他发现县政府地下锅炉间的图纸在哨站手里 | A 主动去哨站接触（解锁 `kilo.stage=1` 路线，契合哨站主线）；B 拒绝 | A：开启军士/中尉任一线；B：他变得沉默，关系−（想帮忙的心被拒） |
| 2 `arc_marcus_2` | stage=1，day≥14，cigarettes=0 | 戒断到极点，他在修加热器时手抖，差点酿成火灾 | A 拿 cigarettes 或 whiskey 换他稳定（依赖加深）；B 让 elena 陪他熬（需 elena 在队）；C 让他休息 1 天 | A：心理+、`addict.marcus`+；B：关系+、心理渐复；C：全队少一个修理工 |
| 3 `arc_marcus_3` | stage=2，day≥22 | 他决定把最后的家当（锅炉图纸/零件）献给全队的避寒方案 | A 全队留守：解锁避寒小间零件加成；B 随哨站走（需 kilo.stage≥3） | 结局：守家变体"有人修好了暖气"；或地下变体 |

- **崩溃表现**：离开去找妻子的路，留下一张写着"锅炉维护要点"的纸。若不挽留，尾声为"没人知道他走到了哪"。

### 3.2 elena — 埃琳娜·鲁伊斯 Elena Ruiz（34 岁）

- **小传**：哈洛瀑布县医院急诊护士，寒潮前一周刚值完一轮连班。医院断电后她在走廊里给四十多个人分过最后的药，看着大半人在三周内没熬过去。她听不得别人说"没办法"，在队里总是第一个问那家人还有没有吃的。但她其实比谁都清楚账怎么算——一瓶抗生素能救几个人、救不了几个人，她心里有数。
- **价值观**（同情 / 务实 / 秩序）：.95 / .2 / .8
- **特长**：治疗效果 ↑，用药 ↓（消耗 ×0.7）。**缺点**：良知极重，团队伤害他人时心理重创（负向 ×1.4），崩溃阈值低。
- **关系倾向**：与 grace +10（同为医护）、与 priya −10、与 sam −5。
- **台词**：偷窃——"他们也在数罐头，一天一个。"杀人——"别跟我说'没办法'，这话我听了半年。"帮助——"我来，你们搭把手。"

| 段 | 触发 | 梗概 | 选择与走向 | 影响 |
|---|---|---|---|---|
| 0 `bark_elena_0`（伏笔，无选项） | 在队，day≥3，队中有人受伤 | 她清点药品时低头看着手背上的日期：“我手上写的还是停电那天。” | — | 置 `flag.bark_elena_0`；无机制后果（原 `elena.rationed` 标志随原选项取消，不进入首批） |
| 1 `arc_elena_1` | stage=0，已播伏笔，`deed_exists{verb=refuse_help}` 或 day≥10 | 邻居孩子发烧（联动 `neighbor_plea_sick_child`），她请求拿出抗生素 | A 给（抗生素 −）→ 孩子活；B 拒绝 → 她冷淡 | A：关系+、尾声线"救人者"；B：心理−−、关系− |
| 2 `arc_elena_2` | stage=1，队伍有 `lethal` 行为 或 (`day≥18` 且 `tension≥50`) | 她拒绝与动手者同桌吃饭（若无杀戮则因长期紧绷与拒绝对外施救而爆发） | A 动手者道歉并归还/坦白，或承诺不再拒人 → 修复；B 解释"必要"，她沉默；C 让她离队 | A：关系回升；B：心理持续−；C：`leave` 触发 `crisis_runaway` 变体 |
| 3 `arc_elena_3` | stage=2，day≥22 | 临近大寒潮她问：我们救下的人和我们害过的人，哪边多？ | A 如实回答（读出 `deeds.helped` 与 `deeds.harmed`），并陪她把名字一个个写下来；B 说"别想了，没有别的办法"，她不再追问 | A：关系+，按两个数的对比决定尾声（救人者 / 沉默者 / 离开者）；B：心理−，尾声偏"沉默者"或"离开者" |

- **崩溃表现**：先停止进食和说话，两天后拒绝再给任何人治疗，最终走出去"看看还有谁需要"。可由 grace、tasha 谈话挽回。

### 3.3 junho — 박준호 Jun-ho Park（45 岁，朴俊浩）

- **小传**：主街韩式小馆"东门"的老板，来明尼苏达二十二年，妻子和女儿在首尔，断网前最后一条消息停在十月。他能用三只罐头和一把干辣椒熬出像样的汤，平时很讲究，再缺粮也坚持吃饭得上桌。酒瘾一直戒不掉，只要屋里有酒，晚上就得喝两口才能睡。
- **价值观**（同情 / 务实 / 秩序）：.6 / .5 / .4
- **特长**：烹饪产出 ↑，燃料与水耗 ↓。**缺点**：酒精依赖，无酒时心理渐降；饮酒过量时白天工作变慢。
- **关系倾向**：与 tasha +10（像女儿）、与 priya −5。
- **台词**：偷窃——"饿急了什么都顾不上，但别把人家锅底端了。"杀人——"我做饭的，不干这个。"帮助——"坐下，先喝口热的。"

| 段 | 触发 | 梗概 | 选择与走向 | 影响 |
|---|---|---|---|---|
| 0 `bark_junho_0`（伏笔，无选项） | 在队，day≥3，有热食 | 他把汤锅端上桌，挨个敲碗沿：“都坐下。站着吃的饭，不算饭。” | — | 置 `flag.bark_junho_0`；全队 `morale` +3（原因键 `table_together`，一次） |
| 1 `arc_junho_1` | stage=0，已播伏笔，whiskey 存量 ≥1 且 day≥8 | 他半夜翻出酒，把瓶口对着厨房窗口 | A 没收酒；B 陪他喝一杯；C 假装没看见 | A：依赖−、关系−；B：依赖+、关系+；C：心理微升、依赖+ |
| 2 `arc_junho_2` | stage=1，day≥14，`food_any` 紧缺 | 邻居老太太闻到汤味上门，他想分一碗 | A 同意：食物−、`give`，邻里态度+；B 拒绝 → 他沉默 | A：他心理+，`loc.elder_house.attitude`+；B：心理− |
| 3 `arc_junho_3` | stage=2，day≥22 | 大寒潮前夜，他想给所有人做一顿"像样的饭"；需要 food_any ≥6、fuel_any ≥2，消耗大 | A 备料开火，做这一顿；B 作罢，省下物资 | A：全队心理大幅+，尾声"一桌人"；B：节省物资，他独自喝酒，尾声"只剩酒" |

- **崩溃表现**：醉到不再说话，把自己锁在厨房。队友可以进去陪坐。不会离队，会拒绝一切烹饪。

### 3.4 linwei — 林薇 Lin Wei（26 岁）

- **小传**：明大（本地州立大学分校）电子工程研究生，寒潮来时正在做低功耗短波收发模块的毕设。导师第二个月南下，她没跟着走，因为觉得高速上太冷、车又不可靠。她体弱，打架指望不上，但耐得住性子焊电路。每晚她用手摇发电机的电给小收音机听两分钟，听听外面还有没有人在说话。
- **价值观**（同情 / 务实 / 秩序）：.6 / .6 / .7
- **特长**：无线电与电器制作更快，预报更准（预报提前量 ↑）。**缺点**：体弱畏寒（体温下降更快），近战差。
- **关系倾向**：与 marcus +5、与 walt +5、与 dale −5。
- **台词**：偷窃——"空屋我能去，有人的我真的下不去手。"杀人——"别这样……我们还有别的办法吧？"帮助——"这个坏了？给我看看，说不定能接上。"

| 段 | 触发 | 梗概 | 选择与走向 | 影响 |
|---|---|---|---|---|
| 0 `bark_linwei_0`（伏笔，无选项） | 在队，day≥3，有 radio_parts 或 components | 她修好收音机，在噪声里停住：“……有人在说话。‘哈洛夜班’，是真的。” | — | 置 `flag.bark_linwei_0`；`radio.level` 至少为 1，解锁广播片段（原第 1 段的机制后果） |
| 1 `arc_linwei_1` | stage=0，已播伏笔，radio.level≥2 | 她从噪声里解出一串有规律的脉冲，来自南山电台塔 | A 派人去塔（`unlock_loc radio_tower`）；B 只记录 | A：新地点；B：线索留在 `rumor.tower` |
| 2 `arc_linwei_2` | stage=1，day≥14，`kilo.stage≥1` | 她认出哨站短波的加密方式，可以窃听 | A 窃听 → `kilo.pike_leverage` 的线索；B 不碰 | A：军士线把柄、关系±；B：中立 |
| 3 `arc_linwei_3` | stage=2，day≥22 | 她算出大寒潮的确切日期（预报准确度 ↑） | A 当晚公布，全队提前一天做避寒准备（耗柴火，全队心理+），`cold.big_day` 确认；B 把电留给加热器，不再收听 | A：守家结局变体：有无线电预警；B：省电，尾声"没有回应" |

- **崩溃表现**：关掉收音机，不再说话。若体温危急，会"留在窗边听"而不进屋。不会主动离队。

### 3.5 dale — 戴尔·科瓦尔斯基 Dale Kowalski（62 岁）

- **小传**：退休长途卡车司机，周末在县里猎鹿。老婆五年前过世，女儿在西海岸，通信断了。他总说人比鹿难伺候，陌生人靠近先把猎枪端起来再说。他嗓门大，爱指手画脚，其实是怕一个人待着。年轻时跑长途被老板扔在半路过，所以对"半道丢下人"这事特别犯冲。
- **价值观**（同情 / 务实 / 秩序）：.3 / .8 / .4
- **特长**：远程武器、陷阱更强，负重 ↑。**缺点**：暴躁，交易容易谈崩；心情差时拖累同屋人的心理。
- **关系倾向**：与 grace +5（同为"前线人"）、与 priya −10、与 tasha +5。
- **台词**：偷窃——"拿吧，他们也不见得干净。"杀人——"响了就别啰嗦，赶紧走。"帮助——"……行，进来坐着。别碰我那把椅子。"

| 段 | 触发 | 梗概 | 选择与走向 | 影响 |
|---|---|---|---|---|
| 0 `bark_dale_0`（伏笔，无选项） | 在队，day≥3，有 weapon_any | 他在院子里架陷阱，头也不回：“脚印别踩，丫头，学着认。” | — | 置 `flag.bark_dale_0`；tasha 在队时 `relation(dale, tasha) +3` |
| 1 `arc_dale_1` | stage=0，已播伏笔，day≥10 | 他在河滩认出一个被他以前的车队"丢下"的老司机（`npc.odell`，dale 的旧识） | A 让他带路回河边；B 他拒绝回忆 | A：解锁 river_dock 线索，odell 愿以鱼换电池；B：心情− |
| 2 `arc_dale_2` | stage=1，`deed_exists{verb in abandon, refuse_help}` 或 (`day≥18` 且 队内有成员处于低落/抑郁) | 有人被丢下，或他觉得队友要散伙，当场炸了 | A 让他发火（他心理+、关系−）；B 劝他（grace/elena 在队时可行） | 影响：全队凝聚；他可能单独离队 |
| 3 `arc_dale_3` | stage=2，day≥22 | 他提出"最后一个晚上，我守" | A 同意：他守夜，守住家时尾声强；B 不同意，他闷头离开 | 结局：守家变体"有人守夜" |

- **崩溃表现**：对队友破口大骂，然后拿着枪独自出走，在雪地里"找鹿"。可谈话拉回，成功率看关系值。

### 3.6 tasha — 塔莎·布鲁克斯 Tasha Brooks（17 岁）

- **小传**：哈洛瀑布高中田径队的 800 米选手，寒潮前刚收到州立大学的试训通知。父母在第三个月因煤气中毒去世，她一个人带着弟弟在街坊间讨吃的，后来弟弟走散了。她跑得快，队里跑腿传话的活常落在她头上。别人一说"你还小、别去"，她嘴上不顶嘴，转身就把鞋带系得更紧。
- **价值观**（同情 / 务实 / 秩序）：.8 / .2 / .5
- **特长**：移动速度 ↑，脚步噪音 ↓。**缺点**：负重低；杀人会留下严重创伤（kill 负向 ×2，长期压力条目）。
- **关系倾向**：与 junho +10、与 grace +5、与 sam −5（觉得他危险）。
- **台词**：偷窃——"我以前偷过一次。出来就吐了。"杀人——"别这样……让我出去等行吗？"帮助——"我背得动，你们走前面。"

| 段 | 触发 | 梗概 | 选择与走向 | 影响 |
|---|---|---|---|---|
| 0 `bark_tasha_0`（伏笔，无选项） | 在队，day≥3 | 她从雪里捡起一只小孩的手套，塞进外套内袋：“这只……跟我弟弟那双一样大。” | — | 置 `flag.bark_tasha_0` 与 `flag.tasha.glove`（`arc_tasha_1` 前置，手套与 river_dock 的线索衔接） |
| 1 `arc_tasha_1` | stage=0，已播伏笔，day≥9 | 弟弟的下落线索：有人在 river_dock 见过一个戴着单只红手套的小男孩（与她那只成对） | A 派她去找（需有人陪同）；B 阻止 | A：解锁 river_dock 线索，可能找到弟弟（`rumor.tasha_brother` 三分支）；B：关系−−，心理− |
| 2 `arc_tasha_2` | stage=1，队伍在她面前发生 `kill` 或 (`day≥18` 且 发现过死去的住户) | 她第一次直面死亡 | A 全队停下陪她一晚；B 命令继续行动 | A：心理缓冲、关系+；B：她可能崩溃 |
| 3 `arc_tasha_3` | stage=2，day≥22 | 试训通知书被她烧了取暖，或交给队友 | A 劝她留着：尾声"跑向南方"；B 烧 | 结局：南行/守家变体 |

- **崩溃表现**：连续两天不说话，蜷在最小的一间屋，不会主动离队；队友谈话成功率高。

### 3.7 walt — 沃尔特·雷耶斯 Walter Reyes（68 岁）

- **小传**：退休木匠，干了四十年橱柜和屋架。老伴过世前留下的那间老屋，让他翻修得像个碉堡。心脏不好，药只剩半瓶。他平时话少，见着门窗漏风就顺手拿木条钉上；看见年轻人偷东西不骂人，只冷着脸问一句"家里大人知道吗"。
- **价值观**（同情 / 务实 / 秩序）：.7 / .3 / .9
- **特长**：建造与加固更省料、更快。**缺点**：年迈，行动慢，易生病。
- **关系倾向**：与 marcus +10、与 tasha +10、与 sam −5。
- **台词**：偷窃——"手别太野，拿了就赶紧走。"杀人——"我这把年纪了，不想看这个。"帮助——"拿去吧，反正我也用不完。"

| 段 | 触发 | 梗概 | 选择与走向 | 影响 |
|---|---|---|---|---|
| 0 `bark_walt_0`（伏笔，无选项） | 在队，day≥3 | 他蹲在后墙下，拿旧栅栏木条一根根钉：“漏风的地方，早补早省柴火。” | — | 置 `flag.bark_walt_0`；`home.condition` +1（用院里旧木条，不耗 scrap 与 firewood；原第 1 段"防御+"的机制后果） |
| 1 `arc_walt_1` | stage=0，已播伏笔，day≥9，有药品 | 他的心脏药快没了，他瞒着 | A 让 elena 检查并分药；B 他拒绝 | A：关系+，elena 参与；B：伏笔，day 15 后可能触发危机 |
| 2 `arc_walt_2` | stage=1，day≥15 | 他教 tasha 或 sam 做木工，说起自己年轻时的错 | A 让 sam 学（秩序转向）；B 教 tasha | A：sam 价值观 秩序 +0.1、关系+；B：tasha 关系+ |
| 3 `arc_walt_3` | stage=2，day≥22 | 他想用余下的木料做避寒小间，但需要全队出力 | A 全力支持：守家结局变体"房子站着"；B 不同意 | 结局：若 walt 存活则增强守家变体；若他在此前死亡，改为尾声里的一块木牌 |

- **崩溃表现**：不会"崩溃"，会"安静地病倒"，拒绝治疗；若病逝，全队有一条持久的压力条目。

### 3.8 priya — 普丽娅·奈尔 Priya Nair（38 岁）

- **小传**：哈洛瀑布最大的房产经纪人，镇上三分之一的房子经过她的手，谁家几口人、地下室有没有壁炉她门儿清。寒潮头一个月她靠帮人估摸哪家空了换到第一批罐头。她嫌脏、怕冷，讨厌别人背后说她精明，可真要出门找粮，全队数她最会算哪户人家还扛得住。
- **价值观**（同情 / 务实 / 秩序）：.4 / .9 / .4
- **特长**：交易价更好，哨站交涉有加成。**缺点**：挑剔，挨饿受冻时心理下降更快。
- **关系倾向**：与 dale −10、与 elena −10、与 sam +5（同为"算计型"）。
- **台词**：偷窃——"挑门牌号单数的那排，那几户去年刚添过冷柜。"杀人——"疯了吧，这账怎么算？"帮助——"行，东西给你。下回有消息先告诉我。"

| 段 | 触发 | 梗概 | 选择与走向 | 影响 |
|---|---|---|---|---|
| 0 `bark_priya_0`（伏笔，无选项） | 在队，day≥3 | 她把一张全镇住户清单拍在桌上：“谁家有冷柜、谁家有壁炉，我心里都有数。” | — | 置 `flag.bark_priya_0`；解锁 3 户住户的初始情报（`loc.*.known`）；`relation(elena, priya) −2`（原第 1 段的机制后果） |
| 1 `arc_priya_1` | stage=0，已播伏笔，day≥10 | 她在哨站交涉中认出中尉的前妻是她的客户 | A 利用关系：kilo.favor+；B 不用 | A：中尉线更顺，`rep.kilo`+；B：中立 |
| 2 `arc_priya_2` | stage=1，day≥16，tension 高 | 她提议"卖掉"一个住户的存粮位置给军士 | A 同意：`inform`、kilo.favor+、civilians 恶名风险；B 拒绝 | A：军士线推进；B：她心理− |
| 3 `arc_priya_3` | stage=2，day≥22 | 她拿出自己最后一件奢侈品（一枚戒指）换全员名额 | A 接受：`kilo.slots_paid_extra`+1；B 拒绝 | 结局：地下变体"全员入内" |

- **崩溃表现**：喋喋不休地列出损失，最后不再要求任何东西；有可能带着自己那份物资搬去教堂。

### 3.9 sam — 萨姆·奥尔蒂斯 Sam Ortiz（33 岁）

- **小传**：开了十二年锁匠铺，十八岁时因入室盗窃坐过两年牢，后来在镇上踏实干了十五年才让人不再指脊梁。寒潮头一个月大家全找他配钥匙开地窖，没人提从前的事；第三个月他帮人开了一扇不该开的门，里面还有人。那之后他话更少了，总抢着干脏活累活，生怕队友哪天把他踢出去。
- **价值观**（同情 / 务实 / 秩序）：.5 / .8 / .2
- **特长**：撬锁又快又静，潜行强。**缺点**：不被信任（队友关系起点低），绝境时可能偷团队物资。
- **关系倾向**：与 priya +5、与 walt −5、与 elena −5、与 tasha −5。
- **台词**：偷窃——"后门暗锁三秒就能拨开，动作轻点。"杀人——"我蹲过号子，知道里面什么样。别把我逼回去。"帮助——"这门我熟，你们站后面。"

| 段 | 触发 | 梗概 | 选择与走向 | 影响 |
|---|---|---|---|---|
| 0 `bark_sam_0`（伏笔，无选项） | 在队，day≥3 | 有人嘀咕"东西好像少了"，他立刻开口：“要不现在就点一遍？我站在这儿。” | — | 置 `flag.bark_sam_0`；无机制后果 |
| 1 `arc_sam_1` | stage=0，已播伏笔，day≥10，食物紧缺 | 他在深夜站在储藏室门口，手里有一把钥匙 | A 夜里有人发现并劝他；B 无人发现，他取走一份物资（`steal`，target=teammate） | A：关系+；B：物资−、flag `sam.stole_team`，之后如被发现，全队对 sam 关系 −15（§2.4"偷队友"） |
| 2 `arc_sam_2` | stage=1，day≥16 | 他在一户人家门前认出"开错了的那扇门" | A 去敲门道歉（`confess`）；B 避开 | A：修复，心理+；B：压力条目长期存在 |
| 3 `arc_sam_3` | stage=2，day≥22 | 他提议潜入哨站仓库（夜袭线）并保证不会出事 | A 同意：夜袭副本；B 拒绝 | 结局：夜袭线（成功/失败）见 §7 |

- **崩溃表现**：偷走一份物资后离开，留下一把钥匙。若此前有修复行为（`confess`/`return_goods`），他会留下物资。

### 3.10 grace — 格蕾丝·奥卡福 Grace Okafor（31 岁）

- **小传**：基洛哨站的战地医护兵（下士），在清理县北公路路障时被强令参与处决一名搭便车的平民，当晚翻出铁丝网逃了。右肩有旧枪伤，阴冷天发紧。她在哨站里有熟人，也有巴不得她闭嘴的人。夜里睡得极浅，常听见风声就摸到窗边站着。
- **价值观**（同情 / 务实 / 秩序）：.6 / .5 / .6
- **特长**：近战与枪械强；认识哨站的人（专属路线：`kilo.stage` 入口之一）。**缺点**：创伤后应激，枪声下可能僵住；夜里噩梦（睡眠恢复 ↓）。
- **关系倾向**：与 elena +10、与 dale +5、与 priya −5。
- **台词**：偷窃——"换作是我，半夜进院子的人我直接开枪。自己想清楚。"杀人——"……别说了，埋了吧。"帮助——"别乱动，让我看看伤口。"

| 段 | 触发 | 梗概 | 选择与走向 | 影响 |
|---|---|---|---|---|
| 0 `bark_grace_0`（伏笔，无选项） | 在队，day≥3 | 远处传来枪声，她已经站到窗边，手还搭在不存在的枪带上：“……是风。我知道是风。” | — | 置 `flag.bark_grace_0`；触发一次 `dream_grace_gunfire`（小幅压力条目，原第 1 段的联动） |
| 1 `arc_grace_1` | stage=0，已播伏笔，day≥11（哨站开放） | 她在哨站巡逻队里认出旧同伴 | A 主动联络（`kilo.contact_via="grace"`，进入中尉线）；B 躲开 | A：哨站线；B：关系−、被通缉风险 |
| 2 `arc_grace_2` | stage=1，`kilo.stage≥1` | 派克军士认出她，要挟 | A 屈服：`kilo.pike_trust`+、她心理−；B 揭露派克：需把柄；C 杀人灭口 | 影响：军士线 / 夜袭线 / 她离队 |
| 3 `arc_grace_3` | stage=2，day≥22 | 她决定承认当年的处决，写下证词 | A 交给中尉：`kilo.lt_trust`+，中尉线完成；B 烧毁 | 结局：地下·中尉线/军士线 |

- **崩溃表现**：枪声下僵住，夜里连续噩梦后拒绝守夜；最终走回哨站"自首"。若被挽留，将与全队保持沉默。

---

## 4. 具名 NPC 与住户

每名 NPC 的字段：id、地点、身份、台词、个人物品（item_name，用于 §10 的受害者文本）、反应倾向、小模拟可能结局（NARRATIVE §2.5）。"态度"指 `loc.<id>.attitude`（−3 敌对 … 0 中立 … +3 友好）。

### 4.0 准入审查表（PLAN §10.6 S6）

准入标准，满足任一即保留具名：**①** 某个可去地点的受害者面孔或交易对象；**②** 势力中的角色；**③** 与某条角色线关联。不满足的降为"地点通用住户"（只在地点描述里用一句话体现，不再有角色卡）。

| id | 地点 | 满足标准 | 结论 |
|---|---|---|---|
| npc.miller_ruth | suburb_house | ① 夜袭受害者面孔（`beggar_at_door`、`gift_from_friendly_household`） | 保留 |
| npc.miller_ben | suburb_house | ① 孩子受害者（`raid_enter_wakes_child` 一类原则 7 的内容） | 保留 |
| npc.hendry_carl | suburb_house（变体） | ① 交易对象（情报交换）；③ elena 线（`neighbor_plea_sick_child`） | 保留 |
| npc.hendry_lily | suburb_house（变体） | ③ elena 线（`arc_elena_1` 的结果分支） | 保留 |
| npc.halvorsen_edith | elder_house | ① 受害者面孔；③ walt、junho 线（`arc_walt_2`、`arc_junho_2` 的邻里联动） | 保留 |
| npc.lindqvist | church | ② st_mark 负责人 | 保留 |
| npc.hollis | church | ② st_mark 仓库执事，但 lindqvist 已是教堂的面孔，且无独立片段或机制 | **降级**为通用住户（"巡夜执事"） |
| npc.bea | church | ② st_mark 志愿护士；③ elena 线（向 elena 求药） | 保留 |
| npc.odell | river_dock / trailer_market | ① 交易对象；② traders；③ dale 线（`arc_dale_1` 的旧识） | 保留，并承接 olaf |
| npc.olaf | river_dock | 与 odell 同地点、同为交易/冰钓角色，单独存在时只满足 ③（dale 旧识），由 odell 承担 | **并入 npc.odell**（冰钓/换鱼、dale 旧识关联改挂 odell，`npc.olaf` 不再有角色卡） |
| npc.rourke | warehouse | ② raiders 头目 | 保留 |
| npc.dot | warehouse | ② raiders 副手，但 rourke 已是仓库的面孔，情报交易可由 rourke 承担 | **降级**为通用住户（"副手"），情报交易并入 rourke |
| npc.finn | warehouse / construction_site | ② raiders（可招募、可放过） | 保留 |
| npc.marsh | checkpoint_kilo | ② kilo | 保留 |
| npc.pike | checkpoint_kilo | ② kilo；③ grace 线 | 保留 |
| npc.ames | checkpoint_kilo | ② kilo 守门哨兵，但 marsh、pike 已各有主线，ames 无独立片段 | **降级**为通用住户（"门岗哨兵"） |
| npc.gus | farm | ① 交易对象 | 保留 |
| npc.nell | farm | ① 受害者面孔（缺药连锁） | 保留 |
| npc.shirin | motel | ① 交易对象（情报） | 保留 |
| npc.hobbs | radio_tower | ③ linwei 线（`arc_linwei_1`、`radio_hobbs_silent`） | 保留 |
| npc.wren | clinic | ① 交易对象（药）；③ elena 线（愿传授） | 保留 |
| npc.garza | school | ① 受害者面孔；PLAN S6 明确保留，并为学校补 `school_garza_door`、`school_after_raid` 进入首批 | 保留 |
| npc.lowe | police_station | ① 夜袭受害者面孔与"保管"交易对象 | 保留 |

审查结果（主代理按收紧后的标准复核）：23 人中 **19 人**保留具名。`npc.olaf` 并入 `npc.odell`；`npc.hollis`、`npc.dot`、`npc.ames` 降级为通用住户。收紧后的标准：**每个地点只保留一张"面孔"卡；同一地点的第二位及以后的具名人物，必须有自己的片段、角色线关联或独有机制**（例如 finn 可招募、nell 的胰岛素两难、bea 与 elena 线、miller_ben 与 hendry_lily 是孩子受害者）。降级者的台词与个人物品可作为该地点通用住户的素材（各地点的无名住户，如学校的 8 个孩子，仍以"通用住户"形式出现在地点描述里，不另设卡）。

### 4.1 NPC 一览

| id | 地点 | 身份 | 台词 | 个人物品 | 反应倾向 | 小模拟可能结局 |
|---|---|---|---|---|---|---|
| npc.miller_ruth | suburb_house | 露丝·米勒，58 岁寡妇，原学校食堂员工 | "罐头在橱柜上层，别动里屋小床上的东西。" | 丈夫留下的猎刀 | 被偷：加强戒备（持刀开门）；被帮：回赠自制果酱；被抢：求救或报复 | 饿死 / 投靠教堂 / 送孙子去教堂后独居 / 被救助后成为朋友 |
| npc.miller_ben | suburb_house | 本，11 岁，露丝的孙子 | "你是 Elena 队里的吗？她上次给了我两颗糖。" | 一只缺角的玩具卡车 | 对外人怯，对友好者很快信任；见到暴力会哭 | 被送往教堂 / 随露丝饿死 / 被掠夺者收留（负面分支） |
| npc.hendry_carl | suburb_house（变体） | 卡尔·亨德里，44 岁，原保险理赔员，丧偶 | "我以前管核赔的，现在家里就剩点工具能换吃的。" | 公文包里的家庭保单 | 爱讲理；被偷：写告示；被帮：愿意做情报交换 | 投靠哨站告密 / 带女儿去教堂 / 因女儿病重上门乞讨 |
| npc.hendry_lily | suburb_house（变体） | 莉莉，7 岁，卡尔的女儿 | "爸爸说天暖了就能出门。" | 一本没读完的绘本 | 发烧高危；是 `neighbor_plea_sick_child` 的主角 | 病愈 / 病逝（触发 elena 线 2 的结果分支） |
| npc.halvorsen_edith | elder_house | 伊迪丝·霍尔沃森，81 岁，退休高中教师 | "先在门垫上把雪跺干净，别把水带进走廊。" | 一箱学生贺卡 | 对礼貌者开门；被偷：不报复但挨饿；被帮：教堂里有人带话 | 病逝 / 被送教堂 / 在你家过冬 / 尸体被发现 |
| npc.lindqvist | church | 卡琳·林德奎斯特，52 岁牧师，互助会负责人 | "外头的事我不管，进了教堂，领多少粮按人头签字。" | 一本被翻烂的账本 | 收容恶名者但不给粮；按声望决定物资；告发者进黑名单 | 过劳病倒 / 把领导权交给执事 / 维持到结局 |
| npc.bea | church | 比阿，29 岁志愿护士，带着 4 个月的婴儿 | "你们认识 Elena 吗？她之前在急诊科待过。" | 一只婴儿鞋 | 对医疗帮助极度感激；会向 elena 求药 | 婴儿夭折（若 med_any 不足）/ 与 elena 同行 |
| npc.odell | river_dock / trailer_market | 奥德尔，57 岁流动商贩，前长途卡车司机（dale 的旧识），卡车改雪橇；冬天在码头冰面钓鱼，承接原 `npc.olaf` | "车陷在雪里没人理，雪橇倒好推，就是冻手。冰面底下发响了，别往中间走。" | 一只旧怀表、一把手摇钻 | 讲价；对被他讹过的人冷淡；会传话；慷慨，愿用鱼换电池 | 被抢（若你放任）/ 持续交易 / 被掠夺者劫持 / 淹没于冰窟 / 与 dale 和解（`arc_dale_1`） |
| npc.rourke | warehouse | 鲁克，46 岁，锯木厂工头，掠夺者头目 | "东工业区归我管，过路也好找货也好，先交份子。" | 一把电锯链条 | 被杀者复仇；被放过者记仇；可贿赂 | 被哨站击溃 / 被你击杀 / 与哨站交易 |
| npc.finn | warehouse / construction_site | 芬，19 岁，最年轻的掠夺者，原锯木厂学徒 | "我真没想动手……厂子停了没地方去才跟过来的。" | 一张母亲的照片 | 被放过则感激；被杀则全组仇恨 | 叛逃 / 被你招募（requires 放过 + 供食） / 死于混战 |
| npc.marsh | checkpoint_kilo | 伊芙琳·马什中尉，36 岁，国民警卫队后备军官 | "把证件或能顶事的东西拿出来，别跟我绕圈子。" | 一枚被磨掉编号的军徽 | 守纪；对告发谨慎；看重守约；对腐败敏感 | 被军士架空 / 揭发军士 / 战死 / 与你合作 |
| npc.pike | checkpoint_kilo | 达恩·派克军士，42 岁，军需负责人 | "仓库里有些登记不上的边角料，看你们拿什么来换。" | 一只总装着威士忌的行军壶 | 喜欢交易；记仇；可被把柄控制；对 grace 有杀意 | 被中尉免职 / 被你的把柄反制 / 带货潜逃 |
| npc.gus | farm | 格斯·勃兰特，61 岁，农场主，丧偶 | "土都冻实了，锄头下去崩虎口。你们有退烧药吗？" | 一包去年留的种子 | 用药物与燃料换粮；对掠夺者警惕 | 守农场 / 病倒 / 把种子交给教堂 |
| npc.nell | farm | 内尔，58 岁，格斯的妹妹，糖尿病 | "别的东西我都不要，就看能不能弄到胰岛素。" | 一瓶即将用完的胰岛素笔 | 对药物极度感激；缺药数日必有危机 | 病重（连锁 gus 求助）/ 病愈 / 病逝 |
| npc.shirin | motel | 席琳，44 岁，汽车旅馆经营者，情报贩子 | "住店免谈，暖气早就停了。要打听谁家还有油，拿罐头来换。" | 一本客人签到本 | 中立；只按物物交换给消息；可拿线索 | 关店 / 被掠夺者占领 / 与你长期合作 |
| npc.hobbs | radio_tower | 温德尔·霍布斯，70 岁，业余无线电爱好者，"哈洛夜班"广播员 | "今晚零下三十一，还有人开着机子吗？回我一声。" | 一副磨破的耳机 | 隐居；对带来电池或零件的人非常热情 | 病逝 / 继续广播 / 被你救出 |
| npc.wren | clinic | 托拜厄斯·伦医生，67 岁，退休全科医生，留守诊所 | "消炎药只剩两盒，留给伤口化脓的，感冒自己扛。" | 听诊器 | 帮助伤者；对抢药者怒；对 elena 愿意传授 | 被抢药后崩溃 / 救治你的队友 / 病逝 |
| npc.garza | school | 加尔萨老师，33 岁，在学校收留 8 个孩子 | "我以前教体育的，现在天天带着八个小的烧水煮麦片。" | 孩子们画的壁画 | 极度保护孩子；对男性外人警惕；对女性与医护友好 | 带孩子去教堂 / 被迫投靠掠夺者 / 孩子夭折 |
| npc.lowe | police_station | 洛威副警长，49 岁，留守的最后一名警察 | "枪柜钥匙在我这儿，没正经理由别想拿。" | 一枚被磨亮的警徽 | 讲法；放过只要有理由；告发需证据 | 被哨站征用 / 殉职 / 把枪交给你 |

---

## 5. 势力

声望统一范围 −100..+100；档位：**敌对**（≤ −60）/ **戒备**（−59..−20）/ **中立**（−19..+19）/ **友好**（+20..+59）/ **盟友**（≥ +60）。`rep.<faction>` 写入事实黑板。

### 5.1 civilians（平民）

- **目标**：活过冬天，保住自己家。**声望含义**：全镇"恶名/美名"，由 `rumor` 传入（延迟 1–3 天）。
- **阈值与服务**：友好：愿意白天开门交易，报信 `rumor.*`；盟友：可有人投奔、送食物；戒备：只隔门说话；敌对：不开门、投石、通报哨站。
- **声望来源**：

| 来源 | Δ rep |
|---|---|
| 行为 `help`/`give`/`rescue`（受益人知情） | +2 ~ +6 |
| `return_goods` / `confess` | +3 / +4 |
| `bury` | +2 |
| `steal`（有目击者） | −3 |
| `rob`/`assault`（有目击者） | −8 |
| `kill` 平民（有目击者） | −25 |
| `refuse_help`（被求助者知情） | −2 |
| 住户被你害死后 `loc.<id>.attitude=−3` 的邻居传播 | −5 |

- **敌对后的行动**：关门、涂鸦，白天不再接受交易；在夜里设陷阱或警报，提高 `loc.*.guard`；向哨站告发。

### 5.2 st_mark（圣马可教堂互助会）

- **目标**：让尽可能多的人活到春天；以登记与记录维持秩序。
- **阈值与服务**：中立：可白天交换；友好：以优惠价换药品/柴火，可求助；盟友：可寄宿 1 名队员，或在大寒潮时借用避寒所；戒备：只能取一次食物；敌对：被赶走，且执事会在夜里派人守门。
- **声望来源**：

| 来源 | Δ rep |
|---|---|
| 捐赠（`give` to church，food_any/med_any） | +3 ~ +8 |
| 护送难民到教堂 | +6 |
| 帮 bea/wren 医疗事务 | +4 |
| 偷教堂 | −15 |
| 目击者作证（`witness_testimony_st_mark`）后 | −10 |
| 杀平民（谣言传入） | −20 |
| 交易 `trade_cheat` | −5 |

- **敌对后的行动**：拒绝交易，向哨站和平民传话；若处于"盟友"后背叛，触发 `betrayal_church` 世界反应。

### 5.3 traders（流动商贩）

- **目标**：做买卖，保住货。
- **阈值与服务**：中立：正常价；友好：8 折，优先送来药品；盟友：预告行程，开放特殊货；戒备：要价高；敌对：不来。
- **声望来源**：

| 来源 | Δ rep |
|---|---|
| `trade_fair` | +2 |
| `trade_cheat`（被发现） | −10 |
| `rescue` 商贩 | +10 |
| 抢商贩（`rob` target trader） | −30，并 `rumor.traders_avoid` |
| 抢走掠夺者劫持的货并归还 | +8 |

- **敌对后的行动**：不上门；在其他商贩之间传话；你的区域 `trader.route` 绕行。

### 5.4 raiders（掠夺者）

- **目标**：以仓库为据点，收"保管费"，抢夺油与药。
- **声望含义**：对掠夺者来说是"威胁度/恩怨"：敌对 = 视你为必杀对象；中立 = 视你为猎物；友好 = 愿意交易；盟友 = 招募你。
- **阈值与服务**：友好：可买走私货（价格偏高）；盟友：给情报、放过你家；敌对：夜袭家、劫持商贩、报复被你害过的住户。
- **声望来源**：

| 来源 | Δ rep |
|---|---|
| `kill` 掠夺者 | −20（并 `raiders.vendetta`+1） |
| `spare` 掠夺者 | +6 |
| `trade` 与其做交易 | +4 |
| 帮助被抓的 finn | +10 |
| 向哨站告发掠夺者据点 | −15 |
| 被你害过的住户投靠掠夺者 | `raiders.strength`+1 |

- **敌对后的行动**：`revenge_party`（夜袭家）、拦路、劫持商贩、向你的家投放火种。

### 5.5 kilo（基洛哨站）

- **目标**：控制汽油与药品，维持"秩序"并保住自己（马什）；倒卖物资发财（派克）。
- **阈值与服务**：中立：可接触、被盘查；友好：可交换发电机零件、药品；盟友：获得庇护资格；戒备：被盘查并没收武器；敌对：被通缉，夜间路上有巡逻。
- **声望来源**：

| 来源 | Δ rep |
|---|---|
| 交付 `fuel_any` / `med_any` / `whiskey` | +3 ~ +6 |
| 办事（取回物资、修发电机、救治伤员） | +5 ~ +10 |
| 告发邻居存粮 (`inform`) | +4（civilians −3） |
| 杀死哨站士兵 | −40 |
| 偷哨站物资（被发现） | −20 |
| 帮助 grace 的前战友 | +6（仅 grace 在队） |
| 向 lt_marsh 揭发 pike 的把柄 | +12（pike_trust 清零） |

- **敌对后的行动**：封锁相关地点、通缉、夜里巡逻队上门，大寒潮时拒绝一切庇护。

---

## 6. 地点原型

### 6.1 总表

占用概率（%）：空置 / 平民 / 商贩 / 敌对；"白天"栏为白天门口交互；"布局"为布局模板数；"夜袭难度"：1–5。

| id | 中文名 / English | 空置 | 平民 | 商贩 | 敌对 | 布局 | 夜袭难度 | 关联 NPC |
|---|---|---|---|---|---|---|---|---|
| supermarket | 哈洛超市 Harlow Foods | 60 | 5 | 0 | 35 | 3 | 3 | rourke（若敌对） |
| pharmacy | 主街药房 Main St Pharmacy | 70 | 10 | 0 | 20 | 2 | 2 | — |
| gas_station | 国道加油站 Route 14 Gas | 55 | 0 | 15 | 30 | 2 | 2 | — |
| hardware_store | 五金店 Brandt Hardware | 75 | 5 | 0 | 20 | 2 | 2 | — |
| suburb_house | 郊区住宅 North Hill Home | 15 | 75 | 0 | 10 | 3 | 2 | miller_ruth, miller_ben, hendry_carl, hendry_lily |
| elder_house | 老人之家 Elder's House | 20 | 80 | 0 | 0 | 2 | 1 | halvorsen_edith |
| church | 圣马可教堂 St. Mark's | 0 | 100 | 0 | 0 | 2 | 4 | lindqvist, bea |
| school | 北坡小学 North Hill Elementary | 30 | 60 | 0 | 10 | 2 | 3 | garza |
| clinic | 诊所 Falls Medical | 30 | 60 | 0 | 10 | 2 | 3 | wren |
| warehouse | 木材仓库 East Works Yard | 0 | 0 | 0 | 100 | 3 | 5 | rourke, finn |
| farm | 勃兰特农场 Brandt Farm | 5 | 90 | 0 | 5 | 2 | 3 | gus, nell |
| radio_tower | 电台塔 South Ridge Tower | 40 | 60 | 0 | 0 | 2 | 3 | hobbs |
| motel | 河口汽车旅馆 Riverside Motel | 20 | 50 | 20 | 10 | 2 | 3 | shirin |
| trailer_market | 拖车营地集市 Flats Market | 0 | 20 | 70 | 10 | 2 | 3 | odell |
| construction_site | 未竟工地 Falls View Site | 50 | 0 | 0 | 50 | 2 | 3 | finn |
| police_station | 警察局 Harlow PD | 20 | 40 | 0 | 40 | 3 | 4 | lowe |
| river_dock | 河边码头 River Landing | 40 | 20 | 40 | 0 | 2 | 2 | odell |
| checkpoint_kilo | 基洛哨站 Checkpoint Kilo | 0 | 0 | 0 | 100 | 2 | 5 | marsh, pike |

备注：checkpoint_kilo 的 `occ` 固定为 `hostile`，不随机（"敌对"指武装）；它的"官方"身份不新增 `occ` 枚举，由地点 id 与 `rep.kilo` 表达。warehouse 固定掠夺者。每局至少有一个超市/药房被"敌对/平民"占用，保证夜袭有对象（生成器校验）。

### 6.2 逐地点详述

每地点：**白天互动** / **夜间潜行** / **布局差异** / **片段与解锁**。

**supermarket**
- 白天：空置时无；平民占用时门口换粮；敌对时被驱赶。
- 夜间：入口为后仓卸货门（需 crowbar 或 lockpick）；敌对占用时有 2 人巡逻，冷库与收银台是关键房间；货架多，战利品大但噪音大。
- 布局：A 带冷库；B 带二层办公室；C 被烧毁一半（零战利品，多瓦砾）。
- 片段：`raid_found_hidden_cellar`；解锁：第 2 天。

**pharmacy**
- 白天：平民占用时可门口换药。
- 夜间：入口为橱窗后的侧门；药品柜上锁（lockpick）；柜台后的储藏间是 `med_any` 集中地。
- 布局：A 带地下室；B 柜台在二楼。
- 片段：`dream_victim_returns`（若在此杀人）；解锁：开局。

**gas_station**
- 白天：商贩占用时可买 `fuel_any`。
- 夜间：入口为便利店后门；油罐区（`gasoline`）有噪音与易燃风险；机修间含 `parts_any`。
- 布局：A 双车位；B 带小型修车间（南行线索）。
- 片段：`travel_raider_toll`；解锁：第 5 天。

**hardware_store**
- 白天：平民占用时门口换 `scrap`/`parts_any`。
- 夜间：入口为后巷；仓库区含 `crowbar`、`lockpick`、`scrap`；货架高，易碰倒。
- 布局：A 一层；B 带阁楼。
- 解锁：第 2 天。

**suburb_house**
- 白天：门口乞讨/交易；可见住户。
- 夜间：窗户（撬）与后门（锁），住户在卧室睡眠；厨房是 `food_any`，卧室有 `luxury_any` 与个人物品；孩子易惊醒。
- 布局：见下方字符网格（3 套：A 米勒家、B 亨德里家、C 空置带地下室）。
- 片段：`beggar_at_door`、`raid_enter_wakes_child`；解锁：开局。

```
 suburb_house 布局 A（米勒家，12×8）
 ##########+###
 #K.K..#B..B..#
 #...T.#......#
 ####+##...b..#
 #L...L+###+###
 #..S..#C.....#
 #..f..+...w..#
 ####D#########
 K 厨房台面(food)  T 餐桌  B 床  b 婴儿床/孩子床
 L 客厅  S 沙发  f 壁炉  C 衣橱  w 窗(可撬)  D 前门  + 内门
```

**elder_house**
- 白天：门口交谈，换茶/书；对礼貌者开门。
- 夜间：几乎不设防，但居住者浅睡；关键房间为卧室旁的储藏柜（`food_any`、药品 `med_any`）。
- 布局：A 平房；B 带地下防空洞。
- 片段：`arc_walt_2`（若 walt 在队）；解锁：开局。

**church**
- 白天：互助会窗口：换物、登记、避寒；声望决定服务。
- 夜间：入口为钟楼侧门与地下室的通风口；巡夜执事（通用住户）巡夜，仓库在地下室，粮食量大但守卫最多。
- 布局：A 传统十字形；B 带附属礼堂。
- 片段：`witness_testimony_st_mark`、`survivor_flees_to_church`；解锁：第 3 天。

```
 church 布局 A（16×12）
 ################
 #..p p p p p p.#   p 长椅
 #..............#
 #.A............#   A 祭坛
 ####+####+######
 #S.#C.C.#V.....#   S 钟楼梯  C 储物柜  V 通往地下室
 #..#....#......#
 ##D##...######+#   D 正门   + 侧门（夜间入口）
 ┌ 地下室 ┐
 #G G G G G G.##    G 货架(粮仓)  H 巡夜执事的值班桌在入口旁
```

**school**
- 白天：门口与 garza 交谈；孩子在窗口。
- 夜间：入口为体育馆侧门；garza 的警觉高，孩子们睡在体育馆；食堂有 `food_any`。
- 布局：A 一层；B 二层教室。
- 片段：`school_garza_door`（白天）、`school_after_raid`（夜袭后）、`raid_found_dead_household`（若被毁）；解锁：第 4 天。

**clinic**
- 白天：wren 在场时可门口求医、换药。
- 夜间：入口为后巷药品门；wren 睡在诊室；手术室与药柜 `med_any`；他警觉度低。
- 布局：A 一层；B 带地下室。
- 片段：`crisis_intervene`（可寻求 wren 帮助）；解锁：第 4 天。

**warehouse**
- 白天：不可进，只能远观。
- 夜间：掠夺者据点；入口为屋顶通风口与西侧货运门；rourke 住在办公室；货堆是视线遮挡；关键物品：汽油、药品、派克的货单（把柄）。
- 布局：见字符网格（3 套：A 长条形；B 双层；C 带地下室）。
- 片段：`raid_found_ledger`；解锁：第 9 天。

```
 warehouse 布局 A（20×10）
 ####################
 #O.........c c c c.#   O 办公室(rourke)
 #....T.....c c c c.#   c 货箱
 ###+###............#   T 桌(货单)
 #d d d .....G G G..#   d 睡铺  G 汽油桶
 #d d d .....G G G..#
 ####+###############
 +  货运门(西)   +  通风口(屋顶)
```

**farm**
- 白天：门口换 `food_any`（土豆、罐头），用药品或燃料交换。
- 夜间：入口为谷仓后门；仓库、地窖有存粮；狗叫是警报；gus 在屋里持枪。
- 布局：A 谷仓 + 住宅；B 住宅 + 温室。
- 片段：`neighbor_plea_sick_child` 的延伸（nell 缺药）；解锁：第 12 天或 `rumor.farm`。

**radio_tower**
- 白天：不可。夜间到访才能进入。
- 夜间：入口为底层铁门；hobbs 住在塔基小屋；关键房间：发射机房（`radio_parts`、`components`）。
- 布局：A 塔基单间；B 塔基带阁楼。
- 片段：`radio_hobbs_silent`；解锁：`rumor.tower` 且 radio.level≥2。

**motel**
- 白天：shirin 门口交易线索。
- 夜间：入口为后院楼梯；客房有零散 `luxury_any`；前台账本。
- 布局：A U 形；B 一字形。
- 片段：`dawn_lead_from_shirin`；解锁：第 10 天或 `rumor.motel`。

**trailer_market**
- 白天：商贩集中，交易最多。
- 夜间：营地内多人睡眠；货车上锁；掠夺者偶尔抢劫。
- 布局：A 环形；B 线形。
- 片段：`trader_odell_arrives`；解锁：第 6 天。

**construction_site**
- 白天：不可。夜间：入口为围栏缺口；吊机下存放 `scrap`、`firewood`；少量敌对巡逻。
- 布局：A 脚手架楼；B 单层框架。
- 片段：`raid_enter_wakes_child`（若有难民）；解锁：第 8 天。

**police_station**
- 白天：lowe 在场，仅门口交谈，可请求"保管"。
- 夜间：入口为拘留所后门；枪柜（`handgun`、`handgun_ammo`）在军械室，最危险；lowe 睡在值班室。
- 布局：A 单层；B 两层 + 地下证物室。
- 片段：`kilo_patrol_stop`（周边）；解锁：第 6 天。

**river_dock**
- 白天：odell 在冰面钓鱼，可换鱼（dale 的旧识，见 `arc_dale_1`）；商贩偶尔到访。
- 夜间：入口为码头栈桥；冰面的声音会传远；仓库有 `scrap`、`gasoline`（船用）。
- 布局：A 栈桥；B 带船库。
- 片段：`travel_frozen_stranger`；解锁：第 7 天。

**checkpoint_kilo**
- 白天：门口盘查，接触门岗哨兵、marsh 或 pike。
- 夜间：入口为县政府后侧的地下车库；巡逻 + 摄像头已损；关键房间：军需仓、通讯室；全游戏最难副本。
- 布局：见 §7。字符网格见 §7.3。
- 片段：`kilo_marsh_meeting`、`kilo_pike_private_deal`；解锁：第 11 天。

---

## 7. 基洛哨站主线详案

GDD §1.11 的三阶段。主线由 `kilo.stage`（0..4）串起，全程用事实键表示，片段条件只读这些键。哨站内部：**马什中尉**（想维持纪律，要"理由"）与 **派克军士**（倒卖物资，要"东西"）互相牵制；**艾姆斯**是门口的内线；**grace** 的旧识与 **linwei** 的短波是两个额外入口。

### 7.1 阶段与任务

| 阶段 | `kilo.stage` | 开放条件 | 任务清单 | 完成条件 | 效果 |
|---|---|---|---|---|---|
| 0 未开放 | 0 | day < 11 | — | day ≥ 11 且 checkpoint_kilo 已解锁 | 进入阶段 1 |
| 1 接触 | 1 | day ≥ 11 | **K1-a** 通过任意一个入口：路上被巡逻拦下（`kilo_patrol_stop`，`kilo.contact_via="patrol"`）/ 短波找到频率（`radio_kilo_frequency`，需 radio.level≥3，`"shortwave"`）/ grace 引荐（`arc_grace_1`，`"grace"`）。**K1-b** 在门口完成首次盘查（`kilo_marsh_meeting` 或 `kilo_pike_private_deal` 任一） | `kilo.met_marsh` 或 `kilo.met_pike` 为真 | `kilo.favor` +5；开放阶段 2 任务；中尉/军士各一次初始信任 |
| 2 证明价值 | 2 | stage=1 | **中尉线（L）**：L1 交付 fuel_any（`kilo.delivered_fuel`）；L2 救治哨站伤员（elena/grace 在场）；L3 修发电机（marcus 或 linwei；`kilo.generator_fixed`）；L4 夜间取回被掠夺者劫走的哨站物资（warehouse 副本）。**军士线（S）**：S1 交付 whiskey/cigarettes；S2 替派克运私货（`kilo.smuggle_runs`，夜间 travel 片段）；S3 告发邻居存粮（`inform`，每次 civilians −3）。**通用**：priya 交涉加成（kilo.favor ×1.2） | `kilo.favor ≥ 40` 且 `lt_trust ≥ 30` 或 `pike_trust ≥ 30` | 按较高者设 `kilo.line = "lt" / "sgt"`；两者都 ≥ 30 且玩家未选，默认 "lt" |
| 3 庇护资格 | 3 | day ≥ 21 且 stage=2 | **M1** `kilo_slot_decision`（黄昏）：展示名额 `kilo.slots`，并按线分支。**M2** 决定谁入内、谁留下，付"代价包"换额外名额。**M3** 军士线：`kilo_betrayal` 判定；中尉线：马什验证（需 lt_trust ≥ 60） | 选定名单并在大寒潮前一天（day=27）到达哨站，或被出卖 | `kilo.shelter` = "full" / "partial" / "none" / "betrayed" |
| 4 结果 | 4 | day≥28 | 大寒潮期间庇护生效 | — | 结局见 §11 |

### 7.2 分支

| 分支 | 触发 | 流程 | 结果事实 |
|---|---|---|---|
| **中尉线** | `lt_trust ≥ 60`，`pike_trust < 60` 或 `pike_leverage` 为真 | 马什按"理由"审核：`kilo.slots` = 2 + 1（lt 线奖励）。若 grace 写下证词（`arc_grace_3` 选 A）或有揭发派克的证据，再 +1。付 priya/物资的"代价包"可再 +1（每包一名，最多全员） | `kilo.slots` ∈ 2..全员；`kilo.line="lt"` |
| **军士线** | `pike_trust ≥ 60` | 派克承诺名额，要求"礼物"（whiskey/gasoline）。**除非 `kilo.pike_leverage` 为真**，否则 `kilo_betrayal` 以 60% 概率触发：收了东西翻脸、关门；有把柄则派克无法翻脸 | `kilo.line="sgt"`；`kilo.betrayed` 可能为真 |
| **夜袭仓库** | stage≥1 且 `arc_sam_3` 选 A，或 `kilo.stage=3` 且名额谈崩 | 全游戏最难副本：军需仓与通讯室。成功：取得大量 `fuel_any/med_any/ammo_any`；失败：死伤、被通缉 | `kilo.line="raid"`；`kilo.raid_done`；`kilo.raid_result` ∈ success/fail；`rep.kilo` ≤ −60，不可再取得庇护 |
| **被出卖** | `kilo.betrayed` 为真 | 在名单日到达，门被关；此时哨站防线已知你的位置；可选"强闯"（夜袭 hard）或回家守 | `kilo.shelter="betrayed"`；回家则只能走守家结局 |
| **揭发线** | 手头有 `kilo.pike_leverage`（`raid_found_ledger` 或 linwei 窃听）且 `lt_trust ≥ 40` | 交给马什：派克被免职（`kilo.pike_removed`），`rep.kilo` +12，名额 +1；但派克的人手变成敌对 | `kilo.line="lt"` 且 `kilo.pike_removed` |

**名额规则**：`kilo.slots = 2 + lt_bonus(0/1) + evidence_bonus(0/1) + slots_paid_extra`；`slots_paid_extra` 每次由玩家交付一份代价包（燃料/药/酒的组合，具体由 CONTENT 定）+1；上限 = 队伍人数。`kilo.shelter="partial"` 表示 slots < 队伍人数。

### 7.3 夜袭副本布局（checkpoint_kilo，2 套）

A：县政府地下车库入口 → 走廊 → 军需仓 / 通讯室；B：从屋顶通风井下降到军需仓上方（较安静，进出口少）。

```
 checkpoint_kilo 布局 A（18×10）
 ##################
 #G..G....#.......#   G 巡逻点(2人)
 #........+..R....#   R 通讯室
 #..V.....#.......#   V 车库入口
 ####+#####....####
 #Q Q Q....#M.....#   Q 军需货架  M 马什办公室
 #Q Q Q....+.....P#   P 派克的小间(把柄: ledger)
 ##################
```

---

## 8. 事实键目录

类型：N 数值、B 布尔、S 字符串（枚举）、L 列表。`$id` 为模板变量；`派生` = 由 `facts.derive` 计算，不可被效果直接 set。

| 键 | 类型 | 含义 / 取值 |
|---|---|---|
| `day` | N | 1..30，当前天数 |
| `phase` | S | day / dusk / night / dawn |
| `act` | N | 1..3，派生自 day |
| `cold.next_day` | N | 下一次小寒潮日期（0=无）；准确度受 radio.level 影响 |
| `cold.big_day` | N | 大寒潮首日（28..30）；linwei 线 3 可确认 |
| `cold.count` | N | 已发生的小寒潮次数 |
| `tension` | N | 0–100，导演张力（派生） |
| `radio.level` | N | 0..3，无线电等级 |
| `team.size` | N | 当前队伍人数 |
| `team.morale_min` | N | 最低心理状态（派生） |
| `home.heat_ok` | B | 家中至少一间房 ≥ 舒适温度（派生） |
| `home.condition` | N | 0..3，房屋状态（破损/修复） |
| `home.fortified` | B | 门窗是否已加固 |
| `car.fixed` | B | 车是否修好（南行条件） |
| `car.fuel` | N | 车辆燃料量 |
| `arc.<char>.stage` | N | 0..3，角色线进度（完成第 n 段后 = n），char ∈ 十人 |
| `flag.bark_<char>_0` | B | 伏笔台词已播出（`arc_<char>_1` 前置） |
| `arc.<char>.flag` | S | 该线的分支标记（如 `marcus.hides_smokes`） |
| `char.<id>.addict` | N | 0..3 依赖等级（marcus / junho） |
| `char.<id>.crisis` | S | none / warned / broken / recovering，危机进度 |
| `rel.<a>.<b>` | N | −100..100，a 对 b 的关系值（派生，条件里可读） |
| `food_days_home` | N | 家中存粮可撑天数（派生） |
| `kilo.gift_given` | B | 已向派克送礼 |
| `loc.<id>.state` | S | unknown / known / visited / friendly / burned，**只表示对玩家的接触进度**；hostile / empty 不在此，只在 `occ` |
| `loc.<id>.unlocked` | B | 是否已开放 |
| `loc.<id>.occ` | S | empty / civilian / trader / hostile（占用状态；checkpoint_kilo 固定 hostile） |
| `loc.<id>.alert` | B | 因被偷抢而进入戒备（§9.3 `world_guard_up` 置真，`world_return_reset` 置假） |
| `loc.<id>.variant` | S | 布局变体字母 A / B（§6.2、M2-PLAN §2.1；不用数字编号） |
| `loc.<id>.raid_difficulty` | N | 1..5，夜袭难度（§6.1） |
| `loc.<id>.food_days` | N | 住户存粮可撑天数（NARRATIVE §2.5） |
| `loc.<id>.attitude` | N | −3..+3，对玩家态度 |
| `loc.<id>.guard` | N | 0..3 防备等级 |
| `loc.<id>.members_alive` | N | 具名成员存活数 |
| `loc.<id>.visits` | N | 到访次数 |
| `loc.<id>.looted` | N | 被偷抢次数 |
| `npc.<id>.alive` | B | 具名 NPC 是否存活 |
| `npc.<id>.status` | S | ok / sick / injured / missing / fled / dead |
| `npc.<id>.loc` | S | 当前所在地点 id |
| `npc.<id>.fate` | S | 小模拟的最终结局标签（如 `starved`、`joined_raiders`） |
| `rep.<faction>` | N | −100..100，faction ∈ civilians/st_mark/traders/raiders/kilo |
| `rumor.notoriety` | N | 0..100，全镇"恶名" |
| `rumor.<topic>` | B | 线索，topic ∈ tower/farm/motel/kilo/tasha_brother/traders_avoid |
| `rumor.known_<id>` | S | 某行为 deed 已传到的层级：loc/faction/town |
| `kilo.stage` | N | 0..4，见 §7 |
| `kilo.contact_via` | S | patrol / shortwave / grace |
| `kilo.met_marsh` / `kilo.met_pike` | B | 已见过该人物 |
| `kilo.favor` | N | 0..100，哨站总体好感（交付与办事累积） |
| `kilo.lt_trust` / `kilo.pike_trust` | N | 0..100，对两人的信任 |
| `kilo.line` | S | none / lt / sgt / raid |
| `kilo.slots` | N | 庇护名额 |
| `kilo.slots_paid_extra` | N | 付代价包额外增加的名额 |
| `kilo.delivered_fuel` | N | 已交付燃料份数 |
| `kilo.generator_fixed` | B | 发电机已修 |
| `kilo.smuggle_runs` | N | 为派克运私货次数 |
| `kilo.informed_on` | L | 已告发的住户 loc id |
| `kilo.pike_leverage` | B | 掌握派克把柄 |
| `kilo.pike_removed` | B | 派克被免职 |
| `kilo.betrayed` | B | 被出卖 |
| `kilo.raid_done` / `kilo.raid_result` | B / S | 夜袭是否进行 / success / fail |
| `kilo.shelter` | S | none / full / partial / betrayed |
| `raiders.vendetta` | N | 掠夺者对你的复仇累计 |
| `raiders.strength` | N | 掠夺者实力（被害住户投靠则上升） |
| `trader.next_day` | N | 下一次商贩上门的日期（保底每 3 天） |
| `deeds.helped` | N | 帮助/救助累计 |
| `deeds.harmed` | N | 伤害累计（assault/kill/rob 之和） |
| `deeds.kills_civilian` | N | 杀平民累计 |
| `deeds.kills_hostile` | N | 杀敌对累计 |
| `deeds.buried` | N | 埋葬次数 |
| `deeds.repaired` | N | 归还/坦白次数 |
| `deeds.witness_silenced` | N | 灭口次数 |
| `flag.<name>` | B | 一次性标志（`flag.marsh_met` 等） |
| `ending.kind` | S | hold_home / underground / south / fail |
| `ending.variant` | S | 各结局的变体标签 |
| `epilogue.<char>` | S | 逐角色尾声标签（结局时计算） |

**`loc.*` 的数据源**：`state.world.locations[id]`（PARALLEL-PLAN C8）是地点数据的**唯一数据源**；上表的 `loc.<id>.*` 事实全部由它派生（`facts.derive("loc.", ...)`），字段同名（`loc.<id>.occ` = `world.locations[id].occ`，`raid_difficulty`、`variant`、`alert` 等同理），黑板里不另存一份。因此 `loc.*` 只读，写入一律走专用效果：`loc_state`（`state`）、`loc_occ`（`occ`）、`loc_alert`（`alert`）、`loc_add`（`food_days`、`guard`、`attitude`、`looted`……）、`unlock_loc`（`unlocked`）。`state`（接触进度）与 `occ`（占用）互相独立：空屋是 `occ = "empty"`，不是 `state`。

---

## 9. 反应规则目录（25 条）

按 NARRATIVE §2.4 的格式。`$loc`、`$target`、`$actor` 为行为里的绑定。心理族规则的 `psy_generic` 对**每条** deed 都执行；其余在其基础上附加。

### 9.1 心理族（`data/reactors/psyche.lua`）

| id | 匹配条件 | 效果 |
|---|---|---|
| `psy_generic` | 任意 deed | 对每个在队角色按 §2.2 公式计算影响（`target_kind=teammate` 的 deed 改走 §2.4 关系规则）；负 → `psyche.add_stress(char, "deed:<id>", -v, decay=slow)`；正 → 慰藉条目；生成该角色台词 |
| `psy_relation_shift` | 任意 deed（`target_kind≠teammate`），对角色 C 的影响 ≤ −6 且 actor≠C | `relation(C, actor, -ceil(abs(v)/4))`；影响 ≥ +6 则 `+ceil(v/4)` |
| `psy_tasha_kill` | verb=kill，actor=tasha 或 tasha 在场 | tasha 增加长期压力条目 `kill_trauma`（decay=very_slow）；影响 ×2 |
| `psy_repair_return` | verb=return_goods / confess | 清除或减半同一 `target` 的既有压力条目（−50%）；`deeds.repaired`+1 |
| `psy_bury` | verb=bury | 对 target 死亡相关的压力条目 −30%；全队慰藉 +（按 compassion） |
| `psy_refuse_echo` | verb=refuse_help，tags.victim_child 或 victim_vulnerable | `schedule("dream_victim_returns", after_days={1,3})`（对 compassion ≥ 0.6 的角色） |
| `psy_silenced` | tags.silenced | 动手者与同行者额外长期压力；`schedule("dream_victim_returns", ...)` |
| `psy_comfort_help` | verb ∈ help/give/rescue，tags.cost_paid | 动手者 `morale(+)`，原因键 `helped_with_cost`；队友 `relation +1` |
| `psy_teammate_death` | verb=die 且 target_kind=teammate | 其余队友按 §2.4 加压力条目：−12 × 关系系数 k(与死者关系) × 自身 compassion（亲近者的加重已含在 k 中，不再单列）；`flag.<char>.mourning` |

### 9.2 社会族（`data/reactors/social.lua`）

| id | 匹配条件 | 效果 |
|---|---|---|
| `soc_witness_spread` | 有 `witnesses` 且 target_kind=civilian | 该地点知道（`rumor.known_<id>=loc`）；`schedule("rumor_to_faction", {after_days={1,3}})`；之后 `town` |
| `soc_steal_occupied_seen` | verb=steal，occupied，witnessed | `rep(civilians, -3)`；`loc.$loc.attitude -1` |
| `soc_rob_notoriety` | verb ∈ rob/assault，有 witnesses | `rep(civilians, -8)`；`rep(st_mark, -4)`；`rumor.notoriety +8`；`deeds.harmed +1` |
| `soc_kill_civilian` | verb=kill，target_kind=civilian | `rep(civilians, -25)`；`rep(st_mark, -20)`；`deeds.kills_civilian +1`；`deeds.harmed +1`；`schedule("kilo_asks_about_victim")`（若有活着的目击者） |
| `soc_kill_raider` | verb=kill，target_kind=raider | `rep(raiders, -20)`；`raiders.vendetta +1`；`rep(kilo, +3)`（若 witnessed 为 soldier） |
| `soc_help_stranger` | verb ∈ help/give/rescue，target_kind=civilian | `rep(civilians, +4)`；`loc.$loc.attitude +1`；`deeds.helped +1` |
| `soc_trade_cheat` | verb=trade_cheat | `rep(traders, -10)`；`rumor.traders_avoid` 若累计 ≥ 2 |
| `soc_inform_kilo` | verb=inform | `kilo.favor +4`；`kilo.informed_on` 追加；`rep(civilians, -3)`；若受害者幸存，`schedule("informed_on_revenge", {after_days={2,4}})` |
| `soc_betray_teammate` | verb ∈ abandon/betray/assault/kill/steal/refuse_help，target_kind=teammate；或 verb=rescue（对象为队友） | 按 §2.4 关系规则：受害队友对 actor 的关系按表下降（rescue 则上升），其余队友对 actor 的关系 = 表值 × 0.25 × k(与受害者关系)；`betray` 另置 `flag.<actor>.betrayer` |

### 9.3 世界族（`data/reactors/world.lua`）

| id | 匹配条件 | 效果 |
|---|---|---|
| `robbed_household_starves` | verb ∈ steal/rob，occupied，took_essentials | `loc_add($loc, food_days, -3)`；`schedule("beggar_at_door", {after_days={2,4}, bind={victim="$target"}})`（`$loc = school` 时改排 `school_after_raid`，见 §10.1） |
| `world_guard_up` | verb ∈ steal/rob，occupied | `loc_add($loc, guard, +1)`；`loc_alert($loc, true)` |
| `world_defect_to_raiders` | `loc.$loc.food_days ≤ 0` 且 `loc.$loc.attitude ≤ -2` 且 `raiders.strength ≥ 1` | `chance 0.3`：`loc_occ($loc, "empty")`，`raiders.strength +1`，`schedule("revenge_party", {after_days={3,5}})` |
| `world_survivor_flees` | verb ∈ rob/assault/kill，有 `witnesses` 存活 | 幸存者 `npc.<id>.status="fled"`，`loc` 改为 church 或 checkpoint_kilo；`schedule("survivor_flees_to_church")` |
| `world_empty_house_squatter` | `loc.$loc.members_alive == 0` 且 `loc.$loc.occ="empty"` | 每日 `chance 0.1`：`loc_occ($loc, "hostile"` 或 `"civilian")` |
| `world_friend_gift` | `loc.$loc.attitude ≥ +2`（交易或帮助累计 ≥ 2） | `schedule("gift_from_friendly_household", {after_days={2,4}})` |
| `world_burial_closure` | verb=bury | 对 `$loc` 邻居 `attitude +1`；`rep(st_mark, +2)` |
| `world_unwitnessed_kill` | verb=kill，无 witnesses | 不触发传播；`schedule("body_found", {after_days={3,5}, bind={loc="$loc"}})`，找到后 `loc_occ($loc, "empty")` |
| `world_return_reset` | verb=return_goods | `loc.$loc.attitude +2`（上限 0 → 若原为 −3 则恢复至 −1）；`loc_alert($loc, false)` |

---

## 10. 首批 42 个故事片段

**曝光预算与参数化**（PLAN §10.6 S1–S3）：导演每天最多推出 2 个有选项的片段（`balance.story.daily_choice_budget = 2`，危机与排期片段不占预算但计入统计），单局约 40–50 次有选项曝光；片段池目标约 80 个，首批 42 个 = 原 40 个 + 学校 2 个（S6），其余由角色线 30 段与结局、哨站、南行衔接片段补足；加内容的门槛是 §4.7 的两个重玩指标（单局内无重复、两局重合率低于 50%），M10 先用约 80 个片段跑批量模拟，不达标才补写。因此首批优先写**参数化**片段（带 `$victim`、`$loc` 绑定，一个片段覆盖多个地点或住户）。首批 42 个中参数化的共 **12 个**：`beggar_at_door`(1)、`beggar_forgiven`(2)、`revenge_party`(3)、`informed_on_revenge`(4)、`survivor_flees_to_church`(6)、`witness_testimony_st_mark`(7)、`kilo_asks_about_victim`(8)、`gift_from_friendly_household`(14)、`dream_victim_returns`(17)、`raid_found_hidden_cellar`(35)、`raid_found_dead_household`(36)、`raid_enter_wakes_child`(38)；其余 30 个绑定固定地点、固定人物或系统状态，不可跨地点复用。无选项的只有 #17（不占每日预算）。

表中 `when` 为 DSL 摘要（略去 `all`）；"原则"列为 NARRATIVE §2.2 的编号（1 系统压力 2 两难 3 作恶划算 4 行善有成本 5 不显示善恶 6 延迟可追溯 7 受害者具体 8 灰度与退路）。tier：S=scheduled，A=arc，M=ambient。`冷却` 默认 4 天；`gate` 表示全局一次。

### 10.1 总表

| # | id | slot | tier | when（摘要） | 内容梗概 | 选项与效果摘要 | 原则 |
|---|---|---|---|---|---|---|---|
| 1 | `beggar_at_door` | door_day | S | 受害户 `npc_alive`，`loc.$v.food_days ≤ 0` | 被你偷过的住户饿得上门，点出"那天夜里"的事 | 给 food_any×2（`give`，`loc_add food_days +2`）/ 拒绝（`refuse_help`）/ 归还全部（若有 `steal` → goto `beggar_forgiven`） | 5,6,7,8 |
| 2 | `beggar_forgiven` | door_day | S | 由 goto 进入 | 对方收下归还，沉默后说出一条情报 | 收下：`return_goods`，`rep civilians +3`，`rumor.<topic>` | 8,6 |
| 3 | `revenge_party` | dawn | S | `world_defect_to_raiders` 排期，`loc.$loc` 已 empty | 被害家庭带着掠夺者夜袭你家，点名那件事 | 守夜判定（加固/守夜人数）；失败：`item - food_any`、`wound`；成功：`raiders.vendetta -1` | 6,3 |
| 4 | `informed_on_revenge` | door_day | S | `kilo.informed_on` 含被告发户，排期 2–4 天 | 被告发的邻居上门质问："士兵来过我家" | 解释（`lied` 或真话）/ 承认（`confess`）/ 威胁（`assault` 风险） | 6,7,8 |
| 5 | `neighbor_plea_sick_child` | door_day | M | lily 在，`status=sick`，day 8–24 | 卡尔来求抗生素救七岁的女儿莉莉 | 给 antibiotics / 拒绝 / 换情报（见 §10.2 完整 Lua） | 1,2,4,7 |
| 6 | `survivor_flees_to_church` | door_day | S | `world_survivor_flees` 排期，church 已解锁 | 逃出的住户在教堂门口被收留，林德奎斯特向你转述 | 为被害者作证道歉（`confess`）/ 沉默 / 反驳 | 5,6,8 |
| 7 | `witness_testimony_st_mark` | dawn | S | `rumor.known_$d = faction`，`rep st_mark ≤ -20` | 互助会公告：不再向你出售，列出事由 | 辩解（`lied`）/ 赔偿 food_any（`rep +`）/ 无视 | 5,6,8 |
| 8 | `kilo_asks_about_victim` | door_day | S | `soc_kill_civilian` 排期，有幸存目击者 | 两名士兵上门问某户的事，艾姆斯在其中 | 说实话 / 撒谎（`lied`）/ 嫁祸掠夺者 | 6,8 |
| 9 | `radio_hobbs_first` | radio | M | `radio.level ≥ 1`，day 2–6，`gate` | 首次收到"哈洛夜班"：今晚零下三十一，大家还在吗 | 回应（`fact rumor.tower`）/ 只听 | 1,5 |
| 10 | `radio_coldwave_warn` | radio | S | `cold.next_day − day ≤ 3` | 无线电预报小寒潮；准确度看 radio.level | 按预报准备（给出明确提示）/ 忽视 | 1 |
| 11 | `radio_hobbs_silent` | radio | S | 连续 2 夜无广播，`npc.hobbs.alive` | 夜班突然沉默，linwei 担心 | 派人去塔（`unlock_loc radio_tower`）/ 不管 | 6 |
| 12 | `radio_kilo_frequency` | radio | A | `radio.level ≥ 3`，`kilo.stage = 1` 且 `kilo.contact_via` 未设 | linwei 在噪声里找到哨站的加密频段 | 呼叫：`kilo.contact_via="shortwave"`，`kilo.favor +2` / 先监听 | 2 |
| 13 | `dawn_lead_from_shirin` | dawn | M | 连续两夜空手而归（`deed_exists` 无 take） | 席琳托人带来一条"值钱的闲话" | 买情报（`item - cigarettes`）：`unlock_loc` / 不买 | 3,4 |
| 14 | `gift_from_friendly_household` | dawn | S | `world_friend_gift` | 门口放着一包菜：露丝的回赠 | 收下 / 回礼（`give`）；回礼增 attitude | 4,6,7 |
| 15 | `dusk_ration_dispute` | dusk | M | `fact food_days_home ≤ 2`，两人关系 ≤ −10 | 晚餐分配争吵：谁该少吃 | 平分 / 偏给外勤 / 偏给病号；`relation` 变化 | 2,5 |
| 16 | `dusk_storm_eve` | dusk | S | `cold.next_day = day + 1` | 寒潮前夜，全员在最暖的屋里；谁都想说句话 | 守夜安排；`morale` 一次性共同慰藉（若 junho 在则加成） | 1 |
| 17 | `dream_victim_returns` | dream | S | `psy_silenced` / `psy_refuse_echo` 排期 | 梦里是那户人家门口的雪：该角色按价值观不同做不同的梦 | 无选项，写入压力条目（原因键 `dream_<victim>`） | 5,6,7 |
| 18 | `arc_grace_1` | talk | A | grace 在队，stage=0，day≥11，已播 `bark_grace_0` | 她在哨站巡逻队里认出旧同伴 | 主动联络（`kilo.contact_via="grace"`，进入中尉线）/ 躲开（关系−、被通缉风险） | 2,5 |
| 19 | `arc_junho_1` | home_idle | A | junho 在队，stage=0，`has_item whiskey 1`，day≥8 | 他半夜翻出酒，把瓶口对着厨房窗口 | 没收（依赖−、关系−）/ 陪他喝一杯（依赖+、关系+）/ 假装没看见（依赖+） | 1,5,8 |
| 20 | `arc_marcus_1` | talk | A | marcus 在队，stage=0，heater 损毁一次或第 1 次小寒潮后 | 他发现县政府地下锅炉间的图纸在哨站手里 | 主动去哨站接触（`kilo.stage=1` 路线）/ 拒绝（关系−） | 2,5 |
| 21 | `talk_judges_deed` | talk | M | 最近 3 天有 `psy_generic` 影响 ≤ −8 的 deed | 队友对最近的行为有评价，数值不显示，用台词表现 | 道歉 / 辩解 / 沉默；`relation` ±、`psy_repair` 入口 | 5,8 |
| 22 | `arc_tasha_2` | talk | A | `arc.tasha.stage = 1`，tasha 刚目睹 `kill` | 她第一次目睹死亡 | 停下陪她一晚 / 继续行动（可能导致崩溃） | 2,5,7 |
| 23 | `arc_sam_1` | home_idle | A | sam 在队，`arc.sam.stage = 0`，食物紧缺 | 深夜他站在储藏室门口，手里是一把钥匙 | 有人劝 / 无人 → 取走物资（`steal`，target teammate，`flag sam.stole_team`） | 2,5 |
| 24 | `arc_priya_2` | talk | A | `arc.priya.stage = 1`，`kilo.stage ≥ 2` | 普丽娅提议把某户存粮位置"卖给"派克 | 同意（`inform`，`kilo.favor +`）/ 拒绝 | 2,3,5 |
| 25 | `crisis_breakdown_warning` | crisis | S | 任意角色进入"低落" 后至少 1 天 | 预警：他/她不再说话、不再进食（必先于崩溃） | 给予慰藉品 / 谈话 / 休息；`morale` 缓冲 | 8 |
| 26 | `crisis_runaway` | crisis | S | 崩溃，未被干预 | 角色离队或带物资出走；留下一句话 | 追（`rescue` 窗口）/ 放走（`leave`） | 2,8 |
| 27 | `crisis_intervene` | crisis | S | 崩溃，且 `relation(helper, subject) ≥ 15` 或有慰藉品 | 全程离屏文字；队友陪伴过夜，成功则回到"低落" | 见 §10.2 完整 Lua；带"温和叙述"文本 | 8,5 |
| 28 | `trader_odell_arrives` | door_day | M | `trader.next_day ≤ day`，`rep traders > -60` | 奥德尔的雪橇停在门口；这一天可以交易 | 交易（`trade_fair`）/ 讨价 / 赶走 | 3,4 |
| 29 | `trader_wounded_courier` | door_day | M | day 9–22，`rep traders ≥ -20` | 受伤的信使倒在门口，货在他背上 | 救治（elena 加成）/ 抢货（`rob`）/ 报给教堂（见 §10.2） | 2,3,4 |
| 30 | `kilo_patrol_stop` | travel | M | `day ≥ 11`，`kilo.stage = 1`，`contact_via` 未设 | 巡逻队拦下，艾姆斯验你的东西 | 配合（`kilo.contact_via="patrol"`）/ 贿赂 / 逃跑 | 1,3 |
| 31 | `kilo_marsh_meeting` | travel | A | `kilo.stage = 1`，`kilo.met_marsh = false`，目的地为 `checkpoint_kilo` | 马什：把证件或能顶事的东西拿出来 | 交付 fuel_any（`lt_trust +5`）/ 提 grace / 拒绝 | 2,5 |
| 32 | `kilo_pike_private_deal` | travel | A | `kilo.stage = 1`，`kilo.met_pike = false`，目的地为 `checkpoint_kilo` | 派克私下：仓库里有些登记不上的边角料 | 接私货（`smuggle_runs +1`，`pike_trust +5`）/ 拒绝 | 2,3 |
| 33 | `kilo_slot_decision` | dusk | A | `kilo.stage = 2..3`，day ≥ 21，`kilo.shelter = "none"` | 名额公布；每个人名字都要被念出来 | 见 §10.2 完整 Lua | 1,2,4 |
| 34 | `kilo_betrayal` | dawn | S | `kilo.gift_given`，`kilo.line = "sgt"` | 到约定日，门口是另一个班的岗哨 | `fn kilo_resolve_sgt`：无把柄 60% 翻脸；有把柄则放行 | 6,3 |
| 35 | `raid_found_hidden_cellar` | raid_found | M | 平民占用地点，`chance 0.25` | 地窖里躲着一家人，手里握着木棍 | 退出（`spare`）/ 夺走存粮（`rob`）/ 留下食物（`give`） | 2,3,7 |
| 36 | `raid_found_dead_household` | raid_found | M | `loc.$loc.members_alive = 0`，day≥8 | 一屋已冻死的住户，一本日记写着他们是谁 | 埋葬（`bury`）/ 拿走 food_any / 读日记（线索） | 7,8 |
| 37 | `raid_found_ledger` | raid_found | A | warehouse，`kilo.stage ≥ 1`，无 `pike_leverage` | 货单上有派克的签名与哨站编号 | 拿走（`kilo.pike_leverage=true`）/ 放回 | 3,6 |
| 38 | `raid_enter_wakes_child` | raid_enter | M | 有 `victim_child` 的住户 | 孩子半夜醒了，眼睛睁得很大 | 低声安慰（`knockout` 之外的选项：`help`）/ 迅速离开 / 威吓（`armed_threat`） | 2,7 |
| 39 | `travel_frozen_stranger` | travel | M | day≥5，`chance 0.15` | 路边一个人快冻僵了，背着一个小包 | 救人（`rescue`，花 bandage 或 coffee）/ 过去 / 拿走小包 | 2,4,8 |
| 40 | `travel_raider_toll` | travel | M | `raiders.strength ≥ 1`，day≥9 | 掠夺者设卡收"过路费" | 付 food_any / 动手（`kill` 风险）/ 绕路（多耗 30 分钟） | 3,6 |
| 41 | `school_garza_door` | door_day | M | `npc_alive npc.garza`，`loc.school.unlocked`，`loc.school.state` ≠ burned，day 6–22，`gate` | garza 在学校门口拦住你：柴火只够撑三天，孩子们挤在体育馆里；她提出让孩子们缝补、捡柴来换食物 | 给 firewood×2（`give`）/ 以工换粮：交 food_any×2，换 firewood×2 与孩子们缝补的手套（`trade_fair`）/ 压价：一罐豆子换走食堂两天的麦片（`trade_cheat`）/ 拒绝（`refuse_help`）；详见下 | 2,3,4,7,8 |
| 42 | `school_after_raid` | door_day | S | `npc_alive npc.garza`，`loc.school.visits ≥ 1`，且 `deed_exists{verb in steal/rob, loc="school", within_days=10}` 或 `deed_exists{verb="spare", loc="school", within_days=10}`，排期 2–4 天 | 学校被夜袭后的回响：被偷则最小的孩子饿病、garza 找上门；放过则她留下一袋麦片与一幅画作回礼；详见下 | 被偷分支：归还或补偿 / 承认 / 否认；放过分支：收下 / 回礼 / 婉拒；详见下 | 4,6,7,8 |

补充：`body_found`（`world_unwitnessed_kill`）、`rumor_to_faction`（系统任务，非玩家可见片段）、`revenge_party` 的结果变体不计入 42，由 M10 实现。

**学校片段（#41、#42）详述**

- **`school_garza_door`**（白天，ambient，冷却 6 天，全局一次；cast：`garza = npc.garza`，`medic = pick_char{in_team, prefer trait=medical}`，医护在队时 garza 的台词变得友好）。
  - A 给 firewood×2：`give`（tags `victim_child, cost_paid, helped_stranger`，magnitude 0.6）；`loc.school.attitude +2`；`rep civilians +3`；`flag.school_helped`。**成本**：柴火是自家取暖；**回报**：此后 `school_after_raid` 的回礼分支更厚。
  - B 以工换粮（需 `has_item food_any 2`）：`item - food_any 2`，`item + firewood 2`；`deed trade_fair`；`loc.school.attitude +1`；`flag.school_helped`。孩子们缝补的手套使下次出外夜间的冻伤风险略降（具体值由 CONTENT 定）。
  - C 压价（原则 3：这样做更划算）：`item + food_any 2`（来自食堂存粮），`deed trade_cheat`（tags `victim_vulnerable, victim_child, took_essentials`，magnitude 0.7），`loc.school.food_days −2`，`loc.school.attitude −2`，`flag.school_cheated`；garza 此后对男性外人拒绝开门。
  - D 拒绝：`deed refuse_help`（tags `victim_child`，magnitude 0.5），`loc.school.attitude −1`。
  - 原则对应：2 两难（柴火自用还是给孩子）、3（压价最划算）、4（给与以工换粮都有成本）、7（8 个孩子、画在墙上的壁画）、8（以工换粮是灰度出路）。
- **`school_after_raid`**（两个入口，由文本变体区分；`$loc = school`，`$victim = npc.garza`）。
  - **被偷分支**（夜里 `steal/rob` 过学校，由 `robbed_household_starves` 排期；该规则对 school 改为排期本片段而非 `beggar_at_door`）：garza 来到你家门口，最小的孩子因断粮病了。
    - 归还（`has_item food_any 2`，`return_goods`）：`item - food_any 2`，`loc.school.attitude +2`，`rep civilians +3`，`psy_repair_return`；garza 不原谅但收下。
    - 承认（`confess`，不付物资）：`loc.school.attitude +1`；garza 沉默后说"那就别再来"，`loc.school.guard +1`。
    - 否认（`lied`）：无成本；`loc.school.attitude −1`；`schedule dream_victim_returns {after_days={1,3}, bind={victim="npc.garza"}}`；3 天后 `npc.garza.fate = "to_church"`，school `occ ← empty`，之后可能被掠夺者占用。
  - **放过分支**（夜袭中 `spare`，没拿走东西）：garza 夜里听见过动静，白天在门口留了一袋麦片与一幅孩子们的画。
    - 收下（`item + food_any 1`）：`loc.school.attitude +1`，`flag.school_helped`；garza 透露"农场的人来换过种子"：`rumor.farm = true`。
    - 回礼（`give` food_any×1，`cost_paid`）：`loc.school.attitude +2`，`rep civilians +3`，进入 `world_friend_gift`。
    - 婉拒（"留给孩子们"，tags `helped_stranger`）：无物资变化；`loc.school.attitude +1`；队里 tasha 或 junho 心理 +（价值观 compassion 高者慰藉）。
  - 原则对应：4（回礼与归还有成本）、6（被偷与放过都在数日后回来）、7（孩子的画与饿病的孩子）、8（承认与婉拒是不付全价的退路）。

### 10.2 三个完整片段（Lua）

**(1) `neighbor_plea_sick_child`**

```lua
return {
  id = "neighbor_plea_sick_child",
  slot = "door_day",
  tier = "ambient",
  weight = 1.0,
  cooldown_days = 6,
  gate = true,                                   -- 全局只出现一次
  when = { "all",
    { "npc_alive", "npc.hendry_lily" },
    { "fact", "npc.hendry_lily.status", "=", "sick" },
    { "fact", "loc.suburb_house.visits", ">=", 1 },
    { "day_between", 8, 24 },
  },
  cast = {
    carl  = { "npc", "npc.hendry_carl" },
    medic = { "pick_char", { in_team = true }, prefer = { trait = "medical" } },
  },
  text = "st.neighbor_plea_sick_child.body",
  choices = {
    { text = "st.neighbor_plea_sick_child.give",
      when = { "has_item", "antibiotics", 1 },
      effects = {
        { "item", "-", "antibiotics", 1 },
        { "deed", { verb = "give", target = "npc.hendry_lily", target_kind = "civilian",
                    tags = { victim_vulnerable = true, victim_child = true, cost_paid = true, helped_stranger = true },
                    magnitude = 0.8 } },
        { "fact", "set", "npc.hendry_lily.status", "ok" },
        { "rep", "civilians", 4 },
        { "fact", "add", "loc.suburb_house.attitude", 2 },
        { "schedule", "gift_from_friendly_household", { after_days = { 2, 4 }, bind = { victim = "npc.hendry_carl" } } },
      } },
    { text = "st.neighbor_plea_sick_child.trade_info",
      when = { "has_item", "med_any", 1 },
      effects = {
        { "item", "-", "med_any", 1 },
        { "deed", { verb = "give", target = "npc.hendry_lily", target_kind = "civilian",
                    tags = { victim_vulnerable = true, victim_child = true }, magnitude = 0.5 } },
        { "fact", "set", "npc.hendry_lily.status", "improving" },
        { "fact", "set", "rumor.motel", true },     -- 卡尔回报一条线索
      } },
    { text = "st.neighbor_plea_sick_child.refuse",
      effects = {
        { "deed", { verb = "refuse_help", target = "npc.hendry_lily", target_kind = "civilian",
                    tags = { victim_vulnerable = true, victim_child = true }, magnitude = 0.9 } },
        { "die", "npc.hendry_lily", { cause = "illness", delay_days = 2 } },
        { "fact", "add", "loc.suburb_house.attitude", -3 },
      } },
  },
}
```

```
st.neighbor_plea_sick_child.body   卡尔站在门廊台阶下，没敢敲门，听见屋里有动静才隔着门板开口："莉莉烧了两天了，喝水都吐。我知道你们前两天去过药房，匀我一盒退烧的或者消炎的都行，我拿工具抵。"
st.neighbor_plea_sick_child.give   把抗生素递给他。
st.neighbor_plea_sick_child.trade_info   拿别的药跟他换消息。
st.neighbor_plea_sick_child.refuse 关上门。
```

**(2) `crisis_intervene`**（崩溃后的干预；全程离屏；D14）

```lua
return {
  id = "crisis_intervene",
  slot = "crisis",
  tier = "scheduled",
  when = { "all",
    { "char", "$subject", "state_at_least", "broken" },
    { "any",
      { "fact", "rel.$helper.$subject", ">=", 15 },
      { "has_item", "coffee", 1 },
      { "has_item", "whiskey", 1 } },
  },
  cast = {
    subject = { "bound" },                       -- 由 crisis_breakdown_warning 排期绑定
    helper  = { "pick_char", { in_team = true, not_self = "$subject" }, prefer = { relation_to = "$subject" } },
  },
  text      = "st.crisis_intervene.body",
  text_soft = "st.crisis_intervene.body_soft",   -- 设置"温和叙述"开启时使用
  choices = {
    { text = "st.crisis_intervene.stay_night",
      when = { "fact", "rel.$helper.$subject", ">=", 15 },
      effects = {
        { "morale", "$subject", 20, "crisis_accompanied" },
        { "relation", "$helper", "$subject", 6 },
        { "fact", "set", "char.$subject.crisis", "recovering" },
        { "deed", { verb = "rescue", target = "$subject", target_kind = "teammate", magnitude = 0.7 } },
      } },
    { text = "st.crisis_intervene.comfort_item",
      when = { "has_item", "coffee", 1 },
      effects = {
        { "item", "-", "coffee", 1 },
        { "morale", "$subject", 10, "crisis_comfort" },
        { "relation", "$helper", "$subject", 2 },
        { "schedule", "crisis_breakdown_warning", { after_days = { 2, 3 }, bind = { subject = "$subject" } } },
      } },
    { text = "st.crisis_intervene.let_go",
      effects = {
        { "leave", "$subject", { reason = "crisis", keeps_items = false } },
        { "deed", { verb = "abandon", target = "$subject", target_kind = "teammate", magnitude = 0.6 } },
      } },
  },
}
```

```
st.crisis_intervene.body       $subject 已经两天没怎么说话，今天夜里也没有进屋。$helper 在门口坐了很久，最后进去，在旁边坐下。
st.crisis_intervene.body_soft  $subject 今晚很不好。$helper 一直陪着，没有离开。
st.crisis_intervene.stay_night 陪到天亮。
st.crisis_intervene.comfort_item 递过去一杯热咖啡。
st.crisis_intervene.let_go     让他/她自己决定。
```
（处理说明：不描写手段与细节；"温和叙述"开启时 `body` 使用 `_soft` 版本，且预警片段只写"情绪很低"；两种版本结果相同。）

**(3) `kilo_slot_decision`**（哨站庇护名额决定，含四个分支）

```lua
return {
  id = "kilo_slot_decision",
  slot = "dusk",
  tier = "arc",
  when = { "all",
    { "fact", "kilo.stage", ">=", 2 },
    { "fact", "kilo.stage", "<=", 3 },
    { "day_between", 21, 27 },
    { "fact", "kilo.shelter", "=", "none" },
    { "rep", "kilo", ">=", -19 },
  },
  cast = { marsh = { "npc", "npc.marsh" }, pike = { "npc", "npc.pike" } },
  text = "st.kilo_slot_decision.body",
  choices = {
    { text = "st.kilo_slot_decision.accept_partial",
      effects = {
        { "fact", "set", "kilo.shelter", "partial" },
        { "fact", "set", "kilo.stage", 3 },
        { "schedule", "kilo_betrayal", { after_days = { 1, 1 } } },   -- kilo_betrayal 自身条件检查 kilo.line="sgt" 且 gift_given
      } },
    { text = "st.kilo_slot_decision.pay_extra",
      when = { "has_item", "fuel_any", 4 },                          -- 数值由 CONTENT 决定
      effects = {
        { "item", "-", "fuel_any", 4 },
        { "fact", "add", "kilo.slots_paid_extra", 1 },
        { "goto", "kilo_slot_decision" },
      } },
    { text = "st.kilo_slot_decision.expose_pike",
      when = { "all", { "fact", "kilo.pike_leverage", "=", true }, { "fact", "kilo.lt_trust", ">=", 40 } },
      effects = {
        { "deed", { verb = "inform", target = "npc.pike", target_kind = "soldier", magnitude = 0.6 } },
        { "fact", "set", "kilo.pike_removed", true },
        { "fact", "set", "kilo.line", "lt" },
        { "fact", "add", "kilo.slots", 1 },
        { "rep", "kilo", 12 },
        { "goto", "kilo_slot_decision" },                            -- 揭发后继续在名额界面做决定
      } },
    { text = "st.kilo_slot_decision.gift_pike",
      when = { "all", { "fact", "kilo.line", "=", "sgt" }, { "has_item", "whiskey", 2 } },
      effects = {
        { "item", "-", "whiskey", 2 },
        { "fact", "set", "kilo.gift_given", true },
        { "fact", "set", "kilo.shelter", "partial" },                -- 未触发翻脸则可进入地下结局
        { "fact", "set", "kilo.stage", 3 },
        { "schedule", "kilo_betrayal", { after_days = { 1, 1 } } },
      } },
    { text = "st.kilo_slot_decision.stay_home",
      effects = {
        { "fact", "set", "kilo.shelter", "none" },
        { "fact", "set", "kilo.stage", 4 },
      } },
  },
}
```

```
st.kilo_slot_decision.body           马什把名单摊在桌上，用铅笔点着空行："名额就这么多，你们自己挑谁进掩体，我只管登记。"门边，派克正拧开行军壶喝了一口。
st.kilo_slot_decision.accept_partial 按现有名额，让选定的人入内。
st.kilo_slot_decision.pay_extra      再塞四桶油，多换一个名额。
st.kilo_slot_decision.expose_pike    把派克的货单拍在桌上。
st.kilo_slot_decision.gift_pike      把两瓶酒递给派克。
st.kilo_slot_decision.stay_home      不进了，回家守着。
```

---

## 11. 结局与尾声

### 11.1 判定

结局在第 30 天结算（`ending.kind`），优先级：南行（若已出发）> 地下（若已入内）> 守住家 > 失败。

| 结局 | 判定事实 | 变体条件（`ending.variant`） |
|---|---|---|
| **守住家 hold_home** | `day ≥ 28` 仍在家，`team.size ≥ 1`，`home.heat_ok` | `warm`：`home.fortified` 且 `home.condition ≥ 2`；`bare`：房屋破损；`neighbors`：`loc.elder_house.attitude ≥ +2` 与 `loc.suburb_house.attitude ≥ +2`（邻里存活）；`watch`：`arc.dale.stage = 3` 且 dale 存活；`standing`：`arc.walt.stage = 3` 且 walt 存活（房子站着） |
| **地下 underground** | `kilo.shelter ∈ {full, partial}` 且 day ≥ 28 | `lt`：`kilo.line="lt"`；`sgt`：`kilo.line="sgt"`；`full`：全员入内；`partial`：未入内者留下（尾声另写）；`betrayed`：`kilo.betrayed`，改为失败或"回家守"；`expose`：`kilo.pike_removed` |
| **南行 south** | `day ≥ 25`，`car.fixed`，`car.fuel ≥` 所需（由 CONTENT 定），玩家选择出发 | `all`：全员同行；`split`：留下若干人（`team.size` 与同行人数之差）；`alone`：仅 1 人；`pursued`：`raiders.vendetta ≥ 3` 或 `rep.kilo ≤ -60` |
| **失败 fail** | `team.size = 0`（全员死亡或离队） | `froze`：死于寒潮；`scattered`：全员离队；`fell`：被敌人杀死 |

> **南行入口补充**：车辆位于自家车库/后院（开局损坏，作为家园固定可修设施；修车件 220 VP、汽油 40 L，见 `PLAN §10 C8`）。当 `day ≥ 25` 且 `car.fixed`、`car.fuel` 达标时，黄昏阶段解锁 `south_depart` 确认片段（选出发则直接进入 `south` 结局）。

"回顾"屏列出：`deeds.helped`、`deeds.harmed`、`deeds.kills_civilian`、住户的 `npc.<id>.fate`（因你而死 / 因你而活）。

### 11.2 逐角色尾声

每名**在场**的角色在结局时得到 `epilogue.<char>`；规则优先级自上而下，首条命中者生效。通用规则（对所有角色）：

| 优先级 | 条件 | 标签 | 内容方向 |
|---|---|---|---|
| 1 | 该角色在结局前已死亡 | `died` | 一块木牌、一句遗言（walt：做给孩子的木板；grace：一张证词） |
| 2 | 该角色已 `leave`（崩溃出走） | `left` | 去向不明，留下一样东西 |
| 3 | 该角色心理状态 ≥ 低落，或 `flag.<char>.crisis` | `shaken` | 沉默的尾声 |
| 4 | 该角色线 `arc.<char>.stage = 3` | `fulfilled` | 个人线的圆满收束（见下表） |
| 5 | 其余 | `survived` | 通用：活下来，各自继续 |

个人线收束（`fulfilled` 时的变体选择，条件用事实键）：

| 角色 | 变体与条件 |
|---|---|
| marcus | 修好暖气（`arc.marcus.flag=stayed`）/ 离队寻妻（选 B 随哨站走） |
| elena | `救人者`：`deeds.helped ≥ deeds.harmed × 2`；`沉默者`：两者接近；`离开者`：`deeds.harmed` 显著大于 helped |
| junho | `一桌人`：线 3 做了晚餐；`只剩酒`：未做且 `char.junho.addict ≥ 2` |
| linwei | `听见了`：线 3 确认日期且结局为守家；`没有回应`：`radio_hobbs_silent` 未处理 |
| dale | `守夜人`：线 3 同意；`出走`：未同意 |
| tasha | `跑向南方`：线 3 选 A 且结局为南行；`烧了的纸`：选 B |
| walt | `房子站着`：线 3 支持且守家结局；`木牌`：已死 |
| priya | `全员入内`：线 3 选 A，`kilo.shelter="full"`；`账本`：`inform` 次数 ≥ 2 且 civilians 恶名高 |
| sam | `敲门`：线 2 选 A；`备用钥匙`：线 1 选 B 且未修复 |
| grace | `证词`：线 3 选 A；`沉默`：线 3 选 B；`被带走`：`kilo.line="sgt"` 且未揭发派克 |

---

## 12. 裁决结果（见 PLAN §10）

范围修订（2026-11-14）见 PLAN §10.6；R2、R6 已被 S5、S4 取代。

| # | 问题 | 涉及文档 | 本文做法 / 建议 |
|---|---|---|---|
| R1 | NARRATIVE §2.7 条件/效果 DSL 参数形式未完全规定（`char`、`morale`、`relation`、`rep`、`fact` 的参数顺序；`die` 的延迟参数；`rel.<a>.<b>` 派生事实；`fn` 的注册名 `kilo_resolve_sgt`；`pick_char` 的 `prefer`/`not_self`/`relation_to` 选项） | NARRATIVE §2.7、§2.9 | 本文 §0 给出一套形式，需 M8 确认或改写；若改动，请通知 M10 批量修改 <br>→ 裁决：PLAN §10 W1，同意：以 WORLD 给出的 DSL 参数形式为准，M8 实现并写进 lint |
| R2 | 价值观增至 **5 个维度**（新增 `honesty`），NARRATIVE 示例仅有 4 个 | NARRATIVE §2.4 | 需要 `confess/return_goods/trade_cheat/betray` 的权重维度；不接受则把 honesty 折叠入 order，§2.2 权重表需重算 <br>→ 裁决：PLAN §10 W2，同意：价值观为五维 `compassion, loyalty, pragmatism, order, honesty`（已被 §10.6 S5 取代） |
| R3 | 特质乘数（elena ×1.4、tasha 杀人 ×2）在公式外 | NARRATIVE §2.4 | 作为角色特质乘数，写入 `data/characters.lua`；若 NARRATIVE 无对应字段，需补充 <br>→ 裁决：PLAN §10 W3，同意：特质乘数在公式结果之后再乘，NARRATIVE §2.4 补"× 特质系数" |
| R4 | 声望档位统一为 −100..+100 与五档；NARRATIVE 只提到 `rep` | NARRATIVE §2.7、GDD §1.7 | 沿用；若 CONTENT 有不同量纲需统一 <br>→ 裁决：PLAN §10 W4，同意：声望 −100..+100，五档 |
| R5 | 哨站开放时间：GDD 说"第 2 幕（11–20）开放"，本文设 day ≥ 11；庇护决定设 day ≥ 21，到达日 day 27 | GDD §1.2、§1.11 | 保持一致；若想让第 3 幕前完成 stage 2，需放宽 <br>→ 裁决：PLAN §10 W5，同意：第 11 天开放，第 21 天决定庇护，第 27 天入住 |
| R6 | 首批 40 片段中角色线仅覆盖 6 段（grace_1、junho_1、marcus_1、tasha_3、sam_2、priya_3）；其余 34 段角色线（共 40 段）留给 M10 | PLAN M10 | 按 §3 的表写 <br>→ 裁决：PLAN §10 W6，同意：首批 40 片段只覆盖 6 段角色线，其余 34 段 M10 补齐（已被 §10.6 S4 取代） |
| R7 | NPC 数量 23（范围修订后为 19，见 §4.0）；`npc.hendry_*` 只在变体住宅 B 出现，`npc.miller_*` 在变体 A | GDD §1.8 | 世界生成时三选一户；若需固定共存，扩大住户数 <br>→ 裁决：PLAN §10 W7，同意：郊区住宅两户住户按住宅变体三选一 |
| R8 | D14：`crisis_*` 以文字离屏处理，提供 `text_soft` 变体；"温和叙述"设置键由 UI 文档定名 | PLAN D14、UI-UX | 本文以 `soft_narration` 暂称 <br>→ 裁决：PLAN §10 W8，设置键定名 `soft_narration`（布尔，默认关闭），片段可选字段 `text_soft` |
| R9 | 南行结局的所需燃料与修车任务未在本文展开（属 CONTENT / 配方） | GDD §1.12 | 本文仅用事实 `car.fixed`、`car.fuel` 接口 <br>→ 裁决：PLAN §10 W9，修车与南行燃料用 CONTENT 的数值（C8），事实键沿用 `car.fixed`、`car.fuel` |
| R10 | 角色 `grace` 在队时，"哨站入口"之一为引荐；若 grace 不在队，stage 1 只能经巡逻或短波 | GDD §1.11 | 已按此设计；需 M10 在条件里检查 grace 是否在队 <br>→ 裁决：PLAN §10 W10，同意：grace 不在队时只能经巡逻队或短波接触哨站 |
