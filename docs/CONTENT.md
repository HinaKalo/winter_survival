# 内容与数值目录 v1

《零下三十 / Thirty Below / 영하 삼십》（暂名）。本文是 `assets/scripts/data/*.lua` 的数值出处，读者是 M3（模拟核心）与 M10（内容与平衡）的实现者。核心决策见 `PLAN.md §0`，玩法见 `GDD.md`，叙事 DSL 见 `NARRATIVE.md`，地点与 NPC 见 `WORLD.md`。

**所有数值都是"初始值，M10 用批量模拟调优"**，每个数字后面给一句推导理由，调优时先看理由是否仍成立。本文给出的推演（§6.2 算例、§10）是手算的设计推演，不是实测。

文件对应关系：

| 章节 | 落地文件 |
|---|---|
| §2 物品 | `data/items.lua` |
| §3 配方 | `data/recipes.lua` |
| §4 科技、§5 设施 | `data/tech.lua`、`data/homes/*.lua` 的设施表 |
| §6、§7 | `data/balance.lua`、`data/weather.lua` |
| §8 | `data/values.lua`（物价部分）、`data/traders.lua` |
| §9 | `data/loot.lua` |

---

## 1. 约定

### 1.1 id 与单位

| 项 | 规则 |
|---|---|
| id | 英文 snake_case，全局唯一；物品 id 与配方 id、科技 id、设施 id 各自独立命名空间 |
| 前缀 | 科技节点 `t_*`；配方 `r_*`（本文表中省略前缀，落表时补 `r_`）；设施 `f_*`；图纸 `bp_<节点名去掉 t_>`，如 `bp_insulation_2` 对应 `t_insulation_2`；天气事件 `snap_*` |
| 时间 | 游戏分钟（整数）。模型步长 1 分钟（PLAN D10）；现实 1 秒 = 游戏 1 分钟（D7） |
| 温度 | °C，浮点，存档保留 1 位小数 |
| 重量 | kg；背包与储物按重量加格数双限制 |
| 能量 | 热能用 W（功率）与 kWh；1 kWh = 3 价值点（见 §8.1 的锚点） |
| 价值点 | VP，浮点；全游戏唯一的"货币"尺度，只用于估价与预算，**不是货币**（GDD §1.7 无货币） |
| 属性 | 饱食、水分、体温、精力、心理均 0–100，越高越好；`hp` 0–100 是隐藏值，只通过伤势三级显示（§6.5） |
| 人·天 | 一个人一天的最低消耗；食物 1 人·天 = 90 饱食点 = 30 VP（§10） |

### 1.2 物品主类与类别标签

每件物品有一个**主类**（`cat`）和若干**标签**（`tags`）。DSL 里的 `food_any` 等是标签，按标签匹配时对队伍与家园储物区的**合计数量**求值（NARRATIVE §2.7 的 `{ "has_item", "food_any", 2 }`）。

| 标签 | 含义 | 包含的物品 |
|---|---|---|
| `food_any` | **可直接食用**（罐头、熟食、芽菜、烟熏肉） | canned_beans, canned_soup, canned_meat, canned_fruit, cooked_meal, stew, sprouts, smoked_meat |
| `food_raw` | 生食材，可吃但有中毒风险；**不计入** `food_any` | raw_meat, raw_fish, rat_meat, wild_roots |
| `food_ingredient` | 需加工的原料，不可直接吃 | dried_rice, sugar, salt |
| `water_any` | 可直接饮用的水 | bottled_water, clean_water（snow_water 不算） |
| `fuel_any` | 任意燃料 | firewood, coal, gasoline, propane |
| `heat_fuel` | 灶与柴火炉可烧的 | firewood, coal |
| `med_any` | 医药（不含剧情药） | bandage, antibiotics, painkillers, cold_medicine, antiseptic, first_aid_kit |
| `luxury_any` | 奢侈品 | coffee, instant_coffee, chicory_coffee, whiskey, moonshine, cigarettes, book, chocolate |
| `alcohol_any` | 酒（依赖机制用） | whiskey, moonshine |
| `parts_any` | 通用材料与专用零件（不含汽车件） | scrap, components, electronics, cloth, insulation, planks, nails, rope, duct_tape, wire, pipe, heater_parts, humidifier_parts, radio_parts, generator_parts, battery, filter_cartridge |
| `tool_any` | 工具 | lockpick, crowbar, shovel, flashlight, hammer, hand_saw, toolbox, multimeter, binoculars |
| `weapon_any` | 武器 | knife, bat, axe, crowbar, handgun, shotgun, hunting_rifle |
| `melee_any` / `gun_any` | 近战 / 枪械 | knife, bat, axe, crowbar / handgun, shotgun, hunting_rifle |
| `ammo_any` | 弹药 | handgun_ammo, shotgun_shells, rifle_ammo |
| `wear_any` | 穿戴 | winter_coat, winter_coat_2, wool_hat, wool_gloves, snow_boots |
| `car_part` | 修车件 | car_parts, car_battery, tire |
| `blueprint_any` | 图纸 | bp_* |

DSL 用法与扣除规则（`sim/inventory.lua` 实现）：

- `{ "has_item", "food_any", 2 }`：队伍背包 + 家园储物区里该标签数量之和 ≥ 2。
- `{ "item", "-", "food_any", 2 }`：按"**VP 最低者优先、已变质者优先**"扣除，所以玩家被剧情"征收"时先交走便宜货；需要指定具体物品时直接写规范 id。
- 条件里写规范 id 与写标签同样合法；`lint.run()` 校验标签与 id 是否存在。
- 一件物品可带多个标签（crowbar 同属 `tool_any`、`weapon_any`、`melee_any`）。

### 1.3 载重与堆叠

| 项 | 数值 | 理由 |
|---|---|---|
| 基础载重 | 15 kg；基础格数 10 | 一晚搜刮要有取舍：约 1.5 天的全队罐头就满了 |
| 角色修正 | tasha 11 kg；dale 20 kg；walt 12 kg；linwei 13 kg；其余 15 kg | 呼应 GDD §1.4 的负重高/低 |
| backpack_small / large | +4 kg +6 格 / +10 kg +14 格 | 大包让"带两个人去"的收益不再是唯一的扩容途径 |
| sled | 户外 +20 kg，速度 ×0.9；进入建筑前须留在入口 | 只能给"搬运型"地点（仓库、农场）加成 |
| 超重 | 负重 > 载重时，移速 ×(1 − 0.5 × 超出比例)，上限惩罚 ×0.5；> 130% 不能走动 | 软惩罚到硬上限 |
| 家园储物 | 基础 60 格；crate +16；locker +30；储水罐 40 L 不占格 | 见 §5 |
| 堆叠上限 | 见物品表；堆叠只影响格数，不影响重量 | |

---

## 2. 物品目录

列：id / 中文名 / English / 主类（附加标签）/ 重量 kg / 堆叠上限 / 基础 VP / 效果（数值）/ 主要来源 / 备注。

通用约定：

- 食物的"饱食 +N"指一份；"热食"指刚做好或加热过的，附带 6 小时的"热饭"慰藉条目（心理 +3，衰减 6 小时）。
- 食物价值锚点：**饱食 3 点 ≈ 1 VP**（豆子罐头 +30 饱食 = 10 VP）；水 **1 L ≈ 4 VP**；热能 **1 kWh ≈ 3 VP**。其余物品按稀缺度与加工量上浮。
- 来源栏的地点 id 取自 §9 的 18 个规范 id；"开局"= 开局物资（§10.2）；"挖掘"= 清瓦砾 / 雪堆挖掘（§5.4）；"制作"= 见 §3。
- 变质：`cooked_meal`、`stew` 在室温 > 5 °C 的储物区放 36 小时后变为 `spoiled`（标记，非物品；食用即 50% 食物中毒）；室外 < 0 °C 不变质。其余物品不变质。

### 2.1 食物与水

| id | 中文名 | English | 类别 | kg | 堆叠 | VP | 效果 | 来源 | 备注 |
|---|---|---|---|---|---|---|---|---|---|
| canned_beans | 豆子罐头 | Canned Beans | food（food_any） | 0.45 | 12 | 10 | 饱食 +30 | supermarket, suburb_house, church, 开局 | 冷食无心理加成；`heat_can` 后心理 +1 |
| canned_soup | 浓汤罐头 | Canned Soup | food（food_any） | 0.4 | 12 | 7 | 饱食 +20，水分 +10 | supermarket, church, school, 开局 | 低饱食，但同时解渴 |
| canned_meat | 肉罐头 | Canned Meat | food（food_any） | 0.4 | 12 | 13 | 饱食 +40 | supermarket, farm, checkpoint_kilo | 可作炖菜原料 |
| canned_fruit | 水果罐头 | Canned Fruit | food（food_any） | 0.45 | 12 | 6 | 饱食 +15，水分 +10，心理 +2 | supermarket, suburb_house, motel | 小慰藉 |
| dried_rice | 干米 | Dried Rice | food（food_ingredient） | 0.5 | 20 | 24 | 不可直接吃 | supermarket, farm, church, 开局 | 0.5 kg 做 2 份熟饭 = 90 饱食，单位重量最高效的主食 |
| sugar | 糖 | Sugar | food（food_ingredient） | 0.5 | 20 | 6 | 原料；直接吃饱食 +8 | supermarket, motel | 蒸馏用 |
| salt | 盐 | Salt | food（food_ingredient） | 0.5 | 20 | 4 | 原料 | supermarket, gas_station, farm | 烟熏用 |
| raw_meat | 生肉 | Raw Meat | food（food_raw） | 0.6 | 8 | 8 | 饱食 +30；吃生的 35% 食物中毒 | farm, river_dock, 事件 | 室外保存不变质 |
| raw_fish | 生鱼 | Raw Fish | food（food_raw） | 0.5 | 8 | 7 | 饱食 +25；吃生的 25% 中毒 | river_dock | |
| rat_meat | 鼠肉 | Rat Meat | food（food_raw） | 0.2 | 20 | 3 | 饱食 +10；吃生的 45% 中毒 | 捕鼠笼 | 2 份熟成 1 份熟饭 |
| wild_roots | 野根茎 | Wild Roots | food（food_raw） | 0.3 | 20 | 2 | 饱食 +10；10% 中毒 | 挖掘, farm | 代用咖啡原料 |
| sprouts | 芽菜 | Sprouts | food（food_any） | 0.2 | 12 | 5 | 饱食 +15，心理 +1 | 芽菜盘 | 1 米 + 1 水 → 3 份，3 天 |
| cooked_meal | 热饭菜 | Cooked Meal | food（food_any） | 0.5 | 10 | 15 | 饱食 +45，水分 +5，热食心理 +3 | 制作 | 36 小时变质（见上） |
| stew | 炖菜 | Stew | food（food_any） | 0.6 | 10 | 20 | 饱食 +60，水分 +10，热食心理 +4 | 制作 | 同上；单份最高饱食 |
| smoked_meat | 烟熏肉 | Smoked Meat | food（food_any） | 0.3 | 12 | 18 | 饱食 +40 | 制作, trailer_market | 不变质；可交易 |
| bottled_water | 瓶装水 | Bottled Water | water（water_any） | 1.0 | 6 | 4 | 水分 +40 | supermarket, church, motel, 开局 | 1 L |
| snow_water | 融雪水 | Snow Water | water | 1.0 | 6 | 1 | 水分 +30；喝生的 20% 食物中毒 | 融雪桶 | 未处理 |
| clean_water | 净水 | Clean Water | water（water_any） | 1.0 | 6 | 4 | 水分 +40 | 煮沸 / 滤水 | 做饭、加湿器、医疗用 |

### 2.2 燃料

| id | 中文名 | English | 类别 | kg | 堆叠 | VP | 效果 | 来源 | 备注 |
|---|---|---|---|---|---|---|---|---|---|
| firewood | 柴火 | Firewood | fuel（fuel_any, heat_fuel） | 2.0 | 10 | 9 | 3.0 kWh | 挖掘, construction_site, farm, warehouse, church, 开局 | 家具拆解、木板劈柴也出 |
| coal | 煤块 | Coal | fuel（fuel_any, heat_fuel） | 1.5 | 10 | 13 | 4.5 kWh | construction_site, river_dock, warehouse | 同重量热值 1.5 倍柴火 |
| gasoline | 汽油 | Gasoline | fuel（fuel_any） | 0.75 | 10 | 8 | 1 L；发电机约 2.6 kWh/L | gas_station, farm, warehouse, radio_tower, 开局 | 同时是南行结局的车用燃料 |
| propane | 丙烷罐 | Propane Canister | fuel（fuel_any） | 1.0 | 4 | 22 | 7.2 kWh（1800 W 加热器烧 4 小时） | gas_station, hardware_store, motel | |

### 2.3 材料与零件

| id | 中文名 | English | 类别 | kg | 堆叠 | VP | 效果 | 来源 | 备注 |
|---|---|---|---|---|---|---|---|---|---|
| scrap | 废料 | Scrap | material | 1.0 | 20 | 2 | 通用金属杂件 | 挖掘, construction_site, hardware_store, warehouse | 最常见 |
| components | 零件 | Components | material | 0.3 | 20 | 6 | 螺栓、弹簧、轴承 | hardware_store, school, construction_site, gas_station | |
| electronics | 电子元件 | Electronics | material | 0.2 | 20 | 9 | 电路板、芯片 | school, radio_tower, police_station, suburb_house | |
| cloth | 布料 | Cloth | material | 0.3 | 20 | 3 | 衣物、被单 | suburb_house, elder_house, motel, church | |
| insulation | 保温棉 | Insulation | material | 0.8 | 10 | 7 | 保温层 I/II 用 | hardware_store, construction_site, warehouse | 也可 3 布料合 1 |
| planks | 板材 | Planks | material | 1.5 | 10 | 3 | 封窗、家具、劈柴 | 挖掘, construction_site, warehouse | |
| nails | 钉子 | Nails | material | 0.1 | 50 | 0.4 | | hardware_store, construction_site | 1 废料 → 6 钉子 |
| rope | 绳索 | Rope | material | 0.3 | 10 | 3 | | hardware_store, river_dock | |
| duct_tape | 胶带 | Duct Tape | material | 0.2 | 10 | 4 | | hardware_store, gas_station, police_station | |
| wire | 电线 | Wire | material | 0.2 | 20 | 3 | | hardware_store, construction_site, radio_tower | |
| pipe | 管件 | Pipe | material | 0.8 | 10 | 4 | | hardware_store, construction_site, river_dock | |
| heater_parts | 加热器配件 | Heater Parts | part（parts_any） | 0.6 | 5 | 16 | 修电暖器、造丙烷加热器 | hardware_store, motel, warehouse | |
| humidifier_parts | 加湿器配件 | Humidifier Parts | part（parts_any） | 0.4 | 5 | 12 | 修加湿器 | clinic, suburb_house, school | |
| radio_parts | 无线电配件 | Radio Parts | part（parts_any） | 0.3 | 5 | 18 | 收音机、天线、短波 | radio_tower, police_station | 最紧缺的专用件 |
| generator_parts | 发电机配件 | Generator Parts | part（parts_any） | 1.5 | 4 | 24 | 修发电机 | construction_site, gas_station, warehouse | |
| battery | 电池 | Battery | part（parts_any） | 0.3 | 10 | 8 | 手电筒 6 小时；蓄电池组原料 | gas_station, school, radio_tower, trailer_market | 一次性 |
| filter_cartridge | 滤芯 | Filter Cartridge | part（parts_any） | 0.4 | 5 | 12 | 净水器 40 L 寿命 | hardware_store, church, 制作 | |
| car_parts | 汽车配件 | Car Parts | part（car_part） | 3.0 | 4 | 30 | 修车 | gas_station, trailer_market, motel | 修车需 4 件 |
| car_battery | 汽车电瓶 | Car Battery | part（car_part） | 8.0 | 1 | 40 | 修车 | gas_station, trailer_market | 修车需 1 件 |
| tire | 轮胎 | Tire | part（car_part） | 9.0 | 1 | 30 | 修车 | gas_station, trailer_market | 修车需 2 件；重，必须用雪橇 |

