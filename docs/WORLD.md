# 世界、人物与首批故事内容 v1

本文是 `NARRATIVE.md`（机制）与 `GDD.md`（玩法）之上的**内容设计**：人物、地点、势力、哨站主线、事实键、反应规则与首批 40 个故事片段。M8（叙事引擎）和 M10（内容铺量）的实现者据此写 `data/characters.lua`、`data/values.lua`、`data/factions.lua`、`data/locations/*.lua`、`data/storylets/*.lua`、`data/reactors/*.lua`，不需再做设计决定。所有人物、地名、机构名均为原创（PLAN D13）。自杀、抑郁相关内容遵循 PLAN D14（见 §3.0 与 §10 `crisis_*`）。

## 0. 约定

- 物品只用类别标签（`food_any fuel_any med_any luxury_any parts_any weapon_any ammo_any`）或规范 id（`canned_beans bottled_water firewood gasoline propane scrap components antibiotics painkillers bandage coffee whiskey cigarettes book lockpick crowbar handgun handgun_ammo radio_parts heater_parts winter_coat`）。
- 引用 CONTENT 数值时只写名称和方向（如"修理耗时 ×0.7"）；具体数值由 CONTENT 定。
- 时间单位：路程用**游戏分钟**（D7：现实 1 秒 = 游戏 1 分钟）。夜晚共 480 分钟，往返耗时从中扣除。
- DSL 参数形式（NARRATIVE §2.7 未给全，本文按以下形式书写，见 §12 裁决 R1）：
  条件 `{"fact",key,op,val}`、`{"has_item",id,n}`、`{"rep",faction,op,val}`、`{"char",who,"has_trait",t}`、`{"char",who,"state_at_least",s}`（s ∈ steady/shaken/low/depressed/broken）、`{"npc_alive",id}`、`{"deed_exists",{verb=,target=,within_days=,loc=}}`、`{"day_between",a,b}`、`{"phase",p}`、`{"chance",p}`；
  效果 `{"fact","set"|"add",key,val}`、`{"item","+"|"-",id,n}`、`{"morale",who,delta,reason_key}`、`{"rep",faction,delta}`、`{"relation",a,b,delta}`、`{"wound",who,level}`、`{"deed",{...}}`、`{"schedule",id,{after_days={a,b},bind={...}}}`。
- 角色 id：`marcus elena junho linwei dale tasha walt priya sam grace`。NPC id：`npc.<name>`。片段 id 用 snake_case；i18n 键 `st.<片段id>.<字段>`。
- 角色线片段 id：`arc_<char>_<n>`（n = 1..4），推进规则 `arc.<char>.stage`：0 → 1 → … → 4，完成第 n 段后 stage = n。

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

### 2.1 五个维度（`data/values.lua`，取值 0..1）

| 维度 | 键 | 含义 |
|---|---|---|
| 同情 | `compassion` | 对他人痛苦的敏感度；越高，伤害弱者越难受，帮助别人越慰藉 |
| 忠诚 | `loyalty` | 对"自己人"（队友、家）的责任感；越高，抛弃/出卖队友越难受，为团队弄到物资越慰藉 |
| 务实 | `pragmatism` | 以生存结果为准；越高，对"拿到东西"越宽容，对"白白付出"与"留目击者"反而不安 |
| 秩序 | `order` | 对规则、财产、法度的尊重；越高，偷抢本身越难受（与受害者是谁无关） |
| 诚实 | `honesty` | 对欺骗、赖账、出卖的反感；越高，说谎与背信越难受，坦白、归还越慰藉 |

### 2.2 行为权重表（`data/values.lua: weights`）

公式（NARRATIVE §2.4）：`影响 = Σ_标签( Σ_维度 权重 × 角色价值观 ) × magnitude × 参与系数`。负 = 压力条目，正 = 慰藉条目。一次行为的权重 = **动词基线 + 其 tags 中为真者的行**。列顺序：同情 / 忠诚 / 务实 / 秩序 / 诚实。

**动词基线**

| verb | 同情 | 忠诚 | 务实 | 秩序 | 诚实 |
|---|---|---|---|---|---|
| steal | 0 | 0 | +3 | −4 | −2 |
| rob | −4 | 0 | +2 | −6 | −3 |
| assault | −8 | 0 | 0 | −5 | 0 |
| knockout | −4 | 0 | 0 | −3 | 0 |
| kill | −4 | 0 | 0 | −2 | 0 |
| spare | +4 | 0 | −1 | +1 | 0 |
| help / give | +6 | +1 | −2 | 0 | 0 |
| rescue | +6 | +4 | −1 | 0 | 0 |
| trade_fair | 0 | 0 | +1 | +1 | +1 |
| trade_cheat | −1 | 0 | +2 | −1 | −5 |
| refuse_help | −5 | 0 | +2 | 0 | 0 |
| abandon | −6 | −8 | 0 | −2 | −2 |
| betray | −4 | −10 | 0 | −3 | −8 |
| bury | +4 | +1 | 0 | +3 | 0 |
| confess | +3 | 0 | −2 | +2 | +8 |
| return_goods | +5 | 0 | −3 | +3 | +4 |
| inform | −1 | −3 | +1 | +3 | 0 |

**标签附加行**

| tag | 同情 | 忠诚 | 务实 | 秩序 | 诚实 | 说明 |
|---|---|---|---|---|---|---|
| occupied | −3 | 0 | 0 | −2 | 0 | 有人住的地方（空屋无此项） |
| victim_vulnerable | −6 | 0 | 0 | 0 | −1 | 老人、孩子、病人、孕妇 |
| victim_child | −8 | 0 | 0 | −2 | 0 | 对象是未成年人（与上一行叠加） |
| took_essentials | −4 | 0 | 0 | 0 | 0 | 拿走的是对方的最后存粮/药/燃料 |
| lethal | −6 | 0 | 0 | −3 | 0 | 造成死亡（kill 之外的间接致死也算） |
| armed_threat | −3 | 0 | 0 | −3 | 0 | 持械威吓 |
| witnessed | 0 | 0 | −2 | −1 | 0 | 有活着的目击者（务实者怕后患） |
| silenced | −8 | 0 | −3 | −3 | −4 | 为灭口而杀/打晕目击者 |
| target_raider | +6 | 0 | +2 | +2 | 0 | 对象是掠夺者（部分抵消负面） |
| target_soldier | 0 | 0 | −2 | −4 | 0 | 对象是哨站士兵（后患大） |
| self_defense | +6 | 0 | +1 | +3 | 0 | 对方先动手 |
| for_team | 0 | +3 | +3 | 0 | 0 | 这件事是为了团队生存 |
| helped_stranger | +3 | 0 | −1 | 0 | 0 | 帮助与己无关的人 |
| cost_paid | +2 | 0 | 0 | 0 | 0 | 帮助时自己付出了关键物资 |
| lied | 0 | 0 | +1 | 0 | −4 | 说谎获利 |
| victim_teammate | −2 | −6 | 0 | −2 | −3 | 对象是队友 |

特质修正（在公式外，作为乘数，写在角色卡）：elena"良知极重"= 负向影响 ×1.4；tasha"杀人创伤"= 动词 kill 的负向 ×2 并附加一条长期压力；其余角色无乘数。

### 2.3 三个算例（同一行为、不同角色）

行为：sam 撬开米勒家夜里偷窃（NARRATIVE §2.4 样例）：`verb=steal, occupied, victim_vulnerable, took_essentials, witnessed(露丝看见), magnitude=0.6`。小队 sam + tasha，elena 与 dale 留守家中（参与系数 0.6）。

权重合计 = steal + occupied + victim_vulnerable + took_essentials + witnessed：同情 −13、忠诚 0、务实 +1、秩序 −7、诚实 −3。

| 角色 | 价值观（同/忠/务/秩/诚） | Σ 权重×价值观 | × magnitude 0.6 | × 参与系数 | 影响 |
|---|---|---|---|---|---|
| elena | .95 / .5 / .2 / .7 / .8 | −12.35 + 0.2 − 4.9 − 2.4 = −19.45 | −11.67 | 0.6（留守） | **−7.0**（×1.4 特质 → −9.8） |
| dale | .3 / .8 / .8 / .4 / .4 | −3.9 + 0.8 − 2.8 − 1.2 = −7.1 | −4.26 | 0.6（留守） | **−2.6** |
| sam | .5 / .6 / .8 / .1 / .5 | −6.5 + 0.8 − 0.7 − 1.5 = −7.9 | −4.74 | 1.5（亲手） | **−7.1** |

读法：elena 只是听说就重创，且之后会对 sam 的好感下降（见反应 `psy_relation_shift`）；dale 几乎无感；sam 动手的本人受的压力和留守的 elena 差不多，因为他对秩序几乎无负担。若换成 elena 亲手做同一件事，影响为 −17.5（×1.4 → −24.5），这就是不能指派她下手的原因。

