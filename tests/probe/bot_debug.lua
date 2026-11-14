function _probe()
  kit_probe.timeout(300)
  package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path
  local sim = require("sim.sim")
  local bot = require("sim.bot")
  local st = assert(sim.new(12345))
  local days = tonumber(os.getenv("BOT_DAYS") or "30")
  local report = bot.run(st, { days = days })
  print("BOT REPORT day", report.day, "phase", report.phase, "alive", report.alive, "deaths", tostring(report.deaths))
  print("food_days", report.food_days, "fuel_days", report.fuel_days, "checksum", report.checksum)
  for _, e in ipairs(st.log) do
    if e.event ~= "craft_started" and e.event ~= "craft_done" and e.event ~= "command_failed" then
      print("LOG", e.day, e.minute, e.event, e.char or "", e.cause or "", e.msg or "", e.disease or "", e.amount or "")
    end
  end
  for id, c in pairs(st.party.chars) do
    print("CHAR", id, c.status, string.format("hp %.1f temp %.1f food %.1f water %.1f energy %.1f mood %.1f",
      c.health.hp, c.needs.temp, c.needs.food, c.needs.water, c.needs.energy, c.needs.mood),
      c.death_day or "", c.death_cause or "")
  end
  for _, rid in ipairs(st.home.room_order) do
    print("ROOM", rid, string.format("%.1f", st.home.rooms[rid].temp), "ins", st.home.rooms[rid].insulation)
  end
  print("humidity", st.home.humidity)
  local inv = {}
  for id, e in pairs(st.home.stash.items) do inv[#inv + 1] = id .. ":" .. tostring(e.count) end
  table.sort(inv)
  print("STASH", table.concat(inv, " "))
  for _, id in ipairs(require("core.util").sorted_keys(st.home.stations)) do
    local x = st.home.stations[id]
    print("ST", id, x.kind, x.room, "hp", x.hp, "on", tostring(x.on))
  end
  print("TECH", table.concat(require("core.util").sorted_keys(st.tech.unlocked), ","))
  print("RUBBLE", st.home.rubble)
  kit_probe.check("bot", report.alive > 0)
  kit_probe.finish()
end
