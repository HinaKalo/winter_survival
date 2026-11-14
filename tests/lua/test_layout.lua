-- Tests for core/layout.lua + data/legend.lua (pure template parsing).
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local layout = require("core.layout")
local legend = require("data.legend")
local serialize = require("core.serialize")

local T = {}

local function house()
  return {
    id = "test_house",
    floor = "wood",
    wall = "siding",
    variants = {
      A = {
        grid = {
          "############",
          "#.K..#.....#",
          "#....+.....#",
          "D....#.....#",
          "#....#.....#",
          "#....#.....#",
          "######w#####",
        },
        legend = { K = { prop = "counter" } },
        rooms = { a = { x = 2, y = 2 }, b = { x = 8, y = 2 } },
      },
    },
  }
end

function T.legend_symbols()
  for _, sym in ipairs({ "#", "=", ".", ",", "+", "D", "w", " " }) do
    assert(legend.symbols[sym], "missing legend symbol " .. sym)
    assert(legend.symbols[sym].kind, "missing kind for " .. sym)
  end
end

function T.parse_rooms()
  local l, err = layout.parse(house(), "A")
  assert(l, err)
  assert(l.width == 12 and l.height == 7)
  assert(l.id == "test_house")
  assert(#l.room_order == 2)
  assert(l.rooms.a.area == 20, "room a area " .. tostring(l.rooms.a.area))
  assert(l.rooms.b.area == 25, "room b area " .. tostring(l.rooms.b.area))
  -- props belong to the room they occupy
  local k = layout.cell(l, 2, 1)
  assert(k and k.kind == "prop" and k.prop == "counter")
  assert(k.room == "a")
end

function T.outer_walls_windows_doors()
  local l = assert(layout.parse(house(), "A"))
  local wa = l.rooms.a.envelope
  local wb = l.rooms.b.envelope
  assert(wa.wall == 12 and wa.door == 1 and wa.window == 0, serialize.encode(wa))
  assert(wb.wall == 14 and wb.door == 0 and wb.window == 1, serialize.encode(wb))
  -- window on the south wall of room b
  local win = layout.cell(l, 6, 6)
  assert(win and win.kind == "window" and win.outer == true)
  -- exterior door on the west wall of room a
  local door = layout.cell(l, 0, 3)
  assert(door and door.kind == "door" and door.outer == true)
  -- outer openings are attached to their room
  local found
  for _, op in ipairs(l.rooms.b.openings) do
    if op.kind == "window" and op.x == 6 and op.y == 6 then found = op end
  end
  assert(found, "room b south window opening")
end

function T.inner_links()
  local l = assert(layout.parse(house(), "A"))
  local function link(a, b)
    for _, e in ipairs(l.rooms[a].links) do
      if e.room == b then return e end
    end
  end
  local ab = link("a", "b")
  assert(ab, "a/b link")
  assert(ab.count == 1, "a/b has one door, got " .. tostring(ab.count))
  assert(ab.wall == 4, "a/b shared wall count " .. tostring(ab.wall))
  assert(#ab.cells == 5, "door + wall cells recorded")
  local ba = link("b", "a")
  assert(ba and ba.count == ab.count and ba.wall == ab.wall, "links are symmetric")
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
  assert(layout.cell(l, 0, 0).kind == "void")
  assert(layout.cell(l, 3, 2).kind == "outdoor")
  assert(#l.room_order == 1, "one interior room")
end

function T.repeat_deterministic()
  local a = assert(layout.parse(house(), "A"))
  local b = assert(layout.parse(house(), "A"))
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

function T.anchors_and_lookup()
  local l = assert(layout.parse(house(), "A"))
  assert(l.rooms.a.name == "room.a.name")
  assert(layout.room_at(l, 2, 2) == "a")
  assert(layout.room_at(l, 8, 2) == "b")
  assert(layout.room_at(l, 5, 2) == nil, "door cells are not rooms")
end

return T
