-- Dawn modal (M4-lite): shows the night report (session.report.lines), confirm starts the new day.
local scene = require("core.scene")
local i18n = require("core.i18n")
local input = require("core.input")
local hs = require("game.home_session")
local theme = require("ui.theme")
local widgets = require("ui.widgets")
local hintbar = require("ui.hintbar")

local M = { session = nil }

local PANEL_W = 620
local LINE_H = 24

-- Report args carry i18n keys for characters ("char.<id>.name") and lists of them; turn them into text.
local function resolve(args)
  local out = {}
  for k, v in pairs(args or {}) do
    if type(v) == "table" then
      local parts = {}
      for _, item in ipairs(v) do
        parts[#parts + 1] = type(item) == "string" and i18n.t(item) or tostring(item)
      end
      out[k] = table.concat(parts, ", ")
    elseif k == "cause" and type(v) == "string" then
      local key = "dawn.cause." .. v
      local txt = i18n.t(key)
      out[k] = (txt ~= key) and txt or v
    elseif type(v) == "string" and v:find("^char%.") then
      out[k] = i18n.t(v)
    else
      out[k] = v
    end
  end
  return out
end

local function layout()
  local sw, sh = ui.screen_size()
  local n = M.session and M.session.report and #M.session.report.lines or 0
  local ph = 120 + math.max(1, n) * LINE_H + 70
  local px, py = math.floor((sw - PANEL_W) / 2), math.max(8, math.floor((sh - ph) / 2))
  return {
    x = px, y = py, w = PANEL_W, h = ph,
    btn = { x = px + math.floor((PANEL_W - 200) / 2), y = py + ph - 52, w = 200, h = 36 },
  }
end

function M:on_enter(args)
  M.session = (args and args.session) or M.session
  hintbar.push("dawn", { { action = "confirm", text = "dawn.hint.confirm" } })
end

function M:on_exit()
  hintbar.pop()
end

local function submit()
  local ok, err = hs.confirm_dawn(M.session)
  if not ok then
    widgets.show_toast(i18n.t("dawn.toast.failed", { reason = tostring(err) }), 2.0)
    return
  end
  scene.pop_modal()
end

function M:update(dt)
  if input.pressed("confirm", "keyboard") or input.pressed("confirm", "pad") then
    submit()
    return
  end
  if input.pressed("confirm", "mouse") then
    local mx, my = ui.mouse_pos()
    local b = layout().btn
    if mx >= b.x and mx < b.x + b.w and my >= b.y and my < b.y + b.h then submit() end
  end
end

function M:draw()
  local s = M.session
  if not (s and s.report) then return end
  local L = layout()
  local tf, bf, sf = theme.font("t"), theme.font("b"), theme.font("s")
  widgets.modal_dim()
  widgets.panel(L.x, L.y, L.w, L.h, 0.97)
  widgets.label(tf, i18n.t("dawn.title", { day = s.report.day }), L.x, L.y + 14, L.w, theme.colors.accent, 1)
  widgets.label(sf, i18n.t("dawn.subtitle"), L.x + 20, L.y + 54, L.w - 40, theme.colors.text_dim, 1)
  local y = L.y + 100
  for _, line in ipairs(s.report.lines) do
    widgets.label(bf, i18n.t(line.key, resolve(line.args)), L.x + 28, y, L.w - 56, theme.colors.text, 0)
    y = y + LINE_H
  end
  theme.nine("btn_hover", L.btn.x, L.btn.y, L.btn.w, L.btn.h)
  theme.set_color(theme.colors.accent)
  ui.rect(L.btn.x, L.btn.y, 3, L.btn.h)
  widgets.label(bf, i18n.t("dawn.continue"), L.btn.x, L.btn.y + math.floor((L.btn.h - ui.font_line_height(bf)) / 2),
    L.btn.w, theme.colors.text, 1)
  hintbar.draw()
end

return M
