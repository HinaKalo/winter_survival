-- Needs: decay by activity, eating/drinking, sleep recovery, body temperature.
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local sim = require("sim.sim")
local needs = require("sim.needs")
local chars = require("sim.chars")
local home = require("sim.home")
local health = require("sim.health")

local T = {}

local function first_char(state)
  return state.party.chars[state.party.order[1]]
end

function T.eat_and_drink()
  local s = assert(sim.new(11))
  local c = first_char(s)
  c.needs.food = 20
  c.needs.water = 20
  local ok = needs.eat(s, c)
  assert(ok, "eat")
  assert(c.needs.food > 20)
  local ok2 = needs.drink(s, c)
  assert(ok2, "drink")
  assert(c.needs.water > 20)
  assert(s.stats.meals >= 1)
end

function T.decay_by_activity()
  local s = assert(sim.new(12))
  local c = first_char(s)
  c.activity = "work"
  c.needs.food = 80
  c.needs.water = 80
  needs.tick(s, 60)
  assert(math.abs(c.needs.food - 75) < 0.1, "work food -5/h, got " .. c.needs.food)
  assert(math.abs(c.needs.water - 75) < 0.1, "work water -5/h, got " .. c.needs.water)
end

function T.sleep_recovers_energy()
  local s = assert(sim.new(13))
  local c = first_char(s)
  c.activity = "sleep"
  c.room = "kitchen"
  s.home.rooms.kitchen.temp = 15
  s.home.humidity = 45
  c.needs.energy = 40
  needs.tick(s, 60)
  assert(c.needs.energy > 45, "warm sleep recovers energy")
end

function T.body_temp_drops_when_cold()
  local s = assert(sim.new(14))
  local c = first_char(s)
  c.activity = "idle"
  c.room = "living"
  s.home.rooms.living.temp = -20
  c.needs.temp = 80
  needs.tick(s, 60)
  assert(c.needs.temp < 80, "body temp drops in a cold room")
end

function T.temperature_band_limits_efficiency()
  local s = assert(sim.new(15))
  local c = first_char(s)
  c.needs.temp = 100
  local warm = chars.efficiency(s, c)
  c.needs.temp = 20
  local cold = chars.efficiency(s, c)
  assert(cold < warm, "cold reduces efficiency")
end

local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

local function drop_beds(s)
  for id, st in pairs(s.home.stations) do
    if st.kind == "bed" then s.home.stations[id] = nil end
  end
end

function T.sleep_energy_table()
  local s = assert(sim.new(51))
  local c = first_char(s)
  c.room = "kitchen"
  s.clock.phase = "night"
  s.home.humidity = 45
  drop_beds(s)
  assert(near(needs.sleep_gain(s, c, 15), 9), "no bed, warm room: 9")
  assert(near(needs.sleep_gain(s, c, 3), 7), "no bed, cold room: 7")
  home.add_station(s, "f_bed", "bed", "kitchen", 100, false)
  assert(near(needs.sleep_gain(s, c, 15), 14), "bed, room >= 10: 14")
  assert(near(needs.sleep_gain(s, c, 10), 14))
  assert(near(needs.sleep_gain(s, c, 7), 9), "bed, 5..10: 9")
  assert(near(needs.sleep_gain(s, c, 3), 7), "cold < 5: 7")
  s.home.humidity = 25
  assert(near(needs.sleep_gain(s, c, 15), 14 * 0.8), "dry air x0.8")
  s.home.humidity = 45
  s.clock.phase = "day"
  assert(near(needs.sleep_gain(s, c, 15), 9), "daytime nap: 9")
  -- a bed in another room does not count
  s.clock.phase = "night"
  c.room = "living"
  assert(near(needs.sleep_gain(s, c, 15), 9), "bed must be in the character's room")
end

function T.sleep_tick_with_bed_is_14_per_hour()
  local s = assert(sim.new(52))
  local c = first_char(s)
  drop_beds(s)
  home.add_station(s, "f_bed", "bed", "kitchen", 100, false)
  c.room = "kitchen"
  c.activity = "sleep"
  s.clock.phase = "night"
  s.home.rooms.kitchen.temp = 15
  s.home.humidity = 45
  c.needs.energy = 20
  for _ = 1, 12 do needs.tick(s, 5) end
  assert(near(c.needs.energy, 34, 0.01), "energy " .. c.needs.energy)
end

