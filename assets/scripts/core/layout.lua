-- 地点/家园模板的纯解析（M2 L3 与 M3 共用）。
-- 不 require 任何引擎库，也不 require view/。输出是普通表：
--   { id, variant, width, height,
--     cells = flat row-major list of cell tables ({x, y, kind, material, prop, room, ...}),
--     grid[y+1][x+1] = the same cell tables (use layout.cell(l, x, y)),
--     rooms[id] = { id, name, area, cells = {cell...} (count = area),
--                   envelope = {wall, hole, window, broken_window, board, door, door_open},
--                   openings = {{kind, x, y, room, outer}},
--                   links = {{room, kind = "door"|"wall", count, cells}} (one entry per kind) },
--     room_order, openings, props = {{x, y, prop, slot, room}}, ... }
-- 房间 = 被墙和门隔开的室内地面连通区域。畸形模板返回 nil, err，绝不抛错。
local legend = require("data.legend")
local util = require("core.util")

local M = {}

local symbol_fallback = {
  ["#"] = { kind = "wall" },
  ["="] = { kind = "wall", inner = true },
  ["."] = { kind = "floor" },
  [","] = { kind = "outdoor" },
  ["+"] = { kind = "door", inner = true },
  ["D"] = { kind = "door" },
  ["w"] = { kind = "window" },
  [" "] = { kind = "void" },
}

local function symbol_table()
  local out = {}
  local src = (legend and legend.symbols) or {}
  for sym, def in pairs(symbol_fallback) do out[sym] = def end
  for sym, def in pairs(src) do out[sym] = def end
  return out
end

local DIRS = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }

local function is_open(cell)
  return cell and (cell.kind == "floor" or cell.kind == "prop")
end

local function neighbor(grid, x, y, dx, dy)
  local row = grid[y + dy + 1]
  if not row then return nil end
  return row[x + dx + 1]
end

local function outside_adjacent(grid, x, y)
  for _, d in ipairs(DIRS) do
    local c = neighbor(grid, x, y, d[1], d[2])
    if not c or c.kind == "void" or c.kind == "outdoor" then
      return true
    end
  end
  return false
end

