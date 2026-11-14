-- M2 demo scene (dev only: entered via WS_SCENE=m2_demo or --script, never from the title menu).
-- street_block / suburb_house maps, exterior/cutaway, doors, hourly ambient light (time slider), FOV, fog, NPC cone.
-- Env: WS_SCENE=m2_demo, WS_MAP=street_block|suburb_house, WS_MODE=exterior|cutaway,
--      WS_PHASE=day|dusk|night|dawn or WS_HOUR=0..24.
local scene = require("core.scene")
local i18n = require("core.i18n")
local input = require("core.input")
local theme = require("ui.theme")
local widgets = require("ui.widgets")
local mapbuild = require("view.mapbuild")
local facing = require("view.facing")
local actors = require("view.actors")
local lightfov = require("view.lightfov")

local MAPS = { "street_block", "suburb_house" }
local PHASE_HOURS = { dawn = 5.5, day = 12.0, dusk = 19.0, night = 23.0 }
local HOUR_STEP = 1.0

local M = {
	map = "street_block",
	mode = "cutaway",
	hour = 12.0,
	roof_on = false,
	state = nil,
	player = nil,
	npc = nil,
	flash_on = nil,
	patrol_idx = 1,
	last_ptile = nil,
	npc_dir = { 1, 0 },
	elapsed = 0,
	menu_click = false,
	menu_over = false,
}

local function is_indoor()
	return M.map == "suburb_house" and M.mode == "cutaway"
end

-- Spiral-free scan: walkable tile closest to (cx, cy), at least min_d away from avoid.
local function find_walkable(plan, cx, cy, avoid, min_d)
	local best, best_d = nil, math.huge
	for _, c in ipairs(plan.cells or {}) do
		if iso.map_walkable(c.x, c.y) then
			local d = (c.x - cx) ^ 2 + (c.y - cy) ^ 2
			local far = true
			if avoid then
				far = ((c.x - avoid.x) ^ 2 + (c.y - avoid.y) ^ 2) >= min_d * min_d
			end
			if far and d < best_d then
				best, best_d = { x = c.x, y = c.y }, d
			end
		end
	end
	return best or { x = math.floor(plan.w / 2), y = math.floor(plan.h / 2) }
end

local function build_world(keep_pos)
	local ppos = keep_pos and M.player and actors.pos(M.player) or nil
	local npos = keep_pos and M.npc and actors.pos(M.npc) or nil
	if M.flash_on == nil then
		M.flash_on = lightfov.phase_of(M.hour) == "night"
	elseif M.player then
		M.flash_on = M.player.flashlight_on
	end

	lightfov.clear_lights() -- engine lights are wiped by mapbuild.apply
	local template = require("data.locations." .. M.map)
	local plan = mapbuild.plan(template, { mode = M.mode })
	M.state = mapbuild.apply(plan, { add_light = lightfov.add_light })
	if M.mode == "exterior" then
		M.roof_on = true
		mapbuild.set_roof_visible(M.state, true)
	else
		M.roof_on = false
	end

	local cx, cy = math.floor(plan.w / 2), math.floor(plan.h / 2)
	local pspawn = plan.player_spawn or find_walkable(plan, cx, cy)
	local px = ppos and ppos[1] or (pspawn.x + 0.5)
	local pz = ppos and ppos[3] or (pspawn.y + 0.5)
	-- Cached positions from the other map/mode may be out of range or inside walls.
	if ppos and (px < 0 or pz < 0 or px >= plan.w or pz >= plan.h or not iso.map_walkable(math.floor(px), math.floor(pz))) then
		px, pz = pspawn.x + 0.5, pspawn.y + 0.5
	end
	M.player = actors.spawn({
		sheet = "assets/sprites/char_marcus.png",
		x = px,
		z = pz,
		wpx = 64,
		hpx = 96,
		speed = 4.5,
		facing = facing.SE,
		flashlight = M.flash_on,
	})

	local patrol = plan.npc_patrol or {}
	local nspawn = patrol[1] or find_walkable(plan, cx, cy, { x = math.floor(px), y = math.floor(pz) }, 4)
	local nx = npos and npos[1] or (nspawn.x + 0.5)
	local nz = npos and npos[3] or (nspawn.y + 0.5)
	if npos and (nx < 0 or nz < 0 or nx >= plan.w or nz >= plan.h or not iso.map_walkable(math.floor(nx), math.floor(nz))) then
		nx, nz = nspawn.x + 0.5, nspawn.y + 0.5
	end
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
	M.patrol_idx = 1

	iso.camera_set_ppu(90.50967)
	iso.camera_set_snap(true)
	iso.camera_set_zoom(1.0)
	iso.camera_follow(M.player.id)

	lightfov.init({ hour = M.hour, indoor = is_indoor() })
	M.last_ptile = nil
