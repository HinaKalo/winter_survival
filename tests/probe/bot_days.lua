local sim, bot, chars
local state
local day = 0
local max_days = tonumber(os.getenv("BOT_DAYS") or "30")
local started = false

function _probe(t, dt)
  if not started then
    started = true
    kit_probe.timeout(600)
    package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path
    sim = require("sim.sim")
    bot = require("sim.bot")
    chars = require("sim.chars")
    state = assert(sim.new(tonumber(os.getenv("BOT_SEED") or "12345")))
  end
  if state.clock.phase ~= "ending" and state.clock.day <= max_days then
    bot.play_day(state)
    return
  end
  local report = sim.summary(state)
  print("BOT REPORT day", report.day, "phase", report.phase, "alive", report.alive,
    "deaths", tostring(report.deaths), "food_days", string.format("%.2f", report.food_days),
    "fuel_days", string.format("%.2f", report.fuel_days), "checksum", report.checksum)
  print("errors", #report.errors)
  for _, e in ipairs(report.errors) do print("ERR", e) end
  for _, d in ipairs(report.dead) do print("DEAD", d.id, d.day, d.cause) end
  for _, c in ipairs(chars.alive(state)) do
    print("ALIVE", c.id, string.format("hp %.0f temp %.0f food %.0f water %.0f", c.health.hp, c.needs.temp, c.needs.food, c.needs.water))
  end
  for _, rid in ipairs(state.home.room_order) do
    print("ROOM", rid, string.format("%.1f", state.home.rooms[rid].temp), "ins", state.home.rooms[rid].insulation)
  end
  print("TECH", table.concat(require("core.util").sorted_keys(state.tech.unlocked), ","))
  print("RUBBLE", state.home.rubble)
  local inv = {}
  for id, e in pairs(state.home.stash.items) do inv[#inv + 1] = id .. ":" .. tostring(e.count) end
  table.sort(inv)
  print("STASH", table.concat(inv, " "))
  for _, id in ipairs(require("core.util").sorted_keys(state.home.stations)) do
    local x = state.home.stations[id]
    print("ST", id, x.kind, x.room, "hp", x.hp, "on", tostring(x.on))
  end
  kit_probe.check("bot 30 days", report.day >= max_days or report.alive > 0)
  kit_probe.finish()
end
