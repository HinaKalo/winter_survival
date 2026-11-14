package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local layout = require("core.layout")
local tiles = require("data.tiles")
local suburb_house = require("data.locations.suburb_house")
local street_block = require("data.locations.street_block")

local T = {}

function T.tiles_mapping_has_required_materials()
	for _, k in ipairs({ "snow", "asphalt", "wood", "brick", "plaster", "door_wood", "door_metal", "door_open", "window_brick", "window_plaster", "ext_wall_brick", "ext_window_brick", "ext_door_wood_brick", "ext_door_metal_brick", "roof_snow", "roof_tile" }) do
		assert(tiles[k] ~= nil, "missing material in data/tiles.lua: " .. k)
	end
end

local WORLD_A = {
	"##########+###",
	"#K.K..#B..B..#",
	"#...T.#......#",
	"####+##...b..#",
	"#L...L+###+###",
	"#..S..#C.....#",
	"#..f..+...w..#",
	"####D#########",
}

function T.suburb_house_grid_matches_world_layout_a()
	local g = suburb_house.variants.A.grid
	assert(#g == #WORLD_A)
	for i = 1, #WORLD_A do
		assert(g[i] == WORLD_A[i], "row " .. i .. " differs from WORLD layout A")
	end
	-- every letter used in the grid is defined by the legend (or the generic legend)
	local generic = require("data.legend").symbols
	for _, row in ipairs(g) do
		for ch in row:gmatch(".") do
			assert(generic[ch] or suburb_house.variants.A.legend[ch], "undefined legend letter " .. ch)
		end
	end
end

function T.tile_defs_wall_segments()
	local w = tiles.ext_wall_brick
	assert(w.side_base == 24 and w.side == 24 and w.side_cap == 60)
	local win = tiles.ext_window_brick
	assert(win.side_base == 24 and win.side == 43 and win.side_cap == 61)
	assert(tiles.ext_door_wood_brick.side_base == 40 and tiles.ext_door_metal_brick.side_base == 41)
	assert(tiles.ext_door_wood_brick.side == 24 and tiles.ext_door_wood_brick.side_cap == 61)
	assert(tiles.roof_snow.top == 57 and tiles.roof_tile.top == 56)
	-- no wall top uses the foundation slot 52
	for name, d in pairs(tiles) do
		if name:find("wall") or name:find("window") or name:find("door") or name == "brick" or name == "plaster" then
			assert(d.top ~= 52, name .. " uses foundation slot 52 as top")
		end
	end
end

function T.suburb_house_parses_three_rooms()
	local parsed = layout.parse(suburb_house, "A")
	assert(parsed.width == 14 and parsed.height == 8)
	assert(parsed.rooms.living ~= nil)
	assert(parsed.rooms.kitchen ~= nil)
	assert(parsed.rooms.bedroom ~= nil)
end

function T.suburb_house_a_has_four_rooms_with_props_inside_rooms()
	local parsed = layout.parse(suburb_house, "A")
	-- kitchen, living, bedroom + the unnamed lower-right room behind door (10,4); doors split rooms, props do not
	assert(#parsed.room_order == 4, "house A room count: " .. #parsed.room_order)
	local function room_at(x, y) return layout.room_at(parsed, x, y) end
	-- kitchen contains counters (K), table (T) and the open floor between them (props are part of the room)
	for _, p in ipairs({ { 4, 1 }, { 5, 1 }, { 5, 2 }, { 1, 1 }, { 3, 1 }, { 4, 2 } }) do
		assert(room_at(p[1], p[2]) == "kitchen", ("(%d,%d) not in kitchen"):format(p[1], p[2]))
	end
	assert(room_at(2, 5) == "living" and room_at(3, 5) == "living" and room_at(1, 4) == "living")
	assert(room_at(8, 2) == "bedroom" and room_at(10, 3) == "bedroom")
	local back = room_at(8, 5)
	assert(back and back ~= "kitchen" and back ~= "living" and back ~= "bedroom", "lower-right room must be a separate unnamed room")
	assert(room_at(11, 6) == back and room_at(7, 5) == back)
end

function T.street_block_64x64_parses_four_houses()
	local parsed = layout.parse(street_block, "A")
	assert(parsed.width == 64 and parsed.height == 64)
	-- four stamped copies of suburb_house A (4 rooms each); street_block has no room anchors
	assert(#parsed.room_order == 16, "street block room count: " .. #parsed.room_order)
end

return T
