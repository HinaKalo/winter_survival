-- Context hint bar (UI-UX §9.2). Pure presentation: reads input bindings,
-- never rebinds or mutates input state.
local i18n = require("core.i18n")
local input = require("core.input")
local theme = require("ui.theme")
local glyphs = require("ui.glyphs")

local M = {
  stack = {},
  _override = nil,
}

local function hint(action, text, extra)
  local h = { action = action, text = text }
  if extra then
    for k, v in pairs(extra) do h[k] = v end
  end
  return h
end

-- UI-UX §9.2 context presets. `show_if`/`target` are resolved at draw time.
function M.preset(name)
  if name == "home_idle" then
    return {
      hint("move_dir", "hint.move"),
      hint("pause", "hint.pause"),
      hint("select_next", "hint.select"),
      hint("open_map", "hint.map"),
    }
  elseif name == "home_focus" then
    return {
      hint("interact", "hint.interact"),
      hint("context", "hint.command"),
      hint("focus_next", "hint.focus_next"),
      hint("pause", "hint.pause"),
    }
  elseif name == "raid" then
    return {
      hint("move_dir", "hint.move"),
      hint("sneak_toggle", "hint.sneak"),
      hint("run_hold", "hint.run"),
      hint("interact", "hint.interact"),
      hint("squad_wheel", "hint.squad"),
      hint("pause", "hint.pause"),
      hint("evacuate", "hint.evacuate", { show_if = false }),
    }
  elseif name == "combat" then
    return {
      hint("attack", "hint.attack"),
      hint("takedown", "hint.takedown"),
      hint("squad_wheel", "hint.squad"),
      hint("pause", "hint.continue"),
    }
  elseif name == "menu" then
    return {
      hint("confirm", "hint.confirm"),
      hint("cancel", "hint.back"),
      hint("ui_page_next", "hint.page"),
      hint("ui_info", "hint.details"),
    }
  elseif name == "dialog" then
    return {
      hint("confirm", "hint.continue"),
      hint("ui_up", "hint.select_option"),
      hint("ui_info", "hint.details"),
    }
  elseif name == "drag" then
    return {
      hint("confirm", "hint.drop"),
      hint("cancel", "hint.cancel"),
      hint("ui_secondary", "hint.transfer"),
    }
  elseif name == "cursor" then
    return {
      hint("confirm", "hint.click"),
      hint("context", "hint.right_click"),
      hint("cancel", "hint.exit"),
    }
  end
  return {}
end

