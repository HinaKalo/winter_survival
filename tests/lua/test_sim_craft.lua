-- Craft: material/station/tech gates, jobs, output, structure effects.
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local sim = require("sim.sim")
local craft = require("sim.craft")
local home = require("sim.home")
local inventory = require("sim.inventory")

local T = {}

function T.make_nails()
  local s = assert(sim.new(51))
  local ch = s.party.chars[s.party.order[1]]
  home.add_station(s, "f_bench1", "bench1", "workshop", 100, false)
  s.tech.unlocked.t_bench1 = true
  inventory.add(s.home.stash, "scrap", 5, { force = true })
  local before = inventory.count(s.home.stash, "nails")
  local scrap_before = inventory.count(s.home.stash, "scrap")
  assert(craft.can(s, "make_nails", ch.id))
  local ok, job = craft.start(s, "make_nails", ch.id)
  assert(ok, job)
  assert(inventory.count(s.home.stash, "scrap") == scrap_before - 1, "scrap consumed")
  craft.tick(s, 600)
  assert(inventory.count(s.home.stash, "nails") > before, "nails produced")
  assert(ch.job == nil, "actor released")
end

function T.tech_gate()
  local s = assert(sim.new(52))
  local ch = s.party.chars[s.party.order[1]]
  local ok, err = craft.can(s, "craft_crowbar", ch.id)
  assert(not ok and err:find("tech"), "missing tech")
end

function T.station_gate()
  local s = assert(sim.new(53))
  local ch = s.party.chars[s.party.order[1]]
  s.tech.unlocked.t_bench1 = true
  inventory.add(s.home.stash, "scrap", 5, { force = true })
  local ok = craft.can(s, "make_nails", ch.id)
  assert(not ok, "missing bench")
end

function T.board_window_effect()
  local s = assert(sim.new(54))
  local ch = s.party.chars[s.party.order[1]]
  s.tech.unlocked.t_board_up = true
  inventory.add(s.home.stash, "planks", 4, { force = true })
  inventory.add(s.home.stash, "nails", 12, { force = true })
  local room = "kitchen"
  local before = s.home.rooms[room].envelope.board
  assert(craft.can(s, "board_window", ch.id, { room = room }))
  local ok, job = craft.start(s, "board_window", ch.id, { room = room })
  assert(ok, job)
  craft.tick(s, 600)
  assert(s.home.rooms[room].envelope.board > before, "window boarded")
end

function T.invalid_recipe()
  local s = assert(sim.new(55))
  local ch = s.party.chars[s.party.order[1]]
  local ok, err = craft.can(s, "no_such_recipe", ch.id)
  assert(not ok and err == "unknown_recipe")
end

function T.phase_boundary_keeps_long_jobs()
  local s = assert(sim.new(56))
  local ch = s.party.chars[s.party.order[1]]
  home.add_station(s, "f_bench1", "bench1", "workshop", 100, false)
  s.tech.unlocked.t_bench1 = true
  inventory.add(s.home.stash, "scrap", 5, { force = true })
  local ok, job = craft.start(s, "make_nails", ch.id)
  assert(ok, job)
  -- Simulate a long job; crossing day -> dusk -> night must not cancel it.
  job.work_remaining = 10000
  sim.step(s, 900)
  assert(s.clock.phase == "night", "reached night: " .. s.clock.phase)
  assert(s.jobs[job.id], "night phase must not cancel an in-progress craft")
  assert(ch.job == job.id, "actor stays assigned to the job")
end

return T
