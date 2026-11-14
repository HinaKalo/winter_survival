-- 演示游戏入口：等距 2.5D 基座的使用模板。
--
-- 约定：
--   * 引擎（Zig）调用全局函数 _init() / _update(dt) / _draw() / _shutdown()，都可省略；
--   * 子模块放在 assets/scripts/，直接 require("hero") 即可；
--   * 按 F5 热重载：重新执行本文件并调用 _init；Lua 出错时游戏暂停脚本，修好后按 F5 恢复。
--
-- 开新游戏：保留本文件的骨架，替换 world_gen / hero / slimes / hud 即可。

local iso = require("iso")
local world_gen = require("world_gen")
local hero = require("hero")
local slimes = require("slimes")
local cursor = require("cursor")
local hud = require("hud")
local audio = require("audio")

-- 调试开关：设置环境变量 ISO_AUTOQUIT=秒数 则在该时间后自动退出（默认关闭）
local autoquit_after = tonumber(os.getenv("ISO_AUTOQUIT") or "")
local elapsed = 0

local ZOOM_SPEED = 1.2 -- 每秒缩放比例

function _init()
	-- 1. 地形：载入图集、定义瓦片、生成地图
	local info = world_gen.generate(iso)

	-- 2. 角色
	hero.spawn(iso, info.hero_x, info.hero_y)
	slimes.spawn(iso, info.hero_x, info.hero_y, 3)

	-- 3. 相机：跟随主角（默认 yaw=45, pitch=30，即 2:1 像素等距观感）
	iso.camera_follow(hero.id)
	local px, py, pz = table.unpack(iso.entity_get_pos(hero.id))
	iso.camera_set_target(px, py, pz)

	-- 4. 背景音乐（热重载后再次调用同一首是空操作，不会重播）
	audio.bgm("bgm/street_chip")
end

function _update(dt)
	elapsed = elapsed + dt
	if autoquit_after and elapsed >= autoquit_after then
		iso.quit()
	end

	-- 通用按键
	if iso.key_pressed(keys.ESCAPE) then
		iso.quit()
	end
	if iso.key_pressed(keys.Q) then
		iso.camera_rotate(-1)
		audio.sfx("sfx/swing1")
	end
	if iso.key_pressed(keys.E) then
		iso.camera_rotate(1)
		audio.sfx("sfx/swing1")
	end
	if iso.key_down(keys.Z) then
		iso.camera_set_zoom(iso.camera_get_zoom() * (1 + ZOOM_SPEED * dt))
	end
	if iso.key_down(keys.X) then
		iso.camera_set_zoom(iso.camera_get_zoom() / (1 + ZOOM_SPEED * dt))
	end

	-- 游戏逻辑（顺序：光标 -> 主角 -> 史莱姆）
	cursor.update()
	hero.update(dt, cursor.tile)
	slimes.update(dt)
end

function _draw()
	hud.draw(iso, hero, cursor, audio)
end
