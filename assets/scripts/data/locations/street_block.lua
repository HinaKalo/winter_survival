-- 64x64 outdoor street block with 4 suburb houses (6-level exterior walls), road, and street props.
local suburb_house = require("data.locations.suburb_house")

local W, H = 64, 64

local function stamp_suburb(rows, ox, oy)
	local src = suburb_house.variants.A.grid
	for ly = 1, #src do
		local line = rows[oy + ly]
		local srow = src[ly]
		rows[oy + ly] = line:sub(1, ox) .. srow .. line:sub(ox + #srow + 1)
	end
end

local function build_grid()
	local rows = {}
	local blank = string.rep(",", W)
	for y = 1, H do
		rows[y] = blank
	end
	stamp_suburb(rows, 8,  10)
	stamp_suburb(rows, 42, 10)
	stamp_suburb(rows, 8,  42)
	stamp_suburb(rows, 42, 42)
	return rows
end

return {
	id = "street_block",
	floor = "wood",
	wall = "brick",
	outdoor = "snow",
	variants = {
		A = {
			grid = build_grid(),
			legend = suburb_house.variants.A.legend,
			road_rects = {
				{ x0 = 0, y0 = 28, x1 = 63, y1 = 35, tile = "asphalt" },
				{ x0 = 0, y0 = 26, x1 = 63, y1 = 27, tile = "sidewalk" },
				{ x0 = 0, y0 = 36, x1 = 63, y1 = 37, tile = "sidewalk" },
			},
			props = {
				{ id = "out_car",         x = 20, y = 31, frame = 1 },
				{ id = "out_car",         x = 46, y = 32, frame = 0 },
				{ id = "out_tree_dead",   x = 4,  y = 24, frame = 1 },
				{ id = "out_tree_dead",   x = 58, y = 40, frame = 1 },
				{ id = "out_streetlight", x = 16, y = 27, frame = 1 },
				{ id = "out_streetlight", x = 44, y = 36, frame = 1 },
			},
			-- name = key of data/lights.lua (ART-AUDIO §3.3); radius/colour come from that table.
			lights = {
				{ name = "street", x = 16, y = 27 },
				{ name = "street", x = 44, y = 36 },
				{ name = "lamp", x = 10, y = 12 },
				{ name = "lamp", x = 44, y = 12 },
			},
			player_spawn = { x = 31, y = 32 },
			npc_patrol = {
				{ x = 24, y = 27 },
				{ x = 38, y = 27 },
				{ x = 38, y = 36 },
				{ x = 24, y = 36 },
			},
		},
	},
}