---

## 3. 幸存者角色卡

### 3.0 通用规则

- **价值观**顺序：同情 / 忠诚 / 务实 / 秩序 / 诚实。
- **关系初值**：同队开局默认 0；表中给"倾向"（+ 亲近 / − 疏远），由 `data/characters.lua: relation_bias` 实现，幅度 ±5..±15。
- **危机统一写法**：崩溃时的文本一律离屏、不写手段（D14）。`crisis_*` 片段带 `soft_narration` 开关：开启时只写"他/她离开了/再没说话"；关闭时仍然只写文字、不写方式与细节，只多一句明确的心境描述。
- **角色线启动条件**：除另写外，该角色在队中且 `day ≥ 3`，tension 不处于高位。同一时刻最多一个角色线片段在池中排队。
- 每条线的"影响"写作：心理 / 关系 / 结局。

### 3.1 marcus — 马库斯·黑尔 Marcus Hale（40 岁）

- **小传**：哈洛瀑布高中的暖通维修工，兼修教堂和县政府的锅炉。妻子在寒潮第二个月随岳母南逃，之后再无消息。他抽了二十年烟，到现在还留着三个月前囤的最后几包，不肯给任何人看。修东西时话很少，一旦东西修好，他会连续说上十分钟它是怎么坏的。他相信所有东西都能修，所以对"修不了"的事——比如人——格外烦躁。
- **价值观**：.5 / .7 / .6 / .5 / .5
- **特长**：修理加热器与加湿器耗时 ×0.7，零件消耗 ↓。**缺点**：烟瘾，缺烟时每日有持续压力条目；有烟时一支即慰藉。
- **关系倾向**：与 walt +10（同行手艺人）、与 dale −5（嫌吵）。
- **台词**：偷窃——"空屋的东西，拿；有人的，别碰，我们不缺到那份上。"杀人——"我修了半辈子东西，没修过这个。"帮助——"拿去，反正我这儿修不了的就是人心。"

| 段 | 触发 | 梗概 | 选择与走向 | 影响 |
|---|---|---|---|---|
| 1 `arc_marcus_1` | 在队，day≥3，cigarettes 存量 ≤ 3 | 他半夜蹲在后院，手里是最后一包烟 | A 递给他一件慰藉品（coffee）→ 他开口谈妻子；B 不理 → 他把烟藏得更深，stage 仍推进，flag `marcus.hides_smokes` | A：关系+、心理+；B：心理−，后续可能偷抽烟 |
| 2 `arc_marcus_2` | stage=1，heater 损毁一次或第 1 次小寒潮后 | 他发现县政府地下锅炉间的图纸在哨站手里 | A 主动去哨站接触（解锁 `kilo.stage=1` 路线，契合哨站主线）；B 拒绝 | A：开启军士/中尉任一线；B：他变得沉默，关系−（想帮忙的心被拒） |
| 3 `arc_marcus_3` | stage=2，day≥14，cigarettes=0 | 戒断到极点，他在修加热器时手抖，差点酿成火灾 | A 拿 cigarettes 或 whiskey 换他稳定（依赖加深）；B 让 elena 陪他熬（需 elena 在队）；C 让他休息 1 天 | A：心理+、`addict.marcus`+；B：关系+、心理渐复；C：全队少一个修理工 |
| 4 `arc_marcus_4` | stage=3，day≥22 | 他决定把最后的家当（锅炉图纸/零件）献给全队的避寒方案 | A 全队留守：解锁避寒小间零件加成；B 随哨站走（需 kilo.stage≥3） | 结局：守家变体"有人修好了暖气"；或地下变体 |

- **崩溃表现**：离开去找妻子的路，留下一张写着"锅炉维护要点"的纸。若不挽留，尾声为"没人知道他走到了哪"。

### 3.2 elena — 埃琳娜·鲁伊斯 Elena Ruiz（34 岁）

- **小传**：哈洛瀑布县医院急诊护士，寒潮前一周才刚值完第 14 个连续夜班。医院断电后她在走廊里给 40 多个人分过最后的药，然后看着其中大半在三周内死去。她不信"这是没办法的事"，所以在队里总是第一个问"那家人有没有吃的"。同时她也是最先知道代价的人：她算得出一瓶抗生素能救几个人、不能救几个人。
- **价值观**：.95 / .5 / .2 / .7 / .8
- **特长**：治疗效果 ↑，用药 ↓（消耗 ×0.7）。**缺点**：良知极重，团队伤害他人时心理重创（负向 ×1.4），崩溃阈值低。
- **关系倾向**：与 grace +10（同为医护）、与 priya −10、与 sam −5。
- **台词**：偷窃——"他们也在数罐头，一天一个一天一个。"杀人——"别告诉我'没办法'，我听了半年了。"帮助——"我来，你们别走开。"

| 段 | 触发 | 梗概 | 选择与走向 | 影响 |
|---|---|---|---|---|
| 1 `arc_elena_1` | day≥3，队中有人受伤 | 她在清点药品时发现自己写在手背上的日期停在了医院停电那天 | A 让她主导救治一名受伤队友 → 她稳住；B 把药留给自己人，不救外人 | A：心理+；B：flag `elena.rationed`，后续不参与"救外人" |
| 2 `arc_elena_2` | stage=1，`deed_exists{verb=refuse_help}` 或 day≥10 | 邻居孩子发烧（联动 `neighbor_plea_sick_child`），她请求拿出抗生素 | A 给（抗生素 −）→ 孩子活；B 拒绝 → 她冷淡 | A：关系+、尾声线"救人者"；B：心理−−、关系− |
| 3 `arc_elena_3` | stage=2，队伍有 `lethal` 行为 | 她拒绝与动手者同桌吃饭 | A 动手者道歉并归还/坦白 → 修复；B 解释"必要"，她沉默；C 让她离队 | A：关系回升；B：心理持续−；C：`leave` 触发 `crisis_runaway` 变体 |
| 4 `arc_elena_4` | stage=3，day≥22 | 临近大寒潮她问：我们救下的人和我们害死的人，谁多？ | 回顾 `facts: deeds.helped` vs `deeds.harmed` | 决定她的尾声：救人者 / 沉默者 / 离开者 |

- **崩溃表现**：先停止进食和说话，两天后拒绝再给任何人治疗，最终走出去"看看还有谁需要"。可由 grace、tasha 谈话挽回。

### 3.3 junho — 박준호 Jun-ho Park（45 岁，朴俊浩）

- **小传**：主街韩式小馆"东门"的主厨，来美国 22 年，妻子和女儿在首尔（寒潮后通讯中断）。他会用三只罐头和一把干香料做出让人想哭的汤。他喝酒，一开始是为了睡着，后来是为了不去想女儿现在多大。他对自己的厨艺很骄傲，不肯把食物当成"补给"，坚持"吃饭要有桌子"。
- **价值观**：.6 / .6 / .5 / .3 / .5
- **特长**：烹饪产出 ↑，燃料与水耗 ↓。**缺点**：酒精依赖，无酒时心理渐降；饮酒过量时白天工作变慢。
- **关系倾向**：与 tasha +10（像女儿）、与 priya −5。
- **台词**：偷窃——"饿的时候谁管桌子。但别偷到人家锅里。"杀人——"我杀过鱼，不杀人。"帮助——"坐下，先喝汤。"

| 段 | 触发 | 梗概 | 选择与走向 | 影响 |
|---|---|---|---|---|
| 1 `arc_junho_1` | day≥3，有热食 | 他坚持晚餐必须在桌上吃，叫所有人落座 | A 全员落座 → 慰藉（全队心理+）；B 嫌浪费时间 | A：全队+、他心理+；B：他沉默、关系− |
| 2 `arc_junho_2` | stage=1，whiskey 存量 ≥1 且 day≥8 | 他半夜翻出酒，把瓶口对着厨房窗口 | A 没收酒；B 陪他喝一杯；C 假装没看见 | A：依赖−、关系−；B：依赖+、关系+；C：flag `junho.drinks` |
| 3 `arc_junho_3` | stage=2，day≥14，`food_any` 紧缺 | 邻居老太太闻到汤味上门，他想分一碗 | A 同意：食物−、`give`，邻里态度+；B 拒绝 → 他沉默 | A：他心理+，`loc.elder_house.attitude`+；B：心理−、flag |
| 4 `arc_junho_4` | stage=3，day≥22 | 大寒潮前夜，他想给所有人做一顿"像样的饭" | 需要 food_any ≥6、fuel_any ≥2，消耗大 | 做了：全队心理大幅+，尾声"一桌人"；没做：尾声"只剩酒" |

- **崩溃表现**：醉到不再说话，把自己锁在厨房。队友可以进去陪坐。不会离队，会拒绝一切烹饪。

### 3.4 linwei — 林薇 Lin Wei（26 岁）

