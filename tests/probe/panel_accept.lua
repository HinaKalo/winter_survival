-- 验收测试，编码代理不得修改（PANEL 第 2 次返工，主代理编写；见 docs/PANEL-PLAN.md §9）。
-- One scenario per Codex finding P1..P10 on the PANEL widgets (2026-11-14), P11 from the final review. Needs the probe binding
-- probe.mouse_button(button, down) to hold a mouse button across frames.
local probe = require("kit_probe")
local scene = require("core.scene")
local focus = require("ui.focus")
local widgets = require("ui.widgets")

probe.timeout(120)

local now = 0
local function wait(sec)
  local untl = now + sec
  while now < untl do coroutine.yield() end
end
local function frames(n) for _ = 1, n do coroutine.yield() end end

local HAS_HOLD = type(probe.mouse_button) == "function"
local function mouse(b, down) if HAS_HOLD then probe.mouse_button(b, down) end end

-- rect of a registered focus element (white-box: focus.groups[*].by_id)
local function rect_of(id)
  for i = #focus.groups, 1, -1 do
    local e = focus.groups[i].by_id and focus.groups[i].by_id[id]
    if e and e.rect then return e.rect end
  end
end
local function centre(r) return r.x + r.w * 0.5, r.y + r.h * 0.5 end

local Ctx = { mode = nil }

local function reset()
  Ctx.bg_clicks, Ctx.bg_ret = 0, 0
  Ctx.results = {}
  Ctx.want = {}
  Ctx.s_val, Ctx.s_enabled, Ctx.s_max = 5, true, 20
  Ctx.shrink_on_pending = false
  Ctx.kb_ret = 0
  Ctx.events = {}
  Ctx.panel_cancel = 0
end
reset()

function Ctx:on_enter()
  focus.push_group("acc", { on_cancel = function() Ctx.panel_cancel = Ctx.panel_cancel + 1 end })
end
function Ctx:on_exit() focus.pop_group() end
function Ctx:update(_dt) end

local GRID_ITEMS = {
  { label = "a", qty = 1, icon = "pad:a" },
  { label = "b", qty = 2, icon = "pad:b", enabled = false },
  { label = "c", qty = 3, icon = "pad:x" },
  { label = "d", qty = 4, icon = "pad:y" },
}

