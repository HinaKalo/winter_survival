-- Character facing (4-way isometric with hysteresis) and sprite-sheet frame lookup (ART-AUDIO §5.4-§5.6).
local M = {}

M.SE = 0
M.SW = 1
M.NE = 2
M.NW = 3

M.DIRS = {
	[0] = { row_base = 0, flip_x = false, fx =  1, fy =  0, sx =  0.70710678, sy =  0.70710678 }, -- SE
	[1] = { row_base = 0, flip_x = true,  fx =  0, fy =  1, sx = -0.70710678, sy =  0.70710678 }, -- SW
	[2] = { row_base = 4, flip_x = false, fx =  0, fy = -1, sx =  0.70710678, sy = -0.70710678 }, -- NE
	[3] = { row_base = 4, flip_x = true,  fx = -1, fy =  0, sx = -0.70710678, sy = -0.70710678 }, -- NW
}

M.ANIMS = {
	walk   = { row = 0, col = 0, len = 6, fps = 10.0, loop = true },
	idle   = { row = 0, col = 6, len = 2, fps = 1.5,  loop = true },
	sneak  = { row = 1, col = 0, len = 6, fps = 7.0,  loop = true },
	hurt   = { row = 1, col = 6, len = 2, fps = 13.3, loop = false },
	work   = { row = 2, col = 0, len = 4, fps = 4.0,  loop = true },
	attack = { row = 2, col = 4, len = 4, fps = 12.0, loop = false },
	aim    = { row = 3, col = 0, len = 2, fps = 4.0,  loop = false },
	down   = { row = 3, col = 2, len = 2, fps = 4.0,  loop = false },
}

local COS_HYST = math.cos(math.rad(67.5)) -- 45 deg half-quadrant + 22.5 deg hysteresis

--- Pick facing 0..3 from world horizontal delta (dx, dz) at camera yaw (default 45 deg).
function M.pick(prev, dx, dz, yaw_deg)
	if type(dx) ~= "number" or type(dz) ~= "number" then
		return prev or M.SE
	end
	local m = math.max(math.abs(dx), math.abs(dz))
	if m < 1e-6 then
		return prev or M.SE
	end
	local yaw = math.rad(yaw_deg or 45)
	local s, c = math.sin(yaw), math.cos(yaw)
	local r = dx * c - dz * s -- screen right
	local t = dx * s + dz * c -- screen down
	local len = math.sqrt(r * r + t * t)
	if len < 1e-9 then
		return prev or M.SE
	end
	local nr, nt = r / len, t / len

	if prev ~= nil and M.DIRS[prev] then
		local pd = M.DIRS[prev]
		local dot = nr * pd.sx + nt * pd.sy
		if dot > COS_HYST then
			return prev
		end
	end

	if r >= 0 then
		return (t >= 0) and M.SE or M.NE
	else
		return (t >= 0) and M.SW or M.NW
	end
end

function M.info(facing)
	return M.DIRS[facing] or M.DIRS[M.SE]
end

function M.anim_spec(facing, action)
	local d = M.info(facing)
	local a = M.ANIMS[action] or M.ANIMS.idle
	return {
		start = (d.row_base + a.row) * 8 + a.col,
		len = a.len,
		fps = a.fps,
		loop = a.loop,
		flip_x = d.flip_x,
	}
end

return M
