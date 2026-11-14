-- Needs: hunger, thirst, energy, body temperature, and mood (a light M3 model;
-- the full pressure-entry psyche system arrives in M8).
local balance = require("data.balance")
local items = require("data.items")
local inventory = require("sim.inventory")
local util = require("core.util")
local chars = require("sim.chars")
local clock = require("sim.clock")

local M = {}

local N = balance.needs

local function rate(table_, activity)
  return table_[activity] or table_.idle
end

local function clamp100(v)
  if v < 0 then return 0 end
  if v > 100 then return 100 end
  return v
end

function M.room_temp(state, ch)
  local thermal = require("sim.thermal")
  return thermal.room_temp(state, ch.room)
end

-- Feed one item to a character. Item is taken from the character bag, then the stash.
function M.consume_item(state, ch, item_id)
  local def = items.get(item_id)
  if not def then return false, "unknown_item" end
  local source = ch.inv
  local e = inventory.entry(source, item_id)
  if not e or e.count <= 0 then
    source = state.home.stash
    e = inventory.entry(source, item_id)
  end
  if not e or e.count <= 0 then return false, "missing" end
  local spoiled = e.spoiled
  inventory.remove(source, item_id, 1)
  local use = def.use or {}
  ch.needs.food = clamp100(ch.needs.food + (use.food or 0))
  ch.needs.water = clamp100(ch.needs.water + (use.water or 0))
  ch.needs.energy = clamp100(ch.needs.energy + (use.energy or 0))
  ch.needs.mood = clamp100(ch.needs.mood + (use.morale or 0))
  if use.food and use.food > 0 then state.stats.meals = state.stats.meals + 1 end
  if use.water then state.stats.drinks = state.stats.drinks + 1 end
  if use.hot then
    ch.hot_meal_minutes = balance.needs.heat_recovery_minutes
  end
  local poison = def.poison or 0
  if spoiled then poison = math.max(poison, balance.health.poison_chance.spoiled) end
  if use.alcohol then
    ch.flags = ch.flags or {}
    ch.flags.alcohol_minutes = 120
  end
  if poison > 0 then
    local r = state.rng.combat
    if require("core.rng").float(r) < poison then
      require("sim.health").add_disease(state, ch, "food_poison")
    end
  end
  return true
end

function M.eat(state, ch, item_id)
  if ch.status ~= "alive" then return false, "dead" end
  item_id = item_id or M.pick_food(state, ch)
  if not item_id then return false, "no_food" end
  local def = items.get(item_id)
  if not def or not items.has_tag(item_id, "food_any") and not items.has_tag(item_id, "food_raw")
    and not (def.use and def.use.food) then
    return false, "not_food"
  end
  return M.consume_item(state, ch, item_id)
end

function M.drink(state, ch, item_id)
  if ch.status ~= "alive" then return false, "dead" end
  item_id = item_id or M.pick_water(state, ch)
  if not item_id then return false, "no_water" end
  local def = items.get(item_id)
  if not def or not (items.has_tag(item_id, "water_any") or (def.use and def.use.water)) then
    return false, "not_drink"
  end
  return M.consume_item(state, ch, item_id)
end

-- Prefer the highest satiety per kg; spoiled food is only picked when nothing else is left.
function M.pick_food(state, ch)
  local function search(bag)
    local best, best_score
    for id, e in pairs(bag.items) do
      local def = items.get(id)
      if def and e.count > 0 and def.use and (def.use.food or 0) > 0
        and (items.has_tag(id, "food_any") or items.has_tag(id, "food_raw") or def.use.food > 0) then
        local score = def.use.food / math.max(0.01, def.kg)
        if e.spoiled then score = score * 0.2 end
        if items.has_tag(id, "cooked_meal") then score = score * 1.2 end
        if not best or score > best_score or (score == best_score and id < best) then
          best, best_score = id, score
        end
      end
    end
    return best
  end
  local id = search(ch.inv)
  if id then return id end
  return search(state.home.stash)
end

function M.pick_water(state, ch)
  local function search(bag)
    local best, best_vp
    for id, e in pairs(bag.items) do
      local def = items.get(id)
      if def and e.count > 0 and def.use and (def.use.water or 0) > 0 then
        if not best or def.vp > best_vp or (def.vp == best_vp and id < best) then
          best, best_vp = id, def.vp
        end
      end
    end
    return best
  end
  local id = search(ch.inv)
  if id then return id end
  return search(state.home.stash)
end

