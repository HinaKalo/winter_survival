-- Actor view helper: sheet loading, facing-aware animation, movement & flashlight.
local facing = require("view.facing")

local M = {}

local function apply_anim(actor, action, dir, force)
	if not force and actor.action == action and actor.facing == dir then
		return
	end
	actor.action = action
	actor.facing = dir
	local spec = facing.anim_spec(dir, action)
	iso.entity_set_flip(actor.id, spec.flip_x)
	iso.entity_play(actor.id, spec.start, spec.len, spec.fps, spec.loop)
end

function M.spawn(opts)
	opts = opts or {}
	local path = opts.sheet or "assets/sprites/char_placeholder.png"
	local wpx = opts.wpx or 64
	local hpx = opts.hpx or 96
	local sid = iso.sheet_load(path, wpx, hpx)
	local x = opts.x or 10.5
	local z = opts.z or 10.5
	local id = iso.entity_spawn(sid, x, z, 1.0, 1.5)
	iso.entity_set_size_px(id, wpx, hpx)
	iso.entity_set_lit(id, opts.lit ~= false)
	iso.entity_set_pickable(id, opts.pickable ~= false)
	iso.entity_set_speed(id, opts.speed or 4.2)

	local actor = {
		id = id,
		sheet = sid,
		facing = opts.facing or facing.SE,
		action = "idle",
		light_id = nil,
		flashlight_on = opts.flashlight == true,
	}
	apply_anim(actor, "idle", actor.facing, true)

	if opts.flashlight ~= nil then
		local lid = iso.light_add(x, z, opts.light_radius or 6.5, 1.0, 0.94, 0.80)
		iso.light_set_enabled(lid, actor.flashlight_on)
		actor.light_id = lid
	end

	return actor
end

function M.set_action(actor, action, dir)
	apply_anim(actor, action or actor.action, dir or actor.facing, false)
end

function M.set_facing(actor, dir)
	apply_anim(actor, actor.action, dir, false)
end

function M.move_to_tile(actor, tx, ty)
	return iso.entity_path_to(actor.id, tx, ty)
end

function M.move_dir(actor, dx, dz, dt)
	if dx == 0 and dz == 0 then
		return
	end
	local pos = iso.entity_get_pos(actor.id)
	if not pos then
		return
	end
	local step = math.max(0.35, (dt or 0.016) * 10)
	iso.entity_move_to(actor.id, pos[1] + dx * step, pos[3] + dz * step)
end

function M.set_flashlight(actor, on)
	actor.flashlight_on = on == true
	if actor.light_id then
		iso.light_set_enabled(actor.light_id, actor.flashlight_on)
	end
end

function M.tile(actor)
	return iso.entity_get_tile(actor.id)
end

function M.pos(actor)
	return iso.entity_get_pos(actor.id)
end

function M.update(actor)
	local moving = iso.entity_is_moving(actor.id)
	local lm = iso.entity_last_move(actor.id)
	local yaw = iso.camera_get_yaw()
	local dir = actor.facing
	if math.abs(lm[1]) > 1e-4 or math.abs(lm[2]) > 1e-4 then
		dir = facing.pick(actor.facing, lm[1], lm[2], yaw)
	end
	apply_anim(actor, moving and "walk" or "idle", dir, false)

	if actor.light_id and actor.flashlight_on then
		local pos = iso.entity_get_pos(actor.id)
		if pos then
			iso.light_set_pos(actor.light_id, pos[1], pos[3])
		end
	end
end

return M
