-- Health: wound bands, healing, disease, treatment, death.
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local sim = require("sim.sim")
local chars = require("sim.chars")
local health = require("sim.health")
local inventory = require("sim.inventory")
local state_mod = require("sim.state")
local balance = require("data.balance")
local home = require("sim.home")

local T = {}

local function first(state)
  return state.party.chars[state.party.order[1]]
end

function T.wound_bands()
  local s = assert(sim.new(21))
  local c = first(s)
  c.health.hp = 100
  assert(chars.wound(c) == "healthy")
  c.health.hp = 70
  assert(chars.wound(c) == "light")
  c.health.hp = 30
  assert(chars.wound(c) == "heavy")
  c.health.hp = 5
  assert(chars.wound(c) == "critical")
end

function T.add_wound_and_death()
  local s = assert(sim.new(22))
  local c = first(s)
  health.add_wound(s, c, 40, "test")
  assert(c.health.hp == 60 and chars.wound(c) == "light")
  local id = c.id
  health.add_wound(s, c, 100, "test")
  assert(c.status == "dead")
  for _, v in ipairs(s.party.order) do assert(v ~= id, "dead char removed from order") end
  local ok = state_mod.validate(s)
  assert(ok, "valid after death")
end

function T.healing()
  local s = assert(sim.new(23))
  local c = first(s)
  c.health.hp = 70
  c.health.bandage_hours = 12
  local before = c.health.hp
  health.tick(s, 60)
  assert(c.health.hp > before, "bandaged light wound heals")
end

function T.disease_and_treatment()
  local s = assert(sim.new(24))
  local c = first(s)
  local actor = c
  assert(health.add_disease(s, c, "cold"))
  assert(c.health.disease.cold)
  inventory.add(s.home.stash, "cold_medicine", 2, { force = true })
  assert(health.treat(s, c, actor, "cold_medicine"))
  assert(c.health.disease.cold.hours <= 36)
  assert(c.health.disease.cold.no_pneumonia == 24)
end

function T.frostbite_and_antiseptic()
  local s = assert(sim.new(25))
  local c = first(s)
  assert(health.add_disease(s, c, "frostbite"))
  inventory.add(s.home.stash, "antiseptic", 2, { force = true })
  assert(health.treat(s, c, c, "antiseptic"))
  assert(c.health.disease.frostbite.treated)
end

function T.hypothermia_damages()
  local s = assert(sim.new(26))
  local c = first(s)
  c.needs.temp = 5
  local hp = c.health.hp
  health.tick(s, 60)
  assert(c.health.hp < hp, "hypothermia drains hp")
end

function T.infection_false_is_not_true()
  local s = assert(sim.new(27))
  local c = first(s)
  c.health.infection = false
  local hp = c.health.hp
  health.daily(s)
  assert(c.health.hp == hp, "infection=false must not deal infection damage")
  assert(c.health.infection == false)
end

local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

local function topped(c)
  c.needs.food, c.needs.water, c.needs.energy, c.needs.temp, c.needs.mood = 100, 100, 100, 100, 100
end

function T.no_invented_critical_clamp()
  for seed = 1, 20 do
    local s = assert(sim.new(100 + seed))
    local c = first(s)
    health.add_wound(s, c, 50, "test")
    assert(near(c.health.hp, 50), "45+ damage has no extra clamp, hp " .. c.health.hp)
  end
end

function T.death_sets_both_flags_and_keeps_disease()
  local s = assert(sim.new(31))
  local c = first(s)
  health.add_disease(s, c, "cold")
  health.add_wound(s, c, 500, "test")
  assert(c.dead == true and c.status == "dead")
  assert(c.health.disease.cold, "disease stays at char.health.disease")
end

function T.frostbite_chance_rates_with_dt5()
  local s = assert(sim.new(32))
  local c = first(s)
  c.activity = "out"
  local thermal = require("sim.thermal")
  assert(thermal.effective_temp(s, c) > -20)
  assert(near(health.frostbite_chance(s, c, 5), 0.15 * 5 / 60), "15%/h scaled to a 5 min tick")
  s.weather.day_means[s.clock.day] = -45
  assert(thermal.effective_temp(s, c) < -20)
  assert(near(health.frostbite_chance(s, c, 5), 0.25 * 5 / 60), "+10%/h below E -20")
  c.activity = "idle"
  assert(health.frostbite_chance(s, c, 5) == 0, "frostbite only outdoors")
