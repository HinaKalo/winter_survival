-- State root, validation, serialization, and the small deterministic event log.
local rng = require("core.rng")
local serialize = require("core.serialize")
local balance = require("data.balance")
local items = require("data.items")
local recipes = require("data.recipes")
local tech_data = require("data.tech")
local inventory = require("sim.inventory")

local M = { VERSION = 1 }

local STREAMS = { "story", "loot", "combat", "worldgen", "health", "weather" }
M.STREAMS = STREAMS

function M.new(seed)
  seed = math.floor(tonumber(seed) or 1)
  if seed < 0 then seed = -seed end
  local streams = {}
  for i, name in ipairs(STREAMS) do
    streams[name] = rng.new(seed + (i - 1) * 2654435761)
  end
  return {
    version = M.VERSION,
    seed = seed,
    rng = streams,
    clock = { day = 1, minute = 360, phase = "day" },
    party = { order = {}, chars = {} },
    home = nil,
    weather = nil,
    tech = { unlocked = {}, blueprints = {}, research = nil },
    jobs = {},
    -- inventory conservation ledger (sim.ledger): worn gear at creation is the starting kit
    -- (CONTENT 10.2, character-owned, outside the budget); bag flows live on the bags themselves.
    ledger = { wear_start = {} },
    model_acc = 0,
    job_seq = 0,
    opts = { party_size = balance.limits.party_size, difficulty = "normal" },
    story = { facts = {}, deeds = {}, scheduled = {}, cooldowns = {}, tension = 0 },
    night = { roles = {}, target = nil, loadout = {} },
    stats = {
      days = 0,
      deaths = 0,
      meals = 0,
      drinks = 0,
      crafts = 0,
      researches = 0,
      expeditions = 0,
      firewood_burned = 0,
      best_room_temp = -99,
      worst_room_temp = 99,
      min_food = 100,
      min_water = 100,
      min_temp = 100,
      expedition_vp = 0,
      food_days = {},
      fuel_days = {},
    },
    log = {},
    errors = {},
  }
end

function M.stream(state, name)
  return state.rng[name] or state.rng.story
end

