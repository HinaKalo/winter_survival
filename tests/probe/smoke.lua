-- 默认探针场景（zig build probe）：脚本化"玩家" + 断言。
-- 在 headless 下游戏时间 ≈ 墙钟时间，所以只用带容差的时间等待，不做逐帧断言。
--
-- 探针 API（kit_probe）：key / tap / mouse_move / click / check / info / script_ok / finish / timeout
-- 场景写成协程：wait(秒) 会让出，直到游戏时间走够。

local iso = require("iso")
local probe = require("kit_probe")
local audio = require("audio")

probe.timeout(30)

local HERO = 1 -- 主角是第一个生成的实体
local now = 0

local function wait(sec)
	local untl = now + sec
	while now < untl do
		coroutine.yield()
	end
end

local function alive_count()
	local n = 0
	for id = 1, 64 do
		if iso.entity_exists(id) then
			n = n + 1
		end
	end
	return n
end

local function hero_tile()
	return iso.entity_get_tile(HERO)
end

local function dist(a, b)
	local dx, dy, dz = a[1] - b[1], a[2] - b[2], a[3] - b[3]
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- 找一个离主角 3..6 格、可走且可达（路径 <= 12 步）的格子
local function pick_reachable(from)
	for dy = -6, 6 do
		for dx = -6, 6 do
			local d = math.abs(dx) + math.abs(dy)
			if d >= 3 and d <= 6 then
				local gx, gy = from[1] + dx, from[2] + dy
				if iso.map_walkable(gx, gy) then
					local path = iso.path_find(from[1], from[2], gx, gy)
					if path and #path > 0 and #path <= 12 then
						return { gx, gy }
					end
				end
			end
		end
	end
	return nil
end

local function tile_screen(t)
	local x, z = t[1] + 0.5, t[2] + 0.5
	local y = iso.map_top_y(t[1], t[2])
	return iso.world_to_screen(x, y, z)
end

local function scenario()
	-- 0. 预热 1 秒后的基本健全性检查
	wait(1.0)
	probe.check("lua script running (no Lua error)", probe.script_ok())
	probe.check("hero + slimes spawned (>= 4 entities)", alive_count() >= 4)
	local size = iso.map_size()
	probe.check("map generated (non-empty)", size[1] * size[2] > 0 and hero_tile() ~= nil)
	probe.check("bgm/street_chip is the current BGM after 1s", audio.current_bgm() == "bgm/street_chip")
	probe.info("audio playback enabled: " .. tostring(audio.enabled()))

	-- 1. 键盘：按住 D 0.6 秒，失败再试 A
	local p0 = iso.entity_get_pos(HERO)
	probe.key(keys.D, true)
	wait(0.6)
	probe.key(keys.D, false)
	wait(0.4)
	local moved = dist(iso.entity_get_pos(HERO), p0)
	if moved <= 0.2 then
		p0 = iso.entity_get_pos(HERO)
		probe.key(keys.A, true)
		wait(0.6)
		probe.key(keys.A, false)
		moved = dist(iso.entity_get_pos(HERO), p0)
	end
	probe.check("keyboard D/A moves hero", moved > 0.2)
	probe.info(string.format("hero moved %.2f units", moved))

	-- 2. 鼠标点击寻路
	wait(0.3)
	local from = hero_tile()
	local target = from and pick_reachable(from)
	probe.check("found reachable target tile", target ~= nil)
	if target then
		local s = tile_screen(target)
		probe.check("target tile projects to the screen", s ~= nil)
		if s then
			probe.info(string.format("click from (%d,%d) to (%d,%d) at screen (%.0f,%.0f)",
				from[1], from[2], target[1], target[2], s[1], s[2]))
			probe.mouse_move(s[1], s[2])
			wait(0.1)
			s = tile_screen(target) or s -- 相机还在平滑时，按最新投影再对准一次
			probe.mouse_move(s[1], s[2])
			local before = audio.stats()
			probe.click(0)
			wait(0.1) -- 点击在本帧游戏 _update 中被消费
			local after = audio.stats()
			probe.check("click that starts pathing plays sfx (sfx_played +1)",
				after.sfx_played == before.sfx_played + 1)

			local t0 = now
			local arrived = false
			while now - t0 < 8.0 do
				local t = hero_tile()
				if t and t[1] == target[1] and t[2] == target[2] and not iso.entity_is_moving(HERO) then
					arrived = true
					break
				end
				coroutine.yield()
			end
			probe.check("mouse click pathfinds hero to target tile", arrived)
			probe.info(string.format("pathing took %.2fs", now - t0))
		end
	end

	-- 3. 音频：未知 id / 错误 kind 被拒绝并计数
	local a0 = audio.stats()
	probe.check("unknown sfx id returns false", audio.sfx("sfx/does_not_exist") == false)
	probe.check("bgm id used as sfx returns false", audio.sfx("bgm/street_chip") == false)
	probe.check("sfx id used as bgm returns false", audio.bgm("sfx/ui") == false)
	local a1 = audio.stats()
	probe.check("rejected sfx increments sfx_rejected", a1.sfx_rejected == a0.sfx_rejected + 2)
	probe.check("rejected bgm does not change bgm_started", a1.bgm_started == a0.bgm_started)
	probe.check("current BGM unchanged by rejected calls", audio.current_bgm() == "bgm/street_chip")

	-- 4. F5 热重载：脚本健康、实体重生，BGM 保持（不重播）
	local b0 = audio.stats().bgm_started
	probe.tap(keys.F5)
	wait(0.5)
	probe.check("F5 hot reload keeps script healthy", probe.script_ok())
	probe.check("entities respawned after reload", alive_count() >= 4)
	probe.check("BGM still bgm/street_chip after F5", audio.current_bgm() == "bgm/street_chip")
	probe.check("bgm_started did not increase after F5", audio.stats().bgm_started == b0)

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
