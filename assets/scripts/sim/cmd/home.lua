-- home.* commands: gear, rooms, stations, doors, boarding, end of the work day (P0-PLAN 3.2).
local commands = require("sim.commands")
local chars = require("sim.chars")
local home = require("sim.home")
local inventory = require("sim.inventory")

local reg = commands.domain("home")

reg("equip", function(state, cmd)
  return chars.equip(state, state.party.chars[cmd.char], cmd.item)
end, { args = { { "char", "char" }, { "item", "item" } } })

reg("unequip", function(state, cmd)
  return chars.unequip(state, state.party.chars[cmd.char], cmd.slot)
end, { args = { { "char", "char" }, { "slot", "string" } } })

reg("assign", function(state, cmd)
  return home.assign(state, cmd.char, cmd.room)
end, { args = { { "char", "char" }, { "room", "room" } } })

-- Changing activity never cancels a job: it just pauses it (PLAN 9.1); only craft.cancel drops it.
reg("set_activity", function(state, cmd)
  state.party.chars[cmd.char].activity = cmd.value
  return true
end, {
  args = { { "char", "char" }, { "value", { "idle", "work", "sleep", "guard", "out" }, enum_err = "bad_activity" } },
})

reg("toggle", function(state, cmd)
  return home.set_toggle(state, cmd.station, cmd.on)
end, { args = { { "station", "station" }, { "on", "boolean" } } })

reg("set_level", function(state, cmd)
  state.home.stations[cmd.station].level = cmd.level
  return true
end, { args = { { "station", "station" }, { "level", { "low", "high" }, enum_err = "bad_level" } } })

reg("set_door", function(state, cmd)
  local d = state.home.structure.doors[tostring(cmd.x) .. "," .. tostring(cmd.y)]
  if not d then return false, "no_door" end
  d.open = cmd.open and true or false
  home.rebuild(state)
  return true
end, { args = { { "x", "int" }, { "y", "int" }, { "open", "boolean" } } })

reg("board", function(state, cmd)
  local room = cmd.room or state.home.default_room
  if cmd.what == "hole" then return home.board_hole(state, room) end
  return home.board_window(state, room)
end, { args = { { "room", "room?" }, { "what", { "window", "hole" }, optional = true } } })

-- Steps minute by minute to dusk. The ticks book their own flow reasons, so the ambient
-- command reason is cleared (it was never set for end_day before the registry).
reg("end_day", function(state)
  local sim = require("sim.sim") -- lazy: sim.sim requires sim.commands
  local prev = inventory.set_reason(nil)
  local ok, err = sim.end_day(state)
  inventory.set_reason(prev)
  return ok, err
end, { args = {}, phase = { "day" }, phase_err = "not_day" })
