-- PANEL widget demo / screenshot harness.
-- Run as the main script:
--   tools/shot.sh out.png --script assets/scripts/ui/panel_demo.lua --lang zh
-- Optional env:
--   PANEL_DEMO_VIEW=main|modal|confirm|radial
--   PANEL_DEMO_DEVICE=keyboard|mouse|pad
--   PANEL_DEMO_LARGE=1            (large text mode)
local iso = require("iso")
local i18n = require("core.i18n")
local input = require("core.input")
local save = require("core.save")
local theme = require("ui.theme")
local focus = require("ui.focus")
local widgets = require("ui.widgets")
local glyphs = require("ui.glyphs")
local hintbar = require("ui.hintbar")

local M = {
  view = os.getenv("PANEL_DEMO_VIEW") or "main",
  device = os.getenv("PANEL_DEMO_DEVICE") or "pad",
  list_sel = 2,
  grid_cur = 1,
  step_val = 5,
  t = 0,
}

local function read_lang()
  local ok, data = save.read("settings")
  if ok and type(data) == "table" and data.lang then return data.lang end
  return "zh"
end

local function list_items()
  return {
    { label = i18n.t("ui.demo.action_craft"), sub = "2×", icon = "pad:x" },
    { label = i18n.t("ui.demo.action_repair"), sub = "1×", icon = "pad:y" },
    { label = i18n.t("ui.demo.action_scavenge"), sub = "3×", icon = "pad:a" },
    { label = i18n.t("ui.demo.action_talk"), sub = "1×", icon = "pad:b" },
    { label = i18n.t("ui.demo.action_follow"), sub = "R", icon = "pad:lb" },
    { label = i18n.t("ui.demo.action_hold"), sub = "R", icon = "pad:rb" },
    { label = i18n.t("ui.demo.action_lookout"), sub = "R", icon = "pad:lt" },
    { label = i18n.t("ui.demo.action_carry"), sub = "R", icon = "pad:rt" },
    { label = i18n.t("ui.demo.action_craft") .. " x2", sub = "4×", icon = "pad:dpad_up" },
    { label = i18n.t("ui.demo.action_repair") .. " x2", sub = "1×", icon = "pad:start", enabled = false },
  }
end

local function grid_items()
  return {
    { label = i18n.t("ui.demo.item_scrap"), qty = 4, icon = "pad:a" },
    { label = i18n.t("ui.demo.item_wood"), qty = 2, icon = "pad:b", too_heavy = true },
    { label = i18n.t("ui.demo.item_water"), qty = 1, icon = "pad:x" },
    { label = i18n.t("ui.demo.item_food"), qty = 3, icon = "pad:y" },
    { label = i18n.t("ui.demo.item_scrap"), qty = 7, icon = "pad:lb" },
    { label = i18n.t("ui.demo.item_wood"), qty = 1, icon = "pad:rb" },
    { label = i18n.t("ui.demo.item_water"), qty = 2, icon = "pad:lt" },
    { label = i18n.t("ui.demo.item_food"), qty = 1, icon = "pad:rt" },
  }
end

local function draw_glyph_strip(x, y)
  local f = theme.font("s")
  widgets.label(f, i18n.t("ui.demo.hintbar"), x, y, 160, theme.colors.text_dim, 0)
  local cx = x + 0
  local cy = y + ui.font_line_height(f) + 4
  local specs = {
    glyphs.key("W"), glyphs.key("ENTER"), glyphs.key("ESCAPE"), glyphs.key("TAB"),
    glyphs.mouse("left"), glyphs.mouse("right"), glyphs.mouse("middle"),
    glyphs.mouse("move"), glyphs.mouse("drag"),
    glyphs.pad("a"), glyphs.pad("b"), glyphs.pad("x"), glyphs.pad("y"),
    glyphs.pad("lb"), glyphs.pad("rb"), glyphs.pad("lt"), glyphs.pad("rt"),
    glyphs.pad("dpad_up"), glyphs.pad("dpad_left"), glyphs.pad("l3"), glyphs.pad("r3"),
    glyphs.pad("start"), glyphs.pad("back"),
  }
  for _, spec in ipairs(specs) do
    local w, h = glyphs.measure(spec, 22)
    glyphs.draw(spec, cx, cy, 22)
    cx = cx + w + 8
  end
  return cy + 26
end

function _init()
  i18n.init(read_lang())
  input.init()
  theme.init()
  local large = os.getenv("PANEL_DEMO_LARGE")
  if large and large ~= "" and large ~= "0" then theme.large_text = true end
  theme.apply_scale()
  hintbar.set_device_override(M.device)
  hintbar.push("raid")
  focus.push_group("panel_demo", { default = "demo_icon_a" })
end

function _update(dt)
  M.t = M.t + dt
  theme.update(dt)
  widgets.update_toast(dt)
  focus.update(dt)
end

