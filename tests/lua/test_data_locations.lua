package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local layout = require("core.layout")
local tiles = require("data.tiles")
local suburb_house = require("data.locations.suburb_house")
local street_block = require("data.locations.street_block")

local T = {}

function T.tiles_mapping_has_required_materials()
	for _, k in ipairs({ "snow", "asphalt", "wood", "brick", "plaster", "door_closed", "door_open", "window", "roof_snow" }) do
		assert(tiles[k] ~= nil, "missing material in data/tiles.lua: " .. k)
	end
end

function T.suburb_house_parses_three_rooms()
	local parsed = layout.parse(suburb_house, "A")
	assert(parsed.width == 12 and parsed.height == 10)
	assert(parsed.rooms.living ~= nil)
	assert(parsed.rooms.kitchen ~= nil)
	assert(parsed.rooms.bedroom ~= nil)
end

function T.street_block_64x64_parses_12_rooms()
	local parsed = layout.parse(street_block, "A")
	assert(parsed.width == 64 and parsed.height == 64)
	assert(#parsed.room_order == 12)
end

return T
