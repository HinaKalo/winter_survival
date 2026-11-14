-- Per-room heat nodes (CONTENT §6.2). G is recomputed from the current envelope.
local balance = require("data.balance")
local weather = require("sim.weather")
local util = require("core.util")

local M = {}

local T = balance.thermal

local function insulation_mult(room)
  local lvl = room.insulation or 0
  if (room.frost or 100) < 50 then lvl = math.max(0, lvl - 1) end
  return T.insulation_mult[math.min(2, lvl)] or 1.0
end

function M.room_temp(state, room_id)
  local room = state.home and state.home.rooms[room_id]
  if room then return room.temp end
  return weather.outdoor_temp(state)
end

-- Conductance of one inner link (W/C): inner walls + closed/open inner doors.
function M.link_g(link)
  local walls = link.walls or 0
  local doors = link.doors or 0
  local open = math.min(doors, link.open_doors or 0)
  -- the cold cell has its own closed-door value (CONTENT 5.3)
  local closed_g = link.cold_cell and T.cold_cell_door_g or T.g.inner_door_closed
  return walls * T.g.inner_wall + (doors - open) * closed_g + open * T.g.inner_door_open
    + (link.stairs or 0) * (T.g.stair_open or 0)
end

-- Envelope-only conductance of a room to the outdoors (W/C). Inner links are NOT included
-- (CONTENT 6.2.1: Q_out = sum G_link (T - T_nb) + G_env (T - T_out)).
-- Insulation multiplies walls, boards and roof/floor only; doors, windows and holes are unaffected.
-- Returns total, solid: `solid` is the walls / boards / roof-floor part; in a ground room (below
-- grade) that part exchanges heat with the ground instead of the outdoor air (M5-3D §4.2).
function M.room_g_parts(state, room_id)
  local room = state.home.rooms[room_id]
  if not room then return 0, 0 end
  local env = room.envelope
  local mult = insulation_mult(room)
  if room.cold_cell then mult = mult * (T.cold_cell_mult or 1.0) end
  local solid = env.wall * T.g.wall * mult + env.board * T.g.board * mult + (room.area or 0) * T.g.roof_floor * mult
  local g = solid
  g = g + env.hole * T.g.hole
  g = g + env.window * T.g.window
  g = g + env.broken_window * T.g.broken_window
  g = g + env.door * T.g.door_closed
  g = g + env.door_open * T.g.door_open
  return g, solid
end

function M.room_g(state, room_id)
  return (M.room_g_parts(state, room_id))
end

function M.heat_capacity(state, room_id)
  local room = state.home.rooms[room_id]
  if not room then return 1 end
  return T.heat_capacity * (room.area or 1)
end

-- Heat contributed by working stations in a room (W).
function M.station_heat(state, room_id)
  local power = require("sim.power")
  local home = require("sim.home")
  local total = 0
  -- a stove in use for cooking/boiling gives extra heat (CONTENT 5.1: +400 W)
  if home.cooking_active(state) then
    local cs = home.cooking_station(state)
    if cs and cs.room == room_id then total = total + balance.power.cooking_heat end
  end
  for _, id in ipairs(util.sorted_keys(state.home.stations)) do
    local st = state.home.stations[id]
    if st.room == room_id and st.on and st.hp > 0 then
      local key = "f_" .. st.kind
      if st.kind == "woodstove" and st.level == "low" then key = "f_woodstove_low" end
      local def = balance.power.station[key]
      if def and def.heat then
        if st.kind ~= "electric_heater" or power.device_powered(state, id) then
          total = total + def.heat
        end
      end
    end
  end
  return total
end

function M.body_heat(state, room_id)
  local total = 0
  for _, ch in ipairs(require("sim.chars").alive(state)) do
    if ch.activity ~= "out" and ch.room == room_id then
      total = total + require("sim.chars").body_heat(ch)
    end
  end
  return total
end

function M.tick(state, minutes)
  minutes = minutes or T.step_minutes
  local out = weather.update_outdoor(state)
  local rooms = state.home.room_order
  local temps = {}
  for _, rid in ipairs(rooms) do temps[rid] = state.home.rooms[rid].temp end

  for _, rid in ipairs(rooms) do
    local room = state.home.rooms[rid]
    local q_in = M.station_heat(state, rid) + M.body_heat(state, rid)
    local g_all, g_solid = M.room_g_parts(state, rid)
    local q_out
    if room.ground then
      q_out = (g_all - g_solid) * (temps[rid] - out) + g_solid * (temps[rid] - T.ground_temp)
    else
      q_out = g_all * (temps[rid] - out)
    end
    for _, link in ipairs(room.links or {}) do
      local nb = temps[link.room]
      if nb then q_out = q_out + M.link_g(link) * (temps[rid] - nb) end
    end
    local c = M.heat_capacity(state, rid)
    local d = (q_in - q_out) / (c * 60) * minutes
    -- explicit Euler is stable at C >= 72 and G <= 100 (CONTENT 6.2.1)
    room.temp = util.clamp(room.temp + d, -60, 50)
  end

  -- update stats (coldest/warmest room in the house)
  local worst, best = 99, -99
  for _, rid in ipairs(rooms) do
    local t = state.home.rooms[rid].temp
    if t < worst then worst = t end
    if t > best then best = t end
  end
  if worst < state.stats.worst_room_temp then state.stats.worst_room_temp = worst end
  if best > state.stats.best_room_temp then state.stats.best_room_temp = best end
end

-- Effective temperature E for a character (CONTENT 6.2.3).
function M.effective_temp(state, ch)
  local E = require("sim.chars").wear_bonus(ch)
  E = E + T.effective.base_clothing
  if ch.activity == "sleep" and ch.wear and ch.wear.blanket then
    local def = require("data.items").get("blanket")
    if def then E = E + (def.sleep_warmth or 0) end
  end
  if ch.hot_meal_minutes and ch.hot_meal_minutes > 0 then E = E + T.effective.hot_meal end

  local local_t
  if ch.activity == "out" then
    local_t = weather.outdoor_temp(state)
    E = E - weather.wind_chill(state)
  else
    local_t = M.room_temp(state, ch.room)
  end
  return local_t + E
end

return M
