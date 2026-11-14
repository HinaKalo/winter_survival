-- Reference bot: repaired devices are actually used (M3 bug pass).
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local sim = require("sim.sim")
local bot = require("sim.bot")
local inventory = require("sim.inventory")
local state_mod = require("sim.state")

local T = {}

function T.repaired_electric_heater_is_used()
  local s = assert(sim.new(71))
  local gen = s.home.stations.f_generator
  local heater = s.home.stations.f_electric_heater
  gen.hp = 100
  gen.on = false
  heater.hp = 100
  heater.on = false
  s.home.rooms.living.temp = -10
  assert(inventory.count(s.home.stash, "gasoline") >= 1)

  bot.morning(s)
  assert(gen.on, "bot starts the generator for the heater")
  assert(heater.on, "bot turns on a repaired electric heater")
end

function T.heater_off_when_room_is_warm()
  local s = assert(sim.new(72))
  local gen = s.home.stations.f_generator
  local heater = s.home.stations.f_electric_heater
  gen.hp = 100
  gen.on = false
  heater.hp = 100
  heater.on = true
  s.home.rooms.living.temp = 20

  bot.morning(s)
  assert(heater.on ~= true, "warm room does not need the electric heater")
end

function T.run_does_not_add_a_kit()
  local plain = assert(sim.new(73))
  local report = bot.run(plain, { days = 1 })
  assert(report.day >= 1)
  assert(rawget(plain, "_bot_kit") == nil, "no root marker field")
  assert(plain.opts.kit == nil)
  assert(plain.tech.blueprints.t_bench3 == nil, "no kit blueprints without opts.kit")
  for _, e in ipairs(plain.log) do assert(e.event ~= "bot_kit_applied") end
  local kit = assert(sim.new(73, { kit = "bot" }))
  assert(kit.tech.blueprints.t_bench3, "the kit arrives via sim.new")
  assert(state_mod.checksum(plain) ~= state_mod.checksum(kit))
end

function T.guard_and_out_chars_get_no_night_jobs()
  local s = assert(sim.new(74, { kit = "bot" }))
  while s.clock.phase ~= "night" do sim.step(s, 1) end
  local out, guard = s.party.order[1], s.party.order[2]
  s.party.chars[out].activity = "out"
  s.party.chars[guard].activity = "guard"
  bot.manage(s)
  assert(s.party.chars[out].job == nil and s.party.chars[out].activity == "out")
  assert(s.party.chars[guard].job == nil and s.party.chars[guard].activity == "guard")
end

function T.bot_resumes_paused_jobs()
  local s = assert(sim.new(75, { kit = "bot" }))
  local ch = s.party.chars[s.party.order[1]]
  bot.morning(s)
  local holder
  for _, id in ipairs(s.party.order) do
    if s.party.chars[id].job then holder = s.party.chars[id] break end
  end
  assert(holder, "morning starts at least one job")
  local job = holder.job
  holder.activity = "idle"
  bot.manage(s)
  assert(holder.job == job and holder.activity == "work", "paused job is resumed, not replaced")
  local _ = ch
end

return T
