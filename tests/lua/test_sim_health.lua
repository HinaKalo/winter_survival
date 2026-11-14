-- Health: wound bands, healing, disease, treatment, death.
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local sim = require("sim.sim")
local chars = require("sim.chars")
local health = require("sim.health")
local inventory = require("sim.inventory")
local state_mod = require("sim.state")

local T = {}

local function first(state)
  return state.party.chars[state.party.order[1]]
end

function T.wound_bands()
  local s = assert(sim.new(21))
  local c = first(s)
  c.health.hp = 100
  assert(chars.wound(c) == "healthy")
  c.health.hp = 70
  assert(chars.wound(c) == "light")
  c.health.hp = 30
  assert(chars.wound(c) == "heavy")
  c.health.hp = 5
  assert(chars.wound(c) == "critical")
end

function T.add_wound_and_death()
  local s = assert(sim.new(22))
  local c = first(s)
  health.add_wound(s, c, 40, "test")
  assert(c.health.hp == 60 and chars.wound(c) == "light")
  local id = c.id
  health.add_wound(s, c, 100, "test")
  assert(c.status == "dead")
  for _, v in ipairs(s.party.order) do assert(v ~= id, "dead char removed from order") end
  local ok = state_mod.validate(s)
  assert(ok, "valid after death")
end

function T.healing()
  local s = assert(sim.new(23))
  local c = first(s)
  c.health.hp = 70
  c.health.bandage_hours = 12
  local before = c.health.hp
  health.tick(s, 60)
  assert(c.health.hp > before, "bandaged light wound heals")
end

function T.disease_and_treatment()
  local s = assert(sim.new(24))
  local c = first(s)
  local actor = c
  assert(health.add_disease(s, c, "cold"))
  assert(c.health.disease.cold)
  inventory.add(s.home.stash, "cold_medicine", 2, { force = true })
  assert(health.treat(s, c, actor, "cold_medicine"))
  assert(c.health.disease.cold.hours <= 36)
  assert(c.health.disease.cold.no_pneumonia == 24)
end

function T.frostbite_and_antiseptic()
  local s = assert(sim.new(25))
  local c = first(s)
  assert(health.add_disease(s, c, "frostbite"))
  inventory.add(s.home.stash, "antiseptic", 2, { force = true })
  assert(health.treat(s, c, c, "antiseptic"))
  assert(c.health.disease.frostbite.treated)
end

function T.hypothermia_damages()
  local s = assert(sim.new(26))
  local c = first(s)
  c.needs.temp = 5
  local hp = c.health.hp
  health.tick(s, 60)
  assert(c.health.hp < hp, "hypothermia drains hp")
end

function T.infection_false_is_not_true()
  local s = assert(sim.new(27))
  local c = first(s)
  c.health.infection = false
  local hp = c.health.hp
  health.daily(s)
  assert(c.health.hp == hp, "infection=false must not deal infection damage")
  assert(c.health.infection == false)
end

return T
