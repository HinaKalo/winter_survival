-- 验收测试，编码代理不得修改（M2-fix，主代理编写；见 docs/M2-PLAN.md §6）。
-- Covers the Codex review findings on the merged M2 (2026-11-14):
--   F1 directional movement (actors.move_dir) must respect map collision (walls, closed doors, diagonals)
--   F3 the demo must configure the camera pixel scale before spawning, so first entry gets correct sizes
--   F4 entity_set_size_px stores exactly wpx/ppu x hpx/ppu world units (no extra pitch factor)
--   F5 entity_pick must agree with the rendered billboard (64x96 px sprite is pickable over its full height)
-- Needs the read-back binding iso.entity_get_size(id) -> { w, h } (world units) or nil.
local probe = require("kit_probe")
local scene = require("core.scene")
local mapbuild = require("view.mapbuild")
local actors = require("view.actors")
local street_block = require("data.locations.street_block")

probe.timeout(60)

local PPU = 90.50967
local DT = 1 / 60

local function wait_frames(n)
	for _ = 1, (n or 1) do
		coroutine.yield()
	end
end

local function near(a, b, eps)
	return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (eps or 1e-3)
end

local function size_px(id)
	local s = iso.entity_get_size and iso.entity_get_size(id)
	if not s then return nil end
	local ppu = iso.camera_get_ppu()
	return s[1] * ppu, s[2] * ppu
end

-- ------------------------------------------------------------------ F3: demo first entry

local function check_demo_first_entry()
	iso.camera_set_ppu(0) -- the state a fresh process has before the demo runs
	local demo = require("scenes.m2_demo")
	scene.push(demo)
	wait_frames(3)
	probe.check("F3: demo set a pixel scale", near(iso.camera_get_ppu(), PPU, 1e-2))
	for _, who in ipairs({ "player", "npc" }) do
		local a = demo[who]
		local w, h = nil, nil
		if a then w, h = size_px(a.id) end
		probe.info(string.format("F3: %s size %s x %s px", who, tostring(w), tostring(h)))
		probe.check("F3: demo " .. who .. " is 64x96 px on first entry", near(w, 64, 0.5) and near(h, 96, 0.5))
	end
	scene.pop()
	wait_frames(2)
end

-- ------------------------------------------------------------------ world for the remaining checks

local state

local function build_map()
	state = mapbuild.apply(mapbuild.plan(street_block, { mode = "cutaway" }))
	iso.camera_set_ppu(PPU)
	iso.camera_set_snap(true)
	iso.camera_set_zoom(1.0)
	wait_frames(2)
end

-- ------------------------------------------------------------------ F4 / F5: size and picking

local function clear_around(cx, cy, r)
	for y = cy - r, cy + r do
		for x = cx - r, cx + r do
			iso.map_set(x, y, 0, 0)
		end
	end
end

local function check_size_and_pick()
	local cx, cy = 32, 32
	clear_around(cx, cy, 7) -- no tiles that could occlude the sprite in front or behind
	local sid = iso.sheet_load("assets/sprites/char_placeholder.png", 64, 96)
	local id = iso.entity_spawn(sid, cx + 0.5, cy + 0.5, 1.0, 1.5)
	iso.entity_set_pickable(id, true)
	iso.entity_set_frame(id, 0)
	iso.entity_set_size_px(id, 64, 96)
	iso.camera_set_target(cx + 0.5, 0, cy + 0.5)
	wait_frames(3)

	local s = iso.entity_get_size and iso.entity_get_size(id)
	probe.check("F4: iso.entity_get_size exists and returns {w,h}", type(s) == "table")
	if s then
		probe.check("F4: size_px 64x96 stores w = 64/ppu", near(s[1], 64 / PPU))
		probe.check("F4: size_px 64x96 stores h = 96/ppu (no pitch factor)", near(s[2], 96 / PPU))
	end

	local foot = iso.world_to_screen(cx + 0.5, 0, cy + 0.5)
	probe.check("F5: foot projects on screen", foot ~= nil)
	if not foot then return end
	local fx, fy = foot[1], foot[2]
	local function pick(dx, up, alpha)
		return iso.entity_pick(fx + dx, fy - up, alpha == true)
	end
	-- geometry (no alpha test): the 64x96 px billboard is pickable over its whole rendered rectangle
	local all_hit = true
	for _, up in ipairs({ 4, 30, 60, 80, 88, 92 }) do
		local ok = pick(0, up) == id
		if not ok then probe.info("F5: miss at " .. up .. " px above the foot") end
		all_hit = all_hit and ok
	end
	probe.check("F5: picks hit from the foot to 92 px above it", all_hit)
	probe.check("F5: no hit 104 px above the foot (sprite is 96 px)", pick(0, 104) ~= id)
	probe.check("F5: hits 28 px left/right of centre", pick(-28, 48) == id and pick(28, 48) == id)
	probe.check("F5: no hit 40 px left/right of centre", pick(-40, 48) ~= id and pick(40, 48) ~= id)
	-- alpha test samples the texel that is drawn there: frame 0 column 32 is opaque from 24 to 70 px
	-- above the foot and transparent from 74 to 88 px (rows 8..22 of the 96-px frame)
	probe.check("F5: alpha pick hits the opaque torso (60 px up)", pick(0, 60, true) == id)
	probe.check("F5: alpha pick ignores the transparent area above the head (80 px up)", pick(0, 80, true) ~= id)
	iso.entity_despawn(id)
	wait_frames(1)
