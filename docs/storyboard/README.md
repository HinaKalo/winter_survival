# 《零下三十 / Thirty Below》故事板与分镜总览（Storyboard）

本目录存放《零下三十（Thirty Below / 영하 삼십）》的视觉分镜、过场演出、10 名幸存者角色线分镜、核心叙事弧分镜以及三幕节奏与触发点映射。

> **冲突隔离约定**：本分支仅新增 `docs/storyboard/` 目录，不修改 `assets/i18n/`、`assets/scripts/`、`tests/` 与 `docs/P0-PLAN.md`。

---

## 1. 上位文档与冻结契约对齐

| 契约 / 文档 | 对齐内容 | 所在位置 |
|---|---|---|
| **C9 触发时机（11 个）** | `door_day`、`radio`、`dawn`、`dusk`、`home_idle`、`raid_enter`、`raid_found`、`travel`、`dream`、`talk`、`crisis` | `PARALLEL-PLAN.md §2` / `NARRATIVE.md §2.7` |
| **C6 行为动词与标签** | 动词：`steal` / `rob` / `assault` / `knockout` / `kill` / `spare` / `help` / `give` / `trade_fair` / `trade_cheat` / `refuse_help` / `abandon` / `betray` / `rescue` / `bury` / `confess` / `return_goods` / `inform` / `die`；撬门与威吓不作动词，使用标签 `break_in`、`armed_threat`；其余标签见 `WORLD.md §2.2` | `NARRATIVE.md §2.4` / `WORLD.md §2.2` |
| **价值观三维** | `compassion`（同情）、`pragmatism`（务实）、`order`（秩序） | `WORLD.md §2.1` |
| **关键帧规格** | 全部 `kf_*` 关键帧为 `320×180` 像素画，整数 ×4 放大至 `1280×720`，不含半透明 | `ART-AUDIO.md §7.3` |
| **D14 温和叙述** | `crisis_*` 全程离屏纯文字、不写自伤/轻生手段细节；支持 `soft_narration` 开关与 `text_soft` 变体 | `WORLD.md §3.0` / `§12 R8` |
| **角色与 NPC ID** | 10 名幸存者（`marcus`、`elena`、`junho`、`linwei`、`dale`、`tasha`、`walt`、`priya`、`sam`、`grace`）与 19 名具名 NPC（`npc.<id>`） | `WORLD.md §3` / `§4.1` |

---

## 2. 目录清单

| 文件 | 内容 | 主要服务对象 |
|---|---|---|
| [01_keyframes_and_cutscenes.md](./01_keyframes_and_cutscenes.md) | 9 张 `kf_*` 关键帧构图与色板分镜、开场序列、寒潮过场、四大结局与尾声演出流 | 美术关键帧制作（GenAI + 手修）、`scenes/ending`、`scenes/dawn` |
| [02_character_arcs_30_beats.md](./02_character_arcs_30_beats.md) | 10 名幸存者 ×（1 句伏笔 `bark_<char>_0` + 3 段 `arc_<char>_1..3`）= 40 拍完整分镜、C6/C9 映射与台词方向 | M8 叙事引擎、M10 角色线铺量、三语 `i18n` |
| [03_storylets_world_and_kilo.md](./03_storylets_world_and_kilo.md) | 道德延迟回响链、基洛哨站主线弧、心理危机与 `text_soft` 对照分镜 | M8 规则验证、M9 哨站线、M10 片段池 |
| [04_act_pacing_and_slot_map.md](./04_act_pacing_and_slot_map.md) | 三幕 30 天张力曲线、11 个 C9 触发点的 UI 承载方式、每日曝光预算与资产交叉索引 | 导演系统调优（M8/M10）、UI/UX 对接 |
| [05_npc_encounters_and_barks.md](./05_npc_encounters_and_barks.md) | 19 名具名 NPC 的物件调度与初次/友好/敌对三态对白分镜 | M5 交易与门口交互、M8/M10 片段与 `i18n` |
| [06_ending_epilogues_and_recap.md](./06_ending_epilogues_and_recap.md) | 四大结局变体、10 名幸存者五档尾声卡片与“你做过的事”账本回顾屏文案方向 | M9 结局与尾声、`scenes/ending` |
