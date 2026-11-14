-- 验收测试，编码代理不得修改（M3 第 2 次返工后的 Codex 审查，主代理编写；见 docs/M3-PLAN.md §9.4）。
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local sim = require("sim.sim")
local state = require("sim.state")
local chars = require("sim.chars")
local home = require("sim.home")
local thermal = require("sim.thermal")
local weather = require("sim.weather")
local inventory = require("sim.inventory")
local layout = require("core.layout")

local T = {}

local function deep_copy(v)
  if type(v) ~= "table" then return v end
  local o = {}
  for k, x in pairs(v) do o[k] = deep_copy(x) end
  return o
end

-- N1 (§9.1): night roles only pause jobs; at dawn every sleeper holding a job goes back to work.
function T.dawn_wakes_sleepers_back_to_their_jobs()
  local s = assert(sim.new(41, { kit = "bot" }))
  local a = s.party.chars[s.party.order[1]]
  local b = s.party.chars[s.party.order[2]]
  assert(sim.command(s, { kind = "craft", recipe = "heat_can", char = a.id }))
  assert(a.job and a.activity == "work", "craft started")
  b.job, b.activity = nil, "idle"
  sim.advance_phase(s, "night", "dusk")
  assert(a.activity == "sleep" and b.activity == "sleep", "default night role is sleep")
  sim.advance_phase(s, "dawn", "night")
  assert(a.activity == "work", "sleeper with a job resumes work at dawn, got " .. tostring(a.activity))
  assert(b.activity == "idle", "sleeper without a job is idle at dawn, got " .. tostring(b.activity))
end

-- N2: state.validate rejects job tables that would crash or run backwards in craft/tech ticks.
function T.validate_rejects_bad_job_speed_and_progress()
  local s = assert(sim.new(42, { kit = "bot" }))
  local a = s.party.chars[s.party.order[1]]
  local _, _, job = sim.command(s, { kind = "craft", recipe = "heat_can", char = a.id })
  local jid = a.job
  assert(jid and s.jobs[jid], "job started")
  assert(state.validate(s))
  local cases = {
    function(j) j.speed = "fast" end,
    function(j) j.speed = 0 end,
    function(j) j.speed = -1 end,
    function(j) j.speed = 0 / 0 end,
    function(j) j.work_total = 0 end,
    function(j) j.work_remaining = -5 end, -- not waiting: progress may not be negative
    function(j) j.work_remaining = j.work_total + 10 end,
    function(j) j.wait_remaining = -1 end,
  }
  for i, mutate in ipairs(cases) do
    local c = deep_copy(s)
    mutate(c.jobs[jid])
    local ok = state.validate(c)
    assert(not ok, "case " .. i .. " must be rejected")
    assert(state.decode(state.encode(c)) == nil, "case " .. i .. " must not decode")
  end
  -- speed nil and a positive finite speed stay valid
  local c = deep_copy(s); c.jobs[jid].speed = nil; assert(state.validate(c))
  c = deep_copy(s); c.jobs[jid].speed = 1.5; assert(state.validate(c))
  local _ = job
end

-- N3: the ledger holds when gear is moved by calling chars.equip / chars.unequip directly
-- (not only through the command dispatcher).
function T.direct_equip_and_unequip_keep_the_ledger()
  local s = assert(sim.new(43, { kit = "bot" }))
  local a = s.party.chars[s.party.order[1]]
  assert(#sim.audit(s) == 0)
  assert(chars.unequip(s, a, "hat"))
  local led = sim.ledger(s)
  assert(#led.problems == 0, "after direct unequip: " .. tostring(led.problems[1]))
  assert(chars.equip(s, a, "wool_hat"))
  led = sim.ledger(s)
  assert(#led.problems == 0, "after direct equip: " .. tostring(led.problems[1]))
  assert(#sim.audit(s) == 0, tostring(sim.audit(s)[1]))
  -- the reason in effect around the call is restored
  local prev = inventory.set_reason("probe_reason")
  chars.unequip(s, a, "hat")
  assert(inventory.reason == "probe_reason", "equip/unequip must not leak or clobber the ambient reason")
  inventory.set_reason(prev)
end

-- N4: a cooking job that is paused (efficiency 0) does not count as cooking: no +400 W, no steam.
function T.stalled_cooking_gives_no_stove_heat()
  local s = assert(sim.new(44, { kit = "bot" }))
  local a = s.party.chars[s.party.order[1]]
  assert(sim.command(s, { kind = "craft", recipe = "heat_can", char = a.id }))
  assert(home.cooking_active(s) == true, "a working cook counts as cooking")
  local real = chars.efficiency
  chars.efficiency = function() return 0 end
  local ok, active = pcall(home.cooking_active, s)
  chars.efficiency = real
  assert(ok, tostring(active))
  assert(active == false, "efficiency 0 pauses the job, so the stove is not cooking")
end

-- N5: malformed anchors never throw; huge or out-of-grid coordinates return nil, err.
function T.anchor_huge_coordinates_return_error()
  local function case(x, y)
    return { id = "anc", variants = { A = { grid = { "#####", "#...#", "#####" }, rooms = { a = { x = x, y = y } } } } }
  end
  for _, xy in ipairs({ { 1e30, 1 }, { 1, 1e30 }, { -1e30, 1 }, { 2 ^ 63, 1 }, { 1, -(2 ^ 63) } }) do
    local ok, l, err = pcall(layout.parse, case(xy[1], xy[2]), "A")
    assert(ok, "layout.parse threw for anchor " .. tostring(xy[1]) .. "," .. tostring(xy[2]) .. ": " .. tostring(l))
    assert(l == nil and type(err) == "string", "anchor " .. tostring(xy[1]) .. " must be rejected")
  end
end

-- N6: the CONTENT 6.2.4 steady state comes out of the real model (thermal.tick), not arithmetic.
function T.steady_state_from_the_model()
  local function env(t)
    local e = { wall = 0, hole = 0, window = 0, broken_window = 0, board = 0, door = 0, door_open = 0 }
    for k, v in pairs(t) do e[k] = v end
    return e
  end
  local s = assert(sim.new(45))
  for _, c in ipairs(chars.alive(s)) do c.room = "nowhere" end
  s.home = {
    rooms = { r = { id = "r", area = 20, envelope = env({ wall = 5, broken_window = 2, hole = 1, door = 1 }),
      links = {}, insulation = 0, frost = 100, temp = -15 } },
    room_order = { "r" }, stations = {}, humidity = 45,
  }
  local q = 800 + 240
  local real_heat, real_out = thermal.station_heat, weather.update_outdoor
  thermal.station_heat = function() return q end
  weather.update_outdoor = function() return -15 end
  local ok, err = pcall(function()
    local g = thermal.room_g(s, "r")
    local want = -15 + q / g
    for _ = 1, 14 * 24 * 60 do thermal.tick(s, 1) end
    local got = s.home.rooms.r.temp
    assert(math.abs(got - want) < 0.05, string.format("steady state %.3f, model predicts %.3f (G=%.2f)", got, want, g))
    -- and it moved there from -15: the model is actually integrating
    assert(got > -15 + 1, "room warmed up")
  end)
  thermal.station_heat, weather.update_outdoor = real_heat, real_out
  assert(ok, tostring(err))
end

return T
