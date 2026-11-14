-- 鼠标光标：求悬停格并高亮（可走为白、不可走为红）。

local iso = require("iso")

local M = {}

M.tile = nil -- 当前悬停格 {x, y} 或 nil
M.walkable = false

function M.update()
	local t = iso.mouse_tile()
	M.tile = t
	if t then
		M.walkable = iso.map_walkable(t[1], t[2])
		if M.walkable then
			iso.highlight_tile(t[1], t[2], 1, 1, 1, 0.45)
		else
			iso.highlight_tile(t[1], t[2], 1, 0.15, 0.15, 0.55)
		end
	else
		M.walkable = false
		iso.highlight_clear()
	end
end

return M
