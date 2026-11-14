-- X18 probe: exercises all M2 engine_ext iso.* and audio.amb APIs.
local probe = require("kit_probe")
local audio = require("audio")

probe.timeout(30)

local now = 0
local function wait_frames(n)
	for _ = 1, (n or 1) do
		coroutine.yield()
	end
end

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
