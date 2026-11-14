-- Reference bot: plays a run using sim.command only (never touches state directly).
-- M3 acceptance: runs 30 days, no Lua errors, deterministic.
local balance = require("data.balance")
local sim = require("sim.sim")
local chars = require("sim.chars")
local home = require("sim.home")
local weather = require("sim.weather")
local craft = require("sim.craft")
local tech = require("sim.tech")
local inventory = require("sim.inventory")
local items = require("data.items")
local util = require("core.util")

local M = {}

local RESEARCH_ORDER = {
  "t_clear_tools", "t_board_up", "t_bench1", "t_heater_repair", "t_insulation_1",
  "t_shovel", "t_bench2", "t_generator", "t_hearth2", "t_insulation_2",
  "t_wood_stove", "t_snow_melter", "t_water_filter", "t_water_tank", "t_bed",
  "t_crowbar", "t_melee", "t_coat1", "t_lamps", "t_propane_heater",
  "t_radio_fix", "t_antenna", "t_bench3", "t_coat2", "t_humidifier",
}

local WEAR_ORDER = { "winter_coat_2", "winter_coat", "wool_hat", "wool_gloves", "snow_boots" }

local function run(state, cmd)
  return sim.command(state, cmd)
end

local function alive(state)
  return chars.alive(state)
end

local HYDRONIC = { hearth = true, hearth2 = true, woodstove = true, electric_heater = true, propane_heater = true }

local function warmest_room(state)
  -- Prefer the room with an active heater; body heat alone is not enough on day 1.
  local heat_room, heat_t = nil, -999
  for _, id in ipairs(util.sorted_keys(state.home.stations)) do
    local st = state.home.stations[id]
    if st.on and st.hp > 0 and HYDRONIC[st.kind] and (st.kind ~= "electric_heater" or st.powered) then
      local t = state.home.rooms[st.room] and state.home.rooms[st.room].temp or -999
      if t > heat_t then heat_room, heat_t = st.room, t end
    end
  end
  if heat_room then return heat_room end
  local best = state.home.default_room
  local best_t = -999
  for _, rid in ipairs(state.home.room_order) do
    local t = state.home.rooms[rid].temp
    if t > best_t then best, best_t = rid, t end
  end
  return best
end

local function equip_all(state)
  for _, ch in ipairs(alive(state)) do
    for _, id in ipairs(WEAR_ORDER) do
      local def = items.get(id)
      local slot
      if id == "winter_coat" or id == "winter_coat_2" then slot = "coat"
      elseif id == "wool_hat" then slot = "hat"
      elseif id == "wool_gloves" then slot = "gloves"
      elseif id == "snow_boots" then slot = "boots" end
      if slot and not ch.wear[slot] then
        run(state, { kind = "equip", char = ch.id, item = id })
      end
    end
  end
end

local function feed(state, threshold)
  for _, ch in ipairs(alive(state)) do
    if ch.needs.food < threshold then
      local ok = run(state, { kind = "eat", char = ch.id })
      if not ok then
        local water = run(state, { kind = "drink", char = ch.id })
        local _ = water
      end
    end
    if ch.needs.water < threshold then
      run(state, { kind = "drink", char = ch.id })
    end
  end
end

local function set_heater(state, id, on)
  local st = state.home.stations[id]
  if st and st.on ~= on then
    run(state, { kind = "toggle", station = id, on = on })
  end
end

local function manage_heat(state)
  local gen = state.home.stations.f_generator
  local heater = state.home.stations.f_electric_heater
  local humid = state.home.stations.f_humidifier
  local gas = inventory.count(state.home.stash, "gasoline")
  local heater_room_t = heater and home.room_temp(state, heater.room) or 99
  local have_generator = gen and gen.hp > 0
  local want_heater = heater and heater.hp > 0 and have_generator and heater_room_t < 12 and gas >= 1
  local need_power = want_heater or (humid and humid.hp > 0 and humid.on)

  if gen and gen.hp > 0 then
    if need_power and gas >= 1 and not gen.on then
      run(state, { kind = "toggle", station = "f_generator", on = true })
    elseif not need_power and gen.on then
      run(state, { kind = "toggle", station = "f_generator", on = false })
    elseif gen.on and gas < 1 then
      run(state, { kind = "toggle", station = "f_generator", on = false })
    end
  end
  if heater and heater.hp > 0 then
    if want_heater then set_heater(state, "f_electric_heater", true)
    elseif heater_room_t > 16 or gas < 1 then set_heater(state, "f_electric_heater", false) end
  end

  for _, id in ipairs(util.sorted_keys(state.home.stations)) do
    local st = state.home.stations[id]
    if st.hp > 0 and st.kind ~= "bed" then
      local t = home.room_temp(state, st.room)
      if st.kind == "hearth" or st.kind == "hearth2" or st.kind == "woodstove" or st.kind == "propane_heater" then
        local fuel_ok = true
        if st.kind == "propane_heater" then
          fuel_ok = inventory.count(state.home.stash, "propane") >= 1
        else
          fuel_ok = inventory.count(state.home.stash, "firewood") + inventory.count(state.home.stash, "coal") >= 1
        end
        -- Heat hard at night; let the house drift during the day to save fuel.
        local hour = state.clock.minute / 60
        local night_heat = hour >= 17 or hour < 8
        local on_below = night_heat and 2 or -6
        local off_above = night_heat and 14 or 0
        if st.kind == "woodstove" then
          local level = t < -5 and "high" or "low"
          if st.level ~= level then run(state, { kind = "set_level", station = id, level = level }) end
        end
        if t < on_below and fuel_ok then set_heater(state, id, true)
        elseif t > off_above then set_heater(state, id, false) end
      elseif st.kind == "electric_heater" then
        if t < 10 and need_power and gas >= 1 then set_heater(state, id, true)
        elseif t > 16 then set_heater(state, id, false) end
      elseif st.kind == "humidifier" then
        if state.home.humidity < 35 and inventory.count(state.home.stash, "clean_water") >= 1 then
          set_heater(state, id, true)
        elseif state.home.humidity > 55 then
          set_heater(state, id, false)
        end
      end
    end
  end
