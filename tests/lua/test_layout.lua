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

local function find_link(l, a, b, kind)
  for _, e in ipairs(l.rooms[a].links) do
    if e.room == b and e.kind == kind then return e end
  end
end

function T.inner_links()
  local l = assert(layout.parse(house(), "A"))
  local door = find_link(l, "a", "b", "door")
  local wall = find_link(l, "a", "b", "wall")
  assert(door and door.count == 1, "a/b has one door")
  assert(wall and wall.count == 4, "a/b shared wall count")
  assert(#door.cells == 1 and #wall.cells == 4, "cells recorded per kind")
  -- one entry per kind: exactly two links a -> b
  local n = 0
  for _, e in ipairs(l.rooms.a.links) do if e.room == "b" then n = n + 1 end end
  assert(n == 2, "one link entry per kind, got " .. n)
  local bd, bw = find_link(l, "b", "a", "door"), find_link(l, "b", "a", "wall")
  assert(bd and bw and bd.count == door.count and bw.count == wall.count, "links are symmetric")
end

function T.room_cells_and_props()
  local l = assert(layout.parse(house(), "A"))
  assert(l.rooms.a.cell_list == nil, "cell_list removed")
  assert(#l.rooms.a.cells == l.rooms.a.area and l.rooms.a.area == 20)
  assert(type(l.rooms.a.cells[1]) == "table" and l.rooms.a.cells[1].room == "a")
  assert(#l.props == 1)
  local p = l.props[1]
  assert(p.x == 2 and p.y == 1 and p.prop == "counter" and p.room == "a")
  assert(#l.cells == l.width * l.height, "flat row-major cell list")
  assert(l.cells[1].x == 0 and l.cells[2].x == 1 and l.cells[l.width + 1].y == 1)
end

function T.exterior_wall_between_two_rooms()
  -- (2,0) is an exterior wall cell touching room a (left) and room b (right).
  -- DIRS order is up, right, down, left, so the owner must be b, every time.
  local tmpl = {
    id = "two", variants = { A = {
      grid = { "#.#.#", "#.#.#", "#####" },
      rooms = { a = { x = 1, y = 0 }, b = { x = 3, y = 0 } },
    } },
  }
  for _ = 1, 5 do
    local l = assert(layout.parse(tmpl, "A"))
    local function has(room)
      for _, op in ipairs(l.rooms[room].openings) do
        if op.x == 2 and op.y == 0 then return true end
      end
      return false
    end
    assert(has("b") and not has("a"), "owner of shared exterior cell is the first room in DIRS order")
  end
end

function T.partition_links_between_three_rooms()
  -- a | b share the x=3 column; a and b both sit on top of c.
  local tmpl = {
    id = "tj", variants = { A = {
      grid = {
        "#######",
        "#..=..#",
        "#..=..#",
        "###=###",
        "#.....#",
        "#######",
      },
      rooms = { a = { x = 1, y = 1 }, b = { x = 4, y = 1 }, c = { x = 1, y = 4 } },
    } },
  }
  local l = assert(layout.parse(tmpl, "A"))
  assert(find_link(l, "a", "b", "wall"), "a-b link")
  assert(find_link(l, "a", "c", "wall"), "a-c link")
  assert(find_link(l, "b", "c", "wall"), "b-c link")
end

function T.t_junction_cell_touching_three_rooms()
  -- (3,1) is '=' with rooms above (a), left (b) and right (c).
  local tmpl = {
    id = "tj3", variants = { A = {
      grid = {
        "###.###",
        "##.=.##",
        "##.#.##",
        "#######",
      },
      rooms = { a = { x = 3, y = 0 }, b = { x = 2, y = 1 }, c = { x = 4, y = 1 } },
    } },
  }
  local l = assert(layout.parse(tmpl, "A"))
  assert(#l.room_order == 3, "three rooms, got " .. #l.room_order)
  assert(find_link(l, "a", "b", "wall"), "a-b")
  assert(find_link(l, "a", "c", "wall"), "a-c")
  assert(find_link(l, "b", "c", "wall"), "b-c (third pair of the T-junction)")
end

function T.duplicate_anchors_fail()
  local tmpl = {
    id = "dup", variants = { A = {
      grid = { "#####", "#...#", "#####" },
      rooms = { a = { x = 1, y = 1 }, b = { x = 1, y = 1 } },
    } },
  }
  local l, err = layout.parse(tmpl, "A")
  assert(l == nil and type(err) == "string" and err:find("duplicate anchor"), tostring(err))
end

function T.malformed_templates_return_errors()
  local function bad(name, tmpl)
    local ok, l, err = pcall(layout.parse, tmpl, "A")
    assert(ok, name .. " must not throw: " .. tostring(l))
    assert(l == nil and type(err) == "string", name .. " must return nil, err")
  end
  bad("empty grid", { variants = { A = { grid = {} } } })
  bad("non-string row", { variants = { A = { grid = { 5 } } } })
  bad("legend entry not a table", { variants = { A = { grid = { "#K#" }, legend = { K = "counter" } } } })
  bad("legend key too long", { variants = { A = { grid = { "###" }, legend = { KK = { prop = "x" } } } } })
  bad("anchor without x/y", { variants = { A = { grid = { "###", "#.#", "###" }, rooms = { a = {} } } } })
  bad("anchor not a table", { variants = { A = { grid = { "###", "#.#", "###" }, rooms = { a = 5 } } } })
  bad("rooms not a table", { variants = { A = { grid = { "###", "#.#", "###" }, rooms = 5 } } })
  bad("grid not a table", { variants = { A = { grid = "###" } } })
  bad("variants not a table", { variants = 5 })
end

local function anchor_case(rooms, grid)
  return { id = "anc", variants = { A = { grid = grid or { "#####", "#...#", "#####" }, rooms = rooms } } }
end

function T.anchor_id_must_be_string()
  local ok, l, err = pcall(layout.parse, anchor_case({ [1] = { x = 1, y = 1 } }), "A")
  assert(ok, "must not throw")
  assert(l == nil and type(err) == "string" and err:find("string"), tostring(err))
end

function T.anchor_must_be_on_open_cell()
  -- wall cell
  local l, err = layout.parse(anchor_case({ a = { x = 0, y = 0 } }), "A")
  assert(l == nil and type(err) == "string" and err:find("open cell"), tostring(err))
  -- outside the grid
  l, err = layout.parse(anchor_case({ a = { x = 40, y = 40 } }), "A")
  assert(l == nil and type(err) == "string" and err:find("open cell"), tostring(err))
  -- door cell
  l, err = layout.parse(anchor_case({ a = { x = 2, y = 0 } }, { "##+##", "#...#", "#####" }), "A")
  assert(l == nil and type(err) == "string" and err:find("open cell"), tostring(err))
end

function T.anchor_claimed_only_once()
  -- two different anchors inside the same connected room
  local l, err = layout.parse(anchor_case({ a = { x = 1, y = 1 }, b = { x = 3, y = 1 } }), "A")
  assert(l == nil and type(err) == "string" and err:find("same room"), tostring(err))
end

function T.valid_anchor_still_parses()
  local l, err = layout.parse(anchor_case({ a = { x = 1, y = 1 } }), "A")
  assert(l and l.rooms.a, err)
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