end

local function toggle_door_at(x, y)
	if not (M.state and M.state.doors_by_key) then return false end
	if M.state.doors_by_key[tostring(x) .. "," .. tostring(y)] == nil then return false end
	mapbuild.toggle_door(M.state, x, y)
	lightfov.mark_dirty()
	return true
end

local function toggle_nearest_door(max_dist)
	local pt = actors.tile(M.player)
	if not pt or not (M.state and M.state.doors_by_key) then return false end
	local best, best_dist = nil, max_dist
	for _, d in pairs(M.state.doors_by_key) do
		local dist = math.sqrt((d.x - pt[1]) ^ 2 + (d.y - pt[2]) ^ 2)
		if dist <= best_dist then
			best_dist, best = dist, d
		end
	end
	return best ~= nil and toggle_door_at(best.x, best.y)
end

local function set_hour(h)
	M.hour = h % 24
	lightfov.set_time(M.hour, is_indoor())
end

function M:on_enter()
	local env_map = os.getenv("WS_MAP")
	for _, m in ipairs(MAPS) do
		if env_map == m then M.map = m end
	end
	-- The house is a cutaway interior by default.
	M.mode = (M.map == "suburb_house") and "cutaway" or M.mode
	local env_mode = os.getenv("WS_MODE")
	if env_mode == "exterior" or env_mode == "cutaway" then
		M.mode = env_mode
	end
	local env_phase = os.getenv("WS_PHASE")
	if env_phase and PHASE_HOURS[env_phase] then
		M.hour = PHASE_HOURS[env_phase]
	end
	local env_hour = tonumber(os.getenv("WS_HOUR") or "")
	if env_hour then
		M.hour = env_hour % 24
	end
	M.flash_on = nil
	M.menu_click, M.menu_over = false, false
	build_world(false)
end

function M:on_exit()
	iso.camera_follow(-1)
	iso.world_clear()
end

function M:update(dt)
	M.elapsed = M.elapsed + dt

	if input.pressed("system_menu") or input.pressed("open_wheel") or M.menu_click then
		scene.pop()
		return
	end
	if input.pressed("dev.time_prev") then
		set_hour(M.hour - HOUR_STEP)
	elseif input.pressed("dev.time_next") then
		set_hour(M.hour + HOUR_STEP)
	end
	if input.pressed("dev.map_toggle") then
		M.map = (M.map == "street_block") and "suburb_house" or "street_block"
		M.mode = (M.map == "suburb_house") and "cutaway" or M.mode
		build_world(false)
		return
	end
	if input.pressed("dev.mode_toggle") then
		M.mode = (M.mode == "cutaway") and "exterior" or "cutaway"
		build_world(true)
		return
	end
	if input.pressed("dev.roof_toggle") then
		M.roof_on = not M.roof_on
		mapbuild.set_roof_visible(M.state, M.roof_on)
	end
	if input.pressed("dev.flashlight") then
		actors.set_flashlight(M.player, not M.player.flashlight_on)
	end
	-- Direct control (move_dir action; cancels any click-move path)
	local dx, dz = input.move_vec()
	if dx ~= 0 or dz ~= 0 then
		local len = math.sqrt(dx * dx + dz * dz)
		actors.move_dir(M.player, dx / len, dz / len, dt)
	end

	-- Single mouse resolver: door under cursor -> toggle, else move there. `interact` (F) is keyboard only.
	if input.pressed("interact", "keyboard") or input.pressed("interact", "pad") then
		toggle_nearest_door(2.5)
	end
	if (dx == 0 and dz == 0) and not M.menu_over and (input.pressed("move_to", "mouse") or input.pressed("select", "mouse")) then
		local mt = iso.mouse_tile()
		if mt and not toggle_door_at(mt[1], mt[2]) then
			actors.move_to_tile(M.player, mt[1], mt[2])
		end
	end
	-- NPC patrol (street_block only; the house has no patrol route)
	local patrol = M.state.plan.npc_patrol or {}
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

	-- FOV sources; lightfov decides when to recompute (tile change / door toggle immediate, else <= 10 Hz).
	local pt = actors.tile(M.player)
	if pt then
		lightfov.set_player(pt[1], pt[2], 12)
		M.last_ptile = pt
	end
	local nt = actors.tile(M.npc)
	if nt then
		local lm = iso.entity_last_move(M.npc.id)
		if math.abs(lm[1]) > 1e-4 or math.abs(lm[2]) > 1e-4 then
			M.npc_dir = { lm[1], lm[2] }
		end
		lightfov.set_npc(nt[1], nt[2], M.npc_dir[1], M.npc_dir[2], 8, 40)
	end
	lightfov.tick(dt)
