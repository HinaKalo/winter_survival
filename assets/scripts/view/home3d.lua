-- Which nodes of the baked house model are visible for a viewed floor (M5-3D-PLAN §5.2).
-- Pure: reads the sim state only, never calls the engine.
local M = {}

local PREFIX_FLOOR = { B1_ = "B1", F1_ = "F1", F2_ = "F2", DRESS_B1_ = "B1", DRESS_F1_ = "F1", DRESS_F2_ = "F2" }
local ORDER = { "DRESS_B1_", "DRESS_F1_", "DRESS_F2_", "B1_", "F1_", "F2_" }

local PAIR_KIND = { F1_woodstove = "woodstove", F1_hearth = "hearth" }

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
  if name == "stair_B1_1F" then return view_floor == "B1" or view_floor == "F1" end
  if name == "stair_1F_2F" then return view_floor == "F1" or view_floor == "F2" end
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
  local k = name:match("^F1_rubble_0(%d)$")
  if k then return rubble_shown(state, tonumber(k)) end
  return true
end

function M.visibility(names, view_floor, state)
  local out = {}
  for _, n in ipairs(names) do out[n] = M.node_visible(n, view_floor, state) end
  return out
end

return M
