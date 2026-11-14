-- Thermal: G computation, insulation, heater warm-up, effective temperature.
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local sim = require("sim.sim")
local thermal = require("sim.thermal")
local home = require("sim.home")
local weather = require("sim.weather")

local T = {}

function T.conductance()
  local s = assert(sim.new(31))
  -- The M3 reference shelter starts at insulation II; drop to 0 to measure the effect.
  s.home.rooms.living.insulation = 0
  home.rebuild(s)
  local before = thermal.room_g(s, "living")
  assert(before > 10, "living G " .. before)
  home.set_insulation(s, "living", 2)
  local after = thermal.room_g(s, "living")
  assert(after < before, "insulation lowers G: " .. before .. " -> " .. after)
end

function T.heater_warms_room()
  local s = assert(sim.new(32))
  s.home.rooms.kitchen.temp = weather.outdoor_temp(s)
  s.home.stations.f_hearth.on = true
  for _, c in ipairs(require("sim.chars").alive(s)) do c.room = "kitchen"; c.activity = "idle" end
  local before = s.home.rooms.kitchen.temp
  for _ = 1, 60 do thermal.tick(s, 5) end
  assert(s.home.rooms.kitchen.temp > before + 2, "hearth warms kitchen")
end

function T.effective_temp_clothing()
  local s = assert(sim.new(33))
  local c = s.party.chars[s.party.order[1]]
  c.room = "living"
  s.home.rooms.living.temp = -10
  c.activity = "idle"
  local e = thermal.effective_temp(s, c)
  assert(e > -10, "clothing adds to effective temperature")
  c.activity = "out"
  s.clock.minute = 1200
  local out_e = thermal.effective_temp(s, c)
  assert(out_e < e, "outdoor is colder than indoor")
end

function T.heat_capacity()
  local s = assert(sim.new(34))
  local c = thermal.heat_capacity(s, "kitchen")
  assert(c == 12 * s.home.rooms.kitchen.area, "C = 12 Wh/C per cell")
end

return T
