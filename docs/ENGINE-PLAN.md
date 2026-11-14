# 引擎扩展设计（Zig 侧）v1

本仓库对脚手架引擎（`ENGINE-BASE.md`）的扩展。总体架构见 `PLAN.md §4`，里程碑见 `PLAN.md §6`。

13 项需求都能在游戏仓库内完成，不修改 `delve-framework`。做不到的只有鼠标滚轮和文本输入（§A7.2）。以下结论来自读源码，未编译验证；标"实现时核对"的 API 由编码代理对照源码确认，不得凭记忆。

路径约定：`S/` = `~/dev/delve-starter/`（生成后对应本仓库同名文件），`F/` = `~/dev/delve-framework/src/framework/`。

## A0. 现状核实（设计所依赖的事实）

| 结论 | 证据 |
|---|---|
| Lua `text.draw` 逐字节画 8×8 调试字形，无 UTF-8 | `F/api/text.zig:10-35` |
| Delve 没有 scissor 封装 | `F/platform/` 下无 `scissor` |
| 可按区间、按材质从同一缓冲绘制：`drawSubsetWithMaterial(bindings,start,end,material,mats,model)` | `F/platform/graphics.zig:1194-1198` |
| `Batcher` 的 `vertex_buffer/vertex_pos/bindings` 可访问；顶点为 `PackedVertex{x,y,z,color:[4]f32,u,v}` | `F/graphics/batcher.zig:233-243`、`F/platform/graphics.zig:145-151` |
| `addQuad` 顶点顺序 BL、BR、TR、TL，索引 `0,1,2,0,2,3` | `F/graphics/batcher.zig:294-327` |
| Delve 2D 层：`lookat((0,0,5))`、`getProjectionOrtho(0.001,10,true)`、model `translate(0,0,-2.5)` | `F/api/draw.zig:35-42` |
| headless 下图形调用全是空实现，窗口固定 1024×768 | `F/platform/backends/backends.zig:22-33` |
| Lua VM 分配器是 `ArenaAllocator`，只在 `deinit` 整体释放 | `F/scripting/lua.zig:12-13,27-31,177-183` |
| `initLua(allocator)` 是 pub；binder 以 `luaState` 为参数，不依赖全局 | `F/scripting/lua.zig:62-64`、`F/scripting/binder.zig:137,438,468-473` |
| 脚手架经 `manager.init()` 建 VM，4 处 `lua_util.getLua()`、2 处 `runLine` | `S/src/iso/script_host.zig:47-49,88,95,108,134,158`、`S/src/kit/probe.zig:123` |
| 地形单批次、上限 10,000 四边形、任何 `set()` 整图重建 | `S/src/iso/render.zig:89,214-218,233-283` |
| `Batcher` 超 64000 索引只打日志、随后越界写 | `F/graphics/batcher.zig:24-25,508-512` |
| A* 的 open 表线性扫描，每次调用分配 `w*h` 节点 | `S/src/iso/tilemap.zig:175-203` |
| 实体路径 `[64]GridPos`，超出截断；id = 槽位+1，复用无代数 | `S/src/iso/world.zig:30-32,65-88,97-104` |
| 引擎不和 Lua 抢朝向：只写 `facing/last_move`，`flip_x` 从不自动写 | `S/src/iso/world.zig:163-175,241-244` |
| 同一路径反复 `sheet_load` 会无限 append | `S/src/iso/render.zig:203-207` |
| `hh = view_height/(2*zoom)`：像素密度随窗口高度变 | `S/src/iso/camera.zig:172-178` |
| billboard 屏幕像素 = 世界尺寸 × ppu，两轴一致 | `S/src/iso/render.zig:308-329` |
| 音频只有 1 条 BGM 流 + 24 个 SFX 语音；kind 只能是 `sfx/bgm` | `S/src/kit/audio.zig:30,50-55`、`S/tools/assets.py:29,34,178-181,728` |
| 探针看门狗：20 s 无 tick 判卡死；总墙钟 `max(timeout×3,120 s)` | `S/src/kit/probe.zig:26,133,229,239-242,277` |
| 输入只有键盘按下/刚按下和 3 个鼠标键；`MOUSE_SCROLL` 被丢弃；CHAR 只喂控制台 | `F/platform/input.zig:162-166,326-335`、`F/platform/backends/sokol/app.zig:90-131` |
| `~` 开控制台后 `onKeyDown` 被吞；`setConsoleVisible` 是 pub | `F/platform/input.zig:306-309`、`F/debug.zig:385,399` |
| Delve 无手柄支持；本机有 `/dev/input/js0` | grep 无结果；`ls /dev/input` |

## A1. 核心设计决策（子代理不得更改）

1. **自建 Lua VM**。脚本宿主不再调 `manager.init()`，改为 `vm.init()`：
   - 用 `delve.scripting.lua.initLua(heap.allocator())` 建状态，再 `openLibs()`。
   - 照抄 `F/scripting/manager.zig:26-45,52-83`，把 `assets/display/draw/text/graphics/input.mouse/input.keyboard` 七个库绑到自己的状态，并以 -50 注册各自的生命周期模块（模块名保持 `scriptapi.<name>`）。
   - 后备分配器 `std.heap.smp_allocator`，外包计数器 `LuaHeap`，上限默认 512 MiB；超限返回 null，Lua 抛内存不足，被 pcall 接住后进入 `script_failed`。
   - 禁止再调用 `lua_util.getLua()/runLine/runFile`（全局指针未初始化），全部改 `vm.get()`/`vm.runLine()`。
