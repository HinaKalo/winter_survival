-- Tests for core/layout.lua + data/legend.lua (pure template parsing).
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local layout = require("core.layout")
local legend = require("data.legend")
local serialize = require("core.serialize")

-- Self-contained copy of the ranch_a grid so this suite only depends on
-- core/layout.lua + data/legend.lua.
local ranch = {
  id = "ranch_a",
  variants = { A = {
    grid = {
      "####################",
      "#........#.........#",
      "#........#.........#",
      "#........#.........w",
      "#........+.........#",
      "#........#.........#",
      "#........#.........#",
      "####+##########+####",
      "#........#.........#",
      "w........#.........#",
      "#........+.........#",
      "#........#.........w",
      "#........#.........#",
      "############D#######",
    },
    floor = "wood",
    wall = "siding",
    rooms = {
      bedroom = { x = 3, y = 3 },
      living = { x = 12, y = 3 },
      kitchen = { x = 3, y = 10 },
      workshop = { x = 12, y = 10 },
    },
    damage = {
      broken_windows = { { 19, 3 }, { 0, 9 } },
      wall_holes = { { 17, 0 } },
    },
  } },
}

local T = {}

function T.legend_symbols()
  for _, sym in ipairs({ "#", "=", ".", ",", "+", "D", "w", " " }) do
    assert(legend.symbols[sym], "missing legend symbol " .. sym)
    assert(legend.symbols[sym].kind, "missing kind for " .. sym)
  end
end

function T.parse_ranch_rooms()
  local l, err = layout.parse(ranch, "A")
  assert(l, err)
  assert(l.width == 20 and l.height == 14)
  assert(l.id == "ranch_a")
  local expected = { bedroom = 48, living = 54, kitchen = 40, workshop = 45 }
  local total = 0
  for id, area in pairs(expected) do
    assert(l.rooms[id], "missing room " .. id)
    assert(l.rooms[id].area == area, id .. " area " .. tostring(l.rooms[id].area))
    total = total + area
  end
  local sum = 0
  for _, room in pairs(l.rooms) do sum = sum + room.area end
  assert(sum == total, "unexpected extra rooms")
  assert(#l.room_order == 4)
end

function T.outer_walls_windows_doors()
  local l = assert(layout.parse(ranch, "A"))
  -- east window in the living room is on the outer wall
  local w = layout.cell(l, 19, 3)
  assert(w and w.kind == "window", "window at 19,3")
  assert(w.outer == true, "east window must be outer")
  assert(w.room == "living", "east window belongs to living")
  local opening
  for _, op in ipairs(l.rooms.living.openings) do
    if op.kind == "window" and op.x == 19 and op.y == 3 then opening = op end
  end
  assert(opening, "living east window opening")
  -- west window in the kitchen
  local kw
  for _, op in ipairs(l.rooms.kitchen.openings) do
    if op.kind == "window" and op.x == 0 and op.y == 9 then kw = op end
  end
  assert(kw, "kitchen west window opening")
  -- exterior door at the bottom of the workshop
  local door
  for _, op in ipairs(l.rooms.workshop.openings) do
    if op.kind == "door" and op.x == 12 and op.y == 13 then door = op end
  end
  assert(door, "exterior door in workshop")
  -- wall hole in the living room north wall
  local hole
  for _, op in ipairs(l.rooms.living.openings) do
    if op.kind == "wall" and op.x == 17 and op.y == 0 then hole = op end
  end
  assert(hole, "north wall hole in living")
end

function T.inner_links()
  local l = assert(layout.parse(ranch, "A"))
  local function link(a, b)
    for _, e in ipairs(l.rooms[a].links) do
      if e.room == b then return e end
    end
  end
  local bedroom_living = link("bedroom", "living")
  assert(bedroom_living and bedroom_living.count >= 1,
    "bedroom/living door links=" .. serialize.encode(l.rooms.bedroom.links) .. " order=" .. table.concat(l.room_order, ","))
  assert(#bedroom_living.cells >= 1, "door cells recorded")
  local kitchen_workshop = link("kitchen", "workshop")
  assert(kitchen_workshop and kitchen_workshop.count >= 1, "kitchen/workshop door")
  -- links are symmetric
  local back = link("living", "bedroom")
  assert(back and back.count == bedroom_living.count)
end

function T.void_and_outdoor()
  local tmpl = {
    id = "void_test",
    variants = { A = { grid = {
      "  ###  ",
      "  #.#  ",
      "  #, , ",
      "  ###  ",
    } } },
  }
  local l, err = layout.parse(tmpl, "A")
  assert(l, err)
  local v = layout.cell(l, 0, 0)
  assert(v and v.kind == "void")
  local comma = false
  for _, c in ipairs(l.cells) do
    if c.kind == "outdoor" then comma = true end
  end
  assert(comma, "outdoor comma cell")
  assert(#l.room_order >= 1, "one interior room")
end

function T.repeat_deterministic()
  local a = assert(layout.parse(ranch, "A"))
  local b = assert(layout.parse(ranch, "A"))
  assert(serialize.encode(a) == serialize.encode(b), "layout parse must be deterministic")
end

function T.invalid_rows()
  local ok, err = layout.parse({ id = "bad", variants = { A = { grid = { "###", "##" } } } }, "A")
  assert(not ok and err, "unequal rows must fail")
end

function T.unknown_symbol()
  local ok, err = layout.parse({ id = "bad", variants = { A = { grid = { "#?#" } } } }, "A")
  assert(not ok and err, "unknown symbol must fail")
end

function T.anchors()
  local l = assert(layout.parse(ranch, "A"))
  assert(l.rooms.living.cells and l.rooms.living.name == "room.living.name")
  assert(layout.room_at(l, 12, 3) == "living")
  assert(layout.room_at(l, 3, 3) == "bedroom")
  assert(layout.room_at(l, 3, 10) == "kitchen")
  assert(layout.room_at(l, 12, 10) == "workshop")
  assert(layout.room_at(l, 9, 4) == nil, "door cells are not rooms")
end

return T
