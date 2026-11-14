-- Tech tree (CONTENT §4.2). 40 nodes.
-- bench: 0 = no bench, 1..3 = workbench level. blueprint = needs the bp_<id> item.
-- star = the research materials double as the first facility's build cost: on unlock the
-- facility is added for free (CONTENT §4.1). exclusive = needs that character at home,
-- otherwise cost/work x1.5.
local M = { list = {}, by_id = {} }

local function add(t)
  M.list[#M.list + 1] = t
  M.by_id[t.id] = t
  t.name = "tech." .. t.id .. ".name"
  return t
end

-- ------------------------------------------------------------------ survival
add { id = "t_hearth", layer = "S1", cost = { scrap = 3, planks = 1 }, work = 20, star = "f_hearth" }
add { id = "t_snow_melter", layer = "S1", cost = { scrap = 4, pipe = 1 }, work = 30, star = "f_snow_barrel" }
add { id = "t_water_tank", layer = "S1", prereq = { "t_snow_melter" }, cost = { scrap = 3, planks = 2, pipe = 2 }, work = 35, star = "f_water_tank" }
add { id = "t_hearth2", layer = "S2", prereq = { "t_hearth" }, cost = { scrap = 6, pipe = 2, components = 1 }, work = 45, bench = 1, star = "f_hearth2" }
add { id = "t_water_filter", layer = "S2", prereq = { "t_snow_melter" }, cost = { pipe = 2, cloth = 3, coal = 1, components = 1 }, work = 40, bench = 1, star = "f_filter" }
add { id = "t_rat_trap", layer = "S2", prereq = { "t_hearth" }, cost = { scrap = 2, wire = 1, planks = 1 }, work = 25, bench = 1, star = "f_rat_trap" }
add { id = "t_sprout_tray", layer = "S2", prereq = { "t_water_tank" }, cost = { planks = 2, cloth = 2 }, work = 20, bench = 1, star = "f_sprout_tray" }
add { id = "t_distiller", layer = "S3", prereq = { "t_hearth2", "t_water_filter" }, cost = { pipe = 4, scrap = 6, components = 3 }, work = 90, bench = 2, blueprint = true, star = "f_distiller" }
add { id = "t_smokehouse", layer = "S3", prereq = { "t_hearth2", "t_rat_trap" }, cost = { planks = 8, nails = 20, pipe = 2, salt = 2 }, work = 100, bench = 2, blueprint = true, star = "f_smokehouse" }
add { id = "t_chicory_roaster", layer = "S3", prereq = { "t_sprout_tray", "t_hearth2" }, cost = { scrap = 3, components = 2 }, work = 40, bench = 2 }

-- ------------------------------------------------------------------- warmth
add { id = "t_clear_tools", layer = "W1", cost = { scrap = 2 }, work = 10 }
add { id = "t_board_up", layer = "W1", prereq = { "t_clear_tools" }, cost = { planks = 2, nails = 6 }, work = 15 }
add { id = "t_bed", layer = "W1", cost = { planks = 3, cloth = 4 }, work = 25, star = "f_bed" }
add { id = "t_heater_repair", layer = "W2", prereq = { "t_board_up" }, cost = { components = 2, electronics = 1 }, work = 30, bench = 1 }
add { id = "t_humidifier", layer = "W2", prereq = { "t_heater_repair" }, cost = { components = 2, pipe = 1, electronics = 1 }, work = 35, bench = 1 }
add { id = "t_insulation_1", layer = "W2", prereq = { "t_board_up" }, cost = { cloth = 4, duct_tape = 1 }, work = 25, bench = 1 }
add { id = "t_propane_heater", layer = "W2", prereq = { "t_heater_repair" }, cost = { components = 2, pipe = 2, heater_parts = 1 }, work = 45, bench = 2 }
add { id = "t_wood_stove", layer = "W3", prereq = { "t_insulation_1", "t_hearth2" }, cost = { scrap = 6, pipe = 3, components = 2 }, work = 80, bench = 2, blueprint = true }
add { id = "t_insulation_2", layer = "W3", prereq = { "t_insulation_1" }, cost = { insulation = 4, duct_tape = 2, planks = 2 }, work = 60, bench = 2, blueprint = true }
add { id = "t_cold_cell", layer = "W3", prereq = { "t_insulation_2", "t_wood_stove" }, cost = { planks = 6, insulation = 6, nails = 10 }, work = 100, bench = 2, blueprint = true, exclusive = "walt" }

-- ------------------------------------------------------------------- crafting
add { id = "t_bench1", layer = "K1", cost = { planks = 6, nails = 20, scrap = 4 }, work = 60, star = "f_bench1" }
add { id = "t_crowbar", layer = "K1", prereq = { "t_bench1" }, cost = { scrap = 3 }, work = 15, bench = 1 }
add { id = "t_shovel", layer = "K1", prereq = { "t_bench1" }, cost = { scrap = 2, planks = 1 }, work = 15, bench = 1 }
add { id = "t_pack_small", layer = "K1", prereq = { "t_bench1" }, cost = { cloth = 4, rope = 1 }, work = 20, bench = 1 }
add { id = "t_bench2", layer = "K2", prereq = { "t_bench1", "t_shovel" }, cost = { planks = 6, scrap = 10, components = 4, nails = 20 }, work = 120, bench = 1, star = "f_bench2" }
add { id = "t_lockpick", layer = "K2", prereq = { "t_bench2", "t_crowbar" }, cost = { wire = 2, scrap = 3 }, work = 30, bench = 2 }
add { id = "t_melee", layer = "K2", prereq = { "t_bench2", "t_crowbar" }, cost = { scrap = 6, components = 2 }, work = 40, bench = 2 }
add { id = "t_sled", layer = "K2", prereq = { "t_bench2", "t_pack_small" }, cost = { planks = 4, rope = 2, nails = 10 }, work = 45, bench = 2 }
add { id = "t_coat1", layer = "K2", prereq = { "t_bench2", "t_bed" }, cost = { cloth = 6, insulation = 2, duct_tape = 1 }, work = 45, bench = 2 }
add { id = "t_bench3", layer = "K3", prereq = { "t_bench2" }, cost = { scrap = 14, components = 8, electronics = 3, pipe = 4 }, work = 180, bench = 2, blueprint = true, star = "f_bench3" }
add { id = "t_suppressor", layer = "K3", prereq = { "t_bench3", "t_melee" }, cost = { components = 3, pipe = 2, insulation = 2 }, work = 60, bench = 3, blueprint = true }
add { id = "t_traps", layer = "K3", prereq = { "t_bench3", "t_rat_trap" }, cost = { scrap = 6, components = 3, rope = 2 }, work = 60, bench = 3, blueprint = true, exclusive = "dale" }
add { id = "t_coat2", layer = "K3", prereq = { "t_coat1", "t_bench3" }, cost = { cloth = 10, insulation = 6, duct_tape = 3, components = 3 }, work = 90, bench = 3, blueprint = true }
add { id = "t_car_repair", layer = "K3", prereq = { "t_bench3", "t_generator" }, cost = { components = 6, pipe = 4, electronics = 4 }, work = 120, bench = 3, blueprint = true }

-- ----------------------------------------------------------- signal & power
add { id = "t_radio_fix", layer = "G1", cost = { radio_parts = 2, electronics = 2 }, work = 60, tool = "multimeter", star = "f_radio" }
add { id = "t_antenna", layer = "G2", prereq = { "t_radio_fix" }, cost = { wire = 4, pipe = 2, radio_parts = 1 }, work = 60, bench = 1, star = "f_antenna" }
add { id = "t_generator", layer = "G2", prereq = { "t_bench2" }, cost = { components = 3, electronics = 2 }, work = 40, bench = 2 }
add { id = "t_lamps", layer = "G2", prereq = { "t_generator" }, cost = { wire = 2, components = 1, electronics = 1 }, work = 20, bench = 1 }
add { id = "t_battery_bank", layer = "G3", prereq = { "t_generator" }, cost = { electronics = 3, components = 3, wire = 4 }, work = 60, bench = 3, blueprint = true }
add { id = "t_shortwave", layer = "G3", prereq = { "t_antenna", "t_generator" }, cost = { electronics = 4, radio_parts = 3 }, work = 90, bench = 3, blueprint = true, exclusive = "linwei", tool = "multimeter" }

-- Reverse index: which tech unlocks a recipe (data/recipes.lua tech field is the source).
M.stations = {
  t_hearth = "f_hearth", t_snow_melter = "f_snow_barrel", t_water_tank = "f_water_tank",
  t_hearth2 = "f_hearth2", t_water_filter = "f_filter", t_rat_trap = "f_rat_trap",
  t_sprout_tray = "f_sprout_tray", t_distiller = "f_distiller", t_smokehouse = "f_smokehouse",
  t_bed = "f_bed", t_bench1 = "f_bench1", t_bench2 = "f_bench2", t_bench3 = "f_bench3",
  t_radio_fix = "f_radio", t_antenna = "f_antenna",
}

function M.get(id)
  return M.by_id[id]
end

return M
