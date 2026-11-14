-- L2 / R5c: facing + sprite frame table (ART-AUDIO §5.4-§5.6, M2-PLAN G5).
--
-- Frame of reference (camera.zig, yaw 45 deg): the eye sits at (sin yaw, _, cos yaw) from the
-- target, so forward = (-a, 0, -a) and right = forward x up = (a, 0, -a) with a = sqrt(1/2).
-- A world move (dx, dz) therefore has screen-right = a*(dx - dz) and screen-down = a*(dx + dz)
-- (pitch only scales the screen-down term by sin(30 deg); quadrant signs are unaffected).
-- Hence world +X -> SE, +Z -> SW, -X -> NW, -Z -> NE, which is what facing.pick returns.
-- tests/probe/m2_map.lua (G5) checks the same mapping against iso.world_to_screen with the live camera;
-- the luatest runs before the engine refreshes the camera view, so it cannot do that check.
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local facing = require("view.facing")

local SE, SW, NE, NW = facing.SE, facing.SW, facing.NE, facing.NW
local A = math.sqrt(0.5)

local T = {}

-- Model-space screen angle (degrees, 0 = right, 90 = down) -> world move with that direction.
-- Inverse of: r = A*(dx - dz), t = A*(dx + dz).
local function world_at(deg)
	local r, t = math.cos(math.rad(deg)), math.sin(math.rad(deg))
	return (r + t) / (2 * A), (t - r) / (2 * A)
end

-- Facing that pick() returns from scratch for a screen angle (deg in [0, 360)).
local function quadrant(deg)
	if deg < 90 then return SE end
	if deg < 180 then return SW end
	if deg < 270 then return NW end
	return NE
end

-- Canonical screen angle of each facing (matches facing.DIRS sx/sy).
local CANON_DEG = { [SE] = 45, [SW] = 135, [NW] = 225, [NE] = 315 }

local function circ_dist(a, b)
	local d = (a - b) % 360
	if d > 180 then d = 360 - d end
	return d
end

-- ---------------------------------------------------------------- 8 movement directions

function T.eight_directions_from_scratch()
	-- The four axis moves land on a screen diagonal: exact facing.
	assert(facing.pick(nil, 1, 0) == SE, "+X -> SE")
	assert(facing.pick(nil, 0, 1) == SW, "+Z -> SW")
	assert(facing.pick(nil, -1, 0) == NW, "-X -> NW (west)")
	assert(facing.pick(nil, 0, -1) == NE, "-Z -> NE")

	-- The four diagonal moves land exactly on a screen axis, i.e. on the boundary between two
	-- facings. From scratch either neighbour is acceptable; once a facing is set, hysteresis
	-- must keep it (the boundary is inside the 22.5 deg margin).
	local diag = {
		{ 1, 1, SE, SW },   -- screen down
		{ 1, -1, SE, NE },  -- screen right
		{ -1, 1, SW, NW },  -- screen left
		{ -1, -1, NE, NW }, -- screen up
	}
	for _, d in ipairs(diag) do
		local dx, dz, a, b = d[1], d[2], d[3], d[4]
		local f = facing.pick(nil, dx, dz)
		assert(f == a or f == b, string.format("diagonal (%d,%d) gave %d, want %d or %d", dx, dz, f, a, b))
		assert(facing.pick(a, dx, dz) == a, string.format("diagonal (%d,%d) must keep prev %d", dx, dz, a))
		assert(facing.pick(b, dx, dz) == b, string.format("diagonal (%d,%d) must keep prev %d", dx, dz, b))
	end
end

function T.zero_and_bad_input_keep_prev()
	assert(facing.pick(nil, 0, 0) == SE, "zero move without prev -> SE")
	assert(facing.pick(NW, 0, 0) == NW, "zero move keeps prev")
	assert(facing.pick(SW, "x", 1) == SW, "non-number dx keeps prev")
	assert(facing.pick(nil, nil, nil) == SE, "nil input without prev -> SE")
	-- non-finite input must not raise; the result is some valid facing index
	local ok, f = pcall(facing.pick, NE, 1 / 0, 0)
	assert(ok and type(f) == "number" and f >= 0 and f <= 3, "inf input returns a facing index")
end

-- ---------------------------------------------------------------- west mirroring

function T.west_mirroring()
	assert(facing.info(SE).flip_x == false, "SE not mirrored")
	assert(facing.info(SW).flip_x == true, "SW mirrors SE")
	assert(facing.info(NE).flip_x == false, "NE not mirrored")
	assert(facing.info(NW).flip_x == true, "NW mirrors NE")
	assert(facing.info(SW).row_base == facing.info(SE).row_base, "SW uses SE rows")
	assert(facing.info(NW).row_base == facing.info(NE).row_base, "NW uses NE rows")

	local actions = { "walk", "idle", "sneak", "hurt", "work", "attack", "aim", "down" }
	for _, a in ipairs(actions) do
		local se, sw = facing.anim_spec(SE, a), facing.anim_spec(SW, a)
		local ne, nw = facing.anim_spec(NE, a), facing.anim_spec(NW, a)
		assert(sw.start == se.start and sw.len == se.len, a .. ": SW frames == SE frames")
		assert(nw.start == ne.start and nw.len == ne.len, a .. ": NW frames == NE frames")
		assert(sw.flip_x and not se.flip_x and nw.flip_x and not ne.flip_x, a .. ": flip only on west")
	end
end

-- ---------------------------------------------------------------- hysteresis