### 2.4 药品

| id | 中文名 | English | 类别 | kg | 堆叠 | VP | 效果 | 来源 | 备注 |
|---|---|---|---|---|---|---|---|---|---|
| bandage | 绷带 | Bandage | med（med_any） | 0.1 | 20 | 6 | 止血；轻伤愈合速度 ×2（12 小时） | pharmacy, clinic, suburb_house, 开局 | 重伤要 2 条 |
| antibiotics | 抗生素 | Antibiotics | med（med_any） | 0.05 | 20 | 18 | 一剂；肺炎要连服 3 天（每天 1 剂） | pharmacy, clinic, checkpoint_kilo | elena 只需 2 剂 |
| painkillers | 止痛药 | Painkillers | med（med_any） | 0.05 | 20 | 10 | 8 小时内伤病对效率与速度的惩罚减半 | pharmacy, clinic, suburb_house | |
| cold_medicine | 感冒药 | Cold Medicine | med（med_any） | 0.05 | 20 | 9 | 感冒病程减半；24 小时内不转肺炎 | pharmacy, suburb_house, school | |
| antiseptic | 消毒液 | Antiseptic | med（med_any） | 0.3 | 10 | 8 | 重伤感染率 −50%；冻伤病程 6→3 天 | pharmacy, clinic, 制作 | 酒可制作 |
| first_aid_kit | 急救包 | First Aid Kit | med（med_any） | 0.8 | 3 | 35 | 一次完成 2 绷带 + 消毒液 + 止痛药的效果，濒死也能稳住 | clinic, police_station, checkpoint_kilo, 制作 | 合成要 3 绷带 + 消毒液 + 止痛药（36 VP），买卖价 35：省的是时间与格数 |
| insulin | 胰岛素 | Insulin | quest | 0.05 | 4 | 60 | 剧情：救助糖尿病 NPC | pharmacy, clinic | 不属 `med_any`，防止被泛称条件征收 |

### 2.5 奢侈品

| id | 中文名 | English | 类别 | kg | 堆叠 | VP | 效果 | 来源 | 备注 |
|---|---|---|---|---|---|---|---|---|---|
| coffee | 咖啡 | Coffee | luxury（luxury_any） | 0.1 | 20 | 12 | 一份：精力 +15，心理 +6（6 小时） | supermarket, motel, church | |
| instant_coffee | 速溶咖啡 | Instant Coffee | luxury（luxury_any） | 0.1 | 20 | 8 | 一份：精力 +12，心理 +4（6 小时） | supermarket, gas_station, motel | |
| chicory_coffee | 代用咖啡 | Chicory Coffee | luxury（luxury_any） | 0.1 | 20 | 4 | 一份：精力 +6，心理 +3（6 小时） | 制作 | 野根茎烘焙 |
| whiskey | 威士忌 | Whiskey | luxury（luxury_any, alcohol_any） | 0.9 | 6 | 28 | 一瓶 4 份；每份心理 +8（2 小时）；junho 酒精依赖 | supermarket, motel, checkpoint_kilo | 哨站军士的"礼物" |
| moonshine | 私酿酒 | Moonshine | luxury（luxury_any, alcohol_any） | 0.9 | 6 | 16 | 一瓶 4 份；每份心理 +7；每份 3% 食物中毒 | farm, trailer_market, 制作 | |
| cigarettes | 香烟 | Cigarettes | luxury（luxury_any） | 0.1 | 10 | 18 | 一包 5 份；每份心理 +4（3 小时）；marcus 烟瘾 | gas_station, supermarket, trailer_market | |
| book | 书 | Book | luxury（luxury_any） | 0.5 | 6 | 10 | 阅读 2 小时：心理 +5；可重复读，同一人每天最多一次 | suburb_house, elder_house, church, school | 可烧：0.5 kWh，部分角色扣心理 |
| chocolate | 巧克力 | Chocolate | luxury（luxury_any） | 0.1 | 20 | 10 | 饱食 +10，心理 +5 | supermarket, school, church | |

### 2.6 工具与武器

| id | 中文名 | English | 类别 | kg | 堆叠 | VP | 效果 | 来源 | 备注 |
|---|---|---|---|---|---|---|---|---|---|
| lockpick | 开锁器 | Lockpick | tool（tool_any） | 0.1 | 5 | 8 | 撬锁；耐久 15 次 | hardware_store, police_station, 制作 | sam 自带一套，不占格 |
| crowbar | 撬棍 | Crowbar | tool（tool_any, weapon_any, melee_any） | 2.0 | 1 | 12 | 破门；近战伤害 16；耐久 120 | hardware_store, construction_site, 制作 | |
| shovel | 铲子 | Shovel | tool（tool_any） | 2.5 | 1 | 10 | 挖掘 / 清瓦砾速度 ×2.5 | hardware_store, construction_site, farm, 制作 | |
| flashlight | 手电筒 | Flashlight | tool（tool_any） | 0.4 | 1 | 14 | 光照 +0.5（锥形）；耗 1 电池 / 6 小时 | gas_station, hardware_store, school | 会暴露自己 |
| hammer | 锤子 | Hammer | tool（tool_any） | 0.8 | 1 | 8 | 封窗、加固必备 | hardware_store, construction_site, 开局 | |
| hand_saw | 手锯 | Hand Saw | tool（tool_any） | 0.7 | 1 | 8 | 拆家具、劈板材速度 ×1.5 | hardware_store, construction_site | |
| toolbox | 工具箱 | Toolbox | tool（tool_any） | 3.0 | 1 | 30 | 修发电机、修车必备；携带时修理耗时 ×0.85 | hardware_store, gas_station, 开局 | |
| multimeter | 万用表 | Multimeter | tool（tool_any） | 0.3 | 1 | 18 | 修收音机 / 造短波必备 | school, radio_tower, police_station | linwei 开局自带 |
| binoculars | 望远镜 | Binoculars | tool（tool_any） | 0.5 | 1 | 22 | 望风时视距 +4 格 | police_station, motel, farm | |
| knife | 小刀 | Knife | weapon（weapon_any, melee_any） | 0.3 | 1 | 10 | 伤害 14；背后一击必杀 | suburb_house, supermarket, 制作 | |
| bat | 球棒 | Bat | weapon（weapon_any, melee_any） | 1.0 | 1 | 8 | 伤害 18；可打晕 | suburb_house, school, 制作 | |
| axe | 斧头 | Axe | weapon（weapon_any, melee_any） | 2.0 | 1 | 14 | 伤害 28；劈柴速度 ×2 | farm, hardware_store, 制作 | |
| handgun | 手枪 | Handgun | weapon（weapon_any, gun_any） | 1.0 | 1 | 90 | 伤害 30，弹匣 8 | police_station, warehouse, elder_house, checkpoint_kilo | |
| shotgun | 霰弹枪 | Shotgun | weapon（weapon_any, gun_any） | 3.2 | 1 | 140 | 伤害 55（近），弹匣 2 | police_station, warehouse, farm | |
| hunting_rifle | 猎枪 | Hunting Rifle | weapon（weapon_any, gun_any） | 3.5 | 1 | 150 | 伤害 60，弹匣 4 | elder_house, farm, police_station | dale 开局可能自带 |
| suppressor | 消音器 | Suppressor | weapon | 0.3 | 1 | 50 | 装在手枪上：噪音半径 60→25，用 60 发后失效 | 制作, checkpoint_kilo | |
| bear_trap | 捕兽夹 | Bear Trap | weapon | 1.5 | 4 | 20 | 放置；伤害 25，定身 6 秒 | 制作, farm | 家园防御用 |
| handgun_ammo | 手枪弹 | Handgun Ammo | ammo（ammo_any） | 0.02 | 30 | 4 | 1 发 | police_station, warehouse, checkpoint_kilo | |
| shotgun_shells | 霰弹 | Shotgun Shells | ammo（ammo_any） | 0.05 | 20 | 6 | 1 发 | police_station, farm, warehouse | |
| rifle_ammo | 步枪弹 | Rifle Ammo | ammo（ammo_any） | 0.04 | 20 | 7 | 1 发 | farm, elder_house, police_station | |

### 2.7 穿戴与装备

体温加成见 §6.2（"有效温度"加项）。

| id | 中文名 | English | 类别 | kg | 堆叠 | VP | 效果 | 来源 | 备注 |
|---|---|---|---|---|---|---|---|---|---|
| winter_coat | 冬季外套 | Winter Coat | wear（wear_any） | 1.2 | 1 | 40 | 有效温度 +5 °C | suburb_house, motel, 制作 | |
| winter_coat_2 | 防寒大衣 | Arctic Coat | wear（wear_any） | 2.0 | 1 | 100 | 有效温度 +9 °C；受近战伤害 −10% | police_station, checkpoint_kilo, 制作 | 寒潮夜外出的门槛 |
| wool_hat | 毛线帽 | Wool Hat | wear（wear_any） | 0.1 | 1 | 8 | +1.5 °C | suburb_house, elder_house, 制作 | |
| wool_gloves | 手套 | Wool Gloves | wear（wear_any） | 0.1 | 1 | 8 | +1.5 °C | suburb_house, elder_house, 制作 | |
| snow_boots | 雪地靴 | Snow Boots | wear（wear_any） | 1.0 | 1 | 18 | +2 °C；雪地行走噪音 −10% | suburb_house, hardware_store, 制作 | |
| backpack_small | 小背包 | Small Backpack | gear | 0.5 | 1 | 15 | 载重 +4 kg，+6 格 | school, suburb_house, 制作 | |
| backpack_large | 大背包 | Large Backpack | gear | 1.0 | 1 | 40 | 载重 +10 kg，+14 格 | school, police_station, construction_site, 制作 | |
| sled | 雪橇 | Sled | gear | 6.0 | 1 | 60 | 户外载重 +20 kg，速度 ×0.9 | school, 制作 | 只能留在入口 |
| blanket | 毯子 | Blanket | gear | 0.8 | 4 | 12 | 铺在床上：睡眠有效温度 +2 °C | suburb_house, elder_house, motel, 制作 | |

### 2.8 剧情物品

| id | 中文名 | English | 类别 | kg | 堆叠 | VP | 效果 | 来源 | 备注 |
|---|---|---|---|---|---|---|---|---|---|
| keepsake | 遗物 | Keepsake | quest | 0.1 | 8 | 0 | 每位 NPC 的个人物品（WORLD §5）；实际条目带 `owner` 字段 | 住户地点 | 归还可触发 `return_goods`；不可交易估价 |
| kilo_pass | 哨站通行证 | Kilo Pass | quest | 0 | 1 | 0 | 通过哨站盘查 | checkpoint_kilo 剧情 | |
| kilo_ledger | 军士账本 | Pike's Ledger | quest | 0.3 | 1 | 0 | 把柄（`kilo.pike_leverage`） | checkpoint_kilo, raid_found 事件 | |
| lieutenant_letter | 中尉的信 | Lieutenant's Letter | quest | 0 | 1 | 0 | 推荐信，提高 `lt_trust` | checkpoint_kilo 剧情 | |
| frequency_note | 频率纸条 | Frequency Note | quest | 0 | 1 | 0 | 短波哨站频率 | radio_tower, grace 引荐 | 与 t_shortwave 配合 |
| car_key | 车钥匙 | Car Key | quest | 0 | 1 | 0 | 南行结局必需 | 剧情 / 事件 | |

### 2.9 图纸

读取图纸后写入 `state.tech.blueprints[id] = true`，物品消失；图纸可在读取前交易（VP 35，仅哨站军士与流动商贩收）。每局图纸的投放规则见 §4.3。

| id | 中文名 | English | 对应科技 | 主要来源 |
|---|---|---|---|---|
| bp_bench3 | 工作台 III 图纸 | Bench III Plans | t_bench3 | construction_site, warehouse |
| bp_insulation_2 | 保温层 II 图纸 | Insulation II Plans | t_insulation_2 | hardware_store, construction_site |
| bp_wood_stove | 柴火炉图纸 | Wood Stove Plans | t_wood_stove | hardware_store, farm, church |
| bp_cold_cell | 避寒小间图纸 | Cold Cell Plans | t_cold_cell | construction_site, elder_house |
| bp_distiller | 蒸馏器图纸 | Still Plans | t_distiller | farm, trailer_market, motel |
| bp_smokehouse | 烟熏架图纸 | Smokehouse Plans | t_smokehouse | farm, river_dock |
| bp_suppressor | 消音手段图纸 | Suppressor Plans | t_suppressor | police_station, checkpoint_kilo |
| bp_traps | 陷阱图纸 | Trap Plans | t_traps | farm, elder_house |
| bp_coat2 | 冬装 II 图纸 | Arctic Coat Plans | t_coat2 | police_station, school |
| bp_car_repair | 修车图纸 | Auto Repair Manual | t_car_repair | gas_station, river_dock |
| bp_battery_bank | 蓄电池组图纸 | Battery Bank Plans | t_battery_bank | radio_tower, school |
| bp_shortwave | 短波图纸 | Shortwave Plans | t_shortwave | radio_tower, police_station |

物品合计：食物 15 + 水 3 + 燃料 4 + 材料与零件 20 + 药品 7 + 奢侈品 8 + 工具 9 + 武器弹药 11 + 穿戴装备 9 + 剧情 6 + 图纸 12 = **104** 项。

---

## 3. 配方表

### 3.1 通则

| 项 | 规则 |
|---|---|
| 耗时 | "工 + 等"：**工**是占用角色的分钟数（按角色效率换算，§6.4）；**等**是设施自行运转的分钟数，不占人 |
| 设施 | `手` = 徒手，任何地方；`灶` = 简易灶 / 改良灶 / 柴火炉任一；`台 I/II/III` = 工作台等级（高级台可做低级配方）；工作台速度：I ×1.0，II ×1.15，III ×1.3（工时除以该值） |
| 燃料 | 小数燃料按设施累计，凑满 1 件才扣一件；改良灶：燃料 ×0.7、工时 ×0.8 |
| 科技 | 配方在对应 `t_*` 节点研究完成后解锁；"—" = 开局即会 |
| 特长 | 来自 GDD §1.4；写作"工时 ×0.6"表示该角色亲手做时工时乘 0.6；"料 ×0.75"表示材料数量乘 0.75（向上取整，至少 1）；"产 +1"表示成品数 +1 |
| 工具 | 配方列出"需"的工具只要求在背包或设施旁，不消耗（除非写明耐久） |
| 失败 | 无随机失败；做错的代价由"浪费材料的选择"体现，不由骰子决定 |

### 3.2 烹饪（设施：灶）

| id | 产出 | 材料 | 设施 | 耗时（工+等） | 科技 | 特长加成 |
|---|---|---|---|---|---|---|
| heat_can | 一份热食罐头（只给"热食"慰藉，物品不变） | 任一 `food_any` 罐头 ×1 + 柴 0.05 | 灶 | 5 | t_hearth | junho 工时 ×0.6 |
| cook_meat | cooked_meal ×1 | raw_meat ×1 + 柴 0.1 | 灶 | 15 | t_hearth | — |
| cook_fish | cooked_meal ×1 | raw_fish ×1 + 柴 0.1 | 灶 | 12 | t_hearth | — |
| cook_roots | cooked_meal ×1 | wild_roots ×3 + 柴 0.1 | 灶 | 12 | t_hearth | |
| cook_rat | cooked_meal ×1 | rat_meat ×2 + 柴 0.1 | 灶 | 15 | t_rat_trap | |
| cook_rice | cooked_meal ×2 | dried_rice ×1 + clean_water ×1 + 柴 0.2 | 灶 | 25 | t_hearth | **junho 产 +1（共 3 份）**、燃料 ×0.7、水 ×0.8（向上取整，至少 1） |
| cook_stew | stew ×2 | (raw_meat 或 canned_meat) ×1 + dried_rice ×1 + clean_water ×1 + 柴 0.3 | 灶（改良灶起） | 35 | t_hearth2 | junho 产 +1（共 3 份）、燃料 ×0.7 |
| grow_sprouts | sprouts ×3 | dried_rice ×1 + clean_water ×1 | 芽菜盘（房间 ≥ 8 °C） | 10 + 4320 | t_sprout_tray | |
| smoke_meat | smoked_meat ×2 | raw_meat ×2 + salt ×1 + 柴 0.5 | 烟熏架 | 20 + 360 | t_smokehouse | junho 工时 ×0.7 |
| roast_chicory | chicory_coffee ×2 | wild_roots ×2 + 柴 0.15 | 灶（改良灶起） | 20 | t_chicory_roaster | |
| distill_moonshine | moonshine ×2 | sugar ×3 + dried_rice ×1 + clean_water ×3 + 柴 1 | 蒸馏器 | 20 + 240 | t_distiller | junho 产 +1（共 3 瓶） |

