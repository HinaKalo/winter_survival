-- Simulation driver: create a run, advance time, dispatch commands.
local state_mod = require("sim.state")
local clock = require("sim.clock")
local weather = require("sim.weather")
local home = require("sim.home")
local chars = require("sim.chars")
local needs = require("sim.needs")
local health = require("sim.health")
local power = require("sim.power")
local thermal = require("sim.thermal")
local craft = require("sim.craft")
local tech = require("sim.tech")
local commands = require("sim.commands")
local inventory = require("sim.inventory")
local items = require("data.items")
local balance = require("data.balance")
local util = require("core.util")

local M = {}

function M.new(seed, opts)
  opts = opts or {}
  local state = state_mod.new(seed, opts)
  state.opts = state.opts or {}
  state.opts.party_size = opts.party_size or balance.limits.party_size
  state.opts.difficulty = opts.difficulty or "normal"

  weather.generate(state)
  local h, err = home.init(state, opts)
  if not h then return nil, err end

  local party = chars.draw(state, state.opts.party_size)
  for _, id in ipairs(party) do
    local ch = chars.create(state, id)
    state.party.chars[id] = ch
  end
  state.party.order = party
  chars.setup_relations(state)

  for _, id in ipairs(util.sorted_keys(balance.start_stash)) do
    inventory.add(state.home.stash, id, balance.start_stash[id], { force = true })
  end

  -- opening state: the stove works, everything else is damaged (CONTENT C4)
  state.tech.unlocked.t_hearth = true
  for id in pairs(balance.start_blueprints or {}) do
    state.tech.blueprints[id] = true
  end
  state.stats.days = 1
  weather.refresh_forecast(state)
  state_mod.log(state, "run_started", { seed = state.seed, party = party })
  return state
end

-- Days of food/fuel left for the living party (CONTENT C5).
function M.food_days(state)
  local vp = 0
  for id, e in pairs(state.home.stash.items) do
    local def = items.get(id)
    if def and e.count > 0 and (items.has_tag(id, "food_any") or items.has_tag(id, "food_raw")
      or items.has_tag(id, "food_ingredient")) then
      vp = vp + def.vp * e.count
    end
  end
  local n = math.max(1, #chars.alive(state))
  return vp / (n * 30)
end

function M.fuel_days(state)
  local vp = 0
  for id, e in pairs(state.home.stash.items) do
    local def = items.get(id)
    if def and e.count > 0 and items.has_tag(id, "fuel_any") then
      vp = vp + def.vp * e.count
    end
  end
  local n = math.max(1, #chars.alive(state))
  return vp / (n * 6.3)
end

function M.record_day(state)
  local d = state.clock.day
  state.stats.food_days[d] = M.food_days(state)
  state.stats.fuel_days[d] = M.fuel_days(state)
end

function M.apply_night_roles(state)
  local roles = state.night.roles or {}
  for _, cid in ipairs(state.party.order) do
    local ch = state.party.chars[cid]
    if ch and ch.status == "alive" then
      local role = roles[cid] or "sleep"
      if role == "out" then
        ch.activity = "out"
      elseif role == "guard" then
        ch.activity = "guard"
      else
        ch.activity = "sleep"
      end
    end
  end
end

-- Phase boundary settlement. `to` is the new phase.
function M.advance_phase(state, to, from)
  if to == "night" then
    M.apply_night_roles(state)
    state_mod.log(state, "night_start", { day = state.clock.day })
  elseif to == "dawn" then
    for _, ch in ipairs(chars.alive(state)) do
      if ch.activity == "out" then ch.activity = "idle" end
      if ch.activity == "guard" then ch.activity = "idle" end
    end
    state_mod.log(state, "dawn", { day = state.clock.day })
  elseif to == "day" then
    state_mod.log(state, "day_start", { day = state.clock.day })
  end
end

function M.on_new_day(state, day)
  state.stats.days = day
  health.daily(state)
  weather.refresh_forecast(state)
  if day == 10 or day == 20 or day == 30 then M.record_day(state) end
  state_mod.log(state, "new_day", { day = day, alive = #chars.alive(state) })
end

function M.tick_minute(state)
  local events = clock.tick(state)
  for _, ev in ipairs(events) do
    if ev.kind == "new_day" then
      M.on_new_day(state, ev.day)
    elseif ev.kind == "phase" then
      M.advance_phase(state, ev.to, ev.from)
    elseif ev.kind == "ending" then
      state.stats.days = balance.time.days
      state_mod.log(state, "run_finished", { day = state.stats.days })
    end
  end
  if state.clock.phase == "ending" then return false end

  weather.update_outdoor(state)
  -- M3 keeps the clock at 1-minute steps but aggregates the heavier model systems
  -- every 5 minutes; the deltas are time-based so results stay stable.
  state.model_acc = (state.model_acc or 0) + 1
  if state.model_acc >= balance.model.step_minutes then
    local dt = state.model_acc
    state.model_acc = 0
    power.tick(state, dt)
    thermal.tick(state, dt)
    home.tick(state, dt)
    craft.tick(state, dt)
    tech.tick(state, dt)
    needs.tick(state, dt)
    health.tick(state, dt)
  end

  local alive = chars.alive(state)
  if #alive == 0 then
    state.clock.phase = "ending"
    state.stats.days = state.clock.day
    state_mod.log(state, "party_wiped", { day = state.clock.day })
    return false
  end
  for _, ch in ipairs(alive) do
    if ch.needs.food < state.stats.min_food then state.stats.min_food = ch.needs.food end
    if ch.needs.water < state.stats.min_water then state.stats.min_water = ch.needs.water end
    if ch.needs.temp < state.stats.min_temp then state.stats.min_temp = ch.needs.temp end
  end
  return true
end

function M.step(state, minutes)
  minutes = math.max(0, math.floor(minutes or 1))
  if state.clock.phase == "ending" then return state end
  for _ = 1, minutes do
    if not M.tick_minute(state) then break end
  end
  return state
end

function M.command(state, cmd)
  return commands.run(state, cmd)
end

function M.run(seed, days, opts)
  local state, err = M.new(seed, opts)
  if not state then return nil, err end
  local cap = (days or balance.time.days) * 1440
  M.step(state, cap)
  return state
end

function M.summary(state)
  local alive = chars.alive(state)
  local dead = {}
  for id, ch in pairs(state.party.chars) do
    if ch.status == "dead" then
      dead[#dead + 1] = { id = id, day = ch.death_day, cause = ch.death_cause }
    end
  end
  table.sort(dead, function(a, b)
    if a.day ~= b.day then return (a.day or 0) < (b.day or 0) end
    return a.id < b.id
  end)
  return {
    seed = state.seed,
    day = state.clock.day,
    phase = state.clock.phase,
    alive = #alive,
    alive_ids = chars.alive_ids(state),
    dead = dead,
    food_days = M.food_days(state),
    fuel_days = M.fuel_days(state),
    food_days_log = state.stats.food_days,
    fuel_days_log = state.stats.fuel_days,
    stats = state.stats,
    errors = state.errors,
    checksum = state_mod.checksum(state),
  }
end

return M
