# 04 三幕叙事节奏与 11 触发点分布图

上位设计：`GDD.md §1.2 / §1.3`、`NARRATIVE.md §2.8`、`UI-UX.md §8 / §10`、`PARALLEL-PLAN.md §2 C9`。

---

## 1. 三幕 30 天叙事与张力节拍

| 幕 | 天数 | 叙事主题 | 主线与世界节拍 | 导演张力调节重点 |
|---|---|---|---|---|
| **第一幕：安顿** | Day 1–10 | 认识街区、修暖气、第一次抉择 | Day 1 开场 3 拍；Day 2–6 `radio_hobbs_first`；Day 3+ 陆续播出 `bark_<char>_0` 伏笔；Day 6–9 第 1 次小寒潮（`kf_coldsnap_a/b`）；Day 8–10 第一轮 `arc_*_1` | 优先保证生存可读性与角色建档；`ambient` 以资源两难（`neighbor_plea_sick_child`、`school_garza_door`）为主 |
| **第二幕：稀缺与回响** | Day 11–20 | 因果回头找上门、哨站开放 | Day 11 基洛哨站开放（`kilo_patrol_stop` / `arc_grace_1` / `radio_kilo_frequency`）；Day 13–17 第 2 次小寒潮；第一幕偷抢的住户在 2–5 天后以 `beggar_at_door` / `revenge_party` / `school_after_raid` 回响；`arc_*_2` 爆发 | 张力高时提高喘息型片段（如 `gift_from_friendly_household`）权重；`scheduled` 与 `crisis` 不占每日 2 次选项预算 |
| **第三幕：清算与大寒潮** | Day 21–30 | 去留抉择、终局验收 | Day 21 `kilo_slot_decision`；Day 21–24 第 3 次小寒潮（60%）；Day 22+ 全员 `arc_*_3` 终章抉择；Day 25+ 修车完成解锁 `south_depart`；Day 27 `kilo_betrayal` / 入住；Day 28–30 大寒潮 → `scenes/ending` | 强制收束个人线与势力线，减少无关 `ambient`，确保尾声与回顾屏能引用清晰因果 |

---

## 2. C9 的 11 个触发时机（`slot`）UI 承载与演出规范

| # | slot（C9） | 触发时段 | UI 容器与画面形式 | 暂停与预算 | 典型片段示例 |
|---|---|---|---|---|---|
| 1 | `door_day` | `day` | 门口提示条 → 点击弹出模态叙事卡（`panel_paper` + NPC 96×96 头像） | 打开卡片自动暂停；计入每日预算（排期除外） | `beggar_at_door`、`neighbor_plea_sick_child`、`school_garza_door`、`trader_odell_arrives` |
| 2 | `radio` | `day` / `dawn` | 无线电角标闪动 / 黎明报告内嵌短波卡（绿/琥珀指示灯色调） | 自动暂停；`ambient` 计预算，预报类不计 | `radio_hobbs_first`、`radio_coldwave_warn`、`radio_kilo_frequency` |
| 3 | `dawn` | `dawn` | 黎明报告全屏底图 `kf_dawn_report` 上方分页或独立叙事卡 | 时段本身不计时；排期回响不占预算 | `revenge_party`、`witness_testimony_st_mark`、`gift_from_friendly_household`、`kilo_betrayal` |
| 4 | `dusk` | `dusk` | 黄昏分配界面切换前弹出模态事件卡（带全员小头像状态参考） | 黄昏不计时；`arc_*_3` / `kilo_slot_decision` | `dusk_ration_dispute`、`dusk_storm_eve`、`kilo_slot_decision`、`south_depart` |
| 5 | `home_idle` | `day` | 角色头顶气泡（`bark_*_0` 无选项）或家园低频模态卡（有选项） | `bark_*_0` 不暂停不占预算；有选项片段自动暂停 | `bark_marcus_0`、`arc_sam_1`、`arc_junho_1` |
| 6 | `raid_enter` | `night` | 进入副本后首帧定格模态提示卡（保留暗夜潜行底图与警戒 UI） | 自动暂停；直接影响当前副本开局姿态 | `raid_enter_wakes_child` |
| 7 | `raid_found` | `night` | 搜刮特定容器/地下室完成瞬间弹出模态选择卡 | 自动暂停；高紧张度，BGM 压低 | `raid_found_hidden_cellar`、`raid_found_dead_household`、`raid_found_ledger` |
| 8 | `travel` | `day` / `night` | 地图节点连线行进途中弹出过路卡（底图为暗化 `kf_map`） | 行进暂停；选择后继续结算路程时间 | `kilo_patrol_stop`、`kilo_marsh_meeting`、`travel_frozen_stranger`、`travel_raider_toll` |
| 9 | `dream` | `dawn`（睡醒瞬间） | 黑底冷蓝极简文字卡（无选项，2–3s 后可点击关闭进入黎明报告） | 不占预算，不显示善恶数值，仅写压力原因键 | `dream_victim_returns`、`dream_grace_gunfire` |
| 10 | `talk` | `day` / `dusk` | 双人对话模态卡（左右分别显示提问队友与回应/默认代表头像） | 自动暂停；`arc` 线主承载时机 | `talk_judges_deed`、`arc_elena_2`、`arc_grace_1` |
| 11 | `crisis` | 任意时段切换边界 | 深色纸面板模态卡，严格执行 D14 离屏纯文字 + `soft_narration` | 强制暂停，**不占每日预算**，高优先级阻断 | `crisis_breakdown_warning`、`crisis_intervene`、`crisis_runaway` |

---

## 3. 故事板涉及的资产与音频交叉索引

| 资产组 | 对应文档位置 | 本故事板使用处 |
|---|---|---|
| 9 张 `kf_*` 关键帧（320×180） | `ART-AUDIO.md §7.3` | [01_keyframes_and_cutscenes.md](./01_keyframes_and_cutscenes.md) 全部过场、大地图、黎明、四大结局 |
| 10 名角色 96×96 / 48×48 多情绪头像 | `ART-AUDIO.md §7.2` | [02_character_arcs_30_beats.md](./02_character_arcs_30_beats.md) 与 `crisis` / `talk` 卡片 |
| 结局曲 `bgm/ending_*`（4 首，不循环） | `ART-AUDIO.md §11.2` | `scenes/ending` 四大结局定格与尾声翻页 |
| 环境音 `amb/*` 与 UI 音效 `sfx/ui_*` | `ART-AUDIO.md §11.2` / `UI-UX.md §10.2` | 寒潮过场风雪压低（ducking）、无线电杂音、模态卡弹出提示音 |
