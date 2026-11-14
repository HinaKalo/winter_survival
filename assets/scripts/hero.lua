-- 主角：WASD 按屏幕方向连续移动；左键点击格子寻路；按朝向 + 是否移动选动画。
--
-- hero.png：每帧 32x48，4 列走路帧 x 4 行方向（行 0 下、1 左、2 右、3 上）。
-- 帧号 = 行 * 4 + 列。entity_facing 返回 0..3 正好对应行号。

local audio = require("audio")

local M = {}

local FRAME_W, FRAME_H = 32, 48
local WALK_FPS = 8
local WALK_SPEED = 3.0
local PROBE = 0.15 -- 前探距离：目标点落在不可走格子里就不动

M.id = 0
local pathing = false -- 正在执行点击寻路
local goal_x, goal_y = 0, 0 -- 寻路目标格

function M.spawn(iso, tx, ty)
	local sheet = iso.sheet_load("assets/sprites/hero.png", FRAME_W, FRAME_H)
	assert(sheet ~= 0, "无法加载 hero.png")
	M.iso = iso
	M.id = iso.entity_spawn(sheet, tx + 0.5, ty + 0.5, 1.0, 1.5)
	iso.entity_set_speed(M.id, WALK_SPEED)
	iso.entity_set_frame(M.id, 0)
	pathing = false
end

-- 把屏幕方向的输入 (右, 上) 转成世界水平方向 (dx, dz)。
-- 相机 yaw 下：屏幕右 = (cos y, -sin y)，屏幕上(远离相机) = (-sin y, -cos y)。
local function screen_to_world(sx, sy, yaw_deg)
	local yaw = math.rad(yaw_deg)
	local s, c = math.sin(yaw), math.cos(yaw)
	return sx * c - sy * s, -sx * s - sy * c
end

-- 从 (x,z) 走向 (nx,nz) 是否允许：目标格可走，且（跨格时）高度差满足 canStep
local function can_go(iso, x, z, nx, nz)
	local fx, fy = math.floor(x), math.floor(z)
	local tx, ty = math.floor(nx), math.floor(nz)
	if fx == tx and fy == ty then
		return iso.map_walkable(tx, ty)
	end
	return iso.map_can_step(fx, fy, tx, ty)
end

function M.update(dt, hover_tile)
	local iso = M.iso
	local id = M.id
	if not iso.entity_exists(id) then
		return
	end

	-- 读取 WASD
	local ix, iy = 0, 0
	if iso.key_down(keys.D) then ix = ix + 1 end
	if iso.key_down(keys.A) then ix = ix - 1 end
	if iso.key_down(keys.W) then iy = iy + 1 end
	if iso.key_down(keys.S) then iy = iy - 1 end

	local px, py, pz = table.unpack(iso.entity_get_pos(id))

	if ix ~= 0 or iy ~= 0 then
		-- 手动移动：取消寻路
		pathing = false
		local dx, dz = screen_to_world(ix, iy, iso.camera_get_yaw())
		local len = math.sqrt(dx * dx + dz * dz)
		dx, dz = dx / len, dz / len

		-- 先试完整方向，不行再沿单轴滑动
		local candidates = { { dx, dz }, { dx, 0 }, { 0, dz } }
		local moved = false
		for _, d in ipairs(candidates) do
			if (d[1] ~= 0 or d[2] ~= 0) and can_go(iso, px, pz, px + d[1] * PROBE, pz + d[2] * PROBE) then
				-- 把目标设在前方 PROBE 处：引擎负责移动、朝向与贴地
				iso.entity_move_to(id, px + d[1] * PROBE, pz + d[2] * PROBE)
				moved = true
				break
			end
		end
		if not moved then
			iso.entity_stop(id)
		end
	elseif pathing then
		-- 点击寻路：路径最长 64 格，走完后若还没到目标则继续
		if not iso.entity_is_moving(id) then
			local tile = iso.entity_get_tile(id)
			if tile and (tile[1] ~= goal_x or tile[2] ~= goal_y) then
				pathing = iso.entity_path_to(id, goal_x, goal_y)
			else
				pathing = false
			end
		end
	else
		iso.entity_stop(id) -- 松开按键立即停下
	end

	-- 左键点击：寻路到悬停格
	if iso.mouse_pressed(0) and hover_tile then
		if iso.map_walkable(hover_tile[1], hover_tile[2]) and iso.entity_path_to(id, hover_tile[1], hover_tile[2]) then
			pathing = true
			goal_x, goal_y = hover_tile[1], hover_tile[2]
			audio.sfx("sfx/ui")
		else
			audio.sfx("sfx/blip") -- 点到不可走 / 到不了的格子
		end
	end

	-- 动画：行 = 朝向；移动中循环播放 4 帧，站立停在第 0 帧
	local row = iso.entity_facing(id)
	if iso.entity_is_moving(id) then
		iso.entity_play(id, row * 4, 4, WALK_FPS, true)
	else
		iso.entity_set_frame(id, row * 4)
	end
end

return M
