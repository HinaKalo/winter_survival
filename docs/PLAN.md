# iso-base 架构计划（v1）

基于 Delve Framework（`../delve-framework`，Zig 0.16.0 + Lua 5.4）的等距伪 2.5D 游戏基座。
目标：Zig 层提供“世界 / 地图 / 相机 / 实体 / 渲染 / 寻路 / Lua 宿主”，游戏逻辑全部写在 Lua，开新游戏只需改 `assets/`。

## 0. 核心设计决策（子代理不得更改）

1. **真 3D 世界 + 正交等距相机**（不是 2D 菱形贴图排序）。地面瓦片是 3D 方块面，角色是竖直的 billboard 精灵；遮挡关系交给**深度缓冲**，精灵用 `alpha_cutoff = 0.5` 镂空、不做混合 ⇒ **无需任何手工排序**。
2. **坐标约定**：右手系，Y 向上。格子 `(gx, gy)` 占据世界 `X∈[gx,gx+1]`、`Z∈[gy,gy+1]`；格子中心 `(gx+0.5, topY, gy+0.5)`；`topY = height * height_unit`（默认 `height_unit = 0.5`）。
3. **相机**：`eye = target + distance * (cos(p)·sin(y), sin(p), cos(p)·cos(y))`，`y = yaw`、`p = pitch`（度）。默认 `yaw = 45`、`pitch = 30`（2:1 像素等距观感），可切 35.264（真等距）。投影 `Mat4.ortho(-hw, hw, -hh, hh, near, far)`，`hh = view_height / (2*zoom)`，`hw = hh*aspect`。
4. **精灵 billboard**：竖直四边形，脚底锚点（底边中点）在实体 `pos`；模型矩阵 = `translate(pos) * rotateY(yaw) * scale(1, 1/cos(pitch), 1)`，使正交投影下像素纵横比不被压扁。`rotate(yaw, up)` 作用于 `(0,0,1)` 必须得到 `(sin yaw, 0, cos yaw)`（即朝向 eye 的水平方向）——有单元测试保证。
5. **深度重映射（HUD 置顶）**：Delve 的 Lua 2D API（`draw`/`text`/`graphics`）绘制深度约为 NDC z≈0.4999。世界投影矩阵左乘一个重映射矩阵，`z' = 0.25*z + 0.75*w`，把世界深度压到 `[0.5, 1]`，HUD 永远在世界之上。实现为纯函数 `camera.remapDepthToBackHalf(proj) Mat4`，带测试：near 平面点 → z_ndc=0.5，far 平面点 → 1.0。
6. **模块优先级（数值越小越先）**：Delve 的 scriptapi 库模块是 `Priority.first = -50`，它们在 `pre_draw` 里 reset、在 `draw` 里提交。因此：
   - `iso_world`（世界 tick + 世界渲染）：priority **-70**
   - `iso_script_host`（Lua `_update`/`_draw`）：priority **-60**（`_draw` 里 Lua 排入的 HUD 指令会在 -50 的 libDraw 中被画出）
   - tick 顺序：world(-70) 先 tick 实体 → script(-60) 调 `_update(dt)`。
7. **纯逻辑 / 图形分离**：`coords / camera / tilemap / world` 只依赖 `delve.math` 和 std，**不得**调用任何 graphics/app/input，以便 `zig build test` 直接单测。图形只出现在 `render.zig`，引擎胶水在 `engine.zig`。
8. 纹理统一走 Delve 的 `delve.api.assets.get_texture(path)` 句柄（u32）缓存，生命周期由 Delve assets 库管理；尺寸通过 `assets._getImageFromHandle(h)` 获取。我们为每个纹理句柄缓存一个 `graphics.Material`（`samplers = &.{.NEAREST}`、`cull_mode = .NONE`、`alpha_cutoff = 0.5`、`blend_mode = .NONE`），在 cleanup 时 deinit。

9. **输入健壮性（v1.1 新增，所有层强制）**：任何 pub 函数收到的浮点参数（坐标、方向、dt、距离、缩放、速度等）都可能是 NaN/Inf/负数/极大值——因为它们最终可由 Lua 传入。规则：
   - 浮点→整数一律经检查（`isFinite` + 范围）后再 `@intFromFloat`；整数↔整数一律 `std.math.cast`/clamp，不得裸 `@intCast`。
   - 所有循环的迭代次数必须有与输入无关的整数上限（不得用 `f32` 累加作为循环变量）。
   - `dt` 非有限或 < 0 时视为 0；`max_dist` 等非有限/负数时直接返回“无结果”。
   - 非法输入的结果是“安全无操作/返回 null”，不得 panic、不得挂起、不得把 NaN 写入持久状态。