2. **模块优先级**：`kit_probe` -80 → `kit_input` -75（新）→ `iso_world` -70 → `kit_audio` -65 → `iso_script_host` -60 → `kit_ui` -55（新）→ Delve scriptapi -50。绘制顺序：世界 → Lua `_draw()` 排 UI 指令 → `kit_ui` 提交 → Delve 调试层。
3. **dt 钳制**：`iso_world.onTick` 和传给 Lua `_update` 的 dt 统一 `min(dt, 0.1)`。
4. **像素基准**（yaw 45°、pitch 30° 锁定）：
   - `ppu = 128/√2 = 90.50967` px/世界单位。相机新增 `pixels_per_unit`，大于 0 时 `hh = viewport_h / (2·ppu·zoom)`，窗口缩放时 ppu 恒定、可见范围变化。
   - 顶面菱形 = `√2·ppu` × `√2·ppu·sin30°` = 128×64 px。
   - 竖直 1 世界单位 = `ppu·cos30° = 78.3837 px`。取 `height_unit = 1/√6 = 0.408248`，每级高度正好 32 px。
   - billboard：世界尺寸 = 像素/ppu，64×96 px → `0.707107 × 1.060660`。
   - zoom 只取整数：Lua 用 `zoom = max(1, floor(H/720))`。
   - 侧面贴图：一个 64×64 图集格覆盖 2 级高度，从 level 0 向上对齐，不足 2 级的段按比例裁 V。
5. **像素吸附**（默认开）：`update()` 把 target 沿 right/camUp 轴换算成像素后取整，反算得 `view_target`；view、`screenToRay`、`worldToScreen` 都用 `view_target`，逻辑 `target` 不变。渲染时每个实体脚底做同样吸附。顶面是旋转 45° 的贴图，吸附只保证不闪烁。
6. **瓦片分块**：
   - 块 16×16 格，每块一个带材质的 `Batcher`，懒创建。地图上限 128×128。每块上限 10,000 四边形。
   - 顶点由纯逻辑 `tilemesh.zig` 生成世界坐标四边形；render 层先 `addRectangle` 占位（借它扩容和写索引），再覆写最后 4 个顶点。
   - 脏块只在 `draw` 里重建，每块每帧最多 `apply()` 一次。
7. **每格动态属性**（不触发重建网格）：`flags: []u8`（bit0 `blocked`、bit1 `opaque`）+ `tag: []u8`。
   - 写格子时按 TileDef 复位：`opaque = def.opaque`、`blocked = false`、`tag = def.tag`。
   - `isWalkable = 非空 && !solid && !liquid && !blocked`。
   - 视线只看 `opaque`，不看高度。越界视为 opaque。`opaque` 变化时 `opacity_version += 1`。
8. **视线只有一个判定函数** `vision.los()`，FOV、光照遮挡、潜行检测全部复用，保证"画出来的视锥 = 实际判定"。
   - 中心到中心的整数网格 DDA，端点不参与遮挡（能看见墙本身）。
   - 精确穿过格角时，两侧正交邻格都 opaque 才算挡。
   - 调用前把端点按字典序规范化，保证 `los(a,b) == los(b,a)`。步数上限 `|dx|+|dy|+2`。
9. **FOV = 半径内逐格 LOS**，半径上限 32。锥形用朝向向量 + 半角；零向量或半角 ≥ 180 为全向；原点格恒可见。NPC 单点侦测走 `vision_can_see`（O(r)），掩码只用于画覆盖层和战争迷雾。
10. **可见性掩码池**：16 个槽（id 1..16）。`fov_compute` 是并入语义：小队并集 = `mask_clear` + N 次 `fov_compute`；已探索 = `mask_or(explored, visible)`。同一池也承载 BFS 可达区域。
11. **光照**：
    - 每格 `[3]u8`。`lit = min(1, ambient + Σ color_i · (1−d/r)² · vis_i)`。
    - 最多 64 个点光源，r ≤ 16；每个光源缓存 33×33 的贡献表，只在光源变化或 `opacity_version` 变化时重算。
    - 合成 `tile_rgb = lit × fog`：可见 1.0 / 已探索 0.4 / 未知 0.0；未设迷雾掩码时恒 1。
    - 每帧最多合成一次；逐格比较新旧值，变化格及其 8 邻格所在块置脏。
    - 另有 `world_set_tint`：材质整体乘色，零重建，用于暴风雪压暗和淡出。
12. **逐顶点光**：顶面角点的光 = 共享该角的至多 4 格中"在界内、非空、与本格同高"者的平均。侧面顶点取朝向邻格在该角的角点光；邻格越界或为空时用本格值。最终顶点色 = 面系数（顶 1.0 / ±X 0.78 / ±Z 0.62）× 角点光。
13. **覆盖层**：16 组（0..15，按组号升序绘制，后画的在上），保留式列表，总上限 8,192 格，脏时才重建。沿用现有高亮材质（BLEND、不写深度）和 `topY + 0.01`。格子可以是纯色，也可以取地块图集的一格做贴图（`overlay_add_tex`，用于血迹、脚印等地面贴花；贴图像素 alpha 仍只有 0/255，整体透明度来自颜色的 a）。`highlight_tile/clear` 保留为组 15 的兼容包装。
    **组号分配（全项目唯一出处，UI-UX 与 ART-AUDIO 引用此表）**：

    | 组 | 用途 | 组 | 用途 |
    |---|---|---|---|
    | 0 | 可达区域预览 | 8 | 选中角色脚下环 |
    | 1 | 血迹贴花 | 9 | 焦点目标 / 可交互标记 |
    | 2 | 脚印贴花 | 10–14 | 预留 |
    | 3 | NPC 视锥 | 15 | 悬停（`highlight_tile` 兼容） |
    | 4 | 事件噪音（枪声、打斗、破门） | | |
    | 5 | 玩家噪音圈 | | |
    | 6 | 路径预览 | | |
    | 7 | 小队成员脚下环 | | |
14. **实体代数 id**：`id = (gen:u16 << 16) | (slot+1:u16)`。despawn 时代数加一，旧 id 永远失效。首代 id 仍是 1,2,3…。
15. **实体路径上限 256**。A* 改二叉堆 + 常驻 scratch（用代数戳免清零），仍为 4 邻接，f 相等时取 h 小者。
16. **UI 屏幕空间绘制**：
    - `kit_ui` 持有一个 `Batcher` 存全部四边形，外加有序 run 表 `{material, index_start, index_end}`，逐 run 调 `drawSubsetWithMaterial`，严格保持提交顺序。
    - 材质：`BLEND`、`depth_compare = .ALWAYS`、不写深度、`cull NONE`、`NEAREST`。不依赖 z 值，一定盖在世界之上。
    - 坐标：左上原点、y 向下的虚拟像素；`ui.set_scale(n)` 整数缩放。
    - 裁剪用 CPU 裁矩形 + 按比例裁 UV，headless 下也能测。每帧上限 10,000 四边形。
