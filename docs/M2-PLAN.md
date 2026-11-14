# M2 实施计划：引擎 B + 地图表现

上位文档：`PLAN.md §6`（里程碑）、`ENGINE-PLAN.md`（X2–X9、X13、X18 的接口与单测清单，**本文不重复，子代理必须直接读原文**）、`ART-AUDIO.md §3–§5`（光照表、图集格位、精灵表与朝向）。§0 决策与 ENGINE-PLAN §A1 决策子代理不得更改。

## 0. 目标与验收

把一份字符网格模板变成带光照、视野和战争迷雾的等距场景，像素尺寸达到最终基准。

| # | 验收项 | 怎么验 |
|---|---|---|
| G1 | 顶面菱形 128×64 px，人物 64×96 px，1:1 显示，静止时不闪烁 | Xvfb 截图量像素（§3） |
| G2 | 64×64 地图、外墙 6 级，无 quad 超限警告；改 1 格只重建 ≤ 4 块 | 探针 `m2_map.lua` 断言调试计数器 + 日志 `grep -a` |
| G3 | 夜间光照（环境光 + 炉火/手电）、NPC 视锥覆盖层、战争迷雾三态都可见 | Xvfb 截图 |
| G4 | 同一模板 `exterior` / `cutaway` 两种模式都能生成；门开关改变通行和视线 | luatest + 探针 |
| G5 | 人物 4 朝向正确（含西侧镜像），行走/待机动画帧号符合 ART-AUDIO §5.4 | luatest（`facing`）+ 截图 |
| G6 | `zig build test`、`luatest`、全部探针、`assets.py check`、`timeout 8` 运行全过；`-Dtarget=x86_64-windows` 交叉编译通过 | PLAN §7 |

## 1. M1 遗留（M2 开工前关闭）

- **UI 贴图上下颠倒**：已修（`src/kit/ui.zig`，UI 批次开 `flip_tex_y`）。
- **面板九宫格采到字形、焦点按钮字底白块、副标题重影**：coder-sonnet 排查中。
- 教训：headless 探针只能数四边形，测不出采样方向。**从 M2 起，凡是“看画面”的子任务，编码代理必须自己用 Xvfb 截图确认后才能交审**（§3 的脚本），审查代理也要看截图。

## 2. 子任务

### 2.1 新增约定（本计划裁定，子代理照做）

**地点模板格式**（`assets/scripts/data/locations/<原型>.lua`，M2 只做两份测试模板，正式模板在 M5）：

```lua
return {
  id = "suburb_house",
  variants = {
    A = {
      grid = {            -- 行 = y（网格 z），列 = x；所有行等长；空格 = 地图外（void）
        "##########+###",
        "#K.K..#B..B..#",
        ...
      },
      legend = { K = { prop = "counter", slot = "food" }, B = { prop = "bed" } },  -- 覆盖/补充通用图例
      floor = "wood",       -- 室内默认地面材质
      wall = "siding",      -- 外墙材质；内墙固定 plaster
    },
  },
}
```

- 通用图例放 `data/legend.lua`：`#` 外墙、`=` 内墙、`.` 室内地面、`,` 室外地面、`+` 内门、`D` 外门、`w` 窗、空格 void。字母留给道具，由模板的 `legend` 定义。WORLD 网格里内外墙都写成 `#`；`mapbuild` 判定“与 void 或室外相邻的墙 = 外墙，其余为内墙”，所以模板作者不需要区分。
- 道具格 M2 只占格（`blocked`，按 prop 表决定是否 `opaque`），并放一个最终尺寸的占位 billboard。
- 材质名 → 图集格号的映射放 `data/tiles.lua`，格号以 ART-AUDIO §4.2 为准。

**两种生成模式**（PLAN §4.2 墙体约定）：