end

function T.frostbite_statistics_per_hour()
  local s = assert(sim.new(33, { party_size = 1 }))
  local c = first(s)
  c.activity = "out"
  local trials, hits = 1500, 0
  for _ = 1, trials do
    c.health.disease = {}
    c.health.frost_hours = 1
    c.needs.temp = 20
    c.health.hp = 100
    for _ = 1, 12 do health.tick(s, 5) end -- one hour
    if c.health.disease.frostbite then hits = hits + 1 end
  end
  local rate = hits / trials
  assert(rate > 0.11 and rate < 0.19, "~15%/h expected, got " .. rate)
  -- indoors it never happens
  c.activity = "idle"
  for _ = 1, 300 do
    c.health.disease = {}
    c.health.frost_hours = 1
    c.needs.temp = 20
    health.tick(s, 5)
    assert(not c.health.disease.frostbite, "no indoor frostbite")
  end
end

function T.infection_chance_rates()
  local s = assert(sim.new(34))
  local c = first(s)
  assert(near(health.infection_chance(c, 5), 0.15 * 5 / 1440, 1e-9))
  c.health.antiseptic_hours = 10
  assert(near(health.infection_chance(c, 5), 0.15 * 5 / 1440 * 0.5, 1e-9))
end

function T.infection_statistics_per_day()
  local s = assert(sim.new(35, { party_size = 1 }))
  local c = first(s)
  local trials, hits = 1500, 0
  for _ = 1, trials do
    c.health.hp = 30
    c.health.infection = false
    c.needs.food, c.needs.water = 100, 100
    for _ = 1, 72 do health.tick(s, 5) end -- 6 hours
    if c.health.infection then hits = hits + 1 end
  end
  local rate = hits / trials -- expected ~ 1-(1-0.15/288)^72 = 3.7%
  assert(rate > 0.02 and rate < 0.055, "heavy infection ~15%/day, got " .. rate)
end

function T.pneumonia_numbers()
  local s = assert(sim.new(36))
  local c = first(s)
  assert(health.add_disease(s, c, "pneumonia"))
  assert(c.health.disease.pneumonia.days == 8)
  topped(c)
  assert(near(chars.efficiency(s, c), 0.5), "pneumonia efficiency 0.5, got " .. chars.efficiency(s, c))
  assert(near(chars.capacity(s, c), c.capacity * 0.7), "pneumonia capacity x0.7")
  assert(near(chars.speed(s, c), (c.speed or 1) * 0.8), "pneumonia speed x0.8")
  -- one 5-minute tick drains 6 hp/day * 5/1440 and a day removes one day of course
  c.health.hp = 100
  health.tick(s, 5)
  assert(near(c.health.hp, 100 - 6 * 5 / 1440, 1e-6), "hp " .. c.health.hp)
  for _ = 1, 287 do health.tick(s, 5) end
  assert(near(c.health.disease.pneumonia.days, 8 - 1, 1e-6))
end

function T.antibiotics_one_dose_per_day()
  local s = assert(sim.new(37))
  local c = first(s)
  c.traits.treat = nil
  health.add_disease(s, c, "pneumonia")
  inventory.add(s.home.stash, "antibiotics", 5, { force = true })
  assert(health.treat(s, c, c, "antibiotics"))
  local ok, err = health.treat(s, c, c, "antibiotics")
  assert(ok == false and err == "dose_today", "second dose the same day refused")
  assert(inventory.count(s.home.stash, "antibiotics") == 4)
  s.clock.day = s.clock.day + 1
  assert(health.treat(s, c, c, "antibiotics"))
  assert(c.health.disease.pneumonia, "two doses do not cure yet")
  s.clock.day = s.clock.day + 1
  assert(health.treat(s, c, c, "antibiotics"))
  assert(not c.health.disease.pneumonia, "three daily doses cure")
end

local function level(c, hp)
  c.health.hp = hp
  topped(c)
  c.health.disease = {}
  c.health.painkiller_until = 0
end