## 1. 目录结构

```
iso-base/
  mise.toml                 zig = "0.16.0"
  build.zig.zon             .delve = .{ .path = "../delve-framework" }
  build.zig                 exe "iso-game"; steps: run(cwd=项目根), test
  .gitignore                .zig-cache/ zig-out/ zig-pkg/
  README.md                 中文：快速开始、架构、Lua API 参考、约定
  docs/PLAN.md              本文件
  src/main.zig              入口（游戏专属，极简）
  src/iso/root.zig          `iso` Zig 模块根，pub 重导出下列文件
  src/iso/coords.zig        纯：Dir、screenDirection、GridPos
  src/iso/camera.zig        纯：IsoCamera、Ray、remapDepthToBackHalf
  src/iso/tilemap.zig       纯：TileDef、Tile、TileMap、A*、raycastPick
  src/iso/world.zig         纯：Entity、World（动画、移动、路径跟随）
  src/iso/tests.zig         测试根：引用上面四个纯文件
  src/iso/render.zig        图形：TileAtlas、SpriteSheet、WorldRenderer
  src/iso/engine.zig        全局状态 + 注册 iso_world 模块 + register(config)
  src/iso/script_host.zig   Lua 生命周期 + F5 热重载 + 错误恢复
  src/iso/lua_api.zig       Lua 库 `iso`
  assets/main.lua           演示游戏入口
  assets/scripts/*.lua      演示游戏子模块（require 可达）
  assets/textures/tiles.png 瓦片图集（生成）
  assets/sprites/hero.png   主角 4 方向 × 4 帧（生成）
  assets/sprites/slime.png  史莱姆 1 行 × 4 帧（生成）
  tools/gen_assets.py       Pillow 占位美术生成器
```

## 2. 接口定义

### coords.zig
```zig
pub const Dir = enum(u8) { down = 0, left = 1, right = 2, up = 3 }; // 屏幕空间方向，对应精灵表行号
/// 世界水平位移(dx,dz) 在当前相机 yaw 下对应的屏幕朝向；零向量返回 null
pub fn screenDirection(dx: f32, dz: f32, yaw_deg: f32) ?Dir;
pub const GridPos = struct { x: i32, y: i32 };
```
`screenDirection` 规则：把 (dx,dz) 投到相机水平 right / forward 轴上，取绝对值较大的分量；朝向相机（屏幕下方）= down。

### camera.zig
```zig
pub const Ray = struct { origin: Vec3, dir: Vec3 };
pub const IsoCamera = struct {
    target: Vec3 = Vec3.zero,
    yaw: f32 = 45.0, pitch: f32 = 30.0,
    yaw_goal: f32 = 45.0,          // rotateStep 设定，tick 平滑逼近（每秒 ~8 倍差值的指数平滑）
    distance: f32 = 60.0,
    zoom: f32 = 1.0, min_zoom: f32 = 0.25, max_zoom: f32 = 4.0,
    view_height: f32 = 14.0,
    near: f32 = 0.1, far: f32 = 200.0,
    follow_smoothing: f32 = 8.0,   // 0 = 瞬移
    follow_goal: ?Vec3 = null,
    view: Mat4 = Mat4.identity, proj: Mat4 = Mat4.identity,
    viewport_w: f32 = 1, viewport_h: f32 = 1,

    pub fn eyePosition(self: *const IsoCamera) Vec3;
    pub fn forward(self: *const IsoCamera) Vec3;          // eye→target 单位向量
    pub fn right(self: *const IsoCamera) Vec3;
    pub fn camUp(self: *const IsoCamera) Vec3;
    pub fn rotateStep(self: *IsoCamera, steps: i32) void; // yaw_goal += 90*steps
    pub fn setZoom(self: *IsoCamera, z: f32) void;        // clamp
    pub fn tick(self: *IsoCamera, dt: f32) void;          // yaw 平滑 + follow 平滑
    pub fn update(self: *IsoCamera, viewport_w: f32, viewport_h: f32) void; // 计算 view/proj
    pub fn screenToRay(self: *const IsoCamera, sx: f32, sy: f32) Ray; // 像素坐标，左上为原点
    pub fn screenToPlane(self: *const IsoCamera, sx: f32, sy: f32, plane_y: f32) ?Vec3;
    pub fn worldToScreen(self: *const IsoCamera, p: Vec3) Vec2;
};
pub fn remapDepthToBackHalf(proj: Mat4) Mat4;
```
`screenToRay`：`ndc_x = sx/vw*2-1`，`ndc_y = 1-sy/vh*2`；`origin = eye + right*ndc_x*hw + camUp*ndc_y*hh`；`dir = forward`。