推导：cook_rice 1 米 24 VP + 水 4 VP + 柴 1.8 VP ≈ 30 VP，产出 2 × 15 = 30 VP，**做饭本身不增值，只换来"能吃"与热食心理加成**；炖菜与烟熏、蒸馏才有加价（炖菜 13 + 24 + 4 + 2.7 = 44 VP → 40 VP，略亏，靠心理 +4 与 +60 饱食的紧凑重量拿回来；蒸馏 6×3 + 24 + 12 + 9 = 63 VP → 32 VP，**亏本酿酒只在以酒换哨站名额或安抚酒依赖者时才划算**，这是有意的）。

### 3.3 水（设施：融雪桶 / 灶 / 净水器）

| id | 产出 | 材料 | 设施 | 耗时（工+等） | 科技 | 特长加成 |
|---|---|---|---|---|---|---|
| melt_snow | snow_water ×4 | 柴 0.5（雪取自室外，免费） | 融雪桶 | 5 + 60 | t_snow_melter | |
| boil_water | clean_water ×4 | snow_water ×4 + 柴 0.25 | 灶 | 20 | t_hearth | junho 燃料 ×0.7、工时 ×0.8 |
| filter_water | clean_water ×4 | snow_water ×4（滤芯寿命 −4 L） | 净水器 | 10 | t_water_filter | |
| make_filter | filter_cartridge ×1 | cloth ×1 + coal ×1 + scrap ×1 | 台 I | 15 | t_water_filter | |

推导：每升净水的燃料成本 = 融雪 0.125 + 煮沸 0.06 = 0.19 柴 ≈ 1.7 VP，低于瓶装水 4 VP；滤水免去煮沸，每 40 L 一个滤芯（12 VP）= 0.3 VP/L，所以净水器值得在第二幕前建好。

### 3.4 制作（设施：工作台）

| id | 产出 | 材料 | 设施 | 耗时（工+等） | 科技 | 特长加成 |
|---|---|---|---|---|---|---|
| make_nails | nails ×6 | scrap ×1 | 台 I | 8 | t_bench1 | walt 工时 ×0.7 |
| make_insulation | insulation ×1 | cloth ×3 | 台 I | 10 | t_insulation_1 | |
| chop_planks | firewood ×2 | planks ×1 | 手（需 axe 或 hand_saw） | 10 | — | walt 工时 ×0.8 |
| repair_tool | 工具耐久 +50% | scrap ×1 | 台 I | 10 | t_bench1 | marcus 料 ×0.75 |
| craft_crowbar | crowbar ×1 | scrap ×3 | 台 I | 30 | t_crowbar | |
| craft_shovel | shovel ×1 | scrap ×2 + planks ×1 | 台 I | 25 | t_shovel | walt 工时 ×0.7 |
| craft_pack_small | backpack_small ×1 | cloth ×4 + rope ×1 | 台 I | 40 | t_pack_small | |
| craft_blanket | blanket ×1 | cloth ×5 + insulation ×1 | 台 I | 25 | t_bed | |
| craft_pack_large | backpack_large ×1 | cloth ×8 + rope ×2 + duct_tape ×1 | 台 II | 70 | t_pack_small | |
| craft_lockpick | lockpick ×2 | scrap ×1 + wire ×1 | 台 II | 20 | t_lockpick | **sam 工时 ×0.5、产 +1** |
| craft_knife | knife ×1 | scrap ×2 + cloth ×1 | 台 II | 25 | t_melee | |
| craft_bat | bat ×1 | planks ×2 + nails ×4 | 台 II | 25 | t_melee | walt 工时 ×0.7 |
| craft_axe | axe ×1 | scrap ×4 + planks ×2 | 台 II | 45 | t_melee | walt 工时 ×0.7 |
| repair_weapon | 武器耐久 +50% | scrap ×1 + components ×1 | 台 II | 20 | t_melee | grace 工时 ×0.6 |
| craft_sled | sled ×1 | planks ×6 + rope ×2 + nails ×10 + scrap ×2 | 台 II | 90 | t_sled | walt 工时 ×0.7、料 ×0.8 |
| craft_coat | winter_coat ×1 | cloth ×6 + insulation ×2 + duct_tape ×1 | 台 II | 60 | t_coat1 | |
| craft_hat | wool_hat ×1 | cloth ×2 | 台 II | 20 | t_coat1 | |
| craft_gloves | wool_gloves ×1 | cloth ×2 | 台 II | 20 | t_coat1 | |
| craft_boots | snow_boots ×1 | cloth ×3 + insulation ×1 + rope ×1 | 台 II | 40 | t_coat1 | |
| craft_coat2 | winter_coat_2 ×1 | cloth ×8 + insulation ×4 + duct_tape ×2 + components ×2 | 台 III | 120 | t_coat2 | |
| craft_suppressor | suppressor ×1 | pipe ×1 + insulation ×1 + scrap ×2 + components ×1 | 台 III | 60 | t_suppressor | grace 工时 ×0.8 |
| craft_bear_trap | bear_trap ×1 | scrap ×4 + components ×1 | 台 III | 40 | t_traps | **dale 工时 ×0.7、产 +1** |

价值核对（防止"制作比捡便宜得多"或"亏得没意义"）：冬季外套材料 18 + 14 + 4 = 36 VP，成品 40 VP；防寒大衣材料 24 + 28 + 8 + 12 = 72 VP，成品 100 VP（高阶制作加价约 40%）；撬棍 6 VP → 12 VP。基调：**制作的价值是"把废料变成急需的东西"，不是套利**。

### 3.5 修理、建造与加固

设施的建造/修复成本集中在 §5；这里列配方入口（工作台等级与耗时）。

| id | 产出 | 材料 | 设施 | 耗时（工+等） | 科技 | 特长加成 |
|---|---|---|---|---|---|---|
| clear_rubble | 清除 1 格瓦砾，产出见 §5.4 | — | 手（铲子更快） | 20（铲子 8；t_clear_tools 后无铲 12） | — | walt 工时 ×0.8 |
| salvage_furniture | planks ×2 或 firewood ×3 | 一件家具 | 手 | 10 | t_clear_tools | 烧书、烧遗物类家具对部分角色扣心理（价值观权重，WORLD §2.2） |
| board_window | 窗洞 → 封板 | planks ×2 + nails ×4 | 手（需 hammer） | 20 | t_board_up | **walt 工时 ×0.7、料 ×0.8** |
| board_hole | 墙洞 → 封板 | planks ×4 + nails ×8 | 手（需 hammer） | 35 | t_board_up | walt 同上 |
| insulate_I | 房间保温层 I | insulation ×⌈格数/4⌉ + nails ×⌈格数/2⌉ | 手（需 hammer） | 3 分钟/格 | t_insulation_1 | walt 同上 |
| insulate_II | 房间保温层 II（须先有 I） | insulation ×⌈格数/4⌉×2 + planks ×⌈格数/4⌉ + duct_tape ×⌈格数/10⌉ | 手（需 hammer） | 5 分钟/格 | t_insulation_2 | walt 同上 |
| reinforce_door_1 | 门强度 60 → 150 | planks ×4 + nails ×8 | 手（需 hammer） | 30 | t_board_up | walt 同上 |
| reinforce_door_2 | 门强度 → 300（钢板） | scrap ×6 + planks ×2 + nails ×6 + components ×2 | 台 II | 60 | t_bench2 | walt 同上 |
| reinforce_window | 封板强度 80 → 160 | planks ×3 + nails ×6 | 手（需 hammer） | 25 | t_board_up | walt 同上 |
| build_tripwire | 绊线警报 ×1 | scrap ×1 + rope ×1 | 手 | 10 | t_board_up | dale 工时 ×0.6 |
| repair_heater | 电暖器修复 | heater_parts ×2 + components ×1 | 手 | 40 | t_heater_repair | **marcus 工时 ×0.6、料 ×0.75**；部分修复见 §5.2 |
| repair_humidifier | 加湿器修复 | humidifier_parts ×2 + components ×1 | 手 | 30 | t_humidifier | marcus 同上 |
| repair_generator | 发电机修复 | generator_parts ×3 + components ×2（需 toolbox） | 手 | 90 | t_generator | marcus 同上 |
| repair_radio | 收音机修复 | radio_parts ×2 + electronics ×2（需 multimeter） | 手 | 60 | t_radio_fix | **linwei 工时 ×0.6、料 ×0.75** |
| build_antenna | 天线 | wire ×4 + pipe ×2 + radio_parts ×1 | 台 I | 60 | t_antenna | linwei 同上 |
| build_lamp | 灯 ×1 | components ×1 + wire ×1 + electronics ×1 | 台 I | 20 | t_lamps | linwei 工时 ×0.7 |
| build_battery_bank | 蓄电池组 | battery ×8 + electronics ×3 + wire ×4 + components ×3 | 台 III | 100 | t_battery_bank | linwei 工时 ×0.6 |
| build_shortwave | 短波电台 | radio_parts ×3 + electronics ×4 + battery ×2（需 multimeter） | 台 III | 120 | t_shortwave | linwei 工时 ×0.6、料 ×0.75 |
| build_propane_heater | 丙烷加热器 | heater_parts ×2 + pipe ×2 + components ×2 + scrap ×2 | 台 II | 60 | t_propane_heater | marcus 同上 |
| build_woodstove | 柴火炉 | scrap ×10 + pipe ×4 + components ×2 + duct_tape ×1 | 台 II | 120 | t_wood_stove | walt 工时 ×0.7 |
| build_cold_cell | 避寒小间（6 格小房，见 §5.3） | planks ×12 + insulation ×12 + nails ×20 + duct_tape ×4 | 手（需 hammer） | 180 | t_cold_cell | walt 工时 ×0.6、料 ×0.8 |
| repair_car | 修好汽车 | car_parts ×4 + car_battery ×1 + tire ×2（需 toolbox + car_key） | 车库 | 240，分多个班次完成 | t_car_repair | marcus 工时 ×0.7 |

南行结局所需：修车件 4×30 + 40 + 2×30 = **220 VP**，加汽油 **40 L（320 VP）**（`car.fuel ≥ 40`，回应 WORLD R9）。合计约 540 VP ≈ 3 天的全队消耗（§10.1），第 25 天后才可出发（GDD §1.12），所以不是"早点修好就能溜"。

### 3.6 医疗

| id | 产出 | 材料 | 设施 | 耗时（工+等） | 科技 | 特长加成 |
|---|---|---|---|---|---|---|
| improvise_bandage | bandage ×1 | cloth ×2 + clean_water ×1 + 柴 0.1 | 灶 | 15 | t_hearth | **elena 产 +1（共 2 条）** |
| antiseptic_brew | antiseptic ×2 | whiskey 或 moonshine ×1（1 瓶） | 手 | 10 | — | elena 产 +1（共 3 瓶） |
| assemble_first_aid | first_aid_kit ×1 | bandage ×3 + antiseptic ×1 + painkillers ×1 | 手 | 15 | — | elena 工时 ×0.6 |

治疗动作本身（用药、包扎、护理）是命令 `treat`，耗时与效果：

| 动作 | 耗时 | 效果 | elena 加成 |
|---|---|---|---|
| 包扎（bandage ×1） | 10 分钟 | 止血；轻伤愈合 ×2 持续 12 小时 | 效果 ×1.5 |
| 重伤处置（bandage ×2） | 20 分钟 | 重伤愈合速度 +0.4/h → +1.2/h，持续 24 小时 | 只需 bandage ×1 |
| 濒死稳定（bandage ×1，或 first_aid_kit ×1） | 15 分钟 | 停止失血，计时器暂停 | 成功率 +20% |
| 服药（抗生素等） | 2 分钟 | 见 §6.5 | 抗生素疗程 3 → 2 剂 |
| 护理（陪床） | 持续 | 病程 ×0.8，需要一人专职 | 病程 ×0.65 |

---

## 4. 科技树

### 4.1 规则

- 研究 = 在**对应等级工作台**（表中"台"列）旁，消耗"材料"并占用一名角色"工时"分钟；完成后节点解锁。"★" = 材料同时是**首件设施的建造成本**（首件免费建成，再建同类设施按 §5 的成本）；其余节点的材料是研究原型的消耗，设施本身另付 §5 的建造成本。
- "图纸"列为"是"的节点，必须先在副本里找到 `bp_<节点>` 才能研究。
- "专属"：研究该节点需要指定角色在队且在家工作；该角色不在队时，**持图纸并且成本 ×1.5、工时 ×1.5 仍可研究**（避免死路）。
- 分支缩写：S = 生存，W = 保暖，K = 工坊，G = 信号与电力；后面的数字是层。
- 全树 40 个节点，材料合计约 **1420 VP**（不含图纸）。一局预计研究 55–65%（约 800–900 VP），占零件类实收（约 1800 VP，§9.2）的约 47%，剩下的用于设施建造、装备与修理。

### 4.2 节点表