function T.efficiency_combinations()
  local s = assert(sim.new(38))
  local c = first(s)
  level(c, 100)
  assert(near(chars.efficiency(s, c), 1.0))
  level(c, 70) -- light
  assert(near(chars.efficiency(s, c), 0.9))
  level(c, 30) -- heavy
  assert(near(chars.efficiency(s, c), 0.5))
  level(c, 100)
  c.health.disease = { cold = { id = "cold", hours = 10 } }
  assert(near(chars.efficiency(s, c), 0.85), "single disease value")
  level(c, 70)
  c.health.disease = { cold = { id = "cold", hours = 10 } }
  assert(near(chars.efficiency(s, c), 0.85 * 0.9), "light wound + cold: min(0.9, 0.85) x 0.9")
  level(c, 30)
  c.health.disease = { pneumonia = { id = "pneumonia", days = 3 } }
  assert(near(chars.efficiency(s, c), 0.5 * 0.9), "heavy + pneumonia: 0.5 x 0.9")
  c.health.painkiller_until = 100
  -- penalties halved: wound 0.75, pneumonia 0.75 -> 0.75 * 0.9
  assert(near(chars.efficiency(s, c), 0.75 * 0.9), "painkiller halves: " .. chars.efficiency(s, c))
  level(c, 70)
  c.health.painkiller_until = 100
  assert(near(chars.efficiency(s, c), 0.95))
  -- other factors still multiply
  level(c, 70)
  c.needs.food = 10
  assert(near(chars.efficiency(s, c), 0.9 * 0.8))
  -- dying: zero
  level(c, 5)
  assert(chars.efficiency(s, c) == 0)
end

function T.capacity_multipliers()
  local s = assert(sim.new(39))
  local c = first(s)
  local base = c.capacity
  level(c, 100)
  assert(near(chars.capacity(s, c), base))
  c.health.hp = 70
  assert(near(chars.capacity(s, c), base * 0.9), "light x0.9")
  c.health.hp = 30
  assert(near(chars.capacity(s, c), base * 0.6), "heavy x0.6")
  c.health.hp = 100
  c.health.disease.pneumonia = { id = "pneumonia", days = 3 }
  assert(near(chars.capacity(s, c), base * 0.7), "pneumonia x0.7")
end

local function count_everywhere(s, id)
  local n = inventory.count(s.home.stash, id)
  for _, cid in ipairs(s.party.order) do
    local c = s.party.chars[cid]
    n = n + inventory.count(c.inv, id)
    for _, worn in pairs(c.wear) do if worn == id then n = n + 1 end end
  end
  return n
end

function T.equip_unequip_ledger_and_capacity()
  local s = assert(sim.new(40))
  local c = first(s)
  local base_cap, base_slots = c.inv.kg_cap, c.inv.slots
  assert(near(base_cap, c.capacity) and base_slots == 10)
  inventory.add(s.home.stash, "backpack_small", 1, { force = true })
  inventory.add(s.home.stash, "winter_coat_2", 1, { force = true })
  local before = {}
  local ids = { "backpack_small", "winter_coat", "winter_coat_2", "wool_hat" }
  for _, id in ipairs(ids) do before[id] = count_everywhere(s, id) end
  assert(chars.equip(s, c, "backpack_small"))
  assert(near(c.inv.kg_cap, base_cap + 4) and c.inv.slots == base_slots + 6, "backpack raises capacity")
  assert(chars.equip(s, c, "winter_coat_2"))
  assert(c.wear.coat == "winter_coat_2")
  for _, id in ipairs(ids) do assert(count_everywhere(s, id) == before[id], "ledger " .. id) end
  assert(chars.unequip(s, c, "pack"))
  assert(near(c.inv.kg_cap, base_cap) and c.inv.slots == base_slots, "unequip restores capacity")
  assert(chars.unequip(s, c, "hat"))
  for _, id in ipairs(ids) do assert(count_everywhere(s, id) == before[id], "ledger " .. id) end
  assert(select(1, chars.unequip(s, c, "hat")) == false)
end


function T.wound_thresholds_come_from_balance()
  local s = assert(sim.new(81))
  local c = first(s)
  local H = balance.health
  local function band(hp) c.health.hp = hp return chars.wound(c) end
  assert(band(H.healthy + 1) == "healthy" and band(H.healthy) == "light")
  assert(band(H.light) == "light" and band(H.light - 1) == "heavy")
  assert(band(H.heavy) == "heavy" and band(H.heavy - 1) == "critical")
  assert(band(H.critical) == "critical" and band(0) == "dead")
  local saved = H.light
  H.light = 50
  local r = band(45)
  H.light = saved
  assert(r == "heavy", "moving balance.health.light moves the band, got " .. r)