function M.log(state, event, data)
  local entry = { day = state.clock.day, minute = state.clock.minute, event = event }
  if data then
    for k, v in pairs(data) do entry[k] = v end
  end
  state.log[#state.log + 1] = entry
  local max = balance.limits.max_log
  if #state.log > max then
    table.remove(state.log, 1)
  end
end

function M.error(state, msg)
  state.errors[#state.errors + 1] = string.format("day %d %02d:%02d: %s",
    state.clock.day, math.floor(state.clock.minute / 60), state.clock.minute % 60, tostring(msg))
  if #state.errors > 50 then table.remove(state.errors, 1) end
  M.log(state, "error", { msg = tostring(msg) })
end

function M.encode(state)
  return serialize.encode(state)
end

local function finite(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function nonneg_int(v)
  return finite(v) and v >= 0 and v == math.floor(v)
end

local function validate_wear(id, wear)
  if type(wear) ~= "table" then return false, "bad wear for " .. id end
  for slot, item in pairs(wear) do
    if type(slot) ~= "string" then return false, "bad wear slot for " .. id end
    if type(item) ~= "string" or not items.get(item) then
      return false, string.format("%s.wear.%s holds unknown item %s", id, slot, tostring(item))
    end
  end
  return true
end

local function validate_refund(jid, refund)
  if refund == nil then return true end
  if type(refund) ~= "table" then return false, "bad refund on " .. jid end
  for _, e in ipairs(refund) do
    if type(e) ~= "table" or type(e.item) ~= "string" or not items.get(e.item) or not nonneg_int(e.n) then
      return false, "bad refund entry on " .. jid
    end
  end
  return true
end

-- Stash, every bag and wear, and the job tables (types, known ids, integer counts, references).
local function validate_inventories_and_jobs(state)
  local ok, err = inventory.validate(state.home.stash, "stash")
  if not ok then return false, err end
  local ids = {}
  for id in pairs(state.party.chars) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local ch = state.party.chars[id]
    if type(ch.inv) ~= "table" then return false, "missing bag for " .. id end
    local good, e = inventory.validate(ch.inv, "bag " .. id)
    if not good then return false, e end
    good, e = validate_wear(id, ch.wear)
    if not good then return false, e end
  end
  local jids = {}
  for jid in pairs(state.jobs) do jids[#jids + 1] = tostring(jid) end
  table.sort(jids)
  for _, jid in ipairs(jids) do
    local job = state.jobs[jid]
    if type(job) ~= "table" or job.id ~= jid then return false, "bad job " .. jid end
    if type(job.actor) ~= "string" or type(state.party.chars[job.actor]) ~= "table" then
      return false, "job " .. jid .. " has unknown actor"
    end
    if job.kind == "research" then
      if type(job.tech) ~= "string" or not tech_data.get(job.tech) then
        return false, "job " .. jid .. " has unknown tech"
      end
      if not finite(job.remaining) or not finite(job.total) then return false, "job " .. jid .. " bad progress" end
      if state.tech.research ~= jid then return false, "research job " .. jid .. " is not tech.research" end
    else
      if type(job.recipe) ~= "string" or not recipes.get(job.recipe) then
        return false, "job " .. jid .. " has unknown recipe"
      end
      if not finite(job.work_remaining) or not finite(job.work_total) or not finite(job.wait_remaining) then
        return false, "job " .. jid .. " bad progress"
      end
    end
    local good, e = validate_refund(jid, job.refund)
    if not good then return false, e end
  end
  local research = state.tech.research
  if research ~= nil then
    local job = state.jobs[research]
    if type(job) ~= "table" or job.kind ~= "research" then
      return false, "tech.research points at a missing job"
    end
  end
  for _, id in ipairs(ids) do
    local ch = state.party.chars[id]
    -- a dead character may keep a stale job id until the next job tick cleans it up
    if ch.status == "alive" and ch.job ~= nil then
      local job = state.jobs[ch.job]
      if type(job) ~= "table" or job.actor ~= id then
        return false, string.format("%s.job references missing/foreign job %s", id, tostring(ch.job))
      end
    end
  end
  return true
end

function M.validate(state)
  if type(state) ~= "table" then return false, "state is not a table" end
  if state.version ~= M.VERSION then return false, "bad version " .. tostring(state.version) end
  if not finite(state.seed) then return false, "bad seed" end
  if type(state.rng) ~= "table" then return false, "bad rng" end
  for _, name in ipairs(STREAMS) do
    local r = state.rng[name]
    if type(r) ~= "table" or not finite(r.s) then return false, "bad rng." .. name end
  end
  local c = state.clock
  if type(c) ~= "table" or not finite(c.day) or not finite(c.minute) or type(c.phase) ~= "string" then
    return false, "bad clock"
  end
  if c.day < 1 or c.day > balance.time.days + 1 then return false, "clock.day out of range" end
  if c.minute < 0 or c.minute > 1439 then return false, "clock.minute out of range" end
  local party = state.party
  if type(party) ~= "table" or type(party.order) ~= "table" or type(party.chars) ~= "table" then
    return false, "bad party"
  end
  for _, id in ipairs(party.order) do
    local ch = party.chars[id]
    if type(ch) ~= "table" then return false, "missing char " .. tostring(id) end
    if ch.status ~= "alive" then return false, "party contains non-alive char " .. tostring(id) end
  end
  for id, ch in pairs(party.chars) do
    if type(ch) ~= "table" then return false, "bad char " .. tostring(id) end
    if type(ch.needs) ~= "table" or type(ch.health) ~= "table" then
      return false, "missing needs/health for " .. tostring(id)
    end
    for _, field in ipairs({ "food", "water", "energy", "temp", "mood" }) do
      local v = ch.needs[field]
      if not finite(v) then return false, string.format("%s.needs.%s is not a finite number", tostring(id), field) end
      if v < -0.001 or v > 100.001 then
        return false, string.format("%s.%s out of range: %s", tostring(id), field, tostring(v))
      end
    end
    if not finite(ch.health.hp) then return false, "bad hp for " .. tostring(id) end
    if ch.health.hp < 0 or ch.health.hp > 100.001 then return false, "bad hp for " .. tostring(id) end
  end
  local home = state.home
  if type(home) ~= "table" or type(home.rooms) ~= "table" then return false, "bad home" end
  for id, room in pairs(home.rooms) do
    if type(room) ~= "table" or not finite(room.temp) then return false, "bad room " .. tostring(id) end
  end
  if not finite(home.humidity) then return false, "bad humidity" end
  if type(state.weather) ~= "table" or type(state.weather.snaps) ~= "table" then return false, "bad weather" end
  if type(state.tech) ~= "table" or type(state.tech.unlocked) ~= "table" then return false, "bad tech" end
  if type(state.jobs) ~= "table" then return false, "bad jobs" end
  if type(home.stash) ~= "table" then return false, "bad stash" end
  if state.ledger ~= nil and (type(state.ledger) ~= "table" or type(state.ledger.wear_start) ~= "table") then
    return false, "bad ledger"
  end
  local good, jerr = validate_inventories_and_jobs(state)
  if not good then return false, jerr end
  if type(state.log) ~= "table" or #state.log > balance.limits.max_log then return false, "bad log" end
  return true
end

-- Decoding never raises: garbage text, wrong types and malformed states give nil, err.
function M.decode(text)
  if type(text) ~= "string" then return nil, "expected string" end
  local ok, a, b = pcall(serialize.decode, text)
  if not ok then return nil, "decode failed: " .. tostring(a) end
  if not a then return nil, tostring(b) end
  local okv, valid, err = pcall(M.validate, b)
  if not okv then return nil, "validate failed: " .. tostring(valid) end
  if not valid then return nil, err end
  return b
end

-- FNV-1a 32-bit over the canonical serialization; used by balance/determinism reports.
function M.checksum(state)
  local text = M.encode(state)
  local h = 2166136261
  for i = 1, #text do
    h = h ~ text:byte(i)
    h = (h * 16777619) & 0xFFFFFFFF
  end
  return string.format("%08x", h)
end

return M
