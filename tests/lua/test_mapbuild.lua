package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local mapbuild = require("view.mapbuild")
local tiles = require("data.tiles")
local suburb_house = require("data.locations.suburb_house")
local street_block = require("data.locations.street_block")

local T = {}

function T.suburb_house_exterior_vs_cutaway()
	local ext = mapbuild.plan(suburb_house, { mode = "exterior" })
	local cut = mapbuild.plan(suburb_house, { mode = "cutaway" })

	assert(ext.w == 12 and ext.h == 10)
	assert(#ext.cells == 120 and #cut.cells == 120)
	-- Corner (0,0) is outer wall: height 6 in exterior, 2 in cutaway
	assert(ext.cells[1].height == 6 and ext.cells[1].opaque == true)
	assert(cut.cells[1].height == 2 and cut.cells[1].opaque == true)
	-- Roof exists only in exterior mode
	assert(#ext.roof > 0)
	assert(#cut.roof == 0)
	-- All mapped tile keys exist in data/tiles.lua
	for _, c in ipairs(ext.cells) do
		if c.tile ~= nil then
			assert(tiles[c.tile] ~= nil, "unmapped tile: " .. tostring(c.tile))
		end
	end
end

function T.street_block_64x64_deterministic()
	local p1 = mapbuild.plan(street_block, { mode = "exterior" })
	local p2 = mapbuild.plan(street_block, { mode = "exterior" })
	assert(p1.w == 64 and p1.h == 64)
	assert(#p1.cells == 64 * 64)
	for i = 1, #p1.cells do
		assert(p1.cells[i].tile == p2.cells[i].tile)
		assert(p1.cells[i].height == p2.cells[i].height)
	end
end

return T
