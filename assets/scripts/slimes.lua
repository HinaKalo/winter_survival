-- 史莱姆：循环播放弹跳动画；每隔 2~4 秒在附近随机挑一个可走格走过去。
-- slime.png：帧 32x32，1 行 4 帧。

local M = {}

local WANDER_RADIUS = 5
local list = {}

local function next_delay()
	return 2 + math.random() * 2
end

-- 在 (cx,cy) 附近找一个可走且互不重叠的格子
local function pick_spawn(iso, cx, cy, i)
	for r = 2 + i, 10 do
		for _ = 1, 20 do
			local x = cx + math.random(-r, r)
			local y = cy + math.random(-r, r)
			if iso.map_walkable(x, y) then
				return x, y
			end
		end
	end
	return cx, cy
end

function M.spawn(iso, cx, cy, count)
	M.iso = iso
	list = {}
	local sheet = iso.sheet_load("assets/sprites/slime.png", 32, 32)
	assert(sheet ~= 0, "无法加载 slime.png")
	for i = 1, count do
		local x, y = pick_spawn(iso, cx, cy, i)
		local id = iso.entity_spawn(sheet, x + 0.5, y + 0.5, 0.8, 0.8)
		iso.entity_set_speed(id, 1.2)
		iso.entity_play(id, 0, 4, 6, true) -- 一直弹跳
		list[#list + 1] = { id = id, timer = next_delay() * math.random() }
	end
end

function M.update(dt)
	local iso = M.iso
	for _, s in ipairs(list) do
		local moving = iso.entity_is_moving(s.id)
		if moving then
			s.was_moving = true
		elseif s.was_moving then
			-- 刚到达：重新计时 2~4 秒后再走
			s.was_moving = false
			s.timer = next_delay()
		end
		s.timer = s.timer - dt
		if s.timer <= 0 and not moving then
			s.timer = next_delay()
			local tile = iso.entity_get_tile(s.id)
			if tile then
				-- 多试几次：随机格可能不可走或无路
				for _ = 1, 8 do
					local tx = tile[1] + math.random(-WANDER_RADIUS, WANDER_RADIUS)
					local ty = tile[2] + math.random(-WANDER_RADIUS, WANDER_RADIUS)
					if iso.map_walkable(tx, ty) and iso.entity_path_to(s.id, tx, ty) then
						break
					end
				end
			end
		end
	end
end

return M
