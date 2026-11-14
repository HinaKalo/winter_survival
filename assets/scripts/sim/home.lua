-- Home model: rooms, stations, structure damage, storage, humidity, frost.
local layout_parser = require("core.layout")
local inventory = require("sim.inventory")
local weather = require("sim.weather")
local balance = require("data.balance")
local util = require("core.util")

local M = {}

local STATION_KIND = {
  f_hearth = "hearth", f_hearth2 = "hearth2", f_snow_barrel = "snow_barrel",
  f_water_tank = "water_tank", f_water_filter = "filter", f_filter = "filter",
  f_rat_trap = "rat_trap", f_sprout_tray = "sprout_tray", f_distiller = "distiller",
  f_smokehouse = "smokehouse", f_bench1 = "bench1", f_bench2 = "bench2", f_bench3 = "bench3",
  f_bed = "bed", f_electric_heater = "electric_heater", f_propane_heater = "propane_heater",
  f_woodstove = "woodstove", f_humidifier = "humidifier", f_generator = "generator",
  f_battery_bank = "battery_bank", f_radio = "radio", f_antenna = "antenna",
  f_shortwave = "shortwave", f_lamp = "lamp", f_tripwire = "tripwire",
}

local DEFAULT_ROOM = {
  f_snow_barrel = "kitchen", f_water_tank = "kitchen", f_water_filter = "kitchen",
  f_filter = "kitchen", f_rat_trap = "kitchen", f_sprout_tray = "kitchen",
  f_distiller = "kitchen", f_smokehouse = "workshop", f_bench1 = "workshop",
  f_bench2 = "workshop", f_bench3 = "workshop", f_radio = "living", f_antenna = "living",
  f_shortwave = "living", f_lamp = "living", f_generator = "workshop",
  f_battery_bank = "workshop", f_propane_heater = "living", f_woodstove = "living",
  f_tripwire = "living",
}

-- Cold cell (CONTENT 5.3): a 2x3 room inside the house. Its outer envelope is the 10 edge cells;
-- its door opens to the default room (inner link, mirrored on both sides).
local function cold_cell_envelope()
  return { wall = balance.thermal.cold_cell_room.wall, hole = 0, window = 0, broken_window = 0, board = 0, door = 0, door_open = 0 }
end

local function key(x, y) return tostring(x) .. "," .. tostring(y) end

function M.station_kind(id)
  return STATION_KIND[id] or STATION_KIND["f_" .. tostring(id)] or id
end

function M.template(layout_id)
  local ok, tmpl = pcall(require, "data.homes." .. tostring(layout_id))
  if not ok then return nil, "missing home template " .. tostring(layout_id) end
  return tmpl
end

