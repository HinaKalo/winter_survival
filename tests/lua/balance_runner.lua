-- `zig build balance` runner: one game day per frame, deterministic report in out/balance/.
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local sim = require("sim.sim")
local bot = require("sim.bot")
local state_mod = require("sim.state")
local chars = require("sim.chars")
local clock = require("sim.clock")
local util = require("core.util")

local runs = tonumber(os.getenv("WS_BALANCE_RUNS") or "1") or 1
local days = tonumber(os.getenv("WS_BALANCE_DAYS") or "30") or 30
local base_seed = tonumber(os.getenv("WS_BALANCE_SEED") or "20261114") or 20261114
local verify = (os.getenv("WS_BALANCE_VERIFY") or "true") ~= "false"

local report = {
  days = days,
  runs = {},
  determinism = nil,
  errors = {},
}

local function one_run(seed)
  -- PLAN 9.3: acceptance runs use the reference kit (sim.new creates it; the bot never adds it).
  local st, err = sim.new(seed, { kit = "bot" })
  if not st then return { seed = seed, fatal = err } end
  for _ = 1, days do
    if st.clock.phase == "ending" then break end
    local alive = bot.play_day(st)
    -- Daily ledger audit (validate + inventory counts + NaN scan); failures land in st.errors,
    -- which feed report.errors and therefore ok_all.
    sim.audit_into(st)
    if not alive then break end
    coroutine.yield()
  end
  local s = sim.summary(st)
  return {
    seed = seed,
    day = s.day,
    phase = s.phase,
    alive = s.alive,
    deaths = #s.dead,
    food_days = s.food_days,
    fuel_days = s.fuel_days,
    checksum = s.checksum,
    errors = s.errors,
    stats = s.stats,
    dead = s.dead,
  }
end

