-- Craft: material/station/tech gates, jobs, output, structure effects.
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local sim = require("sim.sim")
local craft = require("sim.craft")
local home = require("sim.home")
local inventory = require("sim.inventory")
local chars = require("sim.chars")
local recipes = require("data.recipes")

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
  local ok, _, job = craft.start(s, "make_nails", ch.id)
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
  local ok, _, job = craft.start(s, "board_window", ch.id, { room = room })
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
  local ok, _, job = craft.start(s, "make_nails", ch.id)
  assert(ok, job)
  -- Long job: only the actor's role changes may pause it, never a phase boundary.
  job.work_remaining = 10000
  s.night.roles = {}
  for _, id in ipairs(s.party.order) do s.night.roles[id] = "sleep" end
  s.night.roles[ch.id] = "out"
  sim.step(s, 900)
  assert(s.clock.phase == "night", "reached night: " .. s.clock.phase)
  assert(s.jobs[job.id], "night phase must not cancel an in-progress craft")
  assert(ch.job == job.id, "actor stays assigned to the job")
  assert(ch.activity == "out", "actor is out at night, got " .. tostring(ch.activity))
  local mid = job.work_remaining
  assert(mid < 10000, "work advanced during the day")
  sim.step(s, 120)
  assert(job.work_remaining == mid, "job is paused while the actor is out")

  -- Sleeping pauses it too.
  ch.activity = "sleep"
  sim.step(s, 60)
  assert(job.work_remaining == mid and ch.job == job.id, "paused while asleep")
  ch.activity = "out"

  -- Dawn ends the night role: the job holder goes back to work and progress resumes.
  while s.clock.phase ~= "dawn" do sim.step(s, 5) end
  assert(ch.activity == "work", "dawn restores work, got " .. tostring(ch.activity))
  sim.step(s, 10)
  assert(job.work_remaining < mid, "progress resumes after dawn")
  assert(ch.job == job.id and s.jobs[job.id])
end

function T.job_pauses_without_work_activity()
  local s = assert(sim.new(57))
  local ch = s.party.chars[s.party.order[1]]
  home.add_station(s, "f_bench1", "bench1", "workshop", 100, false)
  s.tech.unlocked.t_bench1 = true
  inventory.add(s.home.stash, "scrap", 5, { force = true })
  local _, _, job = craft.start(s, "make_nails", ch.id)
  craft.tick(s, 2)
  local left = job.work_remaining
  assert(left < job.work_total)
  assert(sim.command(s, { kind = "activity", char = ch.id, value = "idle" }))
  assert(s.jobs[job.id] and ch.job == job.id, "activity change keeps the job")
  craft.tick(s, 5)
  assert(job.work_remaining == left, "idle actor makes no progress")
  assert(sim.command(s, { kind = "activity", char = ch.id, value = "work" }))
  craft.tick(s, 1)
  assert(job.work_remaining < left, "resumes when working again")
end

