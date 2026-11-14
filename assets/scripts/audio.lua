-- 音频封装：local audio = require("audio")
-- 底层是 Zig 原始库 kit_audio（固定参数个数），这里补上默认值和类型守卫。
-- 所有函数对未知 id / 非法数值 / 错误类型都是安全的空操作（返回 false），不会报错。
--
--   audio.sfx(id, vol, pitch)       播放音效；vol 默认 1，pitch 默认 1；返回是否播放
--   audio.sfx_var(id, vol, spread)  随机音高 1±spread（默认 0.05）
--   audio.bgm(id, fade)             切换 BGM；fade 默认 1.0 秒；同一首重复调用是空操作（返回 true）
--   audio.stop_bgm(fade)            停止 BGM；fade 默认 1.0 秒
--   audio.set_bus(name, v)          name = "master" | "sfx" | "bgm"，v = 0..1
--   audio.has(id)                   目录里是否有该 id
--   audio.current_bgm()             当前 BGM id 或 nil
--   audio.stats()                   {sfx_played=, sfx_rejected=, bgm_started=}
--   audio.enabled()                 是否真的在出声（--no-audio 时为 false）
--
-- 参数类型守卫：id / 总线名必须是字符串；数值参数走 tonumber，得到 nil 则用默认值；
-- 其它错误类型返回 false（current_bgm 返回 nil），并按函数+参数只打印一次日志。
-- 原始库 kit_audio / kit_probe 是内部接口：参数类型错误会直接抛 binder 错误，游戏脚本不要直接 require。

local k = require("kit_audio")

local M = {}

local warned = {}
local function warn_once(key, msg)
	if not warned[key] then
		warned[key] = true
		print("[audio] " .. msg)
	end
end

-- 必须是字符串，否则警告一次并返回 nil
local function str(fn, what, v)
	if type(v) == "string" then
		return v
	end
	warn_once(fn .. ":" .. what, fn .. ": " .. what .. " must be a string, got " .. type(v))
	return nil
end

-- 数值：可转换则返回数字，否则（nil / 无法转换）用默认值；NaN/inf 交给 Zig 侧拒绝
local function num(v, default)
	local n = tonumber(v)
	if n == nil then
		return default
	end
	return n
end

function M.sfx(id, vol, pitch)
	id = str("sfx", "id", id)
	if not id then
		return false
	end
	return k.sfx(id, num(vol, 1), num(pitch, 1))
end

function M.sfx_var(id, vol, spread)
	id = str("sfx_var", "id", id)
	if not id then
		return false
	end
	spread = num(spread, 0.05)
	return k.sfx(id, num(vol, 1), 1 + (math.random() * 2 - 1) * spread)
end

function M.bgm(id, fade)
	id = str("bgm", "id", id)
	if not id then
		return false
	end
	return k.bgm(id, num(fade, 1.0))
end

function M.stop_bgm(fade)
	k.stop_bgm(num(fade, 1.0))
end

local function layer_num(fn, layer)
	if type(layer) ~= "number" or layer < 1 or layer > 3 or layer ~= math.floor(layer) then
		warn_once(fn .. ":layer", fn .. ": layer must be 1..3")
		return nil
	end
	return layer
end

function M.amb(layer, id, fade)
	layer = layer_num("amb", layer)
	if not layer then
		return false
	end
	id = str("amb", "id", id)
	if not id then
		return false
	end
	return k.amb(layer, id, num(fade, 1.0))
end

function M.stop_amb(layer, fade)
	layer = layer_num("stop_amb", layer)
	if not layer then
		return
	end
	k.stop_amb(layer, num(fade, 1.0))
end

function M.amb_gain(layer, v, fade)
	layer = layer_num("amb_gain", layer)
	if not layer then
		return false
	end
	v = tonumber(v)
	if v == nil then
		warn_once("amb_gain:v", "amb_gain: v must be a number")
		return false
	end
	return k.amb_gain(layer, v, num(fade, 0.2))
end

function M.current_amb(layer)
	layer = layer_num("current_amb", layer)
	if not layer then
		return nil
	end
	return k.current_amb(layer)
end

function M.set_bus(name, v)
	name = str("set_bus", "name", name)
	if not name then
		return false
	end
	v = tonumber(v)
	if v == nil then
		warn_once("set_bus:v", "set_bus: value must be a number")
		return false
	end
	return k.set_bus(name, v)
end

function M.has(id)
	id = str("has", "id", id)
	if not id then
		return false
	end
	return k.has(id)
end

function M.current_bgm()
	return k.current_bgm()
end

function M.stats()
	local s = k.stats()
	return { sfx_played = s[1], sfx_rejected = s[2], bgm_started = s[3] }
end

function M.enabled()
	return k.enabled()
end

return M