- **小传**：明大（本地州立大学分校）电子工程研究生，在寒潮时正在做一块低功耗短波收发模块的毕设。导师在第二个月南下，她没跟上，因为怕冷。她身体弱，打架不行，最大的武器是耐心。她每晚用手摇发电机的电给自己的小收音机听两分钟，只为确认"世界还在"。
- **价值观**：.6 / .5 / .6 / .6 / .7
- **特长**：无线电与电器制作更快，预报更准（预报提前量 ↑）。**缺点**：体弱畏寒（体温下降更快），近战差。
- **关系倾向**：与 marcus +5、与 walt +5、与 dale −5。
- **台词**：偷窃——"空屋行，有人的我真的做不到。"杀人——"信号再差，我也不想听到那个声音。"帮助——"我这边能不能做个东西给你们？"

| 段 | 触发 | 梗概 | 选择与走向 | 影响 |
|---|---|---|---|---|
| 1 `arc_linwei_1` | day≥3，有 radio_parts 或 components | 她修好收音机，抓到"哈洛夜班"（Hobbs）的广播 | A 让她每晚收听；B 把电留给加热器 | A：心理+、解锁广播片段；B：关系− |
| 2 `arc_linwei_2` | stage=1，radio.level≥2 | 她从噪声里解出一串有规律的脉冲，来自南山电台塔 | A 派人去塔（`unlock_loc radio_tower`）；B 只记录 | A：新地点；B：线索留在 `rumor.tower` |
| 3 `arc_linwei_3` | stage=2，day≥14，`kilo.stage≥1` | 她认出哨站短波的加密方式，可以窃听 | A 窃听 → `kilo.pike_leverage` 的线索；B 不碰 | A：军士线把柄、关系±；B：中立 |
| 4 `arc_linwei_4` | stage=3，day≥22 | 她算出大寒潮的确切日期（预报准确度 ↑） | 全局 `cold.big_day` 提前一天确认 | 守家结局变体：有无线电预警 |

- **崩溃表现**：关掉收音机，不再说话。若体温危急，会"留在窗边听"而不进屋。不会主动离队。

### 3.5 dale — 戴尔·科瓦尔斯基 Dale Kowalski（62 岁）

- **小传**：退休长途卡车司机，周末在县里猎鹿。老婆五年前过世，女儿在西海岸，通信断了。他认定"人比鹿难对付"，对陌生人一律先端枪。他嗓门大，爱对着别人的做法指指点点，其实是怕自己一个人。他对"在路上被丢下的人"有说不清的怨气，因为年轻时自己被老板扔在过路旁。
- **价值观**：.3 / .8 / .8 / .4 / .4
- **特长**：远程武器、陷阱更强，负重 ↑。**缺点**：暴躁，交易容易谈崩；心情差时拖累同屋人的心理。
- **关系倾向**：与 grace +5（同为"前线人"）、与 priya −10、与 tasha +5。
- **台词**：偷窃——"拿，谁让他们不先拿出来分。"杀人——"枪响了就别装没响。"帮助——"……行，进来。别碰我的椅子。"

| 段 | 触发 | 梗概 | 选择与走向 | 影响 |
|---|---|---|---|---|
| 1 `arc_dale_1` | day≥3，有 weapon_any | 他在院子里架陷阱，教 tasha 认脚印 | A 让 tasha 跟着学 → 技能与关系+；B 要她去干别的 | A：双方关系+；B：他暴躁事件概率↑ |
| 2 `arc_dale_2` | stage=1，day≥10 | 他在路上认出一个被他以前的车队"丢下"的老司机（npc.olaf 的旧识） | A 让他带路回河边；B 他拒绝回忆 | A：解锁 river_dock 线索；B：心情− |
| 3 `arc_dale_3` | stage=2，`deed_exists{verb in abandon, refuse_help}` 在队中发生 | 有队友在途中丢下了某人，他当场发作 | A 让他发火（他心理+、关系−）；B 劝他（grace/elena 在队时可行） | 影响：全队凝聚；他可能单独离队 |
| 4 `arc_dale_4` | stage=3，day≥22 | 他提出"最后一个晚上，我守" | A 同意：他守夜，守住家时尾声强；B 不同意，他闷头离开 | 结局：守家变体"有人守夜" |

- **崩溃表现**：对队友破口大骂，然后拿着枪独自出走，在雪地里"找鹿"。可谈话拉回，成功率看关系值。

### 3.6 tasha — 塔莎·布鲁克斯 Tasha Brooks（17 岁）

- **小传**：哈洛瀑布高中田径队，800 米州级决赛选手，寒潮时刚拿到大学试训通知。父母在第三个月因一氧化碳中毒去世，她一个人带着弟弟（已走失）在邻里间换食物。她跑得快，所以总是被派去传话和探路；她不说，但每次听见有人说"孩子别去"都会气得发抖。
- **价值观**：.8 / .6 / .2 / .4 / .7
- **特长**：移动速度 ↑，脚步噪音 ↓。**缺点**：负重低；杀人会留下严重创伤（kill 负向 ×2，长期压力条目）。
- **关系倾向**：与 junho +10、与 grace +5、与 sam −5（觉得他危险）。
- **台词**：偷窃——"我偷过。那天我哭了。"杀人——"别让我再看见，求你们。"帮助——"我帮他背，没事，我跑得快。"

| 段 | 触发 | 梗概 | 选择与走向 | 影响 |
|---|---|---|---|---|
| 1 `arc_tasha_1` | day≥3 | 她在雪地里捡到一个小孩的手套，一直带着 | A 让她留着；B 劝她扔 | A：心理+；B：关系− |
| 2 `arc_tasha_2` | stage=1，day≥9 | 弟弟的下落线索：有人在 river_dock 见过一个小男孩 | A 派她去找（需有人陪同）；B 阻止 | A：解锁 river_dock 线索，可能找到弟弟（`rumor.tasha_brother` 三分支）；B：关系−−，心理− |
| 3 `arc_tasha_3` | stage=2，队伍在她面前发生 `kill` | 她第一次目睹死亡 | A 全队停下陪她一晚；B 命令继续行动 | A：心理缓冲、关系+；B：她可能崩溃 |
| 4 `arc_tasha_4` | stage=3，day≥22 | 试训通知书被她烧了取暖，或交给队友 | A 劝她留着：尾声"跑向南方"；B 烧 | 结局：南行/守家变体 |

- **崩溃表现**：连续两天不说话，蜷在最小的一间屋，不会主动离队；队友谈话成功率高。

### 3.7 walt — 沃尔特·雷耶斯 Walter Reyes（68 岁）

- **小传**：退休木匠，做了 40 年的橱柜和屋架，把妻子留下的那间老屋做成了镇上最结实的房子之一。他心脏不好，药只剩半瓶。他把"盖房子"当成唯一值得操心的事：房子立得住，人就有可能活。他看到年轻人偷东西时不骂，只会问一句"你妈知道吗"。
- **价值观**：.7 / .6 / .3 / .9 / .8
- **特长**：建造与加固更省料、更快。**缺点**：年迈，行动慢，易生病。
- **关系倾向**：与 marcus +10、与 tasha +10、与 sam −5。
- **台词**：偷窃——"拿不属于你的东西，手会记住。"杀人——"我为盖房子活了一辈子，不想为拆别人的房子死。"帮助——"我这把年纪，也没什么给不起的。"

| 段 | 触发 | 梗概 | 选择与走向 | 影响 |
|---|---|---|---|---|
| 1 `arc_walt_1` | day≥3 | 他想把整个后墙重新钉一遍，需要 scrap 与 firewood | A 提供 → 防御+；B 拒绝 → 他自己做 | A：关系+；B：他体力−、患病概率+ |
| 2 `arc_walt_2` | stage=1，day≥9，有药品 | 他的心脏药快没了，他瞒着 | A 让 elena 检查并分药；B 他拒绝 | A：关系+，elena 参与；B：伏笔，day 15 后可能触发危机 |
| 3 `arc_walt_3` | stage=2，day≥15 | 他教 tasha 或 sam 做木工，说起自己年轻时的错 | A 让 sam 学（秩序转向）；B 教 tasha | A：sam 价值观 秩序 +0.1、关系+；B：tasha 关系+ |
| 4 `arc_walt_4` | stage=3，day≥22 | 他想用余下的木料做避寒小间，但需要全队出力 | A 全力支持：守家结局变体"房子站着"；B 不同意 | 结局：若 walt 存活则增强守家变体；若他在此前死亡，改为尾声里的一块木牌 |

- **崩溃表现**：不会"崩溃"，会"安静地病倒"，拒绝治疗；若病逝，全队有一条持久的压力条目。

### 3.8 priya — 普丽娅·奈尔 Priya Nair（38 岁）

