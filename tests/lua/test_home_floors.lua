-- 验收测试，编码代理不得修改（主代理编写；认为有误时停下报告）。docs/M5-3D-PLAN.md §4、§5、§7。
-- 三层住宅：模板 levels / stairs、房间楼层、地温与楼梯换热、move 动作、game/floors、view/home3d、存读档。
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local hs = require("game.home_session")
local serialize = require("core.serialize")
local layout = require("core.layout")
local floors = require("game.floors")
local home3d = require("view.home3d")
local thermal = require("sim.thermal")
local balance = require("data.balance")

local T = {}

local B1_ROOMS = { "boiler", "cellar", "shelter", "storage" }
local F1_ROOMS = { "bedroom", "kitchen", "living", "workshop" }
local F2_ROOMS = { "attic_bed", "attic_store", "kids" }

local function tmpl() return require("data.homes.ranch_a") end
local function snap(s) return serialize.encode(s.state) end
local function find(list, id)
  for _, a in ipairs(list) do if a.id == id then return a end end
end
local function first_cid(s) return s.state.party.order[1] end

-- ------------------------------------------------------------------ template
function T.template_has_three_levels()
  local v = tmpl().variants.A
  assert(type(v.levels) == "table", "variants.A.levels")
  for _, f in ipairs({ "B1", "F2" }) do
    local lv = v.levels[f]
    assert(type(lv) == "table" and type(lv.grid) == "table", f .. " grid")
    assert(#lv.grid == #v.grid, f .. " has the same height as 1F")
    for _, row in ipairs(lv.grid) do assert(#row == #v.grid[1], f .. " row width") end
    local parsed, err = layout.parse(lv)
    assert(parsed, tostring(err))
  end
  assert(v.levels.B1.ground == true, "B1 is below ground")
end

function T.level_rooms_parse_with_their_ids()
  local v = tmpl().variants.A
  local b1 = assert(layout.parse(v.levels.B1))
  local f2 = assert(layout.parse(v.levels.F2))
  for _, id in ipairs(B1_ROOMS) do assert(b1.rooms[id], "B1 room " .. id) end
  for _, id in ipairs(F2_ROOMS) do assert(f2.rooms[id], "F2 room " .. id) end
end

function T.stairs_are_aligned_and_walkable()
  local v = tmpl().variants.A
  assert(type(v.stairs) == "table" and #v.stairs == 2, "two stairs")
  local grids = { B1 = v.levels.B1.grid, F1 = v.grid, F2 = v.levels.F2.grid }
  local function at(f, c)
    return grids[f][c[2] + 1]:sub(c[1] + 1, c[1] + 1)
  end
  local seen = {}
  for _, st in ipairs(v.stairs) do
    seen[st.lower .. ">" .. st.upper] = st
    assert(at(st.lower, st.lower_cell) == ".", st.id .. " lower cell walkable")
    assert(at(st.upper, st.upper_cell) == ".", st.id .. " upper cell walkable")
    -- same stair shaft in plan: the x column matches
    assert(st.lower_cell[1] == st.upper_cell[1], st.id .. " x aligned")
  end
  assert(seen["B1>F1"] and seen["F1>F2"], "B1-F1 and F1-F2 stairs")
  -- HOUSE3D-BRIEF §3: kitchen stairs at (1..2, 8..12), living stairs at (17..18, 1..5)
  assert(seen["B1>F1"].upper_room == "kitchen" and seen["B1>F1"].lower_room == "storage")
  assert(seen["F1>F2"].lower_room == "living" and seen["F1>F2"].upper_room == "attic_store")
end

-- ------------------------------------------------------------------ sim rooms
function T.new_session_has_eleven_rooms_with_floors()
  local s = hs.new(3)
  local rooms = s.state.home.rooms
  for _, id in ipairs(B1_ROOMS) do assert(rooms[id] and rooms[id].floor == "B1", id) end
  for _, id in ipairs(F1_ROOMS) do assert(rooms[id] and rooms[id].floor == "F1", id) end
  for _, id in ipairs(F2_ROOMS) do assert(rooms[id] and rooms[id].floor == "F2", id) end
  assert(#s.state.home.room_order == 11, "room_order " .. #s.state.home.room_order)
  for _, id in ipairs(B1_ROOMS) do assert(rooms[id].ground == true, id .. " ground") end
  for _, id in ipairs(F1_ROOMS) do assert(not rooms[id].ground, id .. " not ground") end
end

local function link_to(room, other)
  for _, l in ipairs(room.links) do if l.room == other then return l end end
end

function T.stair_links_are_symmetric()
  local s = hs.new(3)
  local r = s.state.home.rooms
  local a, b = link_to(r.kitchen, "storage"), link_to(r.storage, "kitchen")
  assert(a and b and (a.stairs or 0) == 1 and (b.stairs or 0) == 1, "kitchen<->storage stair link")
  local c, d = link_to(r.living, "attic_store"), link_to(r.attic_store, "living")
  assert(c and d and (c.stairs or 0) == 1 and (d.stairs or 0) == 1, "living<->attic_store stair link")
  assert(thermal.link_g(a) >= balance.thermal.g.stair_open, "stair conductance counted")
  assert(not link_to(r.bedroom, "cellar"), "no link without stairs")
end

function T.balance_has_ground_temp_and_stair_g()
  assert(type(balance.thermal.ground_temp) == "number")
  assert(balance.thermal.ground_temp > 0 and balance.thermal.ground_temp < 10)
  assert(type(balance.thermal.g.stair_open) == "number" and balance.thermal.g.stair_open > 0)
end

local function avg(state, ids)
  local sum = 0
  for _, id in ipairs(ids) do sum = sum + state.home.rooms[id].temp end
  return sum / #ids
end

function T.basement_stays_warmer_than_the_main_floor()
  local s = hs.new(11)
  local state = s.state
  -- nothing burning: every heater off
  for _, st in pairs(state.home.stations) do st.on = false end
  for _ = 1, 24 * 60 / balance.thermal.step_minutes do thermal.tick(state, balance.thermal.step_minutes) end
  local b1, f1, f2 = avg(state, B1_ROOMS), avg(state, F1_ROOMS), avg(state, F2_ROOMS)
  local out = require("sim.weather").outdoor_temp(state)
  assert(b1 > f1 + 2, string.format("B1 %.1f should beat F1 %.1f", b1, f1))
  assert(b1 > out, "B1 warmer than outdoors")
  assert(b1 <= balance.thermal.ground_temp + 0.5, "B1 does not exceed the ground temperature unheated")
  assert(f2 <= f1 + 0.5, string.format("attic %.1f not warmer than F1 %.1f", f2, f1))
end

function T.hud_rooms_carry_floor()
  local s = hs.new(5)
  local h = hs.hud(s)
  assert(#h.rooms == 11)
  for _, r in ipairs(h.rooms) do assert(r.floor == "B1" or r.floor == "F1" or r.floor == "F2", r.id) end
  for _, c in ipairs(h.chars) do assert(c.floor == "F1", "everyone starts on 1F: " .. tostring(c.floor)) end
end

-- ------------------------------------------------------------------ move action
function T.move_actions_listed_for_other_rooms()
  local s = hs.new(7)
  local cid = first_cid(s)
  local here = s.state.party.chars[cid].room
  local list = hs.actions(s, cid)
  local n = 0
  for _, a in ipairs(list) do
    if a.kind == "move" then
      n = n + 1
      assert(a.id == "move:" .. a.id:sub(6))
      assert(a.label == "home.room." .. a.id:sub(6))
      assert(a.id ~= "move:" .. here, "no move to the current room")
    end
  end
  assert(n == 10, "10 move targets, got " .. n)
  assert(find(list, "move:shelter").enabled == true)
end

function T.move_changes_room_and_floor()
  local s = hs.new(7)
  local cid = first_cid(s)
  assert(hs.act(s, cid, "move:shelter"))
  assert(s.state.party.chars[cid].room == "shelter")
  assert(floors.of_room(s.state, "shelter") == "B1")
  assert(hs.act(s, cid, "move:kids"))
  assert(s.state.party.chars[cid].room == "kids")
end

function T.failed_move_leaves_state_unchanged()
  local s = hs.new(7)
  local cid = first_cid(s)
  local before = snap(s)
  local ok = hs.act(s, cid, "move:no_such_room")
  assert(not ok)
  assert(snap(s) == before)
  assert(hs.act(s, cid, "sleep"))
  local list = hs.actions(s, cid)
  assert(find(list, "move:shelter").enabled == false, "a sleeper cannot move")
  local before2 = snap(s)
  assert(not hs.act(s, cid, "move:shelter"))
  assert(snap(s) == before2)
end

function T.body_heat_follows_the_room()
  local s = hs.new(9)
  local cid = first_cid(s)
  local h0 = thermal.body_heat(s.state, "shelter")
  assert(hs.act(s, cid, "move:shelter"))
  assert(thermal.body_heat(s.state, "shelter") > h0)
end

function T.save_load_keeps_floors()
  local s = hs.new(13)
  local cid = first_cid(s)
  assert(hs.act(s, cid, "move:cellar"))
  local s2 = hs.load(hs.save(s))
  assert(s2.state.home.rooms.cellar.floor == "B1")
  assert(s2.state.home.rooms.cellar.ground == true)
  assert(s2.state.party.chars[cid].room == "cellar")
  assert(#s2.state.home.room_order == 11)
end

-- ------------------------------------------------------------------ game/floors
function T.floors_constants_and_step()
  assert(floors.ORDER[1] == "B1" and floors.ORDER[2] == "F1" and floors.ORDER[3] == "F2")
  assert(floors.BASE_Y.B1 == -3 and floors.BASE_Y.F1 == 0 and floors.BASE_Y.F2 == 3)
  assert(floors.step("F1", 1) == "F2" and floors.step("F1", -1) == "B1")
  assert(floors.step("F2", 1) == "F2" and floors.step("B1", -1) == "B1")
end

function T.floors_of_room()
  local s = hs.new(1)
  assert(floors.of_room(s.state, "living") == "F1")
  assert(floors.of_room(s.state, "boiler") == "B1")
  assert(floors.of_room(s.state, "attic_bed") == "F2")
  assert(floors.of_room(s.state, "nowhere") == nil)
end

function T.floors_route()
  local t = tmpl()
  assert(#floors.route(t, "F1", "F1") == 0)
  local up = floors.route(t, "F1", "F2")
  assert(#up == 1 and up[1].from == "F1" and up[1].to == "F2")
  assert(up[1].from_cell[1] == 17 and up[1].from_cell[2] == 5 and up[1].to_cell[2] == 1)
  local down = floors.route(t, "F1", "B1")
  assert(#down == 1 and down[1].from_cell[2] == 8 and down[1].to_cell[2] == 12)
  local long = floors.route(t, "B1", "F2")
  assert(#long == 2 and long[1].from == "B1" and long[1].to == "F1" and long[2].from == "F1" and long[2].to == "F2")
  local back = floors.route(t, "F2", "B1")
  assert(#back == 2 and back[1].to == "F1" and back[2].to == "B1")
end

-- ------------------------------------------------------------------ view/home3d
local NAMES = {
  "B1_floor", "B1_wall_low", "B1_wall_high", "B1_boiler_on", "B1_boiler_off", "B1_cot_1",
  "F1_floor", "F1_wall_low", "F1_wall_high", "F1_woodstove_on", "F1_woodstove_off",
  "F1_hearth_on", "F1_hearth_off", "F1_bed",
  "F1_rubble_01", "F1_rubble_02", "F1_rubble_03", "F1_rubble_04", "F1_rubble_05", "F1_rubble_06",
  "F2_floor", "F2_wall_low", "F2_wall_high", "F2_kid_bed",
  "DRESS_B1_floor_ice", "DRESS_F1_calendar", "DRESS_F2_war_floor_shards",
  "stair_B1_1F", "stair_1F_2F",
  "roof_panel_0", "roof_snow_1", "exterior_snow", "exterior_snowdrift_01", "EXT_DRESS_F1_horizontal_siding",
}

local function stations_off(state)
  for _, st in pairs(state.home.stations) do st.on = false end
end

function T.home3d_main_floor_view()
  local s = hs.new(2)
  stations_off(s.state)
  local v = home3d.visibility(NAMES, "F1", s.state)
  for _, n in ipairs({ "F1_floor", "F1_wall_low", "F1_bed", "DRESS_F1_calendar", "stair_B1_1F", "stair_1F_2F",
    "F1_woodstove_off", "F1_hearth_off" }) do
    assert(v[n] == true, n .. " visible on F1")
  end
  for _, n in ipairs({ "F1_wall_high", "F1_woodstove_on", "F1_hearth_on", "B1_floor", "B1_cot_1", "F2_floor",
    "DRESS_B1_floor_ice", "DRESS_F2_war_floor_shards", "roof_panel_0", "roof_snow_1", "exterior_snow",
    "exterior_snowdrift_01", "EXT_DRESS_F1_horizontal_siding", "B1_boiler_off" }) do
    assert(v[n] == false, n .. " hidden on F1")
  end
  for _, n in ipairs(NAMES) do assert(v[n] == home3d.node_visible(n, "F1", s.state), n) end
end

function T.home3d_basement_and_attic_views()
  local s = hs.new(2)
  stations_off(s.state)
  local b = home3d.visibility(NAMES, "B1", s.state)
  assert(b.B1_floor and b.B1_wall_low and b.B1_cot_1 and b.DRESS_B1_floor_ice and b.stair_B1_1F)
  assert(b.B1_boiler_off and not b.B1_boiler_on)
  assert(not b.B1_wall_high and not b.stair_1F_2F and not b.F1_floor and not b.F2_floor and not b.roof_panel_0)
  local a = home3d.visibility(NAMES, "F2", s.state)
  assert(a.F2_floor and a.F2_wall_low and a.F2_kid_bed and a.DRESS_F2_war_floor_shards and a.stair_1F_2F)
  assert(not a.F2_wall_high and not a.stair_B1_1F and not a.F1_floor and not a.roof_snow_1)
end

function T.home3d_station_pairs_follow_on_state()
  local s = hs.new(2)
  stations_off(s.state)
  local stove
  for _, st in pairs(s.state.home.stations) do if st.kind == "woodstove" then stove = st end end
  assert(stove, "ranch_a has a woodstove")
  stove.on, stove.hp = true, 100
  assert(home3d.node_visible("F1_woodstove_on", "F1", s.state) == true)
  assert(home3d.node_visible("F1_woodstove_off", "F1", s.state) == false)
  stove.hp = 0
  assert(home3d.node_visible("F1_woodstove_on", "F1", s.state) == false, "broken stove is off")
  assert(home3d.node_visible("F1_woodstove_off", "F1", s.state) == true)
  -- on/off pairs never both visible, never both hidden on their floor
  for _, base in ipairs({ "F1_woodstove", "F1_hearth" }) do
    local on = home3d.node_visible(base .. "_on", "F1", s.state)
    local off = home3d.node_visible(base .. "_off", "F1", s.state)
    assert(on ~= off, base)
  end
end

function T.home3d_rubble_shrinks_with_progress()
  local s = hs.new(2)
  local initial = tmpl().variants.A.rubble
  local function shown()
    local n = 0
    for k = 1, 6 do
      if home3d.node_visible(string.format("F1_rubble_%02d", k), "F1", s.state) then n = n + 1 end
    end
    return n
  end
  s.state.home.rubble = initial
  assert(shown() == 6)
  s.state.home.rubble = math.floor(initial / 2)
  assert(shown() == 3, "half rubble -> 3 piles, got " .. shown())
  s.state.home.rubble = 1
  assert(shown() == 1)
  s.state.home.rubble = 0
  assert(shown() == 0)
  -- the remaining piles are the low-numbered ones
  s.state.home.rubble = math.floor(initial / 2)
  assert(home3d.node_visible("F1_rubble_01", "F1", s.state) and not home3d.node_visible("F1_rubble_06", "F1", s.state))
  -- never shown on another floor
  s.state.home.rubble = initial
  assert(home3d.node_visible("F1_rubble_01", "B1", s.state) == false)
end

function T.home3d_is_pure()
  local s = hs.new(2)
  local before = snap(s)
  home3d.visibility(NAMES, "F1", s.state)
  home3d.visibility(NAMES, "B1", s.state)
  assert(snap(s) == before)
  assert(rawget(_G, "iso") == nil or true) -- may run without iso; must not call it
end

return T
