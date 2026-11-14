-- 配方表（CONTENT §3）。工时单位：游戏分钟；fuel 为小数燃料，由 home.fuel_frac 累计。
-- bonus[char] = { work=0.6, cost=0.75, yield=1, fuel=0.7, water=0.8 }
local M = {}

M.recipes = {
  -- ------------------------------------------------------------- cooking
  heat_can = {
    kind = "craft", station = "hearth", minutes = 5, tech = "t_hearth",
    input_any = { { tag = "food_any", n = 1 } }, fuel = { firewood = 0.05 },
    effect = "hot_meal", bonus = { junho = { work = 0.6 } },
  },
  cook_meat = {
    kind = "craft", station = "hearth", minutes = 15, tech = "t_hearth",
    inputs = { raw_meat = 1 }, fuel = { firewood = 0.1 }, outputs = { cooked_meal = 1 },
  },
  cook_fish = {
    kind = "craft", station = "hearth", minutes = 12, tech = "t_hearth",
    inputs = { raw_fish = 1 }, fuel = { firewood = 0.1 }, outputs = { cooked_meal = 1 },
  },
  cook_roots = {
    kind = "craft", station = "hearth", minutes = 12, tech = "t_hearth",
    inputs = { wild_roots = 3 }, fuel = { firewood = 0.1 }, outputs = { cooked_meal = 1 },
  },
  cook_rat = {
    kind = "craft", station = "hearth", minutes = 15, tech = "t_rat_trap",
    inputs = { rat_meat = 2 }, fuel = { firewood = 0.1 }, outputs = { cooked_meal = 1 },
  },
  cook_rice = {
    kind = "craft", station = "hearth", minutes = 25, tech = "t_hearth",
    inputs = { dried_rice = 1, clean_water = 1 }, fuel = { firewood = 0.2 },
    outputs = { cooked_meal = 2 }, bonus = { junho = { yield = 1, fuel = 0.7, water = 0.8 } },
  },
  cook_stew = {
    kind = "craft", station = "hearth2", minutes = 35, tech = "t_hearth2",
    input_any = { { "raw_meat", "canned_meat" } }, inputs = { dried_rice = 1, clean_water = 1 },
    fuel = { firewood = 0.3 }, outputs = { stew = 2 },
    bonus = { junho = { yield = 1, fuel = 0.7 } },
  },
  grow_sprouts = {
    kind = "wait", station = "sprout_tray", minutes = 10, wait = 4320, tech = "t_sprout_tray",
    inputs = { dried_rice = 1, clean_water = 1 }, outputs = { sprouts = 3 },
  },
  smoke_meat = {
    kind = "wait", station = "smokehouse", minutes = 20, wait = 360, tech = "t_smokehouse",
    inputs = { raw_meat = 2, salt = 1 }, fuel = { firewood = 0.5 }, outputs = { smoked_meat = 2 },
    bonus = { junho = { work = 0.7 } },
  },
  roast_chicory = {
    kind = "craft", station = "hearth2", minutes = 20, tech = "t_chicory_roaster",
    inputs = { wild_roots = 2 }, fuel = { firewood = 0.15 }, outputs = { chicory_coffee = 2 },
  },
  distill_moonshine = {
    kind = "wait", station = "distiller", minutes = 20, wait = 240, tech = "t_distiller",
    inputs = { sugar = 3, dried_rice = 1, clean_water = 3 }, fuel = { firewood = 1 },
    outputs = { moonshine = 2 }, bonus = { junho = { yield = 1 } },
  },

  -- ---------------------------------------------------------------- water
  melt_snow = {
    kind = "wait", station = "snow_barrel", minutes = 5, wait = 60, tech = "t_snow_melter",
    fuel = { firewood = 0.5 }, outputs = { snow_water = 4 },
  },
  boil_water = {
    kind = "craft", station = "hearth", minutes = 20, tech = "t_hearth",
    inputs = { snow_water = 4 }, fuel = { firewood = 0.25 }, outputs = { clean_water = 4 },
    bonus = { junho = { fuel = 0.7, work = 0.8 } },
  },
  filter_water = {
    kind = "craft", station = "filter", minutes = 10, tech = "t_water_filter",
    inputs = { snow_water = 4 }, outputs = { clean_water = 4 },
  },
  make_filter = {
    kind = "craft", station = "bench1", minutes = 15, tech = "t_water_filter",
    inputs = { cloth = 1, coal = 1, scrap = 1 }, outputs = { filter_cartridge = 1 },
  },

  -- ------------------------------------------------------------ crafting
  make_nails = {
    kind = "craft", station = "bench1", minutes = 8, tech = "t_bench1",
    inputs = { scrap = 1 }, outputs = { nails = 6 }, bonus = { walt = { work = 0.7 } },
  },
  make_insulation = {
    kind = "craft", station = "bench1", minutes = 10, tech = "t_insulation_1",
    inputs = { cloth = 3 }, outputs = { insulation = 1 },
  },
  chop_planks = {
    kind = "craft", station = "hand", minutes = 10, tech = nil,
    inputs = { planks = 1 }, outputs = { firewood = 2 },
    tools_any = { { "axe", "hand_saw" } }, bonus = { walt = { work = 0.8 } },
  },
  repair_tool = {
    kind = "craft", station = "bench1", minutes = 10, tech = "t_bench1",
    inputs = { scrap = 1 }, effect = "repair_tool", bonus = { marcus = { cost = 0.75 } },
  },
  craft_crowbar = {
    kind = "craft", station = "bench1", minutes = 30, tech = "t_crowbar",
    inputs = { scrap = 3 }, outputs = { crowbar = 1 },
  },
  craft_shovel = {
    kind = "craft", station = "bench1", minutes = 25, tech = "t_shovel",
    inputs = { scrap = 2, planks = 1 }, outputs = { shovel = 1 }, bonus = { walt = { work = 0.7 } },
  },
  craft_pack_small = {
    kind = "craft", station = "bench1", minutes = 40, tech = "t_pack_small",
    inputs = { cloth = 4, rope = 1 }, outputs = { backpack_small = 1 },
  },
  craft_blanket = {
    kind = "craft", station = "bench1", minutes = 25, tech = "t_bed",
    inputs = { cloth = 5, insulation = 1 }, outputs = { blanket = 1 },
  },
  craft_pack_large = {
    kind = "craft", station = "bench2", minutes = 70, tech = "t_pack_small",
    inputs = { cloth = 8, rope = 2, duct_tape = 1 }, outputs = { backpack_large = 1 },
  },
  craft_lockpick = {
    kind = "craft", station = "bench2", minutes = 20, tech = "t_lockpick",
    inputs = { scrap = 1, wire = 1 }, outputs = { lockpick = 2 },
    bonus = { sam = { work = 0.5, yield = 1 } },
  },
  craft_knife = {
    kind = "craft", station = "bench2", minutes = 25, tech = "t_melee",
    inputs = { scrap = 2, cloth = 1 }, outputs = { knife = 1 },
  },
  craft_bat = {
    kind = "craft", station = "bench2", minutes = 25, tech = "t_melee",
    inputs = { planks = 2, nails = 4 }, outputs = { bat = 1 }, bonus = { walt = { work = 0.7 } },
  },
  craft_axe = {
    kind = "craft", station = "bench2", minutes = 45, tech = "t_melee",
    inputs = { scrap = 4, planks = 2 }, outputs = { axe = 1 }, bonus = { walt = { work = 0.7 } },
  },
  repair_weapon = {
    kind = "craft", station = "bench2", minutes = 20, tech = "t_melee",
    inputs = { scrap = 1, components = 1 }, effect = "repair_weapon",
    bonus = { grace = { work = 0.6 } },
  },
  craft_sled = {
    kind = "craft", station = "bench2", minutes = 90, tech = "t_sled",
    inputs = { planks = 6, rope = 2, nails = 10, scrap = 2 }, outputs = { sled = 1 },
    bonus = { walt = { work = 0.7, cost = 0.8 } },
  },
  craft_coat = {
    kind = "craft", station = "bench2", minutes = 60, tech = "t_coat1",
    inputs = { cloth = 6, insulation = 2, duct_tape = 1 }, outputs = { winter_coat = 1 },
  },
  craft_hat = {
    kind = "craft", station = "bench2", minutes = 20, tech = "t_coat1",
    inputs = { cloth = 2 }, outputs = { wool_hat = 1 },
  },
  craft_gloves = {
    kind = "craft", station = "bench2", minutes = 20, tech = "t_coat1",
    inputs = { cloth = 2 }, outputs = { wool_gloves = 1 },
  },
  craft_boots = {
    kind = "craft", station = "bench2", minutes = 40, tech = "t_coat1",
    inputs = { cloth = 3, insulation = 1, rope = 1 }, outputs = { snow_boots = 1 },
  },
  craft_coat2 = {
    kind = "craft", station = "bench3", minutes = 120, tech = "t_coat2",
    inputs = { cloth = 8, insulation = 4, duct_tape = 2, components = 2 }, outputs = { winter_coat_2 = 1 },
  },
  craft_suppressor = {
    kind = "craft", station = "bench3", minutes = 60, tech = "t_suppressor",
    inputs = { pipe = 1, insulation = 1, scrap = 2, components = 1 }, outputs = { suppressor = 1 },
    bonus = { grace = { work = 0.8 } },
  },
  craft_bear_trap = {
    kind = "craft", station = "bench3", minutes = 40, tech = "t_traps",
    inputs = { scrap = 4, components = 1 }, outputs = { bear_trap = 1 },
    bonus = { dale = { work = 0.7, yield = 1 } },
  },

  -- ------------------------------------------- repair/build/fortification
  clear_rubble = {
    kind = "craft", station = "hand", minutes = 20, tech = nil,
    effect = "clear_rubble", bonus = { walt = { work = 0.8 } },
  },
  salvage_furniture = {
    kind = "craft", station = "hand", minutes = 10, tech = "t_clear_tools",
    outputs = { planks = 2 }, effect = "salvage_furniture",
  },
  board_window = {
    kind = "craft", station = "hand", minutes = 20, tech = "t_board_up",
    inputs = { planks = 2, nails = 4 }, tools_all = { "hammer" },
    effect = "board_window", bonus = { walt = { work = 0.7, cost = 0.8 } },
  },
  board_hole = {
    kind = "craft", station = "hand", minutes = 35, tech = "t_board_up",
    inputs = { planks = 4, nails = 8 }, tools_all = { "hammer" },
    effect = "board_hole", bonus = { walt = { work = 0.7, cost = 0.8 } },
  },
  insulate_I = {
    kind = "craft", station = "hand", minutes = 3, tech = "t_insulation_1",
    per_cell = { insulation = 0.25, nails = 0.5 }, tools_all = { "hammer" },
    effect = "insulate", level = 1, bonus = { walt = { work = 0.7, cost = 0.8 } },
  },
  insulate_II = {
    kind = "craft", station = "hand", minutes = 5, tech = "t_insulation_2",
    per_cell = { insulation = 0.5, planks = 0.25, duct_tape = 0.1 }, tools_all = { "hammer" },
    effect = "insulate", level = 2, bonus = { walt = { work = 0.7, cost = 0.8 } },
  },
  reinforce_door_1 = {
    kind = "craft", station = "hand", minutes = 30, tech = "t_board_up",
    inputs = { planks = 4, nails = 8 }, tools_all = { "hammer" },
    effect = "reinforce_door", level = 1, bonus = { walt = { work = 0.7, cost = 0.8 } },
  },
  reinforce_door_2 = {
    kind = "craft", station = "bench2", minutes = 60, tech = "t_bench2",
    inputs = { scrap = 6, planks = 2, nails = 6, components = 2 },
    effect = "reinforce_door", level = 2, bonus = { walt = { work = 0.7, cost = 0.8 } },
  },
  reinforce_window = {
    kind = "craft", station = "hand", minutes = 25, tech = "t_board_up",
    inputs = { planks = 3, nails = 6 }, tools_all = { "hammer" },
    effect = "reinforce_window", bonus = { walt = { work = 0.7, cost = 0.8 } },
  },
  build_tripwire = {
    kind = "craft", station = "hand", minutes = 10, tech = "t_board_up",
    inputs = { scrap = 1, rope = 1 }, effect = "add_station", station_id = "f_tripwire",
    bonus = { dale = { work = 0.6 } },
  },
  repair_heater = {
    kind = "craft", station = "hand", minutes = 40, tech = "t_heater_repair",
    inputs = { heater_parts = 2, components = 1 }, effect = "repair_station",
    target = "f_electric_heater", bonus = { marcus = { work = 0.6, cost = 0.75 } },
  },
  repair_humidifier = {
    kind = "craft", station = "hand", minutes = 30, tech = "t_humidifier",
    inputs = { humidifier_parts = 2, components = 1 }, effect = "repair_station",
    target = "f_humidifier", bonus = { marcus = { work = 0.6, cost = 0.75 } },
  },
  repair_generator = {
    kind = "craft", station = "hand", minutes = 90, tech = "t_generator",
    inputs = { generator_parts = 3, components = 2 }, tools_all = { "toolbox" },
    effect = "repair_station", target = "f_generator",
    bonus = { marcus = { work = 0.6, cost = 0.75 } },
  },
  repair_radio = {
    kind = "craft", station = "hand", minutes = 60, tech = "t_radio_fix",
    inputs = { radio_parts = 2, electronics = 2 }, tools_all = { "multimeter" },
    effect = "repair_station", target = "f_radio",
    bonus = { linwei = { work = 0.6, cost = 0.75 } },
  },
  build_antenna = {
    kind = "craft", station = "bench1", minutes = 60, tech = "t_antenna",
    inputs = { wire = 4, pipe = 2, radio_parts = 1 }, effect = "add_station",
    station_id = "f_antenna", bonus = { linwei = { work = 0.6, cost = 0.75 } },
  },
  build_lamp = {
    kind = "craft", station = "bench1", minutes = 20, tech = "t_lamps",
    inputs = { components = 1, wire = 1, electronics = 1 }, effect = "add_station",
    station_id = "f_lamp", bonus = { linwei = { work = 0.7 } },
  },
  build_battery_bank = {
    kind = "craft", station = "bench3", minutes = 100, tech = "t_battery_bank",
    inputs = { battery = 8, electronics = 3, wire = 4, components = 3 },
    effect = "add_station", station_id = "f_battery_bank",
    bonus = { linwei = { work = 0.6 } },
  },
  build_shortwave = {
    kind = "craft", station = "bench3", minutes = 120, tech = "t_shortwave",
    inputs = { radio_parts = 3, electronics = 4, battery = 2 }, tools_all = { "multimeter" },
    effect = "add_station", station_id = "f_shortwave",
    bonus = { linwei = { work = 0.6, cost = 0.75 } },
  },
  build_propane_heater = {
    kind = "craft", station = "bench2", minutes = 60, tech = "t_propane_heater",
    inputs = { heater_parts = 2, pipe = 2, components = 2, scrap = 2 },
    effect = "add_station", station_id = "f_propane_heater",
    bonus = { marcus = { work = 0.6, cost = 0.75 } },
  },
  build_woodstove = {
    kind = "craft", station = "bench2", minutes = 120, tech = "t_wood_stove",
    inputs = { scrap = 10, pipe = 4, components = 2, duct_tape = 1 },
    effect = "add_station", station_id = "f_woodstove",
    bonus = { walt = { work = 0.7 } },
  },
  build_cold_cell = {
    kind = "craft", station = "hand", minutes = 180, tech = "t_cold_cell",
    inputs = { planks = 12, insulation = 12, nails = 20, duct_tape = 4 },
    tools_all = { "hammer" }, effect = "add_room", room_id = "cold_cell",
    bonus = { walt = { work = 0.6, cost = 0.8 } },
  },
  repair_car = {
    kind = "craft", station = "garage", minutes = 240, tech = "t_car_repair",
    inputs = { car_parts = 4, car_battery = 1, tire = 2 },
    tools_all = { "toolbox", "car_key" }, effect = "fact", fact = "car.fixed",
    bonus = { marcus = { work = 0.7 } },
  },

  -- ------------------------------------------------------------- medical
  improvise_bandage = {
    kind = "craft", station = "hearth", minutes = 15, tech = "t_hearth",
    inputs = { cloth = 2, clean_water = 1 }, fuel = { firewood = 0.1 },
    outputs = { bandage = 1 }, bonus = { elena = { yield = 1 } },
  },
  antiseptic_brew = {
    kind = "craft", station = "hand", minutes = 10, tech = nil,
    input_any = { { "whiskey", "moonshine" } }, outputs = { antiseptic = 2 },
    bonus = { elena = { yield = 1 } },
  },
  assemble_first_aid = {
    kind = "craft", station = "hand", minutes = 15, tech = nil,
    inputs = { bandage = 3, antiseptic = 1, painkillers = 1 }, outputs = { first_aid_kit = 1 },
    bonus = { elena = { work = 0.6 } },
  },
}

for id, r in pairs(M.recipes) do
  r.id = id
  r.name = "recipe." .. id .. ".name"
  r.time = (r.minutes or 0) + (r.wait or 0)
end

function M.get(id)
  return M.recipes[id]
end

M.count = 0
for _ in pairs(M.recipes) do M.count = M.count + 1 end

return M
