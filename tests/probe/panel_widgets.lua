-- PANEL widget probe: controls, focus audit, modal capture, hint presets.
local probe = require("kit_probe")
local i18n = require("core.i18n")
local scene = require("core.scene")
local theme = require("ui.theme")
local focus = require("ui.focus")
local widgets = require("ui.widgets")
local hintbar = require("ui.hintbar")
local glyphs = require("ui.glyphs")

probe.timeout(90)

local now = 0
local function wait(sec)
  local untl = now + sec
  while now < untl do coroutine.yield() end
end

local Ctx = {
  show_modal = false,
  show_confirm = false,
  show_radial = false,
  step_val = 5,
  radial_result = nil,
  confirm_result = nil,
  list_cur = 2,
  grid_events = {},
  panel_cancel = 0,
  dis_changes = 0,
  queue = { q1 = false, q2 = false, q3 = false, qr = false },
  queue_done = {},     -- order in which the queue requests delivered a result
  fire = { confirm = 0, radial = 0 },
  rep_confirm = false,
  rep_radial = false,
}

function Ctx:on_enter()
  focus.push_group("panel_test", { default = "probe_icon",
    on_cancel = function() Ctx.panel_cancel = Ctx.panel_cancel + 1 end })
end

function Ctx:on_exit()
  focus.pop_group()
end

function Ctx:update(_dt) end

