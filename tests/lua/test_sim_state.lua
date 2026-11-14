-- State root: new run, validation, serialization roundtrip, same-seed determinism.
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local sim = require("sim.sim")
local state = require("sim.state")

local T = {}

function T.new_run()
  local s, err = sim.new(12345)
  assert(s, err)
  local ok, verr = state.validate(s)
  assert(ok, verr)
  assert(#s.party.order == 4)
  local have_home, have_field = false, false
  for _, id in ipairs(s.party.order) do
    local c = s.party.chars[id]
    assert(c and c.status == "alive")
    assert(type(c.values.compassion) == "number")
    if c.role == "home" then have_home = true end
    if c.role == "field" then have_field = true end
  end
  assert(have_home and have_field, "party must contain both roles")
  assert(s.home.rooms.living, "home rooms")
  assert(s.home.stations.f_hearth, "starting stove")
  assert(s.tech.unlocked.t_hearth, "stove tech")
  assert(#s.weather.snaps >= 3, "snap schedule")
  assert(s.weather.snaps[#s.weather.snaps].kind == "big")
end

function T.serialize_roundtrip()
  local s = assert(sim.new(99))
  local text = state.encode(s)
  local s2, err = state.decode(text)
  assert(s2, err)
  assert(state.encode(s2) == text, "roundtrip must be byte-identical")
  assert(state.checksum(s) == state.checksum(s2))
end

function T.same_seed_deterministic()
  local a = assert(sim.new(7))
  local b = assert(sim.new(7))
  assert(state.encode(a) == state.encode(b), "same seed must produce the same state")
end

function T.bad_state_rejected()
  local s = assert(sim.new(1))
  s.clock.minute = 5000
  local ok = state.validate(s)
  assert(not ok)
  s = assert(sim.new(1))
  local cid = s.party.order[1]
  s.party.chars[cid].health.hp = -5
  assert(not state.validate(s))
end

return T
