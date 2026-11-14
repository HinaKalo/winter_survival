-- Immediate-mode UI widget library (UI-UX §4).
local iso = require("iso")
local i18n = require("core.i18n")
local input = require("core.input")
local theme = require("ui.theme")
local focus = require("ui.focus")
local glyphs = require("ui.glyphs")

local K = keys or {}
local PA = pad_axes or {}

local M = {
  _pressed_id = nil,
  _drag_slider = nil,
  _toast_msg = nil,
  _toast_t = 0,
  _tt = {},          -- [id] = {t, last}
  _tt_drawn_at = -1,
  _tt_drawn_id = nil,
  _lists = {},       -- [id] = {scroll, last_click, last_t, activate_idx}
  _grids = {},       -- [id] = {cursor, held, ...}
  _modals = {},      -- [id] = {spec, hold_t, pending}
  _modal_order = {},
  _modal_results = {},
  _radials = {},     -- [id] = {sel, spec}
  _radial_results = {},
  _steppers = {},    -- [id] = {btn, t, next}
}

local function now()
  return theme._blink_t
end


local function point_in(mx, my, x, y, w, h)
  return mx >= x and mx <= x + w and my >= y and my <= y + h
end

function M.ellipsize(font, str, max_w)
  if max_w <= 0 then return "" end
  if ui.text_width(font, str) <= max_w then return str end
  local ell = "…"
  local ell_w = ui.text_width(font, ell)
  if ell_w >= max_w then return ell end
  -- Binary search byte boundaries on UTF-8 character starts
  local cuts = { 0 }
  local i = 1
  local n = #str
  while i <= n do
    local b = str:byte(i)
    local step = 1
    if b >= 0xF0 then step = 4
    elseif b >= 0xE0 then step = 3
    elseif b >= 0xC0 then step = 2 end
    i = i + step
    cuts[#cuts + 1] = math.min(i - 1, n)
  end
  local lo, hi, best = 1, #cuts, 1
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    local sub = str:sub(1, cuts[mid])
    if ui.text_width(font, sub) + ell_w <= max_w then
      best = mid
      lo = mid + 1
    else
      hi = mid - 1
    end
  end
  return str:sub(1, cuts[best]) .. ell
end

function M.panel(x, y, w, h, alpha)
  theme.nine("panel", x, y, w, h, theme.colors.white, alpha or 0.94)
end

function M.modal_dim()
  local sw, sh = ui.screen_size()
  ui.color(0, 0, 0, 0.55)
  ui.rect(0, 0, sw, sh)
end

function M.label(font, str, x, y, w, col, align)
  ui.text_shadow(1, 1, 0, 0, 0, 0.6)
  theme.set_color(col or theme.colors.text)
  if w and w > 0 then
    return ui.text_box(font, str, x, y, w, align or 0, -1)
  else
    ui.text(font, str, x, y)
    return ui.font_line_height(font)
  end
end

function M.button(id, rect, label, opts)
  opts = opts or {}
  local enabled = opts.enabled ~= false
  local mx, my = ui.mouse_pos()
  local hovered = enabled and point_in(mx, my, rect.x, rect.y, rect.w, rect.h)
  local down_now = enabled and iso.mouse_down(0)
  local released_now = enabled and kit_input.mouse_released(0)

  if hovered and iso.mouse_pressed(0) then
    M._pressed_id = id
  end

  local clicked = false
  if released_now then
    if hovered and (M._pressed_id == id or M._pressed_id == nil) then
      clicked = true
    end
    if M._pressed_id == id then M._pressed_id = nil end
  elseif not down_now and M._pressed_id == id then
    M._pressed_id = nil
  end

  focus.register({
    id = id,
    rect = rect,
    enabled = enabled,
    sub_group = opts.sub_group,
    nav = opts.nav,
    on_activate = function()
      if opts.on_click then opts.on_click() end
    end,
  })

  if clicked then
    kit_audio.sfx("sfx/ui", 0.7, 1.0)
    if opts.on_click then opts.on_click() end
  end

  local is_pressed = (M._pressed_id == id and hovered)
  local skin_key = "btn_normal"
  if not enabled then
    skin_key = "btn_disabled"
  elseif is_pressed then
    skin_key = "btn_pressed"
  elseif hovered or focus.is_focused(id) then
    skin_key = "btn_hover"
  end

  if opts.variant ~= "link" then
    theme.nine(skin_key, rect.x, rect.y, rect.w, rect.h)
    if opts.variant == "primary" then
      theme.set_color(theme.colors.accent)
      ui.rect(rect.x, rect.y, 3, rect.h)
    elseif opts.variant == "danger" then
      theme.set_color(theme.colors.danger)
      ui.rect(rect.x, rect.y, 3, rect.h)
    end
  end

  local f = theme.font(opts.font_kind or "b")
  local lh = ui.font_line_height(f)
  local txt = M.ellipsize(f, label, rect.w - 16)
  local ty = rect.y + math.floor((rect.h - lh) * 0.5) + (is_pressed and 1 or 0)
  local tc = enabled and theme.colors.text or theme.colors.disabled
  M.label(f, txt, rect.x + 8, ty, rect.w - 16, tc, opts.align or 1)

  if focus.show_ring(id) then
    focus.draw_ring(rect)
  end
  return clicked
end

function M.toggle(id, rect, label, val, opts)
  opts = opts or {}
  local enabled = opts.enabled ~= false
  local changed = false
  local function flip()
    val = not val
    changed = true
    if opts.on_change then opts.on_change(val) end
  end

  local mx, my = ui.mouse_pos()
  local hovered = enabled and point_in(mx, my, rect.x, rect.y, rect.w, rect.h)
  if hovered and kit_input.mouse_released(0) then
    kit_audio.sfx("sfx/ui", 0.7, 1.0)
    flip()
  end

  focus.register({
    id = id,
    rect = rect,
    enabled = enabled,
    sub_group = opts.sub_group,
    on_activate = flip,
    on_dir = function(dir)
      if dir == "left" and val then
        val = false; changed = true
        if opts.on_change then opts.on_change(val) end
        return true
      elseif dir == "right" and not val then
        val = true; changed = true
        if opts.on_change then opts.on_change(val) end
        return true
      end
      return false
    end,
  })

  local f = theme.font("b")
  local fs = theme.font("s")
  local lh = ui.font_line_height(f)
  local txt = M.ellipsize(f, label, rect.w - 80)
  M.label(f, txt, rect.x + 8, rect.y + math.floor((rect.h - lh) * 0.5), rect.w - 80,
    enabled and theme.colors.text or theme.colors.disabled, 0)

  local sw, sh = 56, 26
  local sx = rect.x + rect.w - sw - 8
  local sy = rect.y + math.floor((rect.h - sh) * 0.5)
  theme.set_color(val and theme.colors.ok or theme.colors.bg_dark)
  ui.rect(sx, sy, sw, sh)
  theme.set_color(theme.colors.edge)
  ui.rect(sx, sy, sw, 1)
  ui.rect(sx, sy + sh - 1, sw, 1)

  local knob_x = val and (sx + sw - 24) or (sx + 2)
  theme.set_color(theme.colors.text)
  ui.rect(knob_x, sy + 2, 22, sh - 4)

  local state_txt = i18n.t(val and "ui.on" or "ui.off")
  local state_x = val and (sx + 4) or (sx + 26)
  M.label(fs, state_txt, state_x, sy + math.floor((sh - ui.font_line_height(fs)) * 0.5), 26, theme.colors.text, 1)

  if focus.show_ring(id) then focus.draw_ring(rect) end
  return val, changed
end

function M.slider(id, rect, label, val, min_v, max_v, step, opts)
  opts = opts or {}
  local enabled = opts.enabled ~= false
  local changed = false
  local span = math.max(0.0001, max_v - min_v)

  local track_w = 180
  local track_x = rect.x + rect.w - track_w - 56
  local track_y = rect.y + math.floor((rect.h - 8) * 0.5)

  local function set_v(nv)
    nv = math.max(min_v, math.min(max_v, nv))
    if step and step > 0 then
      nv = min_v + math.floor((nv - min_v) / step + 0.5) * step
      nv = math.max(min_v, math.min(max_v, nv))
    end
    if math.abs(nv - val) > 1e-5 then
      val = nv
      changed = true
      if opts.on_change then opts.on_change(val) end
    end
  end

  local mx, my = ui.mouse_pos()
  if enabled then
    if point_in(mx, my, track_x - 8, rect.y, track_w + 16, rect.h) and iso.mouse_pressed(0) then
      M._drag_slider = id
    end
    if M._drag_slider == id then
      if iso.mouse_down(0) then
        local t = (mx - track_x) / track_w
        set_v(min_v + t * span)
      else
        M._drag_slider = nil
      end
    end
  end

  focus.register({
    id = id,
    rect = rect,
    enabled = enabled,
    sub_group = opts.sub_group,
    on_dir = function(dir)
      local mult = (iso.key_down(keys.LEFT_SHIFT) or pad.button_down(pad_buttons.lt)) and 5 or 1
      local delta = (step or (span * 0.05)) * mult
      if dir == "left" then
        set_v(val - delta); return true
      elseif dir == "right" then
        set_v(val + delta); return true
      end
      return false
    end,
  })

  local f = theme.font("b")
  local fs = theme.font("s")
  local lh = ui.font_line_height(f)
  local txt = M.ellipsize(f, label, track_x - rect.x - 16)
  M.label(f, txt, rect.x + 8, rect.y + math.floor((rect.h - lh) * 0.5), track_x - rect.x - 16,
    enabled and theme.colors.text or theme.colors.disabled, 0)

  theme.nine("slider_track", track_x, track_y, track_w, 8)
  local ratio = math.max(0, math.min(1, (val - min_v) / span))
  theme.set_color(theme.colors.accent)
  ui.rect(track_x, track_y + 1, math.floor(track_w * ratio), 6)

  local thumb_x = track_x + math.floor(track_w * ratio) - 8
  theme.nine("slider_thumb", thumb_x, rect.y + math.floor((rect.h - 24) * 0.5), 16, 24)

  local val_str = opts.format and opts.format(val) or string.format("%d%%", math.floor(ratio * 100 + 0.5))
  M.label(fs, val_str, rect.x + rect.w - 48, rect.y + math.floor((rect.h - ui.font_line_height(fs)) * 0.5), 44, theme.colors.text_dim, 2)

  if focus.show_ring(id) then focus.draw_ring(rect) end
  return val, changed
end

function M.cycle(id, rect, label, options, index, opts)
  opts = opts or {}
  local enabled = opts.enabled ~= false
  local n = #options
  local changed = false

  local function step_idx(delta)
    if n == 0 then return end
    index = ((index - 1 + delta) % n) + 1
    changed = true
    if opts.on_change then opts.on_change(index, options[index]) end
  end

  local box_w = opts.box_w or 220
  local box_x = rect.x + rect.w - box_w - 8

  local mx, my = ui.mouse_pos()
  if enabled and kit_input.mouse_released(0) and point_in(mx, my, box_x, rect.y, box_w, rect.h) then
    kit_audio.sfx("sfx/ui", 0.7, 1.0)
    if mx < box_x + 28 then
      step_idx(-1)
    else
      step_idx(1)
    end
  end

  focus.register({
    id = id,
    rect = rect,
    enabled = enabled,
    sub_group = opts.sub_group,
    on_activate = function() step_idx(1) end,
    on_dir = function(dir)
      if dir == "left" then step_idx(-1); return true
      elseif dir == "right" then step_idx(1); return true end
      return false
    end,
  })

  local f = theme.font("b")
  local lh = ui.font_line_height(f)
  local txt = M.ellipsize(f, label, box_x - rect.x - 16)
  M.label(f, txt, rect.x + 8, rect.y + math.floor((rect.h - lh) * 0.5), box_x - rect.x - 16,
    enabled and theme.colors.text or theme.colors.disabled, 0)

  theme.nine("btn_normal", box_x, rect.y + 4, box_w, rect.h - 8)
  local opt_label = options[index] and (options[index].label or tostring(options[index])) or ""
  local ty = rect.y + math.floor((rect.h - lh) * 0.5)
  M.label(f, "‹", box_x + 6, ty, 20, theme.colors.text_dim, 1)
  M.label(f, M.ellipsize(f, opt_label, box_w - 56), box_x + 28, ty, box_w - 56, theme.colors.text, 1)
  M.label(f, "›", box_x + box_w - 26, ty, 20, theme.colors.text_dim, 1)

  if focus.show_ring(id) then focus.draw_ring(rect) end
  return index, changed
end

function M.tabs(id_prefix, rect, labels, active_idx, opts)
  opts = opts or {}
  local f = theme.font("b")
  local lh = ui.font_line_height(f)
  local x = rect.x
  local h = rect.h or 40
  local mx, my = ui.mouse_pos()
  local changed = false

  for i, lbl in ipairs(labels) do
    local tw = math.max(96, ui.text_width(f, lbl) + 28)
    local tr = { x = x, y = rect.y, w = tw, h = h }
    local is_act = (i == active_idx)
    if point_in(mx, my, tr.x, tr.y, tr.w, tr.h) and kit_input.mouse_released(0) then
      if i ~= active_idx then
        active_idx = i
        changed = true
        kit_audio.sfx("sfx/ui", 0.7, 1.0)
      end
    end
    theme.nine(is_act and "tab_active" or "tab_normal", tr.x, tr.y, tr.w, tr.h)
    M.label(f, lbl, tr.x + 8, tr.y + math.floor((h - lh) * 0.5), tw - 16,
      is_act and theme.colors.text or theme.colors.text_dim, 1)
    x = x + tw + 4
  end
  return active_idx, changed
end

function M.show_toast(msg, dur)
  M._toast_msg = msg
  M._toast_t = dur or 2.2
end

function M.update_toast(dt)
  if M._toast_t > 0 then
    M._toast_t = M._toast_t - dt
    if M._toast_t <= 0 then M._toast_msg = nil end
  end
end

function M.draw_toast()
  if not M._toast_msg or M._toast_t <= 0 then return end
  local sw, sh = ui.screen_size()
  local f = theme.font("b")
  local w = math.min(sw - 64, math.max(240, ui.text_width(f, M._toast_msg) + 40))
  local h = 40
  local x = math.floor((sw - w) * 0.5)
  local y = sh - 72
  theme.nine("tip", x, y, w, h)
  M.label(f, M._toast_msg, x + 12, y + math.floor((h - ui.font_line_height(f)) * 0.5), w - 24, theme.colors.text, 1)
end

-- ======================================================================
-- UI-UX §4 controls added by PANEL (IconButton, List, ItemGrid,
-- ProgressBar, Tooltip, Modal, Confirm, Radial, Stepper).
-- ======================================================================

local function ensure_state(tbl, id)
  local st = tbl[id]
  if not st then st = {}; tbl[id] = st end
  return st
end

local function color_of(c, fallback)
  if type(c) == "table" then return c end
  if type(c) == "string" and theme.colors[c] then return theme.colors[c] end
  return fallback
end

local function glyph_spec(g)
  if type(g) == "table" then return g end
  if type(g) ~= "string" then return nil end
  if g:sub(1, 4) == "pad:" then return glyphs.pad(g:sub(5)) end
  if g:sub(1, 4) == "key:" then return glyphs.key(g:sub(5)) end
  if g:sub(1, 6) == "mouse:" then return glyphs.mouse(tonumber(g:sub(7)) or 0) end
  return glyphs.key(g)
end

-- Free per-id state (scroll, drag, timers) when a panel closes.
function M.reset(id)
  local tables = { M._tt, M._lists, M._grids, M._steppers, M._radials, M._modal_results, M._radial_results }
  for _, tbl in ipairs(tables) do
    for k in pairs(tbl) do
      if type(k) == "string" and (k == id or k:sub(1, #id + 1) == id .. "#") then
        tbl[k] = nil
      end
    end
  end
  if M._modals[id] then M.close_modal(id, "cancel") end
  M._modal_results[id] = nil
end

-- ------------------------------------------------------------------ IconButton (§4.3)
function M.icon_button(id, rect, glyph, opts)
  opts = opts or {}
  local enabled = opts.enabled ~= false
  local mx, my = ui.mouse_pos()
  local hovered = enabled and point_in(mx, my, rect.x, rect.y, rect.w, rect.h)
  local down_now = enabled and iso.mouse_down(0)
  local released_now = enabled and kit_input.mouse_released(0)

  if hovered and iso.mouse_pressed(0) then M._pressed_id = id end
  local clicked = false
  if released_now then
    if hovered and (M._pressed_id == id or M._pressed_id == nil) then clicked = true end
    if M._pressed_id == id then M._pressed_id = nil end
  elseif not down_now and M._pressed_id == id then
    M._pressed_id = nil
  end

  local function activate()
    if not enabled then
      kit_audio.sfx("sfx/ui_deny", 0.5, 0.7)
      return
    end
    if opts.on_click then opts.on_click() end
  end

  focus.register({
    id = id, rect = rect, enabled = enabled, sub_group = opts.sub_group, nav = opts.nav,
    on_activate = activate,
  })

  if clicked then
    kit_audio.sfx("sfx/ui", 0.7, 1.0)
    activate()
  end

  local is_pressed = (M._pressed_id == id and hovered)
  local skin_key = "btn_normal"
  if not enabled then skin_key = "btn_disabled"
  elseif is_pressed then skin_key = "btn_pressed"
  elseif hovered or focus.is_focused(id) then skin_key = "btn_hover" end
  theme.nine(skin_key, rect.x, rect.y, rect.w, rect.h)
  if opts.variant == "primary" then
    theme.set_color(theme.colors.accent)
    ui.rect(rect.x, rect.y + 3, 3, rect.h - 6)
  elseif opts.variant == "danger" then
    theme.set_color(theme.colors.danger)
    ui.rect(rect.x, rect.y + 3, 3, rect.h - 6)
  end

  local spec = glyph_spec(glyph or opts.glyph)
  local icon_size = opts.icon_size or math.min(32, math.max(16, rect.w - 16))
  if spec then
    local gw, gh = glyphs.measure(spec, icon_size)
    local gx = rect.x + math.floor((rect.w - gw) * 0.5)
    local gy = rect.y + math.floor((rect.h - gh) * 0.5) + (is_pressed and 1 or 0)
    glyphs.draw(spec, gx, gy, icon_size)
  end

  if opts.badge ~= nil and opts.badge ~= false then
    if opts.badge == true or opts.badge == "dot" then
      theme.set_color(theme.colors.danger)
      ui.rect(rect.x + rect.w - 12, rect.y + 4, 8, 8)
    else
      local fs = theme.font("s")
      local txt = tostring(opts.badge)
      local bw = math.max(16, ui.text_width(fs, txt) + 8)
      theme.set_color(theme.colors.danger)
      ui.rect(rect.x + rect.w - bw - 2, rect.y + 2, bw, 16)
      M.label(fs, txt, rect.x + rect.w - bw - 2, rect.y + 3, bw, theme.colors.text, 1)
    end
  end

  if opts.tooltip then
    M.tooltip(id .. "#tip", rect, opts.tooltip, {
      hover = hovered,
      focus = focus.is_focused(id),
      force = opts.force_tooltip,
      delay = opts.tooltip_delay,
    })
  end
  if focus.show_ring(id) then focus.draw_ring(rect) end
  return clicked
end

-- ------------------------------------------------------------------ ProgressBar (§4.10)
function M.progress_bar(rect, value, max_v, opts)
  opts = opts or {}
  max_v = (max_v and max_v > 0) and max_v or 1
  local ratio = math.max(0, math.min(1, (value or 0) / max_v))
  local inner = 2

  theme.nine("row", rect.x, rect.y, rect.w, rect.h)
  theme.set_color(theme.colors.edge)
  ui.rect(rect.x, rect.y, rect.w, 1)
  ui.rect(rect.x, rect.y + rect.h - 1, rect.w, 1)
  theme.set_color(theme.colors.bg_dark)
  ui.rect(rect.x + inner, rect.y + inner, rect.w - inner * 2, rect.h - inner * 2)

  local fill_w = math.floor((rect.w - inner * 2) * ratio)
  if fill_w > 0 then
    theme.set_color(color_of(opts.color, theme.colors.accent))
    ui.rect(rect.x + inner, rect.y + inner, fill_w, rect.h - inner * 2)
  end

  -- Optional integer segment separators (needs bars, §3.4).
  if opts.segments and opts.segments > 1 then
    theme.set_color(theme.colors.bg, 0.9)
    for i = 1, opts.segments - 1 do
      local sx = rect.x + inner + math.floor((rect.w - inner * 2) * i / opts.segments)
      ui.rect(sx, rect.y + inner, 1, rect.h - inner * 2)
    end
  end

  local f = theme.font("s")
  local txt = opts.text
  if not txt and opts.show_percent then txt = string.format("%d%%", math.floor(ratio * 100 + 0.5)) end
  if txt then
    M.label(f, txt, rect.x + 4, rect.y + math.floor((rect.h - ui.font_line_height(f)) * 0.5), rect.w - 8,
      opts.text_color or theme.colors.text, 1)
  end
  if opts.noise then
    local lvl = math.max(0, math.min(5, opts.noise))
    for i = 1, 5 do
      theme.set_color(i <= lvl and theme.colors.danger or theme.colors.disabled)
      ui.rect(rect.x + rect.w - 6 * (6 - i) - 2, rect.y - 4, 3, 2)
    end
  end
  return ratio
end

-- ------------------------------------------------------------------ Tooltip (§4.11)
function M.tooltip(id, anchor, spec, opts)
  opts = opts or {}
  if not spec then return false end
  if type(spec) == "string" then spec = { title = spec } end
  local t = now()
  local st = ensure_state(M._tt, id)
  if st.last == nil then st.last = t; st.t = 0 end
  local active = opts.force or opts.hover or opts.focus
  if not active then
    st.t = 0
    st.last = t
    return false
  end
  st.t = st.t + math.max(0, t - st.last)
  st.last = t
  if not (opts.force or opts.info or st.t >= (opts.delay or 0.4)) then return false end
  if M._tt_drawn_at == t and M._tt_drawn_id ~= id then return false end
  M._tt_drawn_at = t
  M._tt_drawn_id = id

  local sw, sh = ui.screen_size()
  local max_w = math.min(opts.max_w or 360, sw - 16)
  local f = theme.font("b")
  local fs = theme.font("s")
  local lh = ui.font_line_height(f)
  local lh_s = ui.font_line_height(fs)

  local title = spec.title or ""
  local body = spec.body
  local footer = spec.footer
  local w = math.max(120, ui.text_width(f, title))
  if body then
    local m = ui.text_measure(fs, body, max_w - 16)
    w = math.max(w, m.w)
  end
  if footer then w = math.max(w, ui.text_width(fs, footer)) end
  w = math.min(max_w, math.ceil(w) + 16)

  local body_h = body and ui.text_measure(fs, body, w - 16).h or 0
  local footer_h = footer and lh_s or 0
  local h = 8 + lh + (body and (4 + body_h) or 0) + (footer and (4 + footer_h) or 0) + 8

  local x = anchor.x + anchor.w + 8
  local y = anchor.y + anchor.h + 8
  if x + w > sw - 4 then x = anchor.x - w - 8 end
  if y + h > sh - 4 then y = anchor.y - h - 8 end
  x = math.max(4, math.min(sw - w - 4, x))
  y = math.max(4, math.min(sh - h - 4, y))

  theme.nine("tip", x, y, w, h, theme.colors.white, 0.98)  M.label(f, M.ellipsize(f, title, w - 16), x + 8, y + 8, w - 16, theme.colors.text, 0)
  local cy = y + 8 + lh
  if body then
    cy = cy + 4
    theme.set_color(theme.colors.text_dim)
    ui.text_box(fs, body, x + 8, cy, w - 16, 0, -1)
    cy = cy + body_h
  end
  if footer then
    cy = cy + 4
    M.label(fs, footer, x + 8, cy, w - 16,
      opts.footer_danger and theme.colors.danger or theme.colors.text_dim, 0)
  end
  return true
end

-- ------------------------------------------------------------------ List (§4.8)
function M.list(id, rect, items, selected, opts)
  opts = opts or {}
  items = items or {}
  local st = ensure_state(M._lists, id)
  st.scroll = st.scroll or 0
  st.last_click = st.last_click or -1
  st.last_t = st.last_t or -100
  st.activate_idx = st.activate_idx or nil

  local row_h = opts.row_h or theme.layout.list_row
  local header_h = opts.header and 24 or 0
  local sb_w = (opts.scrollbar ~= false) and 16 or 0
  local content_w = rect.w - sb_w
  local view_h = rect.h - header_h
  local visible = math.max(1, math.floor(view_h / row_h))
  local max_scroll = math.max(0, #items - visible)
  local cur = selected or 1
  local list_focused = false

  -- If focus landed on a row, honor it and scroll it into view.
  for i = 1, #items do
    if focus.is_focused(id .. "#row" .. i) then
      cur = i
      list_focused = true
      break
    end
  end
  if cur < 1 then cur = 1 end
  if cur > #items then cur = math.max(1, #items) end
  if cur <= st.scroll then st.scroll = cur - 1
  elseif cur > st.scroll + visible then st.scroll = cur - visible end
  st.scroll = math.max(0, math.min(max_scroll, st.scroll))

  if opts.header then
    local f = theme.font("s")
    M.label(f, opts.header, rect.x + 12, rect.y + 2, content_w - 24, theme.colors.text_dim, 0)
  end

  local list_y = rect.y + header_h
  local mx, my = ui.mouse_pos()
  local activated = nil
  local t = now()
  local over_rows = point_in(mx, my, rect.x, list_y, content_w, view_h)

  if over_rows and #items > 0 then
    local row_i = math.floor((my - list_y) / row_h) + 1
    local idx = st.scroll + row_i
    local item = items[idx]
    if item and kit_input.mouse_released(0) then
      local enabled = item.enabled ~= false
      if enabled or opts.allow_disabled_select then cur = idx end
      if enabled then
        if st.last_click == idx and (t - st.last_t) < 0.35 then activated = item end
        st.last_click = idx
        st.last_t = t
      end
    end
  end

  -- Keyboard page / home / end.
  if list_focused or focus.is_focused(id .. "#list") then
    if input.pressed("ui_page_prev") then st.scroll = math.max(0, st.scroll - visible) end
    if input.pressed("ui_page_next") then st.scroll = math.min(max_scroll, st.scroll + visible) end
    if iso.key_pressed(K.HOME) then cur = 1; st.scroll = 0 end
    if iso.key_pressed(K.END) then cur = #items; st.scroll = max_scroll end
  end

  -- Scrollbar (mouse only; rows keep keyboard focus).
  local sb_x = rect.x + content_w + 2
  local sb_y = list_y + 16
  local sb_h = math.max(1, view_h - 32)
  local track_x = sb_x + 4
  local track_w = 8
  if sb_w > 0 then
    if kit_input.mouse_released(0) and point_in(mx, my, sb_x, list_y, 16, 16) then
      st.scroll = math.max(0, st.scroll - 1)
    elseif kit_input.mouse_released(0) and point_in(mx, my, sb_x, list_y + view_h - 16, 16, 16) then
      st.scroll = math.min(max_scroll, st.scroll + 1)
    end
    local thumb_h = math.max(32, math.floor(sb_h * math.min(1, visible / math.max(1, #items))))
    local thumb_y = sb_y + (max_scroll > 0 and math.floor((sb_h - thumb_h) * st.scroll / max_scroll) or 0)
    if iso.mouse_pressed(0) and point_in(mx, my, track_x, thumb_y, track_w, thumb_h) then
      st.drag_thumb = true
    end
    if st.drag_thumb then
      if iso.mouse_down(0) then
        local rel = (my - sb_y - thumb_h * 0.5) / math.max(1, sb_h - thumb_h)
        st.scroll = math.max(0, math.min(max_scroll, math.floor(rel * max_scroll + 0.5)))
      else
        st.drag_thumb = false
      end
    end
    if iso.mouse_pressed(0) and point_in(mx, my, track_x, sb_y, track_w, sb_h)
        and not point_in(mx, my, track_x, thumb_y, track_w, thumb_h) then
      if my < thumb_y then st.scroll = math.max(0, st.scroll - visible)
      else st.scroll = math.min(max_scroll, st.scroll + visible) end
    end
  end

  -- If a row was activated by Enter/A in focus.update, pick it up here.
  if st.activate_idx then
    local idx = st.activate_idx
    st.activate_idx = nil
    local item = items[idx]
    if item and item.enabled ~= false then
      cur = idx
      activated = item
    end
  end

  -- Content.
  local f = theme.font("b")
  local fs = theme.font("s")
  local lh = ui.font_line_height(f)
  ui.clip(rect.x, list_y, content_w, view_h)
  for i = 1, #items do
    local item = items[i]
    local ry = list_y + (i - 1 - st.scroll) * row_h
    local row_rect = { x = rect.x, y = ry + 1, w = content_w, h = row_h - 2 }
    local is_sel = (i == cur)
    local enabled = item.enabled ~= false

    if (i % 2) == 0 then
      theme.set_color(theme.colors.bg_dark, 0.35)
      ui.rect(row_rect.x, row_rect.y, row_rect.w, row_rect.h)
    end
    if is_sel then
      theme.set_color(theme.colors.bg_hi, 0.95)
      ui.rect(row_rect.x, row_rect.y, row_rect.w, row_rect.h)
      theme.set_color(theme.colors.accent)
      ui.rect(row_rect.x, row_rect.y, 4, row_rect.h)
    end

    local tx = row_rect.x + 12
    if item.icon then
      local spec = glyph_spec(item.icon)
      if spec then
        local gw = glyphs.measure(spec, 20)
        glyphs.draw(spec, tx, ry + math.floor((row_h - 20) * 0.5), 20)
        tx = tx + gw + 8
      end
    end
    local right = item.right or item.sub
    local right_w = right and math.max(40, ui.text_width(fs, right) + 12) or 0
    local col = enabled and theme.colors.text or theme.colors.disabled
    M.label(f, M.ellipsize(f, item.label or "", row_rect.w - (tx - row_rect.x) - right_w - 12),
      tx, ry + math.floor((row_h - lh) * 0.5), row_rect.w - (tx - row_rect.x) - right_w - 12, col, 0)
    if right then
      M.label(fs, M.ellipsize(fs, right, right_w), row_rect.x + row_rect.w - right_w - 8,
        ry + math.floor((row_h - ui.font_line_height(fs)) * 0.5), right_w, theme.colors.text_dim, 2)
    end
    if not enabled then
      theme.set_color(theme.colors.disabled, 0.7)
      ui.rect(tx, ry + math.floor(row_h * 0.5), math.max(8, row_rect.w - 24), 1)
    end

    focus.register({
      id = id .. "#row" .. i,
      rect = { x = row_rect.x, y = ry, w = row_rect.w, h = row_h },
      enabled = enabled or opts.allow_disabled_focus ~= false,
      sub_group = opts.sub_group,
      nav = item.nav,
      on_activate = function() st.activate_idx = i end,
      on_dir = function(dir)
        if opts.on_row_dir then return opts.on_row_dir(item, i, dir) end
        return false
      end,
    })
  end
  ui.clip_off()

  -- One focusable element for the list itself is not needed: rows carry focus,
  -- PageUp/Down and Home/End are handled while any row is focused.

  if #items == 0 then
    M.label(fs, opts.empty_text or i18n.t("ui.list.empty"), rect.x + 12, list_y + 8, content_w - 24,
      theme.colors.text_dim, 1)
  end

  if sb_w > 0 and #items > 0 then
    theme.set_color(theme.colors.bg_dark, 0.9)
    ui.rect(sb_x, list_y, 16, view_h)
    theme.set_color(theme.colors.edge)
    ui.rect(track_x, sb_y, track_w, sb_h)
    local thumb_h = math.max(32, math.floor(sb_h * math.min(1, visible / math.max(1, #items))))
    local thumb_y = sb_y + (max_scroll > 0 and math.floor((sb_h - thumb_h) * st.scroll / max_scroll) or 0)
    theme.set_color(theme.colors.text_dim)
    ui.rect(track_x, thumb_y, track_w, thumb_h)
    M.label(fs, "^", sb_x + 1, list_y + 1, 14, theme.colors.text_dim, 1)
    M.label(fs, "v", sb_x + 1, list_y + view_h - 16, 14, theme.colors.text_dim, 1)
  end

  -- Tooltip for the hovered/focused row, after clip_off (§4.8).
  for i = 1, #items do
    local rid = id .. "#row" .. i
    if focus.is_hovered(rid) or focus.is_focused(rid) then
      local item = items[i]
      local ry = list_y + (i - 1 - st.scroll) * row_h
      if i > st.scroll and i <= st.scroll + visible then
        M.tooltip(rid .. "#tip", { x = rect.x, y = ry, w = content_w, h = row_h },
          item.tooltip or { title = item.label, body = item.desc },
          { hover = focus.is_hovered(rid), focus = focus.is_focused(rid) })
      end
      break
    end
  end
  return cur, activated
end

-- ------------------------------------------------------------------ ItemGrid (§4.9)
local function grid_slot_rect(rect, idx, cols, slot, gap)
  local col = (idx - 1) % cols
  local row = math.floor((idx - 1) / cols)
  return { x = rect.x + col * (slot + gap), y = rect.y + row * (slot + gap), w = slot, h = slot }
end

local function grid_cell_at(rect, cols, rows, slot, gap, mx, my)
  for i = 1, cols * rows do
    local r = grid_slot_rect(rect, i, cols, slot, gap)
    if point_in(mx, my, r.x, r.y, r.w, r.h) then return i end
  end
  return nil
end

function M.item_grid(id, rect, cols, rows, items, cursor, opts)
  opts = opts or {}
  items = items or {}
  local st = ensure_state(M._grids, id)
  local slot = opts.slot or theme.layout.slot
  local gap = opts.gap or theme.layout.slot_gap
  local mx, my = ui.mouse_pos()
  local t = now()
  local event = nil
  if not st.cursor then st.cursor = cursor or 1 end
  if cursor then st.cursor = cursor end
  if not st.held then st.held = nil end
  local cur = st.cursor

  local function item_at(i)
    local it = items[i]
    if type(it) == "table" then return it end
    return nil
  end

  -- Mouse button edges.
  if iso.mouse_pressed(0) then
    local idx = grid_cell_at(rect, cols, rows, slot, gap, mx, my)
    if idx then
      st.press_idx = idx
      st.press_x, st.press_y = mx, my
      st.drag_started = false
    end
  end
  if iso.mouse_pressed(1) then
    local idx = grid_cell_at(rect, cols, rows, slot, gap, mx, my)
    if st.held then
      st.held = nil
      event = { kind = "cancel", index = idx }
    elseif idx then
      event = { kind = "secondary", index = idx }
    end
  end
  if iso.mouse_down(0) and st.press_idx and not st.drag_started then
    local dx, dy = mx - (st.press_x or 0), my - (st.press_y or 0)
    if dx * dx + dy * dy >= 36 then st.drag_started = true end
  end
  if kit_input.mouse_released(0) and st.press_idx then
    local target = grid_cell_at(rect, cols, rows, slot, gap, mx, my)
    local shift = iso.key_down(K.LEFT_SHIFT) or iso.key_down(K.RIGHT_SHIFT)
    if st.drag_started then
      if target and target ~= st.press_idx then
        event = { kind = shift and "transfer" or "move", from = st.press_idx, to = target }
      end
    elseif target and target == st.press_idx then
      if st.held == target then
        st.held = nil
      elseif st.held then
        event = { kind = shift and "transfer" or "move", from = st.held, to = target }
        st.held = nil
      elseif shift then
        event = { kind = "transfer", index = target }
      else
        st.held = target
        event = { kind = "select", index = target }
        if st.last_click == target and (t - (st.last_t or -100)) < 0.35 then
          event = { kind = "activate", index = target }
          st.held = nil
        end
        st.last_click = target
        st.last_t = t
      end
    end
    st.press_idx = nil
    st.drag_started = false
  end

  -- Keyboard focus: one element per cell with explicit grid navigation.
  for i = 1, cols * rows do
    local item = item_at(i) or {}
    local cell = grid_slot_rect(rect, i, cols, slot, gap)
    local nav = {}
    if (i - 1) % cols > 0 then nav.left = id .. "#cell" .. (i - 1) end
    if (i - 1) % cols < cols - 1 then nav.right = id .. "#cell" .. (i + 1) end
    if i > cols then nav.up = id .. "#cell" .. (i - cols) end
    if i + cols <= cols * rows then nav.down = id .. "#cell" .. (i + cols) end
    focus.register({
      id = id .. "#cell" .. i,
      rect = cell,
      enabled = item.enabled ~= false,
      sub_group = opts.sub_group,
      nav = nav,
      on_activate = function()
        if st.held and st.held ~= i then
          event = { kind = "move", from = st.held, to = i }
          st.held = nil
        elseif st.held == i then
          st.held = nil
        else
          st.held = i
          event = { kind = "select", index = i }
        end
        st.cursor = i
      end,
    })
    if focus.is_focused(id .. "#cell" .. i) then
      st.cursor = i
      cur = i
      if input.pressed("ui_secondary") then event = { kind = "transfer", index = i } end
      if input.pressed("ui_info") then event = { kind = "secondary", index = i } end
    end
  end

  -- Draw.
  for i = 1, cols * rows do
    local cell = grid_slot_rect(rect, i, cols, slot, gap)
    local item = item_at(i)
    local focused = focus.is_focused(id .. "#cell" .. i)
    local hovered = focus.is_hovered(id .. "#cell" .. i)
    local is_cur = (i == cur)
    local enabled = not item or item.enabled ~= false

    theme.nine("row", cell.x, cell.y, cell.w, cell.h)
    if not enabled then
      theme.set_color(theme.colors.bg_dark, 0.55)
      ui.rect(cell.x + 2, cell.y + 2, cell.w - 4, cell.h - 4)
    end
    if item then
      local icon = item.icon
      if type(icon) == "number" then
        ui.image(icon, 0, 0, 32, 32, cell.x + 8, cell.y + 6, 32, 32)
      elseif icon then
        local spec = glyph_spec(icon)
        if spec then
          local gw, gh = glyphs.measure(spec, 32)
          glyphs.draw(spec, cell.x + math.floor((cell.w - gw) * 0.5),
            cell.y + math.floor((cell.h - gh) * 0.5) - 2, 32)
        end
      end
      if item.qty and item.qty ~= 1 then
        M.label(theme.font("s"), tostring(item.qty), cell.x + 2, cell.y + cell.h - 16, cell.w - 4,
          theme.colors.text, 2)
      end
      if item.too_heavy then
        theme.set_color(theme.colors.danger)
        ui.rect(cell.x, cell.y, cell.w, 1)
        ui.rect(cell.x, cell.y + cell.h - 1, cell.w, 1)
        ui.rect(cell.x, cell.y, 1, cell.h)
        ui.rect(cell.x + cell.w - 1, cell.y, 1, cell.h)
      end
      if not enabled then
        theme.set_color(theme.colors.disabled)
        ui.rect(cell.x + 6, cell.y + math.floor(cell.h * 0.5), cell.w - 12, 1)
      end
    end
    if is_cur then
      theme.set_color(theme.colors.accent)
      ui.rect(cell.x - 2, cell.y - 2, cell.w + 4, 2)
      ui.rect(cell.x - 2, cell.y + cell.h, cell.w + 4, 2)
      ui.rect(cell.x - 2, cell.y, 2, cell.h)
      ui.rect(cell.x + cell.w, cell.y, 2, cell.h)
    end
    if st.held == i then
      -- dashed "held" outline
      theme.set_color(theme.colors.accent, 0.9)
      local dash = 6
      local xx = cell.x
      while xx < cell.x + cell.w do
        ui.rect(xx, cell.y - 1, math.min(dash, cell.x + cell.w - xx), 1)
        xx = xx + dash + 4
      end
      xx = cell.x
      while xx < cell.x + cell.w do
        ui.rect(xx, cell.y + cell.h, math.min(dash, cell.x + cell.w - xx), 1)
        xx = xx + dash + 4
      end
    end
    if (focused or hovered) and item then
      M.tooltip(id .. "#cell" .. i .. "#tip", cell,
        item.tooltip or { title = item.label or "", body = item.desc },
        { hover = hovered, focus = focused })
    end
  end

  -- Drag ghost follows the cursor.
  if st.drag_started and st.press_idx then
    local item = item_at(st.press_idx)
    if item then
      local spec = glyph_spec(item.icon)
      if spec then glyphs.draw(spec, mx - 16, my - 16, 32) end
    end
  end

  return cur, event
end

-- ------------------------------------------------------------------ Modal (§4.12)
local function modal_top_is(id)
  local top = focus.groups[#focus.groups]
  return top and top.id == "modal:" .. id
end

function M.modal_is_open(id)
  return M._modals[id] ~= nil
end

function M.any_modal_open()
  return #M._modal_order > 0
end

function M.close_modal(id, result)
  local st = M._modals[id]
  if not st then return end
  M._modals[id] = nil
  for i, v in ipairs(M._modal_order) do
    if v == id then table.remove(M._modal_order, i) break end
  end
  if modal_top_is(id) then focus.pop_group() end
  M._modal_results[id] = result or "cancel"
end

function M.modal(id, spec)
  spec = spec or {}
  local result = M._modal_results[id]
  if result then
    M._modal_results[id] = nil
    return result
  end

  local st = M._modals[id]
  if not st then
    if #M._modal_order > 0 then return nil end -- queued: caller retries
    st = {}
    M._modals[id] = st
    M._modal_order[#M._modal_order + 1] = id
    focus.push_group("modal:" .. id, {
      modal = true,
      default = spec.default,
      on_cancel = function() M.close_modal(id, spec.cancel_result or "cancel") end,
    })
  end
  st.spec = spec

  local sw, sh = ui.screen_size()
  local f = theme.font("b")
  local ft = theme.font("t")
  local fs = theme.font("s")
  local lh = ui.font_line_height(f)

  local w = spec.width or 560
  w = math.max(480, math.min(720, math.min(w, sw - 64)))
  local body = spec.body
  local body_h = body and ui.text_measure(fs, body, w - 48).h or 0
  local h = spec.height or (24 + ui.font_line_height(ft) + 12 + body_h + 20 + 40 + 24)
  h = math.min(h, sh - 64)
  local px = math.floor((sw - w) * 0.5)
  local py = math.floor((sh - h) * 0.5)

  M.modal_dim()
  M.panel(px, py, w, h, 0.98)
  M.label(ft, spec.title or "", px + 24, py + 16, w - 48, theme.colors.text, 0)
  if body then
    local cy = py + 16 + ui.font_line_height(ft) + 12
    theme.set_color(theme.colors.text)
    ui.text_box(fs, body, px + 24, cy, w - 48, 0, -1)
  end

  local buttons = spec.buttons or {
    { id = "ok", label = i18n.t("ui.ok"), variant = "primary", default = true },
  }
  local bw = spec.button_w or 120
  local bh = 40
  local gap = 12
  local total = #buttons * bw + math.max(0, #buttons - 1) * gap
  local bx = px + w - 24 - total
  local by = py + h - 24 - bh

  local hold_btn = nil
  for _, b in ipairs(buttons) do if b.hold then hold_btn = b end end

  st.hold_t = st.hold_t or 0
  local dt = math.max(0, now() - (st.hold_last or now()))
  st.hold_last = now()

  focus.set_target("modal:" .. id)
  for i, b in ipairs(buttons) do
    local br = { x = bx + (i - 1) * (bw + gap), y = by, w = bw, h = bh }
    local bid = id .. "#btn#" .. b.id
    local is_hold = b.hold
    M.button(bid, br, b.label, {
      variant = b.variant,
      enabled = b.enabled ~= false,
      sub_group = "modal_buttons",
      on_click = (not is_hold) and function() st.pending = b.id end or nil,
    })
    if b.default and not spec.default then
      spec.default = bid
      local top = focus.groups[#focus.groups]
      if top and top.default == nil then top.default = bid; top.remember = bid end
    end
    if is_hold then
      local mx, my = ui.mouse_pos()
      local holding = (point_in(mx, my, br.x, br.y, br.w, br.h) and iso.mouse_down(0))
        or (focus.is_focused(bid) and input.down("confirm"))
      if holding then
        st.hold_t = st.hold_t + dt
      else
        st.hold_t = 0
      end
      local dur = spec.hold_duration or 0.8
      if st.hold_t >= dur then
        st.pending = b.id
      end
      local ratio = math.max(0, math.min(1, st.hold_t / dur))
      theme.set_color(theme.colors.accent, 0.85)
      ui.rect(br.x + 2, br.y + br.h - 4, math.floor((br.w - 4) * ratio), 3)
    end
  end

  -- Dim click cancels non-dangerous modals only (§4.12).
  if not spec.no_dim_cancel then
    local mx, my = ui.mouse_pos()
    if kit_input.mouse_released(0) and not point_in(mx, my, px, py, w, h) then
      st.pending = spec.cancel_result or "cancel"
    end
  end

  if st.pending then
    local r = st.pending
    st.pending = nil
    focus.clear_target()
    M.close_modal(id, r)
    return r
  end
  focus.clear_target()
  return nil
end

-- ------------------------------------------------------------------ Confirm (§4.13)
function M.confirm(id, spec)
  spec = spec or {}
  local buttons = {
    { id = "cancel", label = spec.cancel_label or i18n.t("ui.cancel"), default = true },
    { id = "confirm", label = spec.confirm_label or i18n.t("ui.confirm"),
      variant = spec.danger and "danger" or "primary", hold = spec.hold_confirm },
  }
  local r = M.modal(id, {
    title = spec.title or i18n.t("ui.confirm"),
    body = spec.body,
    width = spec.width or 520,
    height = spec.height,
    buttons = buttons,
    default = id .. "#btn#cancel",
    cancel_result = "cancel",
    no_dim_cancel = spec.danger or spec.no_dim_cancel,
    hold_duration = spec.hold_duration,
  })
  if r == "confirm" then return "confirm" end
  if r == "cancel" then return "cancel" end
  return nil
end

-- ------------------------------------------------------------------ Radial (§4.14)
local function radial_angle_index(dx, dy, n)
  local a = math.atan(dy, dx) + math.pi * 0.5
  if a < 0 then a = a + math.pi * 2 end
  local sector = math.pi * 2 / n
  return math.floor(a / sector) % n + 1
end

function M.radial_is_open(id)
  return M._radials[id] ~= nil
end

function M.close_radial(id, result)
  local st = M._radials[id]
  if not st then return end
  M._radials[id] = nil
  local top = focus.groups[#focus.groups]
  if top and top.id == "radial:" .. id then focus.pop_group() end
  M._radial_results[id] = result or { action = "cancel" }
end

function M.radial(id, spec)
  spec = spec or {}
  local result = M._radial_results[id]
  if result then
    M._radial_results[id] = nil
    return result
  end

  local st = M._radials[id]
  if not st then
    if #M._modal_order > 0 or next(M._radials) then return nil end
    if #(spec.items or {}) < 2 then return { action = "cancel" } end
    if #(spec.items or {}) > 8 then return { action = "too_many" } end
    st = { sel = math.max(1, math.min(#spec.items, spec.selected or 1)) }
    M._radials[id] = st
    focus.push_group("radial:" .. id, {
      modal = true,
      on_cancel = function() M.close_radial(id, { action = "cancel" }) end,
    })
  end
  st.spec = spec
  local items = spec.items or {}
  local n = #items

  local sw, sh = ui.screen_size()
  local cx, cy = spec.center and spec.center[1] or math.floor(sw * 0.5), spec.center and spec.center[2] or math.floor(sh * 0.5)
  local R = spec.radius or 112
  local inner = spec.inner or 40

  -- Keyboard: arrows pick the cardinal sector, digits pick 1..8.
  if not spec.preview then
    if input.pressed("ui_up") then st.sel = 1 end
    if input.pressed("ui_right") then st.sel = math.max(1, math.floor(n / 4) + 1) end
    if input.pressed("ui_down") then st.sel = math.max(1, math.floor(n / 2) + 1) end
    if input.pressed("ui_left") then st.sel = math.max(1, math.floor(n * 3 / 4) + 1) end
    for i = 1, math.min(n, 8) do
      local code = K["_" .. i]
      if code and iso.key_pressed(code) then st.sel = i end
    end

    -- Gamepad left stick direction.
    if pad and PA.lx and PA.ly then
      local lx, ly = pad.axis(PA.lx), pad.axis(PA.ly)
      if lx * lx + ly * ly >= 0.16 then
        st.sel = radial_angle_index(lx, ly, n)
      end
    end
  end

  -- Mouse choose on release.
  local mx, my = ui.mouse_pos()
  local dx, dy = mx - cx, my - cy
  local dist = math.sqrt(dx * dx + dy * dy)
  if not spec.preview and kit_input.mouse_released(0) then
    if dist < inner or dist > R + 48 then
      M.close_radial(id, { action = "cancel" })
      return { action = "cancel" }
    end
    st.sel = radial_angle_index(dx, dy, n)
    M.close_radial(id, { action = "select", item_id = items[st.sel] and items[st.sel].id, index = st.sel })
    return { action = "select", item_id = items[st.sel] and items[st.sel].id, index = st.sel }
  end

  if input.pressed("confirm") then
    local it = items[st.sel]
    M.close_radial(id, { action = "select", item_id = it and it.id, index = st.sel })
    return { action = "select", item_id = it and it.id, index = st.sel }
  end

  -- Draw dim + ring + sectors.
  ui.color(0, 0, 0, 0.35)
  ui.rect(0, 0, sw, sh)
  for i = 0, 47 do
    local a = i / 48 * math.pi * 2
    theme.set_color(theme.colors.edge, 0.8)
    ui.rect(cx + math.cos(a) * R - 2, cy + math.sin(a) * R - 2, 4, 4)
  end

  local icon_size = 32
  for i, it in ipairs(items) do
    local a = -math.pi * 0.5 + (i - 1) * math.pi * 2 / n
    local ix = cx + math.cos(a) * R
    local iy = cy + math.sin(a) * R
    local box = { x = math.floor(ix - icon_size * 0.5), y = math.floor(iy - icon_size * 0.5), w = icon_size, h = icon_size }
    if i == st.sel then
      theme.set_color(theme.colors.bg_hi, 0.95)
      ui.rect(box.x - 4, box.y - 4, box.w + 8, box.h + 8)
      theme.set_color(theme.colors.accent)
      ui.rect(box.x - 4, box.y - 4, box.w + 8, 2)
      ui.rect(box.x - 4, box.y + box.h + 2, box.w + 8, 2)
    end
    local spec_glyph = glyph_spec(it.icon)
    if spec_glyph then
      local gw, gh = glyphs.measure(spec_glyph, icon_size)
      glyphs.draw(spec_glyph, box.x + math.floor((box.w - gw) * 0.5),
        box.y + math.floor((box.h - gh) * 0.5), icon_size)
    end
    local f = theme.font("s")
    local label = it.label or ""
    local ly = iy + icon_size * 0.5 + 6
    if math.sin(a) < -0.2 then ly = iy - icon_size * 0.5 - 6 - ui.font_line_height(f) end
    M.label(f, M.ellipsize(f, label, 120), math.floor(ix - 60), math.floor(ly), 120,
      i == st.sel and theme.colors.accent or theme.colors.text_dim, 1)
  end

  local sel = items[st.sel]
  local label = sel and (sel.label or "") or ""
  local f = theme.font("b")
  local lw = math.max(120, ui.text_width(f, label) + 24)
  theme.nine("tip", cx - lw / 2, cy - 20, lw, 40, theme.colors.white, 0.96)
  M.label(f, M.ellipsize(f, label, lw - 16), cx - lw / 2 + 8, cy - math.floor(ui.font_line_height(f) * 0.5),
    lw - 16, theme.colors.text, 1)
  return nil
end

-- ------------------------------------------------------------------ Stepper (§4.15)
function M.stepper(id, rect, value, min_v, max_v, step, opts)
  opts = opts or {}
  min_v = min_v or 0
  max_v = max_v or 100
  step = step or 1
  local st = ensure_state(M._steppers, id)
  local changed = false
  local done = nil

  local function clamp(v)
    v = math.max(min_v, math.min(max_v, v))
    if step > 0 then v = min_v + math.floor((v - min_v) / step + 0.5) * step end
    return math.max(min_v, math.min(max_v, v))
  end
  local function setv(nv)
    nv = clamp(nv)
    if math.abs(nv - value) > 1e-6 then
      value = nv
      changed = true
      if opts.on_change then opts.on_change(value) end
    end
  end

  local bw, gap, vw = 40, 4, 64
  local total = bw * 4 + vw + gap * 4
  local label_w = 0
  if opts.label then
    label_w = math.max(0, rect.w - total - 12)
  end
  local bx = rect.x + label_w
  local by = rect.y + math.floor((rect.h - bw) * 0.5)
  local btns = {
    { key = "minus10", x = bx, delta = -10 * step, label = "−10" },
    { key = "minus", x = bx + bw + gap, delta = -step, label = "−" },
    { key = "plus", x = bx + bw * 2 + gap * 2 + vw, delta = step, label = "＋" },
    { key = "plus10", x = bx + bw * 3 + gap * 3 + vw, delta = 10 * step, label = "＋10" },
  }

  local mx, my = ui.mouse_pos()
  if opts.enabled ~= false and iso.mouse_pressed(0) then
    for _, b in ipairs(btns) do
      if point_in(mx, my, b.x, by, bw, bw) then
        st.btn = b.key
        st.t = 0
        st.next = 0
        st.last = now()
        setv(value + b.delta)
        break
      end
    end
  end
  if st.btn then
    if iso.mouse_down(0) then
      local dt = math.max(0, now() - (st.last or now()))
      st.last = now()
      st.t = (st.t or 0) + dt
      if st.t >= 0.4 then
        st.next = (st.next or 0) + dt
        while st.next >= 0.06 do
          st.next = st.next - 0.06
          for _, b in ipairs(btns) do
            if b.key == st.btn then setv(value + b.delta); break end
          end
        end
      end
    else
      st.btn = nil
      st.t = 0
      st.next = 0
    end
  end

  focus.register({
    id = id,
    rect = rect,
    enabled = opts.enabled ~= false,
    sub_group = opts.sub_group,
    on_activate = function() done = "confirm" end,
    on_dir = function(dir)
      local big = (iso.key_down(K.LEFT_SHIFT) or iso.key_down(K.RIGHT_SHIFT))
        or (pad and pad_buttons and (pad.button_down(pad_buttons.lb) or pad.button_down(pad_buttons.rb)))
      local d = big and 10 * step or step
      if dir == "left" then setv(value - d); return true end
      if dir == "right" then setv(value + d); return true end
      return false
    end,
  })

  if focus.is_focused(id) then
    local shift = iso.key_down(K.LEFT_SHIFT) or iso.key_down(K.RIGHT_SHIFT)
    -- Shift+arrow does not reach `ui_left/right` because the action bindings are
    -- un-modified; handle the documented ±10 shortcut directly.
    if shift and iso.key_pressed(K.RIGHT) then setv(value + 10 * step) end
    if shift and iso.key_pressed(K.LEFT) then setv(value - 10 * step) end
    if iso.key_pressed(K.HOME) then setv(min_v) end
    if iso.key_pressed(K.END) then setv(max_v) end
    if input.pressed("ui_page_prev") then setv(value - 10 * step) end
    if input.pressed("ui_page_next") then setv(value + 10 * step) end
    if input.pressed("cancel") then done = "cancel" end
    if input.pressed("confirm") then done = "confirm" end
  end

  if opts.label then
    local f = theme.font("b")
    M.label(f, M.ellipsize(f, opts.label, label_w - 8), rect.x, rect.y + math.floor((rect.h - ui.font_line_height(f)) * 0.5),
      label_w - 8, theme.colors.text, 0)
  end
  for _, b in ipairs(btns) do
    local enabled = opts.enabled ~= false
    local hovered = enabled and point_in(mx, my, b.x, by, bw, bw)
    theme.nine(hovered and "btn_hover" or "btn_normal", b.x, by, bw, bw)
    local f = theme.font("b")
    M.label(f, b.label, b.x + 2, by + math.floor((bw - ui.font_line_height(f)) * 0.5), bw - 4,
      enabled and theme.colors.text or theme.colors.disabled, 1)
  end

  local f = theme.font("b")
  local vx = bx + bw * 2 + gap * 2
  theme.nine("row", vx, by, vw, bw)
  local val_txt = opts.format and opts.format(value) or tostring(math.floor(value + 0.5))
  M.label(f, val_txt, vx + 2, by + math.floor((bw - ui.font_line_height(f)) * 0.5), vw - 4,
    opts.enabled ~= false and theme.colors.text or theme.colors.disabled, 1)

  if focus.show_ring(id) then focus.draw_ring(rect) end
  return value, changed, done
end

return M