| | exterior | cutaway |
|---|---|---|
| 外墙 | 6 级，最上一段 `side_cap = 60` | 2 级 |
| 内墙 | 不可见（屋顶盖住） | 2 级 |
| 屋顶 | 墙内所有格加屋顶（顶面 56/57） | 无 |
| 门 | 0 高度格 + 门实体，关 = `blocked + opaque` | 同 |
| 窗 | 2 级窗格夹在实墙之间（6 级时为 实墙 2 + 窗 2 + 墙檐 2） | 2 级窗格，`opaque = false` |

**`mapbuild` 分两层**：`mapbuild.plan(template, variant, mode, opts) -> plan`（纯 Lua，只依赖 `data/`，输出每格的 `{kind, height, flags, tag}` 和道具/门/光源列表，可在 luatest 里单测）；`mapbuild.apply(plan)` 调 `iso` API。`plan` 不得 require 引擎库。

**光照模块命名**：ART-AUDIO §3.1 里的 `view/lighting.lua` 统一叫 `view/lightfov.lua`，光照、FOV、迷雾都在这一个模块里。

### 2.2 任务表

| # | 任务 | 代理 | 依赖 | 文件 | 验收 |
|---|---|---|---|---|---|
| S1 | 测试隔离存档目录：`luatest`、`probe`、`balance` 步骤在 `build.zig` 里固定传 `--save-dir .zig-cache/test-saves/<步骤名>`，启动前清空该目录（M1 发现跑测试会改写真实的 `saves/settings.sav`） | haiku | — | `build.zig` | 跑完全部测试后 `saves/` 下文件的 sha256 不变 |
| S0 | 本地截图脚本 `tools/shot.sh <out.png> [--lang zh\|en\|ko] [--script x.lua] [--at 3]`：先 `zig build`（窗口版），xvfb-run 1280×720 调 `ci/smoke.py`，改语言前备份 `saves/settings.sav`、退出时 trap 恢复 | haiku | — | `tools/shot.sh` | 连跑三语不改动 `settings.sav`；中途 Ctrl-C 也能恢复 |
| X2 | 相机像素模式 + 吸附 | sonnet | — | `camera.zig` | ENGINE-PLAN A5 camera |
| X3 | tilemap flags/tag/块脏 + `pathfind.zig` | sonnet | — | `tilemap.zig`、`pathfind.zig` | A5 tilemap、pathfind |
| X13 | 音频环境层 | haiku | — | `audio.zig`、`lua_audio.zig`、`assets.py` | ENGINE-PLAN X13 |
| P1 | 最终尺寸占位美术（见 §2.3） | haiku | — | `tools/gen_assets.py`、`assets_src/art.json` | `assets.py check` 过；尺寸、格位、透明规则符合 ART-AUDIO §4.1/§5.4 |
| L1 | `data/tiles.lua`（材质名 → 图集格号，ART-AUDIO §4.2）、两份测试模板（WORLD 的 suburb_house A 原样照抄；64×64 室外街区，含 6 级外墙房屋 4 栋）。**图例用 M3 的 `data/legend.lua`**（`#` 墙、`=` 内墙、`.` 室内地面、`,` 室外地面、`+` 内门、`D` 外门、`w` 窗、空格 void，字母留给道具）；材质由模板的 `floor`/`wall` 字段和 `data/tiles.lua` 决定，不编进图例符号 | haiku | M3 的 layout 提交 | `data/` | 模板行等长、字母都有定义；两份模板都能被 `core/layout.lua` 解析出预期的房间数（luatest） |
| X4 | `vision.zig` | sonnet | X3 | | A5 vision |
| X7 | `world.zig` 代数 id、字段、pick、path 256 | sonnet | X3 | | A5 world |
| L2 | `view/facing.lua` + 单测（ART-AUDIO §5.6；轴向→斜向映射对照 `world.zig` 的 `last_move` 与 `camera.zig` 的 yaw 推导，写进测试注释，PLAN §10 A2） | sonnet | X2 | `view/facing.lua`、`tests/lua/test_facing.lua` | 8 个移动方向 + 滞回 + 帧号公式全覆盖 |
| L3 | `view/mapbuild.lua` 的 `plan()`（纯）：在 `core/layout.lua` 的输出上加高度、屋顶、两种模式的规则、材质→图集格号。**`core/layout.lua` 和 `data/legend.lua` 由 M3 分支实现**（见 `M3-PLAN.md §1、§3`，输出结构以那里为准），M2 先合入 M3 单独提交的这两个文件再开工，不得另写一份解析 | sonnet | L1、M3 的 layout 提交 | | luatest：两种模式的墙高、门窗 flags、屋顶范围、void；同输入输出逐字节相同；不 require 引擎库 |
| X5 | `lightmap.zig` | sonnet | X4 | | A5 lightmap |
| X6 | `tilemesh.zig` + `overlay.zig` | sonnet | X5 | | A5 两组 |
| X8 | `render.zig` 分块/覆盖层/精灵 + `engine.zig` 胶水 | sonnet | X2, X6, X7 | | ENGINE-PLAN X8；A7.1 第 1–3 条的自检与计数器 |
| X9 | `lua_api.zig` 全部 `iso` 新绑定 + README API 表 | haiku | X8 | | ENGINE-PLAN X9 |
| L4 | `mapbuild.apply()`、`view/actors.lua`（生成/动作/朝向/受光，动作帧表来自 ART-AUDIO §5.4）、`view/lightfov.lua`（§3.1 环境光插值、§3.3 光源表、10 Hz FOV 与迷雾、组 3 视锥覆盖层） | sonnet | X9, L2, L3, P1 | `view/*.lua` | §0 的 G3–G5 |
| D1 | 开发演示 `scenes/m2_demo.lua`（`--script` 或开发菜单进入）：街区图 / 剖面房屋切换、昼夜时间滑块、一个带视锥的巡逻 NPC、可控角色点击寻路 | sonnet | L4 | | 三种输入可操作；截图 |
| X18 | 探针 `engine_ext.lua`（ENGINE-PLAN X18：每个新 `iso` 函数的 NaN/Inf/越界模糊测试）+ `m2_map.lua`（G2、G4 的断言） | haiku | X9, L4 | `tests/probe/` | 两个探针全过 |

