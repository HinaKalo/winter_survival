-- tech.* commands (P0-PLAN 3.2).
local commands = require("sim.commands")
local tech = require("sim.tech")

local reg = commands.domain("tech")

reg("start", function(state, cmd)
  return tech.start(state, cmd.tech, cmd.char)
end, { args = { { "char", "char" }, { "tech", "tech" } } })

reg("cancel", function(state)
  return tech.cancel(state, "command")
end, { args = {} })

reg("learn_blueprint", function(state, cmd)
  return tech.learn_blueprint(state, cmd.char, cmd.item)
end, { args = { { "char", "char" }, { "item", "item" } } })
