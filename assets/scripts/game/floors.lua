-- Floor model of a multi-storey home (M5-3D-PLAN §5.1). Pure: no engine, no view requires.
local M = {}

M.ORDER = { "B1", "F1", "F2" }
M.BASE_Y = { B1 = -3, F1 = 0, F2 = 3 }

local INDEX = { B1 = 1, F1 = 2, F2 = 3 }

function M.of_room(state, room_id)
  local rooms = state and state.home and state.home.rooms
  local r = rooms and rooms[room_id]
  return r and r.floor or nil
end

-- dir = +1 up / -1 down; stays put at the ends (and for unknown floors)
function M.step(floor, dir)
  local i = INDEX[floor]
  if not i then return floor end
  local n = i + (dir > 0 and 1 or dir < 0 and -1 or 0)
  return M.ORDER[n] or floor
end

local function stair_list(template)
  if type(template) ~= "table" then return {} end
  if template.stairs then return template.stairs end
  local v = template.variants and template.variants.A
  return v and v.stairs or {}
end

-- Stairs to take, in order, from floor `from` to floor `to` (empty on the same floor).
function M.route(template, from, to)
  local out = {}
  local fi, ti = INDEX[from], INDEX[to]
  if not fi or not ti or fi == ti then return out end
  local stairs = stair_list(template)
  local dir = ti > fi and 1 or -1
  local cur = fi
  while cur ~= ti do
    local nxt = cur + dir
    local a, b = M.ORDER[cur], M.ORDER[nxt]
    local found
    for _, st in ipairs(stairs) do
      if (st.lower == a and st.upper == b) or (st.lower == b and st.upper == a) then found = st break end
    end
    if not found then return {} end
    local up = found.lower == a
    out[#out + 1] = {
      id = found.id, from = a, to = b,
      from_cell = { (up and found.lower_cell or found.upper_cell)[1], (up and found.lower_cell or found.upper_cell)[2] },
      to_cell = { (up and found.upper_cell or found.lower_cell)[1], (up and found.upper_cell or found.lower_cell)[2] },
    }
    cur = nxt
  end
  return out
end

return M
