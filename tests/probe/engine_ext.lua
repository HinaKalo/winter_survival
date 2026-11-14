-- X18 probe: exercises all M2 engine_ext iso.* and audio.amb APIs, then fuzzes every iso function
-- added in M2 (lua_api.zig vs 13a02db) with NaN / Inf / 1e20 / negative / out-of-range / wrong-but-numeric values.
local probe = require("kit_probe")
local audio = require("audio")

probe.timeout(30)

local now = 0
local function wait_frames(n)
	for _ = 1, (n or 1) do
		coroutine.yield()
	end
end

-- ------------------------------------------------------------------ X18 fuzz (ENGINE-PLAN X18)
--
-- A Zig safety panic aborts the process, so reaching the end of each group is the no-crash proof;
-- the render path then runs over the damaged state. A Lua error is accepted only when it is the
-- binder rejecting an argument (non-integral / unrepresentable number for an i64 parameter, or a
-- wrong argument count); any other error fails the group. Return values are checked against their
-- documented shape (nil / 0 / false on rejection, finite numbers, ranges).

local NAN = 0 / 0
local INF = 1 / 0

-- f32 parameters: the binder accepts every number, so these reach the engine unchanged.
local BAD_F = { NAN, INF, -INF, 1e20, -1e20, 0, -1, 1e7, -1e7, 1e-30, 3.5 }
-- i64 parameters: integer-valued numbers pass the binder and reach the engine.
local BAD_I = { -1, 0, 1, 2.0, 129, 65535, 65536, -2147483649, 2147483648, math.maxinteger, math.mininteger, 1e6 }
-- i64 parameters: the binder must reject these with a Lua error (not a crash).
local BAD_I_REJECT = { NAN, INF, -INF, 1e20, -1e20, 2.5 }

local TILES_PNG = "assets/textures/tiles.png"
local SPRITE_PNG = "assets/sprites/char_placeholder.png"

local function isfin(x)
	return type(x) == "number" and x == x and x ~= INF and x ~= -INF
end

local function isint(x)
	return math.type(x) == "integer"
end

local function group(name)
	return { name = name, ok = true, calls = 0, rejected = 0 }
end

local function expect(g, cond, what)
	if not cond and g.ok then
		g.ok = false
		probe.info(g.name .. ": " .. what)
	end
end

-- pcall wrapper: returns true, results... on success; false on any error. Binder rejections are
-- counted; any other error is a failure of the group.
local function call(g, fn, ...)
	g.calls = g.calls + 1
	local r = table.pack(pcall(fn, ...))
	if r[1] then
		return true, table.unpack(r, 2, r.n)
	end
	local msg = tostring(r[2])
	if msg:find("Could not bind argument", 1, true) or msg:find("Invalid number of arguments", 1, true) then
		g.rejected = g.rejected + 1
	else
		expect(g, false, "unexpected error: " .. msg)
	end
	return false
end

local function finish_group(g)
	probe.check(string.format("X18 fuzz %s (%d calls, %d binder-rejected)", g.name, g.calls, g.rejected), g.ok)
end

local function each(list, fn)
	for _, v in ipairs(list) do
		fn(v)
	end
end

-- ---------------------------------------------------------------- map / tiles / paths

