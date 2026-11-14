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

-- Total conductance of a room to outside + neighbours (W/C).
function M.room_g(state, room_id)
  local room = state.home.rooms[room_id]
  if not room then return 0 end
  if room_id == "cold_cell" then
    return 10.0  -- CONTENT §5.3: 6-cell cold cell, G ~= 10 W/C
  end
  local env = room.envelope
  local mult = insulation_mult(room)
  local g = 0
  g = g + env.wall * T.g.wall * mult
  g = g + env.hole * T.g.hole * mult
  g = g + env.board * T.g.board * mult
  g = g + env.window * T.g.window
  g = g + env.broken_window * T.g.broken_window
  g = g + env.door * T.g.door_closed
  g = g + env.door_open * T.g.door_open
  g = g + room.area * T.g.roof_floor * mult
  for _, link in ipairs(room.links or {}) do
    local walls = link.walls or 0
    local doors = math.max(0, (link.doors or 0) - (link.open_doors or 0))
    local open = link.open_doors or 0
    g = g + walls * T.g.inner_wall + doors * T.g.inner_door_closed + open * T.g.inner_door_open
  end
  return g
end

function M.heat_capacity(state, room_id)
  local room = state.home.rooms[room_id]
  if not room then return 1 end
  return T.heat_capacity * (room.area or 1)
end

-- Heat contributed by working stations in a room (W).
function M.station_heat(state, room_id)
  local power = require("sim.power")
  local total = 0
  for _, id in ipairs(util.sorted_keys(state.home.stations)) do
    local st = state.home.stations[id]
    if st.room == room_id and st.on and st.hp > 0 then
      if st.kind == "hearth" then total = total + 600
      elseif st.kind == "hearth2" then total = total + 750
      elseif st.kind == "snow_barrel" then total = total + 300
      elseif st.kind == "propane_heater" then total = total + 1800
      elseif st.kind == "woodstove" then total = total + (st.level == "low" and 1000 or 2500)
      elseif st.kind == "electric_heater" then
        if power.device_powered(state, "f_electric_heater") then total = total + 800 end
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
    local g = M.room_g(state, rid)
    local q_in = M.station_heat(state, rid) + M.body_heat(state, rid)
    local q_out = g * (temps[rid] - out)
    for _, link in ipairs(room.links or {}) do
      local other = state.home.rooms[link.room]
      if other then
        local g_link = (link.walls or 0) * T.g.inner_wall
          + math.max(0, (link.doors or 0) - (link.open_doors or 0)) * T.g.inner_door_closed
          + (link.open_doors or 0) * T.g.inner_door_open
        q_out = q_out + g_link * (temps[rid] - other.temp)
      end
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