- **小传**：哈洛瀑布最大的房产经纪人，卖过全镇 1/3 的房子，认识所有人的钱包与脾气。寒潮里她用"谁家还剩什么"的记忆换到了第一批罐头。她受不了脏、冷、饿，也受不了别人说她势利；但她是团队里唯一一个会认真算"这家人明天还剩几天粮"的人。
- **价值观**：.4 / .5 / .9 / .5 / .3
- **特长**：交易价更好，哨站交涉有加成。**缺点**：挑剔，挨饿受冻时心理下降更快。
- **关系倾向**：与 dale −10、与 elena −10、与 sam +5（同为"算计型"）。
- **台词**：偷窃——"最好挑那家有两份的。"杀人——"这笔账，我不愿意记。"帮助——"我不亏本地帮，但我帮。"

| 段 | 触发 | 梗概 | 选择与走向 | 影响 |
|---|---|---|---|---|
| 1 `arc_priya_1` | day≥3 | 她列出全镇住户清单（谁家有存粮） | A 采纳：解锁 3 户住户的初始情报；B 嫌这是出卖邻居 | A：`loc.*.known` 解锁，elena 关系−；B：关系− |
| 2 `arc_priya_2` | stage=1，day≥10 | 她在哨站交涉中认出中尉的前妻是她的客户 | A 利用关系：kilo.favor+；B 不用 | A：中尉线更顺，`rep.kilo`+；B：中立 |
| 3 `arc_priya_3` | stage=2，day≥16，tension 高 | 她提议"卖掉"一个住户的存粮位置给军士 | A 同意：`inform`、kilo.favor+、civilians 恶名风险；B 拒绝 | A：军士线推进；B：她心理− |
| 4 `arc_priya_4` | stage=3，day≥22 | 她拿出自己最后一件奢侈品（一枚戒指）换全员名额 | A 接受：`kilo.slots_paid_extra`+1；B 拒绝 | 结局：地下变体"全员入内" |

- **崩溃表现**：喋喋不休地列出损失，最后不再要求任何东西；有可能带着自己那份物资搬去教堂。

### 3.9 sam — 萨姆·奥尔蒂斯 Sam Ortiz（33 岁）

- **小传**：开了十二年锁匠铺，十八岁时因入室盗窃坐过两年牢，之后在镇上花了十五年证明自己。寒潮第一个月，全镇的人突然需要他开门，没人问他的过去；第三个月他开错了一扇门，里面有人。他不再提那件事。他知道队友多半不信他，所以会过度做事。
- **价值观**：.5 / .6 / .8 / .1 / .5
- **特长**：撬锁又快又静，潜行强。**缺点**：不被信任（队友关系起点低），绝境时可能偷团队物资。
- **关系倾向**：与 priya +5、与 walt −5、与 elena −5、与 tasha −5。
- **台词**：偷窃——"锁不是用来拦人的，是用来提醒你该敲门。"杀人——"我坐过牢，知道出来后的样子。"帮助——"我欠的，不止一扇门。"

| 段 | 触发 | 梗概 | 选择与走向 | 影响 |
|---|---|---|---|---|
| 1 `arc_sam_1` | day≥3 | 队友在清点物资时有人暗示"东西少了" | A 公开清点；B 偷偷查看 | A：关系±0、全队安心；B：sam 心理−、关系− |
| 2 `arc_sam_2` | stage=1，day≥10，食物紧缺 | 他在深夜站在储藏室门口，手里有一把钥匙 | A 夜里有人发现并劝他；B 无人发现，他取走一份物资（`steal`，target=teammate） | A：关系+；B：物资− 、flag `sam.stole_team`，之后如被发现，全队关系− |
| 3 `arc_sam_3` | stage=2，day≥16 | 他在一户人家门前认出"开错了的那扇门" | A 去敲门道歉（`confess`）；B 避开 | A：修复，心理+；B：压力条目长期存在 |
| 4 `arc_sam_4` | stage=3，day≥22 | 他提议潜入哨站仓库（夜袭线）并保证不会出事 | A 同意：夜袭副本；B 拒绝 | 结局：夜袭线（成功/失败）见 §7 |

- **崩溃表现**：偷走一份物资后离开，留下一把钥匙。若此前有修复行为（`confess`/`return_goods`），他会留下物资。

### 3.10 grace — 格蕾丝·奥卡福 Grace Okafor（31 岁）

- **小传**：基洛哨站的战地医护兵（Corporal），在清理县北公路事故时被迫参与处决一名搭便车的平民，当晚逃出哨站。她的右肩有旧枪伤。她在镇上有认识的人，也有想杀她的人。她睡眠极浅，夜里常自己起来站在窗前。
- **价值观**：.6 / .9 / .5 / .6 / .6
- **特长**：近战与枪械强；认识哨站的人（专属路线：`kilo.stage` 入口之一）。**缺点**：创伤后应激，枪声下可能僵住；夜里噩梦（睡眠恢复 ↓）。
- **关系倾向**：与 elena +10、与 dale +5、与 priya −5。
- **台词**：偷窃——"如果是我们的存粮被偷，我会开枪。你想好了再去。"杀人——"我不想再数这个数字了。"帮助——"别动，让我看看伤。"

| 段 | 触发 | 梗概 | 选择与走向 | 影响 |
|---|---|---|---|---|
| 1 `arc_grace_1` | 在队，day≥3 | 夜里窗外枪声（远处），她僵在床上（联动 `dream_grace_gunfire`） | A 有人陪她：心理缓冲；B 无人 | A：关系+；B：flag `grace.frozen` |
| 2 `arc_grace_2` | stage=1，day≥11（哨站开放） | 她在哨站巡逻队里认出旧同伴 | A 主动联络（`kilo.contact_via="grace"`，进入中尉线）；B 躲开 | A：哨站线；B：关系−、被通缉风险 |
| 3 `arc_grace_3` | stage=2，`kilo.stage≥1` | 派克军士认出她，要挟 | A 屈服：`kilo.pike_trust`+、她心理−；B 揭露派克：需把柄；C 杀人灭口 | 影响：军士线 / 夜袭线 / 她离队 |
| 4 `arc_grace_4` | stage=3，day≥22 | 她决定承认当年的处决，写下证词 | A 交给中尉：`kilo.lt_trust`+，中尉线完成；B 烧毁 | 结局：地下·中尉线/军士线 |

- **崩溃表现**：枪声下僵住，夜里连续噩梦后拒绝守夜；最终走回哨站"自首"。若被挽留，将与全队保持沉默。

---

## 4. 具名 NPC 与住户

每名 NPC 的字段：id、地点、身份、台词、个人物品（item_name，用于 §10 的受害者文本）、反应倾向、小模拟可能结局（NARRATIVE §2.5）。"态度"指 `loc.<id>.attitude`（−3 敌对 … 0 中立 … +3 友好）。

