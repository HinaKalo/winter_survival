package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local mapbuild = require("view.mapbuild")
local tiles = require("data.tiles")
local suburb_house = require("data.locations.suburb_house")
local street_block = require("data.locations.street_block")

local T = {}

local BLOCKED, OPAQUE = 1, 2

local function at(plan, x, y)
	for _, c in ipairs(plan.cells) do
		if c.x == x and c.y == y then return c end
	end
	error("no cell " .. x .. "," .. y)
end

local function def_of(plan, c)
	return c.tile and plan.tiledefs[c.tile]
end

-- Synthetic template with outer window + outer door + inner door + prop, to exercise every rule.
local function mini()
	return {
		id = "mini", floor = "wood", wall = "siding",
		variants = { A = {
			grid = {
				"#####w###",
				"#K..=..B#",
				"#...+...#",
				"####D####",
			},
			legend = { K = { prop = "bookshelf" }, B = { prop = "bed" } },
		} },
	}
end

-- deterministic serializer (sorted keys, cycle-safe)
local function ser(v, seen, out)
	local t = type(v)
	if t ~= "table" then
		out[#out + 1] = t .. ":" .. tostring(v)
		return
	end
	if seen[v] then out[#out + 1] = "<ref>"; return end
	seen[v] = true
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b)
		local ta, tb = type(a), type(b)
		if ta ~= tb then return ta < tb end
		return a < b
	end)
	out[#out + 1] = "{"
	for _, k in ipairs(keys) do
		out[#out + 1] = tostring(k) .. "="
		ser(v[k], seen, out)
		out[#out + 1] = ","
	end
	out[#out + 1] = "}"
end

local function serialize(plan)
	local out = {}
	ser(plan, {}, out)
	return table.concat(out)
end

function T.suburb_house_exterior_vs_cutaway()
	local ext = mapbuild.plan(suburb_house, { mode = "exterior" })
	local cut = mapbuild.plan(suburb_house, { mode = "cutaway" })
	assert(ext.w == 14 and ext.h == 8)
	assert(#ext.cells == 112 and #cut.cells == 112)
	-- corner: outer wall
	local e, c = at(ext, 0, 0), at(cut, 0, 0)
	assert(e.height == 6 and e.flags == (BLOCKED | OPAQUE) and e.tag == 5)
	assert(c.height == 2 and c.flags == (BLOCKED | OPAQUE))
	assert(#ext.roof > 0 and #cut.roof == 0)
	for _, cell in ipairs(ext.cells) do
		assert(cell.tile == nil or tiles[cell.tile] ~= nil)
		assert(cell.tile == nil or ext.tiledefs[cell.tile] ~= nil)
	end
	for _, cell in ipairs(cut.cells) do
		assert(cell.tile == nil or cut.tiledefs[cell.tile] ~= nil)
	end
end

function T.exterior_hides_interior_and_roofs_enclosed_cells()
	local ext = mapbuild.plan(suburb_house, { mode = "exterior" })
	-- interior wall (6,1), inner door (4,3), prop K (1,1), window (10,6) inside: height-0 floor, no flags
	for _, p in ipairs({ { 6, 1 }, { 4, 3 }, { 1, 1 }, { 10, 6 }, { 7, 1 }, { 4, 2 } }) do
		local c = at(ext, p[1], p[2])
		assert(c.height == 0 and c.flags == 0, "interior not hidden at " .. p[1] .. "," .. p[2])
		assert(c.tile == "wood", "hidden interior should be floor, got " .. tostring(c.tile))
	end
	assert(#ext.doors == 0 and #ext.props == 0, "no door entities / props in exterior")
	-- roof = every cell not outer wall/door/window and not void: 14*8 - perimeter (outer cells)
	local outer = 0
	for _, c in ipairs(ext.cells) do
		if c.height == 6 then outer = outer + 1 end
	end
	assert(outer + #ext.roof == 14 * 8, "roof must cover exactly the enclosed cells")
	local seen = {}
	for _, r in ipairs(ext.roof) do
		assert(r.height == 6 and r.flags == (BLOCKED | OPAQUE))
		assert(r.tile == "roof_snow" or r.tile == "roof_tile")
		assert(ext.tiledefs[r.tile] and (ext.tiledefs[r.tile].top == 56 or ext.tiledefs[r.tile].top == 57))
		seen[r.x .. "," .. r.y] = true
		assert(at(ext, r.x, r.y).height == 0)
	end
	assert(seen["1,1"] and seen["6,1"] and seen["4,3"])
	assert(not seen["0,0"] and not seen["4,7"])
end

function T.exterior_window_and_door_columns()
	local p = mapbuild.plan(mini(), { mode = "exterior" })
	local win = at(p, 5, 0)
	local wd = def_of(p, win)
	assert(win.height == 6 and win.flags == (BLOCKED | OPAQUE) and win.tag == 7)
	assert(wd.side_base == 26 and wd.side == 43 and wd.side_cap == 61)
	local door = at(p, 4, 3)
	local dd = def_of(p, door)
	assert(door.height == 6 and door.flags == (BLOCKED | OPAQUE) and door.tag == 6)
	assert(dd.side_base == 40 and dd.side == 26 and dd.side_cap == 61)
	assert(#p.doors == 0)
	local wall = at(p, 0, 0)
	local wdef = def_of(p, wall)
	assert(wdef.side_base == 26 and wdef.side == 26 and wdef.side_cap == 60)
	-- inner door (4,2) and inner wall (4,1), props hidden
	for _, q in ipairs({ { 4, 2 }, { 4, 1 }, { 1, 1 }, { 7, 1 } }) do
		local c = at(p, q[1], q[2])
		assert(c.height == 0 and c.flags == 0)
	end
end

function T.cutaway_walls_windows_doors_props()
	local p = mapbuild.plan(mini(), { mode = "cutaway" })
	local wall, inner = at(p, 0, 0), at(p, 4, 1)
	assert(wall.height == 2 and wall.flags == 3 and wall.tile == "siding")
	assert(inner.height == 2 and inner.flags == 3 and inner.tile == "plaster")
	local win = at(p, 5, 0)
	assert(win.height == 2 and win.flags == BLOCKED and win.tag == 7)
	local wd = def_of(p, win)
	assert(wd.side == 43 and wd.side_cap == -1)
	-- outer door closed by default: 0 height, blocked+opaque, with entity data
	local door = at(p, 4, 3)
	assert(door.height == 0 and door.flags == 3 and door.tag == 6)
	-- inner door open by default: no flags
	local idoor = at(p, 4, 2)
	assert(idoor.height == 0 and idoor.flags == 0 and idoor.tile == "door_open")
	assert(#p.doors == 2)
	for _, d in ipairs(p.doors) do assert(d.sprite ~= nil) end
	-- props: blocked; bookshelf opaque, bed not
	local shelf, bed = at(p, 1, 1), at(p, 7, 1)
	assert(shelf.flags == (BLOCKED | OPAQUE) and shelf.tag == 8 and shelf.height == 0)
	assert(bed.flags == BLOCKED and bed.height == 0)
	assert(#p.props == 2)
	assert(#p.roof == 0)
end

function T.suburb_house_cutaway_props_and_marker()
	local p = mapbuild.plan(suburb_house, { mode = "cutaway" })
	local counter, bed, fire, mark = at(p, 1, 1), at(p, 7, 1), at(p, 3, 6), at(p, 1, 4)
	assert(counter.flags == BLOCKED and bed.flags == BLOCKED and fire.flags == (BLOCKED | OPAQUE))
	assert(mark.flags == 0 and mark.tile == "wood", "L is a room label, not a blocker")
	local win = at(p, 10, 6)
	assert(win.height == 2 and win.flags == BLOCKED)
	local front = at(p, 4, 7)
	assert(front.height == 0 and front.flags == 3)
end

function T.door_override_uses_x_y_keys()
	local key = mapbuild.pos_key(4, 3) -- x=4, y=3 (outer front door of mini)
	assert(key == "4,3")
	local p = mapbuild.plan(mini(), { mode = "cutaway", doors = { [key] = true } })
	local door = at(p, 4, 3)
	assert(door.flags == 0 and door.tile == "door_open")
	local closed = mapbuild.plan(mini(), { mode = "cutaway", doors = { [mapbuild.pos_key(4, 2)] = false } })
	assert(at(closed, 4, 2).flags == 3)
	-- swapped key (y,x) must not match
	local p2 = mapbuild.plan(mini(), { mode = "cutaway", doors = { ["3,4"] = true } })
	assert(at(p2, 4, 3).flags == 3)
end

function T.void_cells()
	local tpl = {
		id = "void_t", floor = "wood", wall = "brick",
		variants = { A = { grid = { "### ", "#.# ", "### " } } },
	}
	for _, mode in ipairs({ "exterior", "cutaway" }) do
		local p = mapbuild.plan(tpl, { mode = mode })
		for y = 0, 2 do
			local c = at(p, 3, y)
			assert(c.kind == "void" and c.tile == nil and c.height == 0 and c.flags == 0 and c.tag == 0)
		end
	end
end

function T.layout_parse_failure_raises_clear_error()
	local bad = { id = "bad_tpl", variants = { A = { grid = { "##", "#" } } } }
	local ok, err = pcall(mapbuild.plan, bad, { mode = "exterior" })
	assert(not ok)
	assert(tostring(err):find("bad_tpl", 1, true) and tostring(err):find("variant", 1, true), tostring(err))
	local ok2, err2 = pcall(mapbuild.plan, bad, { variant = "Z" })
	assert(not ok2 and tostring(err2):find("Z", 1, true))
end

function T.plan_is_deterministic()
	for _, tpl in ipairs({ suburb_house, street_block }) do
		for _, mode in ipairs({ "exterior", "cutaway" }) do
			local a = serialize(mapbuild.plan(tpl, { mode = mode }))
			local b = serialize(mapbuild.plan(tpl, { mode = mode }))
			assert(a == b, "plan differs between runs: " .. tpl.id .. " " .. mode)
		end
	end
end

function T.plan_is_pure_no_engine_require()
	local f = assert(io.open("assets/scripts/view/mapbuild.lua", "r"))
	local src = f:read("a")
	f:close()
	local n = 0
	for mod in src:gmatch('require%("([^"]+)"%)') do
		n = n + 1
		-- view.lightfov is required lazily inside apply() only (light fallback); plan() purity is checked below.
		assert(mod == "core.layout" or mod == "view.lightfov" or mod:match("^data%."),
			"mapbuild requires non-pure module: " .. mod)
	end
	assert(n >= 1)
	-- plan must not touch the engine global
	local saved = _G.iso
	_G.iso = nil
	local ok, err = pcall(mapbuild.plan, suburb_house, { mode = "cutaway" })
	_G.iso = saved
	assert(ok, tostring(err))
end

function T.street_block_64x64_both_modes()
	local ext = mapbuild.plan(street_block, { mode = "exterior" })
	local cut = mapbuild.plan(street_block, { mode = "cutaway" })
	assert(ext.w == 64 and ext.h == 64 and #ext.cells == 4096 and #cut.cells == 4096)
	-- four houses: each house's roof covers its enclosed cells; exterior has none of the 4 front-door entities
	assert(#ext.roof > 0 and #cut.roof == 0)
	local per_house = 0
	for _, row in ipairs(suburb_house.variants.A.grid) do
		for ch in row:gmatch("[%+D]") do per_house = per_house + 1 end
	end
	assert(#ext.doors == 0 and #cut.doors == 4 * per_house)
	local tall = 0
	for _, c in ipairs(ext.cells) do
		if c.height == 6 then tall = tall + 1 end
		assert(c.height == 0 or c.height == 6)
	end
	assert(tall > 0)
	for _, c in ipairs(cut.cells) do assert(c.height <= 2) end
end

function T.apply_reuses_tile_ids_across_applies()
	local saved = _G.iso
	local defines, next_id = 0, 0
	local function noop() end
	local fake = setmetatable({
		tile_define_ex2 = function() defines = defines + 1; next_id = next_id + 1; return next_id end,
		sheet_load = function() return 1 end,
		entity_spawn = function() return 1 end,
	}, { __index = function() return noop end })
	_G.iso = fake
	local ok, err = pcall(function()
		local plan = mapbuild.plan(suburb_house, { mode = "cutaway" })
		local s1 = mapbuild.apply(plan)
		local first = defines
		assert(first > 0)
		local s2 = mapbuild.apply(plan)
		assert(defines == first, "second apply re-defined tiles: " .. first .. " -> " .. defines)
		for name, id in pairs(s1.tile_ids) do assert(s2.tile_ids[name] == id, name) end
		-- a plan in the other mode only defines tiles it newly needs
		local ext = mapbuild.plan(suburb_house, { mode = "exterior" })
		mapbuild.apply(ext)
		local after_ext = defines
		mapbuild.apply(ext)
		assert(defines == after_ext)
	end)
	_G.iso = saved
	assert(ok, tostring(err))
end

return T