| id | 名称 | 层 | 前置 | 材料（≈VP） | 工时 | 台 | 图纸 | 专属 / ★ | 解锁 |
|---|---|---|---|---|---|---|---|---|---|
| t_hearth | 简易灶 | S1 | — | scrap 3 + planks 1 (≈9) | 20 | — | — | ★ | 灶；cook_meat/cook_fish/cook_rice/cook_roots/heat_can/boil_water/improvise_bandage |
| t_snow_melter | 融雪桶 | S1 | — | scrap 4 + pipe 1 (≈12) | 30 | — | — | ★ | 融雪桶；melt_snow |
| t_water_tank | 储水罐 | S1 | t_snow_melter | scrap 3 + planks 2 + pipe 2 (≈20) | 35 | — | — | ★ | 储水罐（40 L） |
| t_hearth2 | 改良灶 | S2 | t_hearth | scrap 6 + pipe 2 + components 1 (≈26) | 45 | I | — | ★ | 改良灶（燃料×0.7、时间×0.8）；cook_stew |
| t_water_filter | 滤水器 | S2 | t_snow_melter | pipe 2 + cloth 3 + coal 1 + components 1 (≈36) | 40 | I | — | ★ | 净水器；filter_water；make_filter |
| t_rat_trap | 捕鼠笼 | S2 | t_hearth | scrap 2 + wire 1 + planks 1 (≈10) | 25 | I | — | ★ | 捕鼠笼设施（0.6 只/天）；cook_rat |
| t_sprout_tray | 芽菜盘 | S2 | t_water_tank | planks 2 + cloth 2 (≈12) | 20 | I | — | ★ | 芽菜盘；grow_sprouts |
| t_distiller | 蒸馏器 | S3 | t_hearth2 + t_water_filter | pipe 4 + scrap 6 + components 3 (≈46) | 90 | II | 是 | ★ | 蒸馏器；distill_moonshine |
| t_smokehouse | 烟熏架 | S3 | t_hearth2 + t_rat_trap | planks 8 + nails 20 + pipe 2 + salt 2 (≈48) | 100 | II | 是 | ★ | 烟熏架；smoke_meat |
| t_chicory_roaster | 代用咖啡烘焙 | S3 | t_sprout_tray + t_hearth2 | scrap 3 + components 2 (≈18) | 40 | II | — | — | roast_chicory |
| t_clear_tools | 清理工具 | W1 | — | scrap 2 (≈4) | 10 | — | — | — | 清瓦砾 20→12 分钟/格；salvage_furniture |
| t_board_up | 钉板封窗 | W1 | t_clear_tools | planks 2 + nails 6 (≈8) | 15 | — | — | — | board_window；board_hole；reinforce_door_1；tripwire |
| t_bed | 床铺 | W1 | — | planks 3 + cloth 4 (≈21) | 25 | — | — | ★ | 床铺；craft_blanket |
| t_heater_repair | 修复电暖器 | W2 | t_board_up | components 2 + electronics 1 (≈21) | 30 | I | — | — | repair_heater |
| t_humidifier | 加湿器 | W2 | t_heater_repair | components 2 + pipe 1 + electronics 1 (≈25) | 35 | I | — | — | repair_humidifier |
| t_insulation_1 | 保温层 I | W2 | t_board_up | cloth 4 + duct_tape 1 (≈16) | 25 | I | — | — | make_insulation；insulate_I |
| t_propane_heater | 丙烷加热器 | W2 | t_heater_repair | components 2 + pipe 2 + heater_parts 1 (≈36) | 45 | II | — | — | build_propane_heater |
| t_wood_stove | 柴火炉改造 | W3 | t_insulation_1 + t_hearth2 | scrap 6 + pipe 3 + components 2 (≈36) | 80 | II | 是 | — | build_woodstove |
| t_insulation_2 | 保温层 II | W3 | t_insulation_1 | insulation 4 + duct_tape 2 + planks 2 (≈42) | 60 | II | 是 | — | insulate_II |
| t_cold_cell | 避寒小间 | W3 | t_insulation_2 + t_wood_stove | planks 6 + insulation 6 + nails 10 (≈64) | 100 | II | 是 | 专属 walt | build_cold_cell |
| t_bench1 | 工作台 I | K1 | — | planks 6 + nails 20 + scrap 4 (≈34) | 60 | — | — | ★ | 工作台 I；make_nails；repair_tool；t_* 的 I 级研究 |
| t_crowbar | 撬棍 | K1 | t_bench1 | scrap 3 (≈6) | 15 | I | — | — | craft_crowbar |
| t_shovel | 铲子 | K1 | t_bench1 | scrap 2 + planks 1 (≈7) | 15 | I | — | — | craft_shovel；挖掘速度×2.5 |
| t_pack_small | 简易背包 | K1 | t_bench1 | cloth 4 + rope 1 (≈15) | 20 | I | — | — | craft_pack_small；（工作台 II 后）craft_pack_large |
| t_bench2 | 工作台 II | K2 | t_bench1 + t_shovel | planks 6 + scrap 10 + components 4 + nails 20 (≈70) | 120 | I | — | ★ | 工作台 II；craft 速度×1.15 |
| t_lockpick | 撬锁工具 | K2 | t_bench2 + t_crowbar | wire 2 + scrap 3 (≈12) | 30 | II | — | — | craft_lockpick |
| t_melee | 近战武器 | K2 | t_bench2 + t_crowbar | scrap 6 + components 2 (≈24) | 40 | II | — | — | craft_knife/bat/axe；repair_weapon |
| t_sled | 雪橇 | K2 | t_bench2 + t_pack_small | planks 4 + rope 2 + nails 10 (≈22) | 45 | II | — | — | craft_sled |
| t_coat1 | 冬装 I | K2 | t_bench2 + t_bed | cloth 6 + insulation 2 + duct_tape 1 (≈36) | 45 | II | — | — | craft_coat/hat/gloves/boots |
| t_bench3 | 工作台 III | K3 | t_bench2 | scrap 14 + components 8 + electronics 3 + pipe 4 (≈119) | 180 | II | 是 | ★ | 工作台 III；craft 速度×1.3 |
| t_suppressor | 消音手段 | K3 | t_bench3 + t_melee | components 3 + pipe 2 + insulation 2 (≈40) | 60 | III | 是 | — | craft_suppressor |
| t_traps | 陷阱 | K3 | t_bench3 + t_rat_trap | scrap 6 + components 3 + rope 2 (≈36) | 60 | III | 是 | 专属 dale | craft_bear_trap；绊线警报升级为"陷阱绊线" |
| t_coat2 | 冬装 II | K3 | t_coat1 + t_bench3 | cloth 10 + insulation 6 + duct_tape 3 + components 3 (≈102) | 90 | III | 是 | — | craft_coat2 |
| t_car_repair | 修车 | K3 | t_bench3 + t_generator | components 6 + pipe 4 + electronics 4 (≈88) | 120 | III | 是 | — | repair_car（南行结局） |
| t_radio_fix | 修复收音机 | G1 | — | radio_parts 2 + electronics 2 (≈54) | 60 | — | — | ★ 需万用表 | 收音机；预报 1 天 |
| t_antenna | 天线 | G2 | t_radio_fix | wire 4 + pipe 2 + radio_parts 1 (≈38) | 60 | I | — | ★ | 天线；预报 3 天；商贩行程 |
| t_generator | 发电机 | G2 | t_bench2 | components 3 + electronics 2 (≈36) | 40 | II | — | — | repair_generator（建造成本另计） |
| t_lamps | 灯 | G2 | t_generator | wire 2 + components 1 + electronics 1 (≈21) | 20 | I | — | — | build_lamp |
| t_battery_bank | 蓄电池组 | G3 | t_generator | electronics 3 + components 3 + wire 4 (≈57) | 60 | III | 是 | — | build_battery_bank |
| t_shortwave | 短波 | G3 | t_antenna + t_generator | electronics 4 + radio_parts 3 (≈90) | 90 | III | 是 | 专属 linwei 需万用表 | build_shortwave；哨站频率、远处消息 |

### 4.3 图纸投放规则（每局不同）

| 规则 | 数值 | 理由 |
|---|---|---|
| 必出 | bp_insulation_2、bp_wood_stove、bp_bench3 | 守住家路线（大寒潮 −48 °C）与全部高阶科技的闸门，不能因运气断路 |
| 其余 9 张 | 每张 65% 概率入池，期望约 6 张 | 总期望 ≈ 9 张，一局能研究其中约 2/3，路线各不相同 |
| 投放地点 | 从该图纸"主要来源"（§2.9）里随机选 1 个**本局已入池**的地点；若无则退而选任意高难度地点 | 保证图纸能被找到 |
| 投放时机 | 第 1 幕只放 bench3 / insulation_2 / wood_stove；其余图纸投在第 2、3 幕地点 | 让玩家第 1 幕就看到"下一步要什么" |
| 容器 | 放在"有主之物"之外的普通容器，同一地点最多 1 张 | 不让图纸挤占食物预算（图纸不计预算，§9） |

### 4.4 依赖图（ASCII）

```
生存 S
 S1: t_hearth ─────────┬─ t_hearth2 ─────────┬─ t_distiller*      (还需 t_water_filter)
                       │                      ├─ t_smokehouse*     (还需 t_rat_trap)
                       │                      └─ t_chicory_roaster (还需 t_sprout_tray)
                       └─ t_rat_trap ─────────────→ (t_smokehouse*, K3 t_traps*)
     t_snow_melter ────┬─ t_water_filter ──────────→ t_distiller*
                       └─ t_water_tank ──── t_sprout_tray ──→ t_chicory_roaster

保暖 W
 W1: t_clear_tools ─ t_board_up ─┬─ t_heater_repair ─┬─ t_humidifier
                                 │                   └─ t_propane_heater
                                 └─ t_insulation_1 ──┬─ t_insulation_2* ─┐
     t_bed ──→ (K2 t_coat1)                          └─ t_wood_stove* ───┴─ t_cold_cell*
                                          (t_wood_stove 还需 S2 t_hearth2)   (专属 walt)

工坊 K
 K1: t_bench1 ─┬─ t_crowbar ──┬─ t_lockpick
               ├─ t_shovel ───┤        ┌─ t_melee ──── t_suppressor*
               └─ t_pack_small┘        │
        t_bench2 (需 t_bench1 + t_shovel) ─┬─ t_lockpick / t_melee (需 t_crowbar)
                                           ├─ t_sled (需 t_pack_small)
                                           ├─ t_coat1 (需 t_bed) ── t_coat2*
                                           └─ t_bench3* ─┬─ t_suppressor* (需 t_melee)
                                                         ├─ t_traps*  (需 t_rat_trap；专属 dale)
                                                         ├─ t_coat2*  (需 t_coat1)
                                                         └─ t_car_repair* (需 G2 t_generator)

信号与电力 G
 G1: t_radio_fix ── t_antenna ──────────┬─ t_shortwave* (还需 t_generator；专属 linwei)
     t_bench2 ──── t_generator ─────────┼─ t_lamps
                                        ├─ t_battery_bank*
                                        └─ → K3 t_car_repair*

  * = 需要图纸      ★ 见 §4.2
```

---

## 5. 设施与家园

### 5.1 热量、燃料与成本总表

热输出为房间获得的**热功率**（W）。单位热成本 = 燃料 VP ÷ 热量 kWh，用来判断"烧什么最划算"（锚点：1 kWh = 3 VP）。

| 热源 | 热输出 | 燃料消耗 | 单位热成本 | 备注 |
|---|---|---|---|---|
| 简易灶（取暖用法：封火慢烧） | 600 W | 柴 0.4/h | 6.0 VP/kWh | 效率 ~50%；开局就有，白天做饭时额外 +400 W |
| 改良灶 | 750 W | 柴 0.4/h | 4.8 VP/kWh | 效率 ~63% |
| 电暖器（经发电机） | 800 W | 电 800 W → 汽油 0.33 L/h | 3.3 VP/kWh | 汽油 8 VP/L，发电机 ~2.6 kWh/L |
| 丙烷加热器 | 1800 W | 丙烷 0.25 罐/h | 3.1 VP/kWh | 不耗电；湿度 +0.8/h |
| 柴火炉（全火） | 2500 W | 柴 1.0/h（或煤 0.67/h） | 3.5 VP/kWh | 效率 85% |
| 柴火炉（压火） | 1000 W | 柴 0.4/h | 3.6 VP/kWh | |
| 人体 | 清醒 60 W / 睡眠 50 W / 搬运或劳作 80 W | — | — | 4 人一间房 = 240 W，相当于 0.3 台电暖器 |

结论：**灶取暖最贵、其余相近**，所以前三天（只有灶）烧得肉疼，推着玩家尽快封窗、修电暖器；之后各条路线价格相近，选择由供应（汽油 vs 柴）与副作用（烟、噪音、湿度）决定。

### 5.2 设施清单

| id | 名称 | 科技 | 建造 / 修复成本（≈VP） | 功率 / 燃料 | 热输出 | 湿度 | 损坏与维修 |
|---|---|---|---|---|---|---|---|
| f_hearth | 简易灶 | t_hearth | 开局自带；新建 scrap ×3 + planks ×1（9） | 见 §3.2 的燃料 | 600 W 取暖 / 做饭 +400 W | 做饭或煮水 +1.5/h | 无损坏 |
| f_hearth2 | 改良灶 | t_hearth2 | 升级 scrap ×6 + pipe ×2 + components ×1（26） | 燃料 ×0.7 | 750 W | 同上 | 无损坏 |
| f_snow_barrel | 融雪桶 | t_snow_melter | scrap ×4 + pipe ×1（12） | 4 L/h，柴 0.5/h | 300 W | +1.0/h | 无 |
| f_water_tank | 储水罐 | t_water_tank | scrap ×3 + planks ×2 + pipe ×2（20） | — | — | — | 容量 40 L 不占格；所在房间 < 0 °C 连续 6 小时冻结，> 2 °C 解冻 |
| f_filter | 净水器 | t_water_filter | pipe ×2 + cloth ×3 + components ×1 + filter_cartridge ×1（35） | 4 L/h | — | — | 滤芯寿命 40 L，用尽停机，换芯 12 VP |
| f_bench1 / 2 / 3 | 工作台 I / II / III | t_bench1 / 2 / 3 | 见 §4.2（34 / 70 / 119） | — | — | — | 无；三级台各占 2×1 格，须在室内 |
| f_electric_heater | 电暖器 | t_heater_repair | **修复** heater_parts ×2 + components ×1（38）；开局损坏 | 800 W 电 | 800 W | 干燥 −1.2/h | 状态值 100，运行时 −0.05/h；< 30 时每小时 2% 故障停机；0 = 损坏。小修：components ×1、20 分钟，+40 状态 |
| f_propane_heater | 丙烷加热器 | t_propane_heater | heater_parts ×2 + pipe ×2 + components ×2 + scrap ×2（56） | 丙烷 0.25 罐/h | 1800 W | +0.8/h | 状态值，−0.08/h；< 30 时每小时 3% 熄火；小修同上 |
| f_woodstove | 柴火炉 | t_wood_stove | scrap ×10 + pipe ×4 + components ×2 + duct_tape ×1（52） | 柴 1.0/h 或压火 0.4/h | 2500 / 1000 W | 干燥 −2.0/h | 烟囱每 72 小时需清（5 分钟，免费）；不清则热输出 −30%；**烟柱使夜袭概率 +3%/晚** |
| f_humidifier | 加湿器 | t_humidifier | **修复** humidifier_parts ×2 + components ×1（30） | 60 W 电；clean_water 1 个/10 小时 | — | +4.0/h，湿度 ≥ 60% 自动停 | 状态 −0.1/h，同电暖器 |
| f_generator | 发电机 | t_generator | **修复** generator_parts ×3 + components ×2（84） | 输出 3000 W；汽油 0.2 + 0.5 × 负载比 L/h | — | — | 状态 −0.1/h；< 30 时每小时 3% 熄火；**夜里运转噪音半径 30 格，夜袭概率 +4%/晚**；开局状态为 0（损坏），第一天靠灶 |
| f_battery_bank | 蓄电池组 | t_battery_bank | battery ×8 + electronics ×3 + wire ×4 + components ×3（121） | 容量 4000 Wh；充电效率 85% | — | — | 无；让发电机白天开、夜里静音 |
| f_radio | 收音机 | t_radio_fix | repair_radio（54） | 10 W | — | — | 无；预报精度见 §6.5.3 |
| f_antenna | 天线 | t_antenna | build_antenna（38） | 0 | — | — | 无 |
| f_shortwave | 短波电台 | t_shortwave | build_shortwave（106） | 25 W | — | — | 无 |
| f_lamp | 灯 | t_lamps | build_lamp（18） | 20 W | — | — | 光照 0.7，半径 6 格；夜里窗户封板则不漏光 |
| f_bed | 床铺 | t_bed | planks ×3 + cloth ×4（21） | — | — | — | 睡眠精力 +14/h（室温 ≥ 10 °C），否则 +9/h |
| f_crate / f_locker | 储物箱 / 储物柜 | t_clear_tools | planks ×4 + nails ×6（14）/ scrap ×6 + planks ×2 + nails ×6（20） | — | — | — | +16 格 / +30 格；locker 上锁，防"偷团队物资"的角色（sam）时撬锁难度 ×1.5 |
| f_tripwire | 绊线警报 | t_board_up | scrap ×1 + rope ×1（5） | — | — | — | 触发时噪音半径 14，唤醒睡眠者；被触发后需重置（2 分钟） |
| f_bear_trap | 捕兽夹（家园放置） | t_traps | 见 §3.4 | — | — | — | 伤害 25、定身 6 秒；一次性可回收 |
| 门 | 木门 | — | 开局即有 | — | — | — | 强度 60；加固 1 级 150、2 级 300 |
| 窗 | 窗 | — | — | — | — | — | 完好窗强度 20；破窗 0；封板 80；加固 160 |

### 5.3 房间与围护的导热系数

见 §6.2；这里补充"避寒小间"：6 格小房（2×3），只有一个门，整体导热 **G ≈ 10 W/°C**（外墙 10 格 × 2.0 × 0.5 × 0.8 = 8，屋顶地面 6 × 0.6 × 0.4 = 1.4，门 0.6），热容 72 Wh/°C。−48 °C 下保持 8 °C 只需约 320 W，一台电暖器或压火的柴火炉都绰绰有余；代价是 6 格里挤 4 人（心理 −0.5/h，拥挤）。

### 5.4 清理瓦砾与挖掘产出

每清理 1 格瓦砾（或挖 1 格雪堆）掷表一次：

