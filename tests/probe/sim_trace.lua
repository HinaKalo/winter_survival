function _probe()
  package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path
  local sim = require("sim.sim")
  local chars = require("sim.chars")
  local st = assert(sim.new(12345))
  local id = st.party.order[1]
  for i = 1, 40 do
    sim.step(st, 15)
    local c = st.party.chars[id]
    print("T", i, require("sim.clock").clock_text(st), "day", st.clock.day, "act", c.activity,
      string.format("room %.1f temp %.1f hp %.1f food %.0f water %.0f", st.home.rooms[c.room].temp, c.needs.temp, c.health.hp, c.needs.food, c.needs.water))
    if c.status ~= "alive" or st.clock.phase == "ending" then break end
  end
  kit_probe.check("trace", true)
  kit_probe.finish()
end
