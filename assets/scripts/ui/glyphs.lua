-- Key / mouse / gamepad glyph lookup and drawing (UI-UX §9.1, ART-AUDIO §7.5).
-- The lookup table is the contract other UI code uses; drawing can later switch
-- to assets/ui/glyphs.png without changing callers.
local theme = require("ui.theme")

local M = {
  _atlas = nil,
  _atlas_tried = false,
  size = 24,
}

-- Optional atlas. If ART has not delivered assets/ui/glyphs.png yet we draw
-- procedural placeholders, so callers never need to branch.
M.atlas_rects = {
  -- filled once an atlas ships; key = spec key, value = {sx,sy,sw,sh}
}

local FACE_COLORS = {
  a = "ok",
  b = "danger",
  x = "cold",
  y = "accent",
}

local KEY_WIDE = {
  ESC = true, ESCAPE = true, TAB = true, ENTER = true, RETURN = true,
  SHIFT = true, CTRL = true, SPACE = true, BACKSPACE = true, DELETE = true,
  PAGEUP = true, PAGEDOWN = true, HOME = true, END = true,
  F1 = true, F2 = true, F3 = true, F4 = true, F5 = true, F6 = true,
  F7 = true, F8 = true, F9 = true, F10 = true, F11 = true, F12 = true,
}

local MOUSE_LABELS = { [0] = "L", [1] = "R", [2] = "M" }
local MOUSE_BTN = { left = 0, right = 1, middle = 2 }
local MOUSE_NAME = { [0] = "left", [1] = "right", [2] = "middle" }

local function ensure_atlas()
  -- ART has not delivered assets/ui/glyphs.png yet. Do not probe for it every
  -- run (a missing image logs an engine error); ART can opt in via use_atlas().
  return M._atlas
end

-- Called by ART/UI bootstrap once the glyph atlas exists.
function M.use_atlas(path)
  local h = ui.image_load(path or "assets/ui/glyphs.png")
  if h and h > 0 then
    M._atlas = h
    return true
  end
  return false
end

local function key_label(name)
  name = tostring(name or "")
  if name == "LEFT_BRACKET" then return "[" end
  if name == "RIGHT_BRACKET" then return "]" end
  if name == "RIGHT" then return "R" end
  if name == "LEFT" then return "L" end
  if name == "UP" then return "U" end
  if name == "DOWN" then return "D" end
  if name == "ESCAPE" then return "Esc" end
  if name == "ENTER" then return "Enter" end
  if name == "BACKSPACE" then return "Bksp" end
  if name == "LEFT_SHIFT" or name == "RIGHT_SHIFT" then return "Shift" end
  if name == "LEFT_CONTROL" or name == "RIGHT_CONTROL" then return "Ctrl" end
  if name == "SPACE" then return "Space" end
  if name == "PAGE_UP" then return "PgUp" end
  if name == "PAGE_DOWN" then return "PgDn" end
  return name
end

function M.key(name)
  return { kind = "key", name = tostring(name or ""), label = key_label(name), key = "key:" .. tostring(name or "") }
end

function M.key_name(code)
  if code == nil then return nil end
  for name, val in pairs(keys or {}) do
    if val == code then return name end
  end
  return "K" .. tostring(code)
end

-- Mouse glyph. `btn` is a number (0/1/2) or a name: "left" | "right" | "middle"
-- | "move" | "drag" (PANEL-PLAN §3). "move" highlights no button (arrows only);
-- "drag" is the left button plus an arrow.
function M.mouse(btn)
  local mode = nil
  if type(btn) == "string" then
    if btn == "move" then mode, btn = "move", -1
    elseif btn == "drag" then mode, btn = "drag", 0
    else btn = MOUSE_BTN[btn] or tonumber(btn) or 0 end
  end
  btn = btn or 0
  return {
    kind = "mouse", btn = btn, mode = mode,
    label = MOUSE_LABELS[btn] or "M",
    key = "mouse:" .. (mode or MOUSE_NAME[btn] or tostring(btn)),
  }
end

