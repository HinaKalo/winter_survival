-- 10 名幸存者（WORLD §3、CONTENT §6.4.3）。数值字段给 sim 使用，叙事字段留在 WORLD。
-- role: home = 持家型，field = 外勤型，either = 只参与随机（开局抽人时不计入两类约束）。
local M = {
  order = {
    "marcus", "elena", "junho", "linwei", "dale",
    "tasha", "walt", "priya", "sam", "grace",
  },
  cards = {},
}

M.cards.marcus = {
  id = "marcus", name = "char.marcus", role = "home", age = 40,
  values = { compassion = 0.5, pragmatism = 0.6, order = 0.5 },
  capacity = 15, speed = 1.0,
  traits = { illness_risk = 1.0, cold_rate = 1.0, melee = 1.0, gun = 0.0, treat = 1.0,
    antibiotic_doses = 3, bandage_yield = 0, trade = 1.0, stealth_noise = 1.0,
    repair_work = 0.6, repair_cost = 0.75, craving = "cigarettes" },
  start_items = {},
  relation_bias = { walt = 10, dale = -5 },
}

M.cards.elena = {
  id = "elena", name = "char.elena", role = "home", age = 34,
  values = { compassion = 0.95, pragmatism = 0.2, order = 0.8 },
  capacity = 15, speed = 1.0,
  traits = { illness_risk = 1.0, cold_rate = 1.0, melee = 1.0, gun = 0.0, treat = 1.5,
    antibiotic_doses = 2, bandage_yield = 1, trade = 1.0, stealth_noise = 1.0,
    negative_morale = 1.4 },
  start_items = {},
  relation_bias = { grace = 10, priya = -10, sam = -5 },
}

M.cards.junho = {
  id = "junho", name = "char.junho", role = "home", age = 45,
  values = { compassion = 0.6, pragmatism = 0.5, order = 0.4 },
  capacity = 15, speed = 1.0,
  traits = { illness_risk = 1.0, cold_rate = 1.0, melee = 1.0, gun = 0.0, treat = 1.0,
    antibiotic_doses = 3, bandage_yield = 0, trade = 1.0, stealth_noise = 1.0,
    cook_yield = 1, cook_fuel = 0.7, cook_water = 0.8, craving = "moonshine" },
  start_items = {},
  relation_bias = { tasha = 10, priya = -5 },
}

M.cards.linwei = {
  id = "linwei", name = "char.linwei", role = "home", age = 26,
  values = { compassion = 0.6, pragmatism = 0.6, order = 0.7 },
  capacity = 13, speed = 1.0,
  traits = { illness_risk = 1.3, cold_rate = 1.3, melee = 0.6, gun = 0.0, treat = 1.0,
    antibiotic_doses = 3, bandage_yield = 0, trade = 1.0, stealth_noise = 1.0,
    electric_work = 0.6, electric_cost = 0.75, forecast_skill = 0.5 },
  start_items = { "multimeter" },
  relation_bias = { marcus = 5, walt = 5, dale = -5 },
}

M.cards.dale = {
  id = "dale", name = "char.dale", role = "field", age = 62,
  values = { compassion = 0.3, pragmatism = 0.8, order = 0.4 },
  capacity = 20, speed = 1.0,
  traits = { illness_risk = 1.0, cold_rate = 1.0, melee = 1.0, gun = 0.10, treat = 1.0,
    antibiotic_doses = 3, bandage_yield = 0, trade = 1.0, stealth_noise = 1.0,
    trap_work = 0.7 },
  start_items = { "hunting_rifle" },
  relation_bias = { grace = 5, priya = -10, tasha = 5 },
}

M.cards.tasha = {
  id = "tasha", name = "char.tasha", role = "field", age = 17,
  values = { compassion = 0.8, pragmatism = 0.2, order = 0.5 },
  capacity = 11, speed = 1.2,
  traits = { illness_risk = 1.0, cold_rate = 1.0, melee = 1.0, gun = 0.0, treat = 1.0,
    antibiotic_doses = 3, bandage_yield = 0, trade = 1.0, stealth_noise = 0.8,
    run_cost = 0.8, kill_morale = 2.0 },
  start_items = {},
  relation_bias = { junho = 10, grace = 5, sam = -5 },
}

M.cards.walt = {
  id = "walt", name = "char.walt", role = "home", age = 68,
  values = { compassion = 0.7, pragmatism = 0.3, order = 0.9 },
  capacity = 12, speed = 0.8,
  traits = { illness_risk = 1.6, cold_rate = 1.0, melee = 1.0, gun = 0.0, treat = 1.0,
    antibiotic_doses = 3, bandage_yield = 0, trade = 1.0, stealth_noise = 1.0,
    build_work = 0.7, build_cost = 0.8 },
  start_items = {},
  relation_bias = { marcus = 10, tasha = 10, sam = -5 },
}

M.cards.priya = {
  id = "priya", name = "char.priya", role = "either", age = 38,
  values = { compassion = 0.4, pragmatism = 0.9, order = 0.4 },
  capacity = 15, speed = 1.0,
  traits = { illness_risk = 1.0, cold_rate = 1.0, melee = 1.0, gun = 0.0, treat = 1.0,
    antibiotic_doses = 3, bandage_yield = 0, trade = 0.7, stealth_noise = 1.0,
    stress_need = 1.5 },
  start_items = {},
  relation_bias = { dale = -10, elena = -10, sam = 5 },
}

M.cards.sam = {
  id = "sam", name = "char.sam", role = "field", age = 33,
  values = { compassion = 0.5, pragmatism = 0.8, order = 0.2 },
  capacity = 15, speed = 1.0,
  traits = { illness_risk = 1.0, cold_rate = 1.0, melee = 1.0, gun = 0.0, treat = 1.0,
    antibiotic_doses = 3, bandage_yield = 0, trade = 1.0, stealth_noise = 0.8,
    lock_work = 0.5, lock_noise = 0.5, relation_start = -10 },
  start_items = { "lockpick" },
  relation_bias = { priya = 5, walt = -5, elena = -5, tasha = -5 },
}

M.cards.grace = {
  id = "grace", name = "char.grace", role = "field", age = 31,
  values = { compassion = 0.6, pragmatism = 0.5, order = 0.6 },
  capacity = 15, speed = 1.0,
  traits = { illness_risk = 1.0, cold_rate = 1.0, melee = 1.25, gun = 0.15, treat = 1.0,
    antibiotic_doses = 3, bandage_yield = 0, trade = 1.0, stealth_noise = 1.0,
    weapon_repair = 0.6, gun_shock = 0.2, nightmare = 0.1 },
  start_items = { "knife" },
  relation_bias = { elena = 10, dale = 5, priya = -5 },
}

function M.get(id)
  return M.cards[id]
end

return M