| id | 地点 | 身份 | 台词 | 个人物品 | 反应倾向 | 小模拟可能结局 |
|---|---|---|---|---|---|---|
| npc.miller_ruth | suburb_house | 露丝·米勒，58 岁寡妇，原学校食堂员工 | "你们要找就找，别碰我孙子的东西。" | 丈夫留下的猎刀 | 被偷：加强戒备（持刀开门）；被帮：回赠自制果酱；被抢：求救或报复 | 饿死 / 投靠教堂 / 送孙子去教堂后独居 / 被救助后成为朋友 |
| npc.miller_ben | suburb_house | 本，11 岁，露丝的孙子 | "你是不是 elena 那个队的？她给我糖。" | 一只缺角的玩具卡车 | 对外人怯，对友好者很快信任；见到暴力会哭 | 被送往教堂 / 随露丝饿死 / 被掠夺者收留（负面分支） |
| npc.hendry_carl | suburb_house（变体） | 卡尔·亨德里，44 岁，原保险理赔员，丧偶 | "我可以付钱，银行卡行吗？……开玩笑的。" | 公文包里的家庭保单 | 爱讲理；被偷：写告示；被帮：愿意做情报交换 | 投靠哨站告密 / 带女儿去教堂 / 因女儿病重上门乞讨 |
| npc.hendry_lily | suburb_house（变体） | 莉莉，7 岁，卡尔的女儿 | "爸爸说，会有人来的。" | 一本没读完的绘本 | 发烧高危；是 `neighbor_plea_sick_child` 的主角 | 病愈 / 病逝（触发 elena 线 2 的结果分支） |
| npc.halvorsen_edith | elder_house | 伊迪丝·霍尔沃森，81 岁，退休高中教师 | "你们这些孩子，进门先擦鞋。" | 一箱学生贺卡 | 对礼貌者开门；被偷：不报复但挨饿；被帮：教堂里有人带话 | 病逝 / 被送教堂 / 在你家过冬 / 尸体被发现 |
| npc.lindqvist | church | 卡琳·林德奎斯特，52 岁牧师，互助会负责人 | "你们的善恶不在我这儿记账，但这里的粮食在。" | 一本被翻烂的账本 | 收容恶名者但不给粮；按声望决定物资；告发者进黑名单 | 过劳病倒 / 把领导权交给 hollis / 维持到结局 |
| npc.hollis | church | 迪恩·霍利斯，63 岁执事，管仓库 | "不是我小气，一百二十张嘴等着。" | 仓库钥匙串 | 严格，要登记；对偷教堂零容忍；对帮手宽厚 | 接管教堂 / 为守粮开枪 / 因腐败被揭发 |
| npc.bea | church | 比阿，29 岁志愿护士，带着 4 个月的婴儿 | "你们那个 Elena，她是医生吗？" | 一只婴儿鞋 | 对医疗帮助极度感激；会向 elena 求药 | 婴儿夭折（若 med_any 不足）/ 与 elena 同行 |
| npc.odell | river_dock / trailer_market | 奥德尔，57 岁流动商贩，卡车改雪橇 | "雪橇比卡车好，因为没人想偷。" | 一只旧怀表 | 讲价；对被他讹过的人冷淡；会传话 | 被抢（若你放任）/ 持续交易 / 被掠夺者劫持 |
| npc.rourke | warehouse | 鲁克，46 岁，锯木厂工头，掠夺者头目 | "我不抢人，我收'保管费'。" | 一把电锯链条 | 被杀者复仇；被放过者记仇；可贿赂 | 被哨站击溃 / 被你击杀 / 与哨站交易 |
| npc.dot | warehouse | 多特，35 岁，副手，原卡车调度员 | "鲁克说了算，但我记账。" | 一本记着各据点存量的本子 | 理性，可交易情报；对暴力冷淡 | 取代鲁克 / 投靠哨站 / 逃走 |
| npc.finn | warehouse / construction_site | 芬，19 岁，最年轻的掠夺者，原锯木厂学徒 | "我不想杀人，真的。" | 一张母亲的照片 | 被放过则感激；被杀则全组仇恨 | 叛逃 / 被你招募（requires 放过 + 供食） / 死于混战 |
| npc.marsh | checkpoint_kilo | 伊芙琳·马什中尉，36 岁，国民警卫队后备军官 | "我需要的是理由，不是借口。" | 一枚被磨掉编号的军徽 | 守纪；对告发谨慎；看重守约；对腐败敏感 | 被军士架空 / 揭发军士 / 战死 / 与你合作 |
| npc.pike | checkpoint_kilo | 达恩·派克军士，42 岁，军需负责人 | "东西总会有人处理。我碰巧是那个人。" | 一只总装着威士忌的行军壶 | 喜欢交易；记仇；可被把柄控制；对 grace 有杀意 | 被中尉免职 / 被你的把柄反制 / 带货潜逃 |
| npc.ames | checkpoint_kilo | 艾姆斯列兵，19 岁，守门哨兵 | "别过线，求你们了，我不想开枪。" | 一张母亲的信（未寄出） | 同情，可放行；被责罚则怨恨；是内线 | 为你开门 / 因放行被处决 / 逃出哨站 |
| npc.gus | farm | 格斯·勃兰特，61 岁，农场主，丧偶 | "地冻成石头了，我在种什么？种希望。" | 一包去年留的种子 | 用药物与燃料换粮；对掠夺者警惕 | 守农场 / 病倒 / 把种子交给教堂 |
| npc.nell | farm | 内尔，58 岁，格斯的妹妹，糖尿病 | "我不是要钱，我要的是那一小瓶。" | 一瓶即将用完的胰岛素笔 | 对药物极度感激；缺药数日必有危机 | 病重（连锁 gus 求助）/ 病愈 / 病逝 |
| npc.shirin | motel | 席琳，44 岁，汽车旅馆经营者，情报贩子 | "我卖的不是房间，是别人不知道的事。" | 一本客人签到本 | 中立；只按物物交换给消息；可拿线索 | 关店 / 被掠夺者占领 / 与你长期合作 |
| npc.hobbs | radio_tower | 温德尔·霍布斯，70 岁，业余无线电爱好者，"哈洛夜班"广播员 | "今晚零下三十一，大家还在吗，回我一句。" | 一副磨破的耳机 | 隐居；对带来电池或零件的人非常热情 | 病逝 / 继续广播 / 被你救出 |
| npc.wren | clinic | 托拜厄斯·伦医生，67 岁，退休全科医生，留守诊所 | "药不是我的，是等药的人的。" | 听诊器 | 帮助伤者；对抢药者怒；对 elena 愿意传授 | 被抢药后崩溃 / 救治你的队友 / 病逝 |
| npc.garza | school | 加尔萨老师，33 岁，在学校收留 8 个孩子 | "他们都叫我'老师'，其实我是体育老师。" | 孩子们画的壁画 | 极度保护孩子；对男性外人警惕；对女性与医护友好 | 带孩子去教堂 / 被迫投靠掠夺者 / 孩子夭折 |
| npc.lowe | police_station | 洛威副警长，49 岁，留守的最后一名警察 | "你要的钥匙，需要我签字。" | 一枚被磨亮的警徽 | 讲法；放过只要有理由；告发需证据 | 被哨站征用 / 殉职 / 把枪交给你 |
| npc.olaf | river_dock | 奥拉夫，63 岁，冰钓者，夏天的渡口管理员 | "冰在响，别上去。" | 一把手摇钻 | 慷慨，用鱼换电池；与 dale 的旧识 | 淹没于冰窟 / 与你成为朋友 |

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
- **阈值与服务**：中立：可白天交换；友好：以优惠价换药品/柴火，可求助；盟友：可寄宿 1 名队员，或在大寒潮时借用避寒所；戒备：只能取一次食物；敌对：被赶走，且 hollis 会在夜里派人守门。
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
| church | 圣马可教堂 St. Mark's | 0 | 100 | 0 | 0 | 2 | 4 | lindqvist, hollis, bea |
| school | 北坡小学 North Hill Elementary | 30 | 60 | 0 | 10 | 2 | 3 | garza |
| clinic | 诊所 Falls Medical | 30 | 60 | 0 | 10 | 2 | 3 | wren |
| warehouse | 木材仓库 East Works Yard | 0 | 0 | 0 | 100 | 3 | 5 | rourke, dot, finn |
| farm | 勃兰特农场 Brandt Farm | 5 | 90 | 0 | 5 | 2 | 3 | gus, nell |
| radio_tower | 电台塔 South Ridge Tower | 40 | 60 | 0 | 0 | 2 | 3 | hobbs |
| motel | 河口汽车旅馆 Riverside Motel | 20 | 50 | 20 | 10 | 2 | 3 | shirin |
| trailer_market | 拖车营地集市 Flats Market | 0 | 20 | 70 | 10 | 2 | 3 | odell |
| construction_site | 未竟工地 Falls View Site | 50 | 0 | 0 | 50 | 2 | 3 | finn |
| police_station | 警察局 Harlow PD | 20 | 40 | 0 | 40 | 3 | 4 | lowe |
| river_dock | 河边码头 River Landing | 40 | 20 | 40 | 0 | 2 | 2 | olaf, odell |
| checkpoint_kilo | 基洛哨站 Checkpoint Kilo | 0 | 0 | 0 | 100（官方） | 2 | 5 | marsh, pike, ames |

备注：checkpoint_kilo 的"占用"固定为哨站，不随机；"敌对"指武装。warehouse 固定掠夺者。每局至少有一个超市/药房被"敌对/平民"占用，保证夜袭有对象（生成器校验）。

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
- 片段：`arc_walt_3`（若 walt 在队）；解锁：开局。

**church**
- 白天：互助会窗口：换物、登记、避寒；声望决定服务。
- 夜间：入口为钟楼侧门与地下室的通风口；hollis 巡夜，仓库在地下室，粮食量大但守卫最多。
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
 #G G G G G G.##    G 货架(粮仓)  H hollis 的值班桌在入口旁