function M.pad(name)
  name = tostring(name or "")
  return { kind = "pad_" .. name, name = name, label = string.upper(name), key = "pad:" .. name }
end

-- Shared parser for glyph names used by widgets and the hint bar:
-- "key:<name>", "mouse:<left|right|middle|move|drag>", "pad:<name>", or a bare
-- key name. Tables (already a spec) pass through.
function M.spec(g)
  if type(g) == "table" then return g end
  if type(g) ~= "string" then return nil end
  local prefix, rest = g:match("^(%a+):(.+)$")
  if prefix == "pad" then return M.pad(rest) end
  if prefix == "key" then return M.key(rest) end
  if prefix == "mouse" then return M.mouse(rest) end
  return M.key(g)
end

function M.pad_button(btn)
  local name = M.pad_name(btn)
  return name and M.pad(name) or nil
end

function M.pad_name(btn)
  if not pad_buttons or btn == nil then return nil end
  for name, val in pairs(pad_buttons) do
    if val == btn then return name end
  end
  return nil
end

-- spec for an input binding returned by core.input.
function M.from_binding(device, b)
  if not b then return nil end
  if device == "keyboard" then
    local name = M.key_name(b.key)
    local spec = M.key(name)
    spec.shift = b.shift or false
    spec.ctrl = b.ctrl or false
    return spec
  elseif device == "mouse" then
    return M.mouse(b.btn)
  elseif device == "pad" then
    if b.axis then
      local spec = M.pad(b.axis)
      spec.dir = b.dir
      if b.dir then
        spec.label = string.upper(b.axis) .. " " .. b.dir
        spec.key = "pad:" .. b.axis .. "_" .. b.dir
      end
      return spec
    end
    local spec = M.pad_button(b.btn)
    if spec then spec.lt = b.lt or false end
    return spec
  end
  return nil
end

function M.available(device)
  if device == "pad" then
    return pad ~= nil and pad.connected() == true
  end
  return true
end

-- Primary binding spec for an action. Falls back to an explicit screen entry.
function M.for_action(entity, device)
  local input = require("core.input")
  local b = input.get_binding(device, entity, 1)
  return M.from_binding(device, b)
end

function M.measure(spec, size)
  size = size or M.size
  if not spec then return size, size end
  if spec.kind == "key" then
    local f = theme.font("s")
    local tw = ui.text_width(f, spec.label or "")
    local w = math.max(size, math.ceil(tw) + 8)
    if KEY_WIDE[spec.name] then w = math.max(w, 32) end
    if spec.name == "SPACE" then w = math.max(w, 56) end
    return w, size
  elseif spec.kind == "pad_lb" or spec.kind == "pad_rb" then
    return 32, 20
  elseif spec.kind == "pad_lt" or spec.kind == "pad_rt" then
    return 30, 24
  end
  return size, size
end

local function face_color(spec)
  local c = FACE_COLORS[spec.name] or "text_dim"
  return theme.colors[c] or theme.colors.text_dim
end

local function centered_text(txt, x, y, w, h, col, font)
  local f = font or theme.font("s")
  local tw = ui.text_width(f, txt)
  local th = ui.font_line_height(f)
  theme.set_color(col or theme.colors.text)
  ui.text(f, txt, math.floor(x + (w - tw) * 0.5), math.floor(y + (h - th) * 0.5))
end

local function draw_key(spec, x, y, w, h)
  theme.nine("btn_normal", x, y, w, h, theme.colors.white, 1.0)
  theme.set_color(theme.colors.edge)
  ui.rect(x, y, w, 1)
  ui.rect(x, y + h - 1, w, 1)
  ui.rect(x, y, 1, h)
  ui.rect(x + w - 1, y, 1, h)
  local label = spec.label or ""
  centered_text(label, x, y + 1, w, h - 1, theme.colors.text, theme.font("s"))
end

