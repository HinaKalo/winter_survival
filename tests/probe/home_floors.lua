-- 验收测试，编码代理不得修改（主代理编写；认为有误时停下报告）。docs/M5-3D-PLAN.md §6、§7。
-- 三层家园端到端（纯键盘 + 会话接口）：开局 1F → 切层 → 幽灵 → 让人去地下室（菜单）→ 跨层 → 选人自动切层 → 炉子开关上模型。
-- 场景冻结字段：scenes/home.lua 的 M.session / M.actors / M.selected / M.menu（M4L），
--               以及 M.view_floor（"B1"|"F1"|"F2"）、M.model（iso 模型 id）、M.actor_floor（cid -> 楼层）。
local probe = require("kit_probe")
local scene = require("core.scene")
local input = require("core.input")
local hs = require("game.home_session")

probe.timeout(150)

local now = 0
local function wait(sec)
  local untl = now + sec
  while now < untl do coroutine.yield() end
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

local function wait_until(sec, fn)
  local untl = now + sec
  while now < untl do
    if fn() then return true end
    coroutine.yield()
  end
  return fn()
end

local function vis(home, name) return iso.model_node_visible(home.model, name) end

local function ghosts(home)
  local g, n = 0, 0
  for _, a in pairs(home.actors) do
    n = n + 1
    if iso.entity_get_ghost(a.id) then g = g + 1 end
  end
  return g, n
end

local function scenario()
  wait(0.4)
  tap("confirm") -- title: new game
  wait(0.8)
  local home = require("scenes.home")
  probe.check("new game enters the home scene", scene.top() == home)
  local s = home.session

  -- start: 1F, model loaded, cutaway
  probe.check("starts viewing 1F", home.view_floor == "F1")
  probe.check("model loaded", type(home.model) == "number" and iso.model_info(home.model) ~= nil)
  probe.check("1F floor and low walls visible", vis(home, "F1_floor") == true and vis(home, "F1_wall_low") == true)
  probe.check("1F high walls cut away", vis(home, "F1_wall_high") == false)
  probe.check("other floors and roof hidden",
    vis(home, "B1_floor") == false and vis(home, "F2_floor") == false and vis(home, "roof_panel_0") == false)
  local all_f1 = true
  for _, cid in ipairs(s.state.party.order) do
    if home.actor_floor[cid] ~= "F1" then all_f1 = false end
  end
  probe.check("everyone starts on 1F", all_f1)
  local g, n = ghosts(home)
  probe.check("no ghosts while everyone is on the viewed floor", g == 0 and n == #s.state.party.order)

  -- switch floors
  tap("floor_down")
  wait(0.4)
  probe.check("floor_down shows B1", home.view_floor == "B1")
  probe.check("B1 geometry visible, 1F hidden", vis(home, "B1_floor") == true and vis(home, "F1_floor") == false)
  g, n = ghosts(home)
  probe.check("1F people are ghosts while viewing B1 (" .. g .. "/" .. n .. ")", g == n)
  tap("floor_down")
  wait(0.3)
  probe.check("floor_down at the bottom stays on B1", home.view_floor == "B1")
  tap("floor_up")
  wait(0.3)
  tap("floor_up")
  wait(0.4)
  probe.check("two floor_up reach 2F", home.view_floor == "F2" and vis(home, "F2_floor") == true)
  tap("floor_up")
  wait(0.3)
  probe.check("floor_up at the top stays on 2F", home.view_floor == "F2")
  tap("floor_down")
  wait(0.4)
  probe.check("back on 1F", home.view_floor == "F1")
  g = ghosts(home)
  probe.check("no ghosts again on 1F", g == 0)

  -- send the selected character to the basement shelter through the action menu
  local cid = home.selected
  tap("interact")
  probe.check("menu opens", home.menu ~= nil)
  local target
  for i, it in ipairs(home.menu and home.menu.items or {}) do
    if it.id == "move:shelter" then target = i end
  end
  probe.check("menu offers move:shelter", target ~= nil and home.menu.items[target].enabled)
  if target then
    local guard = 0
    while home.menu and home.menu.focus ~= target and guard < 200 do
      tap(home.menu.focus < target and "ui_down" or "ui_up")
      guard = guard + 1
    end
    tap("confirm")
  end
  probe.check("move assigned the shelter", s.state.party.chars[cid].room == "shelter")
  probe.check("still viewing 1F after giving the order", home.view_floor == "F1")
  local arrived = wait_until(40, function() return home.actor_floor[cid] == "B1" end)
  probe.check("the character walks down to B1", arrived)
  probe.check("viewing 1F: the basement dweller is a ghost", iso.entity_get_ghost(home.actors[cid].id) == true)

  -- selecting someone on another floor follows them
  local other_idx
  for i, c in ipairs(s.state.party.order) do
    if c ~= cid then other_idx = i; break end
  end
  local idx
  for i, c in ipairs(s.state.party.order) do if c == cid then idx = i end end
  tap("select_" .. other_idx)
  wait(0.3)
  probe.check("selecting a 1F character keeps 1F", home.view_floor == "F1")
  tap("select_" .. idx)
  wait(0.4)
  probe.check("selecting the basement character switches to B1", home.view_floor == "B1")
  probe.check("on B1 the character is a normal entity", iso.entity_get_ghost(home.actors[cid].id) == false)
  local others_ghost = true
  for c, a in pairs(home.actors) do
    if c ~= cid and home.actor_floor[c] == "F1" and not iso.entity_get_ghost(a.id) then others_ghost = false end
  end
  probe.check("1F people are ghosts from B1", others_ghost)

  -- station state shows on the model
  tap("select_" .. other_idx)
  wait(0.4)
  probe.check("back to 1F with a 1F character", home.view_floor == "F1")
  local stove_on = s.state.home.stations.f_woodstove and s.state.home.stations.f_woodstove.on
  probe.check("stove model matches the stove (" .. tostring(stove_on) .. ")",
    vis(home, "F1_woodstove_on") == (stove_on and true or false)
    and vis(home, "F1_woodstove_off") == not stove_on)
  local ok = hs.act(s, home.selected, "toggle:f_woodstove")
  wait(0.4)
  local now_on = s.state.home.stations.f_woodstove.on
  probe.check("toggling the stove succeeded", ok and now_on ~= stove_on)
  probe.check("stove model follows the toggle",
    vis(home, "F1_woodstove_on") == now_on and vis(home, "F1_woodstove_off") == not now_on)

  -- time still runs and nothing broke
  local m0 = s.state.clock.minute
  wait(1.0)
  probe.check("time advances", s.state.clock.minute > m0)
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
