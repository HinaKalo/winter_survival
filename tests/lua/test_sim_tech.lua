-- Tech: prereq/bench/blueprint gates, exclusive x1.5, star facility, blueprint learning.
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local sim = require("sim.sim")
local tech = require("sim.tech")
local tech_data = require("data.tech")
local home = require("sim.home")
local inventory = require("sim.inventory")
local chars = require("sim.chars")
local craft = require("sim.craft")

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
  local ok, _, job = tech.start(s, "t_bench1", ch.id)
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

local function exclusive_setup(seed, specialist_state)
  local s = assert(sim.new(seed))
  -- Remove walt from whatever draw we got, then put him back as requested.
  for i = #s.party.order, 1, -1 do
    if s.party.order[i] == "walt" then table.remove(s.party.order, i) end
  end
  s.party.chars.walt = nil
  if specialist_state ~= "absent" then
    local w = assert(chars.create(s, "walt"))
    if specialist_state == "dead" then w.status = "dead" else s.party.order[#s.party.order + 1] = "walt" end
    s.party.chars.walt = w
  end
  s.tech.unlocked.t_insulation_2 = true
  s.tech.unlocked.t_wood_stove = true
  home.add_station(s, "f_bench2", "bench2", "workshop", 100, false)
  inventory.add(s.home.stash, "planks", 20, { force = true })
  inventory.add(s.home.stash, "insulation", 20, { force = true })
  inventory.add(s.home.stash, "nails", 40, { force = true })
  local other
  for _, id in ipairs(s.party.order) do if id ~= "walt" then other = s.party.chars[id] break end end
  return s, other
end

function T.exclusive_specialist_alive_only_they_research()
  local s, other = exclusive_setup(80, "alive")
  s.tech.blueprints.t_cold_cell = true
  local ok, err = tech.can(s, "t_cold_cell", other.id)
  assert(not ok and err == "not_specialist", tostring(err))
  assert(not tech.start(s, "t_cold_cell", other.id))
  assert(s.tech.research == nil and other.job == nil, "refusal changes nothing")
  assert(tech.can(s, "t_cold_cell", "walt"), "the specialist may research")
  local node = tech_data.get("t_cold_cell")
  assert(tech.cost_for(s, node).planks == 6, "no surcharge with the specialist")
  -- Away from home (out): not allowed either.
  s.party.chars.walt.activity = "out"
  local ok2, err2 = tech.can(s, "t_cold_cell", "walt")
  assert(not ok2 and err2 == "specialist_away", tostring(err2))
  s.party.chars.walt.activity = "idle"
  local started, _, job = tech.start(s, "t_cold_cell", "walt")
  assert(started, job)
  assert(math.abs(job.total - node.work) < 1e-9, "no x1.5 work with the specialist")
end

function T.exclusive_specialist_missing_needs_blueprint_and_costs_more()
  for _, mode in ipairs({ "absent", "dead" }) do
    local s, other = exclusive_setup(81, mode)
    local ok, err = tech.can(s, "t_cold_cell", other.id)
    assert(not ok and err == "blueprint", mode .. ": " .. tostring(err))
    s.tech.blueprints.t_cold_cell = true
    assert(tech.can(s, "t_cold_cell", other.id), mode .. ": blueprint makes it researchable")
    local node = tech_data.get("t_cold_cell")
    local before = inventory.count(s.home.stash, "planks")
    local started, _, job = tech.start(s, "t_cold_cell", other.id)
    assert(started, job)
    assert(inventory.count(s.home.stash, "planks") == before - 9, "cost x1.5 (6 -> 9)")
    assert(math.abs(job.total - node.work * 1.5) < 1e-9, "work x1.5")
  end
end

function T.craft_cancel_research_clears_tech_state()
  local s = assert(sim.new(82))
  local ch = first(s)
  local scrap = inventory.count(s.home.stash, "scrap")
  local ok, _, job = tech.start(s, "t_bench1", ch.id)
  assert(ok, job)
  assert(s.tech.research == job.id)
  assert(craft.cancel(s, job.id))
  assert(s.tech.research == nil, "no dangling research")
  assert(ch.job == nil and s.jobs[job.id] == nil)
  assert(inventory.count(s.home.stash, "scrap") == scrap, "refund before one minute of work")
  local logged = false
  for _, e in ipairs(s.log) do if e.event == "research_cancelled" then logged = true end end
  assert(logged, "research_cancelled is logged")
  assert(tech.start(s, "t_bench1", ch.id), "can start research again")
  tech.tick(s, 3)
  assert(craft.cancel(s, s.tech.research))
  assert(inventory.count(s.home.stash, "scrap") < scrap, "no refund after progress")
end

function T.research_pauses_when_actor_not_working()
  local s = assert(sim.new(83))
  local ch = first(s)
  local _, _, job = tech.start(s, "t_bench1", ch.id)
  tech.tick(s, 5)
  local left = job.remaining
  assert(left < job.total)
  ch.activity = "sleep"
  tech.tick(s, 30)
  assert(job.remaining == left and ch.job == job.id and s.tech.research == job.id, "paused, job kept")
  ch.activity = "work"
  tech.tick(s, 5)
  assert(job.remaining < left, "resumes")
end


function T.start_returns_true_nil_job_and_books_the_input_sink()
  local s = assert(sim.new(86))
  local ch = first(s)
  local ok, err, job = tech.start(s, "t_bench1", ch.id)
  assert(ok == true and err == nil and type(job) == "table" and job.kind == "research")
  local led = sim.ledger(s)
  assert(led.snk.research_input and next(led.snk.research_input), "research cost is a booked sink")
  assert(#led.problems == 0, tostring(led.problems[1]))
end

function T.failed_start_changes_nothing()
  local s = assert(sim.new(87))
  local ch = first(s)
  assert(tech.start(s, "t_bench1", ch.id))
  local before = require("sim.state").encode(s)
  local ok, err = tech.start(s, "t_clear_tools", first(s).id)
  assert(ok == false and type(err) == "string")
  assert(require("sim.state").encode(s) == before, "a refused start must not mutate anything")
end

return T