并行波次：①S0、S1、X2、X3、X13、P1 → ②X4、X7、L2；合入 M3 的 layout 提交后做 L1、L3 → ③X5 → ④X6 → ⑤X8 → ⑥X9 → ⑦L4 → ⑧D1、X18 → 主代理验收。

冲突控制：`src/iso/tests.zig`、`src/kit/tests.zig`、`build.zig`、`README.md` 是共享文件，同一波次的子代理只允许在这些文件里**追加自己那一行**，不得改动其它行。

### 2.3 占位美术（P1）

占位图是**最终尺寸、最终格位**，只把画质换成程序绘制，M11 换正式图时不改代码：

- `assets/textures/tiles.png` 512×512，8×8 格，64×64；每格按 ART-AUDIO §4.2 的材质画纯色 + 简单纹样（砖缝、板缝沿格的 X/Z 轴），左上角用 3×5 像素数字标格号；62、63 带透明。
- `assets/sprites/char_placeholder.png` 512×768，64×96 帧，脚底锚点 (32, 95)。按 §5.4 的行列画剪影，SE/NE 用不同颜色，用一个“鼻子”像素块标出朝向，每个动作的帧有可见差异（腿位、高度），这样截图能核对帧号和镜像。
- `assets/sprites/door_leaf.png` 32×64；道具占位 billboard 若干（床、台面、炉）按 ART-AUDIO §6 的尺寸。
- 旧的 `hero`、`slime`、32 px `tiles` 在 L4 完成后删除（脚手架示例脚本一并删除）。

### 2.4 正式美术试点（用户 2026-11-14 选定：M2 试点，定风格后一次批量）

