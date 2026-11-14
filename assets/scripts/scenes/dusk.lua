-- Dusk modal (M4-lite): choose the night role of every character (sleep / guard / out), confirm to run the night.
-- Pushed by scenes/home when session.mode == "dusk"; the default choice is "sleep" for everyone.
local scene = require("core.scene")
local i18n = require("core.i18n")
local input = require("core.input")
local hs = require("game.home_session")
local theme = require("ui.theme")
local widgets = require("ui.widgets")
local hintbar = require("ui.hintbar")

local M = { session = nil, rows = nil, row = 1 }

local ROW_H = 36
local PANEL_W = 560

local function layout()
  local sw, sh = ui.screen_size()
  local n = #M.rows
  local ph = 96 + n * ROW_H + 70
  local px, py = math.floor((sw - PANEL_W) / 2), math.max(8, math.floor((sh - ph) / 2))
  return {
    x = px, y = py, w = PANEL_W, h = ph,
    rows_y = py + 72,
    btn = { x = px + math.floor((PANEL_W - 200) / 2), y = py + ph - 52, w = 200, h = 36 },
  }
end

local function role_rect(L, i)
  return { x = L.x + 240, y = L.rows_y + (i - 1) * ROW_H, w = L.w - 260, h = ROW_H - 4 }
end

local function inside(r, mx, my)
  return mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h
end

function M:on_enter(args)
  M.session = (args and args.session) or M.session
  local opt = hs.dusk_options(M.session)
  M.roles = opt.roles
  local names = {}
  for _, c in ipairs(hs.hud(M.session).chars) do names[c.id] = i18n.t(c.name) end
  M.rows = {}
  for _, cid in ipairs(opt.chars) do
    M.rows[#M.rows + 1] = { cid = cid, name = names[cid] or cid, role = 1 }
  end
  M.row = 1
  hintbar.push("dusk", {
    { action = "ui_up", text = "dusk.hint.person" },
    { action = "ui_left", text = "dusk.hint.role" },
    { action = "confirm", text = "dusk.hint.confirm" },
  })
end

function M:on_exit()
  hintbar.pop()
end

local function cycle(i, d)
  local r = M.rows[i]
  r.role = ((r.role - 1 + d) % #M.roles) + 1
end

local function submit()
  local roles = {}
  for _, r in ipairs(M.rows) do roles[r.cid] = M.roles[r.role] end
  local ok, err = hs.confirm_dusk(M.session, roles)
  if not ok then
    widgets.show_toast(i18n.t("dusk.toast.failed", { reason = tostring(err) }), 2.0)
    return
  end
  local s = M.session
  scene.pop_modal()
  if s.mode == "dawn" then scene.push_modal(require("scenes.dawn"), { session = s }) end
end

function M:update(dt)
  local n = #M.rows
  if input.pressed("ui_up") then M.row = ((M.row - 2) % n) + 1 end
  if input.pressed("ui_down") then M.row = (M.row % n) + 1 end
  if input.pressed("ui_left") then cycle(M.row, -1) end
  if input.pressed("ui_right") then cycle(M.row, 1) end
  if input.pressed("confirm", "keyboard") or input.pressed("confirm", "pad") then
    submit()
    return
  end
  if input.pressed("confirm", "mouse") then
    local mx, my = ui.mouse_pos()
    local L = layout()
    if inside(L.btn, mx, my) then
      submit()
      return
    end
    for i = 1, n do
      local rr = role_rect(L, i)
      if inside(rr, mx, my) then
        M.row = i
        cycle(i, 1)
      elseif inside({ x = L.x, y = rr.y, w = L.w, h = rr.h }, mx, my) then
        M.row = i
      end
    end
  end
end

function M:draw()
  if not M.rows then return end
  local L = layout()
  local tf, bf, sf = theme.font("t"), theme.font("b"), theme.font("s")
  widgets.modal_dim()
  widgets.panel(L.x, L.y, L.w, L.h, 0.97)
  widgets.label(tf, i18n.t("dusk.title"), L.x, L.y + 14, L.w, theme.colors.accent, 1)
  widgets.label(sf, i18n.t("dusk.subtitle"), L.x + 20, L.y + 48, L.w - 40, theme.colors.text_dim, 1)
  for i, r in ipairs(M.rows) do
    local y = L.rows_y + (i - 1) * ROW_H
    local sel = i == M.row
    if sel then
      theme.set_color(theme.colors.accent, 0.22)
      ui.rect(L.x + 12, y, L.w - 24, ROW_H - 4)
      theme.set_color(theme.colors.accent)
      ui.rect(L.x + 12, y, 3, ROW_H - 4)
    end
    local ty = y + math.floor((ROW_H - 4 - ui.font_line_height(bf)) / 2)
    widgets.label(bf, tostring(r.name), L.x + 26, ty, 200, theme.colors.text, 0)
    local rr = role_rect(L, i)
    local role = M.roles[r.role]
    theme.set_color(sel and theme.colors.accent or theme.colors.text_dim)
    widgets.label(bf, "<  " .. i18n.t("dusk.role." .. role) .. "  >", rr.x, ty, rr.w, sel and theme.colors.accent or theme.colors.text, 1)
  end
  local cur = M.rows[M.row]
  if cur then
    widgets.label(sf, i18n.t("dusk.role_desc." .. M.roles[cur.role]), L.x + 20, L.btn.y - 26, L.w - 40, theme.colors.text_dim, 1)
  end
  theme.nine("btn_hover", L.btn.x, L.btn.y, L.btn.w, L.btn.h)
  theme.set_color(theme.colors.accent)
  ui.rect(L.btn.x, L.btn.y, 3, L.btn.h)
  widgets.label(bf, i18n.t("dusk.confirm"), L.btn.x, L.btn.y + math.floor((L.btn.h - ui.font_line_height(bf)) / 2),
    L.btn.w, theme.colors.text, 1)
  hintbar.draw()
end

return M