```

**school**
- 白天：门口与 garza 交谈；孩子在窗口。
- 夜间：入口为体育馆侧门；garza 的警觉高，孩子们睡在体育馆；食堂有 `food_any`。
- 布局：A 一层；B 二层教室。
- 片段：`raid_found_dead_household`（若被毁）；解锁：第 4 天。

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
- 白天：olaf 在冰面钓鱼，可换鱼；商贩偶尔到访。
- 夜间：入口为码头栈桥；冰面的声音会传远；仓库有 `scrap`、`gasoline`（船用）。
- 布局：A 栈桥；B 带船库。
- 片段：`travel_frozen_stranger`；解锁：第 7 天。

**checkpoint_kilo**
- 白天：门口盘查，接触 marsh/ames/pike。
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
| 1 接触 | 1 | day ≥ 11 | **K1-a** 通过任意一个入口：路上被巡逻拦下（`kilo_patrol_stop`，`kilo.contact_via="patrol"`）/ 短波找到频率（`radio_kilo_frequency`，需 radio.level≥3，`"shortwave"`）/ grace 引荐（`arc_grace_2`，`"grace"`）。**K1-b** 在门口完成首次盘查（`kilo_marsh_meeting` 或 `kilo_pike_private_deal` 任一） | `kilo.met_marsh` 或 `kilo.met_pike` 为真 | `kilo.favor` +5；开放阶段 2 任务；中尉/军士各一次初始信任 |
| 2 证明价值 | 2 | stage=1 | **中尉线（L）**：L1 交付 fuel_any（`kilo.delivered_fuel`）；L2 救治哨站伤员（elena/grace 在场）；L3 修发电机（marcus 或 linwei；`kilo.generator_fixed`）；L4 夜间取回被掠夺者劫走的哨站物资（warehouse 副本）。**军士线（S）**：S1 交付 whiskey/cigarettes；S2 替派克运私货（`kilo.smuggle_runs`，夜间 travel 片段）；S3 告发邻居存粮（`inform`，每次 civilians −3）。**通用**：priya 交涉加成（kilo.favor ×1.2） | `kilo.favor ≥ 40` 且 `lt_trust ≥ 30` 或 `pike_trust ≥ 30` | 按较高者设 `kilo.line = "lt" / "sgt"`；两者都 ≥ 30 且玩家未选，默认 "lt" |
| 3 庇护资格 | 3 | day ≥ 21 且 stage=2 | **M1** `kilo_slot_decision`（黄昏）：展示名额 `kilo.slots`，并按线分支。**M2** 决定谁入内、谁留下，付"代价包"换额外名额。**M3** 军士线：`kilo_betrayal` 判定；中尉线：马什验证（需 lt_trust ≥ 60） | 选定名单并在大寒潮前一天（day=27）到达哨站，或被出卖 | `kilo.shelter` = "full" / "partial" / "none" / "betrayed" |
| 4 结果 | 4 | day≥28 | 大寒潮期间庇护生效 | — | 结局见 §11 |

### 7.2 分支

| 分支 | 触发 | 流程 | 结果事实 |
|---|---|---|---|
| **中尉线** | `lt_trust ≥ 60`，`pike_trust < 60` 或 `pike_leverage` 为真 | 马什按"理由"审核：`kilo.slots` = 2 + 1（lt 线奖励）。若 grace 写下证词（`arc_grace_4` 选 A）或有揭发派克的证据，再 +1。付 priya/物资的"代价包"可再 +1（每包一名，最多全员） | `kilo.slots` ∈ 2..全员；`kilo.line="lt"` |
| **军士线** | `pike_trust ≥ 60` | 派克承诺名额，要求"礼物"（whiskey/gasoline）。**除非 `kilo.pike_leverage` 为真**，否则 `kilo_betrayal` 以 60% 概率触发：收了东西翻脸、关门；有把柄则派克无法翻脸 | `kilo.line="sgt"`；`kilo.betrayed` 可能为真 |
| **夜袭仓库** | stage≥1 且 `arc_sam_4` 选 A，或 `kilo.stage=3` 且名额谈崩 | 全游戏最难副本：军需仓与通讯室。成功：取得大量 `fuel_any/med_any/ammo_any`；失败：死伤、被通缉 | `kilo.line="raid"`；`kilo.raid_done`；`kilo.raid_result` ∈ success/fail；`rep.kilo` ≤ −60，不可再取得庇护 |
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
| `cold.big_day` | N | 大寒潮首日（28..30）；linwei 线 4 可确认 |
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
| `arc.<char>.stage` | N | 0..4，角色线进度，char ∈ 十人 |
| `arc.<char>.flag` | S | 该线的分支标记（如 `marcus.hides_smokes`） |
| `char.<id>.addict` | N | 0..3 依赖等级（marcus / junho） |
| `char.<id>.crisis` | S | none / warned / broken / recovering，危机进度 |
| `rel.<a>.<b>` | N | −100..100，a 对 b 的关系值（派生，条件里可读） |
| `food_days_home` | N | 家中存粮可撑天数（派生） |
| `kilo.gift_given` | B | 已向派克送礼 |
| `loc.<id>.state` | S | unknown / known / visited / hostile / empty / friendly / burned |
| `loc.<id>.unlocked` | B | 是否已开放 |
| `loc.<id>.occ` | S | empty / civilian / trader / hostile（占用状态） |
| `loc.<id>.layout` | N | 布局模板编号 |
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

---

## 9. 反应规则目录（25 条）

按 NARRATIVE §2.4 的格式。`$loc`、`$target`、`$actor` 为行为里的绑定。心理族规则的 `psy_generic` 对**每条** deed 都执行；其余在其基础上附加。

### 9.1 心理族（`data/reactors/psyche.lua`）

| id | 匹配条件 | 效果 |
|---|---|---|
| `psy_generic` | 任意 deed | 对每个在队角色按 §2.2 公式计算影响；负 → `psyche.add_stress(char, "deed:<id>", -v, decay=slow)`；正 → 慰藉条目；生成该角色台词 |
| `psy_relation_shift` | 任意 deed，对角色 C 的影响 ≤ −6 且 actor≠C | `relation(C, actor, -ceil(|v|/4))`；影响 ≥ +6 则 `+ceil(v/4)` |
| `psy_tasha_kill` | verb=kill，actor=tasha 或 tasha 在场 | tasha 增加长期压力条目 `kill_trauma`（decay=very_slow）；影响 ×2 |
| `psy_repair_return` | verb=return_goods / confess | 清除或减半同一 `target` 的既有压力条目（−50%）；`deeds.repaired`+1 |
| `psy_bury` | verb=bury | 对 target 死亡相关的压力条目 −30%；全队慰藉 +（按 compassion） |
| `psy_refuse_echo` | verb=refuse_help，tags.victim_child 或 victim_vulnerable | `schedule("dream_victim_returns", after_days={1,3})`（对 compassion ≥ 0.6 的角色） |
| `psy_silenced` | tags.silenced | 动手者与同行者额外长期压力；`schedule("dream_victim_returns", ...)` |
| `psy_comfort_help` | verb ∈ help/give/rescue，tags.cost_paid | 动手者 `morale(+)`，原因键 `helped_with_cost`；队友 `relation +1` |
| `psy_teammate_death` | verb=die 且 target_kind=teammate | 全队按 loyalty 加压力条目（−3..−12）；与死者关系 ≥ +20 者加倍；`flag.<char>.mourning` |

### 9.2 社会族（`data/reactors/social.lua`）

| id | 匹配条件 | 效果 |
|---|---|---|
| `soc_witness_spread` | 有 `witnesses` 且 target_kind=civilian | 该地点知道（`rumor.known_<id>=loc`）；`schedule("rumor_to_faction", {after_days={1,3}})`；之后 `town` |
| `soc_steal_occupied_seen` | verb=steal，occupied，witnessed | `rep(civilians, -3)`；`loc.$loc.attitude -1` |
| `soc_rob_notoriety` | verb ∈ rob/assault，有 witnesses | `rep(civilians, -8)`；`rep(st_mark, -4)`；`rumor.notoriety +8` |
| `soc_kill_civilian` | verb=kill，target_kind=civilian | `rep(civilians, -25)`；`rep(st_mark, -20)`；`deeds.kills_civilian +1`；`schedule("kilo_asks_about_victim")`（若有活着的目击者） |
| `soc_kill_raider` | verb=kill，target_kind=raider | `rep(raiders, -20)`；`raiders.vendetta +1`；`rep(kilo, +3)`（若 witnessed 为 soldier） |
| `soc_help_stranger` | verb ∈ help/give/rescue，target_kind=civilian | `rep(civilians, +4)`；`loc.$loc.attitude +1`；`deeds.helped +1` |
| `soc_trade_cheat` | verb=trade_cheat | `rep(traders, -10)`；`rumor.traders_avoid` 若累计 ≥ 2 |
| `soc_inform_kilo` | verb=inform | `kilo.favor +4`；`kilo.informed_on` 追加；`rep(civilians, -3)`；若受害者幸存，`schedule("informed_on_revenge", {after_days={2,4}})` |
| `soc_betray_teammate` | verb=betray，target_kind=teammate | 全队对 actor 关系 −10；`flag.<actor>.betrayer` |

### 9.3 世界族（`data/reactors/world.lua`）

| id | 匹配条件 | 效果 |
|---|---|---|
| `robbed_household_starves` | verb ∈ steal/rob，occupied，took_essentials | `loc_add($loc, food_days, -3)`；`schedule("beggar_at_door", {after_days={2,4}, bind={victim="$target"}})` |
| `world_guard_up` | verb ∈ steal/rob，occupied | `loc_add($loc, guard, +1)`；`loc_state($loc, "alert")` |
| `world_defect_to_raiders` | `loc.$loc.food_days ≤ 0` 且 `loc.$loc.attitude ≤ -2` 且 `raiders.strength ≥ 1` | `chance 0.3`：`loc_state($loc, "empty")`，`raiders.strength +1`，`schedule("revenge_party", {after_days={3,5}})` |
| `world_survivor_flees` | verb ∈ rob/assault/kill，有 `witnesses` 存活 | 幸存者 `npc.<id>.status="fled"`，`loc` 改为 church 或 checkpoint_kilo；`schedule("survivor_flees_to_church")` |
| `world_empty_house_squatter` | `loc.$loc.members_alive == 0` 且 `loc.$loc.state="empty"` | 每日 `chance 0.1`：`loc.$loc.occ ← raiders 或 civilian` |
| `world_friend_gift` | `loc.$loc.attitude ≥ +2`（交易或帮助累计 ≥ 2） | `schedule("gift_from_friendly_household", {after_days={2,4}})` |
| `world_burial_closure` | verb=bury | 对 `$loc` 邻居 `attitude +1`；`rep(st_mark, +2)` |
| `world_unwitnessed_kill` | verb=kill，无 witnesses | 不触发传播；`schedule("body_found", {after_days={3,5}, bind={loc="$loc"}})`，找到后 `loc.$loc.state="empty"` |
| `world_return_reset` | verb=return_goods | `loc.$loc.attitude +2`（上限 0 → 若原为 −3 则恢复至 −1）；移除 `loc_state alert` |

---

## 10. 首批 40 个故事片段

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
| 18 | `arc_grace_1` | dream | A | grace 在队，stage=0，day≥3 | 远处枪声，她僵在床上（`dream_grace_gunfire`） | 陪伴（`talk`，关系+）/ 让她独自（flag `grace.frozen`） | 1,5 |
| 19 | `arc_junho_1` | talk | A | junho 在队，有热食，stage=0 | 他要求全队"在桌上吃饭" | 落座（全队 `morale +`）/ 嫌浪费（关系−） | 5,8 |
| 20 | `arc_marcus_1` | talk | A | `item cigarettes ≤ 3`，stage=0 | 马库斯夜里蹲在后院，手里是最后一包烟 | 递 coffee（谈话）/ 不理（flag `marcus.hides_smokes`） | 1,7 |
| 21 | `talk_judges_deed` | talk | M | 最近 3 天有 `psy_generic` 影响 ≤ −8 的 deed | 队友对最近的行为有评价，数值不显示，用台词表现 | 道歉 / 辩解 / 沉默；`relation` ±、`psy_repair` 入口 | 5,8 |
| 22 | `arc_tasha_3` | talk | A | `arc.tasha.stage = 2`，tasha 刚目睹 `kill` | 她第一次目睹死亡 | 停下陪她一晚 / 继续行动（可能导致崩溃） | 2,5,7 |
| 23 | `arc_sam_2` | home_idle | A | sam 在队，`arc.sam.stage = 1`，食物紧缺 | 深夜他站在储藏室门口，手里是一把钥匙 | 有人劝 / 无人 → 取走物资（`steal`，target teammate，`flag sam.stole_team`） | 2,5 |
| 24 | `arc_priya_3` | talk | A | `arc.priya.stage = 2`，`kilo.stage ≥ 2` | 普丽娅提议把某户存粮位置"卖给"派克 | 同意（`inform`，`kilo.favor +`）/ 拒绝 | 2,3,5 |
| 25 | `crisis_breakdown_warning` | crisis | S | 任意角色进入"低落" 后至少 1 天 | 预警：他/她不再说话、不再进食（必先于崩溃） | 给予慰藉品 / 谈话 / 休息；`morale` 缓冲 | 8 |
| 26 | `crisis_runaway` | crisis | S | 崩溃，未被干预 | 角色离队或带物资出走；留下一句话 | 追（`rescue` 窗口）/ 放走（`leave`） | 2,8 |
| 27 | `crisis_intervene` | crisis | S | 崩溃，且 `relation(helper, subject) ≥ 15` 或有慰藉品 | 全程离屏文字；队友陪伴过夜，成功则回到"低落" | 见 §10.2 完整 Lua；带"温和叙述"文本 | 8,5 |
| 28 | `trader_odell_arrives` | door_day | M | `trader.next_day ≤ day`，`rep traders > -60` | 奥德尔的雪橇停在门口；这一天可以交易 | 交易（`trade_fair`）/ 讨价 / 赶走 | 3,4 |
| 29 | `trader_wounded_courier` | door_day | M | day 9–22，`rep traders ≥ -20` | 受伤的信使倒在门口，货在他背上 | 救治（elena 加成）/ 抢货（`rob`）/ 报给教堂（见 §10.2） | 2,3,4 |
| 30 | `kilo_patrol_stop` | travel | M | `day ≥ 11`，`kilo.stage = 1`，`contact_via` 未设 | 巡逻队拦下，艾姆斯验你的东西 | 配合（`kilo.contact_via="patrol"`）/ 贿赂 / 逃跑 | 1,3 |
| 31 | `kilo_marsh_meeting` | raid_enter | A | `kilo.stage = 1`，`kilo.met_marsh = false` | 马什：我需要理由，不是借口 | 交付 fuel_any（`lt_trust +5`）/ 提 grace / 拒绝 | 2,5 |
| 32 | `kilo_pike_private_deal` | raid_enter | A | `kilo.stage = 1`，`kilo.met_pike = false` | 派克私下：有些东西"总会有人处理" | 接私货（`smuggle_runs +1`，`pike_trust +5`）/ 拒绝 | 2,3 |
| 33 | `kilo_slot_decision` | dusk | A | `kilo.stage = 2..3`，day ≥ 21，`kilo.shelter = "none"` | 名额公布；每个人名字都要被念出来 | 见 §10.2 完整 Lua | 1,2,4 |
| 34 | `kilo_betrayal` | dawn | S | `kilo.gift_given`，`kilo.line = "sgt"` | 到约定日，门口是另一个班的岗哨 | `fn kilo_resolve_sgt`：无把柄 60% 翻脸；有把柄则放行 | 6,3 |
| 35 | `raid_found_hidden_cellar` | raid_found | M | 平民占用地点，`chance 0.25` | 地窖里躲着一家人，手里握着木棍 | 退出（`spare`）/ 夺走存粮（`rob`）/ 留下食物（`give`） | 2,3,7 |
| 36 | `raid_found_dead_household` | raid_found | M | `loc.$loc.members_alive = 0`，day≥8 | 一屋已冻死的住户，一本日记写着他们是谁 | 埋葬（`bury`）/ 拿走 food_any / 读日记（线索） | 7,8 |
| 37 | `raid_found_ledger` | raid_found | A | warehouse，`kilo.stage ≥ 1`，无 `pike_leverage` | 货单上有派克的签名与哨站编号 | 拿走（`kilo.pike_leverage=true`）/ 放回 | 3,6 |
| 38 | `raid_enter_wakes_child` | raid_enter | M | 有 `victim_child` 的住户 | 孩子半夜醒了，眼睛睁得很大 | 低声安慰（`knockout` 之外的选项：`help`）/ 迅速离开 / 威吓（`armed_threat`） | 2,7 |
| 39 | `travel_frozen_stranger` | travel | M | day≥5，`chance 0.15` | 路边一个人快冻僵了，背着一个小包 | 救人（`rescue`，花 bandage 或 coffee）/ 过去 / 拿走小包 | 2,4,8 |
| 40 | `travel_raider_toll` | travel | M | `raiders.strength ≥ 1`，day≥9 | 掠夺者设卡收"过路费" | 付 food_any / 动手（`kill` 风险）/ 绕路（多耗 30 分钟） | 3,6 |

补充：`body_found`（`world_unwitnessed_kill`）、`rumor_to_faction`（系统任务，非玩家可见片段）、`revenge_party` 的结果变体不计入 40，由 M10 实现。

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
st.neighbor_plea_sick_child.body   卡尔·亨德里在门口，没敢敲门，雪落在他的肩上。"莉莉烧了两天了。我知道你们有药，我不要多，一次剂量就行。我会还，拿什么还都行。" 他身后的屋子里有一盏很小的灯。
st.neighbor_plea_sick_child.give   把抗生素递给他。（你们自己的药少了一份）
st.neighbor_plea_sick_child.trade_info   给他一点别的药，换他知道的消息。
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
  gate = true,
  when = { "all",
    { "fact", "kilo.stage", ">=", 2 },
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
        { "schedule", "kilo_betrayal", { after_days = { 1, 1 } } },   -- 仅当 kilo.line="sgt" 且 gift_given 时才会显示
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
      } },
    { text = "st.kilo_slot_decision.gift_pike",
      when = { "all", { "fact", "kilo.line", "=", "sgt" }, { "has_item", "whiskey", 2 } },
      effects = {
        { "item", "-", "whiskey", 2 },
        { "fact", "set", "kilo.gift_given", true },
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
st.kilo_slot_decision.body           马什把名单摊在桌上："名额有限，我不能替你们决定谁进去。但我必须写下名字。"门口，派克在擦他的行军壶。
st.kilo_slot_decision.accept_partial 按现有名额，部分人入内。
st.kilo_slot_decision.pay_extra      再付一份代价，换多一个名额。
st.kilo_slot_decision.expose_pike    把派克的货单放在桌上。
st.kilo_slot_decision.gift_pike      把酒递给派克。
st.kilo_slot_decision.stay_home      不进去，回家守。
```