17. **字体离线烘焙**：`tools/bake_font.py` 输出 `assets/fonts/<name>.png` + `<name>.fnt`（§A3.9）。
    - 换行机会：空格之后；CJK 表意文字、假名、全角符号之间任意处。韩文音节与拉丁字母一样只在空格断；单词超宽时强制逐字断。
    - 禁则：行首不放 `，。、！？；：）」』》…`，行尾不放 `（「『《`。
    - 非法 UTF-8 → U+FFFD；缺字 → 回退字形，每个码点只警告一次。
18. **输入原始层**：按键边沿在 `kit_input` 自算，`released = (prev_down or just_pressed) and !down`，同帧按下又松开也能得到 released。非开发模式每帧关闭控制台，防止 `~` 吞键。F5 热重载改为 `Config.dev_hot_reload`，发行版关闭。
19. **手柄**：
    - Linux 读 `/dev/input/js0..js7`（非阻塞、8 字节 `js_event`，直接系统调用，不链接任何库）。
    - Windows 用 `kernel32` 动态加载 `xinput1_4.dll → xinput1_3.dll → xinput9_1_0.dll`，加载失败 = 无设备。
    - 其它平台和探针注入走虚拟后端。只激活第一个已连接手柄，断开后每 1 s 重扫。
    - 逻辑轴约定：上 = −1。震动 v1 不做，`pad.rumble` 预留并返回 false。
20. **存档**用 Zig 助手 `sys`（纯 Lua 没有建目录和列目录，`os.rename` 在 Windows 上不能覆盖）。文件名白名单 `[a-z0-9_-]{1,32}`，固定扩展名 `.sav`；先写 `.tmp` 再 rename；单文件 ≤ 8 MiB；内容是不含 NUL 的文本。目录默认 `saves/`，`--save-dir` 可覆盖。
21. **环境音**复用 kind `bgm`，id 约定 `bgm/amb/<name>`（不改上游音频管线）。运行时 4 个通道：0 = 音乐（总线 `bgm`），1..3 = 环境层（新总线 `amb`），每层独立交叉淡化。

## A2. 目录结构（★ 新增，△ 修改）

```
build.zig                △ 新增 luatest / balance 步骤；测试根加入新纯文件
src/main.zig             △ CLI: --script --save-dir --dev；注册 kit_input / kit_ui / sys
src/iso/
  camera.zig             △ pixels_per_unit、snap_pixels、view_target、snapToPixel
  tilemap.zig            △ flags/tag、TileDef.opaque/tag、块脏位图、opacity_version
  pathfind.zig           ★ 纯：二叉堆 A* + 常驻 scratch + BFS 可达
  vision.zig             ★ 纯：los、canSee、fov、MaskSet
  lightmap.zig           ★ 纯：环境光 + 点光源缓存 + 迷雾合成 + 变化检测
  tilemesh.zig           ★ 纯：分块网格（世界坐标四边形 + 逐顶点色）、块可见性
  overlay.zig            ★ 纯：覆盖层分组存储
  world.zig              △ 代数 id、visible/lit/pickable、path 256、light 字段、pick 候选
  render.zig             △ 分块批次、覆盖层批次、精灵吸附/可见/受光、sheet 去重、tint
  engine.zig             △ 全局 masks/lights/overlays/pathfinder；dt 钳制；clearWorld
  vm.zig                 ★ 自建 Lua VM + LuaHeap + Delve 库绑定
  script_host.zig        △ 改用 vm；dev_hot_reload
  lua_api.zig            △ `iso` 库新增绑定（§A4.1）
src/kit/
  audio.zig              △ Channel×4、bus amb
  lua_audio.zig          △ amb/stop_amb/amb_gain/current_amb
  text.zig               ★ 纯：UTF-8、Font 度量解析、measure、wrap
  ui_geom.zig            ★ 纯：矩形+UV 裁剪、九宫格切分
  ui.zig                 ★ 图形：模块 kit_ui(-55)，指令批次与 run 表
  lua_ui.zig             ★ Lua 库 `ui`
  pad_logic.zig          ★ 纯：死区、映射表、逻辑状态、边沿
  gamepad.zig            ★ 后端选择 + 热插拔；linux js / windows xinput / 虚拟
  rawinput.zig           ★ 模块 kit_input(-75)：键鼠边沿、last_key、活动设备
  lua_input.zig          ★ Lua 库 `kit_input` 与 `pad`
  sys.zig                ★ 存档目录/原子写/列表 + Lua 库 `sys`
  save_name.zig          ★ 纯：文件名校验
  probe.zig              △ 改用 vm；pad_button/pad_axis 注入
assets_src/fonts.json    ★ 字体烘焙清单（支持多字体回退链）
tools/bake_font.py       ★ 扫 i18n → 图集 + .fnt；--check
tools/assets.py          △ check 调 bake_font --check；音频 id 正则加 amb
tests/lua/{main,runner}.lua ★ luatest 入口与探针
tests/tools/test_bake_font.py ★
```

## A3. 接口定义

### A3.1 `src/iso/vm.zig`
```zig
pub const Lua = delve.scripting.lua.Lua;
pub const LuaHeap = struct {
    backing: std.mem.Allocator, bytes: usize = 0, peak: usize = 0, limit: usize = 512 << 20,
    pub fn allocator(self: *LuaHeap) std.mem.Allocator; // 计数；超 limit 返回 null
};
pub var heap: LuaHeap;               // backing = std.heap.smp_allocator
pub fn init() !void;                 // initLua(heap.allocator()) + openLibs + bindDelveLibs
pub fn deinit() void;                // lua.deinit()；heap.bytes != 0 则 debug.err
pub fn get() *Lua;
pub fn ready() bool;
pub fn runLine(code: [:0]const u8) !void;
pub fn heapBytes() usize;  pub fn heapPeak() usize;
```
`LuaHeap` 可脱离 Lua 单测。Zig 0.16 的 `Allocator.VTable` 签名由实现者对照 std 源码。

