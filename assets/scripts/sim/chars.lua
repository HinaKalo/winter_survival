-- Characters: party draw, derived stats (wound / disease / efficiency), relations.
local rng = require("core.rng")
local util = require("core.util")
local cards = require("data.characters")
local balance = require("data.balance")
local inventory = require("sim.inventory")

local M = {}

local base = balance

local WOUND_RANK = { healthy = 4, light = 3, heavy = 2, critical = 1, dead = 0 }

function M.create(state, id)
  local card = cards.get(id)
  if not card then return nil, "unknown character " .. tostring(id) end
  local c = {
    id = id,
    name = card.name,
    role = card.role,
    values = util.deep_copy(card.values),
    capacity = card.capacity,
    speed = card.speed,
    traits = util.deep_copy(card.traits),
    needs = { food = 85, water = 85, energy = 75, temp = 100, mood = 70 },
    health = {
      hp = 100,
      infection = false,
      disease = {},
      bandage_hours = 0,
      heavy_bandage_hours = 0,
      stabilized_until = 0,
      painkiller_until = 0,
      hot_meal_until = 0,
      wet = 0,
    },
    activity = "idle",
    room = state.home and state.home.default_room or "living",
    inv = inventory.new(10, card.capacity),
    wear = { coat = "winter_coat", hat = "wool_hat", gloves = "wool_gloves", boots = "snow_boots" },
    job = nil,
    status = "alive",
    relations = {},
    hot_meal_minutes = 0,
    flags = {},
    death_day = nil,
    death_cause = nil,
  }
  for _, item in ipairs(card.start_items or {}) do
    inventory.add(c.inv, item, 1, { force = true })
  end
  return c
end

function M.setup_relations(state)
  for _, a in ipairs(state.party.order) do
    local ca = state.party.chars[a]
    local bias_a = cards.get(a).relation_bias or {}
    for _, b in ipairs(state.party.order) do
      if a ~= b then
        local cb = state.party.chars[b]
        local v = 0
        if bias_a[b] then v = bias_a[b]
        elseif (cards.get(b).relation_bias or {})[a] then v = -(cards.get(b).relation_bias)[a] end
        ca.relations[b] = v
        if cb and cb.relations[a] == nil then
          cb.relations[a] = -v
        end
      end
    end
  end
  -- "不被信任" (sam): everyone starts lower with this character.
  for _, a in ipairs(state.party.order) do
    local ca = state.party.chars[a]
    local start = ca.traits.relation_start
    if start then
      for _, b in ipairs(state.party.order) do
        if a ~= b then
          ca.relations[b] = (ca.relations[b] or 0) + start
        end
      end
    end
  end
end

