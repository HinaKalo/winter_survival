-- Characters: party draw, derived stats (wound / disease / efficiency), relations.
local rng = require("core.rng")
local util = require("core.util")
local cards = require("data.characters")
local balance = require("data.balance")
local inventory = require("sim.inventory")

local M = {}

local C = balance.chars
local H = balance.health

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
    wear = {},
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
  -- opening worn gear belongs to the starting kit (the only place worn items appear
  -- from nothing); afterwards equip/unequip only move items between bags and wear.
  for _, slot in ipairs(util.sorted_keys(C.start_wear)) do
    c.wear[slot] = C.start_wear[slot]
  end
  M.sync_inv(c)
  return c
end

-- Carry capacity (kg) and slots of the bag without wound multipliers: base + worn packs.
function M.sync_inv(c)
  local items = require("data.items")
  local cap = c.capacity or C.default_capacity
  local slots = C.default_slots
  for _, slot in ipairs(util.sorted_keys(c.wear or {})) do
    local def = items.get(c.wear[slot])
    if def and def.carry_kg then cap = cap + def.carry_kg end
    if def and def.carry_slots then slots = slots + def.carry_slots end
  end
  c.inv.kg_cap = cap
  c.inv.slots = slots
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
  if hp < H.heavy then return "critical" end
  if hp < H.light then return "heavy" end
  if hp <= H.healthy then return "light" end
  return "healthy"
end

-- Disease efficiency multipliers (each disease's own value), sorted by id.
local function disease_values(char, field)
  local out = {}
  for _, id in ipairs(util.sorted_keys(char.health.disease or {})) do
    local spec = H[id]
    out[#out + 1] = (spec and spec[field]) or 1.0
  end
  return out
end

-- Wound + disease penalty (CONTENT 6.4.3, PLAN 9.1): one penalty -> its value; several ->
-- min * multi_penalty. Painkillers halve each penalty (a dying character stays at 0).
function M.injury_eff(char)
  local w = M.wound(char)
  local pk = char.health.painkiller_until and char.health.painkiller_until > 0
  local function soften(x)
    if pk and x > 0 then return 1.0 - (1.0 - x) * C.painkiller_halving end
    return x
  end
  local vals = {}
  if w ~= "healthy" and w ~= "dead" then vals[#vals + 1] = soften(C.wound_eff[w]) end
  for _, v in ipairs(disease_values(char, "eff")) do vals[#vals + 1] = soften(v) end
  if #vals == 0 then return 1.0 end
  local m = vals[1]
  for i = 2, #vals do if vals[i] < m then m = vals[i] end end
  if #vals > 1 then m = m * C.multi_penalty end
  return m
end

-- Kept for callers that only want the disease part.
function M.disease_eff(char)
  local vals = disease_values(char, "eff")
  if #vals == 0 then return 1.0 end
  local m = vals[1]
  for i = 2, #vals do if vals[i] < m then m = vals[i] end end
  if #vals > 1 then m = m * C.multi_penalty end
  return m
end

function M.morale_state(char)
  local m = char.needs.mood
  local b = C.morale_bands
  if m >= b.stable then return "stable" end
  if m >= b.shaken then return "shaken" end
  if m >= b.low then return "low" end
  if m >= b.depressed then return "depressed" end
  return "breakdown"
end

-- Linear interpolation between the CONTENT 6.1 points; below the last point: exhausted.
function M.energy_eff(energy)
  local E = balance.needs.eff.energy
  local pts = E.points
  if energy >= pts[1][1] then return pts[1][2] end
  for i = 1, #pts - 1 do
    local hi, lo = pts[i], pts[i + 1]
    if energy >= lo[1] then
      return lo[2] + (hi[2] - lo[2]) * (energy - lo[1]) / (hi[1] - lo[1])
    end
  end
  return E.exhausted
end

function M.temp_eff(temp)
  for _, band in ipairs(C.temp_eff) do
    if temp >= band[1] then return band[2] end
  end
  return C.temp_eff[#C.temp_eff][2]
end

local function band_eff(spec, v)
  if v <= 0 then return spec.zero end
  local m = 1.0
  for _, band in ipairs(spec.bands) do
    if v < band.below then m = band.mult end
  end
  return m
end

function M.food_eff(food) return band_eff(balance.needs.eff.food, food) end
function M.water_eff(water) return band_eff(balance.needs.eff.water, water) end

-- Final work multiplier (CONTENT 6.4.3). Bench speed is applied by sim/craft.
function M.efficiency(state, cid)
  local c = type(cid) == "table" and cid or state.party.chars[cid]
  if not c or c.status ~= "alive" then return 0 end
  local eff = M.injury_eff(c)
    * C.morale_eff[M.morale_state(c)]
    * M.energy_eff(c.needs.energy)
    * M.temp_eff(c.needs.temp)
    * math.min(M.food_eff(c.needs.food), M.water_eff(c.needs.water))
  if eff < 0 then eff = 0 end
  if eff > 1 then eff = 1 end
  return eff
end

-- Carry capacity in kg: base + worn packs, times wound / pneumonia multipliers.
function M.capacity(state, cid)
  local c = type(cid) == "table" and cid or state.party.chars[cid]
  local items = require("data.items")
  local cap = c and c.capacity or C.default_capacity
  for _, slot in ipairs(util.sorted_keys((c and c.wear) or {})) do
    local def = items.get(c.wear[slot])
    if def and def.carry_kg then cap = cap + def.carry_kg end
  end
  if c then
    local w = M.wound(c)
    if C.wound_capacity[w] then cap = cap * C.wound_capacity[w] end
    if c.health.disease and c.health.disease.pneumonia then cap = cap * H.pneumonia.capacity end
  end
  return cap
end

function M.slots(state, cid)
  local c = type(cid) == "table" and cid or state.party.chars[cid]
  local slots = C.default_slots
  for _, slot in ipairs(util.sorted_keys((c and c.wear) or {})) do
    local def = require("data.items").get(c.wear[slot])
    if def and def.carry_slots then slots = slots + def.carry_slots end
  end
  return slots
end

function M.speed(state, cid)
  local c = type(cid) == "table" and cid or state.party.chars[cid]
  local s = c.speed or 1.0
  local w = M.wound(c)
  if C.wound_speed[w] then s = s * C.wound_speed[w] end
  for _, v in ipairs(disease_values(c, "speed")) do s = s * v end
  local cap = M.capacity(state, c)
  local wkg = inventory.weight(c.inv)
  if wkg > cap then
    local over = (wkg - cap) / math.max(cap, 1)
    if over >= C.overweight.stop_ratio then return 0 end
    s = s * (1 - math.min(C.overweight.pen_cap, C.overweight.pen_per_ratio * over))
  end
  return s
end

function M.wear_bonus(c)
  local total = 0
  for _, slot in ipairs(util.sorted_keys(c.wear or {})) do
    local def = require("data.items").get(c.wear[slot])
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
  M.sync_inv(ch)
  return true
end

function M.unequip(state, ch, slot)
  local old = ch.wear[slot]
  if not old then return false, "empty" end
  ch.wear[slot] = nil
  inventory.add(state.home.stash, old, 1, { force = true })
  M.sync_inv(ch)
  return true
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
  c.dead = true
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
