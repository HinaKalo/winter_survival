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

  -- Everything created here is the starting kit (ledger source "start"): character items, worn
  -- gear (CONTENT 10.2: character-owned, outside the budget), stash and the optional bot kit.
  local prev_reason = inventory.set_reason("start")
  local party = chars.draw(state, state.opts.party_size)
  for _, id in ipairs(party) do
    local ch = chars.create(state, id)
    state.party.chars[id] = ch
  end
  state.party.order = party
  chars.setup_relations(state)
  for _, id in ipairs(util.sorted_keys(state.party.chars)) do
    for _, slot in ipairs(util.sorted_keys(state.party.chars[id].wear)) do
      local item = state.party.chars[id].wear[slot]
      state.ledger.wear_start[item] = (state.ledger.wear_start[item] or 0) + 1
    end
  end

  for _, id in ipairs(util.sorted_keys(balance.start_stash)) do
    inventory.add(state.home.stash, id, balance.start_stash[id], { force = true })
  end

  -- Optional reference kit (PLAN 9.1): given once at creation, never by the bot afterwards.
  if opts.kit ~= nil then
    if opts.kit ~= "bot" or not balance.bot_kit then
      inventory.set_reason(prev_reason)
      return nil, "unknown_kit"
    end
    local kit = balance.bot_kit
    for _, id in ipairs(util.sorted_keys(kit.items or {})) do
      inventory.add(state.home.stash, id, kit.items[id], { force = true })
    end
    for _, id in ipairs(util.sorted_keys(kit.blueprints or {})) do
      state.tech.blueprints[id] = true
    end
    state.opts.kit = "bot"
  end
  inventory.set_reason(prev_reason)

  -- opening state: the stove works, everything else is damaged (CONTENT C4)
  state.tech.unlocked.t_hearth = true
  for _, id in ipairs(util.sorted_keys(balance.start_blueprints or {})) do
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
  for _, id in ipairs(util.sorted_keys(state.home.stash.items)) do
    local e = state.home.stash.items[id]
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
  for _, id in ipairs(util.sorted_keys(state.home.stash.items)) do
    local e = state.home.stash.items[id]
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
    -- Night roles end; anyone holding a job goes back to work (jobs were only paused).
    for _, ch in ipairs(chars.alive(state)) do
      if ch.activity == "out" or ch.activity == "guard" then
        ch.activity = ch.job and "work" or "idle"
      end
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
    local prev = inventory.set_reason("power")
    power.tick(state, dt)
    inventory.set_reason("thermal")
    thermal.tick(state, dt)
    inventory.set_reason("home")
    home.tick(state, dt)
    inventory.set_reason("craft_tick")
    craft.tick(state, dt)
    inventory.set_reason("tech_tick")
    tech.tick(state, dt)
    inventory.set_reason("needs")
    needs.tick(state, dt)
    inventory.set_reason("health")
    health.tick(state, dt)
    inventory.set_reason(prev)
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

-- Player-visible "end the work day": steps minute by minute to dusk (19:00). Jobs are never
-- cancelled; they just keep running until the phase boundary pauses them.
function M.end_day(state)
  if state.clock.phase ~= "day" then return false, "not_day" end
  while state.clock.phase == "day" do
    if not M.tick_minute(state) then break end
  end
  state_mod.log(state, "day_ended", { minute = state.clock.minute })
  return true
end

function M.command(state, cmd)
  if type(cmd) == "table" and cmd.kind == "end_day" then
    local ok, err = M.end_day(state)
    if not ok then state_mod.log(state, "command_failed", { kind = "end_day", err = err }) end
    return ok, err
  end
  return commands.run(state, cmd)
end

