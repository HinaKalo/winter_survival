-- Weather & cold snaps (CONTENT §6.5). Deterministic from state.rng.worldgen.
local rng = require("core.rng")
local cfg = require("data.weather")
local balance = require("data.balance")

local M = {}

local function round1(v)
  return math.floor(v * 10 + 0.5) / 10
end

local function normal(r)
  local u1 = rng.float(r)
  if u1 < 1e-12 then u1 = 1e-12 end
  local u2 = rng.float(r)
  return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

local function weighted(r, list)
  local total = 0
  for _, e in ipairs(list) do total = total + e[2] end
  local x = rng.float(r) * total
  local acc = 0
  for _, e in ipairs(list) do
    acc = acc + e[2]
    if x <= acc then return e[1] end
  end
  return list[#list][1]
end

local function make_snap(r, kind, start_day, days, sev)
  local core = cfg.core_temp[sev] + (rng.float(r) * 2 - 1) * cfg.core_jitter
  local ramp = {}
  local core_days = (days >= 4) and 2 or 1
  for i = 1, days do
    if i == 1 then
      ramp[i] = cfg.ramp_in
    elseif i > days - core_days then
      ramp[i] = cfg.ramp_out
    else
      ramp[i] = round1(core)
    end
  end
  if days == 3 then
    -- ramp_in, core, ramp_out
    ramp[1], ramp[2], ramp[3] = cfg.ramp_in, round1(core), cfg.ramp_out
  end
  if days >= 4 then
    ramp[1] = cfg.ramp_in
    for i = 2, days - 1 do ramp[i] = round1(core) end
    ramp[days] = cfg.ramp_out
  end
  return {
    kind = kind,
    start_day = start_day,
    days = days,
    severity = sev,
    core = round1(core),
    ramp = ramp,
    announced = false,
  }
end

function M.generate(state)
  local r = state.rng.worldgen
  local days = balance.time.days

  -- baseline daily means
  local means = {}
  for d = 1, days + 2 do
    local mu = cfg.base_mean + normal(r) * cfg.sigma
    if mu < cfg.clamp[1] then mu = cfg.clamp[1] end
    if mu > cfg.clamp[2] then mu = cfg.clamp[2] end
    means[d] = round1(mu)
  end

  local snaps = {}
  -- small snap 1: 100%, day 6..9, 3 days
  local s1 = rng.int(r, cfg.small1.start[1], cfg.small1.start[2])
  local d1 = cfg.small1.days
  local sev1 = weighted(r, cfg.small1.severity)
  snaps[#snaps + 1] = make_snap(r, "small", s1, d1, sev1)
  local end1 = s1 + d1 - 1

  -- small snap 2: 100%, start drawn in 13..17 and >= snap1 end + gap
  local lo2 = math.max(cfg.small2.start[1], end1 + cfg.small2.gap)
  local hi2 = cfg.small2.start[2]
  if lo2 > hi2 then lo2 = hi2 end
  local s2 = rng.int(r, lo2, hi2)
  local d2 = rng.int(r, cfg.small2.days[1], cfg.small2.days[2])
  local sev2 = weighted(r, cfg.small2.severity)
  snaps[#snaps + 1] = make_snap(r, "small", s2, d2, sev2)
  local end2 = s2 + d2 - 1

  -- small snap 3: 60%, day 21..24, >= snap2 end + gap
  local roll3 = rng.float(r)
  if roll3 < cfg.small3.chance then
    local lo3 = math.max(cfg.small3.start[1], end2 + cfg.small3.gap)
    if lo3 <= cfg.small3.start[2] then
      local s3 = rng.int(r, lo3, cfg.small3.start[2])
      local sev3 = weighted(r, cfg.small3.severity)
      snaps[#snaps + 1] = make_snap(r, "small", s3, cfg.small3.days, sev3)
    end
  end

  -- big snap: day 28, three days
  local big = {
    kind = "big",
    start_day = cfg.big[1].day,
    days = #cfg.big,
    severity = cfg.big_severity,
    core = cfg.big[2].temp,
    ramp = {},
    announced = false,
  }
  for i, e in ipairs(cfg.big) do
    local t = e.temp
    if e.jitter then t = t + (rng.float(r) * 2 - 1) * e.jitter end
    big.ramp[i] = round1(t)
  end
  snaps[#snaps + 1] = big

  -- apply ramps to the daily means
  for _, snap in ipairs(snaps) do
    for i = 1, snap.days do
      local d = snap.start_day + i - 1
      if means[d] ~= nil then means[d] = snap.ramp[i] end
    end
  end

  state.weather = {
    day_means = means,
    snaps = snaps,
    outdoor_temp = means[1],
    wind_chill = cfg.wind_chill,
    forecast = {},
    forecast_level = 0,
    forecast_day = 0,
  }
  return state.weather
end

function M.daily_mean(state, day)
  local means = state.weather.day_means
  return means[day] or means[#means] or -15
end

function M.outdoor_temp(state, minute)
  local c = state.clock
  local m = minute
  local day = c.day
  if m == nil then m = c.minute end
  local mean = M.daily_mean(state, day)
  local h = m / 60
  return round1(mean + cfg.amplitude * math.cos(2 * math.pi * (h - cfg.warm_hour) / 24))
end

function M.update_outdoor(state)
  state.weather.outdoor_temp = M.outdoor_temp(state)
  return state.weather.outdoor_temp
end

function M.snap_on(state, day)
  for _, s in ipairs(state.weather.snaps) do
    if day >= s.start_day and day < s.start_day + s.days then return s end
  end
  return nil
end

function M.is_big_snap_day(state, day)
  local s = M.snap_on(state, day)
  return s ~= nil and s.kind == "big"
end

function M.wind_chill(state)
  -- CONTENT 6.2.3: every cold-wave day (small and big) has wind chill
  if M.snap_on(state, state.clock.day) then return cfg.wind_chill end
  return 0
end

function M.radio_level(state)
  local st = state.home and state.home.stations or {}
  if st.f_shortwave and st.f_shortwave.hp > 0 and st.f_shortwave.on then return 3 end
  if st.f_antenna and st.f_antenna.hp > 0 and st.f_antenna.on then return 2 end
  if st.f_radio and st.f_radio.hp > 0 and st.f_radio.on then return 1 end
  return 0
end

local function linwei_alive(state)
  for _, cid in ipairs(state.party.order) do
    local c = state.party.chars[cid]
    if c and c.id == "linwei" and c.status == "alive" then return true end
  end
  return false
end

-- Effective forecast spec for a radio level (CONTENT 6.5.3): with linwei alive and
-- level >= 2, miss and error probabilities are halved and the lead grows by a day.
function M.forecast_spec(state, level)
  local base = cfg.forecast[level]
  local W = balance.weather
  local spec = { lead = base.lead, day_ok = base.day_ok, severity_ok = base.severity_ok, miss = base.miss }
  if level >= W.linwei_min_level and linwei_alive(state) then
    local k = W.linwei_error_mult
    spec.lead = spec.lead + W.linwei_lead_bonus
    spec.miss = spec.miss * k
    spec.day_ok = 1 - (1 - spec.day_ok) * k
    spec.severity_ok = 1 - (1 - spec.severity_ok) * k
  end
  return spec
end

local function forecast_entry(r, snap, spec)
  local miss = rng.float(r) < spec.miss
  if miss then return nil end
  local day_ok = rng.float(r) < spec.day_ok
  local sev_ok = rng.float(r) < spec.severity_ok
  local start_day = snap.start_day
  if not day_ok then start_day = start_day + (rng.int(r, 0, 1) == 0 and -1 or 1) end
  local severity = snap.severity
  if not sev_ok then
    severity = severity + (rng.int(r, 0, 1) == 0 and -1 or 1)
    severity = math.max(1, math.min(4, severity))
  end
  return {
    kind = snap.kind,
    start_day = start_day,
    days = snap.days,
    severity = severity,
    estimated = not (day_ok and sev_ok),
    national = snap.kind == "big",
  }
end

-- Rebuild the radio forecast (called at dawn; level from home stations).
function M.refresh_forecast(state)
  local level = M.radio_level(state)
  local r = state.rng.weather
  local out = {}
  local today = state.clock.day
  local spec = M.forecast_spec(state, level)
  if level > 0 then
    for _, snap in ipairs(state.weather.snaps) do
      if snap.start_day >= today and snap.start_day - today <= spec.lead then
        local e = forecast_entry(r, snap, spec)
        if e then out[#out + 1] = e end
      end
    end
    -- national warning for the big snap from day 24
    if today >= cfg.national_big_warning_day then
      local has = false
      for _, e in ipairs(out) do if e.kind == "big" then has = true end end
      if not has then
        local big
        for _, s in ipairs(state.weather.snaps) do if s.kind == "big" then big = s end end
        if big then
          out[#out + 1] = { kind = "big", start_day = big.start_day, days = big.days,
            severity = big.severity, estimated = false, national = true }
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.start_day ~= b.start_day then return a.start_day < b.start_day end
    return a.kind < b.kind
  end)
  state.weather.forecast = out
  state.weather.forecast_level = level
  state.weather.forecast_day = today
  return out
end

return M