local function with_char(s, id)
  if not s.party.chars[id] then
    s.party.chars[id] = assert(chars.create(s, id))
    s.party.order[#s.party.order + 1] = id
  end
  return s.party.chars[id]
end

function T.work_time_and_specialty_bonus()
  local s = assert(sim.new(58))
  local plain = s.party.chars[s.party.order[1]]
  local walt = with_char(s, "walt")
  if plain.id == "walt" then plain = s.party.chars[s.party.order[2]] end
  s.tech.unlocked.t_bench1 = true
  home.add_station(s, "f_bench1", "bench1", "workshop", 100, false)
  inventory.add(s.home.stash, "scrap", 5, { force = true })
  local base = recipes.get("make_nails").minutes
  local ok, _, j1 = craft.start(s, "make_nails", plain.id)
  assert(ok, j1)
  assert(math.abs(j1.work_total - base) < 1e-9, "plain work time = recipe minutes")
  local ok2, _, j2 = craft.start(s, "make_nails", walt.id)
  assert(ok2, j2)
  assert(math.abs(j2.work_total - base * 0.7) < 1e-9, "walt work x0.7, got " .. j2.work_total)
  -- efficiency 1, bench I speed 1.0: exactly `base` minutes of work.
  s.party.chars[plain.id].needs.temp = 100
  local before = inventory.count(s.home.stash, "nails")
  craft.tick(s, base - 1)
  assert(s.jobs[j1.id], "not finished one minute early")
  craft.tick(s, 1)
  assert(not s.jobs[j1.id] and inventory.count(s.home.stash, "nails") >= before + 6)
end

function T.station_tiers()
  local s = assert(sim.new(59))
  local ch = s.party.chars[s.party.order[1]]
  for _, id in ipairs({ "t_hearth", "t_bench1", "t_coat1", "t_wood_stove" }) do s.tech.unlocked[id] = true end
  inventory.add(s.home.stash, "scrap", 20, { force = true })
  inventory.add(s.home.stash, "pipe", 10, { force = true })
  inventory.add(s.home.stash, "components", 10, { force = true })
  inventory.add(s.home.stash, "duct_tape", 10, { force = true })
  inventory.add(s.home.stash, "cloth", 20, { force = true })
  inventory.add(s.home.stash, "insulation", 10, { force = true })
  inventory.add(s.home.stash, "dried_rice", 5, { force = true })
  inventory.add(s.home.stash, "clean_water", 5, { force = true })
  inventory.add(s.home.stash, "firewood", 5, { force = true })

  -- hearth recipes: any of hearth / hearth2 / woodstove.
  assert(craft.can(s, "cook_rice", ch.id), "starting hearth")
  s.home.stations.f_hearth.hp = 0
  if s.home.stations.f_woodstove then s.home.stations.f_woodstove.hp = 0 end
  local ok, err = craft.can(s, "cook_rice", ch.id)
  assert(not ok and err:find("missing_station"), "broken hearth: " .. tostring(err))
  home.add_station(s, "f_woodstove", "woodstove", "living", 100, false)
  assert(craft.can(s, "cook_rice", ch.id), "woodstove counts as a hearth")
  s.home.stations.f_woodstove.hp = 0
  home.add_station(s, "f_hearth2", "hearth2", "kitchen", 100, false)
  assert(craft.can(s, "cook_rice", ch.id), "improved hearth counts as a hearth")

  -- benchN recipes: bench level >= N; a higher bench serves lower recipes.
  assert(not craft.can(s, "make_nails", ch.id), "no bench yet")
  home.add_station(s, "f_bench1", "bench1", "workshop", 100, false)
  assert(craft.can(s, "make_nails", ch.id), "bench I runs bench I recipes")
  local ok2, err2 = craft.can(s, "craft_coat", ch.id)
  assert(not ok2 and err2:find("missing_station"), "bench I cannot run bench II recipes")
  home.add_station(s, "f_bench3", "bench3", "workshop", 100, false)
  assert(craft.can(s, "craft_coat", ch.id), "bench III runs bench II recipes")
  assert(craft.can(s, "make_nails", ch.id), "bench III runs bench I recipes")

  -- bench speed only applies to bench recipes.
  local _, _, bench_job = craft.start(s, "craft_coat", ch.id)
  assert(math.abs(bench_job.speed - 1.3) < 1e-9, "bench III speed")
  craft.cancel(s, bench_job.id)
  local _, _, hearth_job = craft.start(s, "cook_rice", ch.id)
  assert(hearth_job.speed == 1.0, "bench speed does not apply to hearth recipes")
end

function T.cancel_refund_rule()
  local s = assert(sim.new(60))
  local ch = s.party.chars[s.party.order[1]]
  s.tech.unlocked.t_bench1 = true
  home.add_station(s, "f_bench1", "bench1", "workshop", 100, false)
  inventory.add(s.home.stash, "scrap", 5, { force = true })
  local scrap = inventory.count(s.home.stash, "scrap")

  -- progress < 1 game minute: full refund.
  local _, _, job = craft.start(s, "make_nails", ch.id)
  assert(inventory.count(s.home.stash, "scrap") == scrap - 1)
  assert(craft.cancel(s, job.id))
  assert(inventory.count(s.home.stash, "scrap") == scrap, "full refund before one minute of work")
  assert(ch.job == nil and ch.activity == "idle" and not s.jobs[job.id])

  -- progress >= 1 minute: no refund.
  local _, _, job2 = craft.start(s, "make_nails", ch.id)
  craft.tick(s, 2)
  assert(craft.cancel(s, job2.id))
  assert(inventory.count(s.home.stash, "scrap") == scrap - 1, "no refund once work has started")
  assert(not craft.cancel(s, job2.id), "unknown job")
end

function T.commands_validate_input()
  local s = assert(sim.new(61))
  local a, b = s.party.order[1], s.party.order[2]
  local function bad(cmd)
    local ok, err, extra = sim.command(s, cmd)
    assert(ok == false and type(err) == "string", "expected false, err for " .. tostring(cmd.kind) .. ": " .. tostring(err))
    assert(extra == nil)
  end
  bad({ kind = "no_such_kind" })
  bad({ kind = 5 })
  bad({ kind = 0 / 0 })
  bad({ kind = {} })
  bad("garbage")
  bad({})
  bad({ kind = "eat", char = {} })
  bad({ kind = "craft", recipe = "board_window", char = a, room = "no_room" })
  bad({ kind = "craft", recipe = "board_window", char = a, room = {} })
  s.clock.phase = "dusk"
  bad({ kind = "night_roles", roles = 5 })
  bad({ kind = "night_roles", roles = { [a] = "dance" } })
  bad({ kind = "night_roles", roles = {}, target = 7 })
  s.clock.phase = "night"
  bad({ kind = "expedition", squad = "x" })
  bad({ kind = "expedition", squad = {} })
  bad({ kind = "expedition", squad = { a, a } })
  bad({ kind = "expedition", squad = { a, b, s.party.order[3] } })
  bad({ kind = "expedition", squad = { "ghost" } })
  bad({ kind = "expedition", squad = { a, 5 } })
  bad({ kind = "expedition", squad = { a }, hours = 0 / 0 })
  bad({ kind = "expedition", squad = { a }, hours = -1 })
  bad({ kind = "expedition", squad = { a }, hours = 25 })
  bad({ kind = "expedition", squad = { a }, hours = math.huge })
  bad({ kind = "expedition", squad = { a }, hours = "6" })
  s.party.chars[b].status = "dead"
  bad({ kind = "expedition", squad = { b } })
  s.party.chars[b].status = "alive"

  -- Valid expedition: the result travels in the third return, not the error slot.
  local ok, err, result = sim.command(s, { kind = "expedition", squad = { a }, hours = 6 })
  assert(ok == true and err == nil, tostring(err))
  assert(type(result) == "table" and type(result.vp) == "number")
  s.clock.phase = "dusk"
  assert(sim.command(s, { kind = "night_roles", roles = { [a] = "out" }, target = "suburb_house" }))
  assert(#s.errors == 0, "no internal faults recorded: " .. tostring(s.errors[1]))
end

function T.end_day_steps_without_cancelling_jobs()
  local s = assert(sim.new(62))
  local ch = s.party.chars[s.party.order[1]]
  home.add_station(s, "f_bench1", "bench1", "workshop", 100, false)
  s.tech.unlocked.t_bench1 = true
  inventory.add(s.home.stash, "scrap", 5, { force = true })
  local _, _, job = craft.start(s, "make_nails", ch.id)
  job.work_remaining = 100000
  local before = s.clock.minute
  assert(sim.command(s, { kind = "end_day" }))
  assert(s.clock.phase == "dusk" and s.clock.minute == 1140, "end_day lands at 19:00")
  assert(s.jobs[job.id] and ch.job == job.id, "end_day keeps jobs")
  assert(job.work_remaining < 100000, "the clock was stepped, not teleported")
  assert(before < s.clock.minute)
  local ok, err = sim.command(s, { kind = "end_day" })
  assert(ok == false and err == "not_day")
  assert(not sim.command(s, { kind = "sleep_until_dawn" }), "sleep_until_dawn is gone")
end


-- PLAN 9.3: validate first, then mutate. Test recipes are injected into the data table and removed
-- again, so the real recipe set is untouched.
local util = require("core.util")
local commands = require("sim.commands")

local function with_recipe(id, def, fn)
  def.id, def.name, def.time = id, "recipe." .. id .. ".name", def.minutes or 0
  recipes.recipes[id] = def
  local ok, err = pcall(fn)
  recipes.recipes[id] = nil
  assert(ok, err)
end

local function snapshot(s, ch)
  return util.deep_copy({ stash = s.home.stash, bag = ch.inv, jobs = s.jobs, seq = s.job_seq })
end

local function same(a, b)
  return require("sim.state").encode({ a }) == require("sim.state").encode({ b })
end

function T.fuel_precheck_uses_the_burn_rule_pool_case()
  local s = assert(sim.new(81))
  local ch = s.party.chars[s.party.order[1]]
  with_recipe("t_pool", { kind = "craft", station = "hand", minutes = 5,
    inputs = { scrap = 1 }, fuel = { firewood = 1.25 }, outputs = { nails = 1 } }, function()
    s.home.stash.items.firewood = nil
    inventory.add(s.home.stash, "firewood", 1, { force = true })
    inventory.add(s.home.stash, "scrap", 3, { force = true })
    local scrap0 = inventory.count(s.home.stash, "scrap")
    s.home.stash.fuel_frac.firewood = 0.75
    -- the old rule (stock + pool >= n) says 1.75 >= 1.25; the burn needs floor(0.75 + 1.25) = 2
    local before = snapshot(s, ch)
    local ok, err = craft.start(s, "t_pool", ch.id)
    assert(ok == false and err == "missing_fuel", tostring(err))
    assert(same(before, snapshot(s, ch)), "stash/bag/jobs unchanged: no material may be deducted")
    local cok, cerr = craft.can(s, "t_pool", ch.id)
    assert(cok == false and cerr == "missing_fuel", "can() agrees with start()")
    -- one more firewood and the very same call goes through, burning exactly the predicted amount
    inventory.add(s.home.stash, "firewood", 1, { force = true })
    local started, e2, job = craft.start(s, "t_pool", ch.id)
    assert(started == true and e2 == nil and job, tostring(e2))
    assert(inventory.count(s.home.stash, "firewood") == 0 and s.home.stash.fuel_frac.firewood == 0)
    assert(inventory.count(s.home.stash, "scrap") == scrap0 - 1)
  end)
end

function T.fuel_precheck_sees_material_overlap()
  local s = assert(sim.new(82))
  local ch = s.party.chars[s.party.order[1]]
  with_recipe("t_overlap", { kind = "craft", station = "hand", minutes = 5,
    inputs = { firewood = 2 }, fuel = { firewood = 2 }, outputs = { nails = 1 } }, function()
    s.home.stash.items.firewood = nil
    ch.inv.items.firewood = nil
    inventory.add(s.home.stash, "firewood", 3, { force = true })
    -- old checks: material 3 >= 2 and fuel 3 >= 2 both pass, but after the 2 firewood inputs only 1 is left
    local before = snapshot(s, ch)
    local ok, err = craft.start(s, "t_overlap", ch.id)
    assert(ok == false and err == "missing_fuel", tostring(err))
    assert(same(before, snapshot(s, ch)), "failure leaves everything untouched")
    inventory.add(s.home.stash, "firewood", 1, { force = true })
    assert(craft.start(s, "t_overlap", ch.id))
    assert(inventory.count(s.home.stash, "firewood") == 0)
  end)
end

function T.fuel_bonus_multiplier_applies_to_precheck_and_burn()
  local s = assert(sim.new(83))
  local ch = s.party.chars[s.party.order[1]]
  with_recipe("t_mult", { kind = "craft", station = "hand", minutes = 5,
    fuel = { firewood = 2 }, outputs = { nails = 1 },
    bonus = { [ch.id] = { fuel = 0.5 } } }, function()
    s.home.stash.items.firewood = nil
    inventory.add(s.home.stash, "firewood", 1, { force = true })
    assert(craft.start(s, "t_mult", ch.id), "2 x 0.5 = 1 firewood is enough for this character")
    assert(inventory.count(s.home.stash, "firewood") == 0)
  end)
end

function T.craft_and_research_commands_return_ok_nil_job()
  local s = assert(sim.new(84, { kit = "bot" }))
  local ch = s.party.chars[s.party.order[1]]
  s.tech.unlocked.t_clear_tools = true
  local ok, err, job = commands.run(s, { kind = "craft", recipe = "clear_rubble", char = ch.id })
  assert(ok == true and err == nil, tostring(err))
  assert(type(job) == "table" and s.jobs[job.id] == job and job.recipe == "clear_rubble")
  local other = s.party.chars[s.party.order[2]]
  local rok, rerr, rjob = commands.run(s, { kind = "research", tech = "t_bench1", char = other.id })
  assert(rok == true and rerr == nil, tostring(rerr))
  assert(type(rjob) == "table" and rjob.kind == "research" and s.tech.research == rjob.id)
  local bad, berr, bextra = commands.run(s, { kind = "craft", recipe = "nope", char = ch.id })
  assert(bad == false and type(berr) == "string" and bextra == nil)
end

function T.refund_ignores_burned_fuel()
  local s = assert(sim.new(85))
  local ch = s.party.chars[s.party.order[1]]
  with_recipe("t_refund", { kind = "craft", station = "hand", minutes = 5,
    inputs = { scrap = 1 }, fuel = { firewood = 1 }, outputs = { nails = 1 } }, function()
    inventory.add(s.home.stash, "firewood", 2, { force = true })
    inventory.add(s.home.stash, "scrap", 2, { force = true })
    local _, _, job = craft.start(s, "t_refund", ch.id)
    assert(#job.refund == 1 and job.refund[1].item == "scrap" and job.refund[1].n == 1)
  end)
end

-- M3-PLAN 8 handover: no home station provides "garage", so repair_car is uncraftable for now.
function T.repair_car_is_gated_by_the_undefined_garage()
  local s = assert(sim.new(88, { kit = "bot" }))
  local ch = s.party.chars[s.party.order[1]]
  s.tech.unlocked.t_car_repair = true
  for id in pairs(recipes.get("repair_car").inputs or {}) do
    inventory.add(s.home.stash, id, 50, { force = true })
  end
  local ok, err = craft.can(s, "repair_car", ch.id)
  assert(ok == false and err == "missing_station:garage", tostring(err))
end

return T
