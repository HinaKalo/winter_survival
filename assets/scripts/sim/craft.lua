-- Crafting / building / repair jobs (CONTENT §3).
local balance = require("data.balance")
local recipes = require("data.recipes")
local items = require("data.items")
local inventory = require("sim.inventory")
local util = require("core.util")
local rng = require("core.rng")
local chars = require("sim.chars")
local home = require("sim.home")
local state_mod = require("sim.state")

local M = {}

local W = balance.work

local function bench_level(state)
  local best = 0
  for _, id in ipairs(util.sorted_keys(state.home.stations)) do
    local st = state.home.stations[id]
    if st.hp > 0 then
      if st.kind == "bench3" then best = math.max(best, 3)
      elseif st.kind == "bench2" then best = math.max(best, 2)
      elseif st.kind == "bench1" then best = math.max(best, 1) end
    end
  end
  return best
end

function M.bench_level(state)
  return bench_level(state)
end

local function room_for(state, cid)
  local ch = state.party.chars[cid]
  return ch and ch.room or state.home.default_room
end

local function have_tool(state, ch, id)
  return inventory.count(ch.inv, id) > 0 or inventory.count(state.home.stash, id) > 0
end

local function bonus_of(recipe, cid)
  return (recipe.bonus or {})[cid] or {}
end

local function adjusted(n, mult)
  if mult >= 1 then return n end
  return math.max(1, math.ceil(n * mult - 0.0001))
end

local function station_ok(state, recipe)
  if not recipe.station or recipe.station == "hand" or recipe.station == "garage" then return true end
  return home.usable_station(state, recipe.station) ~= nil
end

