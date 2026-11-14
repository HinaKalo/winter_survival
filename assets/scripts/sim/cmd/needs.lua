-- needs.* commands: eating, drinking, sleeping, treatment (P0-PLAN 3.2).
local commands = require("sim.commands")
local needs = require("sim.needs")
local health = require("sim.health")

local reg = commands.domain("needs")

reg("eat", function(state, cmd)
  return needs.eat(state, state.party.chars[cmd.char], cmd.item)
end, { args = { { "char", "char" }, { "item", "item?" } } })

reg("drink", function(state, cmd)
  return needs.drink(state, state.party.chars[cmd.char], cmd.item)
end, { args = { { "char", "char" }, { "item", "item?" } } })

-- M3 answered a missing item with no_item; keep that code.
reg("use", function(state, cmd)
  return needs.consume_item(state, state.party.chars[cmd.char], cmd.item)
end, { args = { { "char", "char" }, { "item", "item", missing_err = "no_item" } } })

reg("sleep", function(state, cmd)
  return needs.sleep(state, state.party.chars[cmd.char])
end, { args = { { "char", "char" } } })

reg("wake", function(state, cmd)
  return needs.wake(state, state.party.chars[cmd.char])
end, { args = { { "char", "char" } } })

reg("treat", function(state, cmd)
  local patient = state.party.chars[cmd.patient]
  local actor = state.party.chars[cmd.actor or cmd.patient]
  return health.treat(state, patient, actor, cmd.item)
end, { args = { { "patient", "char" }, { "actor", "char?" }, { "item", "item?" } } })