local function nan_scan(v, stack, out, seen)
  if type(v) == "number" then
    if v ~= v or v == math.huge or v == -math.huge then
      out[#out + 1] = "non-finite number at " .. table.concat(stack, ".")
    end
  elseif type(v) == "table" and not seen[v] then
    seen[v] = true
    local n = #stack
    for k, x in pairs(v) do
      stack[n + 1] = tostring(k)
      nan_scan(x, stack, out, seen)
    end
    stack[n + 1] = nil
  end
end

-- Reasons that only move items between a bag and the worn slots (chars.equip / unequip).
local WEAR_TRANSFER = { equip = true, unequip = true }
-- Reasons that only move items between two bags; they must net to zero per item.
local BAG_TRANSFER = { transfer = true }

-- Inventory conservation ledger over stash + every character bag (living or dead) + wear.
-- Returns { held = {id=n}, src = {reason={id=n}}, snk = {...}, problems = {...} }.
--   * per bag: count == sum(src) - sum(snk)   (nobody edits counts behind inventory's back)
--   * wear:    count == starting wear + net moved in by equip/unequip
--   * bag<->bag transfers net to zero per item
--   * overall: held == sum of non-transfer sources - sinks (+ starting wear)
-- Sources include start (kit + opening gear), craft_output, rubble_loot, expedition_loot, refund;
-- sinks include consumption commands (eat/drink/use/treat/...), craft_input, craft_fuel,
-- research_input and the subsystem burns (power/humidifier).
function M.ledger(state)
  local out = { held = {}, src = {}, snk = {}, problems = {} }
  local wear_start = (state.ledger and state.ledger.wear_start) or {}
  local function problem(msg) out.problems[#out.problems + 1] = msg end
  local bags = { { name = "stash", bag = state.home.stash } }
  for _, id in ipairs(util.sorted_keys(state.party.chars)) do
    local ch = state.party.chars[id]
    if type(ch.inv) == "table" then bags[#bags + 1] = { name = "bag " .. id, bag = ch.inv } end
  end
  local wear = {}
  for _, id in ipairs(util.sorted_keys(state.party.chars)) do
    local w = state.party.chars[id].wear
    if type(w) == "table" then
      for _, slot in ipairs(util.sorted_keys(w)) do
        local item = w[slot]
        wear[item] = (wear[item] or 0) + 1
      end
    end
  end
  local function add(tbl, reason, id, n)
    tbl[reason] = tbl[reason] or {}
    tbl[reason][id] = (tbl[reason][id] or 0) + n
  end
  for _, entry in ipairs(bags) do
    local bag = entry.bag
    local net = {}
    local flow = bag.flow or { src = {}, snk = {} }
    for _, reason in ipairs(util.sorted_keys(flow.src)) do
      for id, n in pairs(flow.src[reason]) do
        add(out.src, reason, id, n)
        net[id] = (net[id] or 0) + n
      end
    end
    for _, reason in ipairs(util.sorted_keys(flow.snk)) do
      for id, n in pairs(flow.snk[reason]) do
        add(out.snk, reason, id, n)
        net[id] = (net[id] or 0) - n
      end
    end
    for id, e in pairs(bag.items) do
      out.held[id] = (out.held[id] or 0) + e.count
      if (net[id] or 0) ~= e.count then
        problem(string.format("%s: %s holds %d but its flow says %d", entry.name, id, e.count, net[id] or 0))
      end
      net[id] = nil
    end
    for id, n in pairs(net) do
      if n ~= 0 then problem(string.format("%s: %s flow says %d but the bag is empty", entry.name, id, n)) end
    end
  end
  for id, n in pairs(wear) do out.held[id] = (out.held[id] or 0) + n end

  local function total(tbl, reason_ok, id)
    local t = 0
    for reason, by in pairs(tbl) do
      if reason_ok(reason) then t = t + (by[id] or 0) end
    end
    return t
  end
  local seen = {}
  for _, side in ipairs({ out.src, out.snk }) do
    for _, by in pairs(side) do
      for id in pairs(by) do seen[id] = true end
    end
  end
  for id in pairs(wear) do seen[id] = true end
  for id in pairs(wear_start) do seen[id] = true end
  for _, id in ipairs(util.sorted_keys(seen)) do
    local moved_in = total(out.snk, function(r) return WEAR_TRANSFER[r] end, id)
      - total(out.src, function(r) return WEAR_TRANSFER[r] end, id)
    local want_wear = (wear_start[id] or 0) + moved_in
    if (wear[id] or 0) ~= want_wear then
      problem(string.format("wear: %s worn %d but start+equip ledger says %d", id, wear[id] or 0, want_wear))
    end
    local bt_src = total(out.src, function(r) return BAG_TRANSFER[r] end, id)
    local bt_snk = total(out.snk, function(r) return BAG_TRANSFER[r] end, id)
    if bt_src ~= bt_snk then
      problem(string.format("transfer: %s moved in %d but out %d", id, bt_src, bt_snk))
    end
    local plain = function(r) return not WEAR_TRANSFER[r] and not BAG_TRANSFER[r] end
    local expect = (wear_start[id] or 0) + total(out.src, plain, id) - total(out.snk, plain, id)
    if (out.held[id] or 0) ~= expect then
      problem(string.format("conservation: %s held %d but sources-sinks say %d", id, out.held[id] or 0, expect))
    end
  end
  table.sort(out.problems)
  return out
end

-- Read-only ledger audit: schema validity, inventory counts, wear contents, conservation ledger,
-- non-finite numbers. Returns the list of problems (empty when clean).
function M.audit(state)
  local out = {}
  local ok, err = state_mod.validate(state)
  if not ok then
    out[#out + 1] = "validate: " .. tostring(err)
    return out
  end
  local good, verr = inventory.validate(state.home.stash, "stash")
  if not good then out[#out + 1] = verr end
  for _, id in ipairs(util.sorted_keys(state.party.chars)) do
    local ch = state.party.chars[id]
    if type(ch.inv) == "table" then
      local g, e = inventory.validate(ch.inv, id)
      if not g then out[#out + 1] = e end
    end
    for _, slot in ipairs(util.sorted_keys(ch.wear or {})) do
      if not items.get(ch.wear[slot]) then
        out[#out + 1] = string.format("%s.wear.%s holds unknown item %s", id, slot, tostring(ch.wear[slot]))
      end
    end
  end
  for _, msg in ipairs(M.ledger(state).problems) do out[#out + 1] = "ledger: " .. msg end
  nan_scan(state, { "state" }, out, {})
  table.sort(out)
  return out
end

-- audit + record failures in state.errors (state_mod.error). Returns true when clean.
function M.audit_into(state)
  local problems = M.audit(state)
  for _, msg in ipairs(problems) do state_mod.error(state, "audit: " .. msg) end
  return #problems == 0
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
