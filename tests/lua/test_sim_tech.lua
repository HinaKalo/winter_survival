-- Tech: prereq/bench/blueprint gates, exclusive x1.5, star facility, blueprint learning.
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local sim = require("sim.sim")
local tech = require("sim.tech")
local tech_data = require("data.tech")
local home = require("sim.home")
local inventory = require("sim.inventory")

local T = {}

local function first(state)
  return state.party.chars[state.party.order[1]]
end

function T.unknown_and_unlocked()
  local s = assert(sim.new(61))
  local ok, err = tech.can(s, "no_such_tech")
  assert(not ok and err == "unknown_tech")
  local ok2, err2 = tech.can(s, "t_hearth")
  assert(not ok2 and err2 == "unlocked", "starter hearth is known")
end

function T.prereq_gate()
  local s = assert(sim.new(62))
  local ok, err = tech.can(s, "t_board_up")
  assert(not ok and err == "prereq:t_clear_tools", tostring(err))
  -- Once the prerequisite is known, the node becomes researchable.
  s.tech.unlocked.t_clear_tools = true
  assert(tech.can(s, "t_board_up"))
end

function T.bench_gate()
  local s = assert(sim.new(63))
  local ch = first(s)
  s.tech.unlocked.t_board_up = true
  local ok, err = tech.can(s, "t_heater_repair", ch.id)
  assert(not ok and err == "bench", "needs a workbench, got " .. tostring(err))
  home.add_station(s, "f_bench1", "bench1", "workshop", 100, false)
  assert(tech.can(s, "t_heater_repair", ch.id))
end

function T.material_gate()
  local s = assert(sim.new(64))
  local ch = first(s)
  local function drain(id)
    local n = inventory.count(s.home.stash, id)
    if n > 0 then inventory.remove(s.home.stash, id, n) end
    for _, c in ipairs(require("sim.chars").alive(s)) do
      local m = inventory.count(c.inv, id)
      if m > 0 then inventory.remove(c.inv, id, m) end
    end
  end
  drain("scrap")
  local ok, err = tech.can(s, "t_bench1", ch.id)
  assert(not ok and err == "material:scrap", tostring(err))
end

function T.research_completion_adds_star_facility()
  local s = assert(sim.new(65))
  local ch = first(s)
  assert(not s.home.stations.f_bench1, "bench starts unbuilt")
  assert(tech.can(s, "t_bench1", ch.id), "starter materials cover bench 1")
  local ok, job = tech.start(s, "t_bench1", ch.id)
  assert(ok, job)
  assert(s.tech.research == job.id and ch.job == job.id)
  assert(not tech.start(s, "t_clear_tools", ch.id), "one research at a time")
  tech.tick(s, 60)
  assert(s.tech.unlocked.t_bench1, "research completes")
  assert(s.home.stations.f_bench1, "star adds the first facility")
  assert(s.tech.research == nil and ch.job == nil, "actor released")
  assert(s.stats.researches == 1)
end

function T.exclusive_multiplier()
  local s = assert(sim.new(66))
  local node = { id = "fake", cost = { scrap = 2 }, work = 10, exclusive = "nobody" }
  assert(tech.exclusive_missing(s, node))
  local cost = tech.cost_for(s, node)
  assert(cost.scrap == 3, "cost x1.5 without the specialist: " .. tostring(cost.scrap))
  assert(math.abs(tech.work_for(s, node) - 15) < 1e-9, "work x1.5")
  s.party.chars.nobody = { id = "nobody", status = "alive" }
  assert(not tech.exclusive_missing(s, node))
  assert(tech.cost_for(s, node).scrap == 2, "normal cost with the specialist")
end

function T.blueprint_gate_and_learning()
  local s = assert(sim.new(67))
  local ch = first(s)
  s.tech.unlocked.t_hearth2 = true
  s.tech.unlocked.t_water_filter = true
  home.add_station(s, "f_bench2", "bench2", "workshop", 100, false)
  local ok, err = tech.can(s, "t_distiller", ch.id)
  assert(not ok and err == "blueprint", "distiller blueprint missing: " .. tostring(err))

  inventory.add(s.home.stash, "bp_distiller", 1, { force = true })
  assert(tech.learn_blueprint(s, ch.id, "bp_distiller"))
  assert(s.tech.blueprints.t_distiller)
  assert(inventory.count(s.home.stash, "bp_distiller") == 0, "blueprint consumed")
  assert(tech.can(s, "t_distiller", ch.id), "now researchable")
end

function T.cancel_releases_actor()
  local s = assert(sim.new(68))
  local ch = first(s)
  assert(tech.start(s, "t_clear_tools", ch.id))
  assert(s.tech.research)
  assert(tech.cancel(s, "test"))
  assert(s.tech.research == nil and ch.job == nil)
end

function T.available_is_sorted()
  local s = assert(sim.new(69))
  local ch = first(s)
  local list = tech.available(s, ch.id)
  assert(#list > 0)
  for i = 2, #list do assert(list[i - 1] < list[i], "sorted") end
  assert(tech_data.get(list[1]) ~= nil)
end

return T
