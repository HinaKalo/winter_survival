-- Pure map planner built on core/layout.lua (zero engine calls; apply() added in L4).
local layout = require("core.layout")

local M = {}

local PROP_SPECS = {
	fac_stove       = { sprite = "assets/sprites/props/fac_stove.png",       w = 64, h = 64, cols = 3, frame = 1 },
	furn_table      = { sprite = "assets/sprites/props/furn_table.png",      w = 64, h = 64, cols = 2, frame = 0 },
	furn_bed        = { sprite = "assets/sprites/props/furn_bed.png",        w = 64, h = 64, cols = 3, frame = 0 },
	cont_crate      = { sprite = "assets/sprites/props/cont_crate.png",      w = 32, h = 32, cols = 3, frame = 0 },
	out_tree_dead   = { sprite = "assets/sprites/props/out_tree_dead.png",   w = 64, h = 96, cols = 2, frame = 1 },
	out_car         = { sprite = "assets/sprites/props/out_car.png",         w = 96, h = 64, cols = 3, frame = 1 },
	out_streetlight = { sprite = "assets/sprites/props/out_streetlight.png", w = 32, h = 96, cols = 2, frame = 1 },
}

local function hash2d(x, y)
	local h = (x * 73856093 + y * 19349663) % 2147483647
	if h < 0 then h = -h end
	return h
end

local function outdoor_tile(x, y, road_rects)
	for _, r in ipairs(road_rects or {}) do
		if x >= r.x0 and x <= r.x1 and y >= r.y0 and y <= r.y1 then
			if r.tile == "asphalt" then
				return (y == 31 and x % 4 < 2) and "asphalt_line" or "asphalt"
			end
			return r.tile
		end
	end
	return (hash2d(x, y) % 5 == 0) and "snow_drift" or "snow"
end

--- Pure planner: parses template via core/layout and enriches with heights, roofs, and atlas keys.
function M.plan(template, opts)
	opts = opts or {}
	local variant = opts.variant or "A"
	local mode = opts.mode or "exterior"
	local parsed = layout.parse(template, variant, { strict = opts.strict })
	local v = template.variants and template.variants[variant] or template

	local outer_wall_h = (mode == "cutaway") and 2 or 6
	local inner_wall_h = 2
	local outer_wall_key = parsed.wall or "brick"
	local floor_key = parsed.floor or "wood"
	local door_overrides = opts.doors or {}

	local cells = {}
	local doors = {}
	local props = {}
	local roof = {}

	for _, c in ipairs(parsed.cells) do
		local key = nil
		local height = 0
		local blocked = false
		local opaque = false
		local indoor = false

		if c.kind == "void" then
			key = nil
			height = 0
		elseif c.kind == "outdoor" then
			key = outdoor_tile(c.x, c.y, v.road_rects)
			height = 0
		elseif c.kind == "floor" then
			key = c.material or floor_key
			height = 0
			indoor = true
		elseif c.kind == "prop" then
			key = floor_key
			height = 0
			indoor = true
			local spec = PROP_SPECS[c.prop]
			if spec then
				props[#props + 1] = {
					id = c.prop,
					x = c.x,
					y = c.y,
					sprite = spec.sprite,
					w = spec.w,
					h = spec.h,
					frame = spec.frame,
				}
			end
		elseif c.kind == "wall" then
			local is_outer = (c.wall_kind == "outer")
			key = is_outer and outer_wall_key or "plaster"
			height = is_outer and outer_wall_h or inner_wall_h
			blocked = true
			opaque = true
		elseif c.kind == "window" then
			key = "window"
			height = c.outer and outer_wall_h or inner_wall_h
			blocked = true
			opaque = false
		elseif c.kind == "door" then
			local dkey = c.y .. "," .. c.x
			local is_open = door_overrides[dkey]
			if is_open == nil then
				is_open = (not c.outer)
			end
			local wh = c.outer and outer_wall_h or inner_wall_h
			key = is_open and "door_open" or "door_closed"
			height = is_open and 0 or wh
			blocked = not is_open
			opaque = not is_open
			doors[#doors + 1] = {
				x = c.x,
				y = c.y,
				open = is_open,
				outer = c.outer == true,
				wall_height = wh,
				sprite = "assets/sprites/door_leaf.png",
			}
		end

		cells[#cells + 1] = {
			x = c.x,
			y = c.y,
			kind = c.kind,
			tile = key,
			height = height,
			blocked = blocked,
			opaque = opaque,
			indoor = indoor,
		}

		if mode == "exterior" and indoor then
			roof[#roof + 1] = {
				x = c.x,
				y = c.y,
				tile = "roof_snow",
				height = outer_wall_h,
			}
		end
	end

	for _, p in ipairs(v.props or {}) do
		local spec = PROP_SPECS[p.id]
		if spec then
			props[#props + 1] = {
				id = p.id,
				x = p.x,
				y = p.y,
				sprite = spec.sprite,
				w = spec.w,
				h = spec.h,
				frame = p.frame or spec.frame,
			}
		end
	end

	return {
		id = parsed.id,
		w = parsed.width,
		h = parsed.height,
		mode = mode,
		layout = parsed,
		cells = cells,
		doors = doors,
		props = props,
		lights = v.lights or {},
		roof = roof,
		player_spawn = v.player_spawn,
		npc_patrol = v.npc_patrol,
	}
