-- 验收测试（主代理编写，编码代理不得修改；认为有误时停下报告）。
-- P0-PLAN §3.3 / §4 P0-3：输入动作补齐（UI-UX §7.1），长按 / 短按配对 / 摇杆方向 / 上下文 F。
--
-- 本文件冻结的接口（§3.3 未写明的部分以此为准）：
--   input.update(dt)            每帧调用一次（assets/main.lua 在 scene.update 之前调用），推进长按计时与配对状态
--   input.pressed(id[, device]) 该帧触发：无配对短按 = 按下帧；有配对短按 = 松开帧（按住 < HOLD_S）；
--                               长按 = 按满 HOLD_S 的那一帧（一次）；摇杆方向 = 越过 0.5 的边沿，并按
--                               ui_dir_repeat 的节奏重复（0.35 s 后每 0.09 s）
--   input.HOLD_S                默认 0.5；input.set_hold_s(s) 由设置页 acc.hold_duration 调用
--   input.set_dev(on)           main.lua 用 sys.launch_opts().dev 调用；为假时 dev_panel 永不触发
--   input.pan_vec() -> dx, dy   camera_pan 的值（键盘四个命名槽 up/left/down/right + 右摇杆 rs 整轴）
--   input.CTX_CONFLICTS         公开；含 F = { F = true, G = true }
--   input.SHARED_DEFAULTS       { { device = "pad", actions = { "select", "interact" } }, ... }
--   input.find_conflicts(device, id, b) -> 列表（find_conflict 返回其中第一个）
--   动作字段 hold = { keyboard = true, pad = true }
-- 硬件只通过这些函数读取（本测试替换它们模拟设备）：iso.key_down/key_pressed、iso.mouse_down/mouse_pressed、
-- kit_input.key_released/mouse_released、pad.button_down/button_pressed/button_released、pad.axis。
package.path = "assets/scripts/?.lua;assets/?.lua;tests/lua/?.lua;" .. package.path

local input = require("core.input")
local i18n = require("core.i18n")
local cases_mod = require("p0_input_cases")

local K, PB, PA = keys, pad_buttons, pad_axes
local T = {}
local DT = 1 / 60

-- ---------------------------------------------------------------- fake devices

local cur, prev

local function blank() return { key = {}, mouse = {}, pad = {}, axis = {} } end

local function copy(s)
  local o = blank()
  for kind, t in pairs(s) do for k, v in pairs(t) do o[kind][k] = v end end
  return o
end

local function with_fake(fn)
  cur, prev = blank(), blank()
  local kin_was_nil = kit_input == nil
  if kin_was_nil then kit_input = {} end
  local patches = {
    { iso, "key_down", function(c) return cur.key[c] == true end },
    { iso, "key_pressed", function(c) return cur.key[c] == true and not prev.key[c] end },
    { iso, "mouse_down", function(b) return cur.mouse[b] == true end },
    { iso, "mouse_pressed", function(b) return cur.mouse[b] == true and not prev.mouse[b] end },
    { kit_input, "key_released", function(c) return prev.key[c] == true and not cur.key[c] end },
    { kit_input, "mouse_released", function(b) return prev.mouse[b] == true and not cur.mouse[b] end },
    { pad, "button_down", function(b) return cur.pad[b] == true end },
    { pad, "button_pressed", function(b) return cur.pad[b] == true and not prev.pad[b] end },
    { pad, "button_released", function(b) return prev.pad[b] == true and not cur.pad[b] end },
    { pad, "axis", function(a) return cur.axis[a] or 0 end },
  }
  local saved = {}
  for i, p in ipairs(patches) do saved[i] = p[1][p[2]]; p[1][p[2]] = p[3] end
  local ok, err = pcall(fn)
  for i, p in ipairs(patches) do p[1][p[2]] = saved[i] end
  if kin_was_nil then kit_input = nil end
  input.reset_all()
  input.set_dev(false)
  assert(ok, tostring(err))
end