### tilemap.zig
```zig
pub const TileDef = struct { top: u16, side: u16, solid: bool = false, liquid: bool = false };
pub const Tile = struct { kind: u16 = 0, height: u8 = 0 }; // kind 0 = 空（不绘制、不可走）
pub const TileHit = struct { x: i32, y: i32, point: Vec3 };
pub const TileMap = struct {
    allocator: Allocator, width: u32, height: u32, tiles: []Tile,
    defs: std.ArrayList(TileDef),   // 下标 0 预留为空
    height_unit: f32 = 0.5,
    base_depth: f32 = 1.0,          // 地图边缘侧面向下延伸到 y = -base_depth
    max_step: u8 = 1,               // 寻路/行走允许的相邻高度差
    dirty: bool = true,             // 渲染器据此重建瓦片批次
    pub fn init(allocator, w: u32, h: u32) !TileMap;
    pub fn deinit(self) void;
    pub fn resize(self, w, h) !void;          // 清空为 kind 0
    pub fn defineTile(self, def: TileDef) !u16;
    pub fn getDef(self, kind: u16) ?TileDef;
    pub fn inBounds(self, x: i32, y: i32) bool;
    pub fn get(self, x, y) ?Tile;
    pub fn set(self, x, y, kind: u16, height: u8) void; // 越界忽略；置 dirty
    pub fn fill(self, kind, height) void;
    pub fn topY(self, x, y) f32;              // 越界或空 → 0
    pub fn isWalkable(self, x, y) bool;       // 非空 && !solid && !liquid
    pub fn canStep(self, fx, fy, tx, ty) bool;// 两格都可走且 |Δheight| <= max_step
    pub fn worldToTile(self, p: Vec3) ?GridPos;
    pub fn tileCenter(self, x, y) Vec3;       // y 分量 = topY
    pub fn raycastPick(self, ray: Ray, max_dist: f32) ?TileHit; // 步长 0.02 行进，首个 point.y <= topY 的非空格
    /// 4 邻接 A*，曼哈顿启发；out 被清空后写入从起点(不含)到终点(含)的格子序列
    pub fn findPath(self, allocator, from: GridPos, to: GridPos, out: *std.ArrayList(GridPos)) !bool;
};
```
A* 必须有节点上限（`width*height`）保证终止；起点=终点返回 true 且 out 为空。

### world.zig
```zig
pub const Entity = struct {
    id: u32 = 0, alive: bool = false,
    pos: Vec3 = Vec3.zero,            // 脚底
    size: Vec2 = Vec2.new(1, 1.5),    // 世界单位宽高（billboard 尺寸）
    sheet: u32 = 0,                   // 精灵表句柄（render 层解释；0 = 无）
    frame: u16 = 0, flip_x: bool = false,
    tint: Color = colors.white,
    anim_start: u16 = 0, anim_len: u16 = 0, anim_fps: f32 = 0, anim_time: f32 = 0, anim_loop: bool = true,
    speed: f32 = 3.0,
    path: [64]GridPos = undefined, path_len: u8 = 0, path_idx: u8 = 0,
    move_goal: ?Vec3 = null,
    facing: Dir = .down,              // 由最后一次移动方向 + 相机 yaw 计算
    last_move: Vec2 = Vec2.zero,      // 世界 (dx,dz)，供 Lua 读
};
pub const World = struct {
    allocator, entities: std.ArrayList(Entity), free: std.ArrayList(u32),
    pub fn init(allocator) World; pub fn deinit(self) void;
    pub fn spawn(self, e: Entity) !u32;   // 复用空槽；id = 槽位下标+1；返回 id
    pub fn despawn(self, id: u32) void;
    pub fn get(self, id: u32) ?*Entity;
    pub fn setPath(self, id, path: []const GridPos) void; // 超过 64 截断
    pub fn moveTo(self, id, goal: Vec3) void;             // 直线，清空路径
    pub fn isMoving(self, id) bool;
    /// 推进动画、沿路径/直线移动；移动时 pos.y 平滑贴合 map.topY；更新 facing
    pub fn tick(self, dt: f32, map: *const TileMap, cam_yaw: f32) void;
    pub fn iterator(self) ...;             // 遍历存活实体（渲染器用）
};
```

