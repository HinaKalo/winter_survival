-- X18 probe: verifies M2 G2 (64x64 chunk rebuild <= 4, no quad overflow) & G4 (exterior/cutaway + door toggle).
local probe = require("kit_probe")
local street_block = require("data.locations.street_block")
local suburb_house = require("data.locations.suburb_house")
local mapbuild = require("view.mapbuild")

probe.timeout(30)

local function wait_frames(n)
	for _ = 1, (n or 1) do
		coroutine.yield()
	end
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
