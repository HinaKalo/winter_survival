# M5-3D：三层 3D 室内接入（ranch_a）

> 目标：家园场景用用户交付的 3D 模型（`ranch_a_dressed`，战争废墟基调）替换方块墙，做成三层（B1 / 1F / 2F），
> 视角采用方案 A + C：只画当前查看的楼层（矮墙剖切），其它楼层的人以穿墙轮廓（幽灵）显示。
> 交互完整：切楼层、选人自动切层、让人去别的房间（可跨层走楼梯）、地下室更暖、炉子开关与清瓦砾在模型上可见。
> 模型规格见 `docs/HOUSE3D-BRIEF.md`。美术基调：废墟；以后“修好”的家具只能是勉强可用（见 §8）。

## 1. 架构

```
assets_src/models/ranch_a/house_full.glb   用户交付（Blender 导出，glTF Y-up，1 m = 1 格）
        │  tools/model_bake.py（离线，Linux 可测）
        ▼
assets/models/ranch_a.wsm                  自有二进制网格（§2），按节点分组、世界坐标、逐顶点颜色
        │  src/iso/model.zig（纯：解析 + 可见性） + render.zig（绘制） + lua_api.zig（§3）
        ▼
Lua：view/home3d.lua（纯：节点可见性规则）  game/floors.lua（纯：楼层/楼梯/路线）
     scenes/home.lua（查看楼层、角色楼层、幽灵、切层输入）  ui/hud_home.lua（楼层徽标、楼层标签）
sim：data/homes/ranch_a.lua 增加 levels（B1、F2）与 stairs；sim/home.lua 建 7 个新房间；sim/thermal.lua 地温 + 楼梯连通
```

逻辑地图（TileMap）仍然只装“当前查看的楼层”：寻路、光照、视野照旧；切层时重建（20×14，很快）。
模型只负责画面；瓦片不再绘制（`map_set_draw_tiles(false)`），但仍然参与逻辑与光照。
不在查看楼层的角色不走寻路：位置在 Lua 里按直线插值，实体设为幽灵（ghost）。

## 2. `.wsm` 格式（WSM1，小端）

```
header : "WSM1" | u32 version = 1 | u32 node_count | u32 vertex_count
node[i]: u16 name_len | name (UTF-8) | u32 first_vertex | u32 vertex_count | f32 min[3] | f32 max[3]
vertex : f32 x, y, z | i8 nx, ny, nz | u8 pad = 0 | u8 r, g, b, a          (20 字节)
```

- 三角形 = 连续 3 个顶点（非索引）；每个节点 `vertex_count % 3 == 0`，节点的顶点区间连续、互不重叠、按节点顺序排列。
- 节点按名字字节序排序；只收有网格的节点；顶点已乘上节点 TRS（世界坐标，glTF 空间：X = 列，Y = 高，Z = 行）。
- 法线：平面法线（三角形叉积，归一化后 ×127 取整）。
- 颜色：材质 `baseColorFactor` ×255 四舍五入；材质有非零 `emissiveFactor` 时用 emissive 颜色，且 `a = 128`（自发光：渲染不受光照压暗）；否则 `a = 255`。没有材质用 `(200,200,200,255)`。
- min / max：节点所有顶点的包围盒。
- 同一输入烘焙两次，输出字节完全相同。

工具：`python3 tools/model_bake.py IN.glb OUT.wsm`；失败时非零退出并打印原因（不是 glb、缺 POSITION、索引越界）。

## 3. 引擎接口（Lua `iso.*`，冻结）

