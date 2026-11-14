-- night.* commands: the dusk plan (P0-PLAN 3.2). set_role / set_target / set_loadout are reserved (HOME).
local commands = require("sim.commands")
local state_mod = require("sim.state")

local reg = commands.domain("night")

-- The log event keeps its M3 name `night_roles`.
reg("set_roles", function(state, cmd)
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
end, { args = { { "roles", "table?" }, { "target", "loc?" } }, phase = { "dusk", "night" }, phase_err = "not_dusk" })

commands.reserve("night.set_role", { args = { { "char", "char" }, { "role", { "out", "guard", "sleep" } } } })
commands.reserve("night.set_target", { args = { { "loc", "loc?" } } })
commands.reserve("night.set_loadout", { args = { { "char", "char" }, { "items", "item_counts" } } })
