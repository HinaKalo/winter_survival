-- 验收测试，编码代理不得修改（主代理编写；认为有误时停下报告）。docs/M4L-PLAN.md §3。
-- M4-lite 家园场景端到端探针（纯键盘）：标题 → 新游戏 → 家园白天 → 选人 → 交互菜单 → 加速 →
-- 长按结束白天 → 黄昏面板 → 黎明报告 → 第 2 天。
-- 场景约定（冻结）：
--   scenes/home.lua：M.session（game/home_session 会话）、M.actors（cid -> actors 句柄）、M.selected（cid）、
--                    M.menu（nil 或 { items = hs.actions(...) 的列表, focus = 序号 }）
--   scenes/dusk.lua、scenes/dawn.lua：以 scene.push_modal 弹出；确认键（confirm）按默认选择提交
--   按键一律经 core/input 的动作（不写死键码）
local probe = require("kit_probe")
local scene = require("core.scene")
local input = require("core.input")
local serialize = require("core.serialize")

probe.timeout(90)

local now = 0
local function wait(sec)
  local untl = now + sec
  while now < untl do
    coroutine.yield()
  end
end

local function kb(id)
  local b = input.get_binding("keyboard", id, 1)
  assert(b and b.key, "keyboard binding for " .. id)
  return b
end

local function mods(b, down)
  if b.shift then probe.key(keys.LEFT_SHIFT, down) end
  if b.ctrl then probe.key(keys.LEFT_CONTROL, down) end
end

local function tap(id)
  local b = kb(id)
  mods(b, true)
  wait(0.03)
  probe.tap(b.key)
  wait(0.1)
  mods(b, false)
  wait(0.05)
end

local function hold(id, sec)
  local b = kb(id)
  mods(b, true)
  wait(0.03)
  probe.key(b.key, true)
  wait(sec)
  probe.key(b.key, false)
  mods(b, false)
  wait(0.1)
end

local function scenario()
  wait(0.4)
  -- title: the default focus is "new game"
  tap("confirm")
  wait(0.6)
  local home = require("scenes.home")
  probe.check("new game enters the home scene", scene.top() == home)
  local s = home.session
  probe.check("session in day mode on day 1", s and s.mode == "day" and s.state.clock.day == 1)
  local n = #s.state.party.order
  local count = 0
  for _ in pairs(home.actors or {}) do count = count + 1 end
  probe.check("one actor per party member (" .. count .. "/" .. n .. ")", count == n)
  probe.check("first character selected", home.selected == s.state.party.order[1])

  tap("select_next")
  probe.check("select_next selects the second character", home.selected == s.state.party.order[2])

  -- interaction menu for the selected character
  tap("interact")
  probe.check("interact opens the action menu", home.menu ~= nil and #home.menu.items > 0)
  local before = serialize.encode(s.state)
  local item = home.menu and home.menu.items[home.menu.focus]
  probe.check("menu focus starts on an enabled action", item ~= nil and item.enabled == true)
  tap("confirm")
  probe.check("confirm runs the action and closes the menu",
    home.menu == nil and serialize.encode(s.state) ~= before)

  local m0 = s.state.clock.minute
  tap("speed_up")
  probe.check("speed_up raises the speed", s.speed_idx == 3)
  wait(1.0)
  probe.check("time advances in day mode", s.state.clock.minute > m0)

  hold("end_day", input.HOLD_S + 0.4)
  wait(0.3)
  local dusk = require("scenes.dusk")
  probe.check("holding end_day opens the dusk panel", s.mode == "dusk" and scene.top() == dusk)

  tap("confirm")
  wait(0.5)
  local dawn = require("scenes.dawn")
  probe.check("confirming dusk shows the dawn report", s.mode == "dawn" and scene.top() == dawn)

  tap("confirm")
  wait(0.5)
  probe.check("confirming dawn returns to day 2",
    s.mode == "day" and s.state.clock.day == 2 and scene.top() == home)

  probe.check("script healthy", probe.script_ok())
  probe.finish()
end

local co = coroutine.create(scenario)

function _probe(t, dt)
  now = t
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then error(err, 0) end
end
