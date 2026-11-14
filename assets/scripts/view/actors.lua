-- Actor view helper: sheet loading, facing-aware animation, movement & flashlight.
local facing = require("view.facing")
local lightfov = require("view.lightfov")

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
		-- Flashlight: "torch" from the ART-AUDIO §3.3 light table (data/lights.lua).
		actor.light_id = lightfov.add_light("torch", x, z, actor.flashlight_on)
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
	local x, z = pos[1], pos[3]
	local function walkable(px, pz)
		return iso.map_walkable(math.floor(px), math.floor(pz))
	end
	local tx, tz = x + dx * step, z + dz * step
	-- The goal is at most one tile away and every goal is kept on a walkable cell, so the straight
	-- segment can only cross the two axis-neighbour cells; a diagonal needs both of them free too.
	if walkable(tx, tz) and (dx == 0 or dz == 0 or (walkable(tx, z) and walkable(x, tz))) then
		iso.entity_move_to(actor.id, tx, tz)
	elseif dx ~= 0 and dz ~= 0 and walkable(tx, z) then
		iso.entity_move_to(actor.id, tx, z) -- slide along x
	elseif dx ~= 0 and dz ~= 0 and walkable(x, tz) then
		iso.entity_move_to(actor.id, x, tz) -- slide along z
	else
		iso.entity_stop(actor.id)
	end
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
	local dir = actor.facing
	if math.abs(lm[1]) > 1e-4 or math.abs(lm[2]) > 1e-4 then
		dir = facing.pick(actor.facing, lm[1], lm[2]) -- camera yaw is fixed at 45 deg (PLAN D6)
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