function Ctx:draw()
  focus.set_target("panel_test")
  local sw, sh = ui.screen_size()
  theme.set_color(theme.colors.bg, 1)
  ui.rect(0, 0, sw, sh)

  widgets.icon_button("probe_icon", { x = 24, y = 24, w = 48, h = 48 }, "pad:a", {
    on_click = function() end,
    tooltip = { title = i18n.t("ui.demo.inventory"), body = i18n.t("ui.demo.action_carry") },
    force_tooltip = true,
  })
  widgets.icon_button("probe_icon2", { x = 80, y = 24, w = 48, h = 48 }, "key:I", {
    on_click = function() end, badge = "2",
  })
  widgets.icon_button("probe_icon3", { x = 136, y = 24, w = 48, h = 48 }, "mouse:right", {
    on_click = function() end, tooltip = { title = "T3", body = "B3" },
  })

  local items = {}
  for i = 1, 12 do
    items[i] = { label = i18n.t("ui.demo.action_craft") .. " " .. i, sub = tostring(i) }
  end
  Ctx.list_cur = widgets.list("probe_list", { x = 24, y = 100, w = 360, h = 160 }, items, 2, { header = "H" })

  local gitems = {}
  for i = 1, 8 do
    gitems[i] = { label = i18n.t("ui.demo.item_scrap"), qty = i, icon = "pad:a" }
  end
  local _, gev = widgets.item_grid("probe_grid", { x = 420, y = 100 }, 4, 2, gitems, 1, {})
  if gev then Ctx.grid_events[#Ctx.grid_events + 1] = gev end

  widgets.progress_bar({ x = 24, y = 290, w = 240, h = 14 }, 50, 100, { show_percent = true })
  widgets.progress_bar({ x = 24, y = 310, w = 240, h = 14 }, 100, 100, { segments = 5 })

  local nv, nchanged = widgets.stepper("probe_step", { x = 24, y = 350, w = 300, h = 40 }, Ctx.step_val, 0, 10, 1, {
    on_change = function(v) Ctx.step_val = v end,
  })
  if nchanged then Ctx.step_val = nv end
  widgets.stepper("probe_step_dis", { x = 24, y = 400, w = 300, h = 40 }, 5, 0, 10, 1, {
    enabled = false, on_change = function() Ctx.dis_changes = Ctx.dis_changes + 1 end,
  })

  focus.clear_target()

  -- Queue / stale-result scenarios (each id is a separate request).
  for _, qid in ipairs({ "q1", "q2", "q3" }) do
    if Ctx.queue[qid] then
      local r = widgets.modal(qid, { title = qid, body = "queued " .. qid })
      if r then Ctx.queue[qid] = false; Ctx.queue_done[#Ctx.queue_done + 1] = qid end
    end
  end
  if Ctx.queue.qr then
    local r = widgets.radial("qr", { items = { { id = "a", label = "A" }, { id = "b", label = "B" } } })
    if r then Ctx.queue.qr = false; Ctx.queue_done[#Ctx.queue_done + 1] = "qr" end
  end
  if Ctx.rep_confirm then
    local r = widgets.confirm("rep_confirm", { title = "C", body = "x" })
    if r then Ctx.fire.confirm = Ctx.fire.confirm + 1; Ctx.rep_confirm = false end
  end
  if Ctx.rep_radial then
    local r = widgets.radial("rep_radial", { items = { { id = "a", label = "A" }, { id = "b", label = "B" } } })
    if r then Ctx.fire.radial = Ctx.fire.radial + 1; Ctx.rep_radial = false end
  end

  if Ctx.show_modal then
    local r = widgets.modal("probe_modal", {
      title = i18n.t("ui.demo.modal"),
      body = i18n.t("ui.demo.body_modal"),
      buttons = {
        { id = "cancel", label = i18n.t("ui.cancel"), default = true },
        { id = "ok", label = i18n.t("ui.ok"), variant = "primary" },
      },
    })
    if r then Ctx.show_modal = false end
  elseif Ctx.show_confirm then
    local r = widgets.confirm("probe_confirm", {
      title = i18n.t("ui.demo.confirm"),
      body = i18n.t("ui.demo.body_confirm"),
      danger = true,
    })
    if r then Ctx.confirm_result = r; Ctx.show_confirm = false end
  elseif Ctx.show_radial then
    local r = widgets.radial("probe_radial", {
      items = {
        { id = "a", label = "A", icon = "pad:a" },
        { id = "b", label = "B", icon = "pad:b" },
        { id = "c", label = "C", icon = "pad:x" },
        { id = "d", label = "D", icon = "pad:y" },
      },
    })
    if r then Ctx.radial_result = r; Ctx.show_radial = false end
  end
end

local function scenario()
  wait(0.2)
  probe.check("script healthy", probe.script_ok())
  probe.check("widgets drawn", ui.quad_count() > 0)
  probe.check("panel focus.audit().ok", focus.audit().ok)
  probe.check("quad budget (widget demo < 3000)", ui.quad_count() < 3000)

  scene.push(Ctx)
  wait(0.25)
  probe.check("demo scene focus.audit().ok", focus.audit().ok)

  -- Stepper: right arrow increments, Home resets, Shift+right adds 10.
  local g = focus.groups[#focus.groups]
  focus.current = "probe_step"; g.remember = "probe_step"; focus.visible = true
  probe.tap(keys.RIGHT)
  wait(0.12)
  probe.check("stepper +1", Ctx.step_val == 6)
  probe.key(keys.LEFT_SHIFT, true)
  probe.tap(keys.RIGHT)
  wait(0.12)
  probe.key(keys.LEFT_SHIFT, false)
  probe.check("stepper Shift+right -> max clamp", Ctx.step_val == 10)
  probe.tap(keys.END)
  wait(0.12)
  probe.check("stepper End -> max", Ctx.step_val == 10)
  probe.tap(keys.HOME)
  wait(0.12)
  probe.check("stepper Home -> min", Ctx.step_val == 0)
  probe.tap(keys.LEFT)
  wait(0.12)
  probe.check("stepper clamps at min", Ctx.step_val == 0)

  -- List: focus an off-screen row, the list must scroll to reveal it.
  focus.current = "probe_list#row12"; g.remember = "probe_list#row12"
  wait(0.2)
  local lst = widgets._lists["probe_list"]
  probe.check("list scrolled to off-screen row", lst and lst.scroll > 0)
  probe.check("list focus.audit().ok", focus.audit().ok)

  -- Hint presets: eight contexts, each <= 7 (one may be conditional), first item sane.
  local names = { "home_idle", "home_focus", "raid", "combat", "menu", "dialog", "drag", "cursor" }
  local all_ok = true
  for _, name in ipairs(names) do
    local p = hintbar.preset(name)
    if #p == 0 or #p > 7 then all_ok = false end
    for _, it in ipairs(p) do
      if not it.action or not it.text then all_ok = false end
    end
  end
  probe.check("hintbar 8 contexts valid", all_ok)
  probe.check("hintbar raid has move+sneak", hintbar.preset("raid")[1].action == "move_dir"
    and hintbar.preset("raid")[2].action == "sneak_toggle")

  -- Modal: group capture, default focus, Esc closes and restores layer.
  local groups_before = #focus.groups
  Ctx.show_modal = true
  wait(0.3)
  probe.check("modal open", widgets.any_modal_open() and widgets.modal_is_open("probe_modal"))
  probe.check("modal pushed focus group", #focus.groups == groups_before + 1)
  probe.check("modal default focus is cancel", focus.current == "probe_modal#btn#cancel")
  probe.tap(keys.ESCAPE)
  wait(0.25)
  probe.check("modal closed by Esc", not widgets.any_modal_open())
  probe.check("modal restored focus group", #focus.groups == groups_before)
  probe.check("panel audit after modal", focus.audit().ok)

  -- Confirm: cancel is default; dangerous dialog cannot be dim-cancelled.
  Ctx.show_confirm = true
  wait(0.3)
  probe.check("confirm open", widgets.modal_is_open("probe_confirm"))
  probe.check("confirm default focus is cancel", focus.current == "probe_confirm#btn#cancel")
  probe.tap(keys.ESCAPE)
  wait(0.25)
  probe.check("confirm closed by Esc", Ctx.confirm_result == "cancel")

  -- Radial: 4 sectors, Enter selects the north (first) item.
  local many = {}
  for i = 1, 9 do many[i] = { id = tostring(i), label = tostring(i) } end
  local r9 = widgets.radial("probe_radial9", { items = many })
  probe.check("radial rejects >8 sectors", r9 and r9.action == "too_many")

  Ctx.show_radial = true
  wait(0.3)
  probe.check("radial open", widgets.radial_is_open("probe_radial"))
  probe.tap(keys.ENTER)
  wait(0.25)
  probe.check("radial selected first item", Ctx.radial_result and Ctx.radial_result.action == "select"
    and Ctx.radial_result.item_id == "a")

  -- Radial: sector hit-test matches the drawn layout (north = 1, clockwise,
  -- sector i centred on its icon) for 8 sectors, and also +-15 degrees around it.
  local ok8 = true
  for k = 1, 8 do
    for _, off in ipairs({ 0, -15, 15 }) do
      local th = math.rad((k - 1) * 45 + off)
      if widgets.radial_sector(math.sin(th), -math.cos(th), 8) ~= k then ok8 = false end
    end
  end
  probe.check("radial 8 sectors: north=1 clockwise, centred on icons", ok8)
  probe.check("radial 4 sectors: east=2 south=3 west=4",
    widgets.radial_sector(1, 0, 4) == 2 and widgets.radial_sector(0, 1, 4) == 3
    and widgets.radial_sector(-1, 0, 4) == 4)

  -- List: PageUp/PageDown/Home/End move the focused row and the viewport follows.
  local function setfocus(id)
    local gg = focus.groups[#focus.groups]
    focus.current = id; gg.remember = id; focus.visible = true
  end
  local function key(k) probe.tap(k); wait(0.12) end
  local function in_view(i)
    local l = widgets._lists["probe_list"]
    return i > l.scroll and i <= l.scroll + 3
  end
  setfocus("probe_list#row1"); wait(0.1)
  key(keys.PAGE_DOWN)
  probe.check("list PageDown focuses row 4", focus.current == "probe_list#row4" and Ctx.list_cur == 4)
  probe.check("list PageDown row stays visible", in_view(4))
  key(keys.END)
  probe.check("list End focuses last row", focus.current == "probe_list#row12" and Ctx.list_cur == 12)
  probe.check("list End row visible", in_view(12))
  key(keys.PAGE_UP)
  probe.check("list PageUp focuses row 9", focus.current == "probe_list#row9" and Ctx.list_cur == 9)
  key(keys.HOME)
  probe.check("list Home focuses row 1", focus.current == "probe_list#row1" and Ctx.list_cur == 1 and in_view(1))
  probe.check("empty list returns nil selection", (widgets.list("probe_empty", { x = 0, y = 0, w = 100, h = 80 }, {}, 1, {})) == nil)

  -- Disabled stepper: focusable, but arrows do not edit it.
  setfocus("probe_step_dis"); wait(0.1)
  key(keys.RIGHT)
  key(keys.END)
  probe.check("disabled stepper does not change", Ctx.dis_changes == 0)

  -- ItemGrid: keyboard pick/move deliver events; cancel is consumed, not forwarded.
  Ctx.grid_events = {}
  setfocus("probe_grid#cell1"); wait(0.1)
  key(keys.ENTER)
  local gst = widgets._grids["probe_grid"]
  probe.check("grid Enter picks up + delivers select event", gst.held == 1
    and Ctx.grid_events[1] and Ctx.grid_events[1].kind == "select")
  Ctx.panel_cancel = 0
  key(keys.ESCAPE)
  local last = Ctx.grid_events[#Ctx.grid_events]
  probe.check("grid Esc while holding cancels", gst.held == nil and last and last.kind == "cancel")
  probe.check("grid Esc while holding is not forwarded to the panel", Ctx.panel_cancel == 0)
  key(keys.ESCAPE)
  probe.check("Esc without a held item reaches the panel", Ctx.panel_cancel == 1)
  Ctx.grid_events = {}
  key(keys.ENTER)
  key(keys.RIGHT)
  key(keys.ENTER)
  local mv = Ctx.grid_events[#Ctx.grid_events]
  probe.check("grid keyboard move event delivered", mv and mv.kind == "move" and mv.from == 1 and mv.to == 2)
  -- Mouse: pick up, right click cancels (no transfer).
  Ctx.grid_events = {}
  probe.mouse_move(420 + 24, 100 + 24)
  wait(0.1)
  probe.click(0)
  wait(0.15)
  probe.check("grid mouse click picks up", gst.held == 1)
  probe.click(1)
  wait(0.15)
  local kinds = {}
  for _, e in ipairs(Ctx.grid_events) do kinds[#kinds + 1] = e.kind end
  local kj = table.concat(kinds, ",")
  probe.check("grid right click while holding cancels without transfer",
    gst.held == nil and kj:find("cancel") and not kj:find("transfer"))
  probe.mouse_move(900, 650)
  wait(0.1)

  -- ui_info (H) pins the focused element's tooltip until dismissed.
  setfocus("probe_icon3"); wait(0.1)
  probe.check("no tooltip before H (focus delay not reached)", widgets._tt_drawn_id ~= "probe_icon3#tip")
  key(keys.H)
  probe.check("H shows the focused tooltip immediately", widgets._tt_drawn_id == "probe_icon3#tip")
  wait(0.8)
  probe.check("H tooltip stays", widgets._tt_drawn_id == "probe_icon3#tip" and widgets._info_owner == "probe_icon3")
  key(keys.H)
  probe.check("H again dismisses", widgets._info_owner == nil)
  setfocus("probe_icon"); wait(0.1)

  -- Glyph names (PANEL-PLAN §3).
  local gl = glyphs.spec
  probe.check("glyph mouse:left/right/middle -> 0/1/2",
    gl("mouse:left").btn == 0 and gl("mouse:right").btn == 1 and gl("mouse:middle").btn == 2)
  probe.check("glyph mouse:move / mouse:drag", gl("mouse:move").mode == "move" and gl("mouse:drag").mode == "drag"
    and gl("mouse:drag").btn == 0)
  probe.check("glyph key:/pad: parse", gl("key:ESCAPE").kind == "key" and gl("pad:rb").kind == "pad_rb")
  probe.check("hintbar item glyph mouse:right parses", hintbar.resolve({ glyph = "mouse:right" }, "keyboard").btn == 1)

  -- Hint bar: icon types per device (menu preset), no duplicate keyboard glyph in mouse mode.
  hintbar.push("menu")
  local function kinds_for(dev)
    local lay = hintbar.layout({ device = dev })
    local out = {}
    for _, it in ipairs(lay.items) do out[#out + 1] = it.glyph and it.glyph.kind or "none" end
    return out, lay
  end
  local kb = kinds_for("keyboard")
  probe.check("hint icons keyboard = key caps", #kb == 4 and kb[1] == "key" and kb[2] == "key" and kb[3] == "key" and kb[4] == "key")
  local pd = kinds_for("pad")
  -- P0-3 (P0-PLAN §3.3): ui_page_next moved from RB to RS-down; stick-direction bindings show a stick glyph
  local _, pd_lay = kinds_for("pad")
  local g3 = pd_lay.items[3] and pd_lay.items[3].glyph
  probe.check("hint icons pad = a, b, rs(down), y", pd[1] == "pad_a" and pd[2] == "pad_b" and pd[3] == "pad_rs"
    and g3 and g3.dir == "down" and pd[4] == "pad_y")
  local ms, mlay = kinds_for("mouse")
  probe.check("hint icons mouse = left, right, then keyboard fallback", ms[1] == "mouse" and ms[2] == "mouse"
    and mlay.items[1].glyph.btn == 0 and mlay.items[2].glyph.btn == 1 and ms[3] == "key" and ms[4] == "key")
  local dup = false
  for _, name in ipairs({ "home_idle", "home_focus", "raid", "combat", "menu", "dialog", "drag", "cursor" }) do
    hintbar.clear()
    hintbar.push(name)
    local lay = hintbar.layout({ device = "mouse" })
    for _, it in ipairs(lay.items) do
      if it.hotkey and it.glyph and it.glyph.kind == "key" then dup = true end
    end
  end
  probe.check("hint bar mouse mode never draws the keyboard glyph twice", not dup)
  hintbar.clear()
  hintbar.push("raid")
  local rk = hintbar.layout({ device = "keyboard" })
  probe.check("hint bar raid: <= 6 items, sneak/run share one entry", #rk.items <= 6 and #hintbar.preset("raid") <= 6)
  local seq = {}
  for _, it in ipairs(rk.items) do seq[#seq + 1] = it.it.action end
  probe.check("hint bar raid order", seq[1] == "move_dir" and seq[2] == "sneak_toggle" and seq[3] == "interact")
  hintbar.clear()
  hintbar.push("raid")
  local many = {}
  for i = 1, 8 do many[i] = { action = "confirm", text = "hint.confirm" } end
  hintbar.push("x", many)
  local capped = hintbar.layout({ device = "keyboard" })
  probe.check("hint bar caps at 6 items and flags overflow", #capped.items == 6 and capped.overflow)
  hintbar.pop()
  hintbar.clear()

  -- Modal / radial: a result returned on the draw path is not delivered again.
  Ctx.rep_confirm = true
  wait(0.3)
  setfocus("rep_confirm#btn#confirm")
  focus.current = "rep_confirm#btn#cancel"
  key(keys.ENTER)
  wait(0.2)
  probe.check("confirm result delivered once", Ctx.fire.confirm == 1 and not widgets.modal_is_open("rep_confirm"))
  Ctx.rep_confirm = true
  wait(0.3)
  probe.check("reopened confirm waits for input (no stale result)", Ctx.fire.confirm == 1 and widgets.modal_is_open("rep_confirm"))
  key(keys.ESCAPE)
  wait(0.2)
  probe.check("Esc path delivers the cancel result once", Ctx.fire.confirm == 2 and not widgets.modal_is_open("rep_confirm"))
  wait(0.3)
  probe.check("cancel result is not repeated", Ctx.fire.confirm == 2)
  Ctx.rep_radial = true
  wait(0.3)
  key(keys.ENTER)
  wait(0.2)
  probe.check("radial result delivered once", Ctx.fire.radial == 1 and not widgets.radial_is_open("rep_radial"))
  Ctx.rep_radial = true
  wait(0.3)
  probe.check("reopened radial waits for input (no stale result)", Ctx.fire.radial == 1 and widgets.radial_is_open("rep_radial"))
  key(keys.ESCAPE)
  wait(0.2)
  probe.check("radial Esc delivers cancel once", Ctx.fire.radial == 2 and not widgets.radial_is_open("rep_radial"))

  -- Modal queue (FIFO), shared with the radial.
  Ctx.queue_done = {}
  Ctx.queue.q1, Ctx.queue.q2, Ctx.queue.q3, Ctx.queue.qr = true, true, true, true
  wait(0.3)
  probe.check("queue: first request opens, the rest wait",
    widgets.modal_is_open("q1") and not widgets.modal_is_open("q2")
    and not widgets.modal_is_open("q3") and not widgets.radial_is_open("qr"))
  probe.check("queue holds the 3 waiting requests", #widgets._queue == 3)
  key(keys.ENTER)
  wait(0.2)
  probe.check("queue: q2 opens after q1 closes", widgets.modal_is_open("q2") and not widgets.modal_is_open("q1"))
  key(keys.ENTER)
  wait(0.2)
  probe.check("queue: q3 opens after q2 closes", widgets.modal_is_open("q3"))
  key(keys.ENTER)
  wait(0.2)
  probe.check("queue: radial opens last", widgets.radial_is_open("qr"))
  key(keys.ENTER)
  wait(0.2)
  probe.check("queue results in FIFO order", table.concat(Ctx.queue_done, ",") == "q1,q2,q3,qr")
  probe.check("queue drained, no overlay left", not widgets.any_modal_open() and not widgets.radial_is_open("qr")
    and #widgets._queue == 0)
  probe.check("panel audit after queue", focus.audit().ok)

  -- Three languages x standard/large text: quad budget, audit, hint bar fit, text fit.
  local orig_lang = i18n.get_lang()
  local sw, sh = ui.screen_size()
  for _, lang in ipairs({ "zh", "en", "ko" }) do
    for _, large in ipairs({ false, true }) do
      local tag = lang .. (large and "/large" or "/normal")
      i18n.set_lang(lang)
      theme.large_text = large
      Ctx.show_confirm = true
      wait(0.3)
      probe.check("[" .. tag .. "] quad budget with modal open", ui.quad_count() < (large and 4000 or 3000))
      probe.check("[" .. tag .. "] confirm opened", widgets.modal_is_open("probe_confirm"))
      -- modal chrome fits the screen
      local fs = theme.font("s")
      local ft = theme.font("t")
      local body_h = ui.text_measure(fs, i18n.t("ui.demo.body_confirm"), 520 - 48).h
      local need = 24 + ui.font_line_height(ft) + 12 + body_h + 20 + 40 + 24
      probe.check("[" .. tag .. "] confirm body fits modal", need <= sh - 64)
      probe.check("[" .. tag .. "] title fits modal width",
        ui.text_width(ft, i18n.t("ui.demo.confirm")) <= 520 - 48)
      probe.tap(keys.ESCAPE)
      wait(0.25)
      Ctx.confirm_result = nil
      -- hint bar: every preset fits on every device without dropping items
      local fits = true
      local widest = 0
      for _, name in ipairs({ "home_idle", "home_focus", "raid", "combat", "menu", "dialog", "drag", "cursor" }) do
        for _, dev in ipairs({ "keyboard", "mouse", "pad" }) do
          hintbar.clear()
          hintbar.push(name)
          local lay = hintbar.layout({ device = dev })
          widest = math.max(widest, lay.total)
          if lay.overflow or lay.total > sw - 20 then fits = false end
        end
      end
      hintbar.clear()
      probe.check("[" .. tag .. "] every hint preset fits the bar (widest " .. math.floor(widest) .. ")", fits)
      -- ellipsis never exceeds its box
      local fb = theme.font("b")
      local longest = i18n.t("ui.demo.body_modal") .. i18n.t("ui.demo.tip_body")
      probe.check("[" .. tag .. "] ellipsize respects width",
        ui.text_width(fb, widgets.ellipsize(fb, longest, 160)) <= 160)
      probe.check("[" .. tag .. "] focus.audit().ok", focus.audit().ok)
    end
  end
  i18n.set_lang(orig_lang)
  theme.large_text = false
  wait(0.2)

  scene.pop()
  wait(0.1)
  probe.finish()
end

local co = coroutine.create(scenario)

function _probe(t, dt)
  now = t
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then error(err, 0) end
end