### render.zig（图形层）
```zig
pub const TileAtlas = struct { texture_handle: u32, cols: u32, rows: u32, tex_w: u32, tex_h: u32,
    pub fn region(self, index: u16) TextureRegion; }   // 半像素内缩防渗色
pub const SpriteSheet = struct { texture_handle: u32, frame_w: u32, frame_h: u32, cols: u32, rows: u32, tex_w: u32, tex_h: u32,
    pub fn region(self, frame: u16, flip_x: bool) TextureRegion; }
pub const WorldRenderer = struct {
    pub fn init(allocator) !WorldRenderer; pub fn deinit(self) void;
    pub fn setTileAtlas(self, atlas: TileAtlas) !void;
    pub fn addSheet(self, sheet: SpriteSheet) !u32;          // 返回 sheet id（从 1 起）
    pub fn setHighlight(self, tile: ?GridPos, color: Color) void;
    pub fn draw(self, map: *TileMap, world: *World, cam: *IsoCamera) void;
};
```
- 瓦片批次（静态）：`map.dirty` 时重建并清 dirty。顶面：`translate(gx, top, gy+1) * rotateX(-90)` 下的 `Rect(0,0,1,1)`；四个方向侧面：邻格（越界视为 `-base_depth` 高度、空格视为 0）低于本格时画，按 `height_unit` 分段（每段一个 side 纹理，纹理重复清晰）。顶点色做假光照：顶面 1.0、±X 侧 0.78、±Z 侧 0.62。
- 精灵批次（每帧重建）：按决策 4 生成 billboard。
- 高亮：在目标格顶面上方 +0.01 画一个半透明（单独 BLEND 材质，`depth_write = false`）白色四边形。
- 绘制矩阵：`.{ .view = cam.view, .proj = remapDepthToBackHalf(cam.proj) }`。

### engine.zig
```zig
pub const Config = struct { main_script: [:0]const u8 = "assets/main.lua", map_w: u32 = 32, map_h: u32 = 32, clear_color: Color = ... };
pub var map: TileMap; pub var world: World; pub var camera: IsoCamera; pub var renderer: WorldRenderer;
pub var follow_entity: u32 = 0;
pub fn register(cfg: Config) !void; // 注册 iso_world(-70) 与 iso_script_host(-60) 两个模块
```
`iso_world`：init 建全局状态；tick → `world.tick`、若 follow_entity 存活则 `camera.follow_goal = 实体 pos`、`camera.tick`；draw → `camera.update(papp.getWidth(), papp.getHeight())`、`renderer.draw`；cleanup 全部释放（DebugAllocator 不得报泄漏）。

### script_host.zig
- init：`delve.scripting.manager.init()`（绑定 Delve 自带库），然后 `lua_api.bind(lua)`；设置 `package.path = "assets/?.lua;assets/scripts/?.lua;" .. package.path`；注册控制台命令 `lua`。
- start：`runFile(main_script)` → 调 `_init()`。
- tick(dt)：F5 刚按下 → 热重载（调 `_shutdown`（若存在）→ `map.fill(0,0)`、清空 world、重置 renderer 高亮 → 重新 runFile → `_init`）；然后调 `_update(dt)`（带 dt 参数）。
- draw：调 `_draw()`。
- 任何 Lua 全局函数不存在 → 静默跳过；Lua 运行时错误 → `debug.err` 打印错误字符串，置 `script_failed = true` 停止调用 Lua 直到 F5 重载成功，**进程不得崩溃、不得调用 showErrorScreen**。