| 函数 | 说明 |
|---|---|
| `model_load(path) -> id` 或 `nil` | 读取 `.wsm`；id 从 1 起；同一路径可重复加载（各自独立实例） |
| `model_unload(id)` | 释放；之后对该 id 的查询返回 nil / 0 |
| `model_info(id) -> { nodes, tris, visible_tris }` 或 `nil` | `visible_tris` 只数当前可见节点 |
| `model_nodes(id) -> { name, ... }` | 按文件顺序 |
| `model_set_visible(id, pattern, bool) -> n` | `pattern` 是完整节点名，或以 `*` 结尾的前缀；返回匹配的节点数；不匹配返回 0 |
| `model_node_visible(id, name) -> bool` 或 `nil` | 节点不存在返回 nil |
| `model_set_offset(id, x, y, z)` | 整体平移（切层时把被查看楼层的地面移到 y = 0） |
| `map_set_draw_tiles(bool)` | false：瓦片不画，但地图逻辑、光照照常 |
| `entity_set_ghost(id, bool)` / `entity_get_ghost(id) -> bool` | 幽灵：不受墙体遮挡（不做深度测试），画成实体颜色的轮廓或半透明剪影；不可拾取 |

- 新加载的模型所有节点可见、偏移为 0。
- 绘制：模型在瓦片之后、精灵之前；颜色 = 顶点色 × 朝向明暗（光从左上方，顶面最亮，范围 0.55–1.0）× 光照图（按顶点所在格取 `lm.rgb`，越界取最近格；`a = 128` 的自发光顶点不乘光照与明暗）× 世界染色（tint）。
- 只在可见性、偏移或光照图变化时重建顶点缓冲。
- `iso.world_clear()` 不卸载模型；场景退出时由场景调用 `model_unload`。

纯逻辑 `src/iso/model.zig`（`zig build test` 覆盖，验收测试 `src/iso/model_accept_test.zig`）：

```zig
pub const Vertex = extern struct { x: f32, y: f32, z: f32, nx: i8, ny: i8, nz: i8, pad: u8, r: u8, g: u8, b: u8, a: u8 };
pub const Node = struct { name: []const u8, first: u32, count: u32, min: [3]f32, max: [3]f32 };
pub const ParseError = error{ BadMagic, BadVersion, Truncated, BadRange, OutOfMemory };
pub const Model = struct {
    nodes: []Node, verts: []Vertex, visible: []bool,
    pub fn parse(allocator, bytes: []const u8) ParseError!Model;
    pub fn deinit(self: *Model, allocator) void;
    pub fn findNode(self: *const Model, name: []const u8) ?usize;
    pub fn setVisible(self: *Model, pattern: []const u8, on: bool) u32;   // 完整名或 "前缀*"
    pub fn triCount(self: *const Model) u32;
    pub fn visibleTris(self: *const Model) u32;
};
pub fn shade(nx: i8, ny: i8, nz: i8) f32;   // [0.55, 1.0]；朝上 ≥ 朝侧 ≥ 朝下
```

## 4. 数据与模拟

### 4.1 `data/homes/ranch_a.lua`

`variants.A` 现有字段不变（它就是 1F）。新增：

```lua
levels = {
  B1 = { grid = {...20×14...}, floor = "wood", wall = "siding",
         rooms = { cellar = {x=3,y=3}, boiler = {x=13,y=3}, storage = {x=5,y=10}, shelter = {x=13,y=10} },
         ground = true },
  F2 = { grid = {...}, floor = "wood", wall = "siding",
         rooms = { attic_bed = {x=3,y=3}, kids = {x=3,y=10}, attic_store = {x=13,y=6} } },
},
stairs = {
  { id = "stair_b1", lower = "B1", upper = "F1", lower_cell = {1,12}, upper_cell = {1,8},
    lower_room = "storage", upper_room = "kitchen" },
  { id = "stair_f2", lower = "F1", upper = "F2", lower_cell = {17,5}, upper_cell = {17,1},
    lower_room = "living", upper_room = "attic_store" },
},
```

网格照 `docs/HOUSE3D-BRIEF.md` §3，但只用现有图例符号：楼梯格写 `.`（可走），高窗写 `w`，B1 南墙两个高窗。

### 4.2 房间与热

