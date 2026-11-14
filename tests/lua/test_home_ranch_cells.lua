-- 验收测试（主代理编写，实现者不得修改；认为有误时提出，由主代理裁定）。docs/M4-PLAN.md 任务 U4。
-- data/homes/ranch_a.lua 的站点格位与瓦砾格的数据校验。
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local layout = require("core.layout")
local tmpl = require("data.homes.ranch_a")

local T = {}

local function parsed()
  local l = assert(layout.parse(tmpl, "A"))
  return l, tmpl.variants.A
end

local function key(x, y) return x .. "," .. y end

function T.stations_sit_on_floor_in_their_room()
  local l, v = parsed()
  local seen = {}
  for _, st in ipairs(v.stations) do
    assert(type(st.at) == "table" and #st.at == 2, st.id .. " has at = {x, y}")
    local c = layout.cell(l, st.at[1], st.at[2])
    assert(c and c.kind == "floor", st.id .. " is on a floor cell")
    assert(c.room == st.room, st.id .. " is inside room " .. st.room .. ", got " .. tostring(c.room))
    assert(not seen[key(st.at[1], st.at[2])], st.id .. " shares a cell")
    seen[key(st.at[1], st.at[2])] = true
  end
end

function T.rubble_cells_are_floor_and_distinct()
  local l, v = parsed()
  local rc = v.rubble_cells
  assert(type(rc) == "table" and #rc >= 8 and #rc <= 12, "8-12 rubble cells")
  local seen = {}
  for _, st in ipairs(v.stations) do seen[key(st.at[1], st.at[2])] = "station" end
  for _, p in ipairs(rc) do
    local c = layout.cell(l, p[1], p[2])
    assert(c and c.kind == "floor", "rubble " .. key(p[1], p[2]) .. " on floor")
    assert(not seen[key(p[1], p[2])], "rubble " .. key(p[1], p[2]) .. " overlaps")
    seen[key(p[1], p[2])] = "rubble"
  end
end

-- From the front door, with stations as obstacles, every floor cell that is not a station is
-- reachable when rubble is ignored (cleared), and every station has a reachable neighbour.
-- With rubble present every room still has at least one reachable cell (rubble blocks part of a room only).
local function flood(l, blocked)
  local start
  for _, c in ipairs(l.cells) do
    if c.kind == "door" and not c.inner then start = c end
  end
  assert(start, "front door")
  local seen, q = { [key(start.x, start.y)] = true }, { start }
  local i = 1
  while q[i] do
    local c = q[i]; i = i + 1
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local n = layout.cell(l, c.x + d[1], c.y + d[2])
      if n and (n.kind == "floor" or n.kind == "door") and not blocked[key(n.x, n.y)]
          and not seen[key(n.x, n.y)] then
        seen[key(n.x, n.y)] = true
        q[#q + 1] = n
      end
    end
  end
  return seen
end

function T.house_stays_walkable()
  local l, v = parsed()
  local blocked = {}
  for _, st in ipairs(v.stations) do blocked[key(st.at[1], st.at[2])] = true end
  local reach = flood(l, blocked)
  for _, c in ipairs(l.cells) do
    if c.kind == "floor" and not blocked[key(c.x, c.y)] then
      assert(reach[key(c.x, c.y)], "floor " .. key(c.x, c.y) .. " unreachable (stations wall it off)")
    end
  end
  for _, st in ipairs(v.stations) do
    local ok = false
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      if reach[key(st.at[1] + d[1], st.at[2] + d[2])] then ok = true end
    end
    assert(ok, st.id .. " has a reachable neighbour")
  end
  for _, p in ipairs(v.rubble_cells) do blocked[key(p[1], p[2])] = true end
  reach = flood(l, blocked)
  for id, room in pairs(l.rooms) do
    local any = false
    for _, c in ipairs(room.cells) do if reach[key(c.x, c.y)] then any = true end end
    assert(any, "room " .. id .. " reachable with rubble in place")
  end
end

return T
