function _probe()
  kit_probe.timeout(300)
  package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path
  local sim = require("sim.sim")
  local bot = require("sim.bot")
  local chars = require("sim.chars")
  local st = assert(sim.new(12345))
  local last_morning, last_dusk, last_night, last_dawn = 0, 0, 0, 0
  local squad = {}
  for i = 1, 1440 * 2 do
    local day, phase = st.clock.day, st.clock.phase
    if phase == "day" then
      if last_morning ~= day then last_morning = day; bot.morning(st) end
      bot.manage(st)
    elseif phase == "dusk" then
      if last_dusk ~= day then last_dusk = day; squad = bot.dusk(st) or {} end
    elseif phase == "night" then
      if last_night ~= day then last_night = day; bot.night_start(st, squad) end
      bot.manage(st)
    elseif phase == "dawn" then
      if last_dawn ~= day then last_dawn = day; bot.dawn(st) end
    end
    sim.step(st, 1)
    if i % 60 == 0 or #chars.alive(st) < 4 then
      local parts = {}
      for _, c in ipairs(chars.alive(st)) do
        parts[#parts + 1] = string.format("%s:%s@%s body%.0f hp%.0f", c.id, c.activity:sub(1, 3), c.room, c.needs.temp, c.health.hp)
      end
      print("T", i, day, require("sim.clock").clock_text(st), phase, "kitchen", string.format("%.1f", st.home.rooms.kitchen.temp),
        "living", string.format("%.1f", st.home.rooms.living.temp), table.concat(parts, " "))
    end
    if st.clock.phase == "ending" then break end
  end
  for _, e in ipairs(st.log) do
    if e.event == "char_died" or e.event == "disease" then print("LOG", e.day, e.minute, e.event, e.char or "", e.cause or "", e.disease or "") end
  end
  kit_probe.check("trace", true)
  kit_probe.finish()
end