- `state.home.rooms[id].floor ∈ "B1" | "F1" | "F2"`；1F 原有 4 个房间为 `"F1"`；B1 四个、F2 三个新房间。
- B1 房间 `ground = true`：墙、板、顶/地这些“实体围护”与地温 `balance.thermal.ground_temp`（4 °C）换热；窗、洞、门仍与室外换热。
- 楼梯：两层房间之间加一条连接 `{ room = 对方, walls = 0, doors = 0, stairs = 1 }`，`link_g` 增加 `stairs × balance.thermal.g.stair_open`（取 8）。双向对称。
- 1F 房间的顶/地项不变（保持现有平衡）。
- 黄昏/黎明报告里的室内平均温度（`home_session` 的 `avg_room_temp`）只按 1F 房间算（避免数字漂移）；`hs.hud(s).rooms` 每项增加 `floor`，`hs.hud(s).chars` 每项增加 `floor`（由 `ch.room` 推出）。
- 角色位置仍是 `ch.room`；楼层由房间推出。
- 游戏中途新建的房间（冷室 cold_cell，CONTENT 5.3）属于宿主房间（默认房间 living）所在楼层，`floor` 继承宿主；场景里没有模板锚点的房间用宿主房间的锚点（审查 r2 裁定）。

### 4.3 会话动作

`hs.actions(s, cid)` 增加 `kind = "move"`，`id = "move:<room>"`（除当前房间外的每个房间，按 room_order），`label = "home.room.<room>"`。
move 项排在列表最后（不改变现有菜单的默认焦点）。`hs.act` 走 `home.assign`；白天且角色在家、未睡、存活才可用（否则 `enabled = false`，reason 短键）。失败时状态逐字节不变。

## 5. 视图规则（纯模块，冻结）

### 5.1 `game/floors.lua`

```lua
floors.ORDER = { "B1", "F1", "F2" }
floors.BASE_Y = { B1 = -3, F1 = 0, F2 = 3 }
floors.of_room(state, room_id) -> floor | nil
floors.step(floor, dir) -> floor          -- dir = +1 上 / -1 下；到头不变
floors.route(template, from, to) -> { stair, ... }   -- 每项 { id, from, to, from_cell = {x,y}, to_cell = {x,y} }；同层为空表；B1→F2 两段
```

### 5.2 `view/home3d.lua`

```lua
home3d.node_visible(name, view_floor, state) -> bool
home3d.visibility(names, view_floor, state) -> { [name] = bool }
```

规则（按顺序，先命中先用）：
1. `roof*`、`exterior*`、`EXT_*` → 隐藏（剖切视图不画屋顶和外观）。
2. `stair_B1_1F` 在 B1、F1 显示；`stair_1F_2F` 在 F1、F2 显示。
3. 节点所属楼层：`B1_` / `F1_` / `F2_` 前缀，或 `DRESS_B1_` / `DRESS_F1_` / `DRESS_F2_`；不是查看楼层 → 隐藏。
4. `<层>_wall_high` → 隐藏（矮墙剖切）。
5. 开关成对：`F1_woodstove_on/off` 对应 woodstove 站点，`F1_hearth_on/off` 对应 hearth 站点；“开” = 站点 `on and hp > 0`。`_on` 只在开时显示，`_off` 反之。`B1_boiler_on/off`：没有对应站点，恒为 off。
6. `F1_rubble_0k`（k = 1..6）：显示 k ≤ `ceil(6 × rubble / rubble_initial)` 的几堆（`rubble_initial` = 模板的 `rubble`，ranch_a 是 70）。
7. 其余属于查看楼层的节点 → 显示。

## 6. 场景（`scenes/home.lua`，冻结字段）

新增冻结字段：`M.view_floor`（"B1" | "F1" | "F2"）、`M.model`（模型 id）、`M.actor_floor`（cid → 楼层）。