### A3.2 `src/iso/camera.zig`
```zig
pub const IsoCamera = struct {
    // 既有字段不变 ...
    pixels_per_unit: f32 = 0,      // 0 = 旧 view_height 模式
    snap_pixels: bool = false,
    view_target: Vec3 = Vec3.zero, // update() 计算；snap 关闭时 == target
    pub fn effectivePpu(self: *const IsoCamera) f32;
    pub fn snapToPixel(self: *const IsoCamera, p: Vec3) Vec3;
};
pub const iso_ppu: f32 = 90.50967;          // 128/√2
pub const iso_height_unit: f32 = 0.408248;  // 1/√6
```
非有限或 ≤ 0 的 ppu 视为 0。

### A3.3 `src/iso/tilemap.zig`
```zig
pub const TileDef = struct { top: u16, side: u16, solid: bool = false, liquid: bool = false,
                             opaque: bool = false, tag: u8 = 0,
                             side_cap: u16 = 0xFFFF };  // 最上面一段（2 级）侧面用的图集格；0xFFFF = 同 side。用于墙檐、窗楣
pub const Flag = struct { pub const blocked: u8 = 1; pub const opaque: u8 = 2; };
pub const chunk_size: u32 = 16;
pub const TileMap = struct {
    flags: []u8, tag: []u8,
    chunk_dirty: []bool, chunks_w: u32, chunks_h: u32,
    opacity_version: u32 = 0,
    pub fn getFlags(self, x: i32, y: i32) u8;             // 越界 → blocked|opaque
    pub fn setFlag(self, x, y, mask: u8, on: bool) void;  // 不置网格脏
    pub fn getTag(self, x, y) u8;  pub fn setTag(self, x, y, v: u8) void;
    pub fn isOpaque(self, x, y) bool;
    pub fn markDirtyAround(self, x, y) void;              // (x±1,y±1) 所在块
    pub fn markAllDirty(self) void;
};
```
`set()` 只脏化邻近块；`fill/resize` 全脏。`findPath` 保留为薄包装，既有测试不改。

### A3.4 `src/iso/pathfind.zig`
```zig
pub const PathFinder = struct {
    pub fn init(allocator) PathFinder;  pub fn deinit(self) void;
    /// 起点(不含)→终点(含)。goal_adjacent=true 时终点可以不可走，路径止于其相邻可走格
    pub fn find(self, map: *const TileMap, from: GridPos, to: GridPos,
                goal_adjacent: bool, out: *std.ArrayList(GridPos)) !bool;
    /// BFS：把 max_steps 步内可达格并入 mask；返回并入的格数
    pub fn reach(self, map: *const TileMap, from: GridPos, max_steps: u32, mask: *vision.Mask) !u32;
};
```

### A3.5 `src/iso/vision.zig`
```zig
pub const max_masks = 16;  pub const max_radius: i32 = 32;
pub const Mask = struct { cells: []u8, w: u32, h: u32, count: u32 = 0, version: u32 = 0,
    min_x: i32, min_y: i32, max_x: i32, max_y: i32,
    pub fn get(self, x, y) bool;  pub fn set(self, x, y) void;  pub fn clear(self) void;
    pub fn orWith(self, other: *const Mask) void; };
pub const MaskSet = struct {
    pub fn init(allocator, w, h) !MaskSet;  pub fn deinit(self) void;
    pub fn resize(self, w, h) !void;
    pub fn get(self, id: u32) ?*Mask;        // 1..16
};
pub fn los(map: *const TileMap, x0: i32, y0: i32, x1: i32, y1: i32) bool;
pub const Cone = struct { fx: f32 = 0, fy: f32 = 0, half_angle_deg: f32 = 180 };
pub fn canSee(map, ox, oy, radius: f32, cone: Cone, tx, ty) bool;   // 距离 + 锥角 + los
pub fn fov(map, ox, oy, radius: f32, cone: Cone, mask: *Mask) u32;  // 并入 mask，返回新增格数
```
端点越界 → false。锥角判定全部用乘法（`dot(d,f) >= cos(half)·|d|·|f|`）。

### A3.6 `src/iso/lightmap.zig`
```zig
pub const max_lights = 64;  pub const max_light_radius: i32 = 16;
pub const Light = struct { used: bool = false, enabled: bool = true, x: f32, z: f32,
                           radius: f32, color: [3]f32, dirty: bool = true };
pub const Fog = struct { visible: u32 = 0, explored: u32 = 0, explored_k: f32 = 0.4, unknown_k: f32 = 0.0 };
pub const LightMap = struct {
    ambient: [3]u8 = .{255,255,255}, fog: Fog = .{},
    rgb: [][3]u8,      // 含迷雾，tilemesh 与实体取光用
    lit: [][3]u8,      // 不含迷雾，light_level 用
    pub fn init(allocator, w, h) !LightMap;  pub fn deinit(self) void;  pub fn resize(self, w, h) !void;
    pub fn add(self, l: Light) u32;          // 1..64，0 = 满
    pub fn get(self, id: u32) ?*Light;
    pub fn remove(self, id: u32) void;  pub fn clear(self) void;
    pub fn setAmbient(self, r: f32, g: f32, b: f32) void;
    pub fn update(self, map: *TileMap, masks: *const MaskSet) u32;   // 返回变化格数，并置脏相关块
    pub fn level(self, x: i32, y: i32) f32;  // max(r,g,b)，越界 0
    pub fn sample(self, x: i32, y: i32) [3]f32;
};
```

### A3.7 `src/iso/tilemesh.zig`
```zig
pub const Quad = struct { p: [4][3]f32,     // BL, BR, TR, TL（世界坐标）
                          atlas: u16, v_top: f32, v_bot: f32, c: [4][3]u8 };
pub const Params = struct { side_levels: u8 = 2, light_top: f32 = 1.0, light_x: f32 = 0.78, light_z: f32 = 0.62 };
pub fn cornerLight(map: *const TileMap, rgb: []const [3]u8, cx: i32, cy: i32, ref_height: u8, fallback: [3]u8) [3]u8;
pub fn buildChunk(allocator, map: *const TileMap, rgb: []const [3]u8, cx: u32, cy: u32,
                  params: Params, out: *std.ArrayList(Quad)) !void;
pub const Aabb = struct { min: Vec3, max: Vec3 };
pub fn chunkBounds(map: *const TileMap, cx: u32, cy: u32) Aabb;
pub fn chunkVisible(cam: *const IsoCamera, box: Aabb) bool;
```
顶面与四个侧面的角点必须用单测对照旧矩阵逐角一致（`S/src/iso/render.zig:254,259-264`）。
侧面从 level 0 起每 `side_levels` 级一段；最上面一段（高度不足时按比例裁 V）使用 `side_cap`（未设置时同 `side`）。