| 产出 | 概率与数量 | 理由 |
|---|---|---|
| scrap | 100%：0–2 个（均值 1） | 废墟的基础产出 |
| planks | 40%：1 个 | 拆家具残片 |
| firewood | 20%：1 个 | 院子的断枝 |
| 食物发现 | 12%：随机 canned_beans 60% / canned_soup 25% / wild_roots ×2 15% | "瓦砾里挖出罐头"（GDD §1.5） |
| 其它发现 | 5%：cloth / components / bandage 各 1/3 | |

期望每格 ≈ 2 + 1.2 + 1.8 + 1.0 + 0.3 ≈ **6.3 VP**（含食物发现 0.12 × 8.4 ≈ 1 VP）；开局约 70 格瓦砾，全清理约 440 VP，用 8–20 分钟/格，需要约 15 个人·小时。这是第 1 幕"安顿"的主要免费收入（食物约 50 VP、柴约 120 VP；第 2、3 幕只剩雪堆挖掘，各约 20 / 30 VP），但绝大多数是废料，不解决吃饭问题（§10）。

### 5.5 夜袭与防御（建议值，供 M7/M9 对接）

| 项 | 数值 |
|---|---|
| 每晚家被袭概率 | 4% + 0.12% × 恶名（0–100）+ 烟柱 3% + 夜里发电机 4% + 上一次被抢后 2 天内 +6% |
| 防御分 DEF | Σ守夜者（10 + 武器加成：近战 +3、枪 +8）+ 门强度/20 + 窗封板数 × 2 + 绊线 8（只对"偷"型袭击） |
| 进攻分 ATK | 人数 × 10 + 武器 × 5；掠夺者 3–5 人 → 30–50；邻居饥民 2–3 人 → 20–30 |
| 判定 | ATK < DEF × 0.8 被击退；0.8 ≤ ATK/DEF < 1.2 对峙（进入家园实时战斗或威吓）；≥ 1.2 被突破，损失一批物资 |

理由：4 人家，1 人守夜 + 加固门（DEF ≈ 10 + 3 + 15 + 4 = 32）能拦下 2–3 人的饥民，但拦不住 5 人的掠夺者，这给"加固 + 多守夜 + 枪"留了投入产出。

---

## 6. 模拟常数（`data/balance.lua` 的内容）

### 6.1 需求衰减

单位：点/小时。状态按优先级取其一：**睡眠 > 外出（副本与路途）> 劳作 > 清醒闲置**。

| 属性 | 睡眠 | 清醒闲置 | 劳作 | 外出 | 一天合计（16 h 清醒 + 8 h 睡眠，劳作 8 h） | 推导 |
|---|---|---|---|---|---|---|
| 饱食 | −2 | −4 | −5 | −5.5 | −88 | 1 人·天 ≈ 90 点 = 30 VP（§10） |
| 水分 | −2 | −4 | −5 | −5 | −88 | 同上；1 L = 40 点，人均 2.2 L |
| 精力 | +14（床，室温 ≥ 10 °C）/ +9（其它）/ +7（冷 < 5 °C）；干燥（湿度 < 30）再 ×0.8 | −3 | −4 | −5 | 睡满 8 h 回满 | 日间劳作 13 h 耗 ≈ 52，夜间外出 8 h 耗 40：外出一晚后精力约 8，**不能连续两晚出门** |
| 精力（守夜） | — | −2.5（坐着守） | — | — | — | 守夜耗得少，但不回精力 |

数值变量（在 `balance.lua` 里是一张表，便于调优）：

| 变量 | 值 |
|---|---|
| 午睡（白天在床上） | 精力 +9/h，被视为睡眠状态 |
| 咖啡因 | 精力瞬时 +15/+12/+6（见物品表） |

阈值与惩罚：

| 属性 | 阈值 | 效果 |
|---|---|---|
| 饱食 | < 30 "饥饿" | 效率 ×0.9，心理压力条目"饿"（−0.5/h 累积，上限 −10） |
| | < 15 | 效率 ×0.8 |
| | = 0 "饿昏" | 效率 ×0.5；每持续 24 小时扣 hp：轻伤线 → 重伤线（−25 / 24 h），持续 72 小时濒死 |
| 水分 | < 30 "口渴" | 效率 ×0.9 |
| | < 15 | 效率 ×0.7 |
| | = 0 | 效率 ×0.4；每 12 小时 −25 hp，36 小时濒死 |
| 精力 | < 60 | 效率线性 1.0 → 0.8（60→30） |
| | < 30 | 0.8 → 0.5（30→10） |
| | < 10 "力竭" | 效率 ×0.4；每小时 20% 就地昏睡 30 分钟（副本里即被发现风险） |

### 6.2 温度与体温模型

#### 6.2.1 房间节点导热（`sim/thermal.lua`，1 分钟一步）

状态：每个房间一个温度 T；节点集合 = 室外（温度 = `weather.outdoor_temp`）+ 各房间。每个房间的热容 `C = 12 Wh/°C × 格数`（含家具与墙体）。

```
每分钟：
  Q_in  = Σ 热源功率(W) + 体热(Σ 房内人 W)
  Q_out = Σ_邻居 G_link × (T_room − T_nb) + G_env × (T_room − T_out)
  T_room += (Q_in − Q_out) / (C × 60)          -- W / (Wh/°C × 60 min) = °C/min
```

稳定性：G 最大约 100 W/°C，C 最小 72 Wh/°C，一步系数 ≤ 0.023，显式欧拉安全，不需要子步。

#### 6.2.2 导热系数（W/°C，每条**外墙边缘格**计一次；室内按边缘格和门计）

| 构件 | 系数 | 备注 |
|---|---|---|
| 完好外墙（每边缘格） | 2.0 | 老旧住宅墙 |
| 墙洞（破损） | 9.0 | 比墙 4.5 倍 |
| 完好窗 | 3.0 | |
| 破窗 | 7.0 | |
| 封板（窗洞或墙洞封上） | 3.0 | 钉板只挡风，不保温 |
| 外门，关 | 3.0 | |
| 外门，开 | 14.0 | 最大的漏点；有人出入后门保持开 1 分钟再自动关 |
| 屋顶 + 地面（每格） | 0.6 | 与室外耦合 |
| 保温层 I | 该房间的**外墙、封板、屋顶项 ×0.7** | 门窗不受影响 |
| 保温层 II | 同上 **×0.5** | |
| 避寒小间 | 在 II 之上再 ×0.8 | |
| 室内墙（每边缘格） | 0.5 | |
| 室内门，关 | 0.9 | 每扇 |
| 室内门，开 / 无门洞 | 7.0 | 每扇；"挤一间房"= 关上所有门 |
| 结霜（§6.3） | 保温层降一级 | |

推导：**墙洞 + 破窗 = 13–16 W/°C 的"漏点"**，一个破房间的 G 比封好的高 40–50%；保温层 I/II 把剩余的漏热再削 30%/50%。

热源与体热见 §5.1。有效温度 E 见 §6.2.3。

#### 6.2.3 体温（0–100）随环境变化

```
有效温度 E = T_local
           + 3                     -- 基础衣物
           + 穿戴加成（外套 +5 / 防寒大衣 +9 / 帽 +1.5 / 手套 +1.5 / 靴 +2，室内也算）
           + 2（睡眠且铺毯） + 热饭 +2（进食后 60 分钟内）
           − 风寒 5（室外且寒潮日 / 大寒潮）
           (T_local：室内取房间温度；副本室内取 室外 + 8（无供暖）；室外取室外温度)

每小时体温变化 dB（点/h）：
  E ≥ 18          : +15（回暖）
  10 ≤ E < 18     : +5
  E < 10          : −0.35 × (10 − E)
  体温限制在 [0, 100]
```

体温阈值与后果：

| 体温 | 状态 | 效果 |
|---|---|---|
| ≥ 60 | 正常 | — |
| < 60 | 冷 | 效率 ×0.9；感冒风险 ×2.5（§6.4） |
| < 40 | 很冷 | 效率 ×0.7；颤抖：潜行噪音 +20% |
| < 25 | 危险 | 效率 ×0.5；**冻伤触发**：每小时 15% |
| < 10 | 失温 | 效率 ×0.3；每小时 −10 hp |
| = 0 | 濒死线 | 视为重伤，hp 上限 40；持续 2 小时濒死 |
| 室外 E < −20 | 暴露 | 冻伤概率额外 +10%/h |

冻伤触发条件汇总：体温 < 25 持续 ≥ 30 分钟后每小时 15%，或室外 E < −20 额外 +10%/h。

#### 6.2.4 算例：开局破屋 + 一台电暖器 + 4 人挤一间房，室外 −15 °C

设定：起居室 20 格（C = 240 Wh/°C）；外墙边缘 9 格 = 完好墙 5 + 破窗 2 + 墙洞 1 + 外门（关）1；屋顶 + 地面 20 × 0.6；通向"其余房子"（80 格，同样破败，热容 960 Wh/°C，室外耦合 123 W/°C）的内墙与关着的门耦合 5.9 W/°C。电暖器已修好、已有电（800 W），4 人清醒（240 W）。

| 项 | 计算 | W/°C |
|---|---|---|
| 完好墙 5 格 | 5 × 2.0 | 10.0 |
| 破窗 2 + 墙洞 1 | 2 × 7 + 9 | 23.0 |
| 外门（关） | | 3.0 |
| 屋顶 + 地面 | 20 × 0.6 | 12.0 |
| 外围护小计 | | 48.0 |
| 经"其余房子"的串联耦合 | 5.9 × 123 / (5.9 + 123) | 5.6 |
| **等效 G** | | **53.6** |

稳态：`T = −15 + (800 + 240) / 53.6 = −15 + 19.4 ≈ +4.4 °C`。时间常数 C/G = 240 / 53.6 ≈ 4.5 小时，约 8 小时达 83%。

对人的后果：E = 4.4 + 3 = 7.4（醒着）→ dB = −0.35 × 2.6 ≈ −0.9/h，缓慢下降；穿外套（+5）后 E = 12.4，体温回升 +5/h。**结论：勉强不冻，但很不舒适**（心理"冷"条目），而且这时全队没有舒适的窗口，睡觉时室温 4 °C 精力只回 +7/h。逐级改造的效果（同一房间、同一电暖器 + 4 人、室外 −15 °C / −35 °C）：

| 状态 | G（W/°C） | 室温 −15 °C | 室温 −35 °C | 维持 8 °C 需要的加热器平均功率（−15 °C / −35 °C） | 每天热量（−15 °C） |
|---|---|---|---|---|---|
| 破屋（窗洞 + 墙洞敞开） | 53.6 | +4.4 | −15.6 | 993 W / 2066 W（超出一台） | 23.8 kWh |
| 封板 | 39.6 | +11.2 | −8.8 | 671 W / 1464 W | 16.1 kWh |
| 封板 + 保温 I | 30.3 | +19.3 | −0.7 | 458 W / 1064 W | 11.0 kWh |
| 封板 + 保温 II | 24.1 | +28.1 | +8.1 | 315 W / 798 W（一台电暖器够） | 7.6 kWh |

说明：①"维持 8 °C"是 §10 的"最低线"——E = 8 + 3 = 11，体温不掉；②表里的功率已扣除 4 人体热 240 W；③−35 °C 在保温 II 房间里仍要 800 W 持续供暖，**一台电暖器只是刚好**；大寒潮（−48 °C）下同一房间要 (8 + 48) × 24.1 − 240 ≈ 1110 W（约 9 柴/天 = 80 VP/天），要换柴火炉（2500 W 全火或 1000 W 压火 + 电暖器），或进避寒小间（§5.3，仅需约 320 W）；④电暖器需要发电机在转，发电机在夜里噪音 30 格 +4% 夜袭——这是"电暖器 vs 柴火炉 vs 丙烷"之间的真实取舍。

### 6.3 湿度模型（全屋一个值 H，0–100）

```
每小时：
  dH = −0.06 × (H − 25)                     -- 向室外干燥空气（25%）回归
       + 0.5 × 在家人数
       + Σ 设施：电暖器 −1.2，柴火炉 −2.0，丙烷 +0.8，灶（做饭/煮水中）+1.5，融雪桶 +1.0，加湿器 +4.0（H ≥ 60 自停）
H 限制在 [10, 100]；开局 H = 45
```

算例：4 人 + 电暖器：dH = −0.06 × (H − 25) + 2.0 − 1.2 = 0 → H = 38.3，略干；加柴火炉：H → 25；加加湿器（+4）后到 60 自停。

| 区间 | 效果 |
|---|---|
| 40–60 | 理想：无修正 |
| < 40 | 感冒概率 × (1 + (40 − H) / 20)（H = 20 时 ×2）；H < 30 睡眠精力恢复 ×0.8 |
| 60–70 | 无修正 |
| > 70 且房间 < 5 °C | 结霜：保温层状态每小时 −1.5%，降到 50% 时保温等级降一级；晾干后恢复 |

疾病概率曲线见 §6.4 感冒项。

### 6.4 伤势、疾病、效率

#### 6.4.1 伤势三级（隐藏 `hp` 0–100，满值 100）

| 等级 | hp 区间 | 速度 | 载重 | 效率 | 自然愈合 | 备注 |
|---|---|---|---|---|---|---|
| 健康 | > 80 | ×1 | ×1 | ×1 | 回满 +1.5/h（饱食、水分 > 30 且休息） | |
| 轻伤 | 41–80 | ×0.9 | ×0.9 | ×0.9 | +1.1/h（约 36 小时回到健康线）；绷带 ×2（12 小时） | 单次伤害 −25 |
| 重伤 | 11–40 | ×0.6，不能跑 | ×0.6 | ×0.5 | +0.4/h（约 4 天）；2 条绷带 +1.2/h（24 小时） | 单次伤害 −50；每天 15% 感染恶化（消毒液 −50%） |
| 濒死 | 1–10 | 倒地 | — | 0 | 失血 −6.7 hp/h（**90 分钟窗口**）；绷带 / 急救包稳住后 +1.0/h 到 11 | 副本内倒地 = 现实 90 秒（1 秒 = 1 分钟）窗口，可暂停下指令（GDD §1.10） |
| 死亡 | 0 | — | — | — | — | 永久 |

迟归惩罚（GDD §1.3）：到家晚于 05:00 L 分钟，hp −min(70, 15 + 0.2 × L)，精力清零，并有 12% + 0.1% × L 概率触发路遇巡逻片段。理由：晚 1 小时 −27（轻伤），晚 4 小时封顶 −70（重伤线附近），宁可放弃最后一个容器。

#### 6.4.2 疾病

| 疾病 | 触发 | 病程 | 治疗 | 效果 |
|---|---|---|---|---|
| 感冒 | 每小时概率 = 0.12% × f_干 × f_湿 × f_冷 × f_特质，加同房间每名病人 +1%/h 传染 | 72 小时 | cold_medicine：病程 36 小时，24 小时内不转肺炎；休息 + 保暖 | 效率 ×0.85，速度 ×0.95，心理 −3 |
| 肺炎 | 感冒期间每天 4% + 8%（过去 24 小时体温 < 50 超过 4 小时）+ 6%（H < 30）；上限 20% | 8 天；每天 −6 hp | antibiotics ×3（每天 1 剂，3 天治愈，elena 2 剂）；室温 ≥ 15 °C + 清水可自愈但 8 天 | 效率 ×0.5，速度 ×0.8，载重 ×0.7，不能跑；约第 5 天从轻伤降到重伤 |
| 冻伤 | §6.2.3 | 6 天 | 房间 ≥ 12 °C + bandage ×1；消毒液 → 3 天 | 效率 ×0.8，速度 ×0.85；72 小时未治疗 → hp 上限 40（重伤） |
| 食物中毒 | 生肉 35%、生鱼 25%、鼠肉 45%、融雪水 20%、变质食物 50%、私酿酒每份 3% | 24 小时 | 2 份 clean_water → 12 小时；elena ×0.75 | 额外每小时饱食 −2、水分 −3，效率 ×0.6，速度 ×0.9；呕吐丢掉当前一餐 |

感冒各因子：

| 因子 | 取值 |
|---|---|
| f_干 | 1 + max(0, 40 − H) / 20 |
| f_湿 | H > 70 且房间 < 10 °C 时 1 + (H − 70) / 30，否则 1 |
| f_冷 | 体温 < 60 时 2.5，睡在 < 5 °C 房间 ×1.5，否则 1 |
| f_特质 | walt ×1.6，linwei ×1.3，其余 ×1 |

