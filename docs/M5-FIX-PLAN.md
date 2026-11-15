# M5-FIX：修好了，但只是勉强能用

目标：玩家修好的设备、封上的窗户和墙洞要在 3D 模型上看得见。基调不变：这是战后废墟里拼凑出来的东西，不是新买的。

前置：M5-3D（`docs/M5-3D-PLAN.md`）已合并。模型源是用户交付的 `assets_src/models/ranch_a/house.blend`，需要 Blender 5.0 才能打开。本机已装 `blender5`（`~/.local/bin/blender5`，即 5.0.1）；4.2 版打不开这个文件。

## 1. 范围

| 游戏状态 | 现在的模型 | 新增节点 | 显示规则 |
|---|---|---|---|
| `electric_heater` 站 hp > 0 | `F1_electric_heater`（压扁的残骸，高 0.09 m） | `F1_electric_heater_fixed` | 有任一同类站 hp > 0 显示 `_fixed`、隐藏残骸；否则相反 |
| `generator` 站 hp > 0 | `F1_generator` | `F1_generator_fixed` | 同上 |
| `humidifier` 站 hp > 0 | `F1_humidifier` | `F1_humidifier_fixed` | 同上 |
| `structure.windows[k].boarded` | 只有 `F1_window_board_0_9`、`F1_window_board_19_3` 两块，而且一直显示（错误） | 7 扇窗各一块：`<层>_window_board_<x>_<y>` | `boarded` 才显示 |
| `structure.holes["17,0"].boarded` | 只有一块 DRESS 的临时堵板 | `F1_hole_board_17_0` | `boarded` 才显示；DRESS 的临时堵板保持不变 |

7 扇窗：

| 层 | 窗户 |
|---|---|
| B1 | (3,13)、(12,13) |
| F1 | (0,9)、(19,3)、(19,11) |
| F2 | (0,6)、(19,6) |

窗户的 structure key：1F 是 `"x,y"`，其他层是 `"B1:x,y"` 这样带层前缀；对应节点的层前缀取 `w.floor or "F1"`。

不在本轮：
- 新建设施（工作台、床等 `add_station`）的模型
- `reinforce_window` / `reinforce_door` 的样子（sim 里没有状态）
- B1 小暖炉

## 2. 美术要求（"勉强可用"）

总体：
- 材质只用 house.blend 现有调色板里的材质（`rust_*`、`wood_*`、`concrete_*`、`cloth_*` 等）。不加贴图，不加发光。
- 风格同 `dress.py`：低多边形盒子拼装，每个物件转 2–8°，偏一点。

修好的设备（`_fixed`）：
- 立起来了，但一眼能看出是拆东墙补西墙。
- 至少 3 种颜色：
  - 原机身（锈色或褪色）
  - 换上去的不配套零件，颜色明显不同
  - 胶带、铁丝或布条缠绕
- 外露的电线、拧歪的面板、用木块或砖垫平的脚，至少要有其中两样。
- 尺寸约束：
  - 高 0.35–1.6 m
  - 占地不超过约 1 格
  - 中心距残骸中心 < 0.6 m
  - 每件 48–900 三角面

各件具体做法：
- **发电机**：生锈的机壳、一块木板垫脚、油箱用另一种颜色的桶代替、拉绳缠着胶带、排气管是一截歪的烟囱管。
- **电暖器**：一台油汀或暖风机，散热片缺几片，后面露出接线，用铁丝绑在一块木板上。
- **加湿器**：一个水桶加一个拆来的小风扇，用布条和胶带固定，盖子是锅盖。

窗户木板：
- 2–4 块长短不一的木板，斜钉，留缝。
- 覆盖窗洞宽度和高度的大部分（≥ 70% 宽、≥ 60% 高）。
- 贴在窗户内侧。
- 每块 24–400 三角面。

墙洞木板 `F1_hole_board_17_0`：
- 比 DRESS 的临时堵板更结实：横竖交叉的几块厚木板，加一块铁皮或门板。
- 高 ≥ 1.0 m，36–600 三角面。

预算：
- 本轮新增 ≤ 6k 三角面。
- 整栋房子 ≤ 40k 三角面。

## 3. 代码

`assets/scripts/view/home3d.lua`：
- `node_visible` 加上 §1 的规则：
  - `_fixed` 与残骸成对，按站的种类和 hp 判断。
  - `<层>_window_board_<x>_<y>` 看对应 key 的 `boarded`。
  - `F1_hole_board_17_0` 看 `holes["17,0"].boarded`。
  - 不认识的 `_fixed` 名字按普通节点处理。
- 新增纯函数 `M.signature(state)`：
  - 返回字符串，至少编码这些状态：
    - 炉子和壁炉的开关
    - 可修复站的 hp > 0
    - 所有窗户和墙洞的 `boarded`
    - `rubble` 显示的块数
  - 同样的状态必须得到同样的字符串（窗户要按 key 排序后再拼）。
  - 时间、温度这类不影响模型的状态不能算进去。

`assets/scripts/scenes/home.lua`：
- `sync_model` 改用 `M.view_floor .. "|" .. home3d.signature(state)` 作为脏标记，取代现在手拼的 `parts`。

## 4. 资产管线

- 新脚本 `assets_src/models/ranch_a/fixed.py`：
  - 运行方式：`blender5 -b assets_src/models/ranch_a/house.blend --python assets_src/models/ranch_a/fixed.py`
  - 可重复运行：先删除自己以前加的对象，再重建，结果确定（固定随机种子）。
  - 新对象放进对应楼层的 Collection（B1 / F1 / F2），不放进 DRESS 集合。
  - 原有两块 `F1_window_board_*` 换成新做法的木板，名字不变。
  - 保存 `house.blend`。
  - 用与 `dress.py` 第 464–466 行完全相同的导出参数，重新导出 `house_full.glb`（以及 `floor_*.glb`，如果存在）。
- 烘焙：`python3 tools/model_bake.py assets_src/models/ranch_a/house_full.glb assets/models/ranch_a.wsm`。
- 预览图：给 3 件 `_fixed` 和一扇窗户木板各渲染一张特写（Workbench 渲染即可），放在 `assets_src/models/ranch_a/preview_fixed_*.png`。

## 5. 验收

| 测试 | 内容 |
|---|---|
| `tests/lua/test_home3d_repair.lua` | 规则和 signature |
| `tests/tools/test_model_fixed.py` | 节点齐全、位置、尺寸、颜色数、面数、预算 |
| `tests/probe/home_floors.lua` 新增 M5-FIX 段 | 真模型上，修好后 `_fixed` 出现，封窗、封洞后木板出现 |
| 原有测试 | 全绿，包括 `test_model_bake.py` 的确定性和 "wsm 不过期" 检查 |
| 截图 | 由主代理验收："勉强可用"、不像新品 |

命令：
- luatest：`mise exec -- zig build luatest`
- probe：参考 `ci/` 里 home_floors 的调用
- Python：`python3 -m unittest discover -s tests/tools -t .`