-- Draw 4 survivors; guarantee at least one home-type and one field-type (GDD 1.4).
function M.draw(state, n)
  n = n or (state.opts and state.opts.party_size) or balance.limits.party_size
  local pool = {}
  for _, id in ipairs(cards.order) do pool[#pool + 1] = id end
  rng.shuffle(state.rng.story, pool)

  local function has(role)
    for _, id in ipairs(pool) do
      if cards.get(id).role == role then return id end
    end
    return nil
  end

  local picked = {}
  local used = {}
  local function take(id)
    if #picked >= n or used[id] then return false end
    used[id] = true
    picked[#picked + 1] = id
    return true
  end

  local home_id = has("home")
  local field_id = has("field")
  if home_id then take(home_id) end
  if field_id then take(field_id) end
  for _, id in ipairs(pool) do
    if #picked >= n then break end
    take(id)
  end
  -- order is draw order; keep it stable for serialization
  return picked
end

function M.get(state, id)
  return state.party.chars[id]
end

function M.alive(state)
  local out = {}
  for _, id in ipairs(state.party.order) do
    local c = state.party.chars[id]
    if c and c.status == "alive" then out[#out + 1] = c end
  end
  return out
end

function M.alive_ids(state)
  local out = {}
  for _, c in ipairs(M.alive(state)) do out[#out + 1] = c.id end
  return out
end

function M.wound(char)
  local hp = char.health.hp
  if hp <= 0 then return "dead" end
  if hp <= 10 then return "critical" end
  if hp <= 40 then return "heavy" end
  if hp <= 80 then return "light" end
  return "healthy"
end

function M.disease_eff(char)
  local worst = 1.0
  local n = 0
  for id in pairs(char.health.disease or {}) do
    n = n + 1
    local val = 1.0
    if id == "cold" then val = 0.85
    elseif id == "pneumonia" then val = 0.5
    elseif id == "frostbite" then val = 0.8
    elseif id == "food_poison" then val = 0.6 end
    if val < worst then worst = val end
  end
  if n > 1 then worst = worst * 0.9 end
  return worst
end

function M.morale_state(char)
  local m = char.needs.mood
  -- thresholds: 60 / 45 / 28 / 10 (CONTENT 6.4.4)
  if m >= 60 then return "stable" end
  if m >= 45 then return "shaken" end
  if m >= 28 then return "low" end
  if m >= 10 then return "depressed" end
  return "breakdown"
end

local MORALE_EFF = { stable = 1.0, shaken = 0.95, low = 0.8, depressed = 0.6, breakdown = 0.0 }

function M.energy_eff(energy)
  if energy >= 60 then return 1.0 end
  if energy >= 30 then return 0.8 + 0.2 * (energy - 30) / 30 end
  if energy >= 10 then return 0.5 + 0.3 * (energy - 10) / 20 end
  return 0.4
end

function M.temp_eff(temp)
  if temp >= 60 then return 1.0 end
  if temp >= 40 then return 0.9 end
  if temp >= 25 then return 0.7 end
  if temp >= 10 then return 0.5 end
  return 0.3
end

function M.food_eff(food)
  if food >= 30 then return 1.0 end
  if food >= 15 then return 0.9 end
  if food > 0 then return 0.8 end
  return 0.5
end

function M.water_eff(water)
  if water >= 30 then return 1.0 end
  if water >= 15 then return 0.9 end
  if water > 0 then return 0.7 end
  return 0.4
end

-- Final work multiplier (CONTENT 6.4.3). Bench speed is applied by sim/craft.
function M.efficiency(state, cid)
  local c = type(cid) == "table" and cid or state.party.chars[cid]
  if not c or c.status ~= "alive" then return 0 end
  local wound = 1.0
  local w = M.wound(c)
  if w == "light" then wound = 0.9
  elseif w == "heavy" then wound = 0.5
  elseif w == "critical" then wound = 0.0 end
  if c.health.painkiller_until and c.health.painkiller_until > 0 then
    wound = 1.0 - (1.0 - wound) * 0.5
  end
  local eff = wound
    * M.disease_eff(c)
    * MORALE_EFF[M.morale_state(c)]
    * M.energy_eff(c.needs.energy)
    * M.temp_eff(c.needs.temp)
    * math.min(M.food_eff(c.needs.food), M.water_eff(c.needs.water))
  if eff < 0 then eff = 0 end
  if eff > 1 then eff = 1 end
  return eff
end

function M.capacity(state, cid)
  local c = type(cid) == "table" and cid or state.party.chars[cid]
  local cap = c and c.capacity or 15
  for _, id in pairs((c and c.wear) or {}) do
    local def = require("data.items").get(id)
    if def and def.carry_kg then cap = cap + def.carry_kg end
  end
  return cap
end

function M.slots(state, cid)
  local c = type(cid) == "table" and cid or state.party.chars[cid]
  local slots = 10
  for _, id in pairs((c and c.wear) or {}) do
    local def = require("data.items").get(id)
    if def and def.carry_slots then slots = slots + def.carry_slots end
  end
  return slots
end

function M.speed(state, cid)
  local c = type(cid) == "table" and cid or state.party.chars[cid]
  local s = c.speed or 1.0
  local w = M.wound(c)
  if w == "light" then s = s * 0.9
  elseif w == "heavy" then s = s * 0.6
  elseif w == "critical" then s = 0 end
  if c.health.disease and c.health.disease.cold then s = s * 0.95 end
  if c.health.disease and c.health.disease.pneumonia then s = s * 0.8 end
  if c.health.disease and c.health.disease.frostbite then s = s * 0.85 end
  if c.health.disease and c.health.disease.food_poison then s = s * 0.9 end
  local cap = M.capacity(state, c)
  local wkg = inventory.weight(c.inv)
  if wkg > cap then
    local over = (wkg - cap) / math.max(cap, 1)
    local pen = math.min(0.5, 0.5 * over)
    if over >= 0.3 then return 0 end
    s = s * (1 - pen)
  end
  return s
end

function M.wear_bonus(c)
  local total = 0
  for _, id in pairs(c.wear or {}) do
    local def = require("data.items").get(id)
    if def and def.wear then total = total + def.wear end
  end
  return total
end

function M.body_heat(ch)
  if not ch then return 0 end
  if ch.activity == "sleep" then return balance.thermal.body_heat.sleep end
  if ch.activity == "work" then return balance.thermal.body_heat.work end
  return balance.thermal.body_heat.idle
end

function M.equip(state, ch, item_id)
  local def = require("data.items").get(item_id)
  if not def then return false, "unknown_item" end
  local slot
  if item_id == "winter_coat" or item_id == "winter_coat_2" then slot = "coat"
  elseif item_id == "wool_hat" then slot = "hat"
  elseif item_id == "wool_gloves" then slot = "gloves"
  elseif item_id == "snow_boots" then slot = "boots"
  elseif def.carry_kg then slot = "pack"
  elseif def.sleep_warmth then slot = "blanket"
  else return false, "not_wearable" end
  local bag = ch.inv
  if inventory.count(ch.inv, item_id) <= 0 then bag = state.home.stash end
  if inventory.count(bag, item_id) <= 0 then return false, "missing" end
  if ch.wear[slot] then
    inventory.add(state.home.stash, ch.wear[slot], 1, { force = true })
  end
  inventory.remove(bag, item_id, 1)
  ch.wear[slot] = item_id
  return true
end

function M.unequip(state, ch, slot)
  local old = ch.wear[slot]
  if not old then return false, "empty" end
  ch.wear[slot] = nil
  inventory.add(state.home.stash, old, 1, { force = true })
  return true
end

function M.body_heat(ch)
  if not ch then return 0 end
  if ch.activity == "sleep" then return balance.thermal.body_heat.sleep end
  if ch.activity == "work" then return balance.thermal.body_heat.work end
  return balance.thermal.body_heat.idle
end

function M.relation(state, a, b)
  local ca = state.party.chars[a]
  return ca and ca.relations[b] or 0
end

function M.add_relation(state, a, b, delta)
  local ca = state.party.chars[a]
  local cb = state.party.chars[b]
  if not ca or not cb then return end
  ca.relations[b] = math.max(-100, math.min(100, (ca.relations[b] or 0) + delta))
  cb.relations[a] = math.max(-100, math.min(100, (cb.relations[a] or 0) + delta))
end

function M.kill(state, cid, cause)
  local c = state.party.chars[cid]
  if not c or c.status == "dead" then return end
  c.status = "dead"
  c.health.hp = 0
  c.death_day = state.clock.day
  c.death_cause = cause or "unknown"
  state.stats.deaths = (state.stats.deaths or 0) + 1
  state.party.chars[cid] = c
  local order = state.party.order
  for i = #order, 1, -1 do
    if order[i] == cid then table.remove(order, i) end
  end
  local st = require("sim.state")
  st.log(state, "char_died", { char = cid, cause = cause or "unknown" })
end

return M
