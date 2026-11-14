package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local facing = require("view.facing")

local T = {}

function T.four_facings_and_flip()
	-- At yaw=45: +X -> SE (0), +Z -> SW (1), -Z -> NE (2), -X -> NW (3)
	assert(facing.pick(nil, 1, 0) == facing.SE)
	assert(facing.pick(nil, 0, 1) == facing.SW)
	assert(facing.pick(nil, 0, -1) == facing.NE)
	assert(facing.pick(nil, -1, 0) == facing.NW)

	assert(facing.info(facing.SE).flip_x == false)
	assert(facing.info(facing.SW).flip_x == true)
	assert(facing.info(facing.NE).flip_x == false)
	assert(facing.info(facing.NW).flip_x == true)
end

function T.hysteresis_prevents_jitter()
	-- Start SE: screen (1, 1)/sqrt(2); nudging slightly past boundary stays SE
	local f = facing.pick(facing.SE, 0.9, 1.1)
	assert(f == facing.SE)
	-- Opposite direction flips immediately
	local f2 = facing.pick(facing.SE, -1, 0)
	assert(f2 == facing.NW)
end

function T.anim_frame_indices()
	local w_se = facing.anim_spec(facing.SE, "walk")
	assert(w_se.start == 0 and w_se.len == 6 and w_se.flip_x == false)
	local i_sw = facing.anim_spec(facing.SW, "idle")
	assert(i_sw.start == 6 and i_sw.len == 2 and i_sw.flip_x == true)
	local w_ne = facing.anim_spec(facing.NE, "walk")
	assert(w_ne.start == 32 and w_ne.len == 6 and w_ne.flip_x == false)
	local i_nw = facing.anim_spec(facing.NW, "idle")
	assert(i_nw.start == 38 and i_nw.len == 2 and i_nw.flip_x == true)
end

return T
