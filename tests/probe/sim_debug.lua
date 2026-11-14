function _probe()
  kit_probe.timeout(300)
  package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path
  local sim = require("sim.sim")
  local chars = require("sim.chars")
  local st = assert(sim.new(12345))
  for step = 1, 24 do
    sim.step(st, 60)
    local parts = {}
    for _, c in ipairs(chars.alive(st)) do
      parts[#parts + 1] = string.format("%s f%.0f w%.0f e%.0f t%.0f hp%.0f", c.id, c.needs.food, c.needs.water, c.needs.energy, c.needs.temp, c.health.hp)
    end
    print("H", step, require("sim.clock").clock_text(st), "alive", #chars.alive(st), table.concat(parts, " | "), "room", string.format("%.1f", st.home.rooms.living.temp))
    if st.clock.phase == "ending" then break end
  end
  local sum = sim.summary(st)
  for _, d in ipairs(sum.dead) do print("DEAD", d.id, d.day, d.cause) end
  kit_probe.check("debug", true)
  kit_probe.finish()
end
