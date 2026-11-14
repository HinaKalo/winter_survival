-- X18 probe: verifies M2 G2 (64x64 chunk rebuild <= 4, no quad overflow), G4 (exterior/cutaway + door toggle)
-- and the G5 orientation of view/facing.lua against the live camera projection.
local probe = require("kit_probe")
local street_block = require("data.locations.street_block")
local suburb_house = require("data.locations.suburb_house")
local mapbuild = require("view.mapbuild")
local facing = require("view.facing")

probe.timeout(30)

-- render.zig `max_quads_per_batch`: a chunk whose quads exceed it is truncated (and the engine logs
-- "iso: chunk quad budget (...) exceeded" once to stderr). Chunk quads are clamped to the budget before
-- they are summed into render_stats()[1], so a total below the budget proves no chunk was truncated.
-- Lua cannot read the process log; ci/probe_junit.py fails the run if that warning appears in the log.
local QUAD_BUDGET = 10000

local function wait_frames(n)
	for _ = 1, (n or 1) do
		coroutine.yield()
	end
end

-- Waits until the renderer has rebuilt the map, then checks the quad total for this mode.
local function check_no_quad_overflow(label)
	wait_frames(2)
	local s = iso.render_stats()
	probe.info(string.format("%s: tile_quads=%d chunks_rebuilt_last=%d chunks_drawn_last=%d budget=%d",
		label, s[1], s[2], s[3], QUAD_BUDGET))
	probe.check(label .. ": tile_quads " .. s[1] .. " < budget " .. QUAD_BUDGET .. " (no quad truncation)", s[1] < QUAD_BUDGET)
	return s
end

-- G5 (orientation): facing.pick must agree with the real screen projection of the live camera for the
-- four axis moves (yaw 45: +X -> SE, +Z -> SW, -X -> NW, -Z -> NE). Screen right = x, screen down = y.
local function check_facing_vs_camera()
	local o = iso.world_to_screen(32, 0, 32)
	local cases = { { 1, 0, facing.SE }, { 0, 1, facing.SW }, { -1, 0, facing.NW }, { 0, -1, facing.NE } }
	local all = true
	for _, c in ipairs(cases) do
		local dx, dz, f = c[1], c[2], c[3]
		local p = iso.world_to_screen(32 + 4 * dx, 0, 32 + 4 * dz)
		local sx, sy = p[1] - o[1], p[2] - o[2]
		local right = (f == facing.SE or f == facing.NE)
		local down = (f == facing.SE or f == facing.SW)
		local ok = (sx > 0) == right and (sy > 0) == down and facing.pick(nil, dx, dz) == f
		all = all and ok
		probe.info(string.format("G5 move (%d,%d): screen delta (%.1f, %.1f) facing %d", dx, dz, sx, sy, f))
	end
	probe.check("G5: facing.pick matches the live camera projection for the 4 axis moves", all)
end

local function scenario()
	wait_frames(2)

	-- G2: 64x64 street_block in exterior mode (6-level walls)
	local plan_ext = mapbuild.plan(street_block, { mode = "exterior" })
	local state_ext = mapbuild.apply(plan_ext)
	iso.camera_set_ppu(90.50967)
	iso.camera_set_target(32, 0, 32)
	wait_frames(2)

	local s0 = iso.render_stats()
	probe.check("G2: 64x64 tile_quads > 0", s0[1] > 0)
	probe.check("G2: chunks_drawn_last > 0", s0[3] > 0)
	check_no_quad_overflow("G2 exterior")
	check_facing_vs_camera()

	-- Modify 1 cell -> chunks_rebuilt_last <= 4
	local tid_snow = state_ext.tile_ids.snow or 0
	iso.map_set(32, 32, tid_snow, 2)
	wait_frames(1)
	local s1 = iso.render_stats()
	probe.check("G2: modifying 1 cell rebuilds <= 4 chunks (got " .. tostring(s1[2]) .. ")", s1[2] >= 1 and s1[2] <= 4)

	-- G4: same template generates both exterior and cutaway
	local plan_sub_ext = mapbuild.plan(suburb_house, { mode = "exterior" })
	local plan_sub_cut = mapbuild.plan(suburb_house, { mode = "cutaway" })
	probe.check("G4: exterior and cutaway plans share dimensions", plan_sub_ext.w == plan_sub_cut.w and plan_sub_ext.h == plan_sub_cut.h)

	local plan_cut = mapbuild.plan(street_block, { mode = "cutaway" })
	local state_cut = mapbuild.apply(plan_cut)
	wait_frames(1)
	check_no_quad_overflow("G2 cutaway")

	-- Find a closed door with clear tiles on opposite sides (along X or Y)
	local test_door, ax, ay, bx, by = nil, 0, 0, 0, 0
	for _, d in pairs(state_cut.doors_by_key) do
		if not d.open then
			if iso.map_walkable(d.x - 1, d.y) and iso.map_walkable(d.x + 1, d.y) then
				test_door, ax, ay, bx, by = d, d.x - 1, d.y, d.x + 1, d.y
				break
			elseif iso.map_walkable(d.x, d.y - 1) and iso.map_walkable(d.x, d.y + 1) then
				test_door, ax, ay, bx, by = d, d.x, d.y - 1, d.x, d.y + 1
				break
			end
		end
	end
	probe.check("G4: found closed door to test", test_door ~= nil)

	if test_door then
		probe.check("G4: closed door blocks walkability", iso.map_walkable(test_door.x, test_door.y) == false)
		probe.check("G4: closed door blocks LOS", iso.los(ax, ay, bx, by) == false)

		local now_open = mapbuild.toggle_door(state_cut, test_door.x, test_door.y)
		wait_frames(1)
		probe.check("G4: toggle_door opens door", now_open == true)
		probe.check("G4: open door is walkable", iso.map_walkable(test_door.x, test_door.y) == true)
		probe.check("G4: open door allows LOS", iso.los(ax, ay, bx, by) == true)

		local now_closed = mapbuild.toggle_door(state_cut, test_door.x, test_door.y)
		wait_frames(1)
		probe.check("G4: toggle_door closes door again", now_closed == false)
		probe.check("G4: re-closed door blocks walkability & LOS", iso.map_walkable(test_door.x, test_door.y) == false and iso.los(ax, ay, bx, by) == false)
	end

	probe.check("G2/G4: script healthy", probe.script_ok())
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
