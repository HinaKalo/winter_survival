-- story.* commands: reserved until the STORY line implements them (P0-PLAN 3.2).
local commands = require("sim.commands")

commands.reserve("story.choose", { args = { { "instance", "string" }, { "option", "int" } } })