local function draw_mouse(spec, x, y, size)
  local h = size
  theme.set_color(theme.colors.bg_dark)
  ui.rect(x + 4, y + 2, size - 8, h - 2)
  theme.set_color(theme.colors.edge)
  ui.rect(x + 4, y + 2, size - 8, 1)
  ui.rect(x + 4, y + h - 1, size - 8, 1)
  ui.rect(x + 4, y + 2, 1, h - 2)
  ui.rect(x + size - 5, y + 2, 1, h - 2)
  -- split line and highlighted button half
  theme.set_color(theme.colors.text_dim)
  ui.rect(x + size / 2 - 1, y + 2, 1, h - 2)
  local col = theme.colors.accent
  theme.set_color(col)
  if spec.mode == "move" then
    -- four arrow ticks around the body
    local mid = math.floor(size / 2)
    ui.rect(x, y + mid - 1, 3, 2)
    ui.rect(x + size - 3, y + mid - 1, 3, 2)
    ui.rect(x + mid - 1, y, 2, 2)
    ui.rect(x + mid - 1, y + h - 2, 2, 2)
    return
  end
  if spec.btn == 0 then
    ui.rect(x + 5, y + 3, size / 2 - 6, (h - 6) * 0.5)
  elseif spec.btn == 1 then
    ui.rect(x + size / 2, y + 3, size / 2 - 5, (h - 6) * 0.5)
  else
    ui.rect(x + size / 2 - 2, y + h * 0.55, 4, h * 0.35)
  end
  if spec.mode == "drag" then
    -- arrow: tail + head at the lower right
    ui.rect(x + size - 12, y + h - 5, 10, 2)
    ui.rect(x + size - 5, y + h - 8, 2, 8)
  end
end

local function draw_pad_face(spec, x, y, size)
  local c = face_color(spec)
  theme.set_color(theme.colors.bg_dark)
  ui.rect(x + 1, y + 1, size - 2, size - 2)
  theme.set_color(c)
  ui.rect(x + 3, y + 3, size - 6, size - 6)
  theme.set_color(theme.colors.bg_dark, 0.35)
  ui.rect(x + 3, y + 3, size - 6, 2)
  centered_text(string.upper(spec.name), x, y, size, size, theme.colors.white, theme.font("b"))
end

local function draw_pad_shoulder(spec, x, y, w, h, trigger)
  theme.set_color(theme.colors.bg_dark)
  ui.rect(x, y, w, h)
  theme.set_color(theme.colors.edge)
  ui.rect(x, y, w, 1)
  ui.rect(x, y + h - 1, w, 1)
  if trigger then
    theme.set_color(theme.colors.bg_hi)
    ui.rect(x + 2, y + 2, w - 4, h - 5)
  end
  centered_text(string.upper(spec.name), x, y, w, h, theme.colors.text, theme.font("s"))
end

local function draw_dpad(spec, x, y, size)
  local arm = math.floor(size / 3)
  theme.set_color(theme.colors.bg_dark)
  ui.rect(x + arm, y + arm, arm, arm) -- center
  theme.set_color(theme.colors.edge)
  ui.rect(x + arm, y, arm, arm)
  ui.rect(x + arm, y + arm * 2, arm, arm)
  ui.rect(x, y + arm, arm, arm)
  ui.rect(x + arm * 2, y + arm, arm, arm)
  theme.set_color(theme.colors.accent)
  if spec.name == "dpad_up" then ui.rect(x + arm, y, arm, arm)
  elseif spec.name == "dpad_down" then ui.rect(x + arm, y + arm * 2, arm, arm)
  elseif spec.name == "dpad_left" then ui.rect(x, y + arm, arm, arm)
  elseif spec.name == "dpad_right" then ui.rect(x + arm * 2, y + arm, arm, arm)
  else ui.rect(x + arm, y + arm, arm, arm) end
end

