-- raid.* commands (P0-PLAN 3.2). autoresolve is the M3 placeholder; begin / commit are reserved (RAID).
local commands = require("sim.commands")
local expedition = require("sim.expedition")

local reg = commands.domain("raid")

reg("autoresolve", function(state, cmd)
  local squad = cmd.squad
  if cmd.hours ~= nil and (cmd.hours < 0 or cmd.hours > 24) then return false, "bad_hours" end
  local result = expedition.night(state, squad, cmd.hours)
  for _, cid in ipairs(squad) do
    local ch = state.party.chars[cid]
    if ch and ch.status == "alive" then ch.activity = "sleep" end
  end
  return true, nil, result
end, {
  args = { { "squad", "char_list", max = 2 }, { "hours", "number?" } },
  phase = { "night" }, phase_err = "not_night",
})

commands.reserve("raid.begin", { args = { { "loc", "loc" }, { "squad", "char_list" } } })
commands.reserve("raid.commit", { args = { { "result", "table" } } })
