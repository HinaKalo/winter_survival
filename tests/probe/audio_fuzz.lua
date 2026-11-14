-- 音频封装 fuzz 探针：用 nil / 表 / 非数字字符串 / NaN / inf / 负数 调用 audio 封装的每个函数。
-- 断言：不产生脚本失败（probe.script_ok()），且返回值为 false / nil（或状态不变）。
-- 运行：zig build probe -Dbackend=headless -Dprobe=tests/probe/audio_fuzz.lua [-Dprobe-audio=false]

local probe = require("kit_probe")
local audio = require("audio")

probe.timeout(30)

local nan = 0 / 0
local inf = math.huge
local bad = {
	{ "nil", nil },
	{ "table", {} },
	{ "string", "abc" },
	{ "nan", nan },
	{ "inf", inf },
	{ "-inf", -inf },
	{ "negative", -1 },
	{ "boolean", true },
	{ "function", print },
}

local function scenario()
	local before_stats = audio.stats()
	local before_bgm = audio.current_bgm()

	-- 非字符串 / 未知 id：一律 false
	for _, c in ipairs(bad) do
		local n, v = c[1], c[2]
		probe.check("sfx(" .. n .. ") == false", audio.sfx(v) == false)
		probe.check("sfx(" .. n .. ", vol, pitch) == false", audio.sfx(v, v, v) == false)
		probe.check("sfx_var(" .. n .. ") == false", audio.sfx_var(v, v, v) == false)
		probe.check("bgm(" .. n .. ") == false", audio.bgm(v) == false)
		probe.check("bgm(" .. n .. ", fade) == false", audio.bgm(v, v) == false)
		probe.check("has(" .. n .. ") == false", audio.has(v) == false)
		probe.check("set_bus(" .. n .. ", v) == false", audio.set_bus(v, 0.5) == false)
		probe.check("set_bus(" .. n .. ", " .. n .. ") == false", audio.set_bus(v, v) == false)
		probe.check("script still ok after " .. n, probe.script_ok())
	end

	-- 合法 id + 非法数值：NaN / inf 一律被拒绝；其它类型回退默认值（不报错）
	for _, c in ipairs({ { "nan", nan }, { "inf", inf }, { "-inf", -inf } }) do
		probe.check("sfx(valid, " .. c[1] .. ") == false", audio.sfx("sfx/ui", c[2], 1) == false)
		probe.check("sfx(valid, 1, " .. c[1] .. ") == false", audio.sfx("sfx/ui", 1, c[2]) == false)
		probe.check("bgm(valid, " .. c[1] .. ") == false", audio.bgm("bgm/street_chip", c[2]) == false)
		probe.check("set_bus(master, " .. c[1] .. ") == false", audio.set_bus("master", c[2]) == false)
	end
	for _, c in ipairs(bad) do
		audio.sfx("sfx/ui", c[2], c[2])
		audio.sfx_var("sfx/ui", c[2], c[2])
		audio.stop_bgm(c[2])
		audio.set_bus("master", c[2])
		audio.set_bus("nope", c[2])
	end
	probe.check("script ok after valid-id fuzz", probe.script_ok())
	probe.check("unknown bus with valid value == false", audio.set_bus("nope", 0.5) == false)
	probe.check("current_bgm never errors", (pcall(audio.current_bgm)))

	local s = audio.stats()
	probe.check("rejected counter did not decrease", s.sfx_rejected >= before_stats.sfx_rejected)
	probe.check("current_bgm is nil or a string", audio.current_bgm() == nil or type(audio.current_bgm()) == "string")
	probe.info("bgm before=" .. tostring(before_bgm) .. " after=" .. tostring(audio.current_bgm()))

	audio.set_bus("master", 1) -- 还原
	probe.check("final script_ok", probe.script_ok())
	probe.finish()
end

local co = coroutine.create(scenario)

function _probe(t, dt)
	if coroutine.status(co) == "dead" then
		return
	end
	local ok, err = coroutine.resume(co)
	if not ok then
		error(err, 0)
	end
end