---

## 11. 结局与尾声

### 11.1 判定

结局在第 30 天结算（`ending.kind`），优先级：南行（若已出发）> 地下（若已入内）> 守住家 > 失败。

| 结局 | 判定事实 | 变体条件（`ending.variant`） |
|---|---|---|
| **守住家 hold_home** | `day ≥ 28` 仍在家，`team.size ≥ 1`，`home.heat_ok` | `warm`：`home.fortified` 且 `home.condition ≥ 2`；`bare`：房屋破损；`neighbors`：`loc.elder_house.attitude ≥ +2` 与 `loc.suburb_house.attitude ≥ +2`（邻里存活）；`watch`：`arc.dale.stage = 4` 且 dale 存活；`standing`：`arc.walt.stage = 4` 且 walt 存活（房子站着） |
| **地下 underground** | `kilo.shelter ∈ {full, partial}` 且 day ≥ 28 | `lt`：`kilo.line="lt"`；`sgt`：`kilo.line="sgt"`；`full`：全员入内；`partial`：未入内者留下（尾声另写）；`betrayed`：`kilo.betrayed`，改为失败或"回家守"；`expose`：`kilo.pike_removed` |
| **南行 south** | `day ≥ 25`，`car.fixed`，`car.fuel ≥` 所需（由 CONTENT 定），玩家选择出发 | `all`：全员同行；`split`：留下若干人（`team.size` 与同行人数之差）；`alone`：仅 1 人；`pursued`：`raiders.vendetta ≥ 3` 或 `rep.kilo ≤ -60` |
| **失败 fail** | `team.size = 0`（全员死亡或离队） | `froze`：死于寒潮；`scattered`：全员离队；`fell`：被敌人杀死 |

