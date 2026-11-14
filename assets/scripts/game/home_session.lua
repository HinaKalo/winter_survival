-- Playable home session: wraps a sim state with real-time pacing, the day / dusk / dawn flow,
-- per-character action lists, HUD data and save/load. Pure model layer: every change to the
-- model goes through sim.command (time itself advances with sim.step).
local sim = require("sim.sim")
local clock = require("sim.clock")
local craft = require("sim.craft")
local tech = require("sim.tech")
local needs = require("sim.needs")
local weather = require("sim.weather")
local state_mod = require("sim.state")
local balance = require("data.balance")
local recipes = require("data.recipes")
local tech_data = require("data.tech")
local serialize = require("core.serialize")
local util = require("core.util")

local M = {}

M.MIN_PER_SEC = 2
M.SPEEDS = { 0, 1, 2, 4 }

local DEFAULT_SPEED = 2
local ROLES = { "sleep", "guard", "out" }
local MAX_OUT = 2
local NIGHT_TARGET = "suburb_house"

local function run(state, cmd)
  return sim.command(state, cmd)
end

local function alive_ids(state)
  local out = {}
  for _, cid in ipairs(state.party.order) do
    local ch = state.party.chars[cid]
    if ch and ch.status == "alive" then out[#out + 1] = cid end
  end
  return out
end

local function sync_mode(s)
  local phase = s.state.clock.phase
  if phase == "ending" then
    s.mode = "ending"
  elseif phase == "dusk" and s.mode == "day" then
    s.mode = "dusk"
    s.acc = 0
  end
end

function M.new(seed, opts)
  local state, err = sim.new(seed, opts)
  if not state then return nil, err end
  local s = { state = state, mode = "day", speed_idx = DEFAULT_SPEED, acc = 0.0, report = nil }
  sync_mode(s)
  return s
end

function M.set_speed(s, i)
  if M.SPEEDS[i] == nil then return false, "bad_speed" end
  s.speed_idx = i
  return true
end

function M.update(s, dt)
  if s.mode ~= "day" or type(dt) ~= "number" or dt <= 0 then return end
  local mult = M.SPEEDS[s.speed_idx] or 0
  if mult == 0 then return end
  s.acc = s.acc + dt * M.MIN_PER_SEC * mult
  local n = math.floor(s.acc)
  s.acc = s.acc - n
  for _ = 1, n do
    sim.step(s.state, 1)
    sync_mode(s)
    if s.mode ~= "day" then break end
  end
end

function M.end_day(s)
  if s.mode ~= "day" then return false, "not_day" end
  local ok, err = run(s.state, { kind = "home.end_day" })
  if not ok then return false, err or "not_day" end
  sync_mode(s)
  return true
end

function M.dusk_options(s)
  return { chars = alive_ids(s.state), roles = { "sleep", "guard", "out" } }
end

local function valid_role(role)
  for _, r in ipairs(ROLES) do
    if r == role then return true end
  end
  return false
end

local function avg_room_temp(state)
  local sum, n = 0, 0
  for _, rid in ipairs(state.home.room_order) do
    sum = sum + state.home.rooms[rid].temp
    n = n + 1
  end
  return n > 0 and sum / n or 0
end

local function round1(v)
  return math.floor(v * 10 + 0.5) / 10
end

local function name_key(id)
  return "char." .. id .. ".name"
end

local function build_report(state, day, before, squad, result)
  local lines = {}
  local function add(key, args) lines[#lines + 1] = { key = key, args = args or {} } end

  if #squad > 0 then
    local names = {}
    for _, cid in ipairs(squad) do names[#names + 1] = name_key(cid) end
    add("dawn.out", { chars = names, count = #squad, vp = result and result.vp or 0 })
  else
    add("dawn.stayed_home", {})
  end
  if result and result.injured then
    for _, cid in ipairs(result.injured) do add("dawn.injured", { char = name_key(cid) }) end
  end
  for _, cid in ipairs(util.sorted_keys(before)) do
    local ch = state.party.chars[cid]
    if ch and ch.status ~= "alive" then
      add("dawn.died", { char = name_key(cid), cause = ch.death_cause or "unknown" })
    end
  end
  add("dawn.temp", {
    outdoor = round1(weather.outdoor_temp(state)),
    indoor = round1(avg_room_temp(state)),
  })
  add("dawn.supplies", {
    food_days = round1(sim.food_days(state)),
    fuel_days = round1(sim.fuel_days(state)),
  })
  return { day = day, lines = lines }
end

function M.confirm_dusk(s, roles)
  if s.mode ~= "dusk" then return false, "not_dusk" end
  local state = s.state
  roles = roles or {}
  if type(roles) ~= "table" then return false, "bad_role" end

  local alive = {}
  for _, cid in ipairs(alive_ids(state)) do alive[cid] = true end
  for cid, role in pairs(roles) do
    if type(cid) ~= "string" or not alive[cid] then return false, "no_char" end
    if not valid_role(role) then return false, "bad_role" end
  end
  local full, squad = {}, {}
  for _, cid in ipairs(state.party.order) do
    local role = roles[cid] or "sleep"
    full[cid] = role
    if role == "out" and alive[cid] then squad[#squad + 1] = cid end
  end
  if #squad > MAX_OUT then return false, "bad_squad" end

  local day = state.clock.day
  local ok, err = run(state, { kind = "night.set_roles", roles = full, target = NIGHT_TARGET })
  if not ok then return false, err end

  local before = {}
  for cid in pairs(alive) do before[cid] = true end

  local guard = 0
  while state.clock.phase == "dusk" and guard < 1500 do
    guard = guard + 1
    sim.step(state, 1)
  end

  local result
  if state.clock.phase == "night" and #squad > 0 then
    local live = {}
    for _, cid in ipairs(squad) do
      local ch = state.party.chars[cid]
      if ch and ch.status == "alive" then live[#live + 1] = cid end
    end
    if #live > 0 then
      local rok, _, res = run(state, { kind = "raid.autoresolve", squad = live, hours = balance.expedition.hours })
      if rok then result = res end
    end
  end

  guard = 0
  while state.clock.phase == "night" and guard < 1500 do
    guard = guard + 1
    sim.step(state, 1)
  end

  s.acc = 0
  if state.clock.phase == "ending" then
    s.mode = "ending"
  else
    s.mode = "dawn"
  end
  s.report = build_report(state, day, before, squad, result)
  return true
end

function M.confirm_dawn(s)
  if s.mode ~= "dawn" then return false, "not_dawn" end
  local state = s.state
  local guard = 0
  while state.clock.phase == "dawn" and guard < 1500 do
    guard = guard + 1
    sim.step(state, 1)
  end
  s.acc = 0
  if state.clock.phase == "ending" then
    s.mode = "ending"
  else
    s.mode = "day"
  end
  return true
end

-- ------------------------------------------------------------------ actions

local function add_action(list, id, kind, label, enabled, reason)
  list[#list + 1] = {
    id = id, kind = kind, label = label, enabled = enabled and true or false,
    reason = (not enabled) and (reason or "unavailable") or nil,
  }
end

function M.actions(s, cid)
  local state = s.state
  local ch = state.party.chars[cid]
  local list = {}
  if not ch or ch.status ~= "alive" then return list end
  local in_day = s.mode == "day"
  local can_consume = s.mode == "day" or s.mode == "dusk"

  for _, rid in ipairs(util.sorted_keys(recipes.recipes)) do
    local r = recipes.recipes[rid]
    local ok, err = false, "not_day"
    if in_day then ok, err = craft.can(state, rid, cid, { room = ch.room }) end
    add_action(list, "craft:" .. rid, "craft", r.name, ok, err)
  end

  for _, node in ipairs(tech_data.list) do
    local ok, err = false, "not_day"
    if in_day then
      ok, err = tech.can(state, node.id, cid)
      if ok and ch.job then ok, err = false, "char_busy" end
    end
    add_action(list, "research:" .. node.id, "research", "tech." .. node.id .. ".name", ok, err)
  end

  local food = can_consume and needs.pick_food(state, ch) or nil
  add_action(list, "eat", "eat", "home.act.eat", food ~= nil, can_consume and "no_food" or "not_day")
  local water = can_consume and needs.pick_water(state, ch) or nil
  add_action(list, "drink", "drink", "home.act.drink", water ~= nil, can_consume and "no_water" or "not_day")

  local asleep = ch.activity == "sleep"
  add_action(list, "sleep", "sleep", "home.act.sleep", in_day and not asleep,
    in_day and "already_asleep" or "not_day")
  add_action(list, "wake", "wake", "home.act.wake", in_day and asleep, in_day and "not_asleep" or "not_day")

  for _, sid in ipairs(util.sorted_keys(state.home.stations)) do
    local st = state.home.stations[sid]
    if st.kind ~= "bed" then
      local ok, err = in_day and st.hp > 0, nil
      if not in_day then err = "not_day" elseif st.hp <= 0 then err = "broken" end
      add_action(list, "toggle:" .. sid, "toggle", "station." .. sid .. ".name", ok, err)
    end
  end
  return list
end

function M.act(s, cid, action_id)
  if type(cid) ~= "string" or type(action_id) ~= "string" then return false, "bad_arg" end
  local state = s.state
  local ch = state.party.chars[cid]
  if not ch or ch.status ~= "alive" then return false, "no_char" end

  local entry
  for _, a in ipairs(M.actions(s, cid)) do
    if a.id == action_id then entry = a break end
  end
  if not entry then return false, "unknown_action" end
  if not entry.enabled then return false, entry.reason end

  local ok, err
  if entry.kind == "craft" then
    ok, err = run(state, { kind = "craft.start", char = cid, recipe = action_id:sub(7), room = ch.room })
  elseif entry.kind == "research" then
    ok, err = run(state, { kind = "tech.start", char = cid, tech = action_id:sub(10) })
  elseif entry.kind == "eat" then
    ok, err = run(state, { kind = "needs.eat", char = cid })
  elseif entry.kind == "drink" then
    ok, err = run(state, { kind = "needs.drink", char = cid })
  elseif entry.kind == "sleep" then
    ok, err = run(state, { kind = "needs.sleep", char = cid })
  elseif entry.kind == "wake" then
    ok, err = run(state, { kind = "needs.wake", char = cid })
    if ok and state.party.chars[cid].job then
      ok, err = run(state, { kind = "home.set_activity", char = cid, value = "work" })
    end
  elseif entry.kind == "toggle" then
    local sid = action_id:sub(8)
    ok, err = run(state, { kind = "home.toggle", station = sid, on = not state.home.stations[sid].on })
  else
    return false, "unknown_action"
  end
  if not ok then return false, err or "failed" end
  return true
end

-- ------------------------------------------------------------------ hud

local function job_label(state, ch)
  if not ch.job then return nil end
  local job = state.jobs[ch.job]
  if not job then return nil end
  if job.kind == "research" then return "tech." .. tostring(job.tech) .. ".name" end
  return "recipe." .. tostring(job.recipe) .. ".name"
end

function M.hud(s)
  local state = s.state
  local h = {
    day = state.clock.day,
    clock = clock.clock_text(state),
    phase = state.clock.phase,
    outdoor_temp = weather.outdoor_temp(state),
    food_days = sim.food_days(state),
    fuel_days = sim.fuel_days(state),
    rubble = state.home.rubble or 0,
    rooms = {},
    chars = {},
  }
  for _, rid in ipairs(state.home.room_order) do
    h.rooms[#h.rooms + 1] = { id = rid, temp = state.home.rooms[rid].temp }
  end
  for _, cid in ipairs(state.party.order) do
    local ch = state.party.chars[cid]
    h.chars[#h.chars + 1] = {
      id = cid,
      name = name_key(cid),
      activity = ch.activity,
      job = job_label(state, ch),
      hp = ch.health.hp,
      needs = {
        hunger = ch.needs.food,
        thirst = ch.needs.water,
        energy = ch.needs.energy,
        warmth = ch.needs.temp,
      },
    }
  end
  return h
end

-- ------------------------------------------------------------------ save / load

function M.save(s)
  return serialize.encode({
    mode = s.mode,
    speed_idx = s.speed_idx,
    acc = s.acc,
    report = s.report,
    state = s.state,
  })
end

function M.load(str)
  local ok, data = serialize.decode(str)
  if not ok then return nil, tostring(data) end
  if type(data) ~= "table" or type(data.state) ~= "table" then return nil, "bad_save" end
  local valid, err = state_mod.validate(data.state)
  if not valid then return nil, err end
  local mode = data.mode
  if mode ~= "day" and mode ~= "dusk" and mode ~= "dawn" and mode ~= "ending" then return nil, "bad_mode" end
  if M.SPEEDS[data.speed_idx] == nil then return nil, "bad_speed" end
  return {
    state = data.state,
    mode = mode,
    speed_idx = data.speed_idx,
    acc = type(data.acc) == "number" and data.acc or 0.0,
    report = data.report,
  }
end

return M
