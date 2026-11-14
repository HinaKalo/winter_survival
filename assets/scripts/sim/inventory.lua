-- Inventory: deterministic, serializable. Entries are keyed by item id.
-- bag = { items = { [id] = { count, spoil_left?, spoiled? } }, slots, kg_cap, fuel_frac = {} }
local util = require("core.util")
local items = require("data.items")

local M = {}

-- Flow ledger (PLAN 9.3): every successful add/remove is booked on the bag itself as
-- bag.flow = { src = { [reason] = { [id] = n } }, snk = { ... } }, so count == sum(src) - sum(snk)
-- per bag. The reason is opts.reason / the explicit argument, else the ambient reason set by the
-- driver (sim tick / command dispatcher), else "other". It is a label only: no state lives here.
M.reason = nil

-- Sets the ambient reason; returns the previous one so callers can restore it.
function M.set_reason(reason)
  local prev = M.reason
  M.reason = reason
  return prev
end

local function book(bag, side, reason, id, n)
  local flow = bag.flow
  if not flow then
    flow = { src = {}, snk = {} }
    bag.flow = flow
  end
  reason = reason or M.reason or "other"
  local by = flow[side][reason]
  if not by then
    by = {}
    flow[side][reason] = by
  end
  by[id] = (by[id] or 0) + n
end

function M.new(slots, kg_cap)
  return { items = {}, slots = slots or 10, kg_cap = kg_cap or 15, fuel_frac = {} }
end

function M.entry(bag, id)
  return bag.items[id]
end

function M.count(bag, id)
  local e = bag.items[id]
  return e and e.count or 0
end

function M.slots_used(bag)
  local used = 0
  for _, id in ipairs(util.sorted_keys(bag.items)) do
    local e = bag.items[id]
    local def = items.get(id)
    local stack = def and def.stack or 1
    if e.count > 0 then
      used = used + math.ceil(e.count / stack)
    end
  end
  return used
end

function M.weight(bag)
  local kg = 0
  for _, id in ipairs(util.sorted_keys(bag.items)) do
    local e = bag.items[id]
    local def = items.get(id)
    if def and e.count > 0 then
      kg = kg + def.kg * e.count
    end
  end
  return kg
end

function M.value(bag)
  local vp = 0
  for _, id in ipairs(util.sorted_keys(bag.items)) do
    local e = bag.items[id]
    local def = items.get(id)
    if def and e.count > 0 then
      vp = vp + def.vp * e.count
    end
  end
  return vp
end

local function fits(bag, id, n)
  local def = items.get(id)
  if not def then return false, "unknown_item" end
  if bag.slots then
    local extra_slots = 0
    local e = bag.items[id]
    local stack = def.stack or 1
    local before = e and e.count or 0
    local after = before + n
    local used_before = math.ceil(before / stack)
    local used_after = math.ceil(after / stack)
    extra_slots = used_after - used_before
    if extra_slots > 0 and M.slots_used(bag) + extra_slots > bag.slots then
      return false, "slots"
    end
  end
  if bag.kg_cap then
    local w = M.weight(bag) + def.kg * n
    if w > bag.kg_cap + 0.0001 then return false, "weight" end
  end
  return true
end

function M.add(bag, id, n, opts)
  opts = opts or {}
  n = n or 1
  if n <= 0 then return true end
  local def = items.get(id)
  if not def then return false, "unknown_item" end
  if not opts.force then
    local ok, err = fits(bag, id, n)
    if not ok then return false, err end
  end
  local e = bag.items[id]
  if not e then
    e = { count = 0 }
    bag.items[id] = e
  end
  e.count = e.count + n
  if opts.spoil_left then
    if e.spoil_left == nil or opts.spoil_left < e.spoil_left then
      e.spoil_left = opts.spoil_left
    end
  elseif def.spoil_h and e.spoil_left == nil then
    e.spoil_left = def.spoil_h
  end
  if opts.spoiled then e.spoiled = true end
  book(bag, "src", opts.reason, id, n)
  return true
end

function M.remove(bag, id, n, reason)
  n = n or 1
  local e = bag.items[id]
  if not e or e.count < n then return false, "missing" end
  e.count = e.count - n
  if e.count <= 0 then bag.items[id] = nil end
  if n > 0 then book(bag, "snk", reason, id, n) end
  return true
end

function M.has(bag, id, n)
  return M.count(bag, id) >= (n or 1)
end

function M.count_tag(bag, tag)
  local total = 0
  for id, e in pairs(bag.items) do
    if e.count > 0 and items.has_tag(id, tag) then
      total = total + e.count
    end
  end
  return total
end

-- Team total: home stash + every character's bag + equipped wear is not counted.
function M.team_count(state, tag)
  local total = M.count_tag(state.home.stash, tag)
  for _, cid in ipairs(state.party.order) do
    local c = state.party.chars[cid]
    if c and c.inv and c.status ~= "dead" then
      total = total + M.count_tag(c.inv, tag)
    end
  end
  return total
end

function M.team_has(state, tag, n)
  return M.team_count(state, tag) >= (n or 1)
end