"回顾"屏列出：`deeds.helped`、`deeds.harmed`、`deeds.kills_civilian`、住户的 `npc.<id>.fate`（因你而死 / 因你而活）。

### 11.2 逐角色尾声

每名**在场**的角色在结局时得到 `epilogue.<char>`；规则优先级自上而下，首条命中者生效。通用规则（对所有角色）：

| 优先级 | 条件 | 标签 | 内容方向 |
|---|---|---|---|
| 1 | 该角色在结局前已死亡 | `died` | 一块木牌、一句遗言（walt：做给孩子的木板；grace：一张证词） |
| 2 | 该角色已 `leave`（崩溃出走） | `left` | 去向不明，留下一样东西 |
| 3 | 该角色心理状态 ≥ 低落，或 `flag.<char>.crisis` | `shaken` | 沉默的尾声 |
| 4 | 该角色线 `arc.<char>.stage = 4` | `fulfilled` | 个人线的圆满收束（见下表） |
| 5 | 其余 | `survived` | 通用：活下来，各自继续 |

个人线收束（`fulfilled` 时的变体选择，条件用事实键）：

| 角色 | 变体与条件 |
|---|---|
| marcus | 修好暖气（`arc.marcus.flag=stayed`）/ 离队寻妻（选 B 随哨站走） |
| elena | `救人者`：`deeds.helped ≥ deeds.harmed × 2`；`沉默者`：两者接近；`离开者`：`deeds.harmed` 显著大于 helped |
| junho | `一桌人`：线 4 做了晚餐；`只剩酒`：未做且 `char.junho.addict ≥ 2` |
| linwei | `听见了`：线 4 确认日期且结局为守家；`没有回应`：`radio_hobbs_silent` 未处理 |
| dale | `守夜人`：线 4 同意；`出走`：未同意 |
| tasha | `跑向南方`：线 4 选 A 且结局为南行；`烧了的纸`：选 B |
| walt | `房子站着`：线 4 支持且守家结局；`木牌`：已死 |
| priya | `全员入内`：线 4 选 A，`kilo.shelter="full"`；`账本`：`inform` 次数 ≥ 2 且 civilians 恶名高 |
| sam | `敲门`：线 3 选 A；`备用钥匙`：线 2 选 B 且未修复 |
| grace | `证词`：线 4 选 A；`沉默`：线 4 选 B；`被带走`：`kilo.line="sgt"` 且未揭发派克 |

---

## 12. 裁决结果（见 PLAN §10）

| # | 问题 | 涉及文档 | 本文做法 / 建议 |
|---|---|---|---|
| R1 | NARRATIVE §2.7 条件/效果 DSL 参数形式未完全规定（`char`、`morale`、`relation`、`rep`、`fact` 的参数顺序；`die` 的延迟参数；`rel.<a>.<b>` 派生事实；`fn` 的注册名 `kilo_resolve_sgt`；`pick_char` 的 `prefer`/`not_self`/`relation_to` 选项） | NARRATIVE §2.7、§2.9 | 本文 §0 给出一套形式，需 M8 确认或改写；若改动，请通知 M10 批量修改 <br>→ 裁决：PLAN §10 W1，同意：以 WORLD 给出的 DSL 参数形式为准，M8 实现并写进 lint |
| R2 | 价值观增至 **5 个维度**（新增 `honesty`），NARRATIVE 示例仅有 4 个 | NARRATIVE §2.4 | 需要 `confess/return_goods/trade_cheat/betray` 的权重维度；不接受则把 honesty 折叠入 order，§2.2 权重表需重算 <br>→ 裁决：PLAN §10 W2，同意：价值观为五维 `compassion, loyalty, pragmatism, order, honesty` |
| R3 | 特质乘数（elena ×1.4、tasha 杀人 ×2）在公式外 | NARRATIVE §2.4 | 作为角色特质乘数，写入 `data/characters.lua`；若 NARRATIVE 无对应字段，需补充 <br>→ 裁决：PLAN §10 W3，同意：特质乘数在公式结果之后再乘，NARRATIVE §2.4 补"× 特质系数" |
| R4 | 声望档位统一为 −100..+100 与五档；NARRATIVE 只提到 `rep` | NARRATIVE §2.7、GDD §1.7 | 沿用；若 CONTENT 有不同量纲需统一 <br>→ 裁决：PLAN §10 W4，同意：声望 −100..+100，五档 |
| R5 | 哨站开放时间：GDD 说"第 2 幕（11–20）开放"，本文设 day ≥ 11；庇护决定设 day ≥ 21，到达日 day 27 | GDD §1.2、§1.11 | 保持一致；若想让第 3 幕前完成 stage 2，需放宽 <br>→ 裁决：PLAN §10 W5，同意：第 11 天开放，第 21 天决定庇护，第 27 天入住 |
| R6 | 首批 40 片段中角色线仅覆盖 6 段（grace_1、junho_1、marcus_1、tasha_3、sam_2、priya_3）；其余 34 段角色线（共 40 段）留给 M10 | PLAN M10 | 按 §3 的表写 <br>→ 裁决：PLAN §10 W6，同意：首批 40 片段只覆盖 6 段角色线，其余 34 段 M10 补齐 |
| R7 | NPC 数量 23；`npc.hendry_*` 只在变体住宅 B 出现，`npc.miller_*` 在变体 A | GDD §1.8 | 世界生成时三选一户；若需固定共存，扩大住户数 <br>→ 裁决：PLAN §10 W7，同意：郊区住宅两户住户按住宅变体三选一 |
| R8 | D14：`crisis_*` 以文字离屏处理，提供 `text_soft` 变体；"温和叙述"设置键由 UI 文档定名 | PLAN D14、UI-UX | 本文以 `soft_narration` 暂称 <br>→ 裁决：PLAN §10 W8，设置键定名 `soft_narration`（布尔，默认关闭），片段可选字段 `text_soft` |
| R9 | 南行结局的所需燃料与修车任务未在本文展开（属 CONTENT / 配方） | GDD §1.12 | 本文仅用事实 `car.fixed`、`car.fuel` 接口 <br>→ 裁决：PLAN §10 W9，修车与南行燃料用 CONTENT 的数值（C8），事实键沿用 `car.fixed`、`car.fuel` |
| R10 | 角色 `grace` 在队时，"哨站入口"之一为引荐；若 grace 不在队，stage 1 只能经巡逻或短波 | GDD §1.11 | 已按此设计；需 M10 在条件里检查 grace 是否在队 <br>→ 裁决：PLAN §10 W10，同意：grace 不在队时只能经巡逻队或短波接触哨站 |
