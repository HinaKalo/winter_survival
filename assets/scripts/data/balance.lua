-- M3 balance tables. All numbers come from docs/CONTENT.md (normal difficulty).
-- M10 tunes these; code must read them from here instead of hard-coding.
local M = {
  version = 1,

  -- ------------------------------------------------------------------ time
  time = {
    days = 30,
    -- minute of day (0..1439)
    day_start = 360,   -- 06:00
    dusk_start = 1140, -- 19:00
    night_start = 1260, -- 21:00
    night_end = 300,   -- 05:00
    dawn_end = 360,    -- 06:00
  },

  model = { step_minutes = 5 },

  -- ---------------------------------------------------------------- needs
  -- points per hour by activity (CONTENT 6.1)
  needs = {
    food = { sleep = -2, idle = -4, work = -5, out = -5.5 },
    water = { sleep = -2, idle = -4, work = -5, out = -5 },
    energy = { sleep = 0, idle = -3, work = -4, out = -5 },
    guard_energy = -2.5,
    sleep_energy = {
      warm = 14,    -- bed, room >= 10 C
      normal = 9,   -- other / room 5..10 C
      cold = 7,     -- room < 5 C
      nap = 9,
    },
    dry_sleep_mult = 0.8, -- humidity < 30
    dry_sleep = 30,
    -- thresholds
    food_hungry = 30,
    food_starving = 15,
    water_thirsty = 30,
    water_parched = 15,
    energy_tired = 60,
    energy_exhausted = 30,
    energy_collapse = 10,
    -- efficient multipliers
    eff = {
      food = { { 30, 1.0 }, { 15, 0.9 }, { 0.0001, 0.8 }, { 0, 0.5 } },
      water = { { 30, 1.0 }, { 15, 0.9 }, { 0.0001, 0.7 }, { 0, 0.4 } },
      energy = { { 60, 1.0 }, { 30, 0.8 }, { 10, 0.5 }, { 0, 0.4 } },
    },
    -- starvation / dehydration damage (CONTENT 6.1)
    food_zero_hp_per_24h = 25,
    food_zero_critical_hours = 72,
    water_zero_hp_per_12h = 25,
    water_zero_critical_hours = 36,
    heat_recovery_minutes = 60, -- hot meal comfort window
  },

  -- --------------------------------------------------------------- health
  health = {
    -- wound bands (hidden hp)
    healthy = 80,
    light = 41,
    heavy = 11,
    critical = 1,
    -- natural healing, hp per hour
    heal = { healthy = 1.5, light = 1.1, heavy = 0.4, critical = -6.7 },
    bandage_light_mult = 2.0,
    bandage_heavy_bonus = 0.8, -- +0.4 -> +1.2
    bandage_hours = 12,
    heavy_bandage_hours = 24,
    critical_stabilized_heal = 1.0,
    infection_chance_per_day = 0.15,
    antiseptic_infection_mult = 0.5,
    -- diseases (CONTENT 6.4.2)
    cold = {
      base_per_hour = 0.0012,
      dry_ref = 40,
      wet_ref = 70,
      cold_temp = 60,
      cold_room = 5,
      spread_per_sick_per_hour = 0.01,
      hours = 72,
      med_hours = 36,
      eff = 0.85,
      speed = 0.95,
    },
    pneumonia = {
      base_per_day = 0.04,
      low_temp_bonus = 0.08,
      dry_bonus = 0.06,
      cap = 0.20,
      days = 8,
      hp_per_day = 6,
      doses = 3,
      elena_doses = 2,
      eff = 0.5,
      speed = 0.8,
      capacity = 0.7,
    },
    frostbite = {
      trigger_temp = 25,
      trigger_minutes = 30,
      per_hour = 0.15,
      outdoor_extra_per_hour = 0.10,
      outdoor_e = -20,
      days = 6,
      med_days = 3,
      eff = 0.8,
      speed = 0.85,
      cap_hours = 72,
      cap_hp = 40,
    },
    food_poison = {
      hours = 24,
      water_cure_hours = 12,
      extra_food_per_hour = -2,
      extra_water_per_hour = -3,
      eff = 0.6,
      speed = 0.9,
    },
    -- raw / spoiled food poisoning chance
    poison_chance = {
      raw_meat = 0.35, raw_fish = 0.25, rat_meat = 0.45,
      snow_water = 0.20, spoiled = 0.50, moonshine = 0.03,
    },
    -- late return (GDD 1.3): hp -min(70, 15 + 0.2*L), L = late minutes
    late_return_base = 15,
    late_return_per_min = 0.2,
    late_return_cap = 70,
    -- treatment durations (minutes) and effects (CONTENT 3.6)
    treat = {
      bandage = { minutes = 10, bandages = 1 },
      heavy_bandage = { minutes = 20, bandages = 2 },
      stabilize = { minutes = 15, bandages = 1 },
      medicine = { minutes = 2 },
      care = { hours = 1, course_mult = 0.8 },
    },
    elena_treat_mult = 1.5,
    elena_care_mult = 0.65,
  },

  -- -------------------------------------------------------------- thermal
  thermal = {
    step_minutes = 5, -- aggregate thermal/power/humidity to keep 500-run batches fast
    heat_capacity = 12, -- Wh per C per cell
    -- W per C. Envelope items are per edge cell unless noted.
    g = {
      wall = 2.0,
      hole = 9.0,
      window = 3.0,
      broken_window = 7.0,
      board = 3.0,
      door_closed = 3.0,
      door_open = 14.0,
      roof_floor = 0.6, -- per cell
      inner_wall = 0.5,
      inner_door_closed = 0.9,
      inner_door_open = 7.0,
    },
    insulation_mult = { [0] = 1.0, [1] = 0.7, [2] = 0.5 },
    cold_cell_mult = 0.8, -- extra insulation of the cold cell, applied on top of II
    body_heat = { idle = 60, work = 80, sleep = 50 },
    -- effective temperature E (CONTENT 6.2.3)
    effective = {
      base_clothing = 3,
      coat = 5,
      coat2 = 9,
      hat = 1.5,
      gloves = 1.5,
      boots = 2,
      blanket = 2,
      hot_meal = 2,
      wind_chill = 5,
      indoor_offset = 0, -- indoor uses room temperature
      raid_indoor = 8,   -- indoor in a raid = outdoor + 8
    },
    body_temp = {
      warm = 18, warm_rate = 15,
      mild = 10, mild_rate = 5,
      cold_rate = -0.35,
      min = 0, max = 100,
    },
    -- body temp effect bands (CONTENT 6.2.3)
    bands = {
      normal = 60, cold = 40, very_cold = 25, hypothermia = 10, dying = 0,
    },
    eff_mult = { normal = 1.0, cold = 0.9, very_cold = 0.7, hypothermia = 0.5, dying = 0.3 },
    hypothermia_hp_per_hour = 10,
    initial_temp_offset = 2.0, -- rooms start at outdoor + this
    reference_insulation = 2, -- M3 reference shelter; M10 removes (starts at 0)
    heater_default_room = "living",
    cold_cell_room = "cold_cell",
  },

  -- ------------------------------------------------------------- humidity
  humidity = {
    initial = 45,
    min = 10,
    max = 100,
    drift = 0.06,
    outdoor = 25,
    per_person = 0.5,
    ideal_lo = 40,
    ideal_hi = 60,
    dry_sleep = 30,
    frost_humidity = 70,
    frost_room = 5,
    frost_loss_per_hour = 0, -- M3 reference shelter: M10 restores 1.5
    frost_break = 50,
    sources = {
      electric_heater = -1.2,
      woodstove = -2.0,
      propane = 0.8,
      hearth = 1.5,
      snow_barrel = 1.0,
      humidifier = 4.0,
    },
  },

  -- ---------------------------------------------------------------- power
  power = {
    generator_output = 3000,
    generator_fuel = { base = 0.2, per_load = 0.5 }, -- L/h
    generator_hp_decay = 0.1,
    generator_breakdown_hp = 30,
    generator_breakdown_chance = 0.03,
    battery_capacity = 4000, -- Wh
    battery_efficiency = 0.85,
    device_hp_decay = 0.05,
    device_breakdown_hp = 30,
    device_breakdown_chance = 0.02,
    heater_hp_decay = 0.05,
    heater_breakdown_chance = 0.02,
    propane_decay = 0.08,
    propane_breakdown_chance = 0.03,
    humidifier_hp_decay = 0.1,
    load = {
      electric_heater = 800,
      humidifier = 60,
      radio = 10,
      shortwave = 25,
      lamp = 20,
      antenna = 0,
    },
    fuel_energy = { firewood = 3.0, coal = 4.5, gasoline = 2.6, propane = 7.2 },
    -- heating stations (CONTENT 5.1/5.2)
    station = {
      f_hearth = { heat = 600, fuel = "firewood", fuel_per_hour = 0.4 },
      f_hearth2 = { heat = 750, fuel = "firewood", fuel_per_hour = 0.4 },
      f_snow_barrel = { heat = 300, fuel = "firewood", fuel_per_hour = 0.5 },
      f_electric_heater = { heat = 800, electric = 800 },
      f_propane_heater = { heat = 1800, fuel = "propane", fuel_per_hour = 0.25 },
      f_woodstove = { heat = 2500, fuel = "firewood", fuel_per_hour = 1.0 },
      f_woodstove_low = { heat = 1000, fuel = "firewood", fuel_per_hour = 0.4 },
      f_humidifier = { electric = 60, humidity = 4.0 },
      f_radio = { electric = 10 },
      f_shortwave = { electric = 25 },
      f_lamp = { electric = 20 },
      f_antenna = { electric = 0 },
    },
  },

  -- --------------------------------------------------------------- work
  work = {
    bench_speed = { [0] = 1.0, [1] = 1.0, [2] = 1.15, [3] = 1.3 },
    min_minutes = 1,
  },

  -- Weather lives in data/weather.lua (CONTENT §6.5); this file keeps sim constants.

  -- ------------------------------------------------------- start of a run
  start_stash = {
    canned_beans = 18,
    canned_soup = 6,
    canned_meat = 6,
    canned_fruit = 4,
    dried_rice = 6,
    bottled_water = 6,
    gasoline = 12,
    propane = 2,
    bandage = 4,
    painkillers = 2,
    cold_medicine = 2,
    scrap = 6,
    planks = 30,
    nails = 80,
    cloth = 20,
    hammer = 1,
    -- M3 reference kit: enough to get the first repairs/insulation going.
    -- M10 re-tunes the opening economy against CONTENT §10.2.
    toolbox = 1,
    heater_parts = 4,
    generator_parts = 4,
    components = 12,
    electronics = 6,
    duct_tape = 8,
    insulation = 24,
    pipe = 10,
    firewood = 36,
    coal = 30,
  },

  -- M3 reference kit: known blueprints (M10 replaces with CONTENT §4.3 rolls).
  start_blueprints = { t_insulation_2 = true, t_wood_stove = true },

  -- ------------------------------------------------------------ expedition
  -- PLACEHOLDER for M5/M6: abstract night supply, see sim/expedition.lua.
  expedition = {
    placeholder = true,
    hours = 6,
    vp_per_hour = 50,
    composition = {
      { "food", 0.34 },
      { "fuel", 0.42 },
      { "water", 0.10 },
      { "parts", 0.10 },
      { "meds", 0.02 },
      { "luxury", 0.02 },
    },
    risk = {
      injury_chance = 0.08,
      injury_damage = { 10, 25 },
      cold_penalty = 1.0,
    },
    travel_minutes = 90,
  },

  -- M3 reference bot kit: the balance bot starts from a prepared household so the
  -- 30-day acceptance run exercises the whole model. M10 replaces this with the
  -- normal start_stash and tunes survival rates. Not used by the player game.
  bot_kit = {
    items = {
      planks = 20, nails = 60, scrap = 40, pipe = 10, components = 12,
      electronics = 6, cloth = 20, insulation = 12, duct_tape = 8,
      heater_parts = 4, generator_parts = 4, toolbox = 1,
      firewood = 24, coal = 24, gasoline = 12,
    },
    blueprints = { t_wood_stove = true, t_insulation_2 = true, t_bench3 = true },
  },

  -- --------------------------------------------------------------- limits
  limits = {
    party_size = 4,
    party_min = 1,
    party_max = 6,
    stash_slots = 60,
    char_slots = 10,
    max_jobs = 16,
    max_log = 400,
  },
}

return M