end

local function door_key(x, y)
	return tostring(x) .. "," .. tostring(y)
end

local function apply_door_cell(state, door)
	local iso = _G.iso
	local tid_open = state.tile_ids.door_open or 0
	local tid_closed = state.tile_ids.door_closed or 0
	local h = door.open and 1 or ((state.plan.mode == "exterior") and (door.wall_height or 2) or 2)
	local tid = door.open and tid_open or tid_closed
	iso.map_set(door.x, door.y, tid, h)
	iso.tile_set_blocked(door.x, door.y, not door.open)
	iso.tile_set_opaque(door.x, door.y, not door.open)
	if door.entity_id then
		iso.entity_set_visible(door.entity_id, not door.open)
	end
end

function M.apply(plan, opts)
	local iso = _G.iso
	opts = opts or {}
	if not opts.keep_world then
		iso.world_clear()
	end
	iso.map_create(plan.w, plan.h)
	local tileset = opts.tileset or "assets/textures/tiles.png"
	iso.tileset_load(tileset, 8, 8)

	local tile_defs = require("data.tiles")
	local names = {}
	for k in pairs(tile_defs) do
		names[#names + 1] = k
	end
	table.sort(names)

	local tile_ids = {}
	for _, name in ipairs(names) do
		local def = tile_defs[name]
		local id = iso.tile_define_ex(
			def.top,
			def.side,
			def.side_cap or -1,
			def.solid == true,
			def.liquid == true,
			def.opaque == true,
			def.tag or 0
		)
		tile_ids[name] = id
	end

	local cells_by_key = {}
	for _, cell in ipairs(plan.cells) do
		local tid = tile_ids[cell.tile] or 0
		iso.map_set(cell.x, cell.y, tid, cell.height)
		iso.tile_set_blocked(cell.x, cell.y, cell.blocked == true)
		iso.tile_set_opaque(cell.x, cell.y, cell.opaque == true)
		cells_by_key[door_key(cell.x, cell.y)] = cell
	end

	local sheet_cache = {}
	local function get_sheet(path, fw, fh)
		local key = path .. ":" .. tostring(fw) .. "x" .. tostring(fh)
		if not sheet_cache[key] then
			sheet_cache[key] = iso.sheet_load(path, fw, fh)
		end
		return sheet_cache[key]
	end

	local state = {
		plan = plan,
		tile_ids = tile_ids,
		cells_by_key = cells_by_key,
		doors_by_key = {},
		prop_ids = {},
		light_ids = {},
		roof_visible = false,
	}

	for _, door in ipairs(plan.doors) do
		local d = {
			x = door.x,
			y = door.y,
			open = door.open == true,
			outer = door.outer == true,
			wall_height = door.wall_height,
			sprite = door.sprite,
		}
		if d.sprite then
			local sid = get_sheet(d.sprite, 32, 64)
			local eid = iso.entity_spawn(sid, d.x + 0.5, d.y + 0.5, 0.5, 1.0)
			iso.entity_set_size_px(eid, 32, 64)
			iso.entity_set_lit(eid, true)
			iso.entity_set_pickable(eid, true)
			d.entity_id = eid
		end
		apply_door_cell(state, d)
		state.doors_by_key[door_key(d.x, d.y)] = d
	end

	for _, prop in ipairs(plan.props) do
		local fw = prop.w or 64
		local fh = prop.h or 64
		local sid = get_sheet(prop.sprite, fw, fh)
		local eid = iso.entity_spawn(sid, prop.x + 0.5, prop.y + 0.5, 1.0, 1.0)
		iso.entity_set_frame(eid, prop.frame or 0)
		iso.entity_set_size_px(eid, fw, fh)
		iso.entity_set_lit(eid, true)
		iso.entity_set_pickable(eid, true)
		state.prop_ids[#state.prop_ids + 1] = eid
	end

	for _, lt in ipairs(plan.lights) do
		local col = lt.color or { 1.0, 0.8, 0.5 }
		local lid = iso.light_add(lt.x + 0.5, lt.y + 0.5, lt.radius or 5.0, col[1], col[2], col[3])
		state.light_ids[#state.light_ids + 1] = lid
	end

	return state
end

function M.toggle_door(state, x, y)
	local d = state.doors_by_key[door_key(x, y)]
	if not d then
		return nil
	end
	d.open = not d.open
	apply_door_cell(state, d)
	return d.open
end

function M.set_roof_visible(state, visible)
	local iso = _G.iso
	local show = visible == true
	state.roof_visible = show
	local tid_roof = state.tile_ids.roof_snow or 0
	for _, r in ipairs(state.plan.roof or {}) do
		if show then
			iso.map_set(r.x, r.y, tid_roof, r.height)
		else
			local cell = state.cells_by_key[door_key(r.x, r.y)]
			if cell then
				local tid = state.tile_ids[cell.tile] or 0
				iso.map_set(r.x, r.y, tid, cell.height)
			end
		end
	end
end

return M
