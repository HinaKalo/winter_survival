-- 30-day acceptance: same-seed determinism plus save/load continuation at day 5 and 15.
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local sim = require("sim.sim")
local bot = require("sim.bot")
local state_mod = require("sim.state")
local chars = require("sim.chars")
local items = require("data.items")

local T = {}

-- Same setup as tests/probe/bot_days.lua (the documented M3 reference run):
-- no bot_kit and no direct state edits, only sim.command through bot.play_day.
local SEED = 12345
local DAYS = 30

local function begin(seed)
  local st, err = sim.new(seed)
  assert(st, err)
  return st
end

local function yield_frame()
  if coroutine.isyieldable() then coroutine.yield() end
end

local function play_days(st, n)
  for _ = 1, n do
    if st.clock.phase == "ending" then break end
    bot.play_day(st)
    yield_frame()
  end
  return st
end

local function check_bags(st)
  local function bag(name, b)
    for id, e in pairs(b.items) do
      assert(items.get(id), name .. " unknown item " .. tostring(id))
      assert(type(e.count) == "number" and e.count == e.count and e.count >= 0,
        name .. " bad count for " .. id)
    end
  end
  bag("stash", st.home.stash)
  for id, ch in pairs(st.party.chars) do
    bag(id, ch.inv)
    assert(ch.needs.food == ch.needs.food and ch.needs.water == ch.needs.water
      and ch.needs.energy == ch.needs.energy and ch.needs.temp == ch.needs.temp,
      id .. " NaN need")
  end
  for id, room in pairs(st.home.rooms) do
    assert(room.temp == room.temp, id .. " NaN room temp")
  end
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
end

function T.save_roundtrip_day5_and_15()
  local a = play_days(begin(SEED), 5)
  local text = state_mod.encode(a)
  local b, err = state_mod.decode(text)
  assert(b, err)
  assert(state_mod.encode(b) == text, "day-5 roundtrip byte-identical")

  -- One more day in lockstep: the decoded run must continue identically.
  play_days(a, 1)
  play_days(b, 1)
  assert(state_mod.encode(a) == state_mod.encode(b), "continuation after day-5 load diverges")

  -- Continue the original to the day-15 checkpoint.
  play_days(a, 9)
  assert(a.clock.day == 16, "checkpoint after day 15, got " .. tostring(a.clock.day))
  local text15 = state_mod.encode(a)
  local c, err15 = state_mod.decode(text15)
  assert(c, err15)
  assert(state_mod.encode(c) == text15, "day-15 roundtrip byte-identical")
  play_days(a, 1)
  play_days(c, 1)
  assert(state_mod.encode(a) == state_mod.encode(c), "continuation after day-15 load diverges")
  check_bags(a)
  assert(#a.errors == 0, "no Lua errors: " .. tostring(a.errors[1]))
end

return T
