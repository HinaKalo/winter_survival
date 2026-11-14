-- 寒潮日程与温度曲线（CONTENT §6.5）。sim/weather.lua 读取本表。
-- severity: 1..4；4 = 大寒潮。ramp 由 sim/weather.lua 按 ramp_in / core / ramp_out 生成。
return {
  version = 1,
  base_mean = -15,
  sigma = 2.5,
  clamp = { -20, -10 },
  amplitude = 3,
  warm_hour = 14,
  big_snap_day = 28,

  small1 = { start = { 6, 9 }, days = 3, severity = { { 1, 0.6 }, { 2, 0.4 } } },
  small2 = { start = { 13, 17 }, days = { 3, 4 }, gap = 3,
    severity = { { 1, 0.3 }, { 2, 0.5 }, { 3, 0.2 } } },
  small3 = { start = { 21, 24 }, days = 4, chance = 0.6, gap = 3,
    severity = { { 2, 0.4 }, { 3, 0.6 } } },

  core_temp = { [1] = -30, [2] = -35, [3] = -40 },
  core_jitter = 2,
  ramp_in = -24,
  ramp_out = -26,

  big = {
    { day = 28, temp = -35 },
    { day = 29, temp = -48, jitter = 3 },
    { day = 30, temp = -50, jitter = 3 },
  },
  big_severity = 4,
  wind_chill = 5,

  forecast = {
    [0] = { lead = 0, day_ok = 0.0, severity_ok = 0.0, miss = 1.0 },
    [1] = { lead = 1, day_ok = 0.8, severity_ok = 0.55, miss = 0.15 },
    [2] = { lead = 3, day_ok = 0.7, severity_ok = 0.7, miss = 0.05 },
    [3] = { lead = 5, day_ok = 0.9, severity_ok = 0.85, miss = 0.0 },
  },
  national_big_warning_day = 24,
}
