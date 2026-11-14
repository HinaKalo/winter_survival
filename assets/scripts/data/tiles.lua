-- Material name -> tile atlas cell mapping (ART-AUDIO §4.2, 8x8 atlas, 64x64 cells; M2-PLAN §5.1).
-- Side segmentation (TileDef): level 0-1 = side_base (unset = side), top 2 levels = side_cap, rest = side.
-- A wall of <= 2 levels draws one segment with priority side_base > side_cap > side, so every 2-level
-- def below sets side_cap = -1 and every 6-level (ext_*) def sets side_base explicitly.
local T = {}

local function def(top, side, side_cap, side_base, solid, opaque, tag)
	return {
		top = top, side = side, side_cap = side_cap, side_base = side_base,
		solid = solid, liquid = false, opaque = opaque, tag = tag,
	}
end

-- ground / floors (no side_base needed)
T.snow           = def(0,  48, -1, -1, false, false, 1)
T.snow_drift     = def(1,  48, -1, -1, false, false, 1)
T.snow_packed    = def(2,  48, -1, -1, false, false, 1)
T.ice            = def(3,  49, -1, -1, false, false, 2)
T.asphalt        = def(4,  50, -1, -1, false, false, 3)
T.asphalt_line   = def(5,  50, -1, -1, false, false, 3)
T.sidewalk       = def(6,  50, -1, -1, false, false, 3)
T.wood           = def(8,  52, -1, -1, false, false, 4)
T.carpet         = def(10, 52, -1, -1, false, false, 4)
T.tile           = def(12, 52, -1, -1, false, false, 4)
T.concrete_floor = def(15, 52, -1, -1, false, false, 4)

-- floor cells occupied by a prop: same look, tag 8, blocked
for _, f in ipairs({ "wood", "carpet", "tile", "concrete_floor" }) do
	local b = T[f]
	T["prop_" .. f] = def(b.top, b.side, -1, -1, true, false, 8)
end

-- wall materials: body slot (also used as the wall-top slot: "same material" cross-section, §4.4)
local WALLS = { brick = 24, siding = 26, concrete = 28, plaster = 32 }
-- door kinds -> closed-door slot (40 wood, 41 metal); 42 = open doorway
local DOORS = { wood = 40, metal = 41 }

for name, slot in pairs(WALLS) do
	-- cutaway: 2 levels, one segment
	T[name]               = def(slot, slot, -1, slot, true, true, 5)
	T["window_" .. name]  = def(slot, 43,   -1, -1,   true, false, 7)
	-- exterior: 6 levels
	T["ext_wall_" .. name]   = def(slot, slot, 60, slot, true, true, 5)
	T["ext_window_" .. name] = def(slot, 43,   61, slot, true, true, 7)
	for kind, dslot in pairs(DOORS) do
		T["ext_door_" .. kind .. "_" .. name] = def(slot, slot, 61, dslot, true, true, 6)
	end
end

-- cutaway door cells are 0-height (the door leaf is an entity); flags are set per cell by mapbuild
T.door_wood  = def(8, 40, -1, -1, false, true,  6)
T.door_metal = def(8, 41, -1, -1, false, true,  6)
T.door_open  = def(8, 42, -1, -1, false, false, 6)

-- roofs (exterior only): top 56 tile / 57 snow, eaves 53 / 54
T.roof_tile = def(56, 53, -1, -1, true, true, 9)
T.roof_snow = def(57, 54, -1, -1, true, true, 9)

return T
