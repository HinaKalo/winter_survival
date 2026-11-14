-- Weather: snap schedule, day curve, determinism, radio forecast.
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local sim = require("sim.sim")
local weather = require("sim.weather")
local serialize = require("core.serialize")
local state_mod = require("sim.state")

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
      -- CONTENT 6.5.2: start >= previous end (its last day) + 3
      assert(snap.start_day >= prev.start_day + prev.days - 1 + 3, "snap gap")
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

function T.start_windows_over_many_seeds()
  local seen2, seen3, have3 = {}, {}, 0
  for seed = 1, 400 do
    local st = state_mod.new(seed)
    weather.generate(st)
    local sn = st.weather.snaps
    local s1, s2, s3 = sn[1], sn[2], sn[3]
    assert(s1.start_day >= 6 and s1.start_day <= 9)
    local end1 = s1.start_day + s1.days - 1
    assert(s2.start_day >= 13 and s2.start_day <= 17, "snap2 window " .. s2.start_day)
    assert(s2.start_day >= end1 + 3, "snap2 gap")
    seen2[s2.start_day] = true
    local end2 = s2.start_day + s2.days - 1
    if s3.kind == "small" then
      have3 = have3 + 1
      assert(s3.start_day >= 21 and s3.start_day <= 24, "snap3 window " .. s3.start_day)
      assert(s3.start_day >= end2 + 3, "snap3 gap")
      assert(s3.days == 4)
      seen3[s3.start_day] = true
    end
  end
  local n2, n3 = 0, 0
  for _ in pairs(seen2) do n2 = n2 + 1 end
  for _ in pairs(seen3) do n3 = n3 + 1 end
  assert(n2 >= 4, "snap2 start is drawn, not pinned: " .. n2 .. " distinct days")
  assert(n3 >= 3, "snap3 start is drawn: " .. n3 .. " distinct days")
  assert(have3 > 400 * 0.5 and have3 < 400 * 0.7, "snap3 appears ~60%: " .. have3)
end

local function with_linwei(s)
  s.party.chars.linwei = { id = "linwei", status = "alive" }
  s.party.order[#s.party.order + 1] = "linwei"
end

function T.linwei_forecast_spec()
  local st = state_mod.new(5)
  st.party.order = {}
  local base2 = weather.forecast_spec(st, 2)
  assert(base2.lead == 3 and base2.miss == 0.05 and base2.day_ok == 0.7 and base2.severity_ok == 0.7)
  with_linwei(st)
  local s2 = weather.forecast_spec(st, 2)
  assert(s2.lead == 4, "lead +1 day")
  assert(math.abs(s2.miss - 0.025) < 1e-9, "miss x0.5")
  assert(math.abs(s2.day_ok - 0.85) < 1e-9 and math.abs(s2.severity_ok - 0.85) < 1e-9, "errors x0.5")
  local s3 = weather.forecast_spec(st, 3)
  assert(s3.lead == 6 and math.abs(s3.day_ok - 0.95) < 1e-9 and math.abs(s3.severity_ok - 0.925) < 1e-9)
  local s1 = weather.forecast_spec(st, 1)
  assert(s1.lead == 1 and s1.miss == 0.15 and s1.day_ok == 0.8, "level 1 is unaffected")
end

function T.linwei_extends_forecast_lead()
  local s = assert(sim.new(71))
  s.party.order, s.party.chars = {}, {}
  s.home.stations.f_antenna = { id = "f_antenna", kind = "antenna", room = "living", hp = 100, on = true, fuel_frac = {}, charge = 0 }
  s.clock.day = 1
  s.weather.snaps[1].start_day = 5 -- 4 days ahead: beyond level-2 lead 3
  local function count()
    local n = 0
    for _ = 1, 20 do
      for _, e in ipairs(weather.refresh_forecast(s)) do
        if e.kind == "small" and e.days == s.weather.snaps[1].days and e.start_day >= 4 and e.start_day <= 6 then n = n + 1 end
      end
    end
    return n
  end
  assert(count() == 0, "without linwei a snap 4 days out is not forecast")
  with_linwei(s)
  assert(count() >= 15, "with linwei level 2 sees 4 days ahead")
end

return T