function M.init(state, opts)
  opts = opts or {}
  local layout_id = opts.home_layout or "ranch_a"
  local tmpl, err = M.template(layout_id)
  if not tmpl then return nil, err end
  local layout, perr = layout_parser.parse(tmpl, opts.variant or "A")
  if not layout then return nil, perr end

  state.home = {
    layout_id = layout_id,
    variant = layout.variant,
    default_room = "living",
    rooms = {},
    room_order = {},
    humidity = balance.humidity.initial,
    stash = inventory.new(balance.limits.stash_slots, 100000),
    stations = {},
    structure = { windows = {}, holes = {}, doors = {} },
    fuel_frac = {},
    rubble = layout.rubble or 70,
    cold_cell = false,
    water_tank = { frozen = false, cold_hours = 0 },
  }

  local cold_start = weather.outdoor_temp(state) + balance.thermal.initial_temp_offset
  for _, id in ipairs(layout.room_order) do
    local lr = layout.rooms[id]
    local room = {
      id = id,
      name = "room." .. id .. ".name",
      area = lr.area,
      temp = cold_start,
      insulation = balance.thermal.reference_insulation or 0,
      frost = 100,
      envelope = { wall = 0, hole = 0, window = 0, broken_window = 0, board = 0, door = 0, door_open = 0 },
      openings = {},
      links = {},
      cold_cell = false,
    }
    for _, op in ipairs(lr.openings) do
      room.openings[#room.openings + 1] = { kind = op.kind, x = op.x, y = op.y }
    end
    -- layout links are one entry per kind (door / wall); merge them per neighbour room
    local by_room = {}
    for _, link in ipairs(lr.links) do
      local l = by_room[link.room]
      if not l then
        l = { room = link.room, walls = 0, doors = 0, door_cells = {}, open_doors = 0 }
        by_room[link.room] = l
        room.links[#room.links + 1] = l
      end
      if link.kind == "door" then
        l.doors = l.doors + link.count
        for _, c in ipairs(link.cells or {}) do l.door_cells[#l.door_cells + 1] = { x = c.x, y = c.y, kind = c.kind } end
      else
        l.walls = l.walls + link.count
      end
    end
    table.sort(room.links, function(a, b) return a.room < b.room end)
    state.home.rooms[id] = room
    state.home.room_order[#state.home.room_order + 1] = id
  end
  table.sort(state.home.room_order)

  for _, op in ipairs(layout.openings) do
    local k = key(op.x, op.y)
    if op.kind == "window" then
      state.home.structure.windows[k] = { x = op.x, y = op.y, broken = false, boarded = false }
    elseif op.kind == "wall" then
      state.home.structure.holes[k] = { x = op.x, y = op.y, boarded = false, damaged = false }
    elseif op.kind == "door" then
      state.home.structure.doors[k] = { x = op.x, y = op.y, open = false, outer = op.outer and true or false }
    end
  end

  local damage = layout.damage or {}
  for _, p in ipairs(damage.broken_windows or {}) do
    local w = state.home.structure.windows[key(p[1], p[2])]
    if w then w.broken = true end
  end
  for _, p in ipairs(damage.wall_holes or {}) do
    local h = state.home.structure.holes[key(p[1], p[2])]
    if h then h.damaged = true end
  end
  for _, p in ipairs(damage.door_open or {}) do
    local d = state.home.structure.doors[key(p[1], p[2])]
    if d then d.open = true end
  end

  for _, st in ipairs(layout.stations or {}) do
    M.add_station(state, st.id, st.kind or M.station_kind(st.id), st.room, st.hp, st.on)
  end
  M.rebuild(state)
  return state.home
end

function M.add_station(state, id, kind, room, hp, on)
  local h = state.home
  room = room or DEFAULT_ROOM[id] or h.default_room
  if not h.rooms[room] then room = h.default_room end
  h.stations[id] = {
    id = id,
    kind = kind or M.station_kind(id),
    room = room,
    hp = hp or 100,
    on = on or false,
    level = (kind == "woodstove") and "low" or nil,
    fuel_frac = {},
    charge = 0,
    filter_left = 40,
  }
  return h.stations[id]
end

function M.station(state, id)
  return state.home.stations[id]
end

function M.first_station(state, kind)
  local h = state.home
  for _, id in ipairs(util.sorted_keys(h.stations)) do
    local st = h.stations[id]
    if st.kind == kind and st.hp > 0 and st.on ~= false then return st end
  end
  return nil
end

function M.usable_station(state, kind)
  local h = state.home
  for _, id in ipairs(util.sorted_keys(h.stations)) do
    local st = h.stations[id]
    if st.kind == kind and st.hp > 0 then return st end
  end
  return nil
end

function M.assign(state, cid, room)
  local c = state.party.chars[cid]
  if not c or not state.home.rooms[room] then return false, "bad_room" end
  c.room = room
  return true
end

function M.room_temp(state, room)
  local r = state.home.rooms[room]
  if r then return r.temp end
  return weather.outdoor_temp(state)
end

function M.set_toggle(state, id, on)
  local st = state.home.stations[id]
  if not st then return false, "no_station" end
  if st.hp <= 0 and st.kind ~= "bed" then return false, "broken" end
  st.on = on and true or false
  return true
end

function M.set_insulation(state, room_id, level)
  local room = state.home.rooms[room_id]
  if not room then return false, "bad_room" end
  room.insulation = math.max(room.insulation or 0, level)
  M.rebuild(state)
  return true
end

function M.boardable_window(state, room_id)
  local room = state.home.rooms[room_id]
  if not room then return nil end
  for _, op in ipairs(room.openings) do
    if op.kind == "window" then
      local w = state.home.structure.windows[key(op.x, op.y)]
      if w and not w.boarded then return w end
    end
  end
  return nil
end

function M.boardable_hole(state, room_id)
  local room = state.home.rooms[room_id]
  if not room then return nil end
  for _, op in ipairs(room.openings) do
    if op.kind == "wall" then
      local h = state.home.structure.holes[key(op.x, op.y)]
      if h and h.damaged and not h.boarded then return h end
    end
  end
  return nil
end

function M.board_window(state, room_id)
  local w = M.boardable_window(state, room_id)
  if not w then return false, "no_window" end
  w.boarded = true
  M.rebuild(state)
  return true
end

function M.board_hole(state, room_id)
  local h = M.boardable_hole(state, room_id)
  if not h then return false, "no_hole" end
  h.boarded = true
  M.rebuild(state)
  return true
end

function M.repair_station(state, id)
  local st = state.home.stations[id]
  if not st then return false, "no_station" end
  st.hp = 100
  st.on = false
  return true
end

function M.add_cold_cell(state)
  local h = state.home
  if h.rooms[balance.thermal.cold_cell_room.id] then return true end
  local host = h.rooms[h.default_room]
  local cc = balance.thermal.cold_cell_room
  h.rooms[cc.id] = {
    id = cc.id, name = "room." .. cc.id .. ".name", area = cc.area,
    temp = host.temp, insulation = cc.insulation, frost = 100,
    envelope = cold_cell_envelope(),
    openings = {},
    links = { { room = h.default_room, walls = 0, doors = 1, door_cells = {}, open_doors = 0, cold_cell = true } },
    cold_cell = true,
  }
  -- mirror link so the host room exchanges heat with the cell too
  host.links[#host.links + 1] = { room = cc.id, walls = 0, doors = 1, door_cells = {}, open_doors = 0, cold_cell = true }
  table.sort(host.links, function(a, b) return a.room < b.room end)
  h.room_order[#h.room_order + 1] = cc.id
  table.sort(h.room_order)
  h.cold_cell = true
  return true
end

-- Recompute envelope counts and open-door counts from the structure maps.
function M.rebuild(state)
  local h = state.home
  for _, rid in ipairs(h.room_order) do
    local room = h.rooms[rid]
    if room.cold_cell then
      room.envelope = cold_cell_envelope()
    else
      local env = { wall = 0, hole = 0, window = 0, broken_window = 0, board = 0, door = 0, door_open = 0 }
      for _, op in ipairs(room.openings) do
        local k = key(op.x, op.y)
        if op.kind == "wall" then
          local hole = h.structure.holes[k]
          if hole and hole.damaged then
            if hole.boarded then env.board = env.board + 1 else env.hole = env.hole + 1 end
          else
            env.wall = env.wall + 1
          end
        elseif op.kind == "window" then
          local w = h.structure.windows[k]
          if w and w.boarded then
            env.board = env.board + 1
          elseif w and w.broken then
            env.broken_window = env.broken_window + 1
          else
            env.window = env.window + 1
          end
        elseif op.kind == "door" then
          local d = h.structure.doors[k]
          if d and d.open then env.door_open = env.door_open + 1 else env.door = env.door + 1 end
        end
      end
      room.envelope = env
    end
    for _, link in ipairs(room.links) do
      local open = 0
      for _, cell in ipairs(link.door_cells) do
        if cell.kind == "door" then
          local d = h.structure.doors[key(cell.x, cell.y)]
          if d and d.open then open = open + 1 end
        end
      end
      link.open_doors = open
    end
  end
end

function M.ambient_temp(state)
  local living = state.home.rooms[state.home.default_room]
  return living and living.temp or weather.outdoor_temp(state)
end

-- True while a cooking/boiling job (recipe station hearth/hearth2) is actually progressing.
function M.cooking_active(state)
  local recipes = require("data.recipes")
  for _, id in ipairs(util.sorted_keys(state.jobs or {})) do
    local job = state.jobs[id]
    if job.kind ~= "research" and not job.waiting and job.recipe then
      local recipe = recipes.get(job.recipe)
      local ch = state.party.chars[job.actor]
      if recipe and (recipe.station == "hearth" or recipe.station == "hearth2")
        and ch and not ch.dead and ch.status ~= "dead" and ch.job == id and ch.activity == "work" then
        return true
      end
    end
  end
  return false
end

-- The stove a cooking/boiling job runs on: first usable stove-class kind (same order as craft).
function M.cooking_station(state)
  for _, kind in ipairs({ "hearth", "hearth2", "woodstove" }) do
    local st = M.usable_station(state, kind)
    if st then return st end
  end
  return nil
end

function M.tick(state, minutes)
  local h = state.home
  local hours = minutes / 60
  inventory.spoil_tick(h.stash, hours, M.ambient_temp(state))

  -- humidity (CONTENT 6.3)
  local at_home = 0
  for _, c in ipairs(require("sim.chars").alive(state)) do
    if c.activity ~= "out" then at_home = at_home + 1 end
  end
  local hum = balance.humidity
  local dH = -hum.drift * (h.humidity - hum.outdoor) + hum.per_person * at_home
  for _, id in ipairs(util.sorted_keys(h.stations)) do
    local st = h.stations[id]
    if st.on and st.hp > 0 then
      if st.kind == "electric_heater" then dH = dH + hum.sources.electric_heater end
      if st.kind == "woodstove" then dH = dH + hum.sources.woodstove end
      if st.kind == "propane_heater" then dH = dH + hum.sources.propane end
      if st.kind == "snow_barrel" then dH = dH + hum.sources.snow_barrel end
      if st.kind == "humidifier" and st.powered and h.humidity < hum.humidifier_stop then dH = dH + hum.sources.humidifier end
    end
  end
  if M.cooking_active(state) then dH = dH + hum.sources.hearth end
  h.humidity = util.clamp(h.humidity + dH * hours, hum.min, hum.max)

  -- frost
  for _, rid in ipairs(h.room_order) do
    local room = h.rooms[rid]
    if h.humidity > hum.frost_humidity and room.temp < hum.frost_room then
      room.frost = room.frost - hum.frost_loss_per_hour * hours
      if room.frost <= hum.frost_break and (room.insulation or 0) > 0 then
        room.insulation = room.insulation - 1
        room.frost = 100
        require("sim.state").log(state, "frost_damage", { room = rid })
      end
      if room.frost < 0 then room.frost = 0 end
    elseif room.temp >= hum.frost_room and h.humidity < hum.frost_humidity then
      room.frost = math.min(100, room.frost + hours)
    end
  end

  -- water tank freezing
  local tank = h.stations.f_water_tank
  if tank and tank.hp > 0 then
    local room = h.rooms[tank.room]
    if room and room.temp < 0 then
      h.water_tank.cold_hours = h.water_tank.cold_hours + hours
      if h.water_tank.cold_hours >= 6 then h.water_tank.frozen = true end
    else
      h.water_tank.cold_hours = 0
      if room and room.temp > 2 then h.water_tank.frozen = false end
    end
  end

  local warmest, coldest = -99, 99
  for _, rid in ipairs(h.room_order) do
    local t = h.rooms[rid].temp
    if t > warmest then warmest = t end
    if t < coldest then coldest = t end
  end
  if warmest > state.stats.best_room_temp then state.stats.best_room_temp = warmest end
  if coldest < state.stats.worst_room_temp then state.stats.worst_room_temp = coldest end
end

return M