end

local function assign_rooms(state)
  local warm = warmest_room(state)
  for _, ch in ipairs(alive(state)) do
    if ch.room ~= warm and ch.activity ~= "out" then
      run(state, { kind = "assign", char = ch.id, room = warm })
    end
  end
end

local function try_repairs(state, ch)
  for _, id in ipairs({ "repair_heater", "repair_generator", "repair_humidifier", "repair_radio" }) do
    if craft.can(state, id, ch.id) then
      local ok = run(state, { kind = "craft", recipe = id, char = ch.id })
      if ok then return true end
    end
  end
  return false
end

local function try_fortify(state, ch)
  local order = {}
  local warm = warmest_room(state)
  order[#order + 1] = warm
  for _, rid in ipairs(state.home.room_order) do
    if rid ~= warm then order[#order + 1] = rid end
  end
  for _, rid in ipairs(order) do
    for _, id in ipairs({ "board_hole", "board_window", "insulate_I", "insulate_II" }) do
      if craft.can(state, id, ch.id, { room = rid }) then
        local ok = run(state, { kind = "craft", recipe = id, char = ch.id, room = rid })
        if ok then return true end
      end
    end
  end
  return false
end

local function try_food_water(state, ch)
  local food = inventory.team_count(state, "food_any")
  local water = inventory.team_count(state, "water_any")
  if food < 12 then
    for _, id in ipairs({ "cook_rice", "cook_meat", "cook_fish", "cook_roots", "heat_can" }) do
      if craft.can(state, id, ch.id) then
        local ok = run(state, { kind = "craft", recipe = id, char = ch.id })
        if ok then return true end
      end
    end
  end
  if water < 8 then
    for _, id in ipairs({ "boil_water", "melt_snow", "filter_water" }) do
      if craft.can(state, id, ch.id) then
        local ok = run(state, { kind = "craft", recipe = id, char = ch.id })
        if ok then return true end
      end
    end
  end
  return false
end

local function try_wear(state, ch)
  for _, id in ipairs({ "craft_coat", "craft_hat", "craft_gloves", "craft_boots" }) do
    if craft.can(state, id, ch.id) then
      local ok = run(state, { kind = "craft", recipe = id, char = ch.id })
      if ok then return true end
    end
  end
  return false
end

local function try_research(state, ch)
  if state.tech.research then return false end
  for _, id in ipairs(RESEARCH_ORDER) do
    if tech.can(state, id, ch.id) then
      local ok = run(state, { kind = "research", tech = id, char = ch.id })
      if ok then return true end
    end
  end
  return false
end

local function try_build(state, ch)
  for _, id in ipairs({ "build_woodstove", "build_battery_bank", "build_propane_heater", "build_lamp" }) do
    if craft.can(state, id, ch.id) then
      local ok = run(state, { kind = "craft", recipe = id, char = ch.id })
      if ok then return true end
    end
  end
  if inventory.count(state.home.stash, "insulation") < 6 and craft.can(state, "make_insulation", ch.id) then
    local ok = run(state, { kind = "craft", recipe = "make_insulation", char = ch.id })
    if ok then return true end
  end
  if inventory.count(state.home.stash, "nails") < 30 and craft.can(state, "make_nails", ch.id) then
    local ok = run(state, { kind = "craft", recipe = "make_nails", char = ch.id })
    if ok then return true end
  end
  return false
end

local function start_jobs(state)
  local warm = warmest_room(state)
  for _, ch in ipairs(alive(state)) do
    local off_duty = ch.activity == "sleep" or ch.activity == "out" or ch.activity == "guard"
    if ch.job and not off_duty and ch.activity ~= "work" then
      -- A paused job (activity changed) resumes: jobs are never cancelled by role changes.
      run(state, { kind = "activity", char = ch.id, value = "work" })
    end
    if not ch.job and not off_duty then
      local acted = false
      if ch.needs.energy > 25 then
        acted = try_research(state, ch)
        if not acted then acted = try_repairs(state, ch) end
        if not acted then acted = try_fortify(state, ch) end
        if not acted then acted = try_food_water(state, ch) end
        if not acted then acted = try_wear(state, ch) end
        if not acted then acted = try_build(state, ch) end
        if not acted and (state.home.rubble or 0) > 0 then
          if craft.can(state, "clear_rubble", ch.id) then
            run(state, { kind = "craft", recipe = "clear_rubble", char = ch.id })
            acted = true
          end
        end
      end
      if not ch.job then
        run(state, { kind = "assign", char = ch.id, room = warm })
      end
    end
  end
end

function M.morning(state)
  for _, ch in ipairs(alive(state)) do
    if ch.activity == "sleep" then run(state, { kind = "wake", char = ch.id }) end
  end
  equip_all(state)
  manage_heat(state)
  feed(state, 65)
  assign_rooms(state)
  start_jobs(state)
end

function M.dusk(state)
  feed(state, 75)
  manage_heat(state)
  assign_rooms(state)

  local order = alive(state)
  if #order == 0 then return end
  local roles = {}
  local field = {}
  local homebodies = {}
  for _, ch in ipairs(order) do
    if ch.role == "field" then field[#field + 1] = ch.id else homebodies[#homebodies + 1] = ch.id end
  end
  local max_out = (#order >= 3) and 2 or 1
  -- big snap night: only go out if we must
  local big = weather.is_big_snap_day(state, state.clock.day)
  if big and sim.food_days(state) > 2.0 then max_out = 0 end
  local squad = {}
  for _, id in ipairs(field) do
    if #squad < max_out then squad[#squad + 1] = id end
  end
  for _, id in ipairs(homebodies) do
    if #squad < max_out then squad[#squad + 1] = id end
  end
  for _, ch in ipairs(order) do roles[ch.id] = "sleep" end
  for _, id in ipairs(squad) do roles[id] = "out" end
  local guard
  if #order >= 3 then
    for _, id in ipairs(homebodies) do
      local used = false
      for _, s in ipairs(squad) do if s == id then used = true end end
      if not used then guard = id break end
    end
  end
  if guard then roles[guard] = "guard" end
  run(state, { kind = "night_roles", roles = roles, target = "suburb_house" })
  return squad
end

-- The squad is read back from the night roles (state), so a run restored from a save at the
-- start of night behaves exactly like an uninterrupted one.
local function squad_from_roles(state)
  local out = {}
  for _, id in ipairs(state.party.order) do
    if (state.night.roles or {})[id] == "out" then out[#out + 1] = id end
  end
  return out
end

function M.night_start(state, squad)
  squad = squad or squad_from_roles(state)
  local live = {}
  for _, id in ipairs(squad or {}) do
    local ch = state.party.chars[id]
    if ch and ch.status == "alive" then live[#live + 1] = id end
  end
  if #live > 0 then
    run(state, { kind = "expedition", squad = live, hours = balance.expedition.hours })
  end
end

function M.dawn(state)
  manage_heat(state)
  feed(state, 55)
  assign_rooms(state)
  start_jobs(state)
end

function M.manage(state)
  manage_heat(state)
  feed(state, 45)
  assign_rooms(state)
  start_jobs(state)
end

-- Plays one game day (06:00 -> next 06:00). Every decision is made from `state` alone, so the
-- run can be saved/restored at any phase boundary and continued by calling play_day again.
-- opts.stop_phase: return as soon as the clock enters that phase (before its handler runs).
function M.play_day(state, opts)
  opts = opts or {}
  local day = state.clock.day
  local start_phase = state.clock.phase
  local done = { morning = false, dusk = false, night = false, dawn = false }
  -- Resuming inside a phase whose handler already ran in the saved run is not supported;
  -- callers resume at a phase boundary.
  local guard = 0
  while state.clock.phase ~= "ending" and state.clock.day == day and guard < 1500 do
    guard = guard + 1
    local phase = state.clock.phase
    if opts.stop_phase and phase == opts.stop_phase and phase ~= start_phase then return true end
    if phase == "day" then
      if not done.morning then
        done.morning = true
        M.morning(state)
      end
      if state.clock.minute % 10 == 0 then M.manage(state) end
    elseif phase == "dusk" then
      if not done.dusk then
        done.dusk = true
        M.dusk(state)
      end
    elseif phase == "night" then
      if not done.night then
        done.night = true
        M.night_start(state)
      end
      if state.clock.minute % 10 == 0 then M.manage(state) end
    elseif phase == "dawn" then
      if not done.dawn then
        done.dawn = true
        M.dawn(state)
      end
    end
    sim.step(state, 1)
  end
  return state.clock.phase ~= "ending"
end

function M.run(state, opts)
  opts = opts or {}
  -- No kit logic here: the reference kit is given by sim.new(seed, { kit = "bot" }) (PLAN 9.1).
  local max_days = opts.days or balance.time.days
  local guard = 0
  while state.clock.phase ~= "ending" and state.clock.day <= max_days and guard < max_days + 2 do
    guard = guard + 1
    if not M.play_day(state, opts) then break end
  end
  return sim.summary(state)
end

return M