local function fuzz_map(g)
	-- map_create clamps both sides to [1, 128]
	each(BAD_I, function(v)
		call(g, iso.map_create, v, v)
		local s = iso.map_size()
		expect(g, s[1] >= 1 and s[1] <= 128 and s[2] >= 1 and s[2] <= 128, "map_size outside [1,128]")
	end)
	iso.map_create(24, 24)

	local t_floor = iso.tile_define_ex2(0, 48, -1, -1, false, false, false, 1)
	expect(g, isint(t_floor) and t_floor >= 0, "tile_define_ex2 must return integer kind >= 0")
	each(BAD_I, function(v)
		local ok, k = call(g, iso.tile_define_ex2, v, v, v, v, true, false, true, v)
		if ok then expect(g, isint(k) and k >= 0, "tile_define_ex2 kind not integer >= 0") end
		ok, k = call(g, iso.tile_define_ex, v, v, v, false, false, true, v)
		if ok then expect(g, isint(k) and k >= 0, "tile_define_ex kind not integer >= 0") end
	end)
	each(BAD_F, function(v)
		call(g, iso.map_set_height_unit, v)
		call(g, iso.map_set_base_depth, v)
	end)
	iso.map_set_height_unit(1.0)
	iso.map_set_base_depth(0.0)

	each(BAD_I, function(x)
		each(BAD_I, function(y)
			call(g, iso.tile_set_blocked, x, y, true)
			call(g, iso.tile_set_opaque, x, y, true)
			call(g, iso.tile_set_tag, x, y, x)
			call(g, iso.map_set, x, y, t_floor, y)
			local ok, f = call(g, iso.tile_flags, x, y)
			if ok and f ~= nil then
				expect(g, #f == 3 and (f[1] == 0 or f[1] == 1) and (f[2] == 0 or f[2] == 1) and f[3] >= 0 and f[3] <= 255,
					"tile_flags shape")
			end
			ok, f = call(g, iso.map_get, x, y)
			if ok and f ~= nil then expect(g, #f == 2, "map_get shape") end
			call(g, iso.map_top_y, x, y)
			call(g, iso.map_walkable, x, y)
			call(g, iso.map_can_step, x, y, y, x)
			call(g, iso.los, x, y, y, x)
			call(g, iso.highlight_tile, x, y, 1, 1, 1, 1)
		end)
	end)
	-- kinds outside u16 are ignored by map_set / map_fill; undefined kinds must not crash
	each({ -1, 65536, 65000 }, function(k)
		call(g, iso.map_set, 3, 3, k, 1)
		call(g, iso.map_fill, k, 1)
	end)
	iso.map_fill(t_floor, 1)
	iso.highlight_clear()

	-- path results: nil or cells that lie inside the map
	local sz = iso.map_size()
	local w, h = sz[1], sz[2]
	each({ { -5, -5, 30, 30 }, { 0, 0, 0, 0 }, { 2, 2, 9, 9 } }, function(c)
		for _, fn in ipairs({ iso.path_find, iso.path_find_adjacent }) do
			local ok, p = call(g, fn, c[1], c[2], c[3], c[4])
			if ok and p ~= nil then
				expect(g, #p <= 1024, "path longer than buffer")
				for _, cell in ipairs(p) do
					expect(g, cell[1] >= 0 and cell[1] < w and cell[2] >= 0 and cell[2] < h, "path cell outside map")
				end
			end
		end
	end)
	iso.map_fill(t_floor, 1)
	finish_group(g)
end

-- ---------------------------------------------------------------- camera / screen picking

local function fuzz_camera(g)
	each(BAD_F, function(v)
		call(g, iso.camera_set_target, v, v, v)
		local ok, t = call(g, iso.camera_get_target)
		if ok then expect(g, isfin(t[1]) and isfin(t[2]) and isfin(t[3]), "camera_get_target not finite") end
		call(g, iso.camera_set_zoom, v)
		ok, t = call(g, iso.camera_get_zoom)
		if ok then expect(g, isfin(t), "camera_get_zoom not finite") end
		call(g, iso.camera_set_view_height, v)
		call(g, iso.camera_set_ppu, v)
		ok, t = call(g, iso.camera_get_ppu)
		if ok then expect(g, isfin(t) and t >= 0, "camera_get_ppu must be finite >= 0") end
		call(g, iso.px_to_world, v)
		ok, t = call(g, iso.world_to_screen, v, v, v)
		if ok and t ~= nil then expect(g, isfin(t[1]) and isfin(t[2]), "world_to_screen not finite") end
		ok, t = call(g, iso.screen_to_tile, v, v)
		if ok and t ~= nil then expect(g, isint(t[1]) and isint(t[2]), "screen_to_tile must be integer cell") end
	end)
	each(BAD_I, function(v)
		call(g, iso.camera_follow, v)
	end)
	call(g, iso.camera_follow, 0)
	call(g, iso.camera_set_snap, false)
	call(g, iso.camera_set_snap, true)
	call(g, iso.camera_set_snap, nil)
	call(g, iso.camera_set_snap, true)
	local ok, yaw = call(g, iso.camera_get_yaw)
	if ok then expect(g, yaw == 45, "camera_get_yaw must stay 45 (D6)") end
	-- valid camera restored
	iso.camera_set_target(10, 0, 10)
	iso.camera_set_zoom(1.0)
	iso.camera_set_view_height(10)
	iso.camera_set_ppu(90.50967)
	ok, t = call(g, iso.mouse_tile)
	if ok and t ~= nil then expect(g, #t == 2, "mouse_tile shape") end
	finish_group(g)
end

-- ---------------------------------------------------------------- sheets / entities

local function fuzz_entities(g)
	-- start from an empty world so every entity alive here is one this group spawned
	iso.world_clear()
	-- sheets: bad frame sizes and paths return 0 (or a valid id); the tileset rejects bad dims
	each(BAD_I, function(w)
		each(BAD_I, function(hh)
			local ok, s = call(g, iso.sheet_load, SPRITE_PNG, w, hh)
			if ok then expect(g, isint(s) and s >= 0, "sheet_load must return integer >= 0") end
		end)
	end)
	local ok, s = call(g, iso.sheet_load, "assets/does/not/exist.png", 64, 96)
	expect(g, ok and s == 0, "missing sheet file must return 0")
	ok, s = call(g, iso.tileset_load, "assets/does/not/exist.png", 8, 8)
	expect(g, ok and s == false, "missing tileset must return false")
	each(BAD_I, function(c)
		-- tileset_load with a valid path and integer dims: only cols/rows <= 0 or > 4096 must be false
		local tok, r = call(g, iso.tileset_load, TILES_PNG, c, c)
		if tok and (c <= 0 or c > 4096) then expect(g, r == false, "tileset_load with bad dims must be false") end
	end)
	iso.tileset_load(TILES_PNG, 8, 8)

	local sh = iso.sheet_load(SPRITE_PNG, 64, 96)
	expect(g, sh > 0, "valid sheet_load must succeed")
	local live = iso.entity_spawn(sh, 3.5, 3.5, 1.0, 1.5)
	expect(g, live > 0, "valid entity_spawn must succeed")
	local spawned = { live }
	local function is_ours(id)
		for _, s2 in ipairs(spawned) do
			if s2 == id then return true end
		end
		return false
	end

	-- spawn: bogus sheet ids and non-finite / odd sizes return 0 or a usable id
	each({ -1, 0, 999, 4294967295, math.maxinteger }, function(id)
		local ok2, eid = call(g, iso.entity_spawn, id, 3.5, 3.5, 1, 1)
		if ok2 then
			expect(g, isint(eid) and eid >= 0, "entity_spawn must return integer >= 0")
			if eid > 0 then spawned[#spawned + 1] = eid end
		end
	end)
	each(BAD_F, function(v)
		local ok2, eid = call(g, iso.entity_spawn, sh, v, v, v, v)
		if ok2 then
			expect(g, isint(eid) and eid >= 0, "entity_spawn(float) must return integer >= 0")
			if eid > 0 then spawned[#spawned + 1] = eid end
		end
	end)
	local ok3, eid_neg = call(g, iso.entity_spawn, sh, 3.5, 3.5, -1, 1e7)
	if ok3 and eid_neg > 0 then spawned[#spawned + 1] = eid_neg end

	-- id-taking calls with bogus ids (never the entities spawned above)
	each(BAD_I, function(id)
		if is_ours(id) then return end
		call(g, iso.entity_set_visible, id, true)
		call(g, iso.entity_set_lit, id, false)
		call(g, iso.entity_set_pickable, id, true)
		call(g, iso.entity_set_flip, id, false)
		call(g, iso.entity_set_frame, id, id)
		call(g, iso.entity_play, id, id, id, 4.0, true)
		call(g, iso.entity_set_sheet, id, id)
		call(g, iso.entity_stop, id)
		call(g, iso.entity_move_to, id, 1.5, 1.5)
		call(g, iso.entity_set_pos, id, 1.5, 0, 1.5)
		call(g, iso.entity_set_speed, id, 2.0)
		call(g, iso.entity_set_size, id, 1.0, 1.0)
		call(g, iso.entity_set_size_px, id, 64, 96)
		call(g, iso.entity_set_tint, id, 1, 1, 1, 1)
		call(g, iso.entity_path_to, id, id, id)
		call(g, iso.entity_get_tile, id)
		local ok4, ex = call(g, iso.entity_exists, id)
		if ok4 then expect(g, ex == false, "bogus entity id must not exist") end
		local ok5, mv = call(g, iso.entity_is_moving, id)
		if ok5 then expect(g, mv == false, "bogus entity id must not be moving") end
		local ok6, ef = call(g, iso.entity_facing, id)
		if ok6 then expect(g, isint(ef) and ef == 0, "bogus entity_facing must be 0") end
		local ok7, lm = call(g, iso.entity_last_move, id)
		if ok7 then expect(g, #lm == 2 and lm[1] == 0 and lm[2] == 0, "bogus entity_last_move must be {0,0}") end
		local ok8, gp = call(g, iso.entity_get_pos, id)
		if ok8 then expect(g, gp == nil, "bogus entity_get_pos must be nil") end
		call(g, iso.entity_despawn, id)
	end)
	-- id-taking calls with wrong-but-numeric values on the live entity
	each(BAD_I, function(v)
		call(g, iso.entity_play, live, v, v, 4.0, false)
		call(g, iso.entity_set_frame, live, v)
		call(g, iso.entity_path_to, live, v, v)
		call(g, iso.entity_path_to, live, 9, v)
		call(g, iso.entity_set_sheet, live, v)
	end)
	each(BAD_F, function(v)
		call(g, iso.entity_set_pos, live, v, v, v)
		call(g, iso.entity_move_to, live, v, v)
		call(g, iso.entity_set_speed, live, v)
		call(g, iso.entity_set_size, live, v, v)
		call(g, iso.entity_set_size_px, live, v, v)
		call(g, iso.entity_set_tint, live, v, v, v, v)
		call(g, iso.entity_play, live, 0, 2, v, true)
		local ok9, pk = call(g, iso.entity_pick, v, v, true)
		if ok9 and pk ~= nil then expect(g, isint(pk) and pk > 0, "entity_pick id must be positive integer") end
	end)
	local ok10, pk2 = call(g, iso.entity_pick, 640, 360, false)
	if ok10 and pk2 ~= nil then expect(g, iso.entity_exists(pk2), "entity_pick returned a dead id") end

	-- restore a valid live entity, then clear everything we spawned
	iso.entity_set_pos(live, 4.5, 0, 4.5)
	iso.entity_set_size_px(live, 64, 96)
	iso.entity_set_size(live, 1.0, 1.5)
	iso.camera_follow(live)
	iso.camera_follow(0)
	for _, id in ipairs(spawned) do
		iso.entity_despawn(id)
	end
	expect(g, not iso.entity_exists(live), "despawned entity still exists")
	finish_group(g)
end

-- ---------------------------------------------------------------- overlays / lights / vision / input

local function fuzz_overlay_light_vision(g)
	-- overlay_add_tex: atlas outside 0..63 is rejected and counted once per call; 0..63 accepted
	local bad_atlas = { -1, 64, 65, 1000, 65536, math.maxinteger, math.mininteger }
	for _, a in ipairs(bad_atlas) do
		local before = iso.overlay_stats()[2]
		call(g, iso.overlay_add_tex, 1, 2, 2, a, 1, 1, 1, 1)
		local after = iso.overlay_stats()[2]
		expect(g, after - before == 1, "overlay_add_tex atlas " .. tostring(a) .. " not rejected exactly once")
	end
	for _, a in ipairs({ 0, 63 }) do
		local before = iso.overlay_stats()[2]
		call(g, iso.overlay_add_tex, 1, 2, 3, a, 1, 1, 1, 1)
		expect(g, iso.overlay_stats()[2] == before, "overlay_add_tex in-range atlas " .. a .. " counted as rejected")
	end
	each(BAD_I, function(v)
		call(g, iso.overlay_add, v, v, v, 1, 1, 1, 1)
		call(g, iso.overlay_add_mask, v, v, 1, 1, 1, 1)
		call(g, iso.overlay_clear, v)
	end)
	each(BAD_F, function(v)
		call(g, iso.overlay_add, 1, 2, 2, v, v, v, v)
		call(g, iso.overlay_add_tex, 1, 2, 2, 0, v, v, v, v)
		call(g, iso.overlay_add_mask, 2, 1, v, v, v, v)
	end)
	iso.overlay_clear_all()
	local ost = iso.overlay_stats()
	expect(g, #ost == 2 and ost[1] >= 0 and ost[2] >= 0, "overlay_stats must be 2 non-negative integers")
	local rs = iso.render_stats()
	expect(g, #rs == 3 and rs[1] >= 0 and rs[2] >= 0 and rs[3] >= 0, "render_stats must be 3 non-negative integers")

	-- colours and levels: non-finite is ignored, huge finite values are accepted
	each(BAD_F, function(v)
		call(g, iso.world_set_tint, v, v, v)
		call(g, iso.set_clear_color, v, v, v)
		call(g, iso.light_set_ambient, v, v, v)
		call(g, iso.fog_set_levels, v, v)
	end)
	iso.world_set_tint(1, 1, 1)
	iso.light_set_ambient(0.5, 0.5, 0.5)
	iso.fog_set_levels(0.35, 0.08)

	-- lights: light_add returns 0 when rejected; ids stay valid until removed
	local lids = {}
	each(BAD_F, function(v)
		local ok, id = call(g, iso.light_add, v, v, v, v, v, v)
		if ok then expect(g, isint(id) and id >= 0, "light_add must return integer >= 0") end
		ok, id = call(g, iso.light_add, 4.5, 4.5, 3.0, v, 1, 1)
		if ok and isint(id) and id > 0 then lids[#lids + 1] = id end
	end)
	each(BAD_I, function(v)
		call(g, iso.light_set_pos, v, 1.5, 1.5)
		call(g, iso.light_set_radius, v, 3.0)
		call(g, iso.light_set_color, v, 1, 1, 1)
		call(g, iso.light_set_enabled, v, true)
		call(g, iso.light_remove, v)
	end)
	each(BAD_F, function(v)
		local id = lids[1] or 0
		call(g, iso.light_set_pos, id, v, v)
		call(g, iso.light_set_radius, id, v)
		call(g, iso.light_set_color, id, v, v, v)
	end)
	each(BAD_I, function(x)
		local ok, lv = call(g, iso.light_level, x, x)
		if ok then expect(g, isfin(lv) and lv >= 0, "light_level must be finite >= 0") end
		call(g, iso.light_set_enabled, x, false)
	end)
	iso.light_clear()

	-- masks / fog / vision: bogus ids return nil/0/false, shapes stay right
	each(BAD_I, function(m)
		call(g, iso.mask_clear, m)
		call(g, iso.mask_or, m, 1)
		call(g, iso.mask_or, 1, m)
		local ok, c = call(g, iso.mask_count, m)
		if ok then expect(g, isint(c) and c >= 0, "mask_count must be integer >= 0") end
		local ok2, n = call(g, iso.fov_compute, m, 5, 5, 6, 1, 0, 180)
		if ok2 then expect(g, isint(n) and n >= 0, "fov_compute must return integer >= 0") end
		local ok3, vis = call(g, iso.fov_visible, m, m, m)
		if ok3 then expect(g, vis == false or vis == true, "fov_visible must return boolean") end
		local ok4, rc = call(g, iso.reach_compute, m, m, m, m)
		if ok4 then expect(g, isint(rc) and rc >= 0, "reach_compute must return integer >= 0") end
		call(g, iso.fog_set, m, m)
	end)
	each(BAD_F, function(v)
		local ok, n = call(g, iso.fov_compute, 1, 5, 5, v, v, v, v)
		if ok then expect(g, isint(n) and n >= 0, "fov_compute(float) must return integer >= 0") end
		local ok2, vc = call(g, iso.vision_can_see, 2, 2, v, v, v, v, 3, 3)
		if ok2 then expect(g, vc == false or vc == true, "vision_can_see must return boolean") end
	end)
	each(BAD_I, function(v)
		local ok, lo = call(g, iso.los, v, v, v, v)
		if ok then expect(g, lo == false or lo == true, "los must return boolean") end
		local ok2, vc = call(g, iso.vision_can_see, v, v, 4.0, 1, 0, 45, v, v)
		if ok2 then expect(g, vc == false or vc == true, "vision_can_see(int) must return boolean") end
	end)
	-- valid state restored for the rest of the probe
	iso.fog_set(1, 2)
	iso.fog_set_levels(0.35, 0.08)
	iso.mask_clear(1)
	iso.mask_clear(2)
	iso.fov_compute(1, 5, 5, 6, 1, 0, 180)
	finish_group(g)
end

-- ---------------------------------------------------------------- input helpers and binder rejections

local function fuzz_input(g)
	each(BAD_I, function(v)
		local ok1, d = call(g, iso.key_down, v)
		if ok1 then expect(g, d == false or d == true, "key_down must return boolean") end
		local ok2, p = call(g, iso.key_pressed, v)
		if ok2 then expect(g, p == false or p == true, "key_pressed must return boolean") end
		call(g, iso.mouse_pressed, v)
		call(g, iso.mouse_down, v)
	end)
	local ok, mp = call(g, iso.mouse_pos)
	if ok then expect(g, #mp == 2 and isfin(mp[1]) and isfin(mp[2]), "mouse_pos must be 2 finite numbers") end
	finish_group(g)
end

local function fuzz_binder(g)
	-- non-integral / unrepresentable numbers for i64 parameters must be rejected by the binder,
	-- so they never reach Zig (a rejection is counted; the call must not succeed)
	each(BAD_I_REJECT, function(v)
		-- either rejected by the binder, or converted to a harmless value (entity_exists -> false)
		local ok, r = call(g, iso.entity_exists, v)
		expect(g, (not ok) or r == false, "non-integral id returned true")
	end)
	finish_group(g)
end

local function fuzz_all()
	fuzz_map(group("map/tiles/paths"))
	fuzz_camera(group("camera/picking"))
	fuzz_entities(group("sheets/entities"))
	fuzz_overlay_light_vision(group("overlay/light/vision"))
	fuzz_input(group("input"))
	fuzz_binder(group("binder"))

	-- the render path runs over the damaged state, then the world is cleared and rebuilt
	wait_frames(3)
	iso.world_clear()
	iso.world_clear()
	wait_frames(2)
	iso.map_create(24, 24)
	iso.world_clear()
	wait_frames(1)
end

-- ------------------------------------------------------------------ scenario (M2 smoke, unchanged)

local function scenario()
	wait_frames(2)

	-- Map, tileset, tile_define_ex, flags
	iso.world_clear()
	iso.map_create(24, 24)
	local ok_ts = iso.tileset_load("assets/textures/tiles.png", 8, 8)
	probe.check("tileset_load succeeds", ok_ts == true)

	local t_floor = iso.tile_define_ex(0, 48, -1, false, false, false, 1)
	local t_wall = iso.tile_define_ex(52, 24, 60, true, false, true, 5)
	probe.check("tile_define_ex returns valid ids", t_floor >= 0 and t_wall > t_floor)

	for y = 0, 23 do
		for x = 0, 23 do
			iso.map_set(x, y, t_floor, 1)
		end
	end
	iso.map_set(8, 8, t_wall, 3)
	iso.tile_set_blocked(8, 8, true)
	iso.tile_set_opaque(8, 8, true)
	iso.tile_set_tag(8, 8, 9)
	local fl = iso.tile_flags(8, 8)
	probe.check("tile_flags reflects blocked/opaque/tag", fl ~= nil and fl[1] == 1 and fl[2] == 1 and fl[3] == 9)

	-- Pathfinding
	local path = iso.path_find(6, 8, 10, 8)
	probe.check("path_find routes around obstacle", path ~= nil and #path > 4)
	local adj = iso.path_find_adjacent(6, 8, 8, 8)
	probe.check("path_find_adjacent reaches neighbor of blocked tile", adj ~= nil and #adj >= 1)

	-- Vision & masks
	probe.check("los blocked across opaque wall", iso.los(6, 8, 10, 8) == false)
	probe.check("los clear in open space", iso.los(2, 2, 6, 2) == true)
	probe.check("vision_can_see cone check", iso.vision_can_see(2, 2, 10, 1, 0, 45, 6, 2) == true)
	probe.check("vision_can_see rejects behind", iso.vision_can_see(6, 2, 10, 1, 0, 45, 2, 2) == false)

	iso.mask_clear(1)
	iso.mask_clear(2)
	iso.fov_compute(1, 5, 5, 6, 1, 0, 180)
	probe.check("fov_compute populates mask 1", iso.mask_count(1) > 10)
	probe.check("fov_visible origin is true", iso.fov_visible(1, 5, 5) == true)
	iso.mask_or(2, 1)
	probe.check("mask_or copies into mask 2", iso.mask_count(2) == iso.mask_count(1))

	iso.mask_clear(3)
	iso.reach_compute(3, 5, 5, 3)
	probe.check("reach_compute populates mask 3", iso.mask_count(3) > 5)

	-- Fog & lighting
	iso.fog_set(1, 2)
	iso.fog_set_levels(0.35, 0.08)
	iso.light_set_ambient(0.15, 0.18, 0.25)
	local lid = iso.light_add(5.5, 5.5, 6.0, 1.0, 0.8, 0.5)
	probe.check("light_add returns id >= 0", lid >= 0)
	iso.light_set_pos(lid, 6.5, 6.5)
	iso.light_set_radius(lid, 7.0)
	iso.light_set_color(lid, 1.0, 0.9, 0.7)
	iso.light_set_enabled(lid, true)
	wait_frames(1)
	probe.check("light_level near light > ambient", iso.light_level(6, 6) > 0.4)
	iso.light_set_enabled(lid, false)
	iso.light_remove(lid)
	iso.light_clear()

	-- Overlays & world tint
	iso.world_set_tint(0.95, 0.98, 1.0)
	iso.overlay_add(1, 3, 3, 1.0, 0.5, 0.2, 0.4)
	iso.overlay_add_tex(1, 4, 3, 0, 0.2, 0.8, 1.0, 0.4)
	iso.overlay_add_mask(2, 3, 0.2, 0.9, 0.3, 0.3)
	iso.overlay_clear(1)
	iso.overlay_clear_all()

	-- Entities & camera
	local sh = iso.sheet_load("assets/sprites/char_placeholder.png", 64, 96)
	local eid = iso.entity_spawn(sh, 3.5, 3.5, 1.0, 1.5)
	iso.entity_set_visible(eid, true)
	iso.entity_set_lit(eid, true)
	iso.entity_set_pickable(eid, true)
	iso.entity_set_size(eid, 1.0, 1.5)
	iso.entity_set_size_px(eid, 64, 96)
	iso.entity_set_sheet(eid, sh)
	local ok_path = iso.entity_path_to(eid, 6, 3)
	probe.check("entity_path_to succeeds", ok_path == true)

	iso.camera_set_ppu(90.50967)
	iso.camera_set_snap(true)
	probe.check("camera_get_ppu matches set_ppu", math.abs(iso.camera_get_ppu() - 90.50967) < 0.01)
	local wx = iso.px_to_world(128)
	probe.check("px_to_world > 0", wx > 0)

	wait_frames(2)
	local _ = iso.entity_pick(640, 360, false)
	local stats = iso.render_stats()
	probe.check("render_stats returns 3 numbers with quads > 0", #stats == 3 and stats[1] > 0)

	-- Ambient audio channels
	audio.set_bus("amb", 0.5)
	local ch = audio.amb(1, "bgm/street_chip", { gain = 0.6 })
	probe.check("audio.amb rejects non-amb id cleanly", ch == false)
	probe.check("audio.current_amb(1) is nil when not playing", audio.current_amb(1) == nil)
	audio.amb_gain(1, 0.3)
	audio.stop_amb(1)
	probe.check("audio.stop_amb keeps channel 1 clear", audio.current_amb(1) == nil)

	fuzz_all()

	probe.check("script remains healthy", probe.script_ok())
	probe.finish()
end

local co = coroutine.create(scenario)

function _probe(t, dt)
	now = t
	if coroutine.status(co) == "dead" then
		return
	end
	local ok, err = coroutine.resume(co)
	if not ok then
		error(err, 0)
	end
end