end

-- ------------------------------------------------------------------ F1: directional movement collision

-- every sampled position must be on a walkable cell
local function drive(actor, dx, dz, frames)
	local ok = true
	for _ = 1, frames do
		actors.move_dir(actor, dx, dz, DT)
		wait_frames(1)
		local p = iso.entity_get_pos(actor.id)
		if p and not iso.map_walkable(math.floor(p[1]), math.floor(p[3])) then
			ok = false
		end
	end
	return ok
end

local function find_wall_east()
	-- a blocked cell W with three walkable cells to its west and walkable cells N/S of the first one
	for y = 2, 61 do
		for x = 5, 61 do
			if not iso.map_walkable(x, y) and iso.map_walkable(x - 1, y) and iso.map_walkable(x - 2, y)
				and iso.map_walkable(x - 3, y) then
				local closed_door = state.doors_by_key and state.doors_by_key[x .. "," .. y]
				if not closed_door then return x, y end
			end
		end
	end
end

local function find_closed_door()
	for _, d in pairs(state.doors_by_key or {}) do
		if not d.open and iso.map_walkable(d.x - 1, d.y) and iso.map_walkable(d.x - 2, d.y) then
			return d.x, d.y, 1, 0
		end
		if not d.open and iso.map_walkable(d.x, d.y - 1) and iso.map_walkable(d.x, d.y - 2) then
			return d.x, d.y, 0, 1
		end
	end
end

local function check_move_collision()
	local wx, wy = find_wall_east()
	probe.check("F1: found a wall with open floor to its west", wx ~= nil)
	if wx then
		local a = actors.spawn({ x = wx - 1 + 0.5, z = wy + 0.5, speed = 4.2, flashlight = nil })
		wait_frames(1)
		probe.check("F1: holding right into a wall never enters a blocked cell", drive(a, 1, 0, 90))
		local p = iso.entity_get_pos(a.id)
		probe.check("F1: stopped west of the wall (x < " .. wx .. ")", p and p[1] < wx)
		probe.check("F1: holding diagonally into the wall never enters a blocked cell", drive(a, 1, 1, 60) and drive(a, 1, -1, 60))
		-- the fix must not freeze movement: walking away from the wall still covers ground
		iso.entity_set_pos(a.id, wx - 1 + 0.5, 0, wy + 0.5)
		wait_frames(1)
		local x0 = iso.entity_get_pos(a.id)[1]
		drive(a, -1, 0, 30)
		local x1 = iso.entity_get_pos(a.id)[1]
		probe.info(string.format("F1: open-floor move covered %.2f tiles in 0.5 s", x0 - x1))
		probe.check("F1: moving away from the wall still moves >= 1 tile in 0.5 s", x0 - x1 >= 1.0)
		iso.entity_despawn(a.id)
	end

	local dx_, dy_, ax, az = find_closed_door()
	probe.check("F1: found a closed door with floor in front", dx_ ~= nil)
	if dx_ then
		local a = actors.spawn({ x = dx_ - ax + 0.5, z = dy_ - az + 0.5, speed = 4.2 })
		wait_frames(1)
		probe.check("F1: holding toward a closed door never enters it", drive(a, ax, az, 90))
		iso.entity_despawn(a.id)
	end
end

local function scenario()
	wait_frames(2)
	check_demo_first_entry()
	build_map()
	check_move_collision()
	check_size_and_pick()
	probe.check("M2-fix: script healthy", probe.script_ok())
	probe.finish()
end

local co = coroutine.create(scenario)

function _probe(t, dt)
	if coroutine.status(co) == "dead" then
		return
	end
	local ok, err = coroutine.resume(co)
	if not ok then
		error(err, 0)
	end
end
