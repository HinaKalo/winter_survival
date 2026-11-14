function _probe()
  package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path
  local sim = require("sim.sim")
  local thermal = require("sim.thermal")
  local st = assert(sim.new(12345))
  for _, rid in ipairs(st.home.room_order) do
    local r = st.home.rooms[rid]
    print("R", rid, "area", r.area, "G", string.format("%.1f", thermal.room_g(st, rid)),
      "env", r.envelope.wall, r.envelope.window, r.envelope.broken_window, r.envelope.hole, r.envelope.board, r.envelope.door)
  end
  local kit = st.home.rooms.kitchen
  st.home.stations.f_hearth.on = true
  print("kitchen", kit.temp)
  for i = 1, 12 do
    sim.step(st, 60)
    print("H", i, string.format("%.1f", kit.temp), string.format("%.1f", st.home.rooms.living.temp), "firewood", require("sim.inventory").count(st.home.stash, "firewood"))
    local c = st.party.chars[st.party.order[1]]
    print("  char", c.activity, c.room, string.format("body %.1f hp %.1f", c.needs.temp, c.health.hp))
  end
  kit_probe.check("g", true)
  kit_probe.finish()
end
