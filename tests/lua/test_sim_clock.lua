-- Clock: phase boundaries, day rollover at 06:00, 30-day ending.
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local state_mod = require("sim.state")
local clock = require("sim.clock")

local T = {}

function T.phases()
  assert(clock.phase_at(360) == "day")
  assert(clock.phase_at(1139) == "day")
  assert(clock.phase_at(1140) == "dusk")
  assert(clock.phase_at(1259) == "dusk")
  assert(clock.phase_at(1260) == "night")
  assert(clock.phase_at(0) == "night")
  assert(clock.phase_at(299) == "night")
  assert(clock.phase_at(300) == "dawn")
  assert(clock.phase_at(359) == "dawn")
  assert(clock.phase_at(360) == "day")
end

function T.rollover_and_phases()
  local s = state_mod.new(1)
  assert(s.clock.day == 1 and s.clock.minute == 360 and s.clock.phase == "day")
  local ev = clock.advance(s, 1140 - 360)
  assert(s.clock.phase == "dusk", s.clock.phase)
  assert(#ev >= 1)
  clock.advance(s, 120)
  assert(s.clock.phase == "night")
  clock.advance(s, 480)
  assert(s.clock.phase == "dawn", "05:00 is dawn, got " .. s.clock.phase)
  local day = s.clock.day
  clock.advance(s, 60)
  assert(s.clock.day == day + 1, "day increments at 06:00")
  assert(s.clock.phase == "day")
end

function T.thirty_days_ending()
  local s = state_mod.new(1)
  clock.advance(s, 30 * 1440)
  assert(s.clock.phase == "ending", s.clock.phase)
  assert(s.clock.day == 30)
end

function T.clock_text_and_abs()
  local s = state_mod.new(1)
  assert(clock.clock_text(s) == "06:00")
  s.clock.minute = 1140
  assert(clock.clock_text(s) == "19:00")
  assert(clock.abs_minute(s) == 1140)
end

return T
