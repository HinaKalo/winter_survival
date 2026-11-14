-- Thermal: G computation, insulation, heater warm-up, effective temperature.
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local sim = require("sim.sim")
local thermal = require("sim.thermal")
local home = require("sim.home")
local weather = require("sim.weather")
local balance = require("data.balance")
local inventory = require("sim.inventory")

local T = {}

function T.conductance()
  local s = assert(sim.new(31))
  -- The M3 reference shelter starts at insulation II; drop to 0 to measure the effect.
  s.home.rooms.living.insulation = 0
  home.rebuild(s)
  local before = thermal.room_g(s, "living")
  assert(before > 10, "living G " .. before)
  home.set_insulation(s, "living", 2)
  local after = thermal.room_g(s, "living")
  assert(after < before, "insulation lowers G: " .. before .. " -> " .. after)
end

local function near(a, b, eps, msg)
  assert(math.abs(a - b) <= (eps or 1e-6), (msg or "value") .. ": got " .. tostring(a) .. ", want " .. tostring(b))
end

local function env(t)
  local e = { wall = 0, hole = 0, window = 0, broken_window = 0, board = 0, door = 0, door_open = 0 }
  for k, v in pairs(t or {}) do e[k] = v end
  return e
end

-- Minimal home state around a real sim state (needs weather/stats/chars).
local function fake_home(rooms)
  local s = assert(sim.new(35))
  local order = {}
  for id in pairs(rooms) do order[#order + 1] = id end
  table.sort(order)
  for _, c in ipairs(require("sim.chars").alive(s)) do c.room = "nowhere" end
  s.home = { rooms = rooms, room_order = order, stations = {}, humidity = 45 }
  return s
end

function T.spec_g_values()
  local g = balance.thermal.g
  near(g.wall, 2.0); near(g.hole, 9.0); near(g.window, 3.0); near(g.broken_window, 7.0)
  near(g.board, 3.0); near(g.door_closed, 3.0); near(g.door_open, 14.0)
  near(g.roof_floor, 0.6); near(g.inner_wall, 0.5); near(g.inner_door_closed, 0.9); near(g.inner_door_open, 7.0)
  near(balance.thermal.insulation_mult[1], 0.7); near(balance.thermal.insulation_mult[2], 0.5)
end

function T.envelope_items()
  local function g_of(e, area)
    local s = fake_home({ r = { id = "r", area = area or 0, envelope = env(e), links = {}, insulation = 0, frost = 100, temp = 0 } })
    return thermal.room_g(s, "r")
  end
  near(g_of({ wall = 1 }), 2.0, 1e-9, "wall")
  near(g_of({ hole = 1 }), 9.0, 1e-9, "hole")
  near(g_of({ window = 1 }), 3.0, 1e-9, "window")
  near(g_of({ broken_window = 1 }), 7.0, 1e-9, "broken window")
  near(g_of({ board = 1 }), 3.0, 1e-9, "board")
  near(g_of({ door = 1 }), 3.0, 1e-9, "door closed")
  near(g_of({ door_open = 1 }), 14.0, 1e-9, "door open")
  near(g_of({}, 1), 0.6, 1e-9, "roof+floor per cell")
  near(g_of({}, 10), 6.0, 1e-9, "roof+floor 10 cells")
end

function T.inner_link_g()
  near(thermal.link_g({ walls = 1 }), 0.5)
  near(thermal.link_g({ doors = 1, open_doors = 0 }), 0.9)
  near(thermal.link_g({ doors = 1, open_doors = 1 }), 7.0)
  near(thermal.link_g({ walls = 4, doors = 2, open_doors = 1 }), 4 * 0.5 + 0.9 + 7.0)
end

-- CONTENT 6.2.4: 20-cell living room, wall 5 + broken window 2 + hole 1 + door 1.
function T.worked_example_g()
  local function room(e, ins)
    return { id = "r", area = 20, envelope = env(e), links = {}, insulation = ins or 0, frost = 100, temp = 0 }
  end
  local function equivalent(s)
    local g_env = thermal.room_g(s, "r")
    local g_link = 5.9  -- coupling to the rest of the house
    local g_rest = 123  -- the rest's own coupling to outdoors
    return g_env + g_link * g_rest / (g_link + g_rest)
  end
  local broken = { wall = 5, broken_window = 2, hole = 1, door = 1 }
  local s = fake_home({ r = room(broken) })
  near(thermal.room_g(s, "r"), 48.0, 1e-9, "envelope subtotal")
  near(equivalent(s), 53.6, 0.05, "broken house G")
  -- boarded: windows and hole become boards
  local boarded = { wall = 5, board = 3, door = 1 }
  s = fake_home({ r = room(boarded) })
  near(equivalent(s), 39.6, 0.05, "boarded G")
  s = fake_home({ r = room(boarded, 1) })
  near(equivalent(s), 30.3, 0.05, "boarded + insulation I")
  s = fake_home({ r = room(boarded, 2) })
  near(equivalent(s), 24.1, 0.05, "boarded + insulation II")
  -- steady state of the broken room: T = -15 + 1040 / 53.6 ~= +4.4
  local t = -15 + (800 + 240) / 53.6
  near(t, 4.4, 0.05, "steady state")
end

function T.insulation_scope()
  -- insulation multiplies walls, boards and roof only; doors, windows, holes stay.
  local r = { id = "r", area = 10, envelope = env({ wall = 2, board = 1, hole = 1, window = 1, broken_window = 1, door = 1, door_open = 1 }),
    links = {}, insulation = 2, frost = 100, temp = 0 }
  local s = fake_home({ r = r })
  local expect = (2 * 2.0 + 1 * 3.0 + 10 * 0.6) * 0.5 + 9.0 + 3.0 + 7.0 + 3.0 + 14.0
  near(thermal.room_g(s, "r"), expect, 1e-9)
  r.frost = 40  -- frosted: insulation drops one level (II -> I)
  local expect_frost = (2 * 2.0 + 1 * 3.0 + 10 * 0.6) * 0.7 + 9.0 + 3.0 + 7.0 + 3.0 + 14.0
  near(thermal.room_g(s, "r"), expect_frost, 1e-9)
end

function T.room_g_excludes_inner_links()
  local r = { id = "r", area = 0, envelope = env(), links = { { room = "o", walls = 4, doors = 1, open_doors = 0 } },
    insulation = 0, frost = 100, temp = 0 }
  local s = fake_home({ r = r, o = { id = "o", area = 0, envelope = env(), links = {}, insulation = 0, frost = 100, temp = 0 } })
  near(thermal.room_g(s, "r"), 0, 1e-9, "inner links are not part of G_env")
end

function T.two_room_energy_conservation()
  local g = balance.thermal.g
  local saved = g.roof_floor
  g.roof_floor = 0  -- no envelope at all: all heat A loses, B gains
  local ok, err = pcall(function()
    local link = { walls = 4, doors = 1, open_doors = 0 }
    local a = { id = "a", area = 10, envelope = env(), insulation = 0, frost = 100, temp = 20,
      links = { { room = "b", walls = 4, doors = 1, open_doors = 0 } } }
    local b = { id = "b", area = 25, envelope = env(), insulation = 0, frost = 100, temp = 0,
      links = { { room = "a", walls = 4, doors = 1, open_doors = 0 } } }
    local s = fake_home({ a = a, b = b })
    local ca, cb = thermal.heat_capacity(s, "a"), thermal.heat_capacity(s, "b")
    local before = ca * a.temp + cb * b.temp
    for _ = 1, 40 do thermal.tick(s, 5) end
    near(ca * a.temp + cb * b.temp, before, 1e-6, "total energy conserved")
    assert(a.temp < 20 and b.temp > 0, "heat flows from A to B")
    -- first-step check: heat lost by A equals heat gained by B (snapshot temps)
    local a2 = { id = "a", area = 10, envelope = env(), insulation = 0, frost = 100, temp = 20, links = { { room = "b", walls = 4, doors = 1, open_doors = 0 } } }
    local b2 = { id = "b", area = 25, envelope = env(), insulation = 0, frost = 100, temp = 0, links = { { room = "a", walls = 4, doors = 1, open_doors = 0 } } }
    local s2 = fake_home({ a = a2, b = b2 })
    thermal.tick(s2, 5)
    local lost = ca * (20 - a2.temp)
    local gained = cb * (b2.temp - 0)
    near(lost, gained, 1e-9, "A loses what B gains")
    near(lost, thermal.link_g(link) * 20 * (5 / 60), 1e-9, "Q = G_link * dT * dt")
  end)
  g.roof_floor = saved
  assert(ok, err)
end

function T.cold_cell_is_derived_and_two_sided()
  local s = assert(sim.new(36))
  s.home.rooms.living.insulation = 0
  assert(home.add_cold_cell(s))
  home.rebuild(s)
  local cell = s.home.rooms.cold_cell
  near(cell.envelope.wall, 10)
  assert(cell.envelope.door == 0, "the door is an inner link")
  -- 10 walls x 2.0 x 0.5 (II) x 0.8 + 6 cells x 0.6 x 0.5 x 0.8
  near(thermal.room_g(s, "cold_cell"), 10 * 2.0 * 0.5 * 0.8 + 6 * 0.6 * 0.5 * 0.8, 1e-9, "cold cell envelope G")
  local g_total = thermal.room_g(s, "cold_cell") + thermal.link_g(cell.links[1])
  near(g_total, 10, 0.5, "CONTENT 5.3: cold cell G ~ 10")
  -- the door is the CONTENT 5.3 cold-cell value (0.6), not the 0.9 inner door
  near(thermal.link_g(cell.links[1]), 0.6, 1e-9, "cold cell door conductance")
  near(g_total, 8 + 1.44 + 0.6, 1e-9, "CONTENT 5.3 breakdown 8 + 1.4 + 0.6")
  -- mirrored link on the host room
  local mirror
  for _, l in ipairs(s.home.rooms.living.links) do if l.room == "cold_cell" then mirror = l end end
  assert(mirror and mirror.doors == 1, "host has the mirror link")
  -- cold_cell_mult is effective
  local saved = balance.thermal.cold_cell_mult
  balance.thermal.cold_cell_mult = 1.0
  local plain = thermal.room_g(s, "cold_cell")
  balance.thermal.cold_cell_mult = saved
  assert(plain > thermal.room_g(s, "cold_cell"), "cold_cell_mult lowers G")
  -- heat leaks into the cell from the living room
  s.home.rooms.living.temp = 20
  local out = weather.outdoor_temp(s)
  cell.temp = out  -- no envelope loss at the first step: only the link can warm it
  thermal.tick(s, 5)
  assert(cell.temp > out, "cold cell gains heat through its link")
end

function T.station_heat_from_balance()
  local s = assert(sim.new(37))
  local st = s.home.stations
  local power = balance.power.station
  for _, x in pairs(st) do x.on = false end
  local stove = st.f_woodstove
  stove.on, stove.hp, stove.room = true, 100, "living"
  stove.level = "low"
  near(thermal.station_heat(s, "living"), power.f_woodstove_low.heat)
  stove.level = "full"
  near(thermal.station_heat(s, "living"), power.f_woodstove.heat)
  stove.on = false
  local hearth = st.f_hearth
  hearth.on, hearth.hp = true, 100
  near(thermal.station_heat(s, hearth.room), power.f_hearth.heat)
end

function T.hearth_humidity_only_while_cooking()
  local recipe = assert(require("data.recipes").get("boil_water"))
  assert(recipe.station == "hearth" or recipe.station == "hearth2", "boil_water uses the hearth")
  local function humidity_after_hour(with_job)
    local s = assert(sim.new(38))
    for _, c in ipairs(require("sim.chars").alive(s)) do c.activity = "out" end
    local c = s.party.chars[s.party.order[1]]
    c.activity = "work"
    for _, st in pairs(s.home.stations) do st.on = false end
    s.home.stations.f_hearth.on = true  -- lit but nobody cooking
    s.home.humidity = balance.humidity.outdoor  -- no drift
    if with_job then
      s.jobs["job_x"] = { id = "job_x", kind = "craft", recipe = "boil_water", actor = c.id,
        waiting = false, work_remaining = 5, wait_remaining = 0 }
      c.job = "job_x"
    end
    assert(home.cooking_active(s) == with_job)
    home.tick(s, 60)
    return s.home.humidity
  end
  local idle = humidity_after_hour(false)
  local cooking = humidity_after_hour(true)
  near(cooking - idle, balance.humidity.sources.hearth, 1e-9, "cooking adds +1.5/h")
end


function T.cold_cell_door_g_from_balance()
  local s = assert(sim.new(61))
  assert(home.add_cold_cell(s))
  local cell = s.home.rooms.cold_cell
  local host
  for _, l in ipairs(s.home.rooms.living.links) do if l.room == "cold_cell" then host = l end end
  near(thermal.link_g(cell.links[1]), balance.thermal.cold_cell_door_g, 1e-9)
  near(thermal.link_g(host), balance.thermal.cold_cell_door_g, 1e-9, "mirror side too")
  local saved = balance.thermal.cold_cell_door_g
  balance.thermal.cold_cell_door_g = 2.0
  local g = thermal.link_g(cell.links[1])
  balance.thermal.cold_cell_door_g = saved
  near(g, 2.0, 1e-9, "door G is read from balance")
  -- an ordinary inner door keeps 0.9
  near(thermal.link_g({ walls = 0, doors = 1, open_doors = 0 }), 0.9, 1e-9)
end

function T.cold_cell_constants_from_balance()
  local saved = {}
  local cc = balance.thermal.cold_cell_room
  for k, v in pairs(cc) do saved[k] = v end
  cc.area, cc.wall, cc.insulation = 8, 12, 1
  local ok, err = pcall(function()
    local s = assert(sim.new(62))
    assert(home.add_cold_cell(s))
    local cell = s.home.rooms.cold_cell
    assert(cell.area == 8 and cell.envelope.wall == 12 and cell.insulation == 1)
    near(thermal.room_g(s, "cold_cell"),
      12 * 2.0 * 0.7 * balance.thermal.cold_cell_mult + 8 * 0.6 * 0.7 * balance.thermal.cold_cell_mult, 1e-9)
    home.rebuild(s)
    assert(s.home.rooms.cold_cell.envelope.wall == 12, "rebuild keeps the balance wall count")
  end)
  for k, v in pairs(saved) do cc[k] = v end
  assert(ok, err)
end

function T.wind_chill_on_every_cold_wave_day()
  local s = assert(sim.new(63))
  local snap = s.weather.snaps[1]
  assert(snap.kind ~= "big", "first snap is a small one")
  s.clock.day = snap.start_day
  near(weather.wind_chill(s), 5, 1e-9, "small cold wave day has wind chill")
  local ch = s.party.chars[s.party.order[1]]
  ch.activity = "out"
  local function offset() return thermal.effective_temp(s, ch) - weather.outdoor_temp(s) end
  local with = offset()
  s.clock.day = 1
  assert(not weather.snap_on(s, 1), "day 1 is no cold wave day")
  near(weather.wind_chill(s), 0, 1e-9)
  near(with - offset(), -5, 1e-9, "E is 5 lower outdoors on a small cold-wave day")
  -- big cold wave too
  local big
  for _, sn in ipairs(s.weather.snaps) do if sn.kind == "big" then big = sn end end
  s.clock.day = big.start_day
  near(weather.wind_chill(s), 5, 1e-9)
end

function T.cooking_adds_stove_heat()
  local function heat(cooking)
    local s = assert(sim.new(64))
    for _, c in ipairs(require("sim.chars").alive(s)) do c.activity = "out" end
    for _, st in pairs(s.home.stations) do st.on = false end
    local c = s.party.chars[s.party.order[1]]
    c.activity = "work"
    s.home.stations.f_hearth.on = true
    if cooking then
      s.jobs["job_c"] = { id = "job_c", kind = "craft", recipe = "boil_water", actor = c.id,
        waiting = false, work_remaining = 5, wait_remaining = 0 }
      c.job = "job_c"
    end
    return thermal.station_heat(s, s.home.stations.f_hearth.room)
  end
  near(heat(true) - heat(false), 400, 1e-9, "+400 W while cooking")
  near(heat(false), balance.power.station.f_hearth.heat, 1e-9)
end


function T.ranch_a_starting_broken_windows_apply()
  local s = assert(sim.new(65))
  local tmpl = require("data.homes.ranch_a")
  local list = tmpl.variants.A.damage.broken_windows
  assert(#list == 2, "template key is broken_windows")
  assert(tmpl.variants.A.damage.windows_broken == nil, "no second spelling")
  local n = 0
  for _, p in ipairs(list) do
    local w = s.home.structure.windows[p[1] .. "," .. p[2]]
    assert(w and w.broken, "window " .. p[1] .. "," .. p[2] .. " starts broken")
    n = n + 1
  end
  local total = 0
  for _, id in ipairs(s.home.room_order) do total = total + s.home.rooms[id].envelope.broken_window end
  assert(total == n, "broken windows reach the envelope, got " .. total)
end

return T