### A3.8 `overlay.zig`、`world.zig`、`render.zig`、`engine.zig`
```zig
// overlay.zig
pub const max_groups = 16;  pub const max_cells = 8192;
pub const Cell = struct { x: i16, y: i16, rgba: [4]u8, atlas: u16 = 0xFFFF };   // atlas = 地块图集格号，0xFFFF = 纯色
pub const Overlays = struct { groups: [max_groups]std.ArrayList(Cell), total: u32 = 0, dirty: bool = true,
    pub fn add(self, g: u32, x: i32, y: i32, rgba: [4]u8) void;
    pub fn addTex(self, g: u32, x: i32, y: i32, atlas: u16, rgba: [4]u8) void;
    pub fn addMask(self, g: u32, m: *const vision.Mask, rgba: [4]u8) void;
    pub fn clear(self, g: u32) void;  pub fn clearAll(self) void; };

// world.zig：Entity 新增/变更字段
gen: u16 = 0, visible: bool = true, lit: bool = true, pickable: bool = true,
light: [3]f32 = .{1,1,1},
path: [256]GridPos = undefined, path_len: u16 = 0, path_idx: u16 = 0,
pub fn World.clear(self) void;            // 逐个 despawn，代数递增
pub fn World.applyLight(self, lm: *const LightMap, map: *const TileMap, dt: f32) void; // 平滑趋近所在格的光
pub const PickHit = struct { id: u32, u: f32, v: f32 };
pub fn World.pickCandidates(self, cam: *const IsoCamera, sx: f32, sy: f32, out: []PickHit) usize; // 由近到远

// render.zig
pub fn WorldRenderer.draw(self, map: *TileMap, world: *World, cam: *IsoCamera,
                          lm: *const LightMap, ov: *Overlays) void;
pub fn WorldRenderer.setTint(self, c: Color) void;
pub fn WorldRenderer.alphaAt(self, sheet: u32, frame: u16, flip: bool, u: f32, v: f32) ?u8;
pub fn WorldRenderer.dropChunks(self) void;

// engine.zig
pub const Config = struct { ..., max_dt: f32 = 0.1, dev_hot_reload: bool = false,
                            pixels_per_unit: f32 = 0, snap_pixels: bool = false };
pub var masks: vision.MaskSet; pub var lights: lightmap.LightMap;
pub var overlays: overlay.Overlays; pub var pathfinder: pathfind.PathFinder;
pub fn clearWorld() void;
```
精灵色 = `tint × (lit ? light : 1)`；不可见实体跳过。`addSheet` 按 `(纹理, 帧宽, 帧高)` 去重。`map_create` 同步重置掩码、光照和块批次。

### A3.9 字体：`.fnt` 格式与 `src/kit/text.zig`
```
Header 32 字节 LE:  magic "WSFN" | version u16=1 | px u16 | line_height u16 | ascent u16 |
                    atlas_w u16 | atlas_h u16 | glyph_count u32 | fallback_cp u32 | 8 字节保留
Glyph 16 字节 × n（按 cp 升序）: cp u32 | x u16 | y u16 | w u8 | h u8 | xoff i8 | yoff i8 | advance u8 | 3 字节保留
Python: struct '<4sHHHHHHII8x' 与 '<IHHBBbbB3x'；文件长度必须 == 32 + 16n
```
```zig
pub const Glyph = struct { cp: u32, x: u16, y: u16, w: u8, h: u8, xoff: i8, yoff: i8, advance: u8 };
pub const Font = struct { px: u16, line_height: u16, ascent: u16, atlas_w: u16, atlas_h: u16,
    fallback: u32, glyphs: []Glyph,
    pub fn parse(allocator, bytes: []const u8) !Font;   // 校验 magic/version/长度/升序/矩形在图集内
    pub fn deinit(self, allocator) void;
    pub fn glyph(self, cp: u32) ?Glyph;                  // 二分；缺失返回回退字形
    pub fn has(self, cp: u32) bool; };
pub const Utf8Iter = struct { bytes: []const u8, i: usize = 0, pub fn next(self) ?u32; };
pub fn measure(font: *const Font, s: []const u8) u32;
pub const Line = struct { start: u32, end: u32, width: u32 };
pub const max_lines = 256;  pub const max_text_bytes = 16 * 1024;
pub fn wrap(font: *const Font, s: []const u8, max_w: u32, out: []Line) usize;
pub fn isCjkBreakable(cp: u32) bool;  pub fn noLineStart(cp: u32) bool;  pub fn noLineEnd(cp: u32) bool;
```

### A3.10 `src/kit/ui_geom.zig` 与 `ui.zig`
```zig
// ui_geom.zig（纯）
pub const Rect = struct { x: f32, y: f32, w: f32, h: f32 };
pub const UvQuad = struct { dst: Rect, u0: f32, v0: f32, u1: f32, v1: f32 };
pub fn clip(q: UvQuad, c: Rect) ?UvQuad;
pub fn nineSlice(src: Rect, l: f32, t: f32, r: f32, b: f32, dst: Rect, out: *[9]struct { src: Rect, dst: Rect }) usize;
// ui.zig：模块 kit_ui(-55)；pre_draw 清指令；draw 提交
pub fn register() !void;
pub fn loadFont(png: []const u8, fnt: []const u8) u32;   // 1..8，0 失败
pub fn loadImage(path: []const u8) u32;
pub fn pushQuad(tex: u32, q: ui_geom.UvQuad, rgba: [4]f32) void;
pub fn drawText(font: u32, s: []const u8, x: f32, y: f32, max_glyphs: i32) void;
pub fn drawTextBox(font: u32, s: []const u8, x: f32, y: f32, w: f32, alignment: u8, max_glyphs: i32) f32;
```
headless 下指令照常记录，可查 `quadCount()`，绘制为空操作。

