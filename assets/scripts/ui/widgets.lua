-- Immediate-mode UI widget library (UI-UX §4).
local iso = require("iso")
local i18n = require("core.i18n")
local theme = require("ui.theme")
local focus = require("ui.focus")

local M = {
  _pressed_id = nil,
  _drag_slider = nil,
  _toast_msg = nil,
  _toast_t = 0,
}

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

return M
