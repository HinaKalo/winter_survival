-- Weather: snap schedule, day curve, determinism, radio forecast.
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local sim = require("sim.sim")
local weather = require("sim.weather")
local serialize = require("core.serialize")

local T = {}

function T.schedule()
  local s = assert(sim.new(4321))
  local snaps = s.weather.snaps
  assert(#snaps >= 3 and #snaps <= 4, "snap count " .. #snaps)
  local big
  for _, snap in ipairs(snaps) do
    if snap.kind == "big" then big = snap end
    assert(snap.start_day >= 1 and snap.start_day <= 30)
    assert(snap.severity >= 1 and snap.severity <= 4)
    assert(#snap.ramp == snap.days)
  end
  assert(big and big.start_day == 28 and big.severity == 4)
  assert(big.ramp[2] <= -45, "big snap core")
  -- small snaps do not overlap and respect the +3 day gap
  local prev
  for _, snap in ipairs(snaps) do
    if prev and snap.kind == "small" then
      assert(snap.start_day >= prev.start_day + prev.days + 3, "snap gap")
    end
    if snap.kind == "small" then prev = snap end
  end
end

function T.day_curve()
  local s = assert(sim.new(7))
  s.clock.minute = 14 * 60
  local warm = weather.outdoor_temp(s)
  s.clock.minute = 2 * 60
  local cold = weather.outdoor_temp(s)
  assert(warm > cold, "14:00 warmer than 02:00")
  assert(weather.daily_mean(s, 1) >= -20 and weather.daily_mean(s, 1) <= -10)
end

function T.deterministic()
  local a = assert(sim.new(99))
  local b = assert(sim.new(99))
  assert(serialize.encode(a.weather) == serialize.encode(b.weather))
end

function T.forecast()
  local s = assert(sim.new(1))
  s.clock.day = 24
  weather.refresh_forecast(s)
  assert(s.weather.forecast_level == 0)
  s.home.stations.f_radio = { id = "f_radio", kind = "radio", room = "living", hp = 100, on = true, fuel_frac = {}, charge = 0 }
  local entries = weather.refresh_forecast(s)
  assert(s.weather.forecast_level == 1, "radio gives level 1")
  local big = false
  for _, e in ipairs(entries) do if e.kind == "big" then big = true end end
  assert(big, "national warning from day 24")
end

return T
