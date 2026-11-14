-- Title screen scene (M1).
local audio = require("audio")
local i18n = require("core.i18n")
local scene = require("core.scene")
local theme = require("ui.theme")
local focus = require("ui.focus")
local widgets = require("ui.widgets")
local settings = require("ui.settings")

local M = {
  _snow = nil,
  _t = 0,
}

local function init_snow(sw, sh)
  local snow = {}
  -- Deterministic pseudo-random snowflakes to avoid RNG state side effects
  local seed = 1337
  local function next_f()
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed / 2147483648
  end
  for i = 1, 64 do
    snow[i] = {
      x = next_f() * sw,
      y = next_f() * sh,
      vx = -12 - next_f() * 18,
      vy = 24 + next_f() * 36,
      sz = (i % 3 == 0) and 3 or 2,
      a = 0.25 + next_f() * 0.45,
    }
  end
  M._snow = snow
end

function M:on_enter()
  focus.push_group("title", { default = "btn_new_game" })
  audio.bgm("bgm/street_chip")
end

function M:on_exit()
  focus.pop_group()
end

function M:update(dt)
  M._t = M._t + dt
  -- Dev / screenshot hook: WS_NEW_GAME=1 starts the home scene without input.
  if os.getenv("WS_NEW_GAME") == "1" and M._t > 0.2 then M._start = true end
  if M._start then
    M._start = false
    scene.replace(require("scenes.home"))
    return
  end
  local sw, sh = ui.screen_size()
  if not M._snow then
    init_snow(sw, sh)
  end
  for i = 1, #M._snow do
    local p = M._snow[i]
    p.x = p.x + p.vx * dt
    p.y = p.y + p.vy * dt
    if p.x < -4 then p.x = sw + 4 end
    if p.y > sh + 4 then
      p.y = -4
      p.x = (p.x + sw * 0.37) % sw
    end
  end
end

function M:draw()
  local sw, sh = ui.screen_size()

  -- Winter night sky gradient (two layered quads)
  ui.color(0.04, 0.06, 0.11, 1.0)
  ui.rect(0, 0, sw, sh)
  ui.color(0.07, 0.10, 0.17, 0.7)
  ui.rect(0, math.floor(sh * 0.45), sw, math.ceil(sh * 0.55))

  -- Distant snow ridge silhouette
  ui.color(0.09, 0.13, 0.21, 1.0)
  ui.rect(0, math.floor(sh * 0.78), sw, math.ceil(sh * 0.22))

  -- Snowflakes
  if M._snow then
    for i = 1, #M._snow do
      local p = M._snow[i]
      ui.color(0.85, 0.92, 1.0, p.a)
      ui.rect(math.floor(p.x), math.floor(p.y), p.sz, p.sz)
    end
  end

  local u = 1
  local cx = math.floor(sw * 0.5)

  -- Title header
  local tf = theme.font("t")
  local bf = theme.font("b")
  local sf = theme.font("s")
  local title_y = math.floor(sh * 0.16)
  widgets.label(tf, i18n.t("title.name"), 0, title_y, sw, theme.colors.text, 1)
  widgets.label(sf, i18n.t("title.subtitle"), 0, title_y + math.floor(38 * u), sw, theme.colors.text_dim, 1)

  -- Menu panel & buttons
  local btn_w = math.floor(240 * u)
  local btn_h = math.floor(36 * u)
  local gap = math.floor(10 * u)
  local items = {
    { id = "btn_continue", key = "title.continue", enabled = false, variant = "default" },
    { id = "btn_new_game", key = "title.new_game", enabled = true, variant = "primary",
      action = function() M._start = true end },
    { id = "btn_load", key = "title.load", enabled = true, variant = "default",
      action = function() widgets.show_toast(i18n.t("title.stub_notice"), 2.0) end },
    { id = "btn_settings", key = "title.settings", enabled = true, variant = "default",
      action = function() scene.push_modal(settings) end },
    { id = "btn_quit", key = "title.quit", enabled = true, variant = "danger",
      action = function()
        local iso = require("iso")
        iso.quit()
      end },
  }

  local total_h = #items * btn_h + (#items - 1) * gap
  local pad = math.floor(20 * u)
  local panel_w = btn_w + pad * 2
  local panel_h = total_h + pad * 2
  local panel_x = cx - math.floor(panel_w * 0.5)
  local panel_y = math.floor(sh * 0.36)

  widgets.panel(panel_x, panel_y, panel_w, panel_h, 0.88)

  local bx = panel_x + pad
  local by = panel_y + pad
  for i = 1, #items do
    local it = items[i]
    widgets.button(it.id, { x = bx, y = by, w = btn_w, h = btn_h }, i18n.t(it.key), {
      enabled = it.enabled,
      variant = it.variant,
      font_kind = "b",
      on_click = it.action,
    })
    by = by + btn_h + gap
  end

  -- Version / footer
  widgets.label(sf, "M1  |  " .. string.upper(i18n.get_lang()), 16, sh - math.floor(26 * u), sw - 32, theme.colors.text_dim, 0)
  local _ = bf
end

return M
