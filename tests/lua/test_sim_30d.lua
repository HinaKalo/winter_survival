-- 30-day acceptance: same-seed determinism plus save/load continuation at day 5 and 15.
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local sim = require("sim.sim")
local bot = require("sim.bot")
local state_mod = require("sim.state")
local chars = require("sim.chars")

local T = {}

-- Same setup as tests/probe/bot_days.lua and balance_runner (PLAN 9.3 acceptance runs): the
-- reference start kit via sim.new(seed, {kit = "bot"}), no direct state edits, only sim.command
-- through bot.play_day.
local SEED = 12345
local DAYS = 30

local function begin(seed)
  local st, err = sim.new(seed, { kit = "bot" })
  assert(st, err)
  return st
end

local function yield_frame()
  if coroutine.isyieldable() then coroutine.yield() end
end

-- One bot day with the daily ledger audit (validate + inventory + NaN scan), PLAN 9.1.
local function play_day(st, opts)
  bot.play_day(st, opts)
  assert(sim.audit_into(st), "daily audit failed: " .. tostring(st.errors[#st.errors]))
  yield_frame()
end

local function play_days(st, n)
  for _ = 1, n do
    if st.clock.phase == "ending" then break end
    play_day(st)
  end
  return st
end

local function check_bags(st)
  local problems = sim.audit(st)
  assert(#problems == 0, "ledger audit: " .. tostring(problems[1]))
end

function T.deterministic_30_days()
  local a = play_days(begin(SEED), DAYS)
  local b = play_days(begin(SEED), DAYS)
  assert(a.clock.phase == "ending", "run reaches the ending phase")
  assert(a.clock.day == DAYS, "day 30, got " .. tostring(a.clock.day))
  assert(state_mod.encode(a) == state_mod.encode(b), "same seed must be byte-identical")
  assert(state_mod.checksum(a) == state_mod.checksum(b))
  local ok, err = state_mod.validate(a)
  assert(ok, "final state validates: " .. tostring(err))
  assert(#a.errors == 0, "no Lua errors: " .. tostring(a.errors[1]))
  check_bags(a)
  assert(#chars.alive(a) >= 1, "the reference bot keeps the party alive")
  assert(a.opts.kit == "bot", "acceptance runs use the reference kit")
end

-- Inventory conservation after 30 days: stash + bags + wear == start + sources - sinks, with the
-- starting kit, looting, crafting output, consumption, crafting input and fuel burn all booked.
function T.ledger_balances_after_30_days()
  local a = play_days(begin(SEED), DAYS)
  local led = sim.ledger(a)
  assert(#led.problems == 0, "ledger must balance: " .. tostring(led.problems[1]))
  local function booked(side, reason)
    local n = 0
    for _, v in pairs(side[reason] or {}) do n = n + v end
    return n
  end
  assert(booked(led.src, "start") > 0, "starting kit is a booked source")
  assert(booked(led.snk, "craft_input") > 0, "crafting inputs are booked sinks")
  assert(booked(led.src, "craft_output") > 0, "crafting outputs are booked sources")
  assert(booked(led.snk, "eat") + booked(led.snk, "drink") + booked(led.snk, "needs") > 0, "consumption is booked")
  assert(booked(led.src, "expedition_loot") > 0, "looting is a booked source")
  assert(booked(led.snk, "power") + booked(led.snk, "craft_fuel") > 0, "fuel burn is booked")
  -- the check has teeth: one unrecorded item breaks the balance
  a.home.stash.items.scrap = { count = (a.home.stash.items.scrap and a.home.stash.items.scrap.count or 0) + 1 }
  assert(#sim.ledger(a).problems > 0)
  assert(not sim.audit_into(a))
end

-- Save at a phase boundary, load, and continue both copies to the next boundary: the bytes must
-- match the uninterrupted run (G6: any phase boundary).
local function roundtrip_checkpoint(a, label)
  local text = state_mod.encode(a)
  local b, err = state_mod.decode(text)
  assert(b, label .. ": " .. tostring(err))
  assert(state_mod.encode(b) == text, label .. ": roundtrip byte-identical")
  return b
end

local function lockstep(a, b, opts, label)
  play_day(a, opts)
  play_day(b, opts)
  assert(state_mod.encode(a) == state_mod.encode(b), label .. ": continuation after load diverges")
end

local function boundaries_of_day(a, label)
  -- day boundary (06:00 start of the day, before the morning handler)
  local b = roundtrip_checkpoint(a, label .. " day boundary")
  lockstep(a, b, { stop_phase = "dusk" }, label .. " day->dusk")
  assert(a.clock.phase == "dusk")
  -- dusk boundary (19:00, before the dusk handler)
  b = roundtrip_checkpoint(a, label .. " dusk")
  lockstep(a, b, { stop_phase = "night" }, label .. " dusk->night")
  assert(a.clock.phase == "night")
  -- night boundary (21:00, before the night handler)
  b = roundtrip_checkpoint(a, label .. " night")
  lockstep(a, b, nil, label .. " night->next day")
  assert(sim.audit_into(a) and sim.audit_into(b))
end

function T.save_roundtrip_day5_and_15()
  local a = play_days(begin(SEED), 4)
  assert(a.clock.day == 5 and a.clock.phase == "day")
  boundaries_of_day(a, "day 5")

  play_days(a, 9)
  assert(a.clock.day == 15, "checkpoint at the start of day 15, got " .. tostring(a.clock.day))
  boundaries_of_day(a, "day 15")
  check_bags(a)
  assert(#a.errors == 0, "no Lua errors: " .. tostring(a.errors[1]))
end

return T