--- Parse a template variant.
-- template: { id, floor, wall, variants = { A = { grid, legend, floor, wall, rooms } } }
-- variant: variant key (default "A")
-- opts: { strict = true }
function M.parse(template, variant, opts)
  opts = opts or {}
  if type(template) ~= "table" then return nil, "layout: template must be a table" end
  variant = variant or "A"
  local v
  if type(template.variants) == "table" and template.variants[variant] ~= nil then
    v = template.variants[variant]
  else
    v = template
  end
  if type(v) ~= "table" or type(v.grid) ~= "table" then return nil, "layout: missing grid" end
  if #v.grid == 0 then return nil, "layout: empty grid" end
  for y = 1, #v.grid do
    if type(v.grid[y]) ~= "string" then return nil, "layout: row " .. y .. " is not a string" end
  end
  local width = #v.grid[1]
  if width == 0 then return nil, "layout: empty grid" end
  for y = 1, #v.grid do
    if #v.grid[y] ~= width then
      return nil, "layout: row " .. y .. " has length " .. #v.grid[y] .. ", want " .. width
    end
  end

  local symbols = symbol_table()
  if v.legend ~= nil and type(v.legend) ~= "table" then return nil, "layout: legend must be a table" end
  local custom = v.legend or {}
  for _, sym in ipairs(util.sorted_keys(custom)) do
    local def = custom[sym]
    if type(sym) ~= "string" or #sym ~= 1 then
      return nil, "layout: legend key must be a single character: " .. tostring(sym)
    end
    if type(def) ~= "table" then return nil, "layout: legend entry " .. sym .. " is not a table" end
    symbols[sym] = { kind = "prop", prop = def.prop, slot = def.slot, opaque = def.opaque }
  end
  if v.rooms ~= nil and type(v.rooms) ~= "table" then return nil, "layout: rooms must be a table" end

  local grid = {}
  local rooms = {}
  local room_order = {}
  local cells_flat = {}

  local function get(x, y)
    local row = grid[y + 1]
    return row and row[x + 1]
  end

  -- 1. build cells
  for y = 0, #v.grid - 1 do
    local row = {}
    grid[y + 1] = row
    local line = v.grid[y + 1]
    for x = 0, width - 1 do
      local sym = line:sub(x + 1, x + 1)
      local def = symbols[sym]
      if not def then
        if opts.strict ~= false then
          return nil, string.format("layout: unknown symbol %q at (%d,%d)", sym, x, y)
        end
        def = { kind = "void" }
      end
      local cell = {
        x = x, y = y, sym = sym,
        kind = def.kind,
        material = (def.kind == "floor" and (v.floor or template.floor)) or nil,
        prop = def.prop, slot = def.slot, opaque = def.opaque,
      }
      row[x + 1] = cell
      cells_flat[#cells_flat + 1] = cell
    end
  end

  -- 2. classify walls/windows/doors: outer if adjacent to void/outdoor
  for _, cell in ipairs(cells_flat) do
    if cell.kind == "wall" or cell.kind == "window" or cell.kind == "door" then
      cell.outer = outside_adjacent(grid, cell.x, cell.y) and true or false
      if cell.kind == "wall" then
        cell.wall_kind = cell.outer and "outer" or "inner"
      end
    end
  end

  -- 3. flood fill rooms over floor cells (doors split rooms)
  local visit = {}
  local auto = 0
  local queue_x, queue_y = {}, {}
  local function room_of_flood(sx, sy)
    local qx, qy = { sx }, { sy }
    local head = 1
    local cells = {}
    visit[sy .. "," .. sx] = true
    while head <= #qx do
      local x, y = qx[head], qy[head]
      head = head + 1
      local cell = get(x, y)
      cells[#cells + 1] = cell
      for _, d in ipairs(DIRS) do
        local nx, ny = x + d[1], y + d[2]
        local nc = get(nx, ny)
        local key = ny .. "," .. nx
        if nc and is_open(nc) and not visit[key] then
          visit[key] = true
          qx[#qx + 1] = nx
          qy[#qy + 1] = ny
        end
      end
    end
    return cells
  end

  -- anchors: map cell -> semantic room id
  local anchors = {}
  for id in pairs(v.rooms or {}) do
    if type(id) ~= "string" then
      return nil, "layout: anchor id must be a string, got " .. type(id) .. " " .. tostring(id)
    end
  end
  local anchor_ids = util.sorted_keys(v.rooms or {})
  for _, id in ipairs(anchor_ids) do
    local a = v.rooms[id]
    if type(a) ~= "table" or type(a.x) ~= "number" or type(a.y) ~= "number" then
      return nil, "layout: anchor " .. tostring(id) .. " needs numeric x and y"
    end
    if a.x % 1 ~= 0 or a.y % 1 ~= 0 then
      return nil, "layout: anchor " .. id .. " needs integer x and y"
    end
    if not is_open(get(a.x, a.y)) then
      return nil, string.format("layout: anchor %s at (%d,%d) is not on an open cell", id, a.x, a.y)
    end
    local k = a.y .. "," .. a.x
    if anchors[k] then
      return nil, "layout: duplicate anchor cell " .. k .. " for " .. tostring(anchors[k]) .. " and " .. tostring(id)
    end
    anchors[k] = id
  end

  for y = 0, #v.grid - 1 do
    for x = 0, width - 1 do
      local cell = get(x, y)
      if is_open(cell) and not visit[y .. "," .. x] then
        local cells = room_of_flood(x, y)
        local id
        for _, c in ipairs(cells) do
          local a = anchors[c.y .. "," .. c.x]
          if a then
            if id then
              return nil, "layout: anchors " .. id .. " and " .. a .. " are in the same room (each room is claimed once)"
            end
            id = a
          end
        end
        if not id then
          auto = auto + 1
          id = "room_" .. auto
        end
        if rooms[id] then return nil, "layout: duplicate room id " .. tostring(id) end
        local room = {
          id = id,
          name = "room." .. id .. ".name",
          area = #cells,
          cells = cells,
          openings = {},
          envelope = { wall = 0, hole = 0, window = 0, broken_window = 0, board = 0, door = 0, door_open = 0 },
          links = {},
        }
        rooms[id] = room
        room_order[#room_order + 1] = id
        for _, c in ipairs(cells) do
          c.room = id
        end
      end
    end
  end

  -- 4. room boundaries. Scan every wall/window/door once and attach to rooms.
  local link_index, link_keys = {}, {}
  local openings = {}
  local props = {}
  for _, cell in ipairs(cells_flat) do
    if cell.kind == "wall" or cell.kind == "window" or cell.kind == "door" then
      local adjacent_rooms, adjacent_seen = {}, {}  -- ids in DIRS order
      for _, d in ipairs(DIRS) do
        local nc = neighbor(grid, cell.x, cell.y, d[1], d[2])
        if nc and is_open(nc) and nc.room and not adjacent_seen[nc.room] then
          adjacent_seen[nc.room] = true
          adjacent_rooms[#adjacent_rooms + 1] = nc.room
        end
      end
      if cell.outer then
        -- outer envelope belongs to the first adjacent room in DIRS order (or none)
        local room_id = adjacent_rooms[1]
        if room_id then
          local room = rooms[room_id]
          local kind = cell.kind
          if kind == "wall" then
            room.envelope.wall = room.envelope.wall + 1
          elseif kind == "window" then
            room.envelope.window = room.envelope.window + 1
          else
            room.envelope.door = room.envelope.door + 1
          end
          local op = { kind = kind, x = cell.x, y = cell.y, room = room_id, outer = true }
          room.openings[#room.openings + 1] = op
          openings[#openings + 1] = op
          cell.room = cell.room or room_id
        end
      else
        -- inner partition: connect the two rooms that touch it
        local ids = {}
        for i, id in ipairs(adjacent_rooms) do ids[i] = id end
        table.sort(ids)
        if #ids >= 2 then
          -- every pair of touching rooms gets a link (T-junctions touch 3+)
          for i = 1, #ids - 1 do
            for j = i + 1, #ids do
              local a, b = ids[i], ids[j]
              local key = a .. "|" .. b
              local idx = link_index[key]
              if not idx then
                idx = { a = a, b = b, wall = 0, door = 0, wall_cells = {}, door_cells = {} }
                link_index[key] = idx
                link_keys[#link_keys + 1] = key
              end
              if cell.kind == "door" then
                idx.door = idx.door + 1
                idx.door_cells[#idx.door_cells + 1] = { x = cell.x, y = cell.y, kind = "door" }
              else
                idx.wall = idx.wall + 1
                idx.wall_cells[#idx.wall_cells + 1] = { x = cell.x, y = cell.y, kind = cell.kind }
              end
            end
          end
          openings[#openings + 1] = {
            kind = cell.kind, x = cell.x, y = cell.y, room = ids[1], room2 = ids[2], inner = true,
          }
        end
      end
    elseif cell.kind == "prop" then
      openings[#openings + 1] = { kind = "prop", x = cell.x, y = cell.y, prop = cell.prop }
      props[#props + 1] = { x = cell.x, y = cell.y, prop = cell.prop, slot = cell.slot, room = cell.room }
    end
  end

  table.sort(link_keys)
  for _, k in ipairs(link_keys) do
    local link = link_index[k]
    local function emit(from, to)
      local list = rooms[from].links
      if link.door > 0 then
        list[#list + 1] = { room = to, kind = "door", count = link.door, cells = util.deep_copy(link.door_cells) }
      end
      if link.wall > 0 then
        list[#list + 1] = { room = to, kind = "wall", count = link.wall, cells = util.deep_copy(link.wall_cells) }
      end
    end
    emit(link.a, link.b)
    emit(link.b, link.a)
  end
  for _, id in ipairs(room_order) do
    table.sort(rooms[id].links, function(p, q)
      if p.room ~= q.room then return p.room < q.room end
      return p.kind < q.kind
    end)
  end

  return {
    id = template.id,
    variant = variant,
    width = width,
    height = #v.grid,
    floor = v.floor or template.floor,
    wall = v.wall or template.wall,
    grid = grid,
    cells = cells_flat,
    rooms = rooms,
    room_order = room_order,
    openings = openings,
    props = props,
    damage = v.damage,
    stations = v.stations,
    storage = v.storage,
    rubble = v.rubble,
  }
end

function M.cell(layout, x, y)
  local row = layout.grid[y + 1]
  return row and row[x + 1]
end

function M.room_at(layout, x, y)
  local c = M.cell(layout, x, y)
  return c and c.room
end

-- Collect a room's boundary positions for runtime damage/insulation bookkeeping.
function M.room_openings(layout, room_id)
  local room = layout.rooms[room_id]
  return room and room.openings or {}
end

return M