-- Consume n items with `tag`: stash first, then characters' bags in party order.
-- All or nothing: returns false, "missing" (and consumes nothing) when the team
-- does not hold n; otherwise returns true, 0.
function M.consume_tag(state, tag, n)
  n = n or 1
  if M.team_count(state, tag) < n then return false, "missing" end
  local left = n
  local got = M.consume_tag_from(state.home.stash, tag, left)
  if got then left = got end
  for _, cid in ipairs(state.party.order) do
    if left <= 0 then break end
    local c = state.party.chars[cid]
    if c and c.inv and c.status ~= "dead" then
      got = M.consume_tag_from(c.inv, tag, left)
      if got then left = got end
    end
  end
  if left > 0 then return false, "missing" end
  return true, 0
end

-- Returns the number still missing after consuming up to n (0 = fully served), or
-- nil, "missing" when the bag holds nothing with the tag.
function M.consume_tag_from(bag, tag, n, reason)
  local candidates = {}
  for _, id in ipairs(util.sorted_keys(bag.items)) do
    local e = bag.items[id]
    if e.count > 0 and items.has_tag(id, tag) then
      local def = items.get(id)
      candidates[#candidates + 1] = { id = id, e = e, def = def }
    end
  end
  -- lowest VP first; spoiled first
  table.sort(candidates, function(a, b)
    local as = a.e.spoiled and 1 or 0
    local bs = b.e.spoiled and 1 or 0
    if as ~= bs then return as > bs end
    if a.def.vp ~= b.def.vp then return a.def.vp < b.def.vp end
    return a.id < b.id
  end)
  local left = n
  local taken = 0
  for _, c in ipairs(candidates) do
    local take = math.min(left, c.e.count)
    if take > 0 then
      M.remove(bag, c.id, take, reason)
      left = left - take
      taken = taken + take
      if left == 0 then break end
    end
  end
  if taken == 0 then return nil, "missing" end
  return left
end

-- Fractional fuel accounting: fuel burns into the bag's pool; whole items leave the stock once the
-- pool crosses 1. fuel_cost is THE rule (whole items to remove, new pool) shared by the prechecks
-- and the real burn: whole = floor(pool + amount).
function M.fuel_cost(bag, item_id, amount)
  local pool = ((bag.fuel_frac and bag.fuel_frac[item_id]) or 0) + amount
  local whole = math.floor(pool)
  return whole, pool - whole
end

function M.can_burn(bag, item_id, amount)
  local whole = M.fuel_cost(bag, item_id, amount)
  return M.count(bag, item_id) >= whole
end

-- Validates first: when the stock cannot cover the whole items nothing changes (not even the pool).
function M.burn_fuel(bag, item_id, amount, reason)
  bag.fuel_frac = bag.fuel_frac or {}
  local whole, rest = M.fuel_cost(bag, item_id, amount)
  if M.count(bag, item_id) < whole then return false, "missing_fuel" end
  if whole > 0 then M.remove(bag, item_id, whole, reason or "fuel_burn") end
  bag.fuel_frac[item_id] = rest
  return true
end

function M.spoil_tick(bag, hours, ambient_temp)
  if hours <= 0 or (ambient_temp or -15) <= 5 then return end
  for _, id in ipairs(util.sorted_keys(bag.items)) do
    local e = bag.items[id]
    local def = items.get(id)
    if def and def.spoil_h and e.count > 0 and not e.spoiled then
      e.spoil_left = (e.spoil_left or def.spoil_h) - hours
      if e.spoil_left <= 0 then
        e.spoiled = true
        e.spoil_left = 0
      end
    end
  end
end

function M.move(from, to, id, n)
  n = n or M.count(from, id)
  if M.count(from, id) < n then return false, "missing" end
  local e = from.items[id]
  local spoil_left = e and e.spoil_left
  local spoiled = e and e.spoiled
  if not M.add(to, id, n, { spoil_left = spoil_left, spoiled = spoiled, reason = "transfer" }) then
    return false, "no_space"
  end
  M.remove(from, id, n, "transfer")
  return true
end

function M.validate(bag, where)
  if type(bag) ~= "table" or type(bag.items) ~= "table" then
    return false, (where or "bag") .. ": missing items"
  end
  for id, e in pairs(bag.items) do
    if not items.get(id) then return false, (where or "bag") .. ": unknown item " .. tostring(id) end
    if type(e.count) ~= "number" or e.count ~= e.count or e.count < 0 then
      return false, (where or "bag") .. ": bad count for " .. id
    end
    if e.count == 0 then return false, (where or "bag") .. ": zero entry " .. id end
    if e.count ~= math.floor(e.count) or e.count == math.huge then
      return false, (where or "bag") .. ": non-integer count for " .. id
    end
  end
  if bag.flow ~= nil then
    if type(bag.flow) ~= "table" or type(bag.flow.src) ~= "table" or type(bag.flow.snk) ~= "table" then
      return false, (where or "bag") .. ": bad flow"
    end
    for _, side in ipairs({ "src", "snk" }) do
      for reason, by in pairs(bag.flow[side]) do
        if type(reason) ~= "string" or type(by) ~= "table" then
          return false, (where or "bag") .. ": bad flow." .. side
        end
        for id, n in pairs(by) do
          if not items.get(id) or type(n) ~= "number" or n ~= n or n < 0 or n ~= math.floor(n) then
            return false, (where or "bag") .. ": bad flow entry " .. tostring(id)
          end
        end
      end
    end
  end
  return true
end

return M
