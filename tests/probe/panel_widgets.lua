-- PANEL widget probe: controls, focus audit, modal capture, hint presets.
local probe = require("kit_probe")
local i18n = require("core.i18n")
local scene = require("core.scene")
local theme = require("ui.theme")
local focus = require("ui.focus")
local widgets = require("ui.widgets")
local hintbar = require("ui.hintbar")

probe.timeout(25)

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
}

function Ctx:on_enter()
  focus.push_group("panel_test", { default = "probe_icon" })
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

  local items = {}
  for i = 1, 12 do
    items[i] = { label = i18n.t("ui.demo.action_craft") .. " " .. i, sub = tostring(i) }
  end
  widgets.list("probe_list", { x = 24, y = 100, w = 360, h = 160 }, items, 2, { header = "H" })

  local gitems = {}
  for i = 1, 8 do
    gitems[i] = { label = i18n.t("ui.demo.item_scrap"), qty = i, icon = "pad:a" }
  end
  widgets.item_grid("probe_grid", { x = 420, y = 100 }, 4, 2, gitems, 1, {})

  widgets.progress_bar({ x = 24, y = 290, w = 240, h = 14 }, 50, 100, { show_percent = true })
  widgets.progress_bar({ x = 24, y = 310, w = 240, h = 14 }, 100, 100, { segments = 5 })

  local nv, nchanged = widgets.stepper("probe_step", { x = 24, y = 350, w = 300, h = 40 }, Ctx.step_val, 0, 10, 1, {
    on_change = function(v) Ctx.step_val = v end,
  })
  if nchanged then Ctx.step_val = nv end

  focus.clear_target()

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

  -- Large text mode must keep focus reachability and stay in budget.
  theme.large_text = true
  wait(0.25)
  probe.check("large text focus.audit().ok", focus.audit().ok)
  probe.check("large text quad budget", ui.quad_count() < 4000)
  theme.large_text = false

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
