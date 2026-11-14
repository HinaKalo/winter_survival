# winter_survival —《零下三十 / Thirty Below / 영하 삼십》（暂名）

俯视等距 2.5D 的寒冬末日生存游戏。一场史无前例的寒潮在半年内摧毁了现代文明，玩家带领 4 名各有特长与缺点的幸存者，在明尼苏达州虚构小镇哈洛瀑布的一栋半毁的房子里熬过 30 天：白天整理据点、修设备、交易，夜晚派 1–2 人潜入别处偷窃或掠夺。游戏的核心是稀缺逼出来的道德抉择，以及世界对这些抉择的记忆。支持中文、English、한국어；键鼠、纯鼠标、纯手柄均可完整游玩。

基于 [Delve Framework](https://github.com/Interrupt/delve-framework)（Zig 0.16 + Sokol + Lua 5.4），由 `~/dev/delve-starter` 脚手架生成。

## 当前状态

| 项 | 状态 |
|---|---|
| 阶段 | M1 完成（2026-11-14）：自建 Lua VM、三语字体与 UI、键鼠/手柄输入与改键、存档、`core/` 基础设施、标题与设置界面。地图仍是脚手架示例 |
| 下一步 | M2：引擎扩展 B + 地图表现 + 美术试点，见 `docs/M2-PLAN.md` |
| CI | Jenkins 任务 `winter_survival`（每 2 分钟轮询本机 git daemon），见 `docs/CI-PLAN.md`。构建全部通过后，Windows 运行器桌面的 `ThirtyBelow\` 目录会被删掉重放为最新版本（含 `BUILD.txt`） |

## 设计文档

| 文档 | 内容 |
|---|---|
| [`docs/PLAN.md`](docs/PLAN.md) | 总计划：核心决策、技术架构、里程碑 M0–M12、验证、风险。**从这里开始读** |
| [`docs/GDD.md`](docs/GDD.md) | 游戏设计与输入系统 |
| [`docs/NARRATIVE.md`](docs/NARRATIVE.md) | 叙事与道德系统：设计原理与 Lua 架构 |
| [`docs/CONTENT.md`](docs/CONTENT.md) | 物品、配方、科技、设施、模拟常数、战利品预算 |
| [`docs/WORLD.md`](docs/WORLD.md) | 人物、NPC、势力、地点、哨站主线、反应规则与首批故事片段 |
| [`docs/UI-UX.md`](docs/UI-UX.md) | 界面与交互规格 |
| [`docs/ART-AUDIO.md`](docs/ART-AUDIO.md) | 美术与音频规格 |
| [`docs/ENGINE-PLAN.md`](docs/ENGINE-PLAN.md) | 引擎扩展设计（Zig 侧） |
| [`docs/ENGINE-BASE.md`](docs/ENGINE-BASE.md) | 脚手架继承的 iso-base 引擎原始计划 |
| [`docs/CI-PLAN.md`](docs/CI-PLAN.md) | Jenkins 流水线 |

以下各节是脚手架引擎（继承自 iso-base 与 delve-starter）的使用说明。随着 ENGINE-PLAN 的扩展落地，相应章节会更新。

## 特性

- **等距 2.5D 引擎**：真 3D 地面方块 + 竖直 billboard 精灵 + 正交等距相机，遮挡交给深度缓冲；高低起伏地形、4 邻接 A* 寻路、鼠标拾取、精灵动画。
- **音频**：`kit_audio` 模块与 `audio` Lua 封装；BGM 流式播放（整首循环）、SFX 语音环与节流、总线音量；`--no-audio` 无声模式。
- **无头探针**：`zig build probe` 由 Lua 脚本驱动游戏并断言结果，输出 `PROBE` 行与 JUnit XML，是 CI 的门禁。
- **资产流水线**：`tools/assets.py` 负责占位美术、音频导入与目录同步、美术导入，以及 `check` 一致性检查。
- **CI**：Jenkins 流水线，Linux 控制器做检出与轻量检查，Windows GPU 代理做构建、单测、探针与真窗口冒烟截图。
- **热重载**：Lua 脚本按 F5 热重载，脚本出错不崩溃，修复后按 F5 恢复。
- **纯逻辑可测试**：坐标、相机、地图、实体与音频目录解析不依赖图形模块，`zig build test` 直接运行单元测试。

## 快速开始

### 环境

- Zig **0.16.0**，由 [mise](https://mise.jdx.dev/) 管理（见 `mise.toml`）。系统 PATH 中的 `zig` 可能是其他版本，因此所有构建命令都通过 `mise exec --` 运行。
- Delve Framework 必须放在与本工程同级的 `../delve-framework`（`build.zig.zon` 中为 `.path = "../delve-framework"`）。
- Python 3.10+。`tools/assets.py check` 与 Python 单元测试只用标准库；占位美术生成与美术导入检查需要 Pillow。

### 构建、运行与测试

在项目根目录执行：

```bash
mise exec -- zig build run                            # 构建并运行，工作目录自动设为项目根
mise exec -- zig build run -- --no-audio              # 无声模式运行（参数传给可执行文件）
mise exec -- zig build test                           # Zig 纯逻辑单元测试（src/iso 与 src/kit）
mise exec -- zig build probe -Dbackend=headless       # 无头探针，默认 tests/probe/smoke.lua
mise exec -- zig build -Doptimize=ReleaseFast         # 发布构建，产物在 zig-out/bin/winter_survival
python3 -m unittest discover -s tests/tools -t .      # Python 单元测试（资产工具与 CI 脚本）
```

`-Dbackend=sokol`（默认，开窗口、需要 GPU）、`-Dbackend=headless`（无窗口，CI 探针使用）与 `-Dbackend=null` 三种后端可选。

直接运行可执行文件时，必须在项目根目录下执行（脚本与资源路径是相对路径）：

```bash
./zig-out/bin/winter_survival
```

CI 的 Linux Source 阶段由 `ci/setup_delve.sh` 应用 Delve 的兼容性补丁，补丁随源码 stash 传给 Windows 阶段，Windows 阶段不再单独修补。本地若使用上游原版 Delve，需要手动修补。

### 网络问题：lua.org 无法访问

Delve 依赖的 zlua 默认从 `https://www.lua.org` 下载 Lua 5.4.8。若该地址被阻断，构建时会报 TLS 或下载失败。此时可先从镜像下载 tarball，校验后用 `zig fetch` 预填全局缓存：

```bash
curl -LO https://sources.buildroot.net/lua/lua-5.4.8.tar.gz
echo "4f18ddae154e793e46eeab727c59ef1c0c0c2b744e7b94219710d76f530629ae  lua-5.4.8.tar.gz" | sha256sum -c -
mise exec -- zig fetch ./lua-5.4.8.tar.gz
```

`zig fetch` 成功时输出 `N-V-__8AAKEzFAAA695b9LXBhUSVK5MAV_VKSm1mEj3Acbze`，与 zlua 依赖的 hash 一致，之后重新构建即可。CI 的 `ci/setup_zig.py --lua-mirror` 会自动完成同样的操作。

### Delve 兼容性修补

CI 中 `ci/setup_delve.sh` 会按 `ci/delve.rev` 检出 Delve，并幂等地重新应用这一补丁。下文说明本地手动修补的方法。

Delve 上游在 Zig 0.16 下有一处需要修补：`../delve-framework/src/framework/utils/quakemap.zig` 中的 `std.heap.GeneralPurposeAllocator` 已更名为 `std.heap.DebugAllocator`。若你使用的 Delve 是上游原版，请把这一行改为：

```zig
var gpa = std.heap.DebugAllocator(.{}){};
```

## 命令行参数

`winter_survival` 接受以下参数（`zig build run -- <参数>` 会原样传给它）：

| 参数 | 说明 |
|---|---|
| `--probe <file.lua>` | 探针模式：加载 Lua 探针脚本驱动游戏；退出前打印 `PROBE SUMMARY`，有失败或没有任何检查时以非零退出 |
| `--no-audio` | 无声模式：音频的校验、统计与 BGM 记账照常进行，但不真正播放 |
| 环境变量 `STARTER_NO_AUDIO=1` | 等同于 `--no-audio`；取值 `1`、`true`、`yes`（不区分大小写）时生效 |

未知参数会打印用法并退出。窗口标题为 `Thirty Below`，尺寸 1280×720。

## 操作说明

| 按键 / 操作 | 功能 |
|---|---|
| `W` `A` `S` `D` | 按**屏幕**方向移动主角（W 远离镜头，S 朝向镜头，A 左，D 右） |
| 鼠标左键 | 点击可走格子，主角寻路前往 |
| 鼠标悬停 | 高亮所在格：白色为可走，红色为不可走 |
| `Q` / `E` | 相机旋转（每次 90°，平滑过渡） |
| `Z` / `X` | 放大 / 缩小（按住持续生效） |
| `F5` | 热重载 Lua 脚本 |
| `ESC` | 退出 |
| `~` | 打开 / 关闭控制台 |

左上角 HUD 显示 FPS、主角所在格坐标与高度、悬停格信息、当前 BGM 与已播放音效计数。场景中有 3 只史莱姆会在附近随机游走。

## 架构

### 目录结构

```
winter_survival/
├── mise.toml              Zig 版本（0.16.0）
├── build.zig              可执行文件 winter_survival；步骤 run、probe、test
├── build.zig.zon          包信息，依赖 ../delve-framework
├── src/
│   ├── main.zig           入口：解析 --probe / --no-audio，注册 iso 与 kit，开窗
│   ├── iso/               等距引擎（`iso` 模块）
│   │   ├── root.zig       模块根，重导出以下文件
│   │   ├── coords.zig     纯逻辑：方向 Dir、格子 GridPos、屏幕方向换算
│   │   ├── camera.zig     纯逻辑：正交等距相机 IsoCamera、射线、深度重映射
│   │   ├── tilemap.zig    纯逻辑：瓦片定义、地图 TileMap、A*、射线拾取
│   │   ├── world.zig      纯逻辑：实体 Entity、实体管理 World（动画、移动、路径）
│   │   ├── tests.zig      单元测试根
│   │   ├── render.zig     图形：瓦片图集、精灵表、世界渲染器 WorldRenderer
│   │   ├── engine.zig     全局状态、注册 iso_world 模块、Config
│   │   ├── script_host.zig Lua 宿主：生命周期、F5 热重载、错误恢复
│   │   └── lua_api.zig    Lua 库 `iso` 的绑定（所有 pub fn 即 Lua API）
│   └── kit/               音频与探针（`kit` 模块）
│       ├── root.zig       模块根
│       ├── audio_catalog.zig  纯逻辑：解析 assets/audio/catalog.json，校验合约
│       ├── audio.zig      模块 kit_audio：总线、BGM 状态、SFX 语音环、统计
│       ├── lua_audio.zig  Lua 原始库 kit_audio（固定参数个数）
│       ├── probe.zig      模块 kit_probe 与 Lua 原始库 kit_probe
│       └── tests.zig      kit 纯逻辑测试根
├── assets/                演示游戏资源（Lua 脚本、音频、美术）
│   ├── main.lua           游戏入口（_init / _update / _draw）
│   ├── scripts/           子模块：world_gen、hero、slimes、cursor、hud，以及音频封装 audio
│   ├── audio/             catalog.json（工具生成）、sfx/*.wav、bgm/*.ogg
│   ├── textures/tiles.png 瓦片图集（8×4 格，每格 32×32）
│   └── sprites/           hero.png（4×4 帧，每帧 32×48）、slime.png（4×1 帧，每帧 32×32）
├── assets_src/            资产清单：audio.json（pixel-hero-demo 格式）、art.json
├── tests/
│   ├── probe/smoke.lua    默认探针场景
│   └── tools/             Python 单元测试（assets.py 与 ci/ 脚本）
├── tools/
│   ├── assets.py          资产流水线 CLI（placeholder / audio / art / check）
│   ├── i18n_check.py      三语文本静态检查（由 assets.py check 调用）
│   ├── gen_assets.py      Pillow 占位美术生成器（由 assets.py placeholder 调用）
│   └── new_game.py        生成新游戏项目
├── ci/                    Jenkins 流水线与脚本（见 CI 一节）
└── docs/                  设计文档（见上文"设计文档"表）；ENGINE-BASE.md 为引擎原始设计
```

### 渲染思路

- **真 3D 世界**：地面瓦片是 3D 方块的顶面与侧面；角色是竖直四边形（billboard），始终朝向相机的水平方向。
- **正交等距相机**：`yaw = 45°`、`pitch = 30°` 得到 2:1 像素等距观感，可用 `camera_set_angles` 调整（如 35.264° 为真等距）。
- **精灵透明**：精灵使用 `alpha_cutoff = 0.5` 镂空，不做混合，因此可以直接写入深度缓冲，正确遮挡。
- **深度缓冲**：遮挡关系完全由深度缓冲解决，不需要按距离排序。
- **深度重映射（HUD 置顶）**：世界投影矩阵左乘一个重映射矩阵 `z' = 0.25·z + 0.75·w`，把世界深度压到 NDC `[0.5, 1]`。Delve 的 2D 绘制（`draw` / `text`）深度约为 0.4999，因此 HUD 永远画在世界之上。
- **高亮**：悬停格顶面画一个半透明白色（或红色）四边形，单独使用混合材质且不写深度。
- **材质**：每个纹理一个材质，最近邻采样，不剔除，`alpha_cutoff = 0.5`。

### 坐标约定

- 右手坐标系，Y 轴向上。
- 格子 `(gx, gy)` 占据世界 `X ∈ [gx, gx+1]`、`Z ∈ [gy, gy+1]`。格子中心为 `(gx + 0.5, topY, gy + 0.5)`。
- 格顶高度 `topY = height × height_unit`，`height_unit` 默认 **0.5**（`tilemap.zig` 中 `TileMap.height_unit`，当前未暴露给 Lua）。
- Lua 中所有实体位置用世界坐标。生成实体时传入格子中心即可，例如 `iso.entity_spawn(sheet, tx + 0.5, ty + 0.5, w, h)`。
- 实体的 `pos` 是**脚底**位置（精灵底边中点），`y` 会自动贴合地面。
- `entity_get_tile` 等函数由世界坐标向下取整得到格子坐标。

### 模块优先级与每帧调用顺序

Delve 模块按 `priority` 从小到大执行，数值越小越先：

| 模块 | priority | 职责 |
|---|---|---|
| `kit_probe` | -80 | 探针：注入输入、调用 `_probe(t, dt)`、记录检查（仅 `--probe`） |
| `iso_world` | -70 | 实体 tick、相机跟随与平滑、世界渲染 |
| `kit_audio` | -65 | 音频总线、BGM、SFX 语音环、统计 |
| `iso_script_host` | -60 | F5 热重载、Lua `_update(dt)` / `_draw()` |
| Delve 自带库（scriptapi） | -50 | 在 `pre_draw` 中重置、在 `draw` 中提交 `draw` / `text` 等 2D 指令 |

每帧：

1. **tick**：`world.tick`（推进动画与移动）→ 相机跟随 `camera.tick` → `camera.update` → F5 检查 → Lua `_update(dt)`。
2. **draw**：`camera.update` → 世界渲染（瓦片、精灵、高亮）→ Lua `_draw()`（排入 HUD 指令）→ Delve 提交 2D 指令。

### 纯逻辑与图形层分离

- `coords.zig`、`camera.zig`、`tilemap.zig`、`world.zig` 只依赖 `delve.math` 与标准库，**不调用**任何 graphics / app / input，因此可直接用 `zig build test` 单测。
- 图形只出现在 `render.zig`；引擎胶水（全局状态、模块注册）在 `engine.zig`；Lua 相关在 `script_host.zig` 与 `lua_api.zig`。

## Lua 脚本开发

### 生命周期

引擎会调用入口脚本（`assets/main.lua`）中的以下全局函数，都可以省略：

| 函数 | 调用时机 |
|---|---|
| `_init()` | 入口脚本执行完成后调用一次（启动时，以及每次热重载后） |
| `_update(dt)` | 每帧，在实体 tick 之后；`dt` 为秒 |
| `_draw()` | 每帧，在世界渲染之后；HUD 指令在这里排入 |
| `_shutdown()` | 退出时，或热重载之前 |

若某个函数不存在，则静默跳过。

### F5 热重载

按 `F5` 时依次执行：

1. 调用 `_shutdown()`（脚本处于出错状态时跳过）。
2. 引擎状态重置：
   - 地图重建为默认尺寸（`map_w × map_h`，默认 32×32），所有格子清空；
   - 所有实体清空，相机跟随取消，相机恢复默认值；
   - 图集、精灵表、高亮清空。
3. 清除 `_init`、`_update`、`_draw`、`_shutdown` 四个全局函数，并清除通过 `require` 加载的用户模块缓存（`iso` 与 Delve 内置模块保留）。
4. 重新执行入口脚本，并调用 `_init()`。

注意：

- 其他普通全局变量**不会**被清除。模块级 `local` 变量会随模块重新加载而重置。
- 纹理与材质缓存保留，重新加载图片不会有额外开销。
- 热重载后，旧实体 id 失效，脚本需要重新生成实体。

### 出错后的行为与恢复

Lua 运行时错误（包括入口脚本执行失败、`_init` / `_update` / `_draw` / `_shutdown` 报错）的处理：

- 错误信息会打印到控制台 / 日志，格式为 `Lua error while ...: <消息>`。
- 脚本进入**暂停**状态：不再调用任何 Lua 回调，进程不会崩溃。
- 引擎仍然运行：实体继续按已有路径移动，世界继续渲染，但 HUD 与游戏逻辑停止更新，键盘交互失效。
- **恢复方法**：修改脚本文件，然后按 `F5` 重载。重载成功即恢复正常。

### require 搜索路径

脚本启动时设置：

```lua
package.path = "assets/?.lua;assets/scripts/?.lua;" .. package.path
```

因此：

- `require("hero")` 加载 `assets/scripts/hero.lua`；
- `require("iso")` 加载引擎内置的 `iso` 库；
- 路径相对于**当前工作目录**，所以必须在项目根目录运行。`zig build run` 已自动设置。

### 整数参数注意事项

- Lua API 的绑定会严格检查参数个数。调用参数个数与函数定义不一致时会报错 `Invalid number of arguments to function`，且**不会**补齐或忽略多余参数。
- 整数参数（`i32` / `u32`，如格子坐标、种类、帧号、精灵表 id、实体 id）应使用整数。Lua 5.4 中 `/` 会得到浮点数，需要取整时请用 `math.floor`，例如：

```lua
local cx = math.floor(w / 2)
iso.map_set(cx, cy, kind, height)
```

### `keys` 全局表

引擎创建了全局表 `keys`，包含 Delve 的所有按键码，名称与 Delve 的 `KeyCodes` 枚举一致，例如：

```lua
if iso.key_pressed(keys.F5) then ... end
if iso.key_down(keys.W) then ... end
if iso.key_pressed(keys.ESCAPE) then iso.quit() end
```

鼠标按键使用数字：`0` 左键、`1` 右键、`2` 中键。

### 同时使用 Delve 自带库

除 `iso` 库外，脚本中可以直接 `require` 使用 Delve 的库，典型用法见 `assets/scripts/hud.lua`：

```lua
local draw = require("draw")   -- 矩形、线等 2D 图形
local text = require("text")   -- 文字
```

可用的库包括：`assets`、`display`、`draw`、`text`、`graphics`、`input.mouse`、`input.keyboard`。HUD 使用调色板索引绘制（如 `0` 黑、`7` 白、`10` 黄）。

注意：不要调用 `display.set_resolution`，它会改变 HUD 坐标。

## Lua API 参考

`iso` 库通过 `local iso = require("iso")` 获取。以下共 52 个函数，与 `src/iso/lua_api.zig` 中的 `pub fn` 一一对应。

约定：

- 坐标与尺寸为 `f32`，格子坐标、种类、帧号、id 等为整数（见上文"整数参数注意事项"）。
- 多值返回为 Lua 数组表，例如 `{x, y}`；"可能无结果"的函数返回 `nil`。
- 颜色分量范围为 `0..1`。

### 地图

| 函数 | 返回 | 说明 |
|---|---|---|
| `map_create(w, h)` | — | 重建地图为 w×h（最小 1×1），所有格子清空为种类 0 |
| `map_size()` | `{w, h}` | 当前地图尺寸 |
| `map_set(x, y, kind, height)` | — | 设置格子种类与高度（高度钳制到 0..255）；越界忽略 |
| `map_get(x, y)` | `{kind, height}` 或 `nil` | 读取格子；越界返回 `nil`。种类 0 为空格 |
| `map_fill(kind, height)` | — | 整张地图填充为同一种类与高度 |

### 瓦片

| 函数 | 返回 | 说明 |
|---|---|---|
| `tileset_load(path, cols, rows)` | `bool` | 加载瓦片图集，按 cols×rows 等分；成功返回 `true` |
| `tile_define(top, side, solid, liquid)` | `kind` | 定义瓦片种类。`top`、`side` 为图集格子索引（`row × cols + col`）；`solid` 实心，`liquid` 液体，二者都不可走。失败返回 0 |
| `map_top_y(x, y)` | `f32` | 格顶世界高度（`height × height_unit`）；越界或空格返回 0 |
| `map_walkable(x, y)` | `bool` | 格子非空、非实心、非液体 |
| `map_can_step(fx, fy, tx, ty)` | `bool` | 两格都可走且高差不超过 `max_step`（默认 1） |

### 寻路

| 函数 | 返回 | 说明 |
|---|---|---|
| `path_find(x0, y0, x1, y1)` | `{{x, y}, ...}` 或 `nil` | 4 邻接 A* 寻路，不含起点、含终点；起点等于终点返回空表；无路返回 `nil`。结果存放在 API 内部的静态缓冲（最多 1024 格），下次调用会覆盖 |

### 相机

| 函数 | 返回 | 说明 |
|---|---|---|
| `camera_set_target(x, y, z)` | — | 设置相机注视点。若已跟随实体，会被跟随逻辑逐帧覆盖 |
| `camera_get_target()` | `{x, y, z}` | 当前注视点 |
| `camera_follow(id)` | — | 相机平滑跟随实体；`id` 为 0 时取消跟随 |
| `camera_rotate(steps)` | — | 每步旋转 90°，平滑过渡；负数为反向 |
| `camera_set_angles(yaw, pitch)` | — | 立即设置偏航角与俯仰角（度）；`pitch` 钳制到 `[5, 85]` |
| `camera_get_yaw()` | `f32` | 当前平滑后的偏航角（度） |
| `camera_set_zoom(z)` | — | 设置缩放，钳制到 `[0.25, 4]` |
| `camera_get_zoom()` | `f32` | 当前缩放 |
| `camera_set_view_height(h)` | — | 设置视野高度（世界单位）；仅 `h > 0.1` 时生效 |

### 拾取与投影

| 函数 | 返回 | 说明 |
|---|---|---|
| `screen_to_tile(sx, sy)` | `{x, y}` 或 `nil` | 以屏幕像素（左上为原点）发出射线，返回首个命中的非空格子；未命中返回 `nil` |
| `mouse_tile()` | `{x, y}` 或 `nil` | 鼠标当前所指格子，等价于对 `mouse_pos()` 调用 `screen_to_tile` |
| `world_to_screen(x, y, z)` | `{sx, sy}` | 世界坐标转屏幕像素坐标 |

### 实体

| 函数 | 返回 | 说明 |
|---|---|---|
| `entity_spawn(sheet, x, z, w, h)` | `id` | 在世界 `(x, z)` 生成实体，脚底 `y` 自动贴合地面；`w`、`h` 为世界尺寸。失败返回 0 |
| `entity_despawn(id)` | — | 销毁实体；若为跟随目标，则取消跟随 |
| `entity_exists(id)` | `bool` | 实体是否存在 |
| `entity_set_pos(id, x, y, z)` | — | 瞬移到指定位置，并清除路径与移动目标 |
| `entity_get_pos(id)` | `{x, y, z}` 或 `nil` | 脚底世界坐标 |
| `entity_get_tile(id)` | `{x, y}` 或 `nil` | 实体所在格子（由位置向下取整） |
| `entity_move_to(id, x, z)` | — | 直线移动到 `(x, z)`，`y` 自动贴合地面 |
| `entity_path_to(id, tx, ty)` | `bool` | 寻路到目标格并开始移动；无路返回 `false`。路径最多 64 格，超出部分截断，到达后可再次调用 |
| `entity_is_moving(id)` | `bool` | 实体是否正在移动（直线或路径） |
| `entity_stop(id)` | — | 停止移动并清除路径 |
| `entity_set_speed(id, s)` | — | 设置移动速度（世界单位 / 秒） |
| `entity_facing(id)` | `i32` | 朝向：`0` 下、`1` 左、`2` 右、`3` 上（对应精灵表行号）；实体不存在返回 0 |
| `entity_last_move(id)` | `{dx, dz}` | 最近一次移动的世界水平位移；实体不存在返回 `{0, 0}` |

### 动画

| 函数 | 返回 | 说明 |
|---|---|---|
| `sheet_load(path, frame_w, frame_h)` | `sheet id` | 加载精灵表，按 `frame_w × frame_h` 切分帧，帧号 = `row × cols + col`；失败返回 0 |
| `entity_play(id, start, count, fps, loop)` | — | 播放帧区间 `[start, start + count)`，`fps` 帧每秒，`loop` 是否循环。参数未变时重复调用不会重置动画 |
| `entity_set_frame(id, f)` | — | 固定显示第 `f` 帧并停止动画 |
| `entity_set_flip(id, b)` | — | 水平翻转精灵 |
| `entity_set_tint(id, r, g, b, a)` | — | 设置顶点色着色（分量 0..1） |

### 高亮

| 函数 | 返回 | 说明 |
|---|---|---|
| `highlight_tile(x, y, r, g, b, a)` | — | 高亮指定格子的顶面（半透明）；仅对非空格子绘制 |
| `highlight_clear()` | — | 清除高亮 |

### 输入

| 函数 | 返回 | 说明 |
|---|---|---|
| `key_down(code)` | `bool` | 按键是否处于按住状态。`code` 通常使用 `keys.*` |
| `key_pressed(code)` | `bool` | 按键是否在本帧刚被按下 |
| `mouse_pressed(btn)` | `bool` | 鼠标按键是否在本帧刚被按下（`0` 左、`1` 右、`2` 中） |
| `mouse_down(btn)` | `bool` | 鼠标按键是否处于按住状态 |
| `mouse_pos()` | `{x, y}` | 鼠标像素坐标（左上为原点） |

### 其他

| 函数 | 返回 | 说明 |
|---|---|---|
| `set_clear_color(r, g, b)` | — | 设置背景清屏色 |
| `quit()` | — | 退出游戏 |
| `fps()` | `i32` | 当前帧率 |
| `window_size()` | `{w, h}` | 窗口尺寸（像素） |

## 音频

音频由两部分组成：Zig 模块 `kit_audio`（优先级 -65，`main.zig` 中注册）与 Lua 封装 `assets/scripts/audio.lua`。游戏代码只使用封装：

```lua
local audio = require("audio")

audio.bgm("bgm/street_chip")        -- 切换 BGM，淡入淡出各 1.0 秒；播放同一首时是空操作
audio.sfx("sfx/ui")                 -- 音效，vol 与 pitch 默认为 1
audio.sfx("sfx/swing1", 0.5, 1.2)   -- 音量 0.5，音高 1.2
audio.sfx_var("sfx/blip", 1, 0.1)   -- 随机音高 1±0.1（默认 0.05）
audio.set_bus("bgm", 0.4)           -- 总线音量 0..1
local s = audio.stats()             -- {sfx_played=, sfx_rejected=, bgm_started=}
```

### 封装函数（带默认值）

| 函数 | 返回 | 说明 |
|---|---|---|
| `audio.sfx(id, vol, pitch)` | `bool` | 播放音效；`vol` 默认 1，`pitch` 默认 1 |
| `audio.sfx_var(id, vol, spread)` | `bool` | 随机音高 `1±spread`，`spread` 默认 0.05 |
| `audio.bgm(id, fade)` | `bool` | 切换 BGM，`fade` 默认 1.0 秒；正在播放同一首时返回 `true` 且不做任何事 |
| `audio.stop_bgm(fade)` | — | 淡出并停止 BGM，`fade` 默认 1.0 秒 |
| `audio.set_bus(name, v)` | `bool` | `name` 为 `"master"`、`"sfx"` 或 `"bgm"`，`v` 为 0..1；未知名字返回 `false` |
| `audio.has(id)` | `bool` | 目录中是否有该 id |
| `audio.current_bgm()` | `string` 或 `nil` | 当前 BGM 的 id |
| `audio.stats()` | 表 | `{sfx_played=, sfx_rejected=, bgm_started=}` |
| `audio.enabled()` | `bool` | 是否真正在出声（`--no-audio` 时为 `false`） |

底层原始库 `kit_audio` 参数个数固定（`sfx(id, vol, pitch)`、`bgm(id, fade)`、`stop_bgm(fade)`、`set_bus(name, v)`、`has(id)`、`current_bgm()`、`stats()`、`enabled()`）。它是内部接口：参数个数或类型错误会直接抛出 binder 错误，游戏代码请使用封装，不要直接 `require("kit_audio")`。

封装 `audio.*` 的类型守卫行为如下：

- `id` 与总线名必须是字符串。类型错误（如 `audio.sfx(nil)`）时返回 `false`（`audio.current_bgm()` 返回 `nil`），不抛错。
- 数值参数（`vol`、`pitch`、`fade`）经 `tonumber` 转换，无法转换（如 `nil`、表）时使用默认值，不打印日志。`audio.set_bus` 的 `v` 无法转换时返回 `false` 并打印一次日志。
- 未知 id、未知总线名、NaN 与 inf 由 Zig 侧拒绝，返回 `false`。
- 日志：类型错误时打印一行 `[audio] <函数>: <参数> ...`，例如 `[audio] sfx: id must be a string, got table`。日志按**函数 + 参数**各只打印一次，之后静默；**不是**按 id 限流。

### id 与目录

- id 形如 `sfx/<名字>` 或 `bgm/<名字>`，只含小写字母、数字与下划线，可多级；`kind` 必须与前缀一致。
- `assets/audio/catalog.json` 由 `tools/assets.py audio sync` 生成，不要手改。每个条目包含 `path`、`kind`、`loop`、`loop_start`、`loop_length`、`frames`、`sample_rate`、`channels` 与 `volume`（0..4）；`volume` 在同步时会被保留。
- 目录缺失或整体无效时，音频退化为空目录并打印警告，游戏不会崩溃；单个坏条目会被跳过并警告。
- 重复的 id 保留第一个并警告。

### 总线与音量

- 三个总线 `master`、`sfx`、`bgm`，默认 1，范围 0..1。
- 最终音量 = 条目 `volume` × 对应总线 × `master` × 调用时的音量，结果钳制到 0..4。BGM 的调用音量固定为 1。
- 修改总线会立即作用于正在播放的 BGM。

### 节流与语音数

- 同一 id 的音效在 0.03 秒内再次播放会被跳过：返回 `false` 并计入 `sfx_rejected`。
- 同时最多 24 个音效语音（语音环）。槽位被复用时，旧语音会被销毁。
- 音高钳制到 0.25..4，音量钳制到 0..4。

### BGM 行为

- `audio.bgm(id, fade)`：旧曲淡出 `fade` 秒后销毁（`fade <= 0` 时立即停止），新曲淡入 `fade` 秒。`fade` 最大为 60 秒。
- BGM 以流式方式播放。F5 热重载不会触碰音频；热重载后 `_init` 再次调用同一首 BGM 不会重播。

### 循环策略：整首循环

Delve 没有循环点 API，因此音频只支持整首循环：

| 条目 | 播放行为 |
|---|---|
| `loop = false` | 播放一次 |
| `loop = true`，`loop_start = 0`，`loop_length` 为 0 或等于 `frames` | 整首循环 |
| `loop = true`，含 intro 或循环点 | 同样整首循环，并在首次播放时警告一次：`intro+loop points not supported by Delve audio; looping whole file` |

### 无声模式

`--no-audio`（或 `zig build probe -Dprobe-audio=false`）时，校验、统计与 BGM 记账与有声模式完全相同，只是不真正播放。因此探针中对 `sfx_played`、`current_bgm()` 等的断言在两种模式下结果一致；只有"加载失败"只会在有声模式下出现。此时 `audio.enabled()` 返回 `false`。

## 无头探针

探针是由 Lua 脚本驱动的自动化检查：每个 tick 注入按键与鼠标，并断言游戏状态。Windows CI 阶段用它做门禁，并转换为 JUnit 报告。

### 运行

```bash
mise exec -- zig build probe -Dbackend=headless                                     # 默认 tests/probe/smoke.lua，有声
mise exec -- zig build probe -Dbackend=headless -Dprobe=tests/probe/door.lua -Dprobe-audio=false
mise exec -- zig build && ./zig-out/bin/winter_survival --probe tests/probe/smoke.lua --no-audio
```

`-Dprobe=<文件>` 选择场景，`-Dprobe-audio=true|false` 控制是否播放音频（默认 `true`）。

`tests/probe/audio_fuzz.lua` 是音频封装的 fuzz 场景：用 nil、表、字符串、NaN、inf、负数等参数调用 `audio.*` 的每个函数，断言非法 id 与非法数值返回 `false` / `nil`，且脚本不报错。运行：

```bash
mise exec -- zig build probe -Dbackend=headless -Dprobe=tests/probe/audio_fuzz.lua
```

输出以 `PROBE` 开头的行（由 `zig build` 转发到标准错误）：

```
PROBE PASS lua script running (no Lua error)
PROBE FAIL click that starts pathing plays sfx (sfx_played +1)
PROBE info hero moved 2.10 units
PROBE done: 2/3 checks passed after 4.20s
PROBE SUMMARY 2/3 passed
```

`PROBE PASS|FAIL <name>` 是每个检查的结果，`PROBE info` 只是信息，`PROBE SUMMARY <通过>/<总数> passed` 是最终结论。

### 无声设备与看门狗

Delve 在无法打开任何音频设备时会卡死：子系统启动失败后主循环空转，输出 `Fatal error starting subsystems!`，不会退出。因此在没有音频设备的机器上运行探针时，必须关闭音频，三种方式任选其一：

- 游戏参数 `--no-audio`，例如 `./zig-out/bin/winter_survival --probe tests/probe/smoke.lua --no-audio`；
- `zig build probe -Dbackend=headless -Dprobe-audio=false`；
- 环境变量 `STARTER_NO_AUDIO=1`（`1`、`true`、`yes`）。

探针自带看门狗：`--probe` 启动时开一个后台线程。若探针超过 **20 秒**墙钟时间没有任何 tick（子系统初始化失败、死锁），或总墙钟时间超过 **max(timeout × 3, 120 秒)**，看门狗打印

```
PROBE FAIL probe watchdog: <原因> (device-less machine? use --no-audio)
```

随后打印一行 `PROBE SUMMARY`，并以退出码 **3** 结束进程。`probe.finish()` 与正常退出路径会解除看门狗。

### 退出码

- 至少有一个检查、且全部通过：进程以 **0** 退出。
- 看门狗触发（见「无声设备与看门狗」）：进程以 **3** 退出。
- 以下任一情况：有检查失败；检查数为 0；探针没有调用 `finish()`（记为失败 `probe ended before finish()`）；探针文件无法加载或定义 `_probe`；`_probe` 中出现 Lua 错误：进程以**非零**退出，`zig build` 报告失败。

### 运行规则

- 探针文件在第一个 tick 载入（此时主脚本已加载），与主脚本共享同一个 Lua 状态。它必须定义全局函数 `_probe(t, dt)`，之后每个 tick 调用一次；`t` 为自启动起的游戏时间（秒），`dt` 为帧间隔。
- 调用 `_probe` 之前，由 `tap` 按下的键会被自动抬起。
- `probe.timeout(秒)` 设置超时，默认 60 游戏秒；超时记为失败 `probe timed out` 并结束。
- Lua 错误（载入探针文件或 `_probe` 中）记为一个失败检查 `probe script error: <消息>` 并结束。
- 游戏脚本自身出错（`script_failed`）时探针继续运行，由场景用 `probe.script_ok()` 断言。
- headless 下游戏时间约等于墙钟时间：只用带容差的等待（如 `wait(0.6)`），不要做逐帧断言。
- 不要调用 `imgui.*`，headless 没有 ImGui。
- Delve 的日志含 NUL 字节。解析日志时请先去掉 NUL（`ci/probe_junit.py` 已处理），手动查看可用 `grep -a`。

### kit_probe API

在场景中用 `local probe = require("kit_probe")` 获取。

| 函数 | 说明 |
|---|---|
| `probe.key(code, down)` | 按下或抬起按键（`code` 使用 `keys.*`） |
| `probe.tap(code)` | 本帧按下，下一帧自动抬起 |
| `probe.mouse_move(x, y)` | 移动鼠标（屏幕像素，左上为原点） |
| `probe.click(button)` | 本帧按下并抬起；`just_pressed` 在本帧可见（`0` 左、`1` 右、`2` 中） |
| `probe.check(name, ok)` | 记录一个检查，输出 `PROBE PASS name` 或 `PROBE FAIL name` |
| `probe.info(msg)` | 输出 `PROBE info msg`，不计入检查 |
| `probe.script_ok()` | 游戏脚本是否健康（`script_failed == false`） |
| `probe.finish()` | 输出 `PROBE done` 并退出游戏 |
| `probe.timeout(seconds)` | 设置超时（游戏秒，默认 60） |

### 编写新场景

场景写成协程，用 `wait(秒)` 等待游戏时间，最后调用 `probe.finish()`。新建 `tests/probe/door.lua`：

```lua
local iso = require("iso")
local probe = require("kit_probe")
local audio = require("audio")

probe.timeout(20)

local now = 0
local function wait(sec)                 -- 让出，直到游戏时间走过 sec 秒
	local untl = now + sec
	while now < untl do
		coroutine.yield()
	end
end

local co = coroutine.create(function()
	wait(1.0)
	probe.check("script running", probe.script_ok())
	probe.check("bgm is playing", audio.current_bgm() == "bgm/street_chip")

	local before = iso.entity_get_pos(1)
	probe.key(keys.D, true)
	wait(0.6)
	probe.key(keys.D, false)
	wait(0.4)
	local after = iso.entity_get_pos(1)
	local moved = math.abs(after[1] - before[1]) + math.abs(after[3] - before[3])
	probe.check("hero moves with D", moved > 0.2)

	probe.finish()
end)

function _probe(t, dt)
	now = t
	if coroutine.status(co) == "dead" then
		return
	end
	local ok, err = coroutine.resume(co)
	if not ok then
		error(err, 0)
	end
end
```

要点：

- 每个场景都要以 `probe.finish()` 结束，否则会记为失败。
- 断言只针对状态（实体位置、音频统计、脚本健康），并使用容差。
- F5 热重载会重新执行主脚本，依赖实体 id 的断言应在重载后重新获取 id。
- CI 运行的是 `zig build probe` 的默认场景 `tests/probe/smoke.lua`。要让 CI 运行其他场景，需修改 `ci/zig_steps.py` 中的 `PROBE_ARGS`，并确认该场景的 JUnit 结果。

## 资产流水线

`tools/assets.py` 是资产 CLI（Python 3.10+，标准库；占位美术与美术导入检查需要 Pillow）。路径均相对项目根目录，即 `tools/` 的父目录。

```bash
python3 tools/assets.py placeholder                                 # 生成占位美术（tools/gen_assets.py）
python3 tools/assets.py audio build [--pixel-hero DIR] [--only ID...] [--out DIR]
python3 tools/assets.py audio sync --from DIR
python3 tools/assets.py art import --from DIR [--only NAME...]
python3 tools/assets.py check [--junit FILE]
```

| 子命令 | 作用 |
|---|---|
| `placeholder` | 运行 `tools/gen_assets.py`，生成占位美术 |
| `audio build` | 在 pixel-hero-demo 中运行 `audio.build`（`--check --skip-missing`，只构建 `assets_src/audio.json` 中的音频），输出默认到 `out/audio`，完成后自动执行 `audio sync`。pixel-hero-demo 目录取 `--pixel-hero`，否则取环境变量 `PIXEL_HERO_DEMO`，否则 `../pixel-hero-demo` |
| `audio sync --from DIR` | `DIR` 为 `audio.build` 的输出（含 `report.json` 与 `final/`）。把清单中每个音频复制到 `assets/audio/<id><扩展名>`，重写 `catalog.json`，并删除不再属于任何 id 的音频文件。任何缺失或失败的 id 都会列出全部问题，且不写入任何文件 |
| `art import --from DIR` | 对 `source` 为 `genai` 或 `pixelflow` 的美术条目，把 `DIR/<name>.png` 复制到其 `dest`；并检查尺寸、模式与调色板 |
| `check [--junit FILE]` | 只检查，不修改任何文件。失败时退出码为 1；`--junit` 为每组检查写一个用例 |

`check` 检查的内容：

- 目录合约（版本、字段、排序、id 与路径规则）；
- 目录中每个文件存在，且文件头的格式符合规格（见下文）；
- `assets_src/audio.json` 中的 id 与目录一一对应；
- `assets_src/art.json` 中的美术存在且尺寸一致；
- Lua 中以字符串字面量调用的 `audio.sfx("…")`、`audio.sfx_var("…")`、`audio.bgm("…")` 的 id 存在于目录，且 kind 匹配（分组名 `lua audio ids`）；
- 三语文本表 `assets/i18n/{zh,en,ko}.lua` 的键完全一致、占位符一致，且没有未被 Lua 引用的键（行尾加 `-- i18n:keep` 注释的键豁免“未引用”检查，用于预留给后续控件的通用键；分组名 `i18n`；也可单独运行 `python3 tools/i18n_check.py`）。

### 清单

- `assets_src/audio.json`：pixel-hero-demo 的 `audio/assets.json` 格式，包含 `defaults` 与 `assets`。每个条目定义 id、类别、增益，以及生成来源（`webaudio`、`jsfxr` 或 `compose`）。
- `assets_src/art.json`：美术清单，结构为 `{"version": 1, "palette": null 或调色板路径, "art": [{name, dest, size, frame, source}]}`。`source` 为 `placeholder`、`genai`、`pixelflow` 或 `manual`。当前三项为：`hero`（128×192，帧 32×48）、`slime`（128×32，帧 32×32）、`tiles`（256×128，帧 32×32）。

### 音频规格

- **音效（SFX）**：单声道（mono），48 kHz，真峰值 −1 dBTP；格式 `.wav` 或 `.ogg`。
- **背景音乐（BGM）**：立体声（stereo），48 kHz，综合响度 −20 LUFS；格式必须是 `.ogg`。
- 文件路径为 `assets/audio/<id><扩展名>`，例如 `bgm/street_chip` 对应 `assets/audio/bgm/street_chip.ogg`。
- `check` 解析文件头：WAV 读取 RIFF 的 fmt 与 data 块；OGG 读取 Vorbis 识别头（采样率与声道），末页 granule position 给出帧数。

### 美术导入检查

- 图片尺寸等于清单中的 `size`，并能被 `frame` 整除；
- 模式必须是 RGBA；
- 出现介于 0 与 255 之间的半透明像素时给出警告（Delve 的 alpha cutoff 为 0.5）；
- 若 `palette` 指向一个十六进制颜色列表（或按类别分组的列表）的 JSON 文件，所有不透明像素的颜色都必须在调色板内。

### 生成器在 pixel-hero-demo

音频生成器（`audio.build`，含 jsfxr、webaudio 与 compose 来源，并做母带处理）与美术生成器（genai 输出 `out/genai/assets/<name>.png`）都位于 pixel-hero-demo 工程中。本工程只负责导入、校验与同步：

```bash
python3 tools/assets.py audio build --pixel-hero ../pixel-hero-demo
python3 tools/assets.py art import --from ../pixel-hero-demo/out/genai/assets --only hero
python3 tools/assets.py check --junit reports/linux/assets.xml
```

## CI（Jenkins）

Jenkins 任务名为 `winter_survival`，流水线定义在 `ci/Jenkinsfile`。触发方式为 `pollSCM('H/2 * * * *')`，`disableConcurrentBuilds`，超时 60 分钟，保留最近 20 次构建。

| 阶段 | 节点 | 步骤 |
|---|---|---|
| Source | 控制器内置节点（`built-in`） | 检出 `winter_survival/`；`ci/setup_delve.sh` 按 `ci/delve.rev` 检出 delve-framework 并重新应用 quakemap 补丁；`tools/assets.py check`（JUnit：`reports/linux/assets.xml`）；`ci/run_pytests.py`（Python 单测，JUnit：`reports/linux/unit_py.xml`）；stash 源码 |
| Windows GPU | `windows && opengl` | unstash；`ci/setup_zig.py` 安装 Zig 0.16.0；`ci/zig_steps.py --probe`：`zig build`、`zig build test --summary all`、`zig build probe -Dbackend=headless`（有声），探针日志经 `ci/probe_junit.py` 转为 `reports/windows/probe.xml`；`zig build` 恢复默认的 sokol 可执行文件；`ci/smoke.py --title "Thirty Below"` 真窗口冒烟并截图 |

Post 步骤：`reports/linux/*.xml` 与 `reports/windows/*.xml` 发布为 JUnit；`reports/windows/**` 作为构建产物归档（包括 `shot.png`、`game.log`、`build.log`、`unit.log`、`probe.log` 与 `probe.xml`）。

### 顺序：先探针，再冒烟

探针使用 `-Dbackend=headless` 构建，会覆盖 `zig-out/bin/winter_survival.exe`。因此选择"先探针，再重建 sokol，最后冒烟"：冒烟测试的是默认的 GPU 版本。重建命中 Zig 缓存，不会重新编译。

### 工作区布局

```
$WORKSPACE/
  winter_survival/     （Linux：checkout；Windows：unstash）
  delve-framework/   （Linux：setup_delve.sh；Windows：unstash；build.zig.zon 的 ../delve-framework）
```

stash 排除 `**/.git/**`、`**/.zig-cache/**`、`**/zig-out/**`、`**/zig-pkg/**`。Linux 控制器只做轻量工作；编译、探针与冒烟在 Windows GPU 代理上运行。

Windows 的持久缓存位于 `%USERPROFILE%\.ci\`（工具链 `tools\zig-0.16.0`，Zig 全局缓存 `zig-cache`），不随 `deleteDir` 删除。

### 在本地复现

```bash
python3 tools/assets.py check --junit reports/linux/assets.xml
python3 ci/run_pytests.py --junit reports/linux/unit_py.xml
python3 ci/zig_steps.py --zig "$(mise which zig)" --log-dir reports/local --probe   # 在项目根目录执行
```

`ci/probe_junit.py --log <日志> --junit <文件>` 可把任意探针日志转换为 JUnit XML；日志不完整（没有 `PROBE SUMMARY`、检查数为 0 或计数不一致）时退出码为 1。

## 开一个新游戏

推荐用生成器：它复制本工程（排除 `.git`、构建缓存、`out/`、`reports/` 与 `docs/STARTER-PLAN.md`），并改写包名、可执行文件名、窗口标题与 README 标题。

```bash
python3 tools/new_game.py my_game --git
```

用法：

```text
python3 tools/new_game.py NAME [--dest DIR] [--title T] [--delve DIR] [--git]
```

- `NAME`：包名与可执行文件名，匹配 `[a-z][a-z0-9_]{0,31}`（Zig 包名规则，最长 32 字符）。`build.zig.zon` 的 `.name` 与 `.fingerprint` 会随之更新。
- `--dest DIR`：目标目录，默认 `../NAME-with-dashes`（下划线换成连字符，例如 `my_game` 为 `../my-game`）。目标目录必须不存在或为空。
- `--title T`：窗口标题与 README 标题，默认由 `NAME` 生成。
- `--delve DIR`：delve-framework 所在目录，默认取本工程 `build.zig.zon` 中 `.delve` 的路径。新项目的 `.path` 会改写为相对于新目录的路径。
- `--git`：在新目录执行 `git init` 并做一次初始提交。

生成的项目与本工程结构相同，包括 `ci/Jenkinsfile`（其中的 `winter_survival` 替换为新目录名）。

### 只替换 `assets/`

引擎的 Zig 代码不需要修改，替换 `assets/` 即可，入口仍是 `assets/main.lua`。音频同理：替换 `assets/audio/` 时，`catalog.json` 必须与 `assets_src/audio.json` 一致（用 `audio sync` 生成）。

### 修改入口脚本

`assets/main.lua` 的结构可以作为模板：

- `_init()`：生成地形（`world_gen.generate`）、生成角色、设置相机；
- `_update(dt)`：处理输入、更新游戏逻辑；
- `_draw()`：绘制 HUD。

把 `world_gen`、`hero`、`slimes`、`hud` 替换为你自己的模块即可。

### 替换美术

所有美术都是固定格子布局，尺寸由 `tileset_load` 与 `sheet_load` 的参数决定。

**瓦片图集**（`tileset_load(path, cols, rows)`）

- 图集按 `cols × rows` 等分，每格尺寸 = 图宽 / cols、图高 / rows。演示为 8×4 格、每格 32×32，图尺寸 256×128。
- 格子索引 = `row × cols + col`，从左上开始按行计数。
- 每个瓦片种类有两个索引：`top`（顶面）和 `side`（侧面）。
- 顶面是 1×1 世界单位的正方形，应绘制为正方形。
- 侧面每段是 1 × `height_unit`（默认 0.5）世界单位的矩形，整格贴图会拉伸到该段，建议按 2:1（宽:高）绘制，以避免变形。

**精灵表**（`sheet_load(path, frame_w, frame_h)`）

- 每帧尺寸为 `frame_w × frame_h` 像素，列数 = 图宽 / frame_w，行数 = 图高 / frame_h。
- 帧号 = `row × cols + col`。
- **脚底锚点**：精灵的底边中点对应实体的脚底位置（`entity_spawn` 的 `x, z`），因此每帧的脚应位于图像底部中央，底部留出尽量少的透明边距。
- 精灵的世界尺寸由 `entity_spawn(..., w, h)` 决定，与像素大小无关。建议 `w : h` 与帧的宽高比保持一致（演示中 hero 为 1 : 1.5，slime 为 1 : 1）。
- 角色朝向约定：演示中 hero 的行号 0 下、1 左、2 右、3 上，与 `entity_facing` 返回值一致。
- 精灵使用 alpha 镂空（`alpha_cutoff = 0.5`），透明度低于 50% 的像素会被丢弃，不支持半透明。

美术占位图由 `tools/gen_assets.py` 生成，可以作为参考：

```bash
python3 tools/assets.py placeholder
```

依赖 Pillow。该脚本使用固定随机种子，重复运行结果一致。

### 修改窗口标题与尺寸

编辑 `src/main.zig`：

```zig
try delve.app.start(.{ .title = "Thirty Below", .width = 1280, .height = 720 });
```

### 修改地图尺寸与背景色

同样在 `src/main.zig` 中，`iso.engine.register` 接受以下配置（均可省略）：

```zig
try iso.engine.register(.{
    .main_script = "assets/main.lua",
    .map_w = 32,
    .map_h = 32,
    .clear_color = delve.colors.Color.newBytes(40, 48, 72, 255),
});
```

也可以在 Lua 中用 `iso.set_clear_color(r, g, b)` 修改背景色（分量 0..1）。

## 调试

- **控制台**：运行时按 `~` 打开 / 关闭。
- **`lua` 命令**：在控制台输入 `lua <语句>` 可执行一行 Lua 代码。由于 `iso` 是 `main.lua` 中的局部变量，需要通过 `require` 获取，例如：

  ```
  lua print(require("iso").fps())
  lua print(require("iso").map_size()[1])
  ```

  `print` 输出到标准输出（终端），不会显示在游戏窗口中。
- **环境变量 `ISO_AUTOQUIT`**：设置为秒数，运行到该时间后自动退出，便于自动化测试或冒烟运行：

  ```bash
  ISO_AUTOQUIT=8 ./zig-out/bin/winter_survival
  ```

  未设置时不自动退出。
- **单元测试**：

  ```bash
  mise exec -- zig build test
  ```

  测试覆盖坐标换算、相机矩阵与拾取、地图与寻路、实体与动画；`src/kit` 测试覆盖音频目录解析。

## 已知限制与路线图

### 已知限制

- **单批次 quad 上限约 10666**：瓦片批次与精灵批次各自独立。大地图需要分块渲染。
- **未处理高 DPI**：鼠标坐标与 `window_size` 在高 DPI 屏幕上可能不一致。
- **没有鼠标滚轮**：缩放使用 `Z` / `X` 键。
- **实体 id 会被复用（ABA 问题）**：实体销毁后 id 可能分配给新实体。持有旧 id 的脚本需要检查 `entity_exists`，避免长期持有 id。
- **单条路径最多 64 个点**：`entity_path_to` 截断超出部分。演示中 `hero.lua` 通过在到达后再次调用来分段处理长路径。
- **音频只支持整首循环**：Delve 没有循环点 API，带 intro 的 BGM 会整首循环（见"音频"一节）。
- **音频没有空间化、混响或优先级系统**：只有按 id 的节流与 24 个语音的上限。
- **演示未使用的音效**：`sfx/hit_light`、`sfx/jump`、`sfx/coin` 已入库，但演示游戏尚未播放它们。
- **探针没有像素断言**：冒烟截图只归档，供人工查看，不做自动判定。

### 路线图

- 分块渲染（突破单批次 quad 上限）
- 存档
- Tiled 地图导入
- 光照
- 探针截图对比
