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

local function near(a, b, eps, msg)
  assert(math.abs(a - b) <= (eps or 1e-6), (msg or "value") .. ": got " .. tostring(a) .. ", want " .. tostring(b))
end

-- Total fuel burned = whole items removed + fraction still pending.
local function burned(s, st, item, before)
  return (before - inventory.count(s.home.stash, item)) + ((st.fuel_frac and st.fuel_frac[item]) or 0)
end

function T.woodstove_fuel_rates_from_balance()
  local P = require("data.balance").power.station
  near(P.f_woodstove_low.fuel_per_hour, 0.4)
  near(P.f_woodstove.fuel_per_hour, 1.0)
  for level, rate in pairs({ low = 0.4, full = 1.0 }) do
    local s = assert(sim.new(45))
    for _, st in pairs(s.home.stations) do st.on = false end
    local stove = s.home.stations.f_woodstove
    stove.on, stove.hp, stove.level = true, 100, level
    inventory.add(s.home.stash, "firewood", 40, { force = true })
    local before = inventory.count(s.home.stash, "firewood")
    for _ = 1, 5 do power.tick(s, 60) end
    near(burned(s, stove, "firewood", before), rate * 5, 1e-9, level .. " woodstove firewood over 5 h")
  end
end

function T.generator_fuel_formula()
  local s = assert(sim.new(46))
  local gen = s.home.stations.f_generator
  gen.hp, gen.on = 100, true
  local heater = s.home.stations.f_electric_heater
  heater.hp, heater.on = 100, true
  inventory.add(s.home.stash, "gasoline", 20, { force = true })
  local before = inventory.count(s.home.stash, "gasoline")
  power.tick(s, 60)
  -- 0.2 + 0.5 * (800 / 3000) L over one hour
  near(burned(s, gen, "gasoline", before), 0.2 + 0.5 * (800 / 3000), 1e-9, "generator L/h at 800 W")
  -- idle generator (no load): base only
  heater.on = false
  gen.fuel_frac = {}
  before = inventory.count(s.home.stash, "gasoline")
  power.tick(s, 60)
  near(burned(s, gen, "gasoline", before), 0.2, 1e-9, "generator L/h with no load")
end

function T.battery_charges_at_85_percent()
  local s = assert(sim.new(47))
  local gen = s.home.stations.f_generator
  gen.hp, gen.on = 100, true
  local heater = s.home.stations.f_electric_heater
  heater.hp, heater.on = 100, true
  local bat = home.add_station(s, "f_battery_bank", "battery_bank", "living", 100, false)
  bat.charge = 0
  inventory.add(s.home.stash, "gasoline", 20, { force = true })
  power.tick(s, 60)
  -- surplus (3000 - 800) W for one hour at 85% efficiency
  near(bat.charge, (3000 - 800) * 1 * 0.85, 1e-6, "battery charge Wh")
  assert(heater.powered == true)
end


function T.humidifier_stops_and_draws_nothing_when_humid()
  local s = assert(sim.new(71))
  local gen = s.home.stations.f_generator
  gen.hp, gen.on = 100, true
  local hum = s.home.stations.f_humidifier
  hum.hp, hum.on = 100, true
  inventory.add(s.home.stash, "gasoline", 20, { force = true })
  s.home.humidity = 50
  assert(power.load(s) == 60, "draws 60 W below the stop humidity")
  power.tick(s, 5)
  assert(hum.powered == true)
  s.home.humidity = 60
  assert(power.load(s) == 0, "no draw at H >= 60, got " .. power.load(s))
  power.tick(s, 5)
  assert(hum.powered == false, "stopped humidifier is not powered")
  s.home.humidity = 80
  assert(power.load(s) == 0)
end

function T.stopped_humidifier_adds_no_humidity()
  local s = assert(sim.new(72))
  for _, c in ipairs(require("sim.chars").alive(s)) do c.activity = "out" end
  for _, st in pairs(s.home.stations) do st.on = false end
  local hum = s.home.stations.f_humidifier
  hum.hp, hum.on, hum.powered = 100, true, false
  s.home.humidity = 25 -- no drift
  home.tick(s, 60)
  assert(s.home.humidity == 25, "unpowered humidifier adds nothing, got " .. s.home.humidity)
  hum.powered = true
  home.tick(s, 60)
  assert(s.home.humidity > 25, "powered humidifier raises humidity")
end

return T