### A3.11 `pad_logic.zig`、`gamepad.zig`、`rawinput.zig`
```zig
// pad_logic.zig（纯）
pub const Button = enum(u8) { a, b, x, y, lb, rb, back, start, l3, r3, dpad_up, dpad_down, dpad_left, dpad_right, lt, rt, guide };
pub const Axis = enum(u8) { lx, ly, rx, ry, lt, rt };
pub const RawState = struct { buttons: [32]bool, axes: [16]f32, n_buttons: u8, n_axes: u8 };
pub const Mapping = struct { button: [17]i8, axis: [6]i8, axis_invert: [6]bool,
                             hat_x: i8, hat_y: i8, trigger_bipolar: bool,
    pub const xpad: Mapping; };   // 按钮 0 A,1 B,2 X,3 Y,4 LB,5 RB,6 Back,7 Start,8 Guide,9 L3,10 R3；轴 0 LX,1 LY,2 LT,3 RX,4 RY,5 RT,6/7 十字键
pub const Tuning = struct { stick_deadzone: f32 = 0.24, trigger_deadzone: f32 = 0.12,
                            trigger_press: f32 = 0.5, trigger_release: f32 = 0.4, hat_threshold: f32 = 0.5 };
pub fn stick(x: f32, y: f32, dz: f32) [2]f32;            // 径向死区 + 重标定
pub fn trigger(raw: f32, bipolar: bool, dz: f32) f32;    // → 0..1
pub const Logical = struct { down: [17]bool, pressed: [17]bool, released: [17]bool, axes: [6]f32,
    pub fn update(self: *Logical, raw: *const RawState, map: *const Mapping, t: Tuning) void; };
// gamepad.zig
pub fn poll(dt: f32) void;
pub fn connected() bool;  pub fn name() []const u8;  pub fn logical() *const pad_logic.Logical;
pub fn lastRaw() ?struct { is_axis: bool, index: u8, value: f32 };
pub fn setMapping(m: pad_logic.Mapping) void;
pub fn injectButton(b: pad_logic.Button, down: bool) void;  pub fn injectAxis(a: pad_logic.Axis, v: f32) void;
// rawinput.zig：模块 kit_input(-75)
pub const Device = enum(u8) { keyboard = 0, mouse = 1, pad = 2 };
pub fn register(cfg: struct { dev_console: bool = false }) !void;
pub fn keyReleased(code: i32) bool;  pub fn mouseReleased(btn: i32) bool;
pub fn lastKey() ?i32;
pub fn lastMouseButton() ?i32;      // 本帧第一个 just_pressed 的鼠标键（改键界面用）
pub fn lastDevice() Device;
```
- 后端按 `builtin.os.tag` 编译期选择，Linux 不链接额外库；Windows 只引用 kernel32，从 Linux 交叉编译不需要 xinput 导入库。
- Linux：`open(O_RDONLY|O_NONBLOCK)`；`EAGAIN` = 无事件，`ENODEV` = 拔出；每帧最多读 256 个事件；扳机轴在收到首个事件前记为 −1。
- 逻辑状态 = 物理手柄 OR 探针注入。

### A3.12 `audio.zig`、`sys.zig`
```zig
// audio.zig
pub const Bus = enum { master, sfx, bgm, amb };
pub fn amb(layer: u32, id: []const u8, fade_s: f32) bool;   // layer 1..3
pub fn stopAmb(layer: u32, fade_s: f32) void;
pub fn ambGain(layer: u32, v: f32, fade_s: f32) bool;
pub fn currentAmb(layer: u32) ?[]const u8;
// sys.zig
pub fn configure(save_dir: []const u8) void;
```
`bgm()/stopBgm()` 改为操作通道 0，对外行为不变。无声模式下通道记账照常。

## A4. Lua API

### A4.1 `iso` 新增/变更
| 函数 | 说明 |
|---|---|
| `tile_define_ex(top, side, side_cap, solid, liquid, opaque, tag)` → kind | `side_cap` 传 -1 表示同 `side`。旧 `tile_define` 保留，等价于 `side_cap = -1, opaque = solid, tag = 0` |
| `map_set_height_unit(u)` / `map_set_base_depth(d)` | 全图置脏 |
| `tile_set_blocked(x,y,b)` / `tile_set_opaque(x,y,b)` / `tile_set_tag(x,y,v)` | 不重建网格 |
| `tile_flags(x,y)` → `{blocked, opaque, tag}` 或 nil | |
| `path_find_adjacent(x0,y0,x1,y1)` → 路径或 nil | 走到家具/门旁 |
| `entity_path_to(id,tx,ty)` → bool | 上限 256 步 |
| `los(x0,y0,x1,y1)` → bool | |
| `vision_can_see(ox,oy,radius,fx,fy,half_deg,tx,ty)` → bool | NPC 侦测用 |
| `mask_clear(m)` / `mask_or(dst,src)` / `mask_count(m)` | m = 1..16 |
| `fov_compute(m,ox,oy,radius,fx,fy,half_deg)` → 新增格数 | 并入 m |
| `fov_visible(m,x,y)` → bool | |
| `reach_compute(m,x,y,max_steps)` → 格数 | BFS 可达 |
| `fog_set(visible_m, explored_m)` / `fog_set_levels(explored_k, unknown_k)` | 0,0 关闭迷雾 |
| `light_set_ambient(r,g,b)` | |
| `light_add(x,z,radius,r,g,b)` → id（0 = 满） | radius ≤ 16 |
| `light_set_pos` / `light_set_radius` / `light_set_color` / `light_set_enabled` / `light_remove` / `light_clear` | |
| `light_level(x,y)` → 0..1 | 不含迷雾，潜行判定用 |
| `world_set_tint(r,g,b)` | 整体乘色 |
| `overlay_add(g,x,y,r,g2,b,a)` / `overlay_add_tex(g,x,y,atlas,r,g2,b,a)` / `overlay_add_mask(g,m,r,g2,b,a)` / `overlay_clear(g)` / `overlay_clear_all()` | g = 0..15，组号含义见 §A1 第 13 条 |
| `entity_set_visible(id,b)` / `entity_set_lit(id,b)` / `entity_set_pickable(id,b)` | |
| `entity_set_size(id,w,h)` / `entity_set_size_px(id,wpx,hpx)` | |
| `entity_set_sheet(id,sheet)` | 同时停动画 |
| `entity_pick(sx,sy,alpha_test)` → id 或 nil | 最前者优先；被更近的瓦片遮挡则跳过 |
| `world_clear()` | 清实体/覆盖层/光源/掩码；图集与精灵表保留 |
| `camera_set_ppu(ppu)` / `camera_get_ppu()` / `camera_set_snap(b)` | |
| `px_to_world(px)` → number | |

