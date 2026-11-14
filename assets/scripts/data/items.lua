-- 物品目录（CONTENT §2，104 项）。
-- 字段：cat 主类；tags 标签；kg；stack 堆叠；vp 基础价值；use 使用效果；
--       spoil_h 变质小时（室温 > 5 C）；wear 有效温度加成；capacity 载重/格数加成。
local M = {}

M.items = {
  -- ------------------------------------------------------------ food/water
  canned_beans = { cat = "food", tags = { "food_any" }, kg = 0.45, stack = 12, vp = 10, use = { food = 30 } },
  canned_soup = { cat = "food", tags = { "food_any" }, kg = 0.4, stack = 12, vp = 7, use = { food = 20, water = 10 } },
  canned_meat = { cat = "food", tags = { "food_any" }, kg = 0.4, stack = 12, vp = 13, use = { food = 40 } },
  canned_fruit = { cat = "food", tags = { "food_any" }, kg = 0.45, stack = 12, vp = 6, use = { food = 15, water = 10, morale = 2 } },
  dried_rice = { cat = "food", tags = { "food_ingredient" }, kg = 0.5, stack = 20, vp = 24 },
  sugar = { cat = "food", tags = { "food_ingredient" }, kg = 0.5, stack = 20, vp = 6, use = { food = 8 } },
  salt = { cat = "food", tags = { "food_ingredient" }, kg = 0.5, stack = 20, vp = 4 },
  raw_meat = { cat = "food", tags = { "food_raw" }, kg = 0.6, stack = 8, vp = 8, use = { food = 30 }, poison = 0.35 },
  raw_fish = { cat = "food", tags = { "food_raw" }, kg = 0.5, stack = 8, vp = 7, use = { food = 25 }, poison = 0.25 },
  rat_meat = { cat = "food", tags = { "food_raw" }, kg = 0.2, stack = 20, vp = 3, use = { food = 10 }, poison = 0.45 },
  wild_roots = { cat = "food", tags = { "food_raw" }, kg = 0.3, stack = 20, vp = 2, use = { food = 10 }, poison = 0.10 },
  sprouts = { cat = "food", tags = { "food_any" }, kg = 0.2, stack = 12, vp = 5, use = { food = 15, morale = 1 } },
  cooked_meal = { cat = "food", tags = { "food_any" }, kg = 0.5, stack = 10, vp = 15, use = { food = 45, water = 5, morale = 3, hot = true }, spoil_h = 36 },
  stew = { cat = "food", tags = { "food_any" }, kg = 0.6, stack = 10, vp = 20, use = { food = 60, water = 10, morale = 4, hot = true }, spoil_h = 36 },
  smoked_meat = { cat = "food", tags = { "food_any" }, kg = 0.3, stack = 12, vp = 18, use = { food = 40 } },
  bottled_water = { cat = "water", tags = { "water_any" }, kg = 1.0, stack = 6, vp = 4, use = { water = 40 } },
  snow_water = { cat = "water", tags = {}, kg = 1.0, stack = 6, vp = 1, use = { water = 30 }, poison = 0.20 },
  clean_water = { cat = "water", tags = { "water_any" }, kg = 1.0, stack = 6, vp = 4, use = { water = 40 } },

  -- ---------------------------------------------------------------- fuel
  firewood = { cat = "fuel", tags = { "fuel_any", "heat_fuel" }, kg = 2.0, stack = 10, vp = 9, kwh = 3.0 },
  coal = { cat = "fuel", tags = { "fuel_any", "heat_fuel" }, kg = 1.5, stack = 10, vp = 13, kwh = 4.5 },
  gasoline = { cat = "fuel", tags = { "fuel_any" }, kg = 0.75, stack = 10, vp = 8, kwh = 2.6, liters = 1 },
  propane = { cat = "fuel", tags = { "fuel_any" }, kg = 1.0, stack = 4, vp = 22, kwh = 7.2 },

  -- ------------------------------------------------------------ materials
  scrap = { cat = "material", tags = { "parts_any" }, kg = 1.0, stack = 20, vp = 2 },
  components = { cat = "material", tags = { "parts_any" }, kg = 0.3, stack = 20, vp = 6 },
  electronics = { cat = "material", tags = { "parts_any" }, kg = 0.2, stack = 20, vp = 9 },
  cloth = { cat = "material", tags = { "parts_any" }, kg = 0.3, stack = 20, vp = 3 },
  insulation = { cat = "material", tags = { "parts_any" }, kg = 0.8, stack = 10, vp = 7 },
  planks = { cat = "material", tags = { "parts_any" }, kg = 1.5, stack = 10, vp = 3 },
  nails = { cat = "material", tags = { "parts_any" }, kg = 0.1, stack = 50, vp = 0.4 },
  rope = { cat = "material", tags = { "parts_any" }, kg = 0.3, stack = 10, vp = 3 },
  duct_tape = { cat = "material", tags = { "parts_any" }, kg = 0.2, stack = 10, vp = 4 },
  wire = { cat = "material", tags = { "parts_any" }, kg = 0.2, stack = 20, vp = 3 },
  pipe = { cat = "material", tags = { "parts_any" }, kg = 0.8, stack = 10, vp = 4 },
  heater_parts = { cat = "part", tags = { "parts_any" }, kg = 0.6, stack = 5, vp = 16 },
  humidifier_parts = { cat = "part", tags = { "parts_any" }, kg = 0.4, stack = 5, vp = 12 },
  radio_parts = { cat = "part", tags = { "parts_any" }, kg = 0.3, stack = 5, vp = 18 },
  generator_parts = { cat = "part", tags = { "parts_any" }, kg = 1.5, stack = 4, vp = 24 },
  battery = { cat = "part", tags = { "parts_any" }, kg = 0.3, stack = 10, vp = 8 },
  filter_cartridge = { cat = "part", tags = { "parts_any" }, kg = 0.4, stack = 5, vp = 12 },
  car_parts = { cat = "part", tags = { "car_part" }, kg = 3.0, stack = 4, vp = 30 },
  car_battery = { cat = "part", tags = { "car_part" }, kg = 8.0, stack = 1, vp = 40 },
  tire = { cat = "part", tags = { "car_part" }, kg = 9.0, stack = 1, vp = 30 },

  -- ----------------------------------------------------------------- meds
  bandage = { cat = "med", tags = { "med_any" }, kg = 0.1, stack = 20, vp = 6 },
  antibiotics = { cat = "med", tags = { "med_any" }, kg = 0.05, stack = 20, vp = 18 },
  painkillers = { cat = "med", tags = { "med_any" }, kg = 0.05, stack = 20, vp = 10 },
  cold_medicine = { cat = "med", tags = { "med_any" }, kg = 0.05, stack = 20, vp = 9 },
  antiseptic = { cat = "med", tags = { "med_any" }, kg = 0.3, stack = 10, vp = 8 },
  first_aid_kit = { cat = "med", tags = { "med_any" }, kg = 0.8, stack = 3, vp = 35 },
  insulin = { cat = "quest", tags = {}, kg = 0.05, stack = 4, vp = 60 },

  -- -------------------------------------------------------------- luxuries
  coffee = { cat = "luxury", tags = { "luxury_any" }, kg = 0.1, stack = 20, vp = 12, use = { energy = 15, morale = 6 } },
  instant_coffee = { cat = "luxury", tags = { "luxury_any" }, kg = 0.1, stack = 20, vp = 8, use = { energy = 12, morale = 4 } },
  chicory_coffee = { cat = "luxury", tags = { "luxury_any" }, kg = 0.1, stack = 20, vp = 4, use = { energy = 6, morale = 3 } },
  whiskey = { cat = "luxury", tags = { "luxury_any", "alcohol_any" }, kg = 0.9, stack = 6, vp = 28, use = { morale = 8, alcohol = true }, servings = 4 },
  moonshine = { cat = "luxury", tags = { "luxury_any", "alcohol_any" }, kg = 0.9, stack = 6, vp = 16, use = { morale = 7, alcohol = true }, poison = 0.03, servings = 4 },
  cigarettes = { cat = "luxury", tags = { "luxury_any" }, kg = 0.1, stack = 10, vp = 18, use = { morale = 4, smoke = true }, servings = 5 },
  book = { cat = "luxury", tags = { "luxury_any" }, kg = 0.5, stack = 6, vp = 10, use = { morale = 5 } },
  chocolate = { cat = "luxury", tags = { "luxury_any" }, kg = 0.1, stack = 20, vp = 10, use = { food = 10, morale = 5 } },

  -- ----------------------------------------------------------------- tools
  lockpick = { cat = "tool", tags = { "tool_any" }, kg = 0.1, stack = 5, vp = 8, durability = 15 },
  crowbar = { cat = "tool", tags = { "tool_any", "weapon_any", "melee_any" }, kg = 2.0, stack = 1, vp = 12, damage = 16, durability = 120 },
  shovel = { cat = "tool", tags = { "tool_any" }, kg = 2.5, stack = 1, vp = 10 },
  flashlight = { cat = "tool", tags = { "tool_any" }, kg = 0.4, stack = 1, vp = 14 },
  hammer = { cat = "tool", tags = { "tool_any" }, kg = 0.8, stack = 1, vp = 8 },
  hand_saw = { cat = "tool", tags = { "tool_any" }, kg = 0.7, stack = 1, vp = 8 },
  toolbox = { cat = "tool", tags = { "tool_any" }, kg = 3.0, stack = 1, vp = 30 },
  multimeter = { cat = "tool", tags = { "tool_any" }, kg = 0.3, stack = 1, vp = 18 },
  binoculars = { cat = "tool", tags = { "tool_any" }, kg = 0.5, stack = 1, vp = 22 },

  -- --------------------------------------------------------------- weapons
  knife = { cat = "weapon", tags = { "weapon_any", "melee_any" }, kg = 0.3, stack = 1, vp = 10, damage = 14, durability = 80 },
  bat = { cat = "weapon", tags = { "weapon_any", "melee_any" }, kg = 1.0, stack = 1, vp = 8, damage = 18, durability = 60 },
  axe = { cat = "weapon", tags = { "weapon_any", "melee_any" }, kg = 2.0, stack = 1, vp = 14, damage = 28, durability = 70 },
  handgun = { cat = "weapon", tags = { "weapon_any", "gun_any" }, kg = 1.0, stack = 1, vp = 90, damage = 30, magazine = 8, ammo = "handgun_ammo", durability = 150 },
  shotgun = { cat = "weapon", tags = { "weapon_any", "gun_any" }, kg = 3.2, stack = 1, vp = 140, damage = 55, magazine = 2, ammo = "shotgun_shells", durability = 100 },
  hunting_rifle = { cat = "weapon", tags = { "weapon_any", "gun_any" }, kg = 3.5, stack = 1, vp = 150, damage = 60, magazine = 4, ammo = "rifle_ammo", durability = 120 },
  suppressor = { cat = "weapon", tags = {}, kg = 0.3, stack = 1, vp = 50, durability = 60 },
  bear_trap = { cat = "weapon", tags = {}, kg = 1.5, stack = 4, vp = 20, damage = 25 },
  handgun_ammo = { cat = "ammo", tags = { "ammo_any" }, kg = 0.02, stack = 30, vp = 4 },
  shotgun_shells = { cat = "ammo", tags = { "ammo_any" }, kg = 0.05, stack = 20, vp = 6 },
  rifle_ammo = { cat = "ammo", tags = { "ammo_any" }, kg = 0.04, stack = 20, vp = 7 },

  -- ----------------------------------------------------------------- wear
  winter_coat = { cat = "wear", tags = { "wear_any" }, kg = 1.2, stack = 1, vp = 40, wear = 5 },
  winter_coat_2 = { cat = "wear", tags = { "wear_any" }, kg = 2.0, stack = 1, vp = 100, wear = 9 },
  wool_hat = { cat = "wear", tags = { "wear_any" }, kg = 0.1, stack = 1, vp = 8, wear = 1.5 },
  wool_gloves = { cat = "wear", tags = { "wear_any" }, kg = 0.1, stack = 1, vp = 8, wear = 1.5 },
  snow_boots = { cat = "wear", tags = { "wear_any" }, kg = 1.0, stack = 1, vp = 18, wear = 2 },
  backpack_small = { cat = "gear", tags = {}, kg = 0.5, stack = 1, vp = 15, carry_kg = 4, carry_slots = 6 },
  backpack_large = { cat = "gear", tags = {}, kg = 1.0, stack = 1, vp = 40, carry_kg = 10, carry_slots = 14 },
  sled = { cat = "gear", tags = {}, kg = 6.0, stack = 1, vp = 60, carry_kg = 20 },
  blanket = { cat = "gear", tags = {}, kg = 0.8, stack = 4, vp = 12, sleep_warmth = 2 },

  -- ---------------------------------------------------------------- quest
  keepsake = { cat = "quest", tags = {}, kg = 0.1, stack = 8, vp = 0 },
  kilo_pass = { cat = "quest", tags = {}, kg = 0, stack = 1, vp = 0 },
  kilo_ledger = { cat = "quest", tags = {}, kg = 0.3, stack = 1, vp = 0 },
  lieutenant_letter = { cat = "quest", tags = {}, kg = 0, stack = 1, vp = 0 },
  frequency_note = { cat = "quest", tags = {}, kg = 0, stack = 1, vp = 0 },
  car_key = { cat = "quest", tags = {}, kg = 0, stack = 1, vp = 0 },

  -- ------------------------------------------------------------ blueprints
  bp_bench3 = { cat = "blueprint", tags = { "blueprint_any" }, kg = 0.1, stack = 4, vp = 35, tech = "t_bench3" },
  bp_insulation_2 = { cat = "blueprint", tags = { "blueprint_any" }, kg = 0.1, stack = 4, vp = 35, tech = "t_insulation_2" },
  bp_wood_stove = { cat = "blueprint", tags = { "blueprint_any" }, kg = 0.1, stack = 4, vp = 35, tech = "t_wood_stove" },
  bp_cold_cell = { cat = "blueprint", tags = { "blueprint_any" }, kg = 0.1, stack = 4, vp = 35, tech = "t_cold_cell" },
  bp_distiller = { cat = "blueprint", tags = { "blueprint_any" }, kg = 0.1, stack = 4, vp = 35, tech = "t_distiller" },
  bp_smokehouse = { cat = "blueprint", tags = { "blueprint_any" }, kg = 0.1, stack = 4, vp = 35, tech = "t_smokehouse" },
  bp_suppressor = { cat = "blueprint", tags = { "blueprint_any" }, kg = 0.1, stack = 4, vp = 35, tech = "t_suppressor" },
  bp_traps = { cat = "blueprint", tags = { "blueprint_any" }, kg = 0.1, stack = 4, vp = 35, tech = "t_traps" },
  bp_coat2 = { cat = "blueprint", tags = { "blueprint_any" }, kg = 0.1, stack = 4, vp = 35, tech = "t_coat2" },
  bp_car_repair = { cat = "blueprint", tags = { "blueprint_any" }, kg = 0.1, stack = 4, vp = 35, tech = "t_car_repair" },
  bp_battery_bank = { cat = "blueprint", tags = { "blueprint_any" }, kg = 0.1, stack = 4, vp = 35, tech = "t_battery_bank" },
  bp_shortwave = { cat = "blueprint", tags = { "blueprint_any" }, kg = 0.1, stack = 4, vp = 35, tech = "t_shortwave" },
}

-- id -> true, and tag -> { id... } indexes (built once at load).
M.by_tag = {}
for id, def in pairs(M.items) do
  for _, tag in ipairs(def.tags) do
    local list = M.by_tag[tag]
    if not list then
      list = {}
      M.by_tag[tag] = list
    end
    list[#list + 1] = id
  end
end
for tag, list in pairs(M.by_tag) do
  table.sort(list)
end

function M.get(id)
  return M.items[id]
end

function M.has_tag(id, tag)
  local def = M.items[id]
  if not def then return false end
  for _, t in ipairs(def.tags) do
    if t == tag then return true end
  end
  return false
end

function M.ids_with_tag(tag)
  return M.by_tag[tag] or {}
end

M.count = 0
for _ in pairs(M.items) do M.count = M.count + 1 end

return M
