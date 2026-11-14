-- State root, validation, serialization, and the small deterministic event log.
local rng = require("core.rng")
local serialize = require("core.serialize")
local balance = require("data.balance")

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

function M.decode(text)
  if type(text) ~= "string" then return nil, "expected string" end
  local ok, data = serialize.decode(text)
  if not ok then return nil, data end
  local valid, err = M.validate(data)
  if not valid then return nil, err end
  return data
end

local function finite(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function M.validate(state)
  if type(state) ~= "table" then return false, "state is not a table" end
  if state.version ~= M.VERSION then return false, "bad version " .. tostring(state.version) end
  if not finite(state.seed) then return false, "bad seed" end
  for _, name in ipairs(STREAMS) do
    local r = state.rng and state.rng[name]
    if type(r) ~= "table" or not finite(r.s) then return false, "bad rng." .. name end
  end
  local c = state.clock
  if type(c) ~= "table" or not finite(c.day) or not finite(c.minute) or type(c.phase) ~= "string" then
    return false, "bad clock"
  end
  if c.day < 1 or c.day > balance.time.days + 1 then return false, "clock.day out of range" end
  if c.minute < 0 or c.minute > 1439 then return false, "clock.minute out of range" end
  if type(state.party) ~= "table" or type(state.party.order) ~= "table" then return false, "bad party" end
  for _, id in ipairs(state.party.order) do
    local ch = state.party.chars[id]
    if not ch then return false, "missing char " .. tostring(id) end
    if ch.status ~= "alive" then return false, "party contains non-alive char " .. tostring(id) end
  end
  for id, ch in pairs(state.party.chars) do
    if not finite(ch.needs.food) or not finite(ch.needs.water) or not finite(ch.needs.energy)
      or not finite(ch.needs.temp) or not finite(ch.health.hp) then
      return false, "bad needs/health for " .. tostring(id)
    end
    for _, field in ipairs({ "food", "water", "energy", "temp", "mood" }) do
      local v = ch.needs[field]
      if v < -0.001 or v > 100.001 then return false, string.format("%s.%s out of range: %s", id, field, tostring(v)) end
    end
    if ch.health.hp < 0 or ch.health.hp > 100.001 then return false, "bad hp for " .. tostring(id) end
  end
  if type(state.home) ~= "table" or type(state.home.rooms) ~= "table" then return false, "bad home" end
  for id, room in pairs(state.home.rooms) do
    if not finite(room.temp) then return false, "bad room temp " .. tostring(id) end
  end
  if not finite(state.home.humidity) then return false, "bad humidity" end
  if type(state.weather) ~= "table" or type(state.weather.snaps) ~= "table" then return false, "bad weather" end
  if type(state.tech) ~= "table" or type(state.tech.unlocked) ~= "table" then return false, "bad tech" end
  if type(state.jobs) ~= "table" then return false, "bad jobs" end
  if type(state.log) ~= "table" or #state.log > balance.limits.max_log then return false, "bad log" end
  return true
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