-- one frame: update, collect pressed() for every action, then advance prev
local function frame()
  input.update(DT)
  local fired = {}
  for _, a in ipairs(input.ACTIONS) do
    if input.pressed(a.id) then fired[#fired + 1] = a.id end
  end
  prev = copy(cur)
  return fired
end

local STICK = { ls = { x = PA.lx, y = PA.ly }, rs = { x = PA.rx, y = PA.ry } }

local function apply(device, b, down)
  if device == "keyboard" then
    cur.key[b.key] = down or nil
  elseif device == "mouse" then
    cur.mouse[b.btn] = down or nil
  elseif b.axis then
    local st = STICK[b.axis]
    local v = down and 1 or 0
    if b.dir == "up" then cur.axis[st.y] = -v
    elseif b.dir == "down" then cur.axis[st.y] = v
    elseif b.dir == "left" then cur.axis[st.x] = -v
    else cur.axis[st.x] = v end
  else
    cur.pad[b.btn] = down or nil
  end
end

local function modifiers(device, b, down)
  if device == "keyboard" then
    if b.shift then cur.key[K.LEFT_SHIFT] = down or nil end
    if b.ctrl then cur.key[K.LEFT_CONTROL] = down or nil end
  elseif device == "pad" and b.lt then
    cur.pad[PB.lt] = down or nil
  end
end

-- press case.b, hold `hold_time`, release; returns fired map (see p0_input_cases.judge)
local function run_case(case, hold_time)
  for _ = 1, 3 do frame() end -- settle
  modifiers(case.device, case.b, true)
  frame() -- modifier edge is not part of the measurement
  apply(case.device, case.b, true)
  local fired, t = {}, 0
  local released = false
  local nframes = math.floor(hold_time / DT + 0.5)
  for i = 0, nframes + 3 do
    if i == nframes then apply(case.device, case.b, false); released = true end
    for _, id in ipairs(frame()) do
      local f = fired[id]
      if not f then
        f = { count = 0, first = t, at_release = released and i == nframes }
        fired[id] = f
      end
      f.count = f.count + 1
    end
    t = t + DT
  end
  modifiers(case.device, case.b, false)
  for _ = 1, 3 do frame() end
  return fired
end

-- ---------------------------------------------------------------- action table

function T.action_ids_match_spec()
  local have = {}
  for _, a in ipairs(input.ACTIONS) do
    assert(not have[a.id], "duplicate action " .. a.id)
    have[a.id] = a
  end
  for _, id in ipairs(cases_mod.SPEC_IDS) do assert(have[id], "missing action " .. id) end
  for _, id in ipairs(cases_mod.DEV_IDS) do assert(have[id], "missing dev action " .. id) end
  local n = 0
  for id in pairs(have) do
    if not id:match("^dev%.") then n = n + 1 end
  end
  assert(#cases_mod.SPEC_IDS == 65)
  assert(n == 65, "non-dev action count " .. n)
end

function T.contexts()
  local want = {
    select_1 = "W", select_6 = "W", select_next = "W", select_prev = "W", select_all = "H",
    focus_next = "W", focus_prev = "W", cursor_click_l = "F", cursor_click_r = "F",
    squad_follow = "R", squad_hold = "R", squad_lookout = "R", squad_carry = "R",
    quick_1 = "W", quick_4 = "W", camera_pan = "W",
    screenshot = "G", fullscreen = "G", dev_panel = "G", system_menu = "G",
  }
  for id, ctx in pairs(want) do
    assert(input.get_action(id).ctx == ctx, id .. " ctx " .. tostring(input.get_action(id).ctx))
  end
  local F = input.CTX_CONFLICTS.F
  assert(F and F.F and F.G, "F conflicts with F and G")
  for c, t in pairs(input.CTX_CONFLICTS) do
    if c ~= "F" and c ~= "G" then assert(not t.F, c .. " must not list F") end
  end
end

local function kbb(id, slot) return input.get_binding("keyboard", id, slot or 1) end
local function pdb(id, slot) return input.get_binding("pad", id, slot or 1) end

local function is_kb(b, key, shift, ctrl)
  return b and b.key == key and (b.shift or false) == (shift or false) and (b.ctrl or false) == (ctrl or false)
end

local function is_pad(b, btn, lt)
  return b and b.btn == btn and (b.lt or false) == (lt or false)
end

function T.new_defaults()
  input.reset_all()
  local digits = { K._1, K._2, K._3, K._4, K._5, K._6 }
  for i = 1, 6 do assert(is_kb(kbb("select_" .. i), digits[i]), "select_" .. i) end
  local quick = { K._7, K._8, K._9, K._0 }
  local qpad = { PB.dpad_up, PB.dpad_right, PB.dpad_down, PB.dpad_left }
  for i = 1, 4 do
    assert(is_kb(kbb("quick_" .. i), quick[i]), "quick_" .. i .. " key")
    assert(is_pad(pdb("quick_" .. i), qpad[i], true), "quick_" .. i .. " pad LT+D")
  end
  assert(is_kb(kbb("select_next"), K.TAB) and is_kb(kbb("select_prev"), K.TAB, true))
  assert(is_pad(pdb("select_next"), PB.rb) and is_pad(pdb("select_prev"), PB.lb))
  assert(is_kb(kbb("select_all"), K.A, false, true) and is_pad(pdb("select_all"), PB.lb))
  assert(is_kb(kbb("focus_next"), K.PERIOD) and is_kb(kbb("focus_prev"), K.COMMA))
  assert(is_pad(pdb("focus_next"), PB.rb) and is_pad(pdb("focus_prev"), PB.lb))
  assert(is_kb(kbb("cursor_click_l"), K.ENTER) and is_kb(kbb("cursor_click_r"), K.BACKSPACE))
  assert(is_pad(pdb("cursor_click_l"), PB.a) and is_pad(pdb("cursor_click_r"), PB.x))
  assert(is_pad(pdb("squad_follow"), PB.dpad_up) and is_pad(pdb("squad_hold"), PB.dpad_left))
  assert(is_pad(pdb("squad_lookout"), PB.dpad_right) and is_pad(pdb("squad_carry"), PB.dpad_down))
  assert(is_kb(kbb("screenshot"), K.F12) and is_kb(kbb("fullscreen"), K.F11) and is_kb(kbb("dev_panel"), K.F1))
  -- camera_pan: keyboard named slots = arrow keys, pad named slot rs = whole right stick
  local s = input.slot_ids("camera_pan", "keyboard")
  assert(#s == 4 and s[1] == "up" and s[2] == "left" and s[3] == "down" and s[4] == "right")
  assert(is_kb(kbb("camera_pan", "up"), K.UP) and is_kb(kbb("camera_pan", "left"), K.LEFT))
  assert(is_kb(kbb("camera_pan", "down"), K.DOWN) and is_kb(kbb("camera_pan", "right"), K.RIGHT))
  local rs = pdb("camera_pan", "rs")
  assert(rs and rs.axis == "rs" and rs.dir == nil)
  assert(input.label_key("camera_pan", "up") == "act.camera_pan.up")
end

function T.corrected_defaults_and_holds()
  input.reset_all()
  local function hold(id, dev) return cases_mod.is_hold(input, id, dev) end
  assert(is_kb(kbb("end_day"), K.E) and hold("end_day", "keyboard"))
  assert(is_pad(pdb("end_day"), PB.back) and hold("end_day", "pad"))
  assert(is_pad(pdb("intimidate"), PB.y) and hold("intimidate", "pad"))
  assert(is_pad(pdb("evacuate"), PB.b) and hold("evacuate", "pad"))
  assert(is_pad(pdb("camera_center"), PB.r3) and hold("camera_center", "pad"))
  assert(is_pad(pdb("system_menu"), PB.start) and hold("system_menu", "pad"))
  assert(hold("select_all", "pad") and not hold("select_all", "keyboard"))
  local pp, pn = pdb("ui_page_prev"), pdb("ui_page_next")
  assert(pp and pp.axis == "rs" and pp.dir == "up", "ui_page_prev = RS up")
  assert(pn and pn.axis == "rs" and pn.dir == "down", "ui_page_next = RS down")
  -- no other action is hold-type by default
  local allowed = { end_day = true, intimidate = true, evacuate = true, camera_center = true, system_menu = true,
    select_all = true }
  for _, a in ipairs(input.ACTIONS) do
    if a.hold and (a.hold.keyboard or a.hold.pad or a.hold.mouse) then
      assert(allowed[a.id], "unexpected hold action " .. a.id)
    end
  end
  assert(input.HOLD_S == 0.5, "HOLD_S default")
end

function T.dev_keys_moved_off_gameplay_keys()
  input.reset_all()
  -- P0-PLAN §9.4: F5 is the engine's hot-reload key, so dev.* use F2 F3 F4 F6 F7 F8
  local want = { K.F2, K.F3, K.F4, K.F6, K.F7, K.F8 }
  for i, id in ipairs(cases_mod.DEV_IDS) do
    assert(is_kb(kbb(id), want[i]), id)
    assert(input.get_action(id).rebindable == false)
  end
  assert(input.is_reserved_binding("keyboard", { key = K.F5 }), "F5 reserved (hot reload)")
  for _, k in ipairs({ K.F1, K.F11, K.F12, K.ESCAPE }) do
    assert(input.is_reserved_binding("keyboard", { key = k }))
  end
end

function T.validate_passes()
  input.reset_all()
  local ok, id, dev = input.validate()
  assert(ok, "validate: " .. tostring(id) .. "/" .. tostring(dev))
end

function T.no_default_conflicts_outside_whitelist()
  input.reset_all()
  assert(type(input.SHARED_DEFAULTS) == "table" and #input.SHARED_DEFAULTS > 0)
  local bad = {}
  for _, a in ipairs(input.ACTIONS) do
    for _, dev in ipairs(cases_mod.DEVICES) do
      for _, slot in ipairs(input.slot_ids(a.id, dev)) do
        local b = input.get_binding(dev, a.id, slot)
        if b then
          for _, c in ipairs(input.find_conflicts(dev, a.id, b)) do
            if not cases_mod.shared(input, dev, a.id, c.action_id) then
              bad[#bad + 1] = dev .. ":" .. a.id .. "<->" .. c.action_id
            end
          end
        end
      end
    end
  end
  assert(#bad == 0, "default conflicts: " .. table.concat(bad, ", "))
end

function T.whitelist_is_exact()
  -- UI-UX §7.1 intended multi-use (P0-PLAN §3.3 item 5) + mouse right = cancel/ui_secondary (§9.4)
  local want = {
    { "pad", { "select", "interact" } },
    { "pad", { "context", "attack" } },
    { "pad", { "select_next", "focus_next" } },
    { "pad", { "select_prev", "focus_prev" } },
    { "mouse", { "interact", "context", "move_to" } },
    { "mouse", { "cancel", "ui_secondary" } },
    { "keyboard", { "cancel", "system_menu" } },
  }
  assert(#input.SHARED_DEFAULTS == #want, "SHARED_DEFAULTS size " .. #input.SHARED_DEFAULTS)
  for _, w in ipairs(want) do
    for i = 1, #w[2] do
      for j = i + 1, #w[2] do
        assert(cases_mod.shared(input, w[1], w[2][i], w[2][j]), w[1] .. " " .. w[2][i] .. "/" .. w[2][j])
      end
    end
  end
  -- the hold property separates a pair: LB short (select_prev) vs LB hold (select_all) is not a conflict
  input.reset_all()
  for _, c in ipairs(input.find_conflicts("pad", "select_all", { btn = PB.lb })) do
    assert(c.action_id ~= "select_prev" and c.action_id ~= "focus_prev", "hold vs short must not conflict")
  end
end

-- ---------------------------------------------------------------- runtime (fake devices)

function T.every_default_binding_fires_correctly()
  with_fake(function()
    input.set_dev(true)
    local list = cases_mod.cases(input)
    assert(#list > 80, "too few cases " .. #list)
    local errs = {}
    for _, case in ipairs(list) do
      local hold_time = case.hold and (input.HOLD_S + 0.1) or 0.1
      local fired = run_case(case, hold_time)
      local e = cases_mod.judge(input, case, fired, input.HOLD_S, DT)
      if e then errs[#errs + 1] = case.device .. ":" .. case.id .. ": " .. e end
    end
    assert(#errs == 0, table.concat(errs, "\n"))
  end)
end

function T.hold_actions_do_not_fire_on_short_tap()
  with_fake(function()
    for _, case in ipairs(cases_mod.cases(input)) do
      if case.hold then
        local fired = run_case(case, 0.1)
        assert(not fired[case.id], case.device .. ":" .. case.id .. " fired on a short tap")
      end
    end
  end)
end

function T.paired_short_fires_on_release_and_not_after_hold()
  with_fake(function()
    -- pad Back: open_wheel (short, W) / end_day (hold, H)
    local tap = run_case({ device = "pad", b = { btn = PB.back } }, 0.1)
    assert(tap.open_wheel and tap.open_wheel.at_release and not tap.end_day)
    local long = run_case({ device = "pad", b = { btn = PB.back } }, input.HOLD_S + 0.1)
    assert(long.end_day and long.end_day.count == 1 and not long.open_wheel)
    -- pad Start: pause (short, W) / system_menu (hold, G)
    tap = run_case({ device = "pad", b = { btn = PB.start } }, 0.1)
    assert(tap.pause and tap.pause.at_release and not tap.system_menu)
    -- unpaired short is unchanged (M2 behaviour): keyboard F = interact fires on the press frame
    local f = run_case({ device = "keyboard", b = { key = K.F } }, 0.3)
    assert(f.interact and f.interact.first == 0 and f.interact.count == 1)
  end)
end

function T.hold_threshold_follows_setting()
  with_fake(function()
    input.set_hold_s(1.0)
    assert(input.HOLD_S == 1.0)
    local f = run_case({ device = "keyboard", b = { key = K.E } }, 0.7)
    assert(not f.end_day, "0.7 s < 1.0 s threshold")
    f = run_case({ device = "keyboard", b = { key = K.E } }, 1.1)
    assert(f.end_day and f.end_day.first >= 1.0 - 1e-6)
    input.set_hold_s(0.5)
  end)
end

function T.lt_combo_excludes_plain_dpad()
  with_fake(function()
    local f = run_case({ device = "pad", b = { btn = PB.dpad_up, lt = true } }, 0.1)
    assert(f.quick_1, "LT+D-up = quick_1")
    assert(not f.squad_follow, "D-up direct command only when LT is not held")
    f = run_case({ device = "pad", b = { btn = PB.dpad_up } }, 0.1)
    assert(f.squad_follow and not f.quick_1)
  end)
end

function T.stick_direction_edge_and_repeat()
  with_fake(function()
    local f = run_case({ device = "pad", b = { axis = "rs", dir = "up" } }, 0.1)
    assert(f.ui_page_prev and f.ui_page_prev.count == 1 and not f.ui_page_next)
    f = run_case({ device = "pad", b = { axis = "rs", dir = "up" } }, 1.0)
    assert(f.ui_page_prev and f.ui_page_prev.count >= 3, "repeat while held")
    -- below threshold: nothing
    for _ = 1, 3 do frame() end
    cur.axis[PA.ry] = -0.4
    local any = false
    for _ = 1, 30 do for _, id in ipairs(frame()) do any = any or id == "ui_page_prev" end end
    cur.axis[PA.ry] = 0
    assert(not any, "0.4 is below the 0.5 threshold")
  end)
end

function T.dev_panel_only_in_dev_mode()
  with_fake(function()
    input.set_dev(false)
    local f = run_case({ device = "keyboard", b = { key = K.F1 } }, 0.1)
    assert(not f.dev_panel)
    input.set_dev(true)
    f = run_case({ device = "keyboard", b = { key = K.F1 } }, 0.1)
    assert(f.dev_panel)
  end)
end

function T.pan_vec()
  with_fake(function()
    frame()
    local x, y = input.pan_vec()
    assert(x == 0 and y == 0)
    cur.key[K.UP] = true
    cur.key[K.RIGHT] = true
    frame()
    x, y = input.pan_vec()
    assert(x > 0 and y < 0 and math.abs(x * x + y * y - 1) < 1e-6, "unit diagonal")
    cur.key[K.UP], cur.key[K.RIGHT] = nil, nil
    cur.axis[PA.rx] = -0.8
    frame()
    x, y = input.pan_vec()
    assert(x < -0.5 and math.abs(y) < 1e-6, "right stick pans")
    cur.axis[PA.rx] = 0
    -- move_vec is not affected by the arrow keys
    cur.key[K.UP] = true
    frame()
    local mx, my = input.move_vec()
    assert(mx == 0 and my == 0, "arrows pan the camera, not the character")
  end)
end

-- ---------------------------------------------------------------- rebinding keeps hold, save format unchanged

function T.rebind_keeps_hold_and_export_format()
  input.reset_all()
  assert(input.set_binding("pad", "end_day", 1, { btn = PB.y }) or true)
  assert(cases_mod.is_hold(input, "end_day", "pad"), "hold belongs to the action")
  local ex = input.export_bindings()
  for _, dev in ipairs(cases_mod.DEVICES) do
    for id, slots in pairs(ex[dev] or {}) do
      for _, b in pairs(slots) do
        assert(b.hold == nil, "hold must not be stored in settings: " .. dev .. ":" .. id)
      end
    end
  end
  input.reset_all()
end

-- ---------------------------------------------------------------- text

function T.i18n_keys_exist()
  i18n.init("zh")
  local missing = {}
  local keys_needed = { "rebind.hold" }
  for _, id in ipairs(cases_mod.SPEC_IDS) do keys_needed[#keys_needed + 1] = "act." .. id end
  for _, s in ipairs({ "up", "left", "down", "right" }) do keys_needed[#keys_needed + 1] = "act.camera_pan." .. s end
  for _, lang in ipairs({ "zh", "en", "ko" }) do
    local t = i18n.tables[lang]
    for _, k in ipairs(keys_needed) do
      if t[k] == nil then missing[#missing + 1] = lang .. ":" .. k end
    end
  end
  assert(#missing == 0, "missing i18n: " .. table.concat(missing, ", "))
  assert(i18n.tables.zh["rebind.hold"]:find("{key}", 1, true), "rebind.hold has {key}")
end

return T
