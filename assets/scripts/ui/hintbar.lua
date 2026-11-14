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
      hint("sneak_toggle", "hint.sneak_run", { action2 = "run_hold" }),
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

-- Primary glyph for a hint item on `device`. Mouse context with no mouse
-- binding falls back to the keyboard hotkey (then it is the primary glyph, and
-- no second hotkey glyph is drawn next to it).
local function resolve_glyph(item, device)
  if item.glyph then
    local g = glyphs.spec(item.glyph)
    if g then return g end
  end
  if item.action then
    local spec = glyphs.for_action(item.action, device)
    if spec then return spec end
    local fb = fallback_glyph(item.action, device)
    if fb then return fb end
    if device == "mouse" then
      return glyphs.for_action(item.action, "keyboard") or fallback_glyph(item.action, "keyboard")
    end
  end
  return nil
end

function M.resolve(item, device)
  return resolve_glyph(item, device)
end

-- Small keyboard hotkey drawn next to a mouse glyph. Never when the primary
-- glyph already is the keyboard one.
local function hotkey_spec(item, device, primary)
  if device ~= "mouse" or item.action == nil then return nil end
  if primary and primary.kind == "key" then return nil end
  return glyphs.for_action(item.action, "keyboard") or fallback_glyph(item.action, "keyboard")
end

local function item_text(item)
  local vars = item.vars or {}
  if item.target then vars.target = item.target end
  return i18n.t(item.text, vars)
end

-- Resolve which hints fit and where. Used by draw() and by the probe.
function M.layout(opts)
  opts = opts or {}
  local entry = M.current()
  if not entry or #entry.hints == 0 then return nil end
  local device = opts.device or M.device()
  local sw = ui.screen_size()
  local w = opts.w or sw
  local f = theme.font("s")
  local pad_x = 10
  local gap = 16
  local usable = w - pad_x * 2
  local max_items = opts.max_items or 6
  local items = {}
  local total = 0
  local overflow = false
  local visible = 0

  for i = 1, #entry.hints do
    local it = entry.hints[i]
    local show = true
    if it.show_if ~= nil then
      if type(it.show_if) == "function" then show = it.show_if() else show = it.show_if end
    end
    if show then
      visible = visible + 1
      if visible > max_items then overflow = true; break end
      local gs = resolve_glyph(it, device)
      local gw, gh = 0, 0
      if gs then gw, gh = glyphs.measure(gs, 20) end
      -- optional second glyph (e.g. "Sneak/Run" shows both keys)
      local gs2, gw2 = nil, 0
      if it.action2 then
        gs2 = resolve_glyph({ action = it.action2 }, device)
        if gs2 then gw2 = glyphs.measure(gs2, 20) end
      end
      local hk = (opts.show_hotkeys ~= false) and hotkey_spec(it, device, gs) or nil
      local kw, kh = 0, 0
      if hk then kw, kh = glyphs.measure(hk, 16) end
      local txt = item_text(it)
      local tw = ui.text_width(f, txt)
      local iw = gw + (gw2 > 0 and (4 + gw2) or 0) + (gw > 0 and 6 or 0) + kw + (kw > 0 and 6 or 0) + tw
      local sep = (#items > 0) and gap or 0
      if total + sep + iw <= usable then
        items[#items + 1] = { it = it, glyph = gs, gw = gw, gh = gh, glyph2 = gs2, gw2 = gw2, hotkey = hk, kw = kw, kh = kh,
          text = txt, tw = tw, w = iw }
        total = total + sep + iw
      else
        overflow = true
      end
    end
  end
  return { items = items, total = total, overflow = overflow, device = device, usable = usable }
end

function M.draw(opts)
  opts = opts or {}
  local lay = M.layout(opts)
  if not lay then return end

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
  local cx = x + pad_x
  local cy = y + math.floor((h - lh) * 0.5)
  for i, it in ipairs(lay.items) do
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
      cx = cx + it.gw
      if it.glyph2 then
        glyphs.draw(it.glyph2, cx + 4, gy, 20)
        cx = cx + 4 + it.gw2
      end
      cx = cx + 6
    end
    if it.hotkey then
      glyphs.draw(it.hotkey, cx, y + math.floor((h - it.kh) * 0.5), 16)
      cx = cx + it.kw + 6
    end
    theme.set_color(theme.colors.text)
    ui.text(f, it.text, cx, cy)
    cx = cx + it.tw
  end

  if lay.overflow then
    theme.set_color(theme.colors.text_dim)
    ui.text(f, "…", x + w - pad_x - 10, cy)
  end
end

return M
