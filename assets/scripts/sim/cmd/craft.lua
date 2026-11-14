-- craft.* commands (P0-PLAN 3.2).
local commands = require("sim.commands")
local craft = require("sim.craft")

local reg = commands.domain("craft")

reg("start", function(state, cmd)
  return craft.start(state, cmd.recipe, cmd.char, { room = cmd.room })
end, { args = { { "char", "char" }, { "recipe", "recipe" }, { "room", "room?" } } })

reg("cancel", function(state, cmd)
  return craft.cancel(state, cmd.job)
end, { args = { { "job", "job" } } })
