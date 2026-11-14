-- Power & fuel: generator, battery bank, electric devices, stoves (CONTENT §5.1/§5.2).
local balance = require("data.balance")
local inventory = require("sim.inventory")
local rng = require("core.rng")
local util = require("core.util")
local state_mod = require("sim.state")

local M = {}

local P = balance.power

local ELECTRIC = {
  electric_heater = true, humidifier = true, radio = true, shortwave = true,
  lamp = true, antenna = true,
}

local function is_electric(st)
  return ELECTRIC[st.kind] == true
end

-- Burn fuel for a station; fractional amounts accumulate on the station.
function M.burn(state, st, item, amount_per_hour, hours)
  st.fuel_frac = st.fuel_frac or {}
  local pool = (st.fuel_frac[item] or 0) + amount_per_hour * hours
  while pool >= 1 do
    if inventory.count(state.home.stash, item) < 1 then
      st.fuel_frac[item] = math.min(pool, 0.999)
      st.on = false
      state_mod.log(state, "fuel_out", { station = st.id, item = item })
      return false
    end
    inventory.remove(state.home.stash, item, 1)
    if item == "firewood" then
      state.stats.firewood_burned = (state.stats.firewood_burned or 0) + 1
    end
    pool = pool - 1
  end
  st.fuel_frac[item] = pool
  return true
end

function M.load(state)
  local total = 0
  for _, id in ipairs(util.sorted_keys(state.home.stations)) do
    local st = state.home.stations[id]
    if st.on and st.hp > 0 and is_electric(st) then
      total = total + (P.load[st.kind] or 0)
    end
  end
  return total
end

function M.device_powered(state, id)
  local st = state.home.stations[id]
  return st ~= nil and st.powered == true
end

-- Hearth/woodstove burn firewood or coal (coal is ~1.5x the heat per item).
function M.burn_heat(state, st, amount_per_hour, hours)
  if inventory.count(state.home.stash, "firewood") > 0 then
    return M.burn(state, st, "firewood", amount_per_hour, hours)
  elseif inventory.count(state.home.stash, "coal") > 0 then
    return M.burn(state, st, "coal", amount_per_hour / 1.5, hours)
  end
  st.on = false
  state_mod.log(state, "fuel_out", { station = st.id, item = "heat_fuel" })
  return false
end

function M.tick(state, minutes)
  minutes = minutes or balance.thermal.step_minutes
  local h = minutes / 60
  local stations = state.home.stations

  -- 1. heating fuel
  for _, id in ipairs(util.sorted_keys(stations)) do
    local st = stations[id]
    if st.on and st.hp > 0 then
      if st.kind == "hearth" or st.kind == "hearth2" then
        M.burn_heat(state, st, 0.4, h)
      elseif st.kind == "snow_barrel" then
        M.burn_heat(state, st, 0.5, h)
      elseif st.kind == "propane_heater" then
        M.burn(state, st, "propane", 0.25, h)
      elseif st.kind == "woodstove" then
        M.burn_heat(state, st, st.level == "low" and 0.3 or 0.7, h)
      end
    end
  end

  -- 2. electricity
  local load = M.load(state)
  local gen = stations.f_generator
  local battery = stations.f_battery_bank
  local supplied = 0
  local gen_running = false

  if gen and gen.on and gen.hp > 0 and inventory.count(state.home.stash, "gasoline") > 0 then
    gen_running = true
    supplied = math.min(P.generator_output, load)
    local ratio = math.min(1, load / P.generator_output)
    M.burn(state, gen, "gasoline", P.generator_fuel.base + P.generator_fuel.per_load * ratio, h)
    if gen.on then
      local surplus = P.generator_output - load
      if surplus > 0 and battery and battery.hp > 0 then
        battery.charge = math.min(P.battery_capacity, (battery.charge or 0) + surplus * h * P.battery_efficiency)
      end
    else
      supplied, gen_running = 0, false
    end
  end

  local deficit = math.max(0, load - supplied)
  if deficit > 0 and battery and battery.hp > 0 then
    local have = battery.charge or 0
    local give = math.min(have, deficit * h) / h
    battery.charge = math.max(0, have - give * h)
    supplied = supplied + give
  end
  supplied = math.min(load, supplied)

  -- 3. powered flags
  local remaining = supplied
  for _, id in ipairs(util.sorted_keys(stations)) do
    local st = stations[id]
    local need = is_electric(st) and (P.load[st.kind] or 0) or 0
    if need > 0 then
      if st.on and st.hp > 0 and remaining >= need - 0.001 then
        st.powered = true
        remaining = remaining - need
      else
        st.powered = false
      end
    else
      st.powered = true
    end
  end

  -- 4. wear / breakdown
  local r = state.rng.combat
  local function decay(st, per_hour, chance)
    st.hp = math.max(0, st.hp - per_hour * h)
    if st.hp > 0 and st.hp < P.device_breakdown_hp and rng.float(r) < chance * h then
      st.hp = 0
      st.on = false
      state_mod.log(state, "device_broken", { station = st.id })
    end
  end
  if gen and gen.hp > 0 and gen_running then decay(gen, P.generator_hp_decay, P.generator_breakdown_chance) end
  for _, id in ipairs(util.sorted_keys(stations)) do
    local st = stations[id]
    if st.on and st.hp > 0 then
      if st.kind == "electric_heater" and st.powered then decay(st, P.heater_hp_decay, P.heater_breakdown_chance) end
      if st.kind == "humidifier" and st.powered then decay(st, P.humidifier_hp_decay, P.device_breakdown_chance) end
      if st.kind == "propane_heater" then decay(st, P.propane_decay, P.propane_breakdown_chance) end
    end
  end

  -- 5. humidifier water
  local humid = stations.f_humidifier
  if humid and humid.on and humid.hp > 0 and humid.powered and state.home.humidity < 60 then
    humid.fuel_frac.clean_water = (humid.fuel_frac.clean_water or 0) + (1 / 10) * h
    while humid.fuel_frac.clean_water >= 1 do
      if inventory.count(state.home.stash, "clean_water") >= 1 then
        inventory.remove(state.home.stash, "clean_water", 1)
        humid.fuel_frac.clean_water = humid.fuel_frac.clean_water - 1
      else
        humid.fuel_frac.clean_water = math.min(humid.fuel_frac.clean_water, 0.999)
        break
      end
    end
  end

  state.home.power = {
    load = load,
    supplied = supplied,
    generator_on = gen_running,
    battery_charge = battery and battery.charge or 0,
  }
end

function M.available(state)
  return state.home.power and state.home.power.supplied or 0
end

return M
