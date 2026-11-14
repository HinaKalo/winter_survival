-- Reference bot: repaired devices are actually used (M3 bug pass).
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local sim = require("sim.sim")
local bot = require("sim.bot")
local inventory = require("sim.inventory")

local T = {}

function T.repaired_electric_heater_is_used()
  local s = assert(sim.new(71))
  local gen = s.home.stations.f_generator
  local heater = s.home.stations.f_electric_heater
  gen.hp = 100
  gen.on = false
  heater.hp = 100
  heater.on = false
  s.home.rooms.living.temp = -10
  assert(inventory.count(s.home.stash, "gasoline") >= 1)

  bot.morning(s)
  assert(gen.on, "bot starts the generator for the heater")
  assert(heater.on, "bot turns on a repaired electric heater")
end

function T.heater_off_when_room_is_warm()
  local s = assert(sim.new(72))
  local gen = s.home.stations.f_generator
  local heater = s.home.stations.f_electric_heater
  gen.hp = 100
  gen.on = false
  heater.hp = 100
  heater.on = true
  s.home.rooms.living.temp = 20

  bot.morning(s)
  assert(heater.on ~= true, "warm room does not need the electric heater")
end

return T