local function draw_stick(spec, x, y, size)
  theme.set_color(theme.colors.bg_dark)
  ui.rect(x + 2, y + 2, size - 4, size - 4)
  theme.set_color(theme.colors.edge)
  ui.rect(x + 4, y + 4, size - 8, size - 8)
  local col = theme.colors.text_dim
  if spec.name == "l3" or spec.name == "r3" then col = theme.colors.accent end
  theme.set_color(col)
  local inner = math.floor((size - 8) * 0.5)
  ui.rect(x + math.floor(size * 0.5 - inner * 0.5), y + math.floor(size * 0.5 - inner * 0.5), inner, inner)
  centered_text(spec.name == "rs" and "R" or "L", x, y, size, size, theme.colors.text, theme.font("s"))
  if spec.dir then
    -- direction tick on the matching edge
    local mid = math.floor(size / 2)
    theme.set_color(theme.colors.accent)
    if spec.dir == "up" then ui.rect(x + mid - 3, y, 6, 3)
    elseif spec.dir == "down" then ui.rect(x + mid - 3, y + size - 3, 6, 3)
    elseif spec.dir == "left" then ui.rect(x, y + mid - 3, 3, 6)
    elseif spec.dir == "right" then ui.rect(x + size - 3, y + mid - 3, 3, 6) end
  end
end

local function draw_start_back(spec, x, y, size)
  theme.set_color(theme.colors.bg_dark)
  ui.rect(x + 2, y + 5, size - 4, size - 10)
  theme.set_color(theme.colors.edge)
  ui.rect(x + 2, y + 5, size - 4, 1)
  ui.rect(x + 2, y + size - 6, size - 4, 1)
  theme.set_color(theme.colors.text)
  if spec.name == "start" then
    ui.rect(x + 6, y + 9, size - 12, 2)
    ui.rect(x + 6, y + 13, size - 12, 2)
    ui.rect(x + 6, y + 17, size - 12, 2)
  else
    ui.rect(x + 7, y + 9, 4, 4)
    ui.rect(x + size - 11, y + 9, 4, 4)
    ui.rect(x + 7, y + 15, 4, 4)
    ui.rect(x + size - 11, y + 15, 4, 4)
  end
end

-- Draw one glyph. Returns its measured width and height.
function M.draw(spec, x, y, size, opts)
  if not spec then return 0, 0 end
  size = size or M.size
  ensure_atlas()

  local w, h = M.measure(spec, size)
  local ar = M._atlas and M.atlas_rects[spec.key]
  if ar then
    ui.image(M._atlas, ar[1], ar[2], ar[3], ar[4], x, y, w, h)
  elseif spec.kind == "key" then
    draw_key(spec, x, y, w, h)
    if spec.shift or spec.ctrl then
      local mod = spec.ctrl and "Ctrl+" or "Shift+"
      theme.set_color(theme.colors.text_dim)
      ui.text(theme.font("s"), mod, x, y - 2)
    end
  elseif spec.kind == "mouse" then
    draw_mouse(spec, x, y, size)
  elseif spec.kind == "pad_lb" or spec.kind == "pad_rb" then
    draw_pad_shoulder(spec, x, y, 32, 20, false)
  elseif spec.kind == "pad_lt" or spec.kind == "pad_rt" then
    draw_pad_shoulder(spec, x, y, 30, 24, true)
  elseif spec.kind == "pad_dpad_up" or spec.kind == "pad_dpad_down" or
         spec.kind == "pad_dpad_left" or spec.kind == "pad_dpad_right" then
    draw_dpad(spec, x, y, size)
  elseif spec.kind == "pad_l3" or spec.kind == "pad_r3" or spec.kind == "pad_ls" or spec.kind == "pad_rs" then
    draw_stick(spec, x, y, size)
  elseif spec.kind == "pad_start" or spec.kind == "pad_back" then
    draw_start_back(spec, x, y, size)
  else
    draw_pad_face(spec, x, y, size)
  end
  return w, h
end

function M.draw_plus(x, y, h, col)
  theme.set_color(col or theme.colors.text_dim)
  local s = math.max(6, math.floor(h * 0.4))
  ui.rect(x, y + math.floor((h - 2) * 0.5), s, 2)
  ui.rect(x + math.floor((s - 2) * 0.5), y + math.floor((h - s) * 0.5), 2, s)
end

function M.reset_atlas()
  M._atlas = nil
  M._atlas_tried = false
end
return M
