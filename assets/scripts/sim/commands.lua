-- Command interface: every player/bot change to the model goes through here.
local balance = require("data.balance")
local chars = require("sim.chars")
local needs = require("sim.needs")
local health = require("sim.health")
local home = require("sim.home")
local craft = require("sim.craft")
local tech = require("sim.tech")
local inventory = require("sim.inventory")
local expedition = require("sim.expedition")
local state_mod = require("sim.state")

local M = {}

local function finite(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function alive_char(state, cid)
  if type(cid) ~= "string" then return nil, "no_char" end
  local ch = state.party.chars[cid]
  if not ch or ch.status ~= "alive" then return nil, "no_char" end
  return ch
end

local handlers = {}

handlers.eat = function(state, cmd)
  local ch, err = alive_char(state, cmd.char)
  if not ch then return false, err end
  return needs.eat(state, ch, cmd.item)
end

handlers.drink = function(state, cmd)
  local ch, err = alive_char(state, cmd.char)
  if not ch then return false, err end
  return needs.drink(state, ch, cmd.item)
end

handlers.use = function(state, cmd)
  local ch, err = alive_char(state, cmd.char)
  if not ch then return false, err end
  if not cmd.item then return false, "no_item" end
  return needs.consume_item(state, ch, cmd.item)
end

handlers.equip = function(state, cmd)
  local ch, err = alive_char(state, cmd.char)
  if not ch then return false, err end
  return chars.equip(state, ch, cmd.item)
end

handlers.unequip = function(state, cmd)
  local ch, err = alive_char(state, cmd.char)
  if not ch then return false, err end
  return chars.unequip(state, ch, cmd.slot)
end

handlers.sleep = function(state, cmd)
  local ch, err = alive_char(state, cmd.char)
  if not ch then return false, err end
  return needs.sleep(state, ch)
end

handlers.wake = function(state, cmd)
  local ch, err = alive_char(state, cmd.char)
  if not ch then return false, err end
  return needs.wake(state, ch)
end

handlers.assign = function(state, cmd)
  local ch, err = alive_char(state, cmd.char)
  if not ch then return false, err end
  return home.assign(state, ch.id, cmd.room)
end

handlers.activity = function(state, cmd)
  local ch, err = alive_char(state, cmd.char)
  if not ch then return false, err end
  local ok_activity = { idle = true, work = true, sleep = true, guard = true, out = true }
  if not ok_activity[cmd.value] then return false, "bad_activity" end
  -- Changing activity never cancels a job: it just pauses it (PLAN 9.1); only cancel_job drops it.
  ch.activity = cmd.value
  return true
end

handlers.craft = function(state, cmd)
  local ch, err = alive_char(state, cmd.char)
  if not ch then return false, err end
  if cmd.room ~= nil and (type(cmd.room) ~= "string" or not state.home.rooms[cmd.room]) then
    return false, "bad_room"
  end
  return craft.start(state, cmd.recipe, ch.id, { room = cmd.room })
end

handlers.cancel_job = function(state, cmd)
  return craft.cancel(state, cmd.job)
end

handlers.research = function(state, cmd)
  local ch, err = alive_char(state, cmd.char)
  if not ch then return false, err end
  return tech.start(state, cmd.tech, ch.id)
end

handlers.cancel_research = function(state)
  return tech.cancel(state, "command")
end

handlers.toggle = function(state, cmd)
  return home.set_toggle(state, cmd.station, cmd.on)
end

handlers.set_level = function(state, cmd)
  local st = state.home.stations[cmd.station]
  if not st then return false, "no_station" end
  if cmd.level ~= "low" and cmd.level ~= "high" then return false, "bad_level" end
  st.level = cmd.level
  return true
end

handlers.set_door = function(state, cmd)
  local d = state.home.structure.doors[tostring(cmd.x) .. "," .. tostring(cmd.y)]
  if not d then return false, "no_door" end
  d.open = cmd.open and true or false
  home.rebuild(state)
  return true
end

handlers.board = function(state, cmd)
  local room = cmd.room or state.home.default_room
  if cmd.what == "hole" then return home.board_hole(state, room) end
  return home.board_window(state, room)
end

handlers.treat = function(state, cmd)
  local patient, err = alive_char(state, cmd.patient)
  if not patient then return false, err end
  local actor, err2 = alive_char(state, cmd.actor or cmd.patient)
  if not actor then return false, err2 end
  return health.treat(state, patient, actor, cmd.item)
end

handlers.learn_blueprint = function(state, cmd)
  local ch, err = alive_char(state, cmd.char)
  if not ch then return false, err end
  return tech.learn_blueprint(state, ch.id, cmd.item)
end

handlers.night_roles = function(state, cmd)
  if state.clock.phase ~= "dusk" and state.clock.phase ~= "night" then
    return false, "not_dusk"
  end
  if cmd.roles ~= nil and type(cmd.roles) ~= "table" then return false, "bad_roles" end
  if cmd.target ~= nil and type(cmd.target) ~= "string" then return false, "bad_target" end
  local roles = {}
  for _, cid in ipairs(state.party.order) do
    local role = (cmd.roles or {})[cid] or "sleep"
    if role ~= "out" and role ~= "guard" and role ~= "sleep" then return false, "bad_role" end
    roles[cid] = role
  end
  state.night.roles = roles
  state.night.target = cmd.target
  state_mod.log(state, "night_roles", { roles = roles, target = cmd.target })
  return true
end

handlers.expedition = function(state, cmd)
  if state.clock.phase ~= "night" then return false, "not_night" end
  local squad = cmd.squad
  if type(squad) ~= "table" then return false, "bad_squad" end
  local n = 0
  for _ in pairs(squad) do n = n + 1 end
  if n < 1 or n > 2 or n ~= #squad then return false, "bad_squad" end
  local seen = {}
  for _, cid in ipairs(squad) do
    local ch, err = alive_char(state, cid)
    if not ch then return false, err end
    if seen[cid] then return false, "bad_squad" end
    seen[cid] = true
  end
  if cmd.hours ~= nil and (not finite(cmd.hours) or cmd.hours < 0 or cmd.hours > 24) then
    return false, "bad_hours"
  end
  local result = expedition.night(state, squad, cmd.hours)
  for _, cid in ipairs(squad) do
    local ch = state.party.chars[cid]
    if ch and ch.status == "alive" then ch.activity = "sleep" end
  end
  return true, nil, result
end

-- end_day lives in sim.lua (it needs sim.step); sim.command dispatches it.

-- Returns ok, err, extra. Unknown kinds, garbage fields and handler faults give false, err and
-- never raise; faults are also recorded in state.errors so audits see them.
function M.run(state, cmd)
  if type(cmd) ~= "table" then return false, "bad_command" end
  local kind = cmd.kind
  if kind == nil then kind = cmd[1] end
  if type(kind) ~= "string" then return false, "bad_command" end
  local fn = handlers[kind]
  if not fn then return false, "unknown_command:" .. kind end
  -- Inventory flow ledger: everything this command moves is booked under its kind (craft/research
  -- override with finer reasons; equip/unequip are the bag <-> wear transfers the audit expects).
  local prev_reason = inventory.set_reason(kind)
  local called, ok, err, extra = pcall(fn, state, cmd)
  inventory.set_reason(prev_reason)
  if not called then
    state_mod.error(state, "command " .. kind .. " raised: " .. tostring(ok))
    return false, "internal_error"
  end
  if not ok then
    state_mod.log(state, "command_failed", { kind = kind, err = tostring(err) })
  end
  return ok and true or false, err, extra
end

function M.can(state, kind)
  return handlers[kind] ~= nil
end

return M
