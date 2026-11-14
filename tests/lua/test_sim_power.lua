-- Power: load, generator fuel, battery, device power flags.
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local sim = require("sim.sim")
local power = require("sim.power")
local home = require("sim.home")
local inventory = require("sim.inventory")

local T = {}

function T.generator_powers_heater()
  local s = assert(sim.new(41))
  local gen = s.home.stations.f_generator
  gen.hp = 100
  gen.on = true
  local heater = s.home.stations.f_electric_heater
  heater.hp = 100
  heater.on = true
  inventory.add(s.home.stash, "gasoline", 20, { force = true })
  local gas = inventory.count(s.home.stash, "gasoline")
  power.tick(s, 60)
  assert(power.load(s) == 800, "load " .. power.load(s))
  assert(heater.powered == true, "heater powered")
  assert(inventory.count(s.home.stash, "gasoline") <= gas, "generator burns fuel")
end

function T.no_fuel_disables_device()
  local s = assert(sim.new(42))
  local gen = s.home.stations.f_generator
  gen.hp = 100
  gen.on = true
  s.home.stations.f_electric_heater.hp = 100
  s.home.stations.f_electric_heater.on = true
  local gas = inventory.count(s.home.stash, "gasoline")
  inventory.remove(s.home.stash, "gasoline", gas)
  power.tick(s, 60)
  assert(s.home.stations.f_electric_heater.powered ~= true)
end

function T.battery_discharge()
  local s = assert(sim.new(43))
  local bat = home.add_station(s, "f_battery_bank", "battery_bank", "living", 100, false)
  bat.charge = 2000
  s.home.stations.f_electric_heater.hp = 100
  s.home.stations.f_electric_heater.on = true
  power.tick(s, 60)
  assert(s.home.stations.f_electric_heater.powered == true)
  assert(bat.charge < 2000, "battery discharges")
end

function T.woodstove_burns_heat_fuel()
  local s = assert(sim.new(44))
  local stove = s.home.stations.f_woodstove
  assert(stove, "reference stove")
  stove.on = true
  stove.level = "low"
  local fire = inventory.count(s.home.stash, "firewood")
  local coal = inventory.count(s.home.stash, "coal")
  power.tick(s, 240)
  assert(inventory.count(s.home.stash, "firewood") + inventory.count(s.home.stash, "coal") < fire + coal,
    "stove consumes heat fuel")

  -- Coal is a valid heat fuel once the firewood is gone (fixed in M3 bug pass).
  inventory.remove(s.home.stash, "firewood", inventory.count(s.home.stash, "firewood"))
  local coal_only = inventory.count(s.home.stash, "coal")
  stove.on = true
  power.tick(s, 600)
  assert(inventory.count(s.home.stash, "coal") < coal_only, "stove falls back to coal")
end

return T
