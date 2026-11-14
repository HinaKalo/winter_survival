-- travel.* commands: reserved until the WORLD line implements them (P0-PLAN 3.2).
local commands = require("sim.commands")

commands.reserve("travel.go", { args = { { "loc", "loc" }, { "squad", "char_list" } } })
