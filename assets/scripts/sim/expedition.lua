-- PLACEHOLDER (M3): abstract night supply so the balance bot can run 30 days before
-- world generation / raids land in M5/M6. Replaced by sim/worldgen.lua +
-- sim/raid_autoresolve(); keep the signature expedition.night(state, squad, hours).
local balance = require("data.balance")
local items = require("data.items")
local inventory = require("sim.inventory")
local rng = require("core.rng")
local state_mod = require("sim.state")

local M = { PLACEHOLDER = true }

local TAGS = {
  food = { "food_any", "food_raw" },
  fuel = { "heat_fuel" },
  water = { "water_any" },
  parts = { "parts_any" },
  meds = { "med_any" },
  luxury = { "luxury_any" },
}

local candidates = {}
for cat, tags in pairs(TAGS) do
  local ids = {}
  for _, tag in ipairs(tags) do
    for _, id in ipairs(items.ids_with_tag(tag)) do
      local def = items.get(id)
      if def.cat ~= "blueprint" and def.cat ~= "quest" then
        ids[#ids + 1] = id
      end
    end
  end
  table.sort(ids)
  candidates[cat] = ids
end

local function buy(state, cat, budget, r)
  local ids = candidates[cat] or {}
  local spent = 0
  local guard = 0
  while budget - spent >= 1 and #ids > 0 and guard < 500 do
    guard = guard + 1
    local id = ids[rng.int(r, 1, #ids)]
    local def = items.get(id)
    if def.vp <= budget - spent then
      local n = 1
      if def.stack >= 4 and def.vp * 2 <= budget - spent and rng.float(r) < 0.35 then n = 2 end
      inventory.add(state.home.stash, id, n, { force = true })
      spent = spent + def.vp * n
    else
      local cheap
      for _, cid in ipairs(ids) do
        if items.get(cid).vp <= budget - spent then cheap = cid break end
      end
      if not cheap then break end
      inventory.add(state.home.stash, cheap, 1, { force = true })
      spent = spent + items.get(cheap).vp
    end
  end
  return spent
end

function M.night(state, squad, hours)
  local prev_reason = inventory.set_reason("expedition_loot")
  local result = M.night_inner(state, squad, hours)
  inventory.set_reason(prev_reason)
  return result
end

function M.night_inner(state, squad, hours)
  local cfg = balance.expedition
  hours = hours or cfg.hours
  squad = squad or {}
  local crew = 1 + 0.5 * math.max(0, #squad - 1)
  local budget = cfg.vp_per_hour * hours * crew
  local r = state.rng.loot
  local spent = 0
  local by_cat = {}
  for _, entry in ipairs(cfg.composition) do
    local cat, share = entry[1], entry[2]
    local got = 0
    for _, tag in ipairs(TAGS[cat] or {}) do
      got = got + buy(state, cat, budget * share, r)
      break -- first tag carries the category for M3
    end
    by_cat[cat] = got
    spent = spent + got
  end

  -- gasoline for the generator; the placeholder keeps the electric route viable
  local gas = inventory.count(state.home.stash, "gasoline")
  if gas < 2 then
    inventory.add(state.home.stash, "gasoline", 2 - gas, { force = true })
    spent = spent + (2 - gas) * items.get("gasoline").vp
  end

  local injured = {}
  local health = require("sim.health")
  for _, cid in ipairs(squad) do
    local ch = state.party.chars[cid]
    if ch and ch.status == "alive" then
      local cold = ch.wear.coat == nil and cfg.risk.cold_penalty or 0
      if rng.float(state.rng.combat) < cfg.risk.injury_chance + cold * 0.05 then
        local dmg = rng.int(state.rng.combat, cfg.risk.injury_damage[1], cfg.risk.injury_damage[2])
        health.add_wound(state, ch, dmg, "expedition")
        injured[#injured + 1] = cid
      end
      ch.needs.temp = math.max(0, ch.needs.temp - 12)
      ch.needs.energy = math.max(0, ch.needs.energy - 25)
    end
  end
  state.stats.expeditions = state.stats.expeditions + 1
  state.stats.expedition_vp = (state.stats.expedition_vp or 0) + spent
  state_mod.log(state, "expedition", { squad = squad, vp = spent, hours = hours })
  return { vp = spent, by_cat = by_cat, injured = injured, placeholder = true }
end

return M