function M.push(name, hints)
  M.stack[#M.stack + 1] = { name = name, hints = hints or M.preset(name) }
end

function M.pop()
  return table.remove(M.stack)
end

function M.clear()
  M.stack = {}
end

function M.current()
  return M.stack[#M.stack]
end

function M.set_device_override(device)
  M._override = device
end

function M.device()
  if M._override and glyphs.available(M._override) then
    return M._override
  end
  local dev = input.last_device()
  if dev == "pad" and not glyphs.available("pad") then
    return "keyboard"
  end
  return dev
end

local function fallback_glyph(action, device)
  -- Actions added by P0-3 are not in core/input.lua yet; show their documented
  -- default glyphs so the hint bar is complete before P0 lands.
  local table_ = {
    move_dir = { keyboard = glyphs.key("W"), mouse = glyphs.mouse(0), pad = glyphs.pad("ls") },
    select_next = { keyboard = glyphs.key("TAB"), mouse = glyphs.mouse(0), pad = glyphs.pad("rb") },
    select_prev = { keyboard = glyphs.key("TAB"), mouse = glyphs.mouse(0), pad = glyphs.pad("lb") },
    focus_next = { keyboard = glyphs.key("."), pad = glyphs.pad("rb") },
    focus_prev = { keyboard = glyphs.key(","), pad = glyphs.pad("lb") },
    squad_wheel = { keyboard = glyphs.key("Q"), mouse = glyphs.mouse(1), pad = glyphs.pad("back") },
    open_inventory = { pad = glyphs.pad("back") },
    open_craft = { pad = glyphs.pad("back") },
    open_tech = { pad = glyphs.pad("back") },
    open_map = { pad = glyphs.pad("back") },
    open_journal = { pad = glyphs.pad("back") },
  }
  local row = table_[action]
  return row and row[device] or nil
end

local function resolve_glyph(item, device)
  if item.glyph then
    if type(item.glyph) == "table" then return item.glyph end
    if type(item.glyph) == "string" then
      if item.glyph:sub(1, 4) == "pad:" then return glyphs.pad(item.glyph:sub(5)) end
      if item.glyph:sub(1, 4) == "key:" then return glyphs.key(item.glyph:sub(5)) end
      if item.glyph:sub(1, 6) == "mouse:" then return glyphs.mouse(tonumber(item.glyph:sub(7)) or 0) end
    end
  end
  if item.action then
    local spec = glyphs.for_action(item.action, device)
    if spec then return spec end
    local fb = fallback_glyph(item.action, device)
    if fb then return fb end
    if device == "mouse" then
      -- Mouse context may be an on-screen entry; show the keyboard hotkey too.
      return glyphs.for_action(item.action, "keyboard") or fallback_glyph(item.action, "keyboard")
    end
  end
  return nil
end

local function hotkey_spec(item, device)
  if device ~= "mouse" or item.action == nil then return nil end
  return glyphs.for_action(item.action, "keyboard")
end

local function item_text(item)
  local vars = item.vars or {}
  if item.target then vars.target = item.target end
  return i18n.t(item.text, vars)
end

function M.draw(opts)
  opts = opts or {}
  local entry = M.current()
  if not entry or #entry.hints == 0 then return end

  local device = opts.device or M.device()
  local sw, sh = ui.screen_size()
  local bar = theme.layout.hintbar
  local h = opts.h or bar.h
  local y = opts.y or (sh - h)
  local x = opts.x or 0
  local w = opts.w or sw

  theme.set_color(theme.colors.bg, 0.70)
  ui.rect(x, y, w, h)
  theme.set_color(theme.colors.edge)
  ui.rect(x, y, w, 1)

  local f = theme.font("s")
  local lh = ui.font_line_height(f)
  local pad_x = 10
  local gap = 16
  local usable = w - pad_x * 2
  local max_items = opts.max_items or 6
  local items = {}
  local total = 0
  local overflow = false

  for i = 1, math.min(#entry.hints, max_items) do
    local it = entry.hints[i]
    local show = true
    if it.show_if ~= nil then
      if type(it.show_if) == "function" then show = it.show_if() else show = it.show_if end
    end
    if show then
      local gs = resolve_glyph(it, device)
      local gw, gh = 0, 0
      if gs then gw, gh = glyphs.measure(gs, 20) end
      local txt = item_text(it)
      local tw = ui.text_width(f, txt)
      local iw = gw + (gw > 0 and 6 or 0) + tw
      if total + (i > 1 and gap or 0) + iw <= usable then
        items[#items + 1] = { it = it, glyph = gs, gw = gw, gh = gh, text = txt, tw = tw }
        total = total + (i > 1 and gap or 0) + iw
      else
        overflow = true
      end
    end
  end

  local cx = x + pad_x
  local cy = y + math.floor((h - lh) * 0.5)
  for i, it in ipairs(items) do
    if i > 1 then cx = cx + gap end
    local gy = y + math.floor((h - it.gh) * 0.5)
    if it.glyph then
      if it.it.hold then
        theme.set_color(theme.colors.accent)
        ui.rect(cx - 2, gy - 2, it.gw + 4, 1)
        ui.rect(cx - 2, gy + it.gh + 1, it.gw + 4, 1)
        ui.rect(cx - 2, gy - 2, 1, it.gh + 4)
        ui.rect(cx + it.gw + 1, gy - 2, 1, it.gh + 4)
      end
      glyphs.draw(it.glyph, cx, gy, 20)
      cx = cx + it.gw + 6
    end
    -- Mouse context: keep the keyboard hotkey visible as a small secondary glyph.
    local hk = hotkey_spec(it.it, device)
    if hk and opts.show_hotkeys ~= false then
      local kw, kh = glyphs.measure(hk, 16)
      glyphs.draw(hk, cx, y + math.floor((h - kh) * 0.5), 16)
      cx = cx + kw + 6
    end
    theme.set_color(theme.colors.text)
    ui.text(f, it.text, cx, cy)
    cx = cx + it.tw
  end

  if overflow then
    theme.set_color(theme.colors.text_dim)
    ui.text(f, "…", x + w - pad_x - 10, cy)
  end
end

return M
