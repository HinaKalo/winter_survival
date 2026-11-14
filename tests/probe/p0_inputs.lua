-- 验收探针（主代理编写，编码代理不得修改）。P0-PLAN §4 P0-3。
-- 对每个动作 × 每个有默认绑定的设备，用 kit_probe 注入真实输入（键盘含修饰键、鼠标、手柄按钮 / LT 组合 / 右摇杆方向），
-- 断言：目标动作被触发且只触发一次（摇杆方向允许重复）；长按在 HOLD_S 之后 2 帧内触发；有配对的短按在松开时触发；
-- 无配对的短按在按下帧触发；同时触发的其他动作只能是上下文不互斥的动作或 SHARED_DEFAULTS 白名单伙伴。
-- 判定规则与 tests/lua/test_input_actions.lua 相同（tests/lua/p0_input_cases.lua）。
-- 依赖：assets/main.lua 每帧在 scene.update 之前调用 input.update(dt)。
package.path = "tests/lua/?.lua;" .. package.path
local probe = require("kit_probe")
local input = require("core.input")
local scene = require("core.scene")
local cases_mod = require("p0_input_cases")

probe.timeout(240)

local now = 0
local max_dt = 0
local function wait(sec)
  local untl = now + sec
  while now < untl do coroutine.yield() end
end

-- neutral scene: records what fired each frame (scene.update runs after input.update in main.lua)
local rec = nil -- { t0 = press time, release_t = nil|time, fired = {} }
local sink = {
  update = function(_, dt)
    if dt > max_dt then max_dt = dt end
    if not rec then return end
    for _, a in ipairs(input.ACTIONS) do
      if input.pressed(a.id) then
        local f = rec.fired[a.id]
        if not f then
          f = { count = 0, first = now - rec.t0, at_release = rec.release_t ~= nil and now - rec.release_t < 0.05 }
          rec.fired[a.id] = f
        end
        f.count = f.count + 1
      end
    end
  end,
  draw = function() end,
}

local AX = { rs = { x = pad_axes.rx, y = pad_axes.ry }, ls = { x = pad_axes.lx, y = pad_axes.ly } }

local function inject(device, b, down)
  if device == "keyboard" then
    probe.key(b.key, down)
  elseif device == "mouse" then
    probe.mouse_button(b.btn, down)
  elseif b.axis then
    local st, v = AX[b.axis], down and 1.0 or 0.0
    if b.dir == "up" then probe.pad_axis(st.y, -v)
    elseif b.dir == "down" then probe.pad_axis(st.y, v)
    elseif b.dir == "left" then probe.pad_axis(st.x, -v)
    else probe.pad_axis(st.x, v) end
  else
    probe.pad_button(b.btn, down)
  end
end

local function mods(device, b, down)
  if device == "keyboard" then
    if b.shift then probe.key(keys.LEFT_SHIFT, down) end
    if b.ctrl then probe.key(keys.LEFT_CONTROL, down) end
  elseif device == "pad" and b.lt then
    probe.pad_button(pad_buttons.lt, down)
  end
end

local function run_case(case, hold_time)
  mods(case.device, case.b, true)
  wait(0.05)
  rec = { t0 = now, fired = {} }
  inject(case.device, case.b, true)
  wait(hold_time)
  rec.release_t = now
  inject(case.device, case.b, false)
  wait(0.08)
  local fired = rec.fired
  rec = nil
  mods(case.device, case.b, false)
  wait(0.05)
  return fired
end

local function scenario()
  wait(0.3)
  scene.clear()
  scene.push(sink)
  input.set_dev(true)
  input.reset_all()
  wait(0.1)
  local list = cases_mod.cases(input)
  probe.check("case count > 80", #list > 80)
  local hold_s = input.HOLD_S
  for _, case in ipairs(list) do
    local hold_time = case.hold and (hold_s + 0.1) or 0.1
    local fired = run_case(case, hold_time)
    -- injected input reaches the game on the next frame: one frame of latency
    local e = cases_mod.judge(input, case, fired, hold_s, max_dt, max_dt)
    probe.check(case.device .. ":" .. case.id .. (e and (" -- " .. e) or ""), e == nil)
    if case.hold then
      local tap = run_case(case, 0.1)
      probe.check(case.device .. ":" .. case.id .. " not on short tap", tap[case.id] == nil)
    end
  end
  input.set_dev(false)
  probe.finish()
end

local co = coroutine.create(scenario)

function _probe(t, _dt)
  now = t
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then error(err, 0) end
end