-- One-minute needs tick for every living character.
function M.tick(state, minutes)
  minutes = minutes or 1
  local hours = minutes / 60
  local home = state.home
  local thermal = require("sim.thermal")
  local health = require("sim.health")
  for _, ch in ipairs(chars.alive(state)) do
    local act = ch.activity or "idle"
    local food_rate = act == "guard" and N.food.idle or rate(N.food, act)
    local water_rate = act == "guard" and N.water.idle or rate(N.water, act)
    ch.needs.food = clamp100(ch.needs.food + food_rate * hours)
    ch.needs.water = clamp100(ch.needs.water + water_rate * hours)

    if act == "sleep" then
      local room_t = thermal.room_temp(state, ch.room)
      local gain = N.sleep_energy.normal
      if room_t >= 10 then gain = N.sleep_energy.warm
      elseif room_t < 5 then gain = N.sleep_energy.cold end
      if state.home.humidity < balance.humidity.dry_sleep then gain = gain * N.dry_sleep_mult end
      ch.needs.energy = clamp100(ch.needs.energy + gain * hours)
    elseif act == "guard" then
      ch.needs.energy = clamp100(ch.needs.energy + N.guard_energy * hours)
    else
      ch.needs.energy = clamp100(ch.needs.energy + rate(N.energy, act) * hours)
    end

    -- food poisoning drains extra food/water
    local fp = ch.health.diseases and ch.health.diseases.food_poison
    if fp then
      ch.needs.food = clamp100(ch.needs.food + balance.health.food_poison.extra_food_per_hour * hours)
      ch.needs.water = clamp100(ch.needs.water + balance.health.food_poison.extra_water_per_hour * hours)
    end

    -- body temperature
    local E = thermal.effective_temp(state, ch)
    local d
    if E >= balance.thermal.body_temp.warm then
      d = balance.thermal.body_temp.warm_rate
    elseif E >= balance.thermal.body_temp.mild then
      d = balance.thermal.body_temp.mild_rate
    else
      d = balance.thermal.body_temp.cold_rate * (balance.thermal.body_temp.mild - E)
    end
    if d < 0 and ch.traits.cold_rate and ch.traits.cold_rate > 1 then
      d = d * ch.traits.cold_rate
    end
    ch.needs.temp = util.clamp(ch.needs.temp + d * hours, 0, 100)

    -- mood: needs-based entries only (M8 takes over with entries and caps)
    local mood_d = 0
    local room_t = thermal.room_temp(state, ch.room)
    if room_t < 8 then mood_d = mood_d - 0.8 end
    if room_t >= 16 then mood_d = mood_d + 0.5 end
    if ch.needs.food < N.food_hungry then mood_d = mood_d - 0.5 end
    if ch.needs.temp < balance.thermal.bands.cold then mood_d = mood_d - 0.4 end
    if ch.hot_meal_minutes > 0 then
      ch.hot_meal_minutes = math.max(0, ch.hot_meal_minutes - minutes)
    end
    if ch.flags then
      if ch.flags.alcohol_minutes and ch.flags.alcohol_minutes > 0 then
        ch.flags.alcohol_minutes = math.max(0, ch.flags.alcohol_minutes - minutes)
      end
    end
    ch.needs.mood = clamp100(ch.needs.mood + mood_d * hours)

    -- starvation / dehydration timers (CONTENT 6.1)
    if ch.needs.food <= 0 then
      ch.health.starve_hours = (ch.health.starve_hours or 0) + hours
      while ch.health.starve_hours >= 24 do
        ch.health.starve_hours = ch.health.starve_hours - 24
        health.add_wound(state, ch, N.food_zero_hp_per_24h, "starvation")
      end
      if (ch.health.starve_total or 0) + hours >= N.food_zero_critical_hours then
        ch.health.critical_cause = "starvation"
      end
      ch.health.starve_total = (ch.health.starve_total or 0) + hours
    else
      ch.health.starve_hours = 0
      ch.health.starve_total = 0
    end
    if ch.needs.water <= 0 then
      ch.health.thirst_hours = (ch.health.thirst_hours or 0) + hours
      while ch.health.thirst_hours >= 12 do
        ch.health.thirst_hours = ch.health.thirst_hours - 12
        health.add_wound(state, ch, N.water_zero_hp_per_12h, "dehydration")
      end
      if (ch.health.thirst_total or 0) + hours >= N.water_zero_critical_hours then
        ch.health.critical_cause = "dehydration"
      end
      ch.health.thirst_total = (ch.health.thirst_total or 0) + hours
    else
      ch.health.thirst_hours = 0
      ch.health.thirst_total = 0
    end
  end
end

function M.sleep(state, ch)
  if ch.status ~= "alive" then return false, "dead" end
  ch.activity = "sleep"
  return true
end

function M.wake(state, ch)
  if ch.status ~= "alive" then return false, "dead" end
  if ch.activity == "sleep" then ch.activity = "idle" end
  return true
end

return M
