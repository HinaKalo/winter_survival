-- HUD：左上角显示 FPS、主角格坐标/高度、悬停格信息、操作说明。
-- 使用 Delve 自带的 draw / text 库（调色板索引：0 黑 7 白 10 黄 5 深灰）。
-- 注意：不要调用 display.set_resolution，否则会影响 HUD 坐标。
-- Delve 位图字体没有 "_" 字形（会显示成 €），显示 id 时换成 "-"。

local draw = require("draw")
local text = require("text")

local M = {}

local WHITE, YELLOW, BLACK = 7, 10, 0
local LINE_H = 20 -- 字符 16px 宽，行距取 20

local function line(str, y, color)
	text.draw(str, 10, y, color)
end

function M.draw(iso, hero, cursor, audio)
	-- 半透明感的深色底条
	draw.filled_rectangle(4, 4, 660, LINE_H * 5 + 12, BLACK)

	local tile = iso.entity_get_tile(hero.id)
	local hero_str = "Hero: -"
	if tile then
		local t = iso.map_get(tile[1], tile[2])
		hero_str = string.format("Hero tile: (%d, %d)  height: %d", tile[1], tile[2], t and t[2] or 0)
	end
	line(string.format("FPS: %d   %s", iso.fps(), hero_str), 8, YELLOW)

	local hover = "Hover: -"
	if cursor.tile then
		local t = iso.map_get(cursor.tile[1], cursor.tile[2])
		hover = string.format(
			"Hover: (%d, %d) kind %d height %d %s",
			cursor.tile[1], cursor.tile[2], t and t[1] or 0, t and t[2] or 0,
			cursor.walkable and "walkable" or "blocked"
		)
	end
	line(hover, 8 + LINE_H, WHITE)

	line("WASD move  Click walk  Q/E rotate", 8 + LINE_H * 2, WHITE)
	line("Z/X zoom  F5 reload  ESC quit", 8 + LINE_H * 3, WHITE)

	if audio then
		line(string.format("BGM: %s   SFX played: %d", ((audio.current_bgm() or "-"):gsub("_", "-")), audio.stats().sfx_played), 8 + LINE_H * 4, WHITE)
	end
end

return M