function T.hysteresis_margins()
	-- Started at SE, the boundary to SW is at 112.5 deg, to NE at -22.5 deg (22.5 deg margin).
	local function at(deg, prev)
		local dx, dz = world_at(deg)
		return facing.pick(prev, dx, dz)
	end
	assert(at(-20, SE) == SE, "-20 deg stays SE (inside margin)")
	assert(at(0, SE) == SE, "0 deg stays SE")
	assert(at(100, SE) == SE, "100 deg stays SE (inside margin)")
	assert(at(-25, SE) == NE, "-25 deg leaves SE for NE")
	assert(at(115, SE) == SW, "115 deg leaves SE for SW")
	-- Same margins for every facing (+-60 keeps, +-70 leaves)
	for _, f in ipairs({ SE, SW, NW, NE }) do
		local c = CANON_DEG[f]
		assert(at(c + 60, f) == f, "keeps " .. f .. " at +60")
		assert(at(c - 60, f) == f, "keeps " .. f .. " at -60")
		assert(at(c + 70, f) == quadrant((c + 70) % 360), "leaves " .. f .. " at +70")
		assert(at(c - 70, f) == quadrant((c - 70) % 360), "leaves " .. f .. " at -70")
	end
end

function T.hysteresis_oracle_sweep()
	-- Angles 1, 6, 11, ... never sit on a quadrant edge (multiples of 90) or on the 67.5 deg margin edge.
	for _, prev in ipairs({ nil, SE, SW, NW, NE }) do
		for k = 0, 71 do
			local deg = 1 + 5 * k
			local want = quadrant(deg)
			if prev ~= nil and circ_dist(deg, CANON_DEG[prev]) < 67.5 then
				want = prev
			end
			local dx, dz = world_at(deg)
			local got = facing.pick(prev, dx, dz)
			assert(got == want, string.format("prev=%s deg=%d: got %d want %d", tostring(prev), deg, got, want))
		end
	end
end

-- ---------------------------------------------------------------- frame table (ART-AUDIO §5.4)

-- Written out from the §5.4 table: first and last frame index per action, per row base.
local SHEET = {
	[0] = { walk = { 0, 5 }, idle = { 6, 7 }, sneak = { 8, 13 }, hurt = { 14, 15 },
		work = { 16, 19 }, attack = { 20, 23 }, aim = { 24, 25 }, down = { 26, 27 } }, -- SE / SW
	[4] = { walk = { 32, 37 }, idle = { 38, 39 }, sneak = { 40, 45 }, hurt = { 46, 47 },
		work = { 48, 51 }, attack = { 52, 55 }, aim = { 56, 57 }, down = { 58, 59 } }, -- NE / NW
}

-- Play suggestions (§5.4 last column): loop flag, and fps where the spec gives one.
local PLAY = {
	walk = { loop = true, fps = 10 },
	idle = { loop = true, fps = 1.5 },
	sneak = { loop = true, fps = 7 },
	hurt = { loop = false, dur = 0.15 },
	work = { loop = true, fps = 4 },
	attack = { loop = false, fps = 12 },
	aim = { loop = false },
	down = { loop = false },
}

local ACTIONS = { "walk", "idle", "sneak", "hurt", "work", "attack", "aim", "down" }

function T.frame_table_every_action_every_facing()
	local rows = { [SE] = 0, [SW] = 0, [NE] = 4, [NW] = 4 }
	local west = { [SE] = false, [SW] = true, [NE] = false, [NW] = true }
	for _, f in ipairs({ SE, SW, NE, NW }) do
		for _, a in ipairs(ACTIONS) do
			local want = SHEET[rows[f]][a]
			local spec = facing.anim_spec(f, a)
			local label = string.format("facing %d %s", f, a)
			local n = want[2] - want[1] + 1
			assert(spec.start == want[1], label .. ": start " .. spec.start .. " want " .. want[1])
			assert(spec.len == n, label .. ": len " .. spec.len .. " want " .. n)
			assert(spec.flip_x == west[f], label .. ": flip_x")
			assert(spec.loop == PLAY[a].loop, label .. ": loop")
			if PLAY[a].fps then
				assert(math.abs(spec.fps - PLAY[a].fps) < 1e-6, label .. ": fps " .. tostring(spec.fps))
			end
			-- every frame the player will show is an expected index
			for i = 0, 2 * n do
				local got = spec.start + (i % spec.len)
				local exp = want[1] + (i % n)
				assert(got == exp, label .. ": frame step " .. i)
			end
		end
	end
	-- hurt is one 0.15 s play-through
	local hurt = facing.anim_spec(SE, "hurt")
	assert(math.abs(hurt.len / hurt.fps - PLAY.hurt.dur) < 0.005, "hurt lasts 0.15 s")
end

function T.frame_indices_disjoint_and_complete()
	-- 56 frames used: rows 0-3 (SE) and 4-7 (NE) minus the empty cells (row 3/7, cols 4-7).
	local used, seen = {}, {}
	for _, base in ipairs({ 0, 4 }) do
		for _, a in ipairs(ACTIONS) do
			local r = SHEET[base][a]
			for i = r[1], r[2] do
				assert(not seen[i], "frame " .. i .. " used twice")
				seen[i] = true
				used[#used + 1] = i
			end
		end
	end
	assert(#used == 56, "56 frames in use, got " .. #used)
	for i = 0, 63 do
		local row, col = i // 8, i % 8
		local empty = (row == 3 or row == 7) and col >= 4
		assert(not (empty and seen[i]), "empty cell " .. i .. " is used")
	end
end

-- ---------------------------------------------------------------- guards

function T.invalid_facing_and_action_fall_back()
	assert(facing.info(99) == facing.info(SE), "unknown facing -> SE")
	local bogus = facing.anim_spec(SE, "no_such_action")
	local idle = facing.anim_spec(SE, "idle")
	assert(bogus.start == idle.start and bogus.len == idle.len, "unknown action -> idle")
end

return T