local function encode_text(r)
  local lines = {}
  local function add(k, v) lines[#lines + 1] = string.format('    %q: %s', k, v) end
  add("seed", tostring(r.seed))
  add("day", tostring(r.day or 0))
  add("phase", string.format("%q", tostring(r.phase or "?")))
  add("alive", tostring(r.alive or 0))
  add("deaths", tostring(r.deaths or 0))
  add("food_days", string.format("%.4f", r.food_days or 0))
  add("fuel_days", string.format("%.4f", r.fuel_days or 0))
  add("checksum", string.format("%q", tostring(r.checksum or "")))
  add("errors", tostring(#(r.errors or {})))
  local st = r.stats or {}
  add("min_food", string.format("%.4f", st.min_food or 0))
  add("min_water", string.format("%.4f", st.min_water or 0))
  add("min_temp", string.format("%.4f", st.min_temp or 0))
  add("worst_room_temp", string.format("%.4f", st.worst_room_temp or 0))
  add("best_room_temp", string.format("%.4f", st.best_room_temp or 0))
  add("meals", tostring(st.meals or 0))
  add("crafts", tostring(st.crafts or 0))
  add("researches", tostring(st.researches or 0))
  add("expeditions", tostring(st.expeditions or 0))
  local dead = {}
  for _, d in ipairs(r.dead or {}) do
    dead[#dead + 1] = string.format('{ "id": %q, "day": %d, "cause": %q }',
      tostring(d.id), d.day or 0, tostring(d.cause or "unknown"))
  end
  add("dead", "[" .. table.concat(dead, ", ") .. "]")
  return "  {\n" .. table.concat(lines, ",\n") .. "\n  }"
end

local function write_report()
  local alive_sum, day_sum = 0, 0
  for _, r in ipairs(report.runs) do
    alive_sum = alive_sum + (r.alive or 0)
    day_sum = day_sum + (r.day or 0)
  end
  local n = math.max(1, #report.runs)
  local lines = {
    "{",
    string.format('  "days": %d,', days),
    string.format('  "runs": %d,', #report.runs),
    string.format('  "avg_alive": %.4f,', alive_sum / n),
    string.format('  "avg_day": %.4f,', day_sum / n),
    '  "note": "M3 reference bot and start kit are tuning placeholders, not final balance",',
    '  "placeholder_expedition": true,',
    '  "results": [',
  }
  for i, r in ipairs(report.runs) do
    lines[#lines + 1] = encode_text(r) .. (i < #report.runs and "," or "")
  end
  lines[#lines + 1] = "  ],"
  if report.determinism then
    lines[#lines + 1] = string.format('  "determinism": { "ok": %s, "a": %q, "b": %q },',
      tostring(report.determinism.ok), report.determinism.a or "", report.determinism.b or "")
  end
  lines[#lines + 1] = '  "errors": ['
  for i, e in ipairs(report.errors) do
    lines[#lines + 1] = string.format('    %q%s', e, i < #report.errors and "," or "")
  end
  lines[#lines + 1] = "  ]"
  lines[#lines + 1] = "}"
  local text = table.concat(lines, "\n") .. "\n"
  local f = io.open("out/balance/report.json", "wb")
  if not f then
    os.execute("mkdir -p out/balance")
    f = io.open("out/balance/report.json", "wb")
  end
  if f then
    f:write(text)
    f:close()
  end
  local h = io.open("out/balance/report.html", "wb")
  if h then
    h:write("<html><meta charset='utf-8'><body><h1>Thirty Below M3 balance</h1>" ..
      "<p>days=" .. days .. " runs=" .. #report.runs ..
      " — M3 reference bot: tuning placeholders, not final balance.</p>" ..
      "<table border=1><tr><th>seed</th><th>day</th><th>alive</th><th>deaths</th>" ..
      "<th>food d</th><th>fuel d</th><th>min food</th><th>min water</th><th>min body</th>" ..
      "<th>worst room</th><th>checksum</th></tr>")
    for _, r in ipairs(report.runs) do
      local st = r.stats or {}
      h:write(string.format("<tr><td>%d</td><td>%d</td><td>%d</td><td>%d</td>" ..
        "<td>%.2f</td><td>%.2f</td><td>%.1f</td><td>%.1f</td><td>%.1f</td><td>%.1f</td><td>%s</td></tr>",
        r.seed or 0, r.day or 0, r.alive or 0, r.deaths or 0, r.food_days or 0, r.fuel_days or 0,
        st.min_food or 0, st.min_water or 0, st.min_temp or 0, st.worst_room_temp or 0, r.checksum or ""))
    end
    h:write("</table>")
    if report.determinism then
      h:write("<p>determinism: " .. tostring(report.determinism.ok) ..
        " (" .. tostring(report.determinism.a) .. " vs " .. tostring(report.determinism.b) .. ")</p>")
    end
    h:write("</body></html>")
    h:close()
  end
end

local co = coroutine.create(function()
  for i = 1, runs do
    local seed = base_seed + i - 1
    local result = one_run(seed)
    report.runs[#report.runs + 1] = result
    for _, e in ipairs(result.errors or {}) do report.errors[#report.errors + 1] = e end
    print(string.format("balance run %d/%d seed %d day %d alive %d checksum %s",
      i, runs, seed, result.day or 0, result.alive or 0, tostring(result.checksum)))
    coroutine.yield()
  end
  if verify then
    local a = one_run(base_seed)
    local b = one_run(base_seed)
    for _, r in ipairs({ a, b }) do
      for _, e in ipairs(r.errors or {}) do report.errors[#report.errors + 1] = "verify: " .. e end
    end
    local ok = a.checksum == b.checksum and a.checksum ~= nil
    report.determinism = { ok = ok, a = a.checksum, b = b.checksum }
    print("balance determinism", tostring(ok), tostring(a.checksum), tostring(b.checksum))
  end
  write_report()
  local ok_all = #report.errors == 0
  for _, r in ipairs(report.runs) do
    if (r.day or 0) < days or (r.alive or 0) <= 0 then ok_all = false end
  end
  if report.determinism and not report.determinism.ok then ok_all = false end
  kit_probe.check("balance report", ok_all)
  kit_probe.finish()
end)

local done = false
function _probe(_t, _dt)
  if done then return end
  kit_probe.timeout(900)
  local ok, err = coroutine.resume(co)
  if not ok then
    done = true
    print("balance error", tostring(err))
    kit_probe.check("balance script", false)
    print("PROBE info " .. tostring(err))
    kit_probe.finish()
    return
  end
  if coroutine.status(co) == "dead" then done = true end
end
