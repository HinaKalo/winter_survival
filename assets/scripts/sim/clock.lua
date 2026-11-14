-- Game clock: 1 minute steps, 4 phases, a "game day" runs 06:00 -> next 05:59.
local balance = require("data.balance")

local M = {}

local T = balance.time

function M.phase_at(minute)
  if minute >= T.day_start and minute < T.dusk_start then return "day" end
  if minute >= T.dusk_start and minute < T.night_start then return "dusk" end
  if minute >= T.night_start or minute < T.night_end then return "night" end
  if minute >= T.night_end and minute < T.dawn_end then return "dawn" end
  return "day"
end

function M.hour(state)
  return state.clock.minute / 60
end

function M.clock_text(state)
  local c = state.clock
  return string.format("%02d:%02d", math.floor(c.minute / 60), c.minute % 60)
end

function M.minute_of_day(state)
  return state.clock.minute
end

function M.clock_text(state)
  local c = state.clock
  return string.format("%02d:%02d", math.floor(c.minute / 60), c.minute % 60)
end

-- Advance exactly one minute. Returns a list of events:
--   { kind = "phase", from = ..., to = ... }
--   { kind = "new_day", day = n }
--   { kind = "ending" }
function M.tick(state)
  local c = state.clock
  if c.phase == "ending" then return {} end
  local events = {}
  local old_phase = c.phase
  local was_before_dawn = c.minute < T.dawn_end

  c.minute = c.minute + 1
  if c.minute >= 1440 then c.minute = c.minute - 1440 end

  -- game day rolls over at 06:00
  if was_before_dawn and c.minute == T.dawn_end then
    c.day = c.day + 1
    if c.day > T.days then
      c.day = T.days
      c.phase = "ending"
      events[#events + 1] = { kind = "ending" }
      return events
    end
    events[#events + 1] = { kind = "new_day", day = c.day }
  end

  local new_phase = M.phase_at(c.minute)
  c.phase = new_phase
  if old_phase ~= new_phase then
    events[#events + 1] = { kind = "phase", from = old_phase, to = new_phase }
  end
  return events
end

function M.advance(state, minutes)
  local events = {}
  for _ = 1, math.max(0, math.floor(minutes or 0)) do
    local ev = M.tick(state)
    for _, e in ipairs(ev) do events[#events + 1] = e end
    if state.clock.phase == "ending" then break end
  end
  return events
end

-- Absolute minute count since day 1 06:00, handy for spoil timers and ages.
function M.abs_minute(state)
  return (state.clock.day - 1) * 1440 + state.clock.minute
end

function M.is_night(state)
  local p = state.clock.phase
  return p == "night"
end

function M.is_work_time(state)
  return state.clock.phase == "day"
end

return M