基线：4 人 30 天约 3.4 次感冒（0.12% × 24 × 30 × 4 ≈ 3.5），冷屋或干空气下翻 2–3 倍，所以保暖与加湿是"防病"的主要手段；约 25% 的感冒转肺炎对应一支抗生素的预算（§9.2）。

#### 6.4.3 工作效率乘数

最终效率 = 基础 × 特长 × 伤病 × 心理 × 精力 × 体温 × 饥渴：

| 因子 | 取值 |
|---|---|
| 特长 | 见下表；无特长 1.0 |
| 伤势 | 轻伤 0.9 / 重伤 0.5 / 濒死 0；疾病 §6.4.2；多重取**最小**一项再乘 0.9（不无限叠乘） |
| 心理状态 | 稳定 1.0 / 动摇 0.95 / 低落 0.8 / 抑郁 0.6 / 崩溃 0（NARRATIVE §2.6） |
| 精力 | §6.1 |
| 体温 | §6.2.3 |
| 饥渴 | §6.1，取饱食与水分中较小者 |
| 止痛药 | 8 小时内伤病惩罚减半 |
| 工作台 | 台 II ×1.15，台 III ×1.3 |

角色特长与缺点（`data/characters.lua` 的数值部分，叙事字段见 WORLD §3）：

| 角色 | 特长数值 | 缺点数值 |
|---|---|---|
| marcus | 修加热器/加湿器/发电机/丙烷：工时 ×0.6、料 ×0.75 | 烟瘾：> 24 小时无烟，心理压力"戒断"−8/天；有烟时抽 1 份恢复 |
| elena | 治疗效果 ×1.5；抗生素疗程 2 剂；护理病程 ×0.65；绷带产 +1 | 良知极重：价值观参数（WORLD §2），心理"团队伤害他人"权重 ×1.4 |
| junho | 做饭产 +1、燃料 ×0.7、水 ×0.8；煮水燃料 ×0.7 | 酒精依赖：> 24 小时无酒，"戒断"−6/天；喝时 +8 |
| linwei | 电器/无线电工时 ×0.6、料 ×0.75；预报误差 ×0.5，提前量 +1 天 | 体弱：体温下降速度 ×1.3；近战伤害 ×0.6；载重 13 kg |
| dale | 枪械命中 +10%；陷阱工时 ×0.7；载重 20 kg | 暴躁：心理 < 动摇时，由他谈判有 12% 谈崩 |
| tasha | 移速 ×1.2；脚步噪音半径 ×0.8；跑动体力消耗 ×0.8 | 载重 11 kg；杀人心理伤害 ×2 |
| walt | 建造/加固/木工工时 ×0.7、料 ×0.8 | 移速 ×0.8；疾病概率 ×1.6；载重 12 kg |
| priya | 买卖价差 ×0.7；哨站交涉 +1 档（§8） | 饥饿/寒冷压力累积速度 ×1.5 |
| sam | 撬锁工时 ×0.5、撬锁噪音 ×0.5；潜行噪音 ×0.8；自带 lockpick（不占格） | 队友关系起点 −10；绝境（饱食 < 15 且队伍食物 < 1 天）时 10%/天偷团队物资 |
| grace | 近战伤害 ×1.25；枪命中 +15%；武器修理工时 ×0.6 | 枪声 20% 僵住 3 秒；每晚 10% 噩梦（精力恢复 ×0.7） |

#### 6.4.4 心理状态阈值（需求相关部分）

心理值与条目的叙事规则见 NARRATIVE §2.6；这里只给**数值阈值和需求类条目的量**：

| 边界 | 下行阈值（心理值 <） | 回升阈值（≥） | 预警 |
|---|---|---|---|
| 稳定 ↔ 动摇 | 60 | 65 | 角色台词提示 |
| 动摇 ↔ 低落 | 45 | 50 | 至少 1 天的明显预警 |
| 低落 ↔ 抑郁 | 28 | 33 | 同上 |
| 抑郁 ↔ 崩溃 | 10 | 15 | 触发危机片段；回升靠干预 |

回升阈值比下行阈值高 5 点（滞回，避免来回抖动）。需求类条目：饿（上限 −10）、冷（房间 < 8 °C：−0.8/h，上限 −12）、脏水/生病（−3，到病愈）、热饭（+3，6 小时）、温暖房间（房间 ≥ 16 °C：+0.5/h，上限 +6）。

### 6.5 天气与寒潮（`data/weather.lua`）

#### 6.5.1 常态

```
每天均值 μ_d = −15 + N(0, 2.5)，截断到 [−20, −10]
昼夜 T(h) = μ_d + 3 × cos(2π × (h − 14) / 24)   -- 14:00 最暖，02:00 最冷（振幅 3）
```

常态室外 −10 至 −20 °C（GDD §1.1：−15 上下）；夜里外出常态 E ≈ −18 + 3 + 5（外套）= −10 → 体温约 −7/h。

#### 6.5.2 寒潮日程

| 寒潮 | 开始日 | 出现概率 | 持续（含升降） | 核心温度 | 强度档 |
|---|---|---|---|---|---|
| 小寒潮 1 | 6–9 随机 | 100% | 3 天 | −30 | 1（60%）/ 2（40%） |
| 小寒潮 2 | 13–17 随机，且 ≥ 寒潮 1 结束 + 3 天 | 100% | 3–4 天 | −30 / −35 / −40 | 1（30%）/ 2（50%）/ 3（20%） |
| 小寒潮 3 | 21–24 随机，且 ≥ 寒潮 2 结束 + 3 天 | 60% | 4 天 | −35 / −40 | 2（40%）/ 3（60%） |
| 大寒潮 | 28 | 100% | 28–30 及以后 | −48 / −50 | 4 |

强度档对应核心温度：1 = −30，2 = −35，3 = −40，各 ±2（均匀）。形状（日均值 μ）：升温日 −24，核心日取强度值，收尾日 −26；4 天的寒潮有两个核心日。大寒潮：第 28 天 −35，第 29 天 −48（±3），第 30 天 −50（±3）。大寒潮日 E 另加风寒 −5。

对 PLAN §4.4 `weather.snaps = { start_day, days, severity, announced }`：`severity` ∈ 1..4（4 = 大寒潮），其余字段不变；建议加 `ramp` 由代码按上面形状生成（见 §11 第 1 条）。

#### 6.5.3 无线电预报（`weather.forecast`）

| 无线电等级 | 提前量 | 开始日误差 | 强度误差 | 漏报 |
|---|---|---|---|---|
| 0（未修） | 无 | — | — | — |
| 1（收音机） | 1 天 | 精确 80%，±1 天 20% | 强度档精确 55%，±1 档 45% | 15% |
| 2（天线） | 3 天 | 精确 70%，±1 天 30% | 精确 70% | 5% |
| 3（短波） | 5 天 | 精确 90% | 精确 85% | 0% |

linwei 在队：误差概率 ×0.5，提前量 +1 天（仅 2 级以上）。大寒潮例外：**第 24 天起全国广播预警**，等级 ≥ 1 的收音机都能得知，理由：这是主线节拍，不应被漏报。商贩行程在天线（2 级）以上可预知（GDD §1.7）。

---

## 7. 潜行与战斗数值（`sim/raid_rules.lua` 的纯函数输入）

### 7.1 移动速度（格/秒，副本内；1 格 = 1 米）

| 状态 | 玩家 | 说明 |
|---|---|---|
| 走 | 2.6 | |
| 潜行 | 1.4 | 蹲伏 |
| 跑 | 4.4 | 精力消耗 ×1.5 |
| NPC 巡逻 | 1.8 | |
| NPC 追击 | 3.6 | 掠夺者 / 士兵；平民逃跑 3.2 |

角色修正：tasha ×1.2，walt ×0.8，伤势见 §6.4.1，超重见 §1.3。

### 7.2 噪音半径（格，传播代价上限）

| 行为 | 雪地 | 水泥 / 瓷砖 | 木地板 | 碎玻璃 |
|---|---|---|---|---|
| 走 | 4 | 6 | 8 | 12 |
| 潜行 | 1.5 | 2.5 | 3.5 | 6 |
| 跑 | 9 | 12 | 15 | 18 |

修正：载重 > 80% ×1.2；颤抖（体温 < 40）×1.2；tasha ×0.8（走与跑）；sam ×0.8；snow_boots 在雪地 ×0.9。

| 行为 | 半径 | 备注 |
|---|---|---|
| 撬锁 | 2（持续） | 安静但慢：每把锁 8–20 秒（锁难度 1–3）；sam ×0.5 时间、×0.5 噪音；lockpick 耐久 −1，失败不折断 |
| 撬棍破门 | 14（起手和断裂各一次） | 快（2 秒）但响 |
| 搜刮容器 | 3（持续）；金属柜 5 | 每个容器 6–15 秒，有进度条 |
| 开门 | 2 | 生锈门 5 |
| 打碎窗 | 16 | |
| 拳 / 小刀 / 棍、撬棍、斧 的打击 | 8 / 4 / 10 / 10 / 10 | 每次命中一个脉冲 |
| 背后制服 | 3 | |
| 倒地 | 3 | |
| 手枪 / 霰弹枪 / 猎枪 | 60 / 80 / 90 | 覆盖整张图（地图 ≤ 64×64）：全员进入"警觉" |
| 消音手枪 | 25 | 60 发后消音失效 |
| 枪声的"确切位置"半径 | 20 / 25 / 30 / 消音 12 | 超出这个半径只知"有枪声"（警觉，不知方位） |
| 发电机 | 30（持续，家园） | §5.2 |
| 绊线 / 呼救 | 14 / 20 | |

**墙体衰减**：噪音按路径代价传播（`sim/raid_rules.lua`），沿最短路径累加：每格 1；穿过墙格 +4；关着的门 +2.5；完好窗 +1.5；破窗与开着的门 +0。NPC 听到的条件：代价 ≤ 半径 × 听力系数，听力：清醒 1.0、睡眠 0.45、警觉 1.3。睡眠者被噪音唤醒：累积"唤醒量" += (1 − 代价/半径)，≥ 0.6 醒来。

### 7.3 视觉与光照

光照 `light_level`（0..1）取值：

| 场景 | light_level |
|---|---|
| 白天室外 | 1.0 |
| 白天室内 | 0.7 |
| 夜间室外 | 0.12（雪地反光，晴夜 +0.10） |
| 夜间室内无灯 | 0.05 |
| 灯 / 炉火附近 | 0.7 / 0.6 |
| 手电（锥形，射程 8 格） | +0.5（上限 1.0），**同时**使开手电者的"被发现"系数 ×1.5 |

NPC 视锥（`ai/perception.lua`，10 Hz）：

| 状态 | 半径（格） | 半角 |
|---|---|---|
| 日常（白天） | 12 | 55° |
| 日常（夜晚） | 7 | 50° |
| 警觉（半径 ×1.25，半角 +15°） | 白天 15 / 夜晚 8.75 | 70° / 65° |
| 睡眠 | 0 | — |
| 近身觉察（任何状态，全向） | 1.5 | 360° |

被发现的"觉察值" `meter`（0..1，随时间累积）：

```lua
-- 玩家被某 NPC 看到的每秒觉察增量（sim/raid_rules.lua，纯函数）
function awareness_rate(npc_R, angle_ok, dist, light_level, stance, flashlight)
  local light = clamp(light_level + (flashlight and 0.5 or 0), 0, 1)
  local R     = npc_R * (0.5 + 0.5 * light)             -- 光暗改变有效视距
  if not angle_ok or dist >= R then return 0 end          -- angle_ok：在视锥内且视线通畅
  local dist_f = 1 - (dist / R) ^ 2
  local stance_f = ({ still_crouch = 0.35, sneak = 0.5, walk = 1.0, run = 1.5 })[stance]
  local fl = flashlight and 1.5 or 1.0
  return 1.2 * dist_f * (0.25 + 0.75 * light) * stance_f * fl   -- 单位：1/秒
end
-- meter += rate * dt；无任何 NPC 看到则 meter -= 0.25 * dt；
-- meter ≥ 0.4 → 起疑；≥ 0.7 → 警觉；≥ 1.0 → 发现（敌对 / 恐惧）
```

示例（夜晚，NPC 日常半径 7；"有效视距"= 7 × (0.5 + 0.5 × light)）：

| 场景 | light | 有效视距 | 距离 | 姿态 | rate（/秒） | 到 1.0 所需 |
|---|---|---|---|---|---|---|
| 黑处走过 | 0.12 | 3.9 | 3 | 走 | 0.17 | 5.9 秒（实际多半只起疑：meter 过 0.4 后离开视线即衰减） |
| 黑处潜行 | 0.12 | 3.9 | 3 | 潜行 | 0.08 | 11.8 秒 |
| 灯下走过 | 0.7 | 6.0 | 4 | 走 | 0.51 | 2.0 秒 |
| 灯下潜行 | 0.7 | 6.0 | 4 | 潜行 | 0.25 | 3.9 秒 |
| 黑处开手电潜行 | 0.62 | 5.7 | 5 | 潜行 | 0.14 | 7.0 秒（不开手电时 5 格外根本看不见） |
| 黑处蹲伏不动 | 0.12 | 3.9 | 2 | 蹲伏 | 0.11 | 9.5 秒（NPC 站在 2 格内盯着也躲不住） |
| 灯下奔跑 | 0.7 | 6.0 | 3 | 跑 | 1.04 | 1.0 秒 |

理由：黑处只靠潜行就能与巡逻者擦肩而过（有效视距仅 3.9 格），灯与手电才是"潜行的代价"，体现 GDD §1.9"手电会暴露自己"；奔跑几乎等于自首。

### 7.4 NPC 状态机计时与阈值

| 状态 | 进入条件 | 行为与计时 | 退出 |
|---|---|---|---|
| 日常 / 睡眠 | 默认 | 巡逻或睡眠；睡眠者唤醒量 ≥ 0.6 → 起疑 | |
| 起疑 | meter ≥ 0.4，或听到噪音（不知方位） | 转头 2 秒；走向声源 / 最后目击位置，到后停留 6 秒 | 10 秒无新刺激 → 日常 |
| 警觉 | meter ≥ 0.7；或发现门被撬、尸体、被搜空的容器；或 30 秒内第二次起疑 | 搜索 25 秒（半径 8 格绕最后位置）；视锥 ×1.25；警觉共持续 45 秒，有新刺激重置 | 45 秒后降为起疑，再 20 秒 → 日常 |
| 敌对（掠夺者、士兵、被攻击的平民） | meter ≥ 1.0 或被攻击 | 追击；呼援（14 格、2 秒延迟）；近战距离 1.2 格 | 6 秒无视线 → 搜索 15 秒 → 警觉 |
| 恐惧（平民，meter ≥ 1.0 且对方持械或人多） | | 掷骰：逃跑 40%（3.2 格/秒，去最近出口 / 邻居）、躲藏 25%、求饶 15%、呼救 20%（噪音 20 格，3 秒，唤醒同建筑的人） | 脱离视线 20 秒 → 警觉 |

威吓判定（亮武器，平民；`sim/raid_rules.lua: intimidate`）：

```
p_obey = clamp(0.35 + 0.35 × 威胁值 + 0.2 × [背后或多人] − 0.3 × 勇气 − 0.15 × [NPC 持械], 0.05, 0.95)
威胁值：拳 0 / 小刀 0.4 / 棍 0.5 / 斧 0.7 / 手枪 1.0 / 猎枪 1.0 / 霰弹枪 1.2
勇气：平民 0.2 / 老人 0.1 / 掠夺者 0.7 / 士兵 0.6
```

典型：手枪对平民 = 0.35 + 0.35 − 0.06 = 0.64；顺从后给出一件"愿意交出的东西"（价值 ≤ 其储存的 20%）。

### 7.5 武器