-- Build the effective material list, including per-room amounts for insulation.
local function material_list(state, recipe, cid, room)
  local out = {}
  local b = bonus_of(recipe, cid)
  local mult = b.cost or 1.0
  for id, n in pairs(recipe.inputs or {}) do
    local m = mult
    if (id == "clean_water" or id == "snow_water") and b.water then m = m * b.water end
    out[#out + 1] = { item = id, n = adjusted(n, m) }
  end
  for _, entry in ipairs(recipe.input_any or {}) do
    if type(entry) == "table" and entry.tag then
      out[#out + 1] = { tag = entry.tag, n = adjusted(entry.n, mult) }
    else
      out[#out + 1] = { any = entry, n = adjusted(entry.n or 1, mult) }
    end
  end
  if recipe.per_cell and room then
    local cells = state.home.rooms[room] and state.home.rooms[room].area or 0
    for id, per in pairs(recipe.per_cell) do
      out[#out + 1] = { item = id, n = math.max(1, math.ceil(cells * per * mult - 0.0001)) }
    end
  end
  return out
end

local function have_material(state, ch, entry)
  if entry.item then
    return inventory.count(state.home.stash, entry.item) + inventory.count(ch.inv, entry.item) >= entry.n
  elseif entry.tag then
    return inventory.count_tag(state.home.stash, entry.tag) + inventory.count_tag(ch.inv, entry.tag) >= entry.n
  elseif entry.any then
    for _, id in ipairs(entry.any) do
      if inventory.count(state.home.stash, id) + inventory.count(ch.inv, id) >= entry.n then return true end
    end
    return false
  end
  return false
end

local function take_material(state, ch, entry)
  if entry.item then
    local left = entry.n
    local take = math.min(left, inventory.count(ch.inv, entry.item))
    if take > 0 then
      inventory.remove(ch.inv, entry.item, take)
      left = left - take
    end
    if left > 0 then
      if inventory.count(state.home.stash, entry.item) < left then return false end
      inventory.remove(state.home.stash, entry.item, left)
    end
    return true
  elseif entry.tag then
    local left = inventory.consume_tag_from(ch.inv, entry.tag, entry.n) or entry.n
    if left > 0 then
      local left2 = inventory.consume_tag_from(state.home.stash, entry.tag, left)
      left = left2 or left
    end
    return left == 0
  elseif entry.any then
    for _, id in ipairs(entry.any) do
      local total = inventory.count(state.home.stash, id) + inventory.count(ch.inv, id)
      if total >= entry.n then
        local left = entry.n
        local take = math.min(left, inventory.count(ch.inv, id))
        if take > 0 then
          inventory.remove(ch.inv, id, take)
          left = left - take
        end
        if left > 0 then inventory.remove(state.home.stash, id, left) end
        return true
      end
    end
    return false
  end
  return false
end

local function fuel_ok(state, recipe)
  if not recipe.fuel then return true end
  for id, n in pairs(recipe.fuel) do
    local pool = (state.home.stash.fuel_frac and state.home.stash.fuel_frac[id]) or 0
    if inventory.count(state.home.stash, id) + pool < n then return false end
  end
  return true
end

function M.can(state, recipe_id, cid, opts)
  opts = opts or {}
  local recipe = recipes.get(recipe_id)
  if not recipe then return false, "unknown_recipe" end
  local ch = state.party.chars[cid]
  if not ch or ch.status ~= "alive" then return false, "no_char" end
  if ch.job then return false, "char_busy" end
  if recipe.tech and not state.tech.unlocked[recipe.tech] then return false, "missing_tech:" .. recipe.tech end
  if not station_ok(state, recipe) then return false, "missing_station:" .. tostring(recipe.station) end
  if recipe.tools_all then
    for _, id in ipairs(recipe.tools_all) do
      if not have_tool(state, ch, id) then return false, "missing_tool:" .. id end
    end
  end
  if recipe.tools_any then
    for _, group in ipairs(recipe.tools_any) do
      local found = false
      for _, id in ipairs(group) do
        if have_tool(state, ch, id) then found = true break end
      end
      if not found then return false, "missing_tool" end
    end
  end
  local room = opts.room or room_for(state, cid)
  for _, entry in ipairs(material_list(state, recipe, cid, room)) do
    if not have_material(state, ch, entry) then return false, "missing_material" end
  end
  if not fuel_ok(state, recipe) then return false, "missing_fuel" end
  if recipe.effect == "board_window" and not home.boardable_window(state, room) then return false, "no_window" end
  if recipe.effect == "board_hole" and not home.boardable_hole(state, room) then return false, "no_hole" end
  if recipe.effect == "insulate" then
    local r = state.home.rooms[room]
    if not r then return false, "bad_room" end
    if (r.insulation or 0) >= recipe.level then return false, "already_insulated" end
  end
  return true
end

function M.start(state, recipe_id, cid, opts)
  opts = opts or {}
  local ok, err = M.can(state, recipe_id, cid, opts)
  if not ok then return false, err end
  local recipe = recipes.get(recipe_id)
  local ch = state.party.chars[cid]
  local room = opts.room or room_for(state, cid)
  for _, entry in ipairs(material_list(state, recipe, cid, room)) do
    if not take_material(state, ch, entry) then return false, "missing_material" end
  end
  if recipe.fuel then
    local fuel_mult = bonus_of(recipe, cid).fuel or 1.0
    for id, n in pairs(recipe.fuel) do
      if not inventory.burn_fuel(state.home.stash, id, n * fuel_mult) then
        return false, "missing_fuel"
      end
    end
  end
  local work = recipe.minutes or 0
  local b = bonus_of(recipe, cid)
  if b.work then work = work * b.work end
  local speed = 1.0
  if recipe.station ~= "hand" and recipe.station ~= "garage" then
    speed = W.bench_speed[bench_level(state)] or 1.0
  end
  state.job_seq = (state.job_seq or 0) + 1
  local job = {
    id = "job_" .. state.job_seq,
    kind = recipe.kind or "craft",
    recipe = recipe_id,
    actor = cid,
    room = room,
    work_remaining = work,
    work_total = work,
    wait_remaining = recipe.wait or 0,
    speed = speed,
    waiting = (work <= 0),
  }
  state.jobs[job.id] = job
  if not job.waiting then
    ch.job = job.id
    ch.activity = "work"
  end
  state_mod.log(state, "craft_started", { recipe = recipe_id, char = cid })
  return true, job
end

function M.cancel(state, job_id)
  local job = state.jobs[job_id]
  if not job then return false, "no_job" end
  local ch = state.party.chars[job.actor]
  if ch and ch.job == job_id then
    ch.job = nil
    ch.activity = "idle"
  end
  state.jobs[job_id] = nil
  return true
end

local function clear_rubble_loot(state)
  local r = state.rng.loot
  local stash = state.home.stash
  local scrap = rng.int(r, 0, 2)
  if scrap > 0 then inventory.add(stash, "scrap", scrap, { force = true }) end
  if rng.float(r) < 0.40 then inventory.add(stash, "planks", 1, { force = true }) end
  if rng.float(r) < 0.20 then inventory.add(stash, "firewood", 1, { force = true }) end
  if rng.float(r) < 0.12 then
    local roll = rng.float(r)
    if roll < 0.60 then inventory.add(stash, "canned_beans", 1, { force = true })
    elseif roll < 0.85 then inventory.add(stash, "canned_soup", 1, { force = true })
    else inventory.add(stash, "wild_roots", 2, { force = true }) end
  end
  if rng.float(r) < 0.05 then
    local roll = rng.float(r)
    if roll < 0.34 then inventory.add(stash, "cloth", 1, { force = true })
    elseif roll < 0.67 then inventory.add(stash, "components", 1, { force = true })
    else inventory.add(stash, "bandage", 1, { force = true }) end
  end
end

local function apply_effect(state, job, recipe, ch)
  local effect = recipe.effect
  if not effect then return true end
  local room = job.room or room_for(state, ch.id)
  if effect == "hot_meal" then
    ch.hot_meal_minutes = balance.needs.heat_recovery_minutes
    return true
  elseif effect == "clear_rubble" then
    if state.home.rubble <= 0 then return false, "no_rubble" end
    state.home.rubble = state.home.rubble - 1
    clear_rubble_loot(state)
    return true
  elseif effect == "salvage_furniture" then
    return true
  elseif effect == "board_window" then
    return home.board_window(state, room)
  elseif effect == "board_hole" then
    return home.board_hole(state, room)
  elseif effect == "insulate" then
    return home.set_insulation(state, room, recipe.level)
  elseif effect == "add_station" then
    home.add_station(state, recipe.station_id, home.station_kind(recipe.station_id), nil, 100, false)
    state_mod.log(state, "station_built", { station = recipe.station_id })
    return true
  elseif effect == "add_room" then
    return home.add_cold_cell(state)
  elseif effect == "repair_station" then
    return home.repair_station(state, recipe.target)
  elseif effect == "fact" then
    state.story.facts[recipe.fact] = true
    return true
  elseif effect == "repair_tool" or effect == "repair_weapon" then
    return true
  elseif effect == "reinforce_door" or effect == "reinforce_window" then
    state_mod.log(state, "structure_reinforced", { kind = effect, level = recipe.level })
    return true
  end
  return true
end

local function finish(state, job)
  local recipe = recipes.get(job.recipe)
  local ch = state.party.chars[job.actor]
  local b = ch and bonus_of(recipe, job.actor) or {}
  local yield_bonus = b.yield or 0
  local first = true
  for id, n in pairs(recipe.outputs or {}) do
    local count = n
    if first and yield_bonus > 0 then count = count + yield_bonus end
    inventory.add(state.home.stash, id, count, { force = true })
    first = false
  end
  if ch then
    if ch.job == job.id then
      ch.job = nil
      ch.activity = "idle"
    end
    apply_effect(state, job, recipe, ch)
  end
  state.jobs[job.id] = nil
  state.stats.crafts = state.stats.crafts + 1
  state_mod.log(state, "craft_done", { recipe = job.recipe, char = job.actor })
end

function M.tick(state, minutes)
  for _, id in ipairs(util.sorted_keys(state.jobs)) do
    local job = state.jobs[id]
    if job and job.kind ~= "research" then
      local recipe = recipes.get(job.recipe)
      local ch = state.party.chars[job.actor]
      if not recipe then
        state.jobs[id] = nil
      elseif not job.waiting then
        if not ch or ch.status ~= "alive" then
          state.jobs[id] = nil
        else
          local eff = chars.efficiency(state, ch)
          job.work_remaining = job.work_remaining - minutes * math.max(0.05, eff) * (job.speed or 1.0)
          if job.work_remaining <= 0 then
            if job.wait_remaining and job.wait_remaining > 0 then
              job.waiting = true
              ch.job = nil
              ch.activity = "idle"
            else
              finish(state, job)
            end
          end
        end
      else
        job.wait_remaining = job.wait_remaining - minutes
        if job.wait_remaining <= 0 then finish(state, job) end
      end
    end
  end
end

function M.available(state, cid)
  local out = {}
  for id in pairs(recipes.recipes) do
    if M.can(state, id, cid) then out[#out + 1] = id end
  end
  table.sort(out)
  return out
end

return M