### A4.2 `ui`
| 函数 | 说明 |
|---|---|
| `font_load(png, fnt)` → font / `font_line_height(font)` | 最多 8 个 |
| `image_load(path)` → tex / `image_size(tex)` → `{w,h}` | |
| `color(r,g,b,a)` / `color_hex(0xRRGGBBAA)` | 当前色，作用于其后的绘制 |
| `set_scale(n)` / `screen_size()` / `mouse_pos()` | 虚拟像素 |
| `set_text_scale(n)` / `text_shadow(dx,dy,r,g,b,a)` / `text_shadow_off()` | |
| `text(font,str,x,y)` / `text_width(font,str)` | |
| `text_box(font,str,x,y,w,align,max_glyphs)` → 高度 | align 0/1/2 = 左/中/右；`max_glyphs = -1` 全部（打字机效果） |
| `text_measure(font,str,w)` → `{w,h,lines}` / `text_wrap(font,str,w)` → 字节区间列表 | |
| `rect(x,y,w,h)` | 实心 |
| `image(tex,sx,sy,sw,sh,dx,dy,dw,dh)` | 当前色作染色和透明度 |
| `nine_slice(tex,sx,sy,sw,sh,l,t,r,b,dx,dy,dw,dh)` | |
| `clip(x,y,w,h)` / `clip_off()` | 不嵌套 |
| `quad_count()` → n | 探针断言用 |

### A4.3 音频、`sys`、输入
| 函数 | 说明 |
|---|---|
| `audio.amb(layer, id, fade)` / `audio.stop_amb(layer, fade)` / `audio.amb_gain(layer, v, fade)` / `audio.current_amb(layer)` | layer 1..3；id 须为 `bgm/amb/...`。参数顺序与 Zig 侧 `amb(layer, id, fade_s)` 一致 |
| `audio.set_bus("amb", v)` | 新总线 |
| `sys.save_write(name, text)` → bool / `sys.save_read(name)` → string 或 nil | 原子写 |
| `sys.save_list()` / `sys.save_delete(name)` / `sys.save_exists(name)` | |
| `sys.lua_heap()` → `{bytes, peak}` / `sys.platform()` | |
| `kit_input.key_released(code)` / `mouse_released(btn)` / `last_key()` / `last_mouse_button()` / `last_device()` | |
| `pad.connected()` / `pad.name()` / `pad.button_down(b)` / `button_pressed(b)` / `button_released(b)` / `pad.axis(a)` | 全局表 `pad_buttons`、`pad_axes` |
| `pad.rumble(l, r, ms)` → false | v1 预留，不做震动 |
| `pad.last_button()` / `pad.last_raw()` / `pad.set_mapping(kind, logical, raw_index, invert)` / `pad.reset_mapping()` | 改键与校准。`last_button` 覆盖全部 17 个逻辑按钮，LT/RT 以 `trigger_press` 阈值的数字边沿计入 |
| `kit_probe.pad_button(b, down)` / `kit_probe.pad_axis(a, v)` | 注入虚拟手柄 |
| `kit_probe.mouse_button(button, down)` | 跨帧按住 / 松开鼠标键 |

## A5. 单元测试（`zig build test` 必须覆盖）

- **camera**：ppu 模式下相邻格角屏幕距离正确；抬高一级上移 32±0.01 px；改视口后 ppu 不变；吸附后原点投影为整数（宽度奇偶各测）；`screenToRay(worldToScreen(p))` 回到 p；NaN/负 ppu 被忽略。
- **tilemap**：`set` 复位 flags/tag；`setFlag` 不置块脏；`opaque` 变化使版本号递增；`blocked` 影响可走性；`set` 只脏化邻近块；越界 `getFlags = 3`。
- **pathfind**：200 张随机图上与旧 `findPath` 长度一致；绕开 blocked；`goal_adjacent`；64×64 蛇形迷宫超 64 步完整返回；`reach` 步数边界；换图后 scratch 不串。
- **vision**：对称性（随机 1000 对）；端点为墙仍可见；对角缝规则；越界 false；锥形四种情形；`fov` 与逐格 `canSee` 完全一致；NaN 半径无操作。
- **lightmap**：无光源 = 环境光；单光源衰减；墙后为环境光；移动光源只返回受影响格；迷雾三态；`opaque` 翻转触发重算；第 65 个光源返回 0。
- **tilemesh**：顶面与四侧面角点对照旧矩阵；平地 16×16 = 256 个四边形；墙高 6 每露出面 3 段且最上一段取 `side_cap`；奇数高度 V 裁剪 0.5；角点光同高平均、不同高不混；`chunkVisible`。
- **overlay**：分组、上限截断、`addMask` 计数、`addTex` 的图集格号越界被拒。
- **world**：槽位复用后旧 id 失效；`clear` 后旧 id 全失效；路径 256 截断；`pickCandidates` 的顺序与过滤。
- **vm.LuaHeap**：计数归零、超限返回 null、realloc 增减。
- **text**：坏文件被拒；UTF-8 合法/截断/过长编码；中文任意断、英文按词断、韩文按空格断、超长单词强制断；禁则；256 行上限。
- **ui_geom**：全内、全外、四向部分裁剪的 UV；九宫格各种片数与压缩。
- **pad_logic**：径向死区边界与满偏；双极扳机；扳机滞回；十字键阈值；重映射；边沿各只持续一帧。
- **save_name**：合法与非法（`../x`、空、33 字符、大写、带点）。

## A6. 子任务