| 武器 | 伤害 | 攻击间隔（秒） | 射程（格） | 噪音 | 耐久 | 备注 |
|---|---|---|---|---|---|---|
| 拳 | 6 | 0.5 | 1.0 | 8 | ∞ | |
| 小刀 | 14 | 0.45 | 1.1 | 4 | 80 次 | 背后一击必杀（无声 3） |
| 球棒 | 18 | 0.8 | 1.4 | 10 | 60 次 | 可打晕 |
| 撬棍 | 16 | 0.7 | 1.4 | 10 | 120 次 | 兼作工具 |
| 斧头 | 28 | 1.1 | 1.5 | 10 | 70 次 | |
| 手枪 | 30 | 0.6 | 12 | 60 | 150 发 | 弹匣 8 |
| 霰弹枪 | 55（≤ 4 格）/ 40（5–7）/ 20（≥ 8） | 1.3 | 10 | 80 | 100 发 | 弹匣 2 |
| 猎枪 | 60 | 1.7 | 25 | 90 | 120 发 | 弹匣 4 |
| 捕兽夹 | 25 | — | 触发 | 3 | 一次性 | 定身 6 秒 |

命中率（远程）：`p = clamp(0.92 − k × max(0, d − 3) − 0.15×[自己移动] − 0.1×[目标蹲伏] + 特长, 0.1, 0.95)`，k：手枪 0.035、霰弹枪 0.06、猎枪 0.015；特长：dale +0.10、grace +0.15。近战：对未察觉目标 100%，否则 85%。

NPC 生命值：老人 25 / 平民 40 / 掠夺者 60 / 士兵 80。致命武器 hp ≤ 0 即死；钝器（球棒、拳）使 hp ≤ 25% 者昏迷 120 秒。背后制服：1.2 秒内、1 格内、目标未察觉：小刀可杀，球棒 / 拳打晕（成功率 85% / 60%）。

对角色的伤势判定：`hp_new = hp − D × (1 − 减伤)`，减伤：防寒大衣对近战 10%；单次伤害 ≥ 45 时 25% 概率直接 hp = min(hp, 40)（重伤）。伤势等级见 §6.4.1。

---

## 8. 交易

### 8.1 价值点规则

- **锚点**：饱食 3 点 = 1 VP；水 1 L = 4 VP；热能 1 kWh = 3 VP；其余物品见 §2 表。
- 基础 VP 是**静态**的；天数调整在交易时乘 `day_adj`（§8.3），不改物品表。
- 价值只在交易与预算里使用，玩家界面不显示 VP，只显示"对方愿不愿意换"和差额提示（GDD §1.7）。

### 8.2 买卖价差

玩家买入价 = VP × (1 + s)；玩家卖出价 = VP × (1 − s)。一次"往返"（卖出再买回等价物）只剩 `(1 − s)/(1 + s)`。`s` 的构成：

```
s = s_商贩 + s_声望 + s_谈判者，下限 0.08，上限 0.60
```

| 商贩类型 | s_商贩 | 备注 |
|---|---|---|
| 流动商贩 wandering_trader | 0.25 | 货全，公平 |
| 教堂互助会 church_aid | 0.15 | 只卖必需品；不收武器酒类 |
| 平民住户 household | 0.35 | 不缺的才换，缺的拒绝 |
| 拖车集市 trailer_market（掠夺者背景） | 0.40 | 什么都收（赃物 ×0.6），什么都卖 |
| 哨站军士 sgt_pike | 0.45 | 要礼物，不守信（WORLD §7） |
| 哨站中尉 lt_marsh | 0.20 | 只按配给，需声望 |
| 农场主 farmer | 0.25 | 食物多，缺燃料与零件 |

| 声望档（−100..+100，WORLD R4） | s_声望 | 行为 |
|---|---|---|
| 敌对 −100..−60 | — | 拒绝交易，驱赶 |
| 戒备 −59..−20 | +0.10 | |
| 中立 −19..19 | 0 | |
| 友好 20..59 | −0.05 | |
| 盟友 60..100 | −0.10 | 并可能主动给 |

| 谈判者 | s 修正 |
|---|---|
| priya | s × 0.7（先算总和再乘）；哨站声望判定 +1 档 |
| dale | 心理 < 动摇时 12% 概率谈崩（对方离开，当天不再交易） |
| 其余 | 0 |

### 8.3 价值随天数上涨

`day_adj(d) = 1 + k × (d − 1)`，`d` 为第几天；对**买卖两方向都生效**（上涨意味着你持有的奢侈品和药品越晚越值钱，缺的越贵）：

| 类别 | k | 第 10 / 20 / 30 天 |
|---|---|---|
| 奢侈品 | 0.030 | ×1.27 / ×1.57 / ×1.87 |
| 药品 | 0.020 | ×1.18 / ×1.38 / ×1.58 |
| 燃料 | 0.012（寒潮期间额外 +25%） | ×1.11 / ×1.23 / ×1.35 |
| 食物 | 0.010 | ×1.09 / ×1.19 / ×1.29 |
| 其余 | 0 | ×1 |

### 8.4 商贩库存模板

库存总值为 VP 基础值；每 3 天（教堂每 5 天）补货至模板值 ±15%。比例是**类别占比**，具体品种按 §9.4 品种表抽。

| 商贩 | 库存总值 | 食物 | 水 | 燃料 | 零件 | 药品 | 奢侈 | 武器弹药 | 收购偏好（s 再 −0.05） |
|---|---|---|---|---|---|---|---|---|---|
| wandering_trader | 250 | 25% | 5% | 15% | 20% | 15% | 15% | 5% | 奢侈品、药品、电子元件 |
| church_aid | 180 | 45% | 20% | 10% | 10% | 15% | 0 | 0 | 柴、布料、药品（捐赠） |
| household | 40–120（随 `food_days`） | 60% | 10% | 10% | 10% | 10% | 0 | 0 | 食物以外的需要的东西 |
| trailer_market | 400 | 20% | 5% | 15% | 20% | 10% | 15% | 15% | 任何；赃物 ×0.6 |
| sgt_pike | 300 | 5% | 0 | 20% | 0 | 20% | 10% | 45% | whiskey、cigarettes、gasoline、把柄 |
| lt_marsh | 200（配给） | 40% | 20% | 20% | 0 | 20% | 0 | 0 | gasoline、药品 |
| farmer | 220 | 65% | 5% | 5% | 10% | 0 | 10% | 5% | 燃料、零件、药品 |

**哨站庇护"代价包"**（WORLD §7.2）：1 个代价包 = gasoline ×10 + antibiotics ×2 + whiskey ×1（80 + 36 + 28 = **144 VP**），每包多 1 个名额；军士的"礼物"= whiskey ×2 + gasoline ×5（96 VP）。理由：名额价格约等于 1 人 5 天的消耗（30 VP × 5 = 150），让"全员入内"昂贵但可行。

---

## 9. 战利品预算制

### 9.1 目标与换算

GDD §1.8：每幕每类资源有总预算；生成器先抽地点，再按"类型权重 × 危险度"分配到容器，校验每幕每类总量落在目标的 ±10% 内，不合格就重抽。

**预算单位 = 价值点（VP）**，换算到"人·天"：

| 类别 | 内容（按 §2 的标签折算） | 1 人·天 = |
|---|---|---|
| food | `food_any` + `food_raw` + `food_ingredient` | 30 VP（90 饱食） |
| water | `water_any`（瓶装与净水，不含融雪） | 9 VP（2.2 L） |
| fuel | `fuel_any` | 6.3 VP（2.1 kWh，供暖 + 烧水 + 做饭的人均份额）|
| parts | `parts_any` + `tool_any` + `wear_any` + 背包 + 雪橇 + 毯子（含科技研究与修理消耗） | — |
| meds | `med_any` | — |
| luxury | `luxury_any` | — |
| weapons | `weapon_any`（含 suppressor、bear_trap）+ `ammo_any` | — |

不计入预算：剧情物品、图纸（§4.3）、`keepsake`、住户小模拟里的"原有存粮"以外的 NPC 物品。

### 9.2 每幕每类总预算（普通难度）

"总预算"= 该幕所有已解锁地点里**能找到的总量**；玩家实际拿到的比例约 **60%**（谨慎型机器人目标，§10 推演）。

| 类别（VP） | 第 1 幕（1–10 天） | 第 2 幕（11–20 天） | 第 3 幕（21–30 天） | 合计 |
|---|---|---|---|---|
| food | 1600 | 1950 | 1950 | 5500 |
| water | 120 | 100 | 100 | 320 |
| fuel | 900 | 800 | 1000 | 2700 |
| parts | 1100 | 1050 | 850 | 3000 |
| meds | 220 | 260 | 300 | 780 |
| luxury | 200 | 260 | 300 | 760 |
| weapons | 100 | 200 | 260 | 560 |
| **合计** | **4240** | **4620** | **4760** | **13620** |

推导：

- **food**：目标"第 10 天存粮 ≈ 2.3 天、第 20 天 ≈ 2.2 天、第 30 天 ≈ 2.5 天"，全队 120 VP/天 + 开局 480 VP，按 60% 实收反推（§10.3）。第 2、3 幕预算更大，因为近处地点被拿空/被抢，**可拿的总量其实在增加，但分布在更危险、更远的地方**（§9.3 的危险度倾斜）。
- **fuel**：前期供暖贵（§10.1：前 3 天每天 ≈ 78 VP 燃料），保温 I/II 建成后降到 43–53，第 3 幕为大寒潮上调；第 2 幕预算低 = 玩家已把房子改造好。
- **parts**：科技研究 800–900 VP + 设施建造约 500 + 装备（外套、背包、靴）约 250 + 修理与杂项约 250 ≈ 1800 VP；3000 × 60% = 1800，所以零件类是"够用但要选"的类别，研究占实收约 47%。
- **meds**：4 人 30 天约 4 次伤病、1 次肺炎，需求约 400 VP；总预算 780 × 60% ≈ 470，另有交易溢价储备。
- **luxury** 与 **weapons**：不是生存必需，是交易筹码与风险偏好选择，预算小；luxury 随天数升值（§8.3），后期预算更大。

### 9.3 地点原型：类型权重、危险度、容量与解锁

权重 0–5（该类别的相对占比，0 = 不出）。**危险度系数 D = 0.8 + 0.2 × 夜袭难度**（WORLD §6.1 的 1–5）。"容量上限"= 该地点单幕最多承载的总 VP（所有类别合计；防止一个地点吞掉大半预算，取单幕预算的 6%–28%）。单程与解锁日取自 WORLD §1.3（`travel_min`，往返加倍）。

| 地点 id | 夜袭难度 | D | 容量上限（VP/幕） | 单程 min | 解锁日 | food | water | fuel | parts | meds | luxury | weapons |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| supermarket | 3 | 1.4 | 900 | 25 | 2 | 5 | 4 | 0 | 1 | 1 | 3 | 0 |
| pharmacy | 2 | 1.2 | 450 | 20 | 1 | 1 | 1 | 0 | 0 | 5 | 2 | 0 |
| gas_station | 2 | 1.2 | 550 | 40 | 5 | 2 | 2 | 5 | 2 | 0 | 3 | 0 |
| hardware_store | 2 | 1.2 | 650 | 25 | 2 | 0 | 1 | 2 | 5 | 0 | 0 | 1 |
| suburb_house | 2 | 1.2 | 450 | 10 | 1 | 3 | 2 | 2 | 1 | 2 | 2 | 1 |
| elder_house | 1 | 1.0 | 280 | 8 | 1 | 2 | 1 | 1 | 1 | 3 | 2 | 1 |
| church | 4 | 1.6 | 550 | 30 | 3 | 3 | 3 | 1 | 0 | 2 | 1 | 0 |
| school | 3 | 1.4 | 550 | 45 | 4 | 2 | 1 | 1 | 2 | 2 | 1 | 0 |
| clinic | 3 | 1.4 | 550 | 35 | 4 | 0 | 1 | 0 | 1 | 5 | 0 | 0 |
| warehouse | 5 | 1.8 | 1000 | 70 | 9 | 3 | 2 | 3 | 3 | 2 | 3 | 4 |
| farm | 3 | 1.4 | 850 | 110 | 12 | 5 | 1 | 3 | 1 | 0 | 2 | 2 |
| radio_tower | 3 | 1.4 | 450 | 120 | 线索 | 0 | 0 | 2 | 4 | 0 | 0 | 0 |
| motel | 3 | 1.4 | 550 | 90 | 10 | 2 | 2 | 1 | 1 | 1 | 3 | 1 |
| trailer_market | 3 | 1.4 | 750 | 60 | 6 | 3 | 2 | 3 | 3 | 3 | 4 | 2 |
| construction_site | 3 | 1.4 | 650 | 55 | 8 | 0 | 0 | 4 | 5 | 0 | 0 | 1 |
| police_station | 4 | 1.6 | 650 | 40 | 6 | 1 | 1 | 1 | 1 | 2 | 1 | 5 |
| river_dock | 2 | 1.2 | 550 | 50 | 7 | 3 | 1 | 4 | 3 | 0 | 1 | 1 |
| checkpoint_kilo | 5 | 1.8 | 1300 | 65 | 11 | 5 | 4 | 5 | 4 | 5 | 4 | 5 |

补充：

- 世界生成每局从 18 个里选 12–14 个入池（GDD §1.8）：**必含** checkpoint_kilo；**至少含** 1 个食物来源（supermarket / farm / church 之一）、1 个药品来源（pharmacy / clinic 之一）、1 个燃料来源（gas_station / construction_site / river_dock / warehouse 之一）、1 个武器来源（police_station / warehouse 之一）；其余随机。"开局开放"的前 3 个必为解锁日 = 1 的（pharmacy / suburb_house / elder_house，按 WORLD §1.3）。
- 不入池的地点不参与分配，预算按入池地点重新归一，所以**每幕每类总量对种子保持恒定**。入池后做**容量预检**：每幕 Σ(容量上限 × avail) ≥ 1.15 × 该幕总预算，且每类至少有 3 个 weight ≥ 2 的可用地点；否则重抽入池（基线推演：13 个地点入池时第 1 幕容量约为预算的 1.19 倍）。
- 地点在预算里的"可用度" `avail`：解锁日 ≤ 该幕第 5 天 = 1.0；解锁日在该幕后半（第 6–10 天）= 0.5；解锁日晚于该幕 = 0；线索解锁类按"预期解锁日"（radio_tower 取第 15 天）。
- 危险度倾斜 `τ`：第 1 幕 0，第 2 幕 +1.0，第 3 幕 +1.5（权重乘 `D^τ`），表现"近处被拿空，后面的东西在更危险的地方"。
- **收益与耗时**：一次夜间副本有效搜刮时间 = 8 小时 − 往返路程 − 开锁/撤离缓冲；low D（≤ 1.2，如 elder_house）往返 16–20 分钟，一次期望 90–140 VP；high D（≥ 1.6，如 church、warehouse）往返 80–140 分钟，一次期望 250–400 VP，**单位时间收益约 1.7–2.5 倍，但失败代价与恶名更高**（GDD §1.8）。
- 占用类的地点（suburb_house、elder_house、church、school、clinic 等）里，住户自己的存粮计入该地点的 food 配额；被拿走后触发 NARRATIVE §2.5 的住户小模拟，`food_days` 的量纲：**1 食物日 = 该户人数 × 30 VP**。

### 9.4 分配算法