end

function T.cold_spreads_only_within_a_room()
  local H = balance.health
  local saved_base, saved_spread = H.cold.base_per_hour, H.cold.spread_per_sick_per_hour
  H.cold.base_per_hour, H.cold.spread_per_sick_per_hour = 0, 100
  local ok, err = pcall(function()
    local s = assert(sim.new(82))
    local ids = s.party.order
    local a, b, c = s.party.chars[ids[1]], s.party.chars[ids[2]], s.party.chars[ids[3]]
    a.room, b.room, c.room = "living", "living", "bedroom"
    for _, id in ipairs(ids) do
      if id ~= a.id and id ~= b.id and id ~= c.id then s.party.chars[id].room = "kitchen" end
    end
    assert(health.add_disease(s, a, "cold"))
    health.daily(s)
    assert(b.health.disease.cold, "same room catches it")
    assert(not c.health.disease.cold, "another room does not")
    for _, id in ipairs(ids) do
      local ch = s.party.chars[id]
      if ch.room == "kitchen" then assert(not ch.health.disease.cold, "global spread must not happen") end
    end
  end)
  H.cold.base_per_hour, H.cold.spread_per_sick_per_hour = saved_base, saved_spread
  assert(ok, err)
end

local function with_frostbite(seed, room_temp, wound_hp)
  local s = assert(sim.new(seed))
  local c = first(s)
  c.room = "living"
  s.home.rooms.living.temp = room_temp
  c.health.hp = wound_hp or 100
  assert(health.add_disease(s, c, "frostbite"))
  inventory.add(s.home.stash, "bandage", 3, { force = true })
  return s, c
end

function T.frostbite_bandage_needs_warm_room()
  local s, c = with_frostbite(83, balance.health.frostbite.treat_room_temp - 0.5)
  local before = inventory.count(s.home.stash, "bandage")
  local ok, err = health.treat(s, c, c, "bandage")
  assert(ok == false and err == "too_cold", tostring(err))
  assert(not c.health.disease.frostbite.treated)
  assert(inventory.count(s.home.stash, "bandage") == before, "no bandage spent")
  s.home.rooms.living.temp = balance.health.frostbite.treat_room_temp
  assert(health.treat(s, c, c, "bandage"))
  assert(c.health.disease.frostbite.treated, "treated in a 12 C room")
  assert(inventory.count(s.home.stash, "bandage") == before - 1, "one bandage spent")
end

function T.frostbite_treatment_needs_a_bandage()
  local s, c = with_frostbite(84, 20)
  inventory.remove(s.home.stash, "bandage", inventory.count(s.home.stash, "bandage"))
  inventory.remove(c.inv, "bandage", inventory.count(c.inv, "bandage"))
  local ok, err = health.treat(s, c, c, "bandage")
  assert(ok == false and err == "missing", tostring(err))
  assert(not c.health.disease.frostbite.treated)
end

function T.light_wound_bandage_still_works_in_cold_room()
  local s, c = with_frostbite(85, 0, 60)
  assert(health.treat(s, c, c, "bandage"))
  assert(c.health.bandage_hours > 0, "wound bandaged")
  assert(not c.health.disease.frostbite.treated, "frostbite untouched in a cold room")
end

function T.placeholders_live_in_balance()
  local s = assert(sim.new(86))
  local c = first(s)
  local saved = balance.health.stabilize_body_temp
  balance.health.stabilize_body_temp = 33
  c.health.hp = 5
  c.needs.temp = 1
  inventory.add(s.home.stash, "bandage", 2, { force = true })
  local ok = health.treat(s, c, c, "bandage")
  balance.health.stabilize_body_temp = saved
  assert(ok and c.needs.temp == 33, "post-stabilise body temp from balance, got " .. c.needs.temp)
  -- infection damage per day from balance
  local s2 = assert(sim.new(87))
  local d = first(s2)
  d.health.infection = true
  local saved2 = balance.health.infection_daily_damage
  balance.health.infection_daily_damage = 7
  health.daily(s2)
  balance.health.infection_daily_damage = saved2
  assert(d.health.hp == 93, "infection damage from balance, hp " .. d.health.hp)
end

return T
