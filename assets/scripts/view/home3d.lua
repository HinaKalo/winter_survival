-- Which nodes of the baked house model are visible for a viewed floor (M5-3D-PLAN §5.2).
-- Pure: reads the sim state only, never calls the engine.
local M = {}

local PREFIX_FLOOR = { B1_ = "B1", F1_ = "F1", F2_ = "F2", DRESS_B1_ = "B1", DRESS_F1_ = "F1", DRESS_F2_ = "F2" }
local ORDER = { "DRESS_B1_", "DRESS_F1_", "DRESS_F2_", "B1_", "F1_", "F2_" }

local PAIR_KIND = { F1_woodstove = "woodstove", F1_hearth = "hearth" }

local FIXED_KIND = { F1_electric_heater = "electric_heater", F1_generator = "generator", F1_humidifier = "humidifier" }

local function starts(name, p) return name:sub(1, #p) == p end

local function floor_of(name)
  for _, p in ipairs(ORDER) do
    if starts(name, p) then return PREFIX_FLOOR[p] end
  end
  return nil
end

local function station_on(state, kind)
  for _, st in pairs(state.home and state.home.stations or {}) do
    if st.kind == kind and st.on and st.hp > 0 then return true end
  end
  return false
end

local function station_fixed(state, kind)
  for _, st in pairs(state.home and state.home.stations or {}) do
    if st.kind == kind and st.hp > 0 then return true end
  end
  return false
end

local function window_boarded(state, floor_prefix, x, y)
  local key = (floor_prefix == "F1" and "" or floor_prefix .. ":") .. x .. "," .. y
  local w = state.home and state.home.structure and state.home.structure.windows and state.home.structure.windows[key]
  return w ~= nil and w.boarded == true
end

local function rubble_shown(state, k)
  local initial = 70
  local ok, tmpl = pcall(require, "data.homes." .. tostring(state.home and state.home.layout_id or "ranch_a"))
  if ok and tmpl then
    local v = tmpl.variants and tmpl.variants[state.home.variant or "A"]
    if v and v.rubble then initial = v.rubble end
  end
  local cur = state.home and state.home.rubble or 0
  if cur <= 0 or initial <= 0 then return false end
  return k <= math.ceil(6 * cur / initial)
end

function M.node_visible(name, view_floor, state)
  if starts(name, "roof") or starts(name, "exterior") or starts(name, "EXT_") then return false end
  if name == "stair_B1_1F" then return view_floor == "B1" end -- below the 1F slab it pokes out of the house edge
  if name == "stair_1F_2F" then return view_floor == "F1" end -- same: pokes out under the 2F slab
  local f = floor_of(name)
  if f and f ~= view_floor then return false end
  if not f then return true end
  if name:match("_wall_high$") then return false end
  local base, suffix = name:match("^(.-)_(o[nf]+)$")
  if base and (suffix == "on" or suffix == "off") then
    if base == "B1_boiler" then return suffix == "off" end
    local kind = PAIR_KIND[base]
    if kind then
      local on = station_on(state, kind)
      return (suffix == "on") == on
    end
  end
  local fbase = name:match("^(.-)_fixed$")
  if fbase and FIXED_KIND[fbase] then return station_fixed(state, FIXED_KIND[fbase]) end
  local wkind = FIXED_KIND[name]
  if wkind then return not station_fixed(state, wkind) end
  local wf, wx, wy = name:match("^(%u%d)_window_board_(%d+)_(%d+)$")
  if wf then return window_boarded(state, wf, wx, wy) end
  if name == "F1_hole_board_17_0" then
    local h = state.home and state.home.structure and state.home.structure.holes and state.home.structure.holes["17,0"]
    return h ~= nil and h.boarded == true
  end
  local k = name:match("^F1_rubble_0(%d)$")
  if k then return rubble_shown(state, tonumber(k)) end
  return true
end

-- Everything that changes which nodes are shown, as a string (the scene re-syncs the model when it changes).
function M.signature(state)
  local h = state.home or {}
  local parts = { tostring(h.rubble or 0) }
  local ids = {}
  for id in pairs(h.stations or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local st = h.stations[id]
    parts[#parts + 1] = id .. (st.on and "1" or "0") .. (st.hp > 0 and "1" or "0")
  end
  local keys = {}
  local structure = h.structure or {}
  for k in pairs(structure.windows or {}) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do parts[#parts + 1] = "w" .. k .. (structure.windows[k].boarded and "1" or "0") end
  keys = {}
  for k in pairs(structure.holes or {}) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do parts[#parts + 1] = "h" .. k .. (structure.holes[k].boarded and "1" or "0") end
  return table.concat(parts, "|")
end

function M.visibility(names, view_floor, state)
  local out = {}
  for _, n in ipairs(names) do out[n] = M.node_visible(n, view_floor, state) end
  return out
end

return M