function _draw()
  focus.begin_frame()
  local sw, sh = ui.screen_size()

  theme.set_color(theme.colors.bg, 1)
  ui.rect(0, 0, sw, sh)
  local lab = ui.font_line_height(theme.font("s")) + 4 -- label height; layout scales with large text
  local title_h = ui.font_line_height(theme.font("t"))
  local strip_y = 10 + title_h + 2
  theme.set_color(theme.colors.bg_hi, 0.35)
  ui.rect(0, 0, sw, strip_y + lab + 30)

  widgets.label(theme.font("t"), i18n.t("ui.demo.title"), 24, 10, 600, theme.colors.text, 0)
  local strip_bottom = draw_glyph_strip(24, strip_y)

  -- Icon buttons row.
  local by = strip_bottom + 8
  widgets.label(theme.font("s"), i18n.t("ui.demo.icon_buttons"), 24, by, 400, theme.colors.text_dim, 0)
  by = by + lab
  widgets.icon_button("demo_icon_a", { x = 24, y = by, w = 48, h = 48 }, glyphs.pad("a"), {
    on_click = function() widgets.show_toast("A") end,
  })
  widgets.icon_button("demo_icon_b", { x = 80, y = by, w = 48, h = 48 }, glyphs.pad("b"), {
    on_click = function() widgets.show_toast("B") end,
    badge = "3",
  })
  widgets.icon_button("demo_icon_x", { x = 136, y = by, w = 48, h = 48 }, glyphs.pad("x"), {
    on_click = function() widgets.show_toast("X") end,
    badge = "dot",
  })

  -- List.
  local list_y = by + 64
  widgets.label(theme.font("s"), i18n.t("ui.demo.list"), 24, list_y, 400, theme.colors.text_dim, 0)
  local list_h = theme.large_text and 156 or 196
  local sel, activated = widgets.list("demo_list", { x = 24, y = list_y + lab, w = 400, h = list_h },
    list_items(), M.list_sel, { header = i18n.t("ui.demo.crafting") })
  M.list_sel = sel

  -- Item grid.
  local grid_y = list_y + lab + list_h + 16
  widgets.label(theme.font("s"), i18n.t("ui.demo.grid"), 24, grid_y, 260, theme.colors.text_dim, 0)
  local cur, ev = widgets.item_grid("demo_grid", { x = 24, y = grid_y + lab }, 5, 2,
    grid_items(), M.grid_cur, { sub_group = "content" })
  M.grid_cur = cur
  if ev and ev.kind == "select" then
    widgets.show_toast(i18n.t("ui.demo.item_scrap"))
  end

  -- Progress bars.
  local pb_y = grid_y + lab + 120
  widgets.label(theme.font("s"), i18n.t("ui.demo.progress"), 24, pb_y, 260, theme.colors.text_dim, 0)
  widgets.progress_bar({ x = 24, y = pb_y + lab, w = 300, h = 18 }, 35, 100, { show_percent = true, color = theme.colors.cold })
  widgets.progress_bar({ x = 24, y = pb_y + lab + 26, w = 300, h = 18 }, 62, 100,
    { text = i18n.t("ui.demo.progress_label"), color = theme.colors.accent })
  widgets.progress_bar({ x = 24, y = pb_y + lab + 52, w = 300, h = 18 }, 5, 5,
    { show_percent = true, color = theme.colors.ok, segments = 5 })

  -- Stepper (right column, clear of the hint bar).
  local st_y = 320
  widgets.label(theme.font("s"), i18n.t("ui.demo.stepper"), 470, st_y, 260, theme.colors.text_dim, 0)
  local nv, changed, done = widgets.stepper("demo_step", { x = 470, y = st_y + lab, w = 300, h = 40 },
    M.step_val, 0, 20, 1, {
      sub_group = "content",
      on_change = function(v) M.step_val = v end,
    })
  if changed then M.step_val = nv end
  if done == "confirm" then M.step_val = nv end

  -- Tooltip demo (forced open for the screenshot).
  local tip_btn = { x = 470, y = 120, w = 48, h = 48 }
  widgets.icon_button("demo_tip_btn", tip_btn, glyphs.pad("y"), {
    on_click = function() end,
    tooltip = { title = i18n.t("ui.demo.tip_title"), body = i18n.t("ui.demo.tip_body"),
      footer = i18n.t("ui.demo.action_repair") },
    force_tooltip = (M.view == "main"),
  })
  widgets.label(theme.font("s"), i18n.t("ui.demo.tooltip"), 470, 176, 400, theme.colors.text_dim, 0)

  -- Overlay views (modal / confirm / radial).
  if M.view == "modal" then
    local r = widgets.modal("demo_modal", {
      title = i18n.t("ui.demo.modal"),
      body = i18n.t("ui.demo.body_modal"),
      buttons = {
        { id = "cancel", label = i18n.t("ui.cancel"), default = true },
        { id = "ok", label = i18n.t("ui.ok"), variant = "primary" },
      },
    })
    if r then M.view = "main" end
  elseif M.view == "confirm" then
    local r = widgets.confirm("demo_confirm", {
      title = i18n.t("ui.demo.confirm"),
      body = i18n.t("ui.demo.body_confirm"),
      danger = true,
    })
    if r then M.view = "main" end
  elseif M.view == "radial" then
    local r = widgets.radial("demo_radial", {
      center = { math.floor(sw * 0.5), math.floor(sh * 0.5) },
      preview = true,
      selected = 1,
      items = {
        { id = "follow", label = i18n.t("ui.demo.action_follow"), icon = "pad:a" },
        { id = "hold", label = i18n.t("ui.demo.action_hold"), icon = "pad:b" },
        { id = "lookout", label = i18n.t("ui.demo.action_lookout"), icon = "pad:x" },
        { id = "carry", label = i18n.t("ui.demo.action_carry"), icon = "pad:y" },
        { id = "craft", label = i18n.t("ui.demo.action_craft"), icon = "pad:lb" },
        { id = "repair", label = i18n.t("ui.demo.action_repair"), icon = "pad:rb" },
      },
    })
    if r then M.view = "main" end
  end

  hintbar.draw()
  widgets.draw_toast()
end

function _shutdown()
  hintbar.clear()
  focus.clear()
end