### lua_api.zig —— Lua 模块 `iso`（`local iso = require("iso")`）
参数只用 f32/i32/u32/bool/字符串（`[*:0]const u8`）；多值返回用元组（Lua 侧为数组表），“可能无结果”用可选（Lua 侧为 nil）。
| 函数 | 说明 |
|---|---|
| `map_create(w,h)` | 重建地图（清空） |
| `map_size()` → `{w,h}` | |
| `tileset_load(path, cols, rows)` → bool | 设置瓦片图集 |
| `tile_define(top, side, solid, liquid)` → kind | |
| `map_set(x,y,kind,height)` / `map_get(x,y)` → `{kind,height}` 或 nil / `map_fill(kind,height)` | |
| `map_top_y(x,y)` / `map_walkable(x,y)` / `map_can_step(fx,fy,tx,ty)` | |
| `path_find(x0,y0,x1,y1)` → `{{x,y},...}` 或 nil | 结果用 api 内静态缓冲 |
| `camera_set_target(x,y,z)` / `camera_get_target()` → `{x,y,z}` | |
| `camera_follow(id)`（0 取消）/ `camera_rotate(steps)` / `camera_set_angles(yaw,pitch)` / `camera_get_yaw()` | |
| `camera_set_zoom(z)` / `camera_get_zoom()` / `camera_set_view_height(h)` | |
| `screen_to_tile(sx,sy)` → `{x,y}` 或 nil / `mouse_tile()` → `{x,y}` 或 nil / `world_to_screen(x,y,z)` → `{sx,sy}` | 用 raycastPick |
| `sheet_load(path, frame_w, frame_h)` → sheet id（0 失败） | |
| `entity_spawn(sheet, x, z, w, h)` → id | 脚底 y 贴合地图 |
| `entity_despawn(id)` / `entity_exists(id)` | |
| `entity_set_pos(id,x,y,z)` / `entity_get_pos(id)` → `{x,y,z}` / `entity_get_tile(id)` → `{x,y}` 或 nil | |
| `entity_move_to(id,x,z)` / `entity_path_to(id,tx,ty)` → bool / `entity_is_moving(id)` / `entity_stop(id)` / `entity_set_speed(id,s)` | |
| `entity_play(id,start,count,fps,loop)` / `entity_set_frame(id,f)` / `entity_set_flip(id,b)` / `entity_set_tint(id,r,g,b,a)` | |
| `entity_facing(id)` → 0..3 (down,left,right,up) / `entity_last_move(id)` → `{dx,dz}` | |
| `highlight_tile(x,y,r,g,b,a)` / `highlight_clear()` | |
| `key_down(code)` / `key_pressed(code)` / `mouse_pressed(btn)` / `mouse_down(btn)` / `mouse_pos()` → `{x,y}` | |
| `set_clear_color(r,g,b)` | |
`bind()` 额外创建全局表 `keys`：用 `@typeInfo(input.KeyCodes)` 遍历所有字段，`keys.W`、`keys.ESCAPE`、`keys.F5` …（名称与 Delve 枚举一致）。

## 3. 子任务与负责代理

| # | 任务 | 代理 | 依赖 |
|---|---|---|---|
| T1 | 工程脚手架（mise/zon/build.zig/.gitignore/最小 main.zig 开窗）+ `tools/gen_assets.py` 生成三张 PNG | coder-haiku | — |
| T2 | 纯逻辑层 coords/camera/tilemap/world + tests.zig + 单元测试 | coder-sonnet | T1 |
| T3 | render/engine/script_host/lua_api/main.zig + 演示游戏 Lua | coder-sonnet | T2 |
| T4 | README.md（中文，含 Lua API 参考） | coder-haiku | T3 |

## 4. 验收标准（总）

1. `mise exec -- zig build` 无错误无警告；`mise exec -- zig build test` 全部通过。
2. `timeout 8 ./zig-out/bin/iso-game`（cwd=项目根）运行 8 秒：无 panic、无 Lua 错误、退出时无泄漏报告（被 timeout 杀掉不算失败）。
3. 截图可见：带高低起伏的等距方块地形、水面、主角精灵站在地面上、HUD 文字在世界之上。
4. 演示玩法：WASD 相对屏幕方向移动主角（不可走/高差>1 时被挡）、左键点击格子寻路走过去、Q/E 旋转相机 90° 平滑过渡、Z/X 缩放、悬停格高亮、2~3 个史莱姆随机游走、F5 热重载、ESC 退出。
5. 纯逻辑文件不 import graphics/app/input。

## 5. 已知风险

- 网络到 lua.org 被阻断：Lua 5.4.8 tarball 已经 `zig fetch` 进全局缓存（hash `N-V-__8AAKEzFAAA695b9LXBhUSVK5MAV_VKSm1mEj3Acbze`）。若新工程构建又报 TlsInitializationFailed，执行：`mise exec -- zig fetch /tmp/claude-1000/-home-smile-user-dev/b6560f2b-0476-46d4-85a2-3141427eefee/scratchpad/lua/lua-5.4.8.tar.gz`（或从 `https://sources.buildroot.net/lua/lua-5.4.8.tar.gz` 重新下载）。
- Zig 0.16：`std.heap.GeneralPurposeAllocator` 已更名 `DebugAllocator`；`std.ArrayList` 为 unmanaged（方法需传 allocator）。以 Delve 源码中的用法为准。
- `Mat4.mul` 的乘法顺序、`Mat4.rotate` 的旋转方向必须通过单元测试确认，不要凭记忆。
- Delve 鼠标坐标与 `papp.getWidth()` 在高 DPI 下可能不一致；本机非高 DPI，暂不处理，代码里留 TODO。
- 无鼠标滚轮 API，缩放用 Z/X 键。
