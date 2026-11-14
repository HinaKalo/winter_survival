-- Lighting, fog-of-war, and NPC FOV cone overlay controller.
local M = {
	MASK_PLAYER_FOV = 1,
	MASK_EXPLORED = 2,
	MASK_NPC_FOV = 3,
	OVERLAY_NPC_FOV = 1,
}

local AMBIENT = {
	day   = { 0.92, 0.94, 0.98 },
	dusk  = { 0.45, 0.48, 0.62 },
	night = { 0.14, 0.17, 0.28 },
}

function M.init(opts)
	opts = opts or {}
	iso.mask_clear(M.MASK_PLAYER_FOV)
	iso.mask_clear(M.MASK_EXPLORED)
	iso.mask_clear(M.MASK_NPC_FOV)
	iso.overlay_clear(M.OVERLAY_NPC_FOV)
	iso.fog_set(M.MASK_PLAYER_FOV, M.MASK_EXPLORED)
	iso.fog_set_levels(opts.explored_k or 0.36, opts.unknown_k or 0.08)
	M.set_ambient_phase(opts.phase or "day")
end

function M.set_ambient_phase(phase)
	local c = AMBIENT[phase] or AMBIENT.day
	iso.light_set_ambient(c[1], c[2], c[3])
end

function M.update_player_fov(px, py, radius)
	iso.mask_clear(M.MASK_PLAYER_FOV)
	iso.fov_compute(M.MASK_PLAYER_FOV, px, py, radius or 10, 1, 0, 180)
	iso.mask_or(M.MASK_EXPLORED, M.MASK_PLAYER_FOV)
end

function M.update_npc_fov(nx, ny, dir_x, dir_y, radius, half_angle_deg, color)
	iso.mask_clear(M.MASK_NPC_FOV)
	iso.fov_compute(M.MASK_NPC_FOV, nx, ny, radius or 8, dir_x, dir_y, half_angle_deg or 40)
	iso.overlay_clear(M.OVERLAY_NPC_FOV)
	local c = color or { 1.0, 0.72, 0.20, 0.34 }
	iso.overlay_add_mask(M.OVERLAY_NPC_FOV, M.MASK_NPC_FOV, c[1], c[2], c[3], c[4])
end

return M
