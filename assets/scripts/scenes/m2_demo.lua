-- M2 Demo Scene: 64x64 street_block, exterior/cutaway, doors, day/night lights, FOV, fog, pixel camera.
local scene = require("core.scene")
local theme = require("ui.theme")
local widgets = require("ui.widgets")
local street_block = require("data.locations.street_block")
local mapbuild = require("view.mapbuild")
local facing = require("view.facing")
local actors = require("view.actors")
local lightfov = require("view.lightfov")

local M = {
	mode = "cutaway",
	phase = "day",
	roof_on = false,
	state = nil,
	player = nil,
	npc = nil,
	patrol_idx = 1,
	last_ptile = nil,
	npc_dir = { 1, 0 },
	elapsed = 0,
}

local PHASES = { "day", "dusk", "night" }

local function next_phase(cur)
	for i, p in ipairs(PHASES) do
		if p == cur then
			return PHASES[(i % #PHASES) + 1]
		end
	end
	return "day"
end

local function build_world(keep_pos)
	local ppos = keep_pos and M.player and actors.pos(M.player) or nil
	local npos = keep_pos and M.npc and actors.pos(M.npc) or nil
	local pflash = M.player and M.player.flashlight_on or (M.phase == "night")

	local plan = mapbuild.plan(street_block, { mode = M.mode })
	M.state = mapbuild.apply(plan)
	if M.mode == "exterior" then
		M.roof_on = true
		mapbuild.set_roof_visible(M.state, true)
	else
		M.roof_on = false
	end

	local px = ppos and ppos[1] or (plan.player_spawn.x + 0.5)
	local pz = ppos and ppos[3] or (plan.player_spawn.y + 0.5)
	M.player = actors.spawn({
		sheet = "assets/sprites/char_marcus.png",
		x = px,
		z = pz,
		wpx = 64,
		hpx = 96,
		speed = 4.5,
		facing = facing.SE,
		flashlight = pflash,
		light_radius = 7.0,
	})

	local nspawn = plan.npc_patrol[1] or { x = 30, y = 30 }
	local nx = npos and npos[1] or (nspawn.x + 0.5)
	local nz = npos and npos[3] or (nspawn.y + 0.5)
	M.npc = actors.spawn({
		sheet = "assets/sprites/char_placeholder.png",
		x = nx,
		z = nz,
		wpx = 64,
		hpx = 96,
		speed = 2.4,
		facing = facing.SW,
	})
	iso.entity_set_tint(M.npc.id, 0.92, 0.78, 0.72, 1.0)

	iso.camera_set_ppu(90.50967)
	iso.camera_set_snap(true)
	iso.camera_set_zoom(1.0)
	iso.camera_follow(M.player.id)

	lightfov.init({ phase = M.phase })
	M.last_ptile = nil
end

local function toggle_nearest_door(max_dist)
	local pt = actors.tile(M.player)
	if not pt then return false end
	local best_d, best_dist = nil, (max_dist or 2.2)
	for _, d in pairs(M.state.doors_by_key) do
		local dx = d.x - pt[1]
		local dy = d.y - pt[2]
		local dist = math.sqrt(dx * dx + dy * dy)
		if dist <= best_dist then
			best_dist = dist
			best_d = d
		end
	end
	if best_d then
		mapbuild.toggle_door(M.state, best_d.x, best_d.y)
		M.last_ptile = nil
		return true
	end
	return false
end

function M:on_enter()
	local env_mode = os.getenv("WS_MODE")
	if env_mode == "exterior" or env_mode == "cutaway" then
		M.mode = env_mode
	end
	local env_phase = os.getenv("WS_PHASE")
	if env_phase == "day" or env_phase == "dusk" or env_phase == "night" then
		M.phase = env_phase
	end
	build_world(false)
end

function M:on_exit()
	iso.camera_follow(-1)
	iso.world_clear()
end

function M:update(dt)
	M.elapsed = M.elapsed + dt

	if iso.key_pressed(keys.ESCAPE) then
		scene.pop()
		return
	end
	if iso.key_pressed(keys.N) then
		M.phase = next_phase(M.phase)
		lightfov.set_ambient_phase(M.phase)
		if M.phase == "night" then
			actors.set_flashlight(M.player, true)
		end
	end
	if iso.key_pressed(keys.C) then
		M.mode = (M.mode == "cutaway") and "exterior" or "cutaway"
		build_world(true)
		return
	end
	if iso.key_pressed(keys.R) then
		M.roof_on = not M.roof_on
		mapbuild.set_roof_visible(M.state, M.roof_on)
	end
	if iso.key_pressed(keys.F) then
		actors.set_flashlight(M.player, not M.player.flashlight_on)
	end
	if iso.key_pressed(keys.E) then
		toggle_nearest_door(2.5)
	end
	if iso.key_pressed(keys.Q) then
		iso.camera_rotate(-1)
	elseif iso.key_pressed(keys.Z) then
		iso.camera_rotate(1)
	end

	-- Keyboard WASD / Arrow movement
	local dx, dz = 0, 0
	if iso.key_down(keys.W) or iso.key_down(keys.UP) then dz = dz - 1 end
	if iso.key_down(keys.S) or iso.key_down(keys.DOWN) then dz = dz + 1 end
	if iso.key_down(keys.A) or iso.key_down(keys.LEFT) then dx = dx - 1 end
	if iso.key_down(keys.D) or iso.key_down(keys.RIGHT) then dx = dx + 1 end
	if dx ~= 0 or dz ~= 0 then
		local len = math.sqrt(dx * dx + dz * dz)
		actors.move_dir(M.player, dx / len, dz / len, dt)
	elseif iso.mouse_pressed(0) then
		local mt = iso.mouse_tile()
		if mt then
			local key = tostring(mt[1]) .. "," .. tostring(mt[2])
			if M.state.doors_by_key[key] then
				mapbuild.toggle_door(M.state, mt[1], mt[2])
				M.last_ptile = nil
			else
				actors.move_to_tile(M.player, mt[1], mt[2])
			end
		end
	end

	-- NPC patrol
	local patrol = M.state.plan.npc_patrol
	if #patrol > 0 and not iso.entity_is_moving(M.npc.id) then
		local wp = patrol[M.patrol_idx]
		local nt = actors.tile(M.npc)
		if nt and nt[1] == wp.x and nt[2] == wp.y then
			M.patrol_idx = (M.patrol_idx % #patrol) + 1
			wp = patrol[M.patrol_idx]
		end
		actors.move_to_tile(M.npc, wp.x, wp.y)
	end

	actors.update(M.player)
	actors.update(M.npc)

	-- Update player FOV when player changes tile
	local pt = actors.tile(M.player)
	if pt and (not M.last_ptile or M.last_ptile[1] ~= pt[1] or M.last_ptile[2] ~= pt[2]) then
		M.last_ptile = { pt[1], pt[2] }
		lightfov.update_player_fov(pt[1], pt[2], 12)
	end

	-- Update NPC FOV cone
	local nt = actors.tile(M.npc)
	if nt then
		local lm = iso.entity_last_move(M.npc.id)
		if math.abs(lm[1]) > 1e-4 or math.abs(lm[2]) > 1e-4 then
			M.npc_dir = { lm[1], lm[2] }
		end
		lightfov.update_npc_fov(nt[1], nt[2], M.npc_dir[1], M.npc_dir[2], 8, 40)
	end
end

function M:draw()
	local sw, sh = ui.screen_size()
	local sf = theme.font("s")
	local stats = iso.render_stats()
	local pt = actors.tile(M.player) or { 0, 0 }

	widgets.panel(8, 8, sw - 16, 48, 0.78)
	local info = string.format(
		"M2 STREET BLOCK (64x64)  |  Mode: %s  |  Phase: %s  |  Light: %s  |  Pos: (%d,%d)  |  Quads: %d  Chunks: %d  Rebuilt: %d",
		string.upper(M.mode),
		string.upper(M.phase),
		M.player.flashlight_on and "ON" or "OFF",
		pt[1], pt[2],
		stats[1], stats[3], stats[2]
	)
	widgets.label(sf, info, 18, 14, sw - 36, theme.colors.text, 0)
	widgets.label(sf, "WASD/Click: Move/Door  |  E: Door  |  C: Cutaway/Exterior  |  R: Roof  |  N: Day/Dusk/Night  |  F: Flashlight  |  Q/Z: Rotate  |  ESC: Title", 18, 34, sw - 36, theme.colors.text_dim, 0)
	local _ = sh
end

return M
