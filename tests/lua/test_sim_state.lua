-- State root: new run, validation, serialization roundtrip, same-seed determinism.
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local sim = require("sim.sim")
local state = require("sim.state")

local T = {}

function T.new_run()
  local s, err = sim.new(12345)
  assert(s, err)
  local ok, verr = state.validate(s)
  assert(ok, verr)
  assert(#s.party.order == 4)
  local have_home, have_field = false, false
  for _, id in ipairs(s.party.order) do
    local c = s.party.chars[id]
    assert(c and c.status == "alive")
    assert(type(c.values.compassion) == "number")
    if c.role == "home" then have_home = true end
    if c.role == "field" then have_field = true end
  end
  assert(have_home and have_field, "party must contain both roles")
  assert(s.home.rooms.living, "home rooms")
  assert(s.home.stations.f_hearth, "starting stove")
  assert(s.tech.unlocked.t_hearth, "stove tech")
  assert(#s.weather.snaps >= 3, "snap schedule")
  assert(s.weather.snaps[#s.weather.snaps].kind == "big")
end

function T.serialize_roundtrip()
  local s = assert(sim.new(99))
  local text = state.encode(s)
  local s2, err = state.decode(text)
  assert(s2, err)
  assert(state.encode(s2) == text, "roundtrip must be byte-identical")
  assert(state.checksum(s) == state.checksum(s2))
end

function T.same_seed_deterministic()
  local a = assert(sim.new(7))
  local b = assert(sim.new(7))
  assert(state.encode(a) == state.encode(b), "same seed must produce the same state")
end

function T.bad_state_rejected()
  local s = assert(sim.new(1))
  s.clock.minute = 5000
  local ok = state.validate(s)
  assert(not ok)
  s = assert(sim.new(1))
  local cid = s.party.order[1]
  s.party.chars[cid].health.hp = -5
  assert(not state.validate(s))
end

function T.decode_rejects_garbage_without_raising()
  local function reject(label, text)
    local ok, a, b = pcall(state.decode, text)
    assert(ok, label .. ": decode raised " .. tostring(a))
    assert(a == nil and type(b) == "string", label .. ": expected nil, err; got " .. tostring(a))
  end
  reject("number", "return 5")
  reject("empty table", "return {}")
  reject("garbage text", "this is {{ not lua")
  reject("runtime error", "return nil + 1")
  reject("non-string", 42)

  local function mutate(label, fn)
    local s = assert(sim.new(5))
    fn(s)
    reject(label, state.encode(s))
  end
  mutate("char is a number", function(s) s.party.chars[s.party.order[1]] = 7 end)
  mutate("missing needs", function(s) s.party.chars[s.party.order[1]].needs = nil end)
  mutate("missing health", function(s) s.party.chars[s.party.order[1]].health = nil end)
  mutate("missing mood", function(s) s.party.chars[s.party.order[1]].needs.mood = nil end)
  mutate("mood is a string", function(s) s.party.chars[s.party.order[1]].needs.mood = "high" end)
  mutate("room entry not a table", function(s) s.home.rooms.living = 3 end)
  mutate("room temp missing", function(s) s.home.rooms.living.temp = nil end)
  mutate("no home", function(s) s.home = nil end)
  mutate("rng not a table", function(s) s.rng = 1 end)
end

function T.kit_is_given_at_creation_only()
  local plain = assert(sim.new(8))
  local kit = assert(sim.new(8, { kit = "bot" }))
  assert(kit.opts.kit == "bot" and plain.opts.kit == nil)
  assert(kit.tech.blueprints.t_bench3 and not plain.tech.blueprints.t_bench3, "kit blueprints")
  assert(kit.home.stash.items.planks.count > plain.home.stash.items.planks.count, "kit items")
  assert(rawget(kit, "_bot_kit") == nil, "no root marker field")
  local ok, err = sim.new(8, { kit = "nope" })
  assert(ok == nil and err == "unknown_kit")
end


-- PLAN 9.3: validate covers stash, bags, wear and the job tables.
local function rejects(label, fn)
  local s = assert(sim.new(5))
  fn(s)
  local ok, err = state.validate(s)
  assert(not ok and type(err) == "string", label .. ": validate must fail")
  local d, derr = state.decode(state.encode(s))
  assert(d == nil and type(derr) == "string", label .. ": decode must reject")
end

function T.validate_checks_stash_bags_wear()
  local first = function(s) return s.party.chars[s.party.order[1]] end
  rejects("unknown stash item", function(s) s.home.stash.items.nope = { count = 1 } end)
  rejects("negative stash count", function(s) s.home.stash.items.scrap = { count = -2 } end)
  rejects("fractional stash count", function(s) s.home.stash.items.scrap = { count = 1.5 } end)
  rejects("string count", function(s) s.home.stash.items.scrap = { count = "3" } end)
  rejects("stash not a table", function(s) s.home.stash = 4 end)
  rejects("bag missing", function(s) first(s).inv = nil end)
  rejects("bag unknown item", function(s) first(s).inv.items.zzz = { count = 1 } end)
  rejects("wear unknown item", function(s) first(s).wear.coat = "not_an_item" end)
  rejects("wear not a table", function(s) first(s).wear = "coat" end)
  rejects("wear item not a string", function(s) first(s).wear.hat = 5 end)
end

function T.validate_checks_job_tables()
  local first = function(s) return s.party.chars[s.party.order[1]] end
  local function job(s)
    local c = first(s)
    s.jobs.job_1 = { id = "job_1", kind = "craft", recipe = "make_nails", actor = c.id, room = "living",
      work_remaining = 5, work_total = 10, wait_remaining = 0, speed = 1, refund = {}, waiting = false }
    c.job = "job_1"
    return s.jobs.job_1
  end
  local s = assert(sim.new(5))
  job(s)
  assert(state.validate(s), "a well-formed job validates")
  rejects("job id mismatch", function(x) job(x).id = "job_9" end)
  rejects("job unknown actor", function(x) job(x).actor = "nobody" end)
  rejects("job unknown recipe", function(x) job(x).recipe = "no_such" end)
  rejects("job NaN progress", function(x) job(x).work_remaining = 0 / 0 end)
  rejects("job bad refund item", function(x) job(x).refund = { { item = "zzz", n = 1 } } end)
  rejects("job bad refund count", function(x) job(x).refund = { { item = "scrap", n = 1.5 } } end)
  rejects("char references a missing job", function(x) first(x).job = "job_77" end)
  rejects("char references someone else's job", function(x)
    job(x)
    x.party.chars[x.party.order[2]].job = "job_1"
  end)
  rejects("research pointer dangles", function(x) x.tech.research = "job_5" end)
  rejects("research job not the pointer", function(x)
    x.jobs.job_2 = { id = "job_2", kind = "research", tech = "t_bench1", actor = first(x).id,
      remaining = 5, total = 5, refund = {} }
  end)
  rejects("research unknown tech", function(x)
    x.jobs.job_2 = { id = "job_2", kind = "research", tech = "t_nope", actor = first(x).id,
      remaining = 5, total = 5, refund = {} }
    x.tech.research = "job_2"
  end)
end

function T.started_jobs_validate()
  local s = assert(sim.new(5, { kit = "bot" }))
  local c = s.party.chars[s.party.order[1]]
  s.tech.unlocked.t_clear_tools = true
  assert(sim.command(s, { kind = "craft", recipe = "clear_rubble", char = c.id }))
  local o = s.party.chars[s.party.order[2]]
  assert(sim.command(s, { kind = "research", tech = "t_bench1", char = o.id }))
  assert(state.validate(s))
  local d = assert(state.decode(state.encode(s)))
  assert(state.encode(d) == state.encode(s))
end

-- Inventory conservation ledger (stash + bags + wear).
function T.ledger_balances_across_every_flow()
  local s = assert(sim.new(21, { kit = "bot" }))
  assert(#sim.audit(s) == 0, tostring(sim.audit(s)[1]))
  local a = s.party.chars[s.party.order[1]]
  -- worn gear is in the opening ledger
  local led = sim.ledger(s)
  assert(led.held.winter_coat and led.held.winter_coat >= 4, "starting wear is counted")
  -- sinks: eating, crafting input; moves: equip/unequip; sources: crafting output
  assert(sim.command(s, { kind = "unequip", char = a.id, slot = "hat" }))
  assert(sim.command(s, { kind = "equip", char = a.id, item = "wool_hat" }))
  assert(sim.command(s, { kind = "craft", recipe = "heat_can", char = a.id }))
  assert(sim.command(s, { kind = "eat", char = a.id }) ~= nil)
  sim.step(s, 24 * 60)
  assert(#sim.audit(s) == 0, tostring(sim.audit(s)[1]))
  local l2 = sim.ledger(s)
  assert(l2.src.start and l2.snk.craft_input, "start source and craft_input sink are booked")
  assert(#l2.problems == 0, tostring(l2.problems[1]))
end

function T.ledger_catches_unrecorded_changes()
  local function audit_has(s, needle)
    for _, p in ipairs(sim.audit(s)) do
      if p:find(needle, 1, true) then return true end
    end
    return false
  end
  local s = assert(sim.new(22, { kit = "bot" }))
  s.home.stash.items.scrap.count = s.home.stash.items.scrap.count + 1
  assert(audit_has(s, "ledger"), "silently created stash items are an error")
  s = assert(sim.new(22, { kit = "bot" }))
  local a = s.party.chars[s.party.order[1]]
  a.wear.hat = nil
  assert(audit_has(s, "wear: wool_hat"), "gear that vanished from wear is an error")
  s = assert(sim.new(22, { kit = "bot" }))
  s.party.chars[s.party.order[1]].wear.pack = "winter_coat"
  assert(audit_has(s, "wear"), "gear conjured into wear is an error")
  s = assert(sim.new(22, { kit = "bot" }))
  s.party.chars[s.party.order[1]].wear.hat = "not_an_item"
  assert(audit_has(s, "validate"), "unknown wear id is an error")
  s = assert(sim.new(22, { kit = "bot" }))
  s.home.stash.items.scrap = nil
  assert(audit_has(s, "ledger"), "silently removed stash items are an error")
end

return T
