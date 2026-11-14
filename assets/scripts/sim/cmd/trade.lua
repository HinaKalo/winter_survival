-- trade.* commands: all reserved until the WORLD line implements them (P0-PLAN 3.2).
local commands = require("sim.commands")

commands.reserve("trade.offer", {
  args = { { "trader", "npc" }, { "give", "item_counts" }, { "want", "item_counts" } },
})
commands.reserve("trade.accept", { args = { { "trader", "npc" } } })
commands.reserve("trade.leave", { args = { { "trader", "npc" } } })
