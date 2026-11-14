-- 地形生成：用 sin/cos 叠加出高度 0~6，再放置水、桥、石柱。
--
-- 瓦片图集 assets/textures/tiles.png（8 列 4 行，索引 = 行*8+列）：
--   0 草顶 1 草侧 2 泥顶 3 泥侧 4 石顶 5 石侧 6 水顶 7 水侧
--   8 沙顶 9 沙侧 10 雪顶 11 雪侧 12 木顶 13 木侧
-- 高度含义：0 水(liquid)，1 沙，2~4 草，5 石，6 雪。

local M = {}

local MAP_W, MAP_H = 32, 32

-- 高度场：几个 sin/cos 叠加，结果夹在 0..6
local function height_at(x, y)
	local h = 2.7
		+ 1.6 * math.sin(x * 0.25) * math.cos(y * 0.2)
		+ 1.2 * math.sin((x + y) * 0.15)
		+ 0.8 * math.cos(x * 0.5 - y * 0.35)
	h = math.floor(h + 0.5)
	return math.max(0, math.min(6, h))
end

-- 河流中心线（x 随 y 弯曲）
local function river_x(y)
	return 17 + 3 * math.sin(y * 0.2)
end

-- 在 (cx,cy) 附近找一个平坦可走的格子（用于出生点）
local function find_walkable_near(iso, cx, cy)
	for r = 0, 12 do
		for dy = -r, r do
			for dx = -r, r do
				local x, y = cx + dx, cy + dy
				if iso.map_walkable(x, y) then
					return x, y
				end
			end
		end
	end
	return cx, cy
end
M.find_walkable_near = find_walkable_near

function M.generate(iso)
	assert(iso.tileset_load("assets/textures/tiles.png", 8, 4), "无法加载瓦片图集")
	iso.map_create(MAP_W, MAP_H)

	-- tile_define(顶面索引, 侧面索引, 是否实心, 是否液体) -> 瓦片种类 id
	local WATER = iso.tile_define(6, 7, false, true)
	local SAND = iso.tile_define(8, 9, false, false)
	local GRASS = iso.tile_define(0, 1, false, false)
	local DIRT = iso.tile_define(2, 3, false, false)
	local STONE = iso.tile_define(4, 5, false, false)
	local SNOW = iso.tile_define(10, 11, false, false)
	local WOOD = iso.tile_define(12, 13, false, false) -- 木板桥：可走
	local PILLAR = iso.tile_define(4, 5, true, false) -- 石柱：实心不可走

	local kind_by_height = { [0] = WATER, SAND, GRASS, GRASS, GRASS, STONE, SNOW }

	for y = 0, MAP_H - 1 do
		for x = 0, MAP_W - 1 do
			local h = height_at(x, y)
			if math.abs(x - river_x(y)) < 1.7 then
				h = 0 -- 河道
			end
			iso.map_set(x, y, kind_by_height[h], h)
		end
	end

	-- 木板桥：沿 y=16 一行横跨河道，两端各接一格沙地
	local by = 16
	local rx = math.floor(river_x(by) + 0.5)
	local x0, x1 = rx - 3, rx + 3
	for x = x0, x1 do
		if math.abs(x - river_x(by)) < 1.7 then
			iso.map_set(x, by, WOOD, 1) -- 桥面高度 1，与沙岸同高
		end
	end
	-- 保证桥头两侧是沙岸（高度 1），避免高差过大
	for _, x in ipairs({ x0, x0 + 1, x1 - 1, x1 }) do
		if not (math.abs(x - river_x(by)) < 1.7) then
			iso.map_set(x, by, SAND, 1)
		end
	end
	-- 桥面所在列向两侧各拓宽一个泥土格作为引桥
	iso.map_set(x0 - 1, by, DIRT, 1)
	iso.map_set(x1 + 1, by, DIRT, 1)

	-- 几根石柱（实心）：比周围地面高 3 格
	local pillars = { { 6, 10 }, { 7, 10 }, { 11, 22 }, { 24, 8 }, { 26, 24 }, { 13, 13 } }
	for _, p in ipairs(pillars) do
		local px, py = p[1], p[2]
		local t = iso.map_get(px, py)
		if t and t[1] ~= WATER and t[1] ~= WOOD then
			iso.map_set(px, py, PILLAR, math.min(255, t[2] + 3))
		end
	end

	-- 出生点：地图西半边靠中间的可走格
	local hx, hy = find_walkable_near(iso, 9, 16)
	return { hero_x = hx, hero_y = hy }
end

return M
