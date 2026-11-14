-- Command interface: every player/bot change to the model goes through here.
local balance = require("data.balance")
local chars = require("sim.chars")
local needs = require("sim.needs")
local health = require("sim.health")
local home = require("sim.home")
local craft = require("sim.craft")
local tech = require("sim.tech")
local inventory = require("sim.inventory")
local clock = require("sim.clock")
local expedition = require("sim.expedition")
local state_mod = require("sim.state")

local M = {}

local function alive_char(state, cid)
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
  if ch.job and cmd.value ~= "work" then
    craft.cancel(state, ch.job)
  end
  ch.activity = cmd.value
  return true
end

handlers.craft = function(state, cmd)
  local ch, err = alive_char(state, cmd.char)
  if not ch then return false, err end
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
  local squad = cmd.squad or {}
  if #squad < 1 or #squad > 2 then return false, "bad_squad" end
  for _, cid in ipairs(squad) do
    local ch = state.party.chars[cid]
    if not ch or ch.status ~= "alive" then return false, "no_char" end
  end
  local result = expedition.night(state, squad, cmd.hours)
  for _, cid in ipairs(squad) do
    local ch = state.party.chars[cid]
    if ch and ch.status == "alive" then ch.activity = "sleep" end
  end
  return true, result
end

local function stop_work(state)
  for _, cid in ipairs(state.party.order) do
    local ch = state.party.chars[cid]
    if ch and ch.job then
      local job = state.jobs[ch.job]
      if job then
        if job.kind == "research" then tech.cancel(state, "phase") else craft.cancel(state, ch.job) end
      else
        ch.job = nil
      end
      if ch.activity == "work" then ch.activity = "idle" end
    end
  end
end

handlers.end_day = function(state)
  if state.clock.phase ~= "day" then return false, "not_day" end
  stop_work(state)
  state.clock.minute = balance.time.dusk_start - 1
  clock.tick(state)
  state_mod.log(state, "day_ended", { minute = state.clock.minute })
  return true
end

handlers.sleep_until_dawn = function(state)
  -- convenience for bots: jump the clock, but still run sim steps in sim.step
  return true
end

function M.run(state, cmd)
  if type(cmd) ~= "table" then return false, "bad_command" end
  local kind = cmd.kind or cmd[1]
  local fn = handlers[kind]
  if not fn then return false, "unknown_command:" .. tostring(kind) end
  local ok, err = fn(state, cmd)
  if not ok then
    state_mod.log(state, "command_failed", { kind = kind, err = err })
  end
  return ok, err
end

function M.can(state, kind)
  return handlers[kind] ~= nil
end

return M