| # | 任务 | 代理 | 依赖 | 验收 |
|---|---|---|---|---|
| X1 | `vm.zig` + `script_host`/`probe` 改用自建 VM；`max_dt`、`dev_hot_reload`；`--dev` | coder-sonnet | M0 | `grep -rn "lua_util.getLua\|manager.init\|lua_util.runLine" src` 无结果；现有探针通过；退出无泄漏报告 |
| X2 | `camera.zig` 像素模式 + 吸附 + 绑定 | coder-sonnet | X1 | A5 camera；1280×720 截图量得菱形 128×64、角色 64×96 |
| X3 | `tilemap.zig` flags/tag/块脏 + `pathfind.zig` | coder-sonnet | X1 | A5 两组；旧 tilemap 测试除 dirty 语义外不改 |
| X4 | `vision.zig` | coder-sonnet | X3 | A5 vision；不 import graphics/app/input |
| X5 | `lightmap.zig` | coder-sonnet | X4 | A5 lightmap |
| X6 | `tilemesh.zig` + `overlay.zig` | coder-sonnet | X5 | A5 两组 |
| X7 | `world.zig` 代数 id、字段、pick、path 256 | coder-sonnet | X3 | A5 world |
| X8 | `render.zig` 分块/覆盖层/精灵 + `engine.zig` 胶水 | coder-sonnet | X2,X6,X7 | 64×64 墙高 6 的图无 quad 超限警告；改 1 格只重建 ≤4 块（调试计数器，探针断言）；headless 探针通过 |
| X9 | `lua_api.zig` 全部 `iso` 新绑定 + README API 表 | coder-haiku | X8 | 每个函数用 NaN/Inf/负数/越界调用不 panic；辅助函数无 `pub` |
| X10 | `text.zig` + `ui_geom.zig` | coder-sonnet | X1 | A5 两组 |
| X11 | `tools/bake_font.py` + `fonts.json` + 测试 + `assets.py check` 挂钩 | coder-sonnet | X10 | 同输入两次输出逐字节相同；i18n 出现图集外字符时 `--check` 非 0；`Font.parse` 能读产物 |
| X12 | `ui.zig` + `lua_ui.zig` | coder-sonnet | X10,X11 | 截图：中/英/韩三行、九宫格、裁剪、半透明叠在世界之上；headless `quad_count()` 断言 |
| X13 | 音频环境层 | coder-haiku | X1 | `--no-audio` 探针：两层并存、`current_amb`、总线；`assets.py` 测试通过 |
| X14 | `pad_logic.zig` + `gamepad.zig`（三后端） | coder-sonnet | X1 | A5 pad_logic；`-Dtarget=x86_64-windows` 交叉编译通过；本机 js0 插拔不崩；无手柄时不刷日志 |
| X15 | `rawinput.zig` + `lua_input.zig` + 探针注入 | coder-haiku | X14 | 注入 A 键 → pressed 一帧 → released 一帧；`click` 当帧 `mouse_released` 为真；`last_device` 切换 |
| X16 | `sys.zig` + `save_name.zig` + `--save-dir` | coder-haiku | X1 | 写→列→读→删往返；非法名返回 false；不留半截文件 |
| X17 | `luatest` 步骤 + `--script` + `tests/lua/*` + CI 接线 | coder-haiku | X1 | `zig build luatest -Dbackend=headless` 本机 10 s 内跑完示例；失败用例使退出码非 0 |
| X18 | 探针 `engine_ext.lua` / `ui_text.lua` / `soak_heap.lua` | coder-haiku | X9,X12,X16 | 浸泡：30 s 内每帧造 1 MB 垃圾，`lua_heap().bytes` 末值低于峰值且低于 64 MB |

`luatest` 约定：以 `--script tests/lua/main.lua --probe tests/lua/runner.lua --no-audio` 启动；`main.lua` 不定义 `_init`；`runner.lua` 在第一次 `_probe` 里加载全部 `tests/lua/test_*.lua`，每个用例 `pcall` 后 `kit_probe.check(name, ok)`，最后 `finish()`。`balance` 步骤同理，入口换成 `tests/lua/mc_balance.lua`，并用 `kit_probe.timeout` 放宽时限。

## A7. 风险

### A7.1 实现风险
1. **sokol 同一缓冲每帧只能更新一次**：所有 `apply()` 只在 draw 路径，每块每帧至多一次；X8 在调试构建加帧内计数断言。
2. **`Batcher` 超限会越界写**：所有批次在 `addRectangle` 前自查四边形数，不依赖框架报错。
3. **覆写顶点缓冲依赖框架内部布局**：只依赖三件已核实的事（顶点顺序、索引模式、`PackedVertex` 字段）。X8 加启动自检：`addRectangle` 后 `vertex_pos` 增 4、`index_pos` 增 6，否则 `debug.fatal`。
4. **误用 `lua_util` 全局会解引用未初始化指针**：X1 的 grep 验收同时进 CI。
5. **`smp_allocator` 不做泄漏检测**：用 `LuaHeap.bytes == 0` 在 `deinit` 断言弥补。
6. **光照/迷雾频繁变化导致重建过多**：光源缓存 + u8 量化 + 只脏化变化格；Lua 侧约定迷雾和 FOV 以 10 Hz 更新；块重建计数器暴露给探针做回归。
7. **不支持半透明实体**：tint 的 alpha 低于 0.5 整体消失。"半隐"效果用抖动贴图或覆盖层。
8. **Zig 0.16 的 `std.Io` 文件操作、`Allocator.VTable`、`std.os.linux` 签名未逐一核对**：X1、X14、X16 的实现者先读 std 源码。
9. **高 DPI**：鼠标坐标与窗口尺寸可能不一致，本期不处理。
10. **长模拟的探针**：headless 锁 60 FPS、dt 为墙钟；单帧 Lua 不得超过 20 s，批量模拟要分帧跑并放宽 `kit_probe.timeout`。

### A7.2 需要改 delve-framework 才能做的事（本计划都不依赖）
| 功能 | 现状 | 最小补丁 |
|---|---|---|
| 鼠标滚轮 | `MOUSE_SCROLL` 被丢弃 | `backends/sokol/app.zig` 加一个分支转给 `input.onMouseScroll`，`input.zig` 加状态与查询，约 12 行 |
| 文本输入 | `CHAR` 只进控制台 | `input.onKeyChar` 追加本帧字符队列，约 10 行。本作不需要输入文字 |