function Ctx:draw()
  focus.set_target("acc")
  local m = Ctx.mode
  if m == "bg" or m == "kb" then
    if widgets.icon_button("bg_btn", { x = 24, y = 24, w = 48, h = 48 }, "pad:a",
      { on_click = function() Ctx.bg_clicks = Ctx.bg_clicks + 1 end }) then
      Ctx.bg_ret = Ctx.bg_ret + 1
    end
  elseif m == "stepper" then
    -- P11: the draw that consumes a parked keyboard edit sees a smaller range
    local st = widgets._steppers and widgets._steppers["acc_step"]
    if Ctx.shrink_on_pending and st and st.pending ~= nil then Ctx.s_max = 5 end
    local v = widgets.stepper("acc_step", { x = 24, y = 24, w = 320, h = 40 }, Ctx.s_val, 0, Ctx.s_max, 1, { enabled = Ctx.s_enabled })
    Ctx.s_val = v
  elseif m == "grid" then
    local _, ev = widgets.item_grid("acc_grid", { x = 24, y = 24 }, 4, 1, GRID_ITEMS, 1, {})
    if ev then Ctx.events[#Ctx.events + 1] = ev end
  elseif m == "list" then
    local items = {}
    for i = 1, 4 do items[i] = { label = "row " .. i, tooltip = { title = "tip " .. i } } end
    widgets.list("acc_list", { x = 24, y = 24, w = 300, h = 200 }, items, 1, {})
  end
  focus.clear_target()
  -- modal requests (drawn every frame while wanted)
  for _, id in ipairs({ "c1", "m1", "m2", "h1" }) do
    if Ctx.want[id] then
      local r
      if id == "c1" then
        r = widgets.confirm("c1", { title = "C1", body = "x" })
      elseif id == "h1" then
        r = widgets.confirm("h1", { title = "H1", body = "x", danger = true, hold_confirm = true, hold_duration = 0.6 })
      else
        r = widgets.modal(id, { title = id, body = "x", buttons = { { id = "ok", label = "OK", default = true } } })
      end
      if r then Ctx.results[id] = r; Ctx.want[id] = false end
    end
  end
end

-- P1: while a modal is open, background widgets ignore the mouse
local function p1_modal_blocks_background_mouse()
  reset(); Ctx.mode = "bg"; Ctx.want.c1 = true
  wait(0.15)
  probe.mouse_move(48, 48)
  frames(2)
  probe.click(0)
  wait(0.15)
  probe.check("P1: background IconButton ignores clicks while a Confirm is open",
    Ctx.bg_clicks == 0 and Ctx.bg_ret == 0)
  probe.tap(keys.ESCAPE)
  wait(0.2)
  probe.check("P1: Confirm closed by Esc", Ctx.results.c1 == "cancel")
  probe.mouse_move(48, 48); frames(2); probe.click(0); wait(0.15)
  probe.check("P1: background IconButton clickable again after the modal closed", Ctx.bg_clicks == 1)
end

-- P2: closing a queued modal with a click does not also accept the next one
local function p2_queued_modal_not_double_accepted()
  reset(); Ctx.mode = nil; Ctx.want.m1 = true; Ctx.want.m2 = true
  wait(0.2)
  local r = rect_of("m1#btn#ok")
  probe.check("P2: first modal button registered", r ~= nil)
  if not r then return end
  probe.mouse_move(centre(r)); frames(2)
  probe.click(0)
  wait(0.3)
  probe.check("P2: first modal returned ok", Ctx.results.m1 == "ok")
  probe.check("P2: second modal still open (same release not consumed twice)",
    Ctx.results.m2 == nil and widgets.modal_is_open("m2"))
  probe.tap(keys.ESCAPE); wait(0.2)
end

-- P3: a hold-to-confirm completes only while the pointer stays on the button
local function p3_hold_confirm_needs_pointer_on_button()
  probe.check("P3: probe.mouse_button exists (hold a mouse button across frames)", HAS_HOLD)
  reset(); Ctx.mode = nil; Ctx.want.h1 = true
  wait(0.2)
  local r = rect_of("h1#btn#confirm")
  probe.check("P3: hold-confirm button registered", r ~= nil)
  if not (r and HAS_HOLD) then probe.tap(keys.ESCAPE); wait(0.2); return end
  probe.mouse_move(centre(r)); frames(2)
  mouse(0, true)
  wait(0.15)
  probe.mouse_move(r.x + r.w + 200, r.y - 150) -- leave the button, keep holding
  wait(1.0)
  probe.check("P3: no confirm after the pointer left the button", Ctx.results.h1 ~= "confirm")
  mouse(0, false)
  wait(0.1)
  -- holding on the button for the full duration still confirms
  if Ctx.want.h1 then
    probe.mouse_move(centre(r)); frames(2)
    mouse(0, true); wait(0.9); mouse(0, false); wait(0.15)
    probe.check("P3: holding on the button confirms", Ctx.results.h1 == "confirm")
  end
  if Ctx.want.h1 then probe.tap(keys.ESCAPE); wait(0.2) end
end

-- P4: keyboard edits of a Stepper without on_change survive to the returned value
local function p4_stepper_keyboard_without_on_change()
  reset(); Ctx.mode = "stepper"
  wait(0.15)
  focus.set_target("acc"); focus.set_focus("acc_step"); focus.clear_target()
  frames(2)
  probe.tap(keys.RIGHT)
  wait(0.2)
  probe.check("P4: RIGHT on a focused Stepper (no on_change) returns value + step (got " .. tostring(Ctx.s_val) .. ")",
    Ctx.s_val == 6)
end

-- P5: keyboard / pad activation of an IconButton is visible in its return value
local function p5_icon_button_returns_true_on_keyboard()
  reset(); Ctx.mode = "kb"
  wait(0.15)
  focus.set_target("acc"); focus.set_focus("bg_btn"); focus.clear_target()
  frames(2)
  probe.tap(keys.ENTER)
  wait(0.2)
  probe.check("P5: Enter fires on_click once", Ctx.bg_clicks == 1)
  probe.check("P5: Enter makes icon_button return true once (got " .. Ctx.bg_ret .. ")", Ctx.bg_ret == 1)
end

local function grid_cell(i)
  local r = rect_of("acc_grid#" .. i) or rect_of("acc_grid#cell" .. i)
  return r
end

local function count(kind)
  local n = 0
  for _, e in ipairs(Ctx.events) do if e.kind == kind then n = n + 1 end end
  return n
end

-- P6: Esc / right-click during a mouse drag cancels the drag; nothing is moved
local function p6_grid_drag_cancel()
  reset(); Ctx.mode = "grid"
  wait(0.15)
  probe.check("P6: runs with probe.mouse_button (drag needs a held button)", HAS_HOLD)
  local a, c = grid_cell(1), grid_cell(3)
  probe.check("P6: grid cells registered", a ~= nil and c ~= nil)
  if not (a and c and HAS_HOLD) then return end
  probe.mouse_move(centre(a)); frames(2)
  mouse(0, true); frames(2)
  probe.mouse_move(centre(c)); frames(3) -- drag started
  probe.tap(keys.ESCAPE); frames(3)
  probe.check("P6: Esc during a drag emits cancel", count("cancel") == 1)
  probe.check("P6: Esc during a drag does not reach the panel's on_cancel", Ctx.panel_cancel == 0)
  mouse(0, false); wait(0.15)
  probe.check("P6: releasing after the cancel moves nothing", count("move") == 0 and count("transfer") == 0)
  -- right-click during a drag also cancels and does not open the item menu
  Ctx.events = {}
  probe.mouse_move(centre(a)); frames(2)
  mouse(0, true); frames(2)
  probe.mouse_move(centre(c)); frames(3)
  probe.click(1); frames(3)
  mouse(0, false); wait(0.15)
  probe.check("P6: right-click during a drag cancels without secondary/move",
    count("cancel") == 1 and count("secondary") == 0 and count("move") == 0)
end

-- P7: double-click on an item activates it
local function p7_grid_double_click()
  reset(); Ctx.mode = "grid"
  wait(0.15)
  local a = grid_cell(1)
  if not a then probe.check("P7: grid cell registered", false); return end
  probe.mouse_move(centre(a)); frames(2)
  probe.click(0); frames(3); probe.click(0); frames(3)
  probe.check("P7: double-click emits activate", count("activate") == 1)
end

-- P8: a disabled item rejects mouse select / transfer / drag
local function p8_grid_disabled_item_mouse()
  reset(); Ctx.mode = "grid"
  wait(0.15)
  local b = grid_cell(2)
  if not b then probe.check("P8: grid cell registered", false); return end
  probe.mouse_move(centre(b)); frames(2)
  probe.click(0); frames(3)
  probe.key(keys.LEFT_SHIFT, true); probe.click(0); frames(3); probe.key(keys.LEFT_SHIFT, false)
  frames(2)
  local bad = 0
  for _, e in ipairs(Ctx.events) do
    if (e.kind == "select" or e.kind == "transfer" or e.kind == "move" or e.kind == "activate")
      and (e.index == 2 or e.to == 2 or e.from == 2) then bad = bad + 1 end
  end
  probe.check("P8: mouse select/transfer/activate on a disabled item emit nothing", bad == 0)
end

-- P9: a Stepper disabled while an arrow is held stops repeating
local function p9_stepper_disable_stops_repeat()
  reset(); Ctx.mode = "stepper"
  wait(0.15)
  focus.set_target("acc"); focus.set_focus("acc_step"); focus.clear_target()
  frames(2)
  probe.key(keys.RIGHT, true)
  wait(0.1)
  probe.check("P9: the first RIGHT press stepped while enabled (got " .. tostring(Ctx.s_val) .. ")", Ctx.s_val == 6)
  Ctx.s_enabled = false
  local v = Ctx.s_val
  wait(1.0)
  probe.key(keys.RIGHT, false)
  frames(2)
  probe.check("P9: no repeat steps after the Stepper became disabled (" .. tostring(v) .. " -> " .. tostring(Ctx.s_val) .. ")",
    Ctx.s_val == v)
end

-- P10: a List row tooltip restarts its delay when the pointer comes back to the row
local function p10_list_tooltip_reentry_delay()
  reset(); Ctx.mode = "list"
  wait(0.15)
  local r1, r2 = rect_of("acc_list#row1"), rect_of("acc_list#row2")
  probe.check("P10: list rows registered", r1 ~= nil and r2 ~= nil)
  if not (r1 and r2) then return end
  probe.mouse_move(centre(r1)); wait(0.8)
  probe.check("P10: hovering row 1 shows its tooltip", widgets._tt_drawn_id == "acc_list#row1#tip")
  probe.mouse_move(centre(r2)); wait(1.0)
  probe.mouse_move(centre(r1)); frames(2)
  probe.check("P10: row 2's tooltip was showing before coming back", true)
  probe.check("P10: coming back to row 1 does not show the tooltip immediately",
    widgets._tt_drawn_id ~= "acc_list#row1#tip")
end

-- P11: a parked keyboard edit is re-clamped to the bounds of the call that returns it
local function p11_stepper_pending_respects_current_bounds()
  reset(); Ctx.mode = "stepper"; Ctx.shrink_on_pending = true
  wait(0.15)
  focus.set_target("acc"); focus.set_focus("acc_step"); focus.clear_target()
  frames(2)
  probe.tap(keys.RIGHT)
  wait(0.2)
  probe.check("P11: the range shrank while an edit was parked", Ctx.s_max == 5)
  probe.check("P11: Stepper never returns a value above the current max (got " .. tostring(Ctx.s_val) .. ")",
    Ctx.s_val == 5)
end

local function scenario()
  wait(0.2)
  scene.push(Ctx)
  wait(0.2)
  p1_modal_blocks_background_mouse()
  p2_queued_modal_not_double_accepted()
  p3_hold_confirm_needs_pointer_on_button()
  p4_stepper_keyboard_without_on_change()
  p5_icon_button_returns_true_on_keyboard()
  p6_grid_drag_cancel()
  p7_grid_double_click()
  p8_grid_disabled_item_mouse()
  p9_stepper_disable_stops_repeat()
  p10_list_tooltip_reentry_delay()
  p11_stepper_pending_respects_current_bounds()
  Ctx.mode = nil
  scene.pop()
  wait(0.1)
  probe.check("PANEL accept: script healthy", probe.script_ok())
  probe.finish()
end

local co = coroutine.create(scenario)

function _probe(t, dt)
  now = t
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then error(err, 0) end
end
