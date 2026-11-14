-- 三维价值观与行为权重（WORLD §2）。M3 只做完整性校验；M8 的 reactors 使用。
-- 代码不写死维数：新增维度只需改本表。
local M = {
  dimensions = { "compassion", "pragmatism", "order" },
}

-- 动词基线（同情 / 务实 / 秩序）。
M.verbs = {
  steal = { 0, 3, -6 },
  rob = { -4, 2, -9 },
  assault = { -8, 0, -5 },
  knockout = { -4, 0, -3 },
  kill = { -4, 0, -2 },
  spare = { 4, -1, 1 },
  help = { 6, -2, 0 },
  give = { 6, -2, 0 },
  rescue = { 6, -1, 0 },
  trade_fair = { 0, 1, 2 },
  trade_cheat = { -1, 2, -6 },
  refuse_help = { -5, 2, 0 },
  bury = { 4, 0, 3 },
  confess = { 3, -2, 10 },
  return_goods = { 5, -3, 7 },
  inform = { -1, 1, 3 },
}

-- 标签附加行（同情 / 务实 / 秩序）。
M.tags = {
  occupied = { -3, 0, -2 },
  victim_vulnerable = { -6, 0, -1 },
  victim_child = { -8, 0, -2 },
  took_essentials = { -4, 0, 0 },
  lethal = { -6, 0, -3 },
  armed_threat = { -3, 0, -3 },
  witnessed = { 0, -2, -1 },
  silenced = { -8, -3, -7 },
  target_raider = { 6, 2, 2 },
  target_soldier = { 0, -2, -4 },
  self_defense = { 6, 1, 3 },
  for_team = { 0, 4, 0 },
  helped_stranger = { 3, -1, 0 },
  cost_paid = { 2, 0, 0 },
  lied = { 0, 1, -4 },
}

-- 队友行为（WORLD §2.4）：不查权重表，走关系规则。
M.teammate_verbs = {
  abandon = { victim_relation = -25, others_stress = -8 },
  betray = { victim_relation = -40, others_stress = -10 },
  steal = { victim_relation = -15, others_stress = -6 },
  assault = { victim_relation = -30, others_stress = -10 },
  kill = { victim_relation = -60, others_stress = -16 },
  refuse_help = { victim_relation = -10, others_stress = -4 },
  rescue = { victim_relation = 10, others_stress = 6 },
  die = { victim_relation = 0, others_stress = -12 },
}

return M