end

local function fmt_time(h)
	local total = math.floor((h % 24) * 60 + 0.5) % (24 * 60)
	return string.format("%02d:%02d", math.floor(total / 60), total % 60)
end

local KEY_LABELS = { COMMA = ",", PERIOD = ".", ESCAPE = "Esc" }

local function key_of(action)
	local t = input.format_binding("keyboard", input.get_binding("keyboard", action, 1))
	return KEY_LABELS[t] or t
end

function M:draw()
	local sw = ui.screen_size()
	local sf = theme.font("s")
	local stats = iso.render_stats()
	local pt = actors.tile(M.player) or { 0, 0 }

	widgets.panel(8, 8, sw - 16, 74, 0.78)
	local info = i18n.t("demo.hud.info", {
		map = i18n.t("demo.map." .. M.map),
		mode = i18n.t("demo.mode." .. M.mode),
		time = fmt_time(M.hour),
		phase = i18n.t("demo.phase." .. lightfov.phase_of(M.hour)),
		light = i18n.t(M.player.flashlight_on and "ui.on" or "ui.off"),
		x = pt[1],
		y = pt[2],
		quads = stats[1],
		chunks = stats[3],
		rebuilt = stats[2],
	})
	widgets.label(sf, info, 18, 14, sw - 36, theme.colors.text, 0)
	local help = i18n.t("demo.hud.help", {
		interact = key_of("interact"),
		mode = key_of("dev.mode_toggle"),
		roof = key_of("dev.roof_toggle"),
		map = key_of("dev.map_toggle"),
		time_prev = key_of("dev.time_prev"),
		time_next = key_of("dev.time_next"),
		flash = key_of("dev.flashlight"),
		back = key_of("system_menu"),
	})
	widgets.label(sf, help, 18, 34, sw - 36, theme.colors.text_dim, 0)

	-- system_menu mouse entry: Back button (consumed by update(); clicks on it never move the player).
	local brect = { x = sw - 108, y = 88, w = 100, h = 30 }
	local mx, my = ui.mouse_pos()
	M.menu_over = mx >= brect.x and mx < brect.x + brect.w and my >= brect.y and my < brect.y + brect.h
	if widgets.button("demo_back", brect, i18n.t("ui.back"), { font_kind = "s" }) then
		M.menu_click = true
	end

	-- Time slider (0..24 h), display only; step with the dev.time_* keys.
	local bx, by, bw = 18, 62, sw - 36
	ui.color(0.20, 0.24, 0.32, 1.0)
	ui.rect(bx, by, bw, 6)
	for h = 0, 24, 3 do
		ui.color(0.45, 0.50, 0.60, 1.0)
		ui.rect(bx + math.floor(bw * h / 24), by - 2, 1, 10)
	end
	ui.color(1.0, 0.80, 0.30, 1.0)
	ui.rect(bx + math.floor(bw * (M.hour % 24) / 24) - 2, by - 3, 5, 12)
end

return M
