-- Map planner/applier built on core/layout.lua (M2-PLAN §5.1).
-- plan() is pure and deterministic: no engine access, no pairs() iteration of anything it emits.
-- apply() and the runtime helpers below are the only functions that touch the `iso` global.
local layout = require("core.layout")
local tiles = require("data.tiles")
local props_table = require("data.props")
local light_defs = require("data.lights")

local M = {}

-- Matches Zig tilemap Flag.
local FLAG_BLOCKED = 1
local FLAG_OPAQUE = 2

local EXT_WALL_H = 6
local CUT_WALL_H = 2

--- Single helper for "x,y" keys (door overrides, lookups): x first, then y.
local function pos_key(x, y)
	return tostring(x) .. "," .. tostring(y)
end
M.pos_key = pos_key

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

--- Pure planner: parses template via core/layout and enriches with heights, flags, roofs and tile defs.
-- Output per cell: { x, y, kind, tile, height, flags, tag, blocked, opaque, indoor } (flags: blocked=1, opaque=2).
-- plan.tiledefs maps every tile name used (cells + roof) to its def table from data/tiles.lua.
function M.plan(template, opts)
	opts = opts or {}
	local variant = opts.variant or "A"
	local mode = opts.mode or "exterior"
	assert(mode == "exterior" or mode == "cutaway", "mapbuild.plan: bad mode " .. tostring(mode))
	local exterior = (mode == "exterior")

	-- opts.level ("B1" / "F2"): plan that level of a multi-storey template instead of the main floor
	local level_def
	if opts.level and opts.level ~= "F1" then
		local vdef = template.variants and template.variants[variant]
		level_def = vdef and vdef.levels and vdef.levels[opts.level]
		if not level_def then
			error(string.format("mapbuild.plan: template has no level %q", tostring(opts.level)), 2)
		end
		template = level_def
	end
	local parsed, err = layout.parse(template, variant, { strict = opts.strict })
	if not parsed then
		error(string.format("mapbuild.plan: layout.parse failed for template %q variant %q: %s",
			tostring(type(template) == "table" and template.id or template), tostring(variant), tostring(err)), 2)
	end
	local v = template.variants and template.variants[variant] or template

	local wall_key = parsed.wall or "brick"
	local floor_key = parsed.floor or "wood"
	assert(tiles["ext_wall_" .. wall_key], "mapbuild.plan: unknown wall material " .. tostring(wall_key))
	assert(tiles["prop_" .. floor_key], "mapbuild.plan: unknown floor material " .. tostring(floor_key))
	local door_overrides = opts.doors or {}
	local door_kinds = v.door_kinds or {}

	-- deterministic cell order: y then x
	local list = {}
	for i, c in ipairs(parsed.cells) do list[i] = c end
	table.sort(list, function(a, b)
		if a.y ~= b.y then return a.y < b.y end
		return a.x < b.x
	end)

	local tiledefs = {}
	local cells, doors, props, roof = {}, {}, {}, {}
	-- Lights: location data carries { source, x, y } only (source = key of data/lights.lua, ART-AUDIO §3.3;
	-- not `name`, which test_layering reserves for i18n keys). The plan entry calls it `name`.
	local lights = {}
	for _, lt in ipairs(v.lights or {}) do
		assert(light_defs.sources[lt.source],
			string.format("mapbuild.plan: unknown light %q (not in data/lights.lua)", tostring(lt.source)))
		lights[#lights + 1] = { name = lt.source, x = lt.x, y = lt.y }
	end

	local function use(name)
		local d = tiles[name]
		if not d then error("mapbuild.plan: tile not defined in data/tiles.lua: " .. tostring(name), 3) end
		tiledefs[name] = d
		return d
	end

	local function emit(c, name, height, flags, indoor)
		local tag = 0
		if name then tag = use(name).tag or 0 end
		cells[#cells + 1] = {
			x = c.x, y = c.y, kind = c.kind,
			tile = name, height = height, flags = flags, tag = tag,
			blocked = (flags & FLAG_BLOCKED) ~= 0,
			opaque = (flags & FLAG_OPAQUE) ~= 0,
			indoor = indoor == true,
		}
	end

	local function add_roof(c)
		local name = (hash2d(c.x, c.y) % 4 == 0) and "roof_tile" or "roof_snow"
		roof[#roof + 1] = {
			x = c.x, y = c.y, tile = name, height = EXT_WALL_H,
			flags = FLAG_BLOCKED | FLAG_OPAQUE, tag = use(name).tag or 0,
		}
	end

	for _, c in ipairs(list) do
		local kind = c.kind
		local indoor_hidden = false -- interior cell hidden under the roof in exterior mode
		if kind == "void" then
			emit(c, nil, 0, 0, false)
		elseif kind == "outdoor" then
			emit(c, outdoor_tile(c.x, c.y, v.road_rects), 0, 0, false)
		elseif kind == "floor" then
			emit(c, c.material or floor_key, 0, 0, true)
			indoor_hidden = true
		elseif kind == "prop" then
			local spec = props_table[c.prop]
			if not spec then
				error(string.format("mapbuild.plan: unknown prop %q at (%d,%d)", tostring(c.prop), c.x, c.y))
			end
			if spec.marker or exterior then
				-- room-label letter, or prop hidden under the roof: plain floor
				emit(c, floor_key, 0, 0, true)
			else
				local opq = spec.opaque
				if c.opaque ~= nil then opq = c.opaque end
				emit(c, "prop_" .. floor_key, 0, FLAG_BLOCKED | (opq and FLAG_OPAQUE or 0), true)
				props[#props + 1] = {
					id = c.prop, x = c.x, y = c.y, slot = c.slot,
					sprite = spec.sprite, w = spec.w, h = spec.h, frame = spec.frame,
					blocked = true, opaque = opq == true,
				}
			end
			indoor_hidden = true
		elseif kind == "wall" then
			if c.outer then
				if exterior then
					emit(c, "ext_wall_" .. wall_key, EXT_WALL_H, FLAG_BLOCKED | FLAG_OPAQUE, false)
				else
					emit(c, wall_key, CUT_WALL_H, FLAG_BLOCKED | FLAG_OPAQUE, false)
				end
			elseif exterior then
				emit(c, floor_key, 0, 0, true)
				indoor_hidden = true
			else
				emit(c, "plaster", CUT_WALL_H, FLAG_BLOCKED | FLAG_OPAQUE, true)
			end
		elseif kind == "window" then
			if not exterior then
				-- ART-AUDIO §3.1 / PLAN §5.4: one weak daylight light on every window cell (cutaway only).
				lights[#lights + 1] = { name = "window", x = c.x, y = c.y }
			end
			if c.outer then
				if exterior then
					emit(c, "ext_window_" .. wall_key, EXT_WALL_H, FLAG_BLOCKED | FLAG_OPAQUE, false)
				else
					emit(c, "window_" .. wall_key, CUT_WALL_H, FLAG_BLOCKED, false)
				end
			elseif exterior then
				emit(c, floor_key, 0, 0, true)
				indoor_hidden = true
			else
				emit(c, "window_plaster", CUT_WALL_H, FLAG_BLOCKED, true)
			end
		elseif kind == "door" then
			local dk = door_kinds[pos_key(c.x, c.y)] or "wood"
			assert(dk == "wood" or dk == "metal", "mapbuild.plan: bad door kind " .. tostring(dk))
			if exterior then
				if c.outer then
					emit(c, "ext_door_" .. dk .. "_" .. wall_key, EXT_WALL_H, FLAG_BLOCKED | FLAG_OPAQUE, false)
				else
					emit(c, floor_key, 0, 0, true)
					indoor_hidden = true
				end
			else
				local is_open = door_overrides[pos_key(c.x, c.y)]
				if is_open == nil then
					is_open = not c.outer
				end
				local closed_tile = "door_" .. dk
				use(closed_tile)
				use("door_open")
				emit(c, is_open and "door_open" or closed_tile, 0,
					is_open and 0 or (FLAG_BLOCKED | FLAG_OPAQUE), not c.outer)
				doors[#doors + 1] = {
					x = c.x, y = c.y, open = is_open == true, outer = c.outer == true,
					kind = dk, tile = closed_tile, wall_height = CUT_WALL_H,
					sprite = "assets/sprites/door_leaf.png",
				}
			end
		else
			error("mapbuild.plan: unhandled cell kind " .. tostring(kind))
		end

		if exterior and indoor_hidden then
			add_roof(c)
		end
	end

	for _, p in ipairs(v.props or {}) do
		local spec = props_table[p.id]
		if spec and spec.sprite then
			props[#props + 1] = {
				id = p.id, x = p.x, y = p.y,
				sprite = spec.sprite, w = spec.w, h = spec.h,
				frame = p.frame or spec.frame,
				blocked = false, opaque = spec.opaque == true,
			}
		end
	end

	return {
		id = parsed.id,
		w = parsed.width,
		h = parsed.height,
		mode = mode,
		variant = variant,
		layout = parsed,
		cells = cells,
		doors = doors,
		props = props,
		lights = lights,
		roof = roof,
		tiledefs = tiledefs,
		player_spawn = v.player_spawn,
		npc_patrol = v.npc_patrol,
	}
end

-- Engine TileMap.defs is append-only, so re-applying the same defs must reuse ids.
-- Cache: iso table -> tileset path -> def signature -> tile id (weak on the iso table).
local tile_id_cache = setmetatable({}, { __mode = "k" })

local function def_signature(d)
	return table.concat({
		d.top, d.side, d.side_cap or -1, d.side_base or -1,
		d.solid == true and 1 or 0, d.liquid == true and 1 or 0, d.opaque == true and 1 or 0, d.tag or 0,
	}, "|")
end

--- Define one tile in the engine via the positional binding that carries side_base
-- (side_cap/side_base < 0 = unset, same as side). Reuses the id for an identical def on the same tileset.
local function define_tile(iso, tileset, d)
	local per_iso = tile_id_cache[iso]
	if not per_iso then
		per_iso = {}
		tile_id_cache[iso] = per_iso
	end
	local per_set = per_iso[tileset]
	if not per_set then
		per_set = {}
		per_iso[tileset] = per_set
	end
	local sig = def_signature(d)
	local id = per_set[sig]
	if id == nil then
		id = iso.tile_define_ex2(d.top, d.side, d.side_cap or -1, d.side_base or -1,
			d.solid == true, d.liquid == true, d.opaque == true, d.tag or 0)
		if id ~= 0 then per_set[sig] = id end -- 0 = define failed; don't cache it
	end
	return id
end

--- Drop cached tile ids (call if the engine tile defs were reset).
function M.reset_tile_cache()
	tile_id_cache = setmetatable({}, { __mode = "k" })
end

local function set_cell(iso, x, y, tid, height, flags)
	iso.map_set(x, y, tid, height)
	iso.tile_set_blocked(x, y, (flags & FLAG_BLOCKED) ~= 0)
	iso.tile_set_opaque(x, y, (flags & FLAG_OPAQUE) ~= 0)
end

local function apply_door_cell(state, door)
	local iso = _G.iso
	local tid
	if door.open then
		tid = state.tile_ids.door_open or 0
	else
		tid = state.tile_ids[door.tile or "door_wood"] or 0
	end
	-- 0-height cell; closed = blocked + opaque, open clears both
	set_cell(iso, door.x, door.y, tid, 0, door.open and 0 or (FLAG_BLOCKED | FLAG_OPAQUE))
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

	local names = {}
	for k in pairs(plan.tiledefs) do
		names[#names + 1] = k
	end
	table.sort(names)

	local tile_ids = {}
	for _, name in ipairs(names) do
		tile_ids[name] = define_tile(iso, tileset, plan.tiledefs[name])
	end

	local cells_by_key = {}
	for _, cell in ipairs(plan.cells) do
		local tid = cell.tile and tile_ids[cell.tile] or 0
		set_cell(iso, cell.x, cell.y, tid, cell.height, cell.flags)
		cells_by_key[pos_key(cell.x, cell.y)] = cell
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
			x = door.x, y = door.y,
			open = door.open == true, outer = door.outer == true,
			kind = door.kind, tile = door.tile,
			wall_height = door.wall_height, sprite = door.sprite,
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
		state.doors_by_key[pos_key(d.x, d.y)] = d
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

	-- Every map light goes through opts.add_light(name, x, z) (the demo passes lightfov.add_light, which owns the
	-- table lookup, ambient tinting and flicker). Without a hook (probes) lightfov.add_light is used directly.
	for _, lt in ipairs(plan.lights) do
		local lid
		if opts.add_light then
			lid = opts.add_light(lt.name, lt.x + 0.5, lt.y + 0.5)
		else
			-- No hook: still go through lightfov so ambient-tinted entries (window) and flicker match data/lights.lua.
			lid = require("view.lightfov").add_light(lt.name, lt.x + 0.5, lt.y + 0.5)
		end
		if lid and lid ~= 0 then state.light_ids[#state.light_ids + 1] = lid end
	end

	-- exterior: roof is on by default
	if plan.mode == "exterior" and #plan.roof > 0 then
		M.set_roof_visible(state, true)
	end

	return state
end

function M.toggle_door(state, x, y)
	local d = state.doors_by_key[pos_key(x, y)]
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
	for _, r in ipairs(state.plan.roof or {}) do
		if show then
			set_cell(iso, r.x, r.y, state.tile_ids[r.tile] or 0, r.height, r.flags)
		else
			local cell = state.cells_by_key[pos_key(r.x, r.y)]
			if cell then
				set_cell(iso, r.x, r.y, cell.tile and state.tile_ids[cell.tile] or 0, cell.height, cell.flags)
			end
		end
	end
end

return M
