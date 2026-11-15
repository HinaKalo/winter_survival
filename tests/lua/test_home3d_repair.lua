-- 验收测试，编码代理不得修改（主代理编写；认为有误时停下报告）。docs/M5-FIX-PLAN.md §3、§5。
-- 修复后的家具和封堵：残骸 / _fixed 成对切换，窗户木板、墙洞木板跟着 structure 状态显示，
-- home3d.signature(state) 在这些状态变化时必须变化（场景据此刷新模型）。
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local hs = require("game.home_session")
local home = require("sim.home")
local home3d = require("view.home3d")

local T = {}

local REPAIRABLE = {
  { node = "F1_electric_heater", kind = "electric_heater" },
  { node = "F1_generator", kind = "generator" },
  { node = "F1_humidifier", kind = "humidifier" },
}

local function station_of(state, kind)
  for _, st in pairs(state.home.stations) do if st.kind == kind then return st end end
end

local function board_name(w)
  return (w.floor or "F1") .. "_window_board_" .. tostring(w.x) .. "_" .. tostring(w.y)
end

local function vis(name, floor, state) return home3d.node_visible(name, floor, state) end

-- ------------------------------------------------------------------ repaired stations
function T.broken_stations_show_the_wreck_only()
  local s = hs.new(2)
  for _, r in ipairs(REPAIRABLE) do
    local st = station_of(s.state, r.kind)
    assert(st and st.hp == 0, r.kind .. " starts broken in ranch_a")
    assert(vis(r.node, "F1", s.state) == true, r.node .. " wreck visible while broken")
    assert(vis(r.node .. "_fixed", "F1", s.state) == false, r.node .. "_fixed hidden while broken")
  end
end

function T.repaired_station_swaps_wreck_for_fixed_model()
  for _, r in ipairs(REPAIRABLE) do
    local s = hs.new(2)
    local st = station_of(s.state, r.kind)
    assert(home.repair_station(s.state, st.id), "repair " .. st.id)
    assert(vis(r.node .. "_fixed", "F1", s.state) == true, r.node .. "_fixed visible after repair")
    assert(vis(r.node, "F1", s.state) == false, r.node .. " wreck hidden after repair")
    -- on / off does not matter: a repaired device that is switched off is still standing there
    st.on = true
    assert(vis(r.node .. "_fixed", "F1", s.state) == true, r.node .. "_fixed visible while on")
    -- breaks again (power.lua sets hp = 0) -> back to the wreck
    st.hp = 0
    assert(vis(r.node, "F1", s.state) == true and vis(r.node .. "_fixed", "F1", s.state) == false,
      r.node .. " wreck again after breakdown")
  end
end

function T.fixed_models_respect_the_viewed_floor()
  local s = hs.new(2)
  for _, r in ipairs(REPAIRABLE) do
    home.repair_station(s.state, station_of(s.state, r.kind).id)
    for _, f in ipairs({ "B1", "F2" }) do
      assert(vis(r.node .. "_fixed", f, s.state) == false, r.node .. "_fixed hidden on " .. f)
      assert(vis(r.node, f, s.state) == false, r.node .. " hidden on " .. f)
    end
  end
end

-- ------------------------------------------------------------------ window and hole boards
function T.window_boards_follow_boarded_state_on_every_floor()
  local s = hs.new(2)
  local n = 0
  for _, w in pairs(s.state.home.structure.windows) do
    n = n + 1
    local name, f = board_name(w), (w.floor or "F1")
    assert(w.boarded ~= true, name .. " starts unboarded")
    assert(vis(name, f, s.state) == false, name .. " hidden while not boarded")
    w.boarded = true
    assert(vis(name, f, s.state) == true, name .. " visible once boarded")
    for _, other in ipairs({ "B1", "F1", "F2" }) do
      if other ~= f then assert(vis(name, other, s.state) == false, name .. " hidden on " .. other) end
    end
  end
  assert(n == 7, "ranch_a has 7 windows over three floors, got " .. n)
end

function T.boarding_through_the_sim_shows_the_board()
  local s = hs.new(2)
  local done = 0
  for _, rid in ipairs(s.state.home.room_order) do
    local w = home.boardable_window(s.state, rid)
    if w and (w.floor or "F1") == "F1" then
      assert(home.board_window(s.state, rid))
      assert(vis(board_name(w), "F1", s.state) == true, board_name(w) .. " after board_window")
      done = done + 1
    end
  end
  assert(done >= 1, "at least one 1F window is boardable")
end

function T.hole_board_follows_boarded_hole()
  local s = hs.new(2)
  local h = s.state.home.structure.holes["17,0"]
  assert(h and h.damaged and not h.boarded, "ranch_a starts with a damaged hole at 17,0")
  assert(vis("F1_hole_board_17_0", "F1", s.state) == false, "hole board hidden at start")
  h.boarded = true
  assert(vis("F1_hole_board_17_0", "F1", s.state) == true, "hole board visible once boarded")
  assert(vis("F1_hole_board_17_0", "B1", s.state) == false, "hole board hidden on B1")
end

-- ------------------------------------------------------------------ unchanged rules still hold
function T.existing_rules_unchanged()
  local s = hs.new(2)
  for _, st in pairs(s.state.home.stations) do st.on = false end
  assert(vis("F1_woodstove_off", "F1", s.state) == true and vis("F1_woodstove_on", "F1", s.state) == false)
  assert(vis("F1_bed", "F1", s.state) == true)
  assert(vis("F1_wall_high", "F1", s.state) == false)
  assert(vis("stair_1F_2F", "F1", s.state) == true and vis("stair_B1_1F", "F1", s.state) == false)
  assert(vis("roof_panel_0", "F1", s.state) == false)
  -- a "_fixed" name the rules do not know is treated like any other node of its floor
  assert(vis("F1_mystery_fixed", "F1", s.state) == true)
end

-- ------------------------------------------------------------------ signature
function T.signature_changes_with_every_visual_state()
  assert(type(home3d.signature) == "function", "home3d.signature(state) exists")
  local s = hs.new(2)
  local st = s.state
  local seen = {}
  local function step(label)
    local sig = home3d.signature(st)
    assert(type(sig) == "string", "signature is a string")
    assert(not seen[sig], label .. " must change the signature")
    seen[sig] = true
    assert(home3d.signature(st) == sig, "signature is deterministic (" .. label .. ")")
  end
  step("start")
  station_of(st, "woodstove").on = not station_of(st, "woodstove").on
  step("stove toggle")
  home.repair_station(st, station_of(st, "generator").id)
  step("generator repaired")
  home.repair_station(st, station_of(st, "humidifier").id)
  step("humidifier repaired")
  st.home.structure.holes["17,0"].boarded = true
  step("hole boarded")
  local any
  for _, w in pairs(st.home.structure.windows) do any = w end
  any.boarded = true
  step("window boarded")
  st.home.rubble = math.max(0, (st.home.rubble or 0) - 40)
  step("rubble cleared")
end

function T.signature_ignores_irrelevant_state()
  local s = hs.new(2)
  local a = home3d.signature(s.state)
  s.state.clock.minute = s.state.clock.minute + 30
  for _, r in pairs(s.state.home.rooms) do r.temp = (r.temp or 0) + 3 end
  assert(home3d.signature(s.state) == a, "time and temperature do not touch the model")
end

return T