function T.efficiency_bands()
  assert(chars.food_eff(30) == 1.0 and chars.food_eff(29.9) == 0.9)
  assert(chars.food_eff(15) == 0.9 and chars.food_eff(14.9) == 0.8)
  assert(chars.food_eff(0.1) == 0.8 and chars.food_eff(0) == 0.5)
  assert(chars.water_eff(30) == 1.0 and chars.water_eff(29.9) == 0.9)
  assert(chars.water_eff(14.9) == 0.7 and chars.water_eff(0) == 0.4)
  assert(near(chars.energy_eff(60), 1.0) and near(chars.energy_eff(75), 1.0))
  assert(near(chars.energy_eff(45), 0.9), "linear 60 -> 30")
  assert(near(chars.energy_eff(30), 0.8))
  assert(near(chars.energy_eff(20), 0.65), "linear 30 -> 10")
  assert(near(chars.energy_eff(10), 0.5))
  assert(near(chars.energy_eff(9.9), 0.4) and near(chars.energy_eff(0), 0.4), "exhausted")
  assert(chars.temp_eff(60) == 1.0 and chars.temp_eff(59) == 0.9 and chars.temp_eff(39) == 0.7)
  assert(chars.temp_eff(24) == 0.5 and chars.temp_eff(9) == 0.3)
end

function T.starvation_hp_clamp_after_72h()
  local s = assert(sim.new(53, { party_size = 1 }))
  local c = first_char(s)
  c.activity = "idle"
  local function run(hours)
    for _ = 1, hours * 12 do
      c.needs.water, c.needs.food = 100, 0
      c.needs.temp = 100
      needs.tick(s, 5)
    end
  end
  run(71)
  assert(c.health.hp > 10, "not yet dying at 71 h, hp " .. c.health.hp)
  assert(near(c.health.hp, 100 - 25 * 2))
  run(2)
  assert(c.health.hp <= 10, "hp clamped to the dying band after 72 h, hp " .. c.health.hp)
  assert(chars.wound(c) == "critical", chars.wound(c) .. " hp " .. c.health.hp .. " " .. c.status)
  assert(c.health.critical_cause == "starvation")
end

function T.dehydration_hp_clamp_after_36h()
  local s = assert(sim.new(54, { party_size = 1 }))
  local c = first_char(s)
  c.activity = "idle"
  local function run(hours)
    for _ = 1, hours * 12 do
      c.needs.food, c.needs.water = 100, 0
      c.needs.temp = 100
      needs.tick(s, 5)
    end
  end
  run(35)
  assert(c.health.hp > 10 and near(c.health.hp, 100 - 25 * 2), "hp " .. c.health.hp)
  run(2)
  assert(c.health.hp <= 10, "hp clamped after 36 h, hp " .. c.health.hp)
  assert(c.health.critical_cause == "dehydration")
end

function T.food_poison_drains_extra()
  local s = assert(sim.new(55))
  local c = first_char(s)
  c.activity = "idle"
  c.needs.food, c.needs.water = 100, 100
  health.add_disease(s, c, "food_poison")
  needs.tick(s, 60)
  assert(near(c.needs.food, 100 - 4 - 2, 0.01), "food " .. c.needs.food)
  assert(near(c.needs.water, 100 - 4 - 3, 0.01), "water " .. c.needs.water)
end


function T.cold_body_mood_from_balance()
  local balance = require("data.balance")
  local function mood_after_hour(entry)
    local s = assert(sim.new(15))
    local c = first_char(s)
    for _, o in ipairs(chars.alive(s)) do if o ~= c then o.activity = "out" end end
    c.activity = "idle"
    c.room = "living"
    s.home.rooms.living.temp = 12 -- neither cold (<8) nor warm (>=16) mood entries
    c.needs.food, c.needs.water, c.needs.energy = 90, 90, 90
    c.needs.temp = 10 -- the room warms the body +15 during the tick, stays below the cold band
    c.needs.mood = 50
    local saved = balance.thermal.cold_body_mood
    balance.thermal.cold_body_mood = entry
    needs.tick(s, 60)
    balance.thermal.cold_body_mood = saved
    return c.needs.mood
  end
  local base = mood_after_hour(0)
  local lowered = mood_after_hour(-3)
  assert(math.abs((base - lowered) - 3) < 1e-6, "mood entry read from balance, " .. base .. " vs " .. lowered)
  assert(balance.thermal.cold_body_mood == -0.4)
end

return T
