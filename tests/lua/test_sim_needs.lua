-- Needs: decay by activity, eating/drinking, sleep recovery, body temperature.
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local sim = require("sim.sim")
local needs = require("sim.needs")
local chars = require("sim.chars")

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

return T