目的：在铺量之前先定风格。试点通过后，按 ART-AUDIO 资产清单一次写齐全部规格，用 genai 的 Jenkins 任务一次批量生成；从 M3 起和后续里程碑并行，M11 只做收尾和替换。PLAN §9 第 3、6 条涉及的 pixel-hero-demo 改动都只做新增，试点需要的部分提前到 M2，开工前逐条列给用户。

| # | 任务 | 代理 | 依赖 | 产出 | 验收 |
|---|---|---|---|---|---|
| A1 | 色卡 `assets_src/palette/wasteland.json` + `materials.json`（ART-AUDIO §2）；`genai.pixelize --palette` 能读入 | haiku | — | 色卡文件 | 色数 ≤ 64；`Palette.load` 读入通过 |
| A2 | 人物生成器骨架 `tools/art/chargen/`（ART-AUDIO §5.1–§5.4）：成人体型，出 1 名角色的全套 512×768 精灵表 | sonnet | A1, P1 | `assets/sprites/char_<id>.png` | 尺寸/锚点/空帧透明；D1 场景里替换占位人物截图 |
| A3 | 地块图集试制：雪、沥青、木地板、石膏墙、红砖、墙檐、门、窗共约 12 格（pixelflow 程序纹理 + 色卡量化），其余格保持 P1 占位 | sonnet | A1, P1 | `tiles.png` 部分格 | 侧面上下、左右无缝（ART-AUDIO §4.3）；6 级墙叠 3 段无横线 |
| A4 | genai 规格约 6 个：头像 2、图标 2、关键帧 1、家具 1（ART-AUDIO §9 模板），跑一次 `genai-assets` | haiku 写规格，主代理触发 | A1 | `genai/specs/ws_*.json` + 产物 | 产物过 genai QA |
| A5 | 风格评审：主代理把试点截图和产物整理成一页，给用户过目（PLAN §8“先出一名角色的全套动作让用户过目”） | 主代理 | A2–A4、D1 | 评审页 | 用户确认或给出修改意见 |

A1–A4 不阻塞引擎链，排在波次 ①–⑥ 里并行；A5 在 M2 验收时一起做。

## 3. 截图验收方法

```bash
tools/shot.sh /path/out.png --script assets/scripts/scenes/m2_demo.lua --lang zh
```

Xvfb + Mesa 软件渲染，在本机就能截图，不碰用户桌面。像素量测用 PIL 读 PNG 数顶点。Windows GPU 运行器上的 `ci/smoke.py` 仍然是最终依据。

## 4. 风险

| 风险 | 应对 |
|---|---|
| X8 覆写 Batcher 顶点依赖框架内部布局 | ENGINE-PLAN A7.1 第 3 条的启动自检，失败时 `debug.fatal` |
| `graphics.drawSubsetWithMaterial(bindings, start, end, …)` 的第三个参数名叫 `end`，实际是**元素数量**（转给 `sg.draw(base, num, 1)`）。M1 的 UI 因此串画了纹理 | X8 的分块、覆盖层批次一律传 `index_end - index_start`；审查清单必查 |
| 屏幕空间 y 向下时 `Batcher.addQuad` 的 V 方向会反（M1 已在 UI 批次开 `flip_tex_y`） | 世界批次是 y 向上，不要照抄 UI 的设置；X8 截图核对贴图方向 |
| sokol 同一缓冲每帧只能更新一次 | 所有 `apply()` 只在 draw 路径里调；调试构建加帧内计数断言 |
| 软件渲染下 64×64 图帧率低 | 只验正确性；性能数字以 Windows 运行器为准 |
| 轴向与屏幕方向映射容易弄反 | L2 的测试用例由推导得出，D1 截图再确认一次（M1 的 UV 翻转就是这类问题） |
| 链路长（X3→X4→X5→X6→X8→X9→L4） | Lua 侧 L1–L3 与引擎链并行推进；X4/X5 可以交给同一个 sonnet 上下文顺序完成，减少交接 |