```lua
-- sim/worldgen.lua 的 loot 阶段；rng = state.rng.loot
local CATS = { "food", "water", "fuel", "parts", "meds", "luxury", "weapons" }

function allocate_loot(state, pool)                 -- pool：入池地点列表
  for act = 1, 3 do
    for _, c in ipairs(CATS) do
      local B = BUDGET[act][c]                      -- §9.2
      -- 1. 每个地点的份额
      local raw, sum = {}, 0
      for _, loc in ipairs(pool) do
        local w = WEIGHT[loc.id][c] * (loc.D ^ TAU[act]) * avail(loc, act)
        raw[loc.id] = w; sum = sum + w
      end
      assert(sum > 0, "no source for " .. c)         -- 入池约束保证不会触发
      -- 2. 容量限制：超过 cap 的份额截断，余量按比例重分给其他地点（迭代 3 次）
      local share = distribute_with_caps(B, raw, caps_for(pool, act, c))
      -- 3. 住户存粮：先扣 food 类的 household_stock，剩余放容器
      -- 4. 把份额填进该地点布局模板的容器
      for _, loc in ipairs(pool) do
        fill_containers(loc, act, c, share[loc.id], rng)
      end
    end
  end
end

-- 填充：容器数 N_c，各容器权重按布局槽位（柜 1.0、箱 1.3、隐藏 0.6、尸体 0.5）；
-- 重复抽取品种（§9.5 品种表，加权）直到 剩余 < 最便宜品种 VP；
-- 抽到的品种超过剩余时，用 ≥ 1 VP 的小件（scrap / nails / cloth）补尾差。
-- 每个容器的 VP 目标 ≈ 份额 × 槽位权重 / Σ权重，上下浮动 ±25%（rng.loot）

function validate_loot(state)                        -- ±10% 校验（PLAN §4.7）
  for act = 1, 3 do
    for _, c in ipairs(CATS) do
      local total = sum_vp(state.world.locations, act, c)
      if total < 0.90 * BUDGET[act][c] or total > 1.10 * BUDGET[act][c] then
        return false, string.format("act %d %s: %.0f vs %.0f", act, c, total, BUDGET[act][c])
      end
    end
  end
  return true
end

-- sim.new：repeat allocate_loot; ok = validate_loot until ok 或 重抽 8 次，仍不合格则 error（测试以此暴露缺陷）
```

设计上，填充用"尾差补齐"使总量落在 **±3%** 以内，校验线 ±10% 只留给"容量上限截断后无处可放"的极端情况。

### 9.5 品种表（每类的抽取权重）

| 类别 | 品种与权重 |
|---|---|
| food | canned_beans 22、canned_soup 18、canned_meat 10、canned_fruit 10、dried_rice 14、sugar 4、salt 3、raw_meat 6（仅 farm / river_dock / warehouse）、raw_fish 5（仅 river_dock）、smoked_meat 3（仅 trailer_market）、wild_roots 5（仅挖掘与 farm） |
| water | bottled_water 80、clean_water 20 |
| fuel | firewood 35、gasoline 30、propane 15、coal 20（coal 仅 construction_site / river_dock / warehouse） |
| parts | scrap 22、components 14、cloth 12、nails 6、planks 8、insulation 6、wire 5、pipe 5、rope 4、duct_tape 4、electronics 5、heater_parts 2、humidifier_parts 1.5、generator_parts 1.5、radio_parts 2（radio_tower / police_station 权重 ×5）、battery 3、filter_cartridge 1.5、工具（hammer 1、hand_saw 1、toolbox 0.5、multimeter 0.5、flashlight 1、binoculars 0.3）、穿戴与背包（winter_coat 1、wool_hat 1、wool_gloves 1、snow_boots 0.7、backpack_small 0.8、backpack_large 0.3、blanket 1.5、sled 0.2）、汽车件（car_parts / car_battery / tire 仅 gas_station / trailer_market / motel：各 0.6）、lockpick 0.8、crowbar 0.8、shovel 0.8 |
| meds | bandage 30、painkillers 20、cold_medicine 15、antibiotics 12、antiseptic 15、first_aid_kit 6、insulin 2（仅 pharmacy / clinic，剧情用途时额外保证一份） |
| luxury | coffee 18、instant_coffee 20、cigarettes 14、whiskey 10、moonshine 5（farm / trailer_market）、book 18、chocolate 15 |
| weapons | knife 12、bat 12、axe 8、handgun_ammo 20、shotgun_shells 12、rifle_ammo 10、handgun 6、shotgun 3、hunting_rifle 3、suppressor 0.8（仅 police_station / checkpoint_kilo）、bear_trap 1.5（仅 farm） |

---

## 10. 经济自洽检查

### 10.1 全队每天最低消耗（4 人）

"最低线"= 不掉体温（房间 8 °C，E = 11）、不饿不渴的下限。

| 项 | 数量 / 天 | VP / 天 | 推导 |
|---|---|---|---|
| 食物 | 360 饱食点 = 12 罐豆子等价 | 120 | 4 人 × 90 点 ÷ 3 |
| 水 | 9 L（融雪 + 净化） | 15（燃料）；有净水器约 6；全用瓶装 36 | 4 × 2.2 L；融雪 0.5 柴/4 L + 煮沸 0.25 柴/4 L ≈ 1.7 VP/L |
| 烹饪 | 约 6 份熟食 | 5 | 6 × 0.1 柴 × 9 VP |
| 供暖（−15 °C，一间房 4 人，§6.2.4） | 破屋 23.8 / 封板 16.1 / 保温 I 11.0 / 保温 II 7.6 kWh | 71 / 48 / 33 / 23 | × 3 VP/kWh；前 3 天实际只有灶（600 W，16 小时 6.4 柴 = 58 VP），温度到不了 8 °C |
| **合计（无寒潮）** | | **前 3 天 ≈ 78 燃料 + 120 食物 = 198；封板后 188；保温 I 173；保温 II 163** | 燃料行：78 / 68 / 53 / 43（含水与烹饪） |
| 寒潮日 | 供暖热量 ×1.7–2.2 | 额外 +25 ~ +45 | §6.2.4：−35 °C 时同一房间耗热约 2.2 倍 |

食物占 60–75%，燃料占 25–40%，是第二大头。

### 10.2 开局物资与可撑天数

开局物资（`data/balance.lua: start_stash`，普通难度）：

| 类别 | 内容 | VP |
|---|---|---|
| 食物 | canned_beans ×18（180）、canned_soup ×6（42）、canned_meat ×6（78）、canned_fruit ×4（24）、dried_rice ×6（144） | **468** |
| 水 | bottled_water ×6 | 24 |
| 燃料 | firewood ×12、gasoline ×12（L）、propane ×2 | 108 + 96 + 44 = **248** |
| 医药 | bandage ×4、painkillers ×2、cold_medicine ×2 | 62 |
| 材料与工具 | scrap ×6、planks ×4、nails ×20、cloth ×6、hammer ×1 | 58 |
| 角色自带 | linwei 的 multimeter、sam 的 lockpick 等，个人物品 | 不计预算 |

可撑天数：食物 468 ÷ 120 ≈ **3.9 天**；燃料 248 ÷ 约 70（前 8 天均值）≈ **3.5 天**；水：瓶装 6 L ≈ 0.7 天，之后靠融雪（只耗柴）。再加第 1 幕清瓦砾的免费进项（食物约 5 VP/天、柴约 12 VP/天），开局自给约 **4 天**，**第 1 夜就必须外出**（第 4 天食物见底），符合"第 1 幕安顿、前 3 天吃紧"的节拍。

### 10.3 第 10 / 20 / 30 天存粮的设计推演

PLAN §4.7 的"存粮"指食物存量；燃料另有同样的 1–3 天目标（PLAN §10 C5）。下表两者都给出。

日级推演（食物 120 VP/天；实收系数 60% / 60% / 62%；免费进项食物 50 / 20 / 20、燃料 120 / 30 / 30 VP/幕；开局 468 / 248；燃料日耗 78×3 天、68×5、53×6、43×后续，另加寒潮额外 30 / 25 / 25 / 45 VP/天 × 3 天）：

| 日期 | 食物存粮 | 折合天数 | 燃料存量 | 折合天数 | 判定（PLAN §4.7：食物与燃料各 1–3 天） |
|---|---|---|---|---|---|
| 第 10 天 | 278 VP | **2.3 天** | 138 VP | 2.6 天 | 通过 |
| 第 20 天 | 268 VP | **2.2 天** | 103 VP | 2.4 天 | 通过 |
| 第 30 天 | 297 VP | 2.5 天 | 113 VP | 1.3 天 | 通过（大寒潮后一天耗燃料大） |

不同策略（实收系数 f，粗估，M10 用 500 局实测校正）：

| 策略 | f | 预期 |
|---|---|---|
| 谨慎型（偷空屋与敌对据点 + 交易） | 0.60 | 存粮 1–3 天；寒潮是主要死因；存活 35–55% 靠 f 与危险度倾斜共同调出 |
| 消极型（夜里不出） | 0.05（只有挖掘） | 468 + 50 免费进项，对 120/天 的消耗 → 第 4–5 天断粮；存活 < 5% |
| 冷酷型（见谁抢谁） | 0.85（含住户存粮） | 存粮 4–6 天，但心理危机率与恶名使终局人数少；存活 55–75% |

### 10.4 "抢比换多拿"（NARRATIVE §2.2 原则 3）的倍数

| 手段 | 每单位"自己付出的 VP"所得 | 倍数（相对教堂公平交易） |
|---|---|---|
| 公平交易（教堂 s = 0.15） | 0.85/1.15 = 0.74 | 1.0×（基准） |
| 流动商贩（s = 0.25） | 0.75/1.25 = 0.60 | 0.8× |
| 住户（s = 0.35）、拖车集市（s = 0.40） | 0.48 / 0.43 | 0.65× / 0.58× |
| **偷**（夜入空屋或有人家） | 1.0（物资原价） | **1.35–2.3× 于交易** |
| **抢**（持械威吓） | 1.0，加上其存量的 100%（交易只能换其愿卖的 20–30%） | **约 2–3× 于交易** |

按**每个行动额度**对比（GDD 的"一天一个白天一个夜晚"）：

| 行动 | 一次额度的净收益（VP） | 代价 |
|---|---|---|
| 白天交易（1–2 人去，付出价值 150 的奢侈品） | 约 +60–110 的必需品（150 × 0.6 ~ 0.75 再扣差价） | 无；失败风险低 |
| 夜里偷空屋 | 90–140 | 迟归、受伤风险 |
| 夜里偷有人家 | 150–220 | 心理（良知角色 −25）、该户 `food_days` −3、2–5 天后后续片段 |
| 抢（威吓取走大部分） | 220–400 | 心理 + 恶名 + 对方报复 / 向哨站告发（WORLD §5） |

结论：**偷抢的净收益约为公平交易的 2–3 倍（按行动额度）、1.35–2.3 倍（按价值点往返）**，且 elena 型角色的心理代价约 −25 点、恶名 +3–8、报复概率每次约 30%（具体由 WORLD §2.2 权重决定）。作恶在数值上划算，代价付在别处（NARRATIVE §2.2 原则 3、5）。教堂是"公平且便宜"的特例（s = 0.15），但容量小、声望门槛高，使善行"有成本、不保证回报"（原则 4）。

---

## 11. 裁决结果（见 PLAN §10）

| # | 问题 | 涉及文档 | 本文做法 / 建议 |
|---|---|---|---|
| C1 | **天气 `snaps` 结构**：PLAN §4.4 的 `{ start_day, days, severity, announced }` 没有升降形状，也没有"大寒潮"标记 | PLAN §4.4 | 本文把 `severity` 扩为 1..4（4 = 大寒潮），升降形状由 `weather.lua` 按 §6.5.2 生成；若不接受，则需在 `snaps` 里存每日 μ 序列 <br>→ 裁决：PLAN §10 C1，severity 为 1..4（4 = 大寒潮），升降曲线由 `sim/weather.lua` 生成 |
| C2 | **`food_any` 的定义**：NARRATIVE 示例 `{ "has_item", "food_any", 2 }` 的语义。本文把它限定为**可直接食用**，生食材与米、糖、盐不算，防止"乞丐来要吃的"片段拿生肉去应付 | NARRATIVE §2.7、WORLD | 若想把 `food_raw` 也算进去，需改 §1.2 的标签表并在 `inventory.lua` 里按"VP 最低优先"扣，会先扣生食 <br>→ 裁决：PLAN §10 C2，`food_any` 只含可直接食用的食物，生食材用 `food_raw` |
| C3 | **新机制未在 GDD 出现**：①熟食 36 小时变质；②发电机夜噪与柴火炉烟柱各增加夜袭概率；③专属科技节点缺人时 ×1.5 的替代路线；④储水罐在 < 0 °C 冻结；⑤图纸"必出 3 + 每张 65%"规则 | GDD §1.5、§1.6 | 都是为了让既有设计（家园取舍、专属特长、每局不同的图纸）落地的最小新增；若想砍，影响分别在 §2、§5.2、§4.1、§5.2、§4.3 <br>→ 裁决：PLAN §10 C3，五项新增机制全部采纳，GDD 相应章节已补引用 |
| C4 | **开局可用的取暖与电力**：GDD 把电暖器与发电机放在第 2 层，本文设"开局只有灶、发电机损坏"，前 3 天靠灶（600 W）与封窗度过，期间燃料开销最大 | GDD §1.6 | 若你想让第 1 天就有电暖器，则需给开局一台能用的发电机并改 §10.2；`start_stash` 的燃料会相应放宽 <br>→ 裁决：PLAN §10 C4，同意：开局只有灶可用，发电机损坏 |
| C5 | **存粮定义**：PLAN §4.7 的"第 10、20 天存粮中位数 1–3 天"本文按**仅食物**、4 人 120 VP/天计（队伍变小则分母变小）。是否应包含燃料？ | PLAN §4.7 | 本文另给了燃料天数（§10.3）作参考；请裁决 §4.7 是否只看食物 <br>→ 裁决：PLAN §10 C5，§4.7 的"存粮"指食物；另加燃料指标（第 10、20 天燃料存量中位数 1–3 天） |
| C6 | **地点危险度**取 WORLD §6.1 的"夜袭难度"换算（D = 0.8 + 0.2 × 难度），所以 church（难度 4）的 D = 1.6 偏高，而教堂白天可交易、本是和平社区；这会让第 2/3 幕里教堂的 food/water 份额被危险度倾斜放大 | WORLD §6.1 | 容量上限已压到 300 VP；若想让教堂更像"和平据点"，可把它的难度降为 2–3，或在分配时对 church 禁用倾斜（单点覆盖 `tau = 0`） <br>→ 裁决：PLAN §10 C6，同意 D = 0.8 + 0.2 × 夜袭难度；教堂份额偏高是设计意图，M10 观察 |
| C7 | **WORLD 的 `food_days` 量纲**：NARRATIVE 示例 `loc_add ... food_days -3` 未规定单位 | NARRATIVE §2.4、WORLD §5 | 本文约定：1 食物日 = 该户人数 × 30 VP；掠夺一户可拿走其全部库存，库存 = `food_days × 人数 × 30`，计入该地点的 food 配额（§9.3） <br>→ 裁决：PLAN §10 C7，同意：1 个 `food_days` = 该户人数 × 30 VP |
| C8 | **哨站"代价包"与南行燃料**：WORLD §7.2 与 R9 留给本文：代价包 = gasoline ×10 + antibiotics ×2 + whiskey ×1（144 VP）；南行 = 修车件 220 VP + 汽油 40 L（320 VP），`car.fuel ≥ 40` | WORLD §7.2、R9 | 请确认；这两个值直接决定第 3 幕的燃料预算（1000 VP）是否够"带全员南行 + 守家取暖" <br>→ 裁决：PLAN §10 C8，同意：哨站代价包 144 VP；南行需修车件 220 VP + 汽油 40 L |
| C9 | **心理阈值**：本文给的滞回阈值（§6.4.4）覆盖了 NARRATIVE §2.6 只描述为"带滞回"的部分；`psyche.lua` 实现者以本文为准 | NARRATIVE §2.6 | 请确认数值 <br>→ 裁决：PLAN §10 C9，同意：心理阈值以 CONTENT §6.4.4 为准（回升阈值比下行阈值高 5 点） |
| C10 | **夜袭概率与防御分**（§5.5）是建议值，GDD 没给公式；M7/M9 实现时可能需要重写 | GDD §1.5、§1.10 | 先按本文落地，M10 校准 <br>→ 裁决：PLAN §10 C10，夜袭概率与防御分采用建议值，M7 后用探针与批量模拟校准 |
| C11 | **难度档位**（PLAN §9 第 4 条）未定；本文所有数值是"普通"。建议难度修正项只作用于：开局物资 ×0.8/1.2、寒潮核心温度 ±3 °C、预算 ×0.9/1.1（保持 ±10% 校验按各自档位的目标）| PLAN §9 | 暂不实现 <br>→ 裁决：PLAN §10 C11，难度档位 M10 定（PLAN §9 第 4 条） |