- 开局：加载 `assets/models/ranch_a.wsm`，`map_set_draw_tiles(false)`，查看 1F，所有人在 1F 客厅。
- 切层输入：新动作 `floor_up` / `floor_down`（ctx `W`，键盘 PageUp / PageDown，可改键；不得与现有默认键冲突，`core/input` 的校验要通过）。到顶/到底不变。
- 选人（Tab / 数字键 / 点卡片）选中其它楼层的人 → 查看楼层自动切到那层。
- 切层：重建该层的逻辑地图（`mapbuild` 按 `levels[...]` 生成）、模型偏移 `(0, -BASE_Y[f], 0)`、按 `home3d.visibility` 设节点可见；在该层的角色变成普通实体，其余角色变幽灵。
- 角色去另一层的房间：在可见层就按寻路走到楼梯格，到达后换层；不可见时按直线插值移动（不穿模要求只针对可见层）。到达新层时，如果新层不是查看层就变成幽灵。
- 每帧（或状态变化时）按 `home3d.visibility` 同步节点可见性（炉子开关、瓦砾减少会体现在模型上）。
- 退出场景时 `model_unload`。
- HUD：角色卡片显示楼层徽标（B1 / 1F / 2F）；屏幕右侧楼层标签列出三层，标出当前层、每层人数和平均温度；只画当前层的房间温度标签和站点标记。

## 7. 验收测试（红灯，编码代理不得修改）

| 文件 | 覆盖 |
|---|---|
| `tests/tools/test_model_bake.py` | §2 格式、TRS、颜色/自发光、确定性、错误输入；真实资产节点齐全、面数 ≤ 30k、范围正确 |
| `src/iso/model_accept_test.zig` | §3 纯逻辑：解析、错误、查找、前缀可见性、面数、明暗 |
| `tests/probe/model3d.lua` | §3 Lua 接口 |
| `tests/lua/test_home_floors.lua` | §4、§5：数据、房间楼层、地温、楼梯连接、move 动作、floors / home3d 规则、存读档 |
| `tests/probe/home_floors.lua` | §6 端到端：开局 1F、切层、幽灵、选人切层、跨层移动、炉子开关在模型上可见 |

已有全部测试必须继续通过（含 `test_home_session`、`test_sim_30d`、`bot_days`、`home_play`）。如因 §4.2 的热模型变化导致已有测试的数值断言失败：停下报告，由主代理裁定。

## 8. 任务拆分

| 任务 | 内容 | 负责 | 依赖 |
|---|---|---|---|
| W1 | `tools/model_bake.py` + 烘焙 `assets/models/ranch_a.wsm` + 源文件入 `assets_src/models/ranch_a/`；assets 检查不报错 | coder-opencode（Sonnet medium） | — |
| W2 | `model.zig` + 渲染 + Lua 接口 + 幽灵 + 不画瓦片 | coder-sonnet | W1 的格式（可先用测试里的合成数据） |
| W3 | 数据 / 模拟 / 会话 / `floors` / `home3d` / 场景 / HUD / 输入 | coder-sonnet | W2 接口（按 §3 冻结契约并行开发，最后合并） |

以后：修复后的家具变体（`<节点>_patched`），外观“勉强可用”：补丁、绑绳、拼凑的木板，不能是新的；由 `home3d` 按站点 hp 和修理状态切换。

## 9. 审查遗留（P3 backlog）

- `model_info` 以 struct 返回，Debug 构建每次调用打印 binder 警告“pushing a struct that is not a bound type”（只是日志噪声）。
- `model_nodes` 对未加载的 id 返回空表（计划写 nil）；超过 4096 个节点会静默截断（当前 193 个）。
- `model_bake.py`：非三角形图元（strip / fan）静默跳过；有符号索引没有负数检查；极大坐标的 f32 打包会抛未捕获的 OverflowError。
- 光照图任一格变化都会整模型重建上传；灯光逐帧闪烁时可能有帧耗时问题（需要时改为分块）。
- 旧存档（M5 之前，没有 floor / ground 字段）加载后没有迁移。
- 测试覆盖待补：自发光 a=128 的渲染分支、重建规则（models_rebuilt_last）、offset 实际平移几何、world_clear 不卸载 / resetState 清空、烘焙的父子层级、负行列式绕序、matrix 节点、u8/u32 索引。
- 修复后的家具变体（`_patched`，勉强可用的外观）：建模 + `home3d` 切换规则。
