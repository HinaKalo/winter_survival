-- Unified action & rebinding layer (UI-UX §7.1, §7.2).
local util = require("core.util")
local ok_iso, iso_mod = pcall(require, "iso")
local iso = ok_iso and iso_mod or nil

local K = keys or {}
local PB = pad_buttons or {}
local PA = pad_axes or {}

local M = {
  BINDINGS_VERSION = 2, -- saved bindings older than this are not imported (P0-PLAN §9.4)
  -- [device][action_id] = { [1] = primary, [2] = secondary }; actions with `named_slots` for a device (move_dir on
  -- keyboard) instead use { up =, left =, down =, right = }.
  bindings = {},
  _repeat_dir = nil,
  _repeat_timer = 0,
  _repeat_fired = false,
  HOLD_S = 0.5, -- hold threshold (s); the settings page sets it from acc.hold_duration via set_hold_s
  _dev = false, -- dev mode (launch option --dev): dev_panel only fires when true
  _ent = nil,   -- per-binding runtime entries, rebuilt lazily (see ensure())
}

-- Context conflict matrix (UI-UX §7.2)
-- F = free cursor mode: only conflicts with itself and G.
local CTX_CONFLICTS = {
  G = { G = true, U = true, D = true, M = true, W = true, H = true, R = true, C = true, F = true },
  F = { F = true, G = true },
  W = { W = true, H = true, R = true, C = true, G = true },
  H = { W = true, H = true, G = true },
  R = { W = true, R = true, C = true, G = true },
  C = { W = true, R = true, C = true, G = true },
  U = { U = true, D = true, M = true, G = true },
  D = { U = true, D = true, M = true, G = true },
  M = { U = true, D = true, M = true, G = true },
  X = {}, -- dev-only actions (dev.*): never conflict with anything
}
M.CTX_CONFLICTS = CTX_CONFLICTS

local DEVICES = { "keyboard", "mouse", "pad" }

-- Intentional one-key-multi-use defaults (UI-UX §7.1); any other default conflict is a defect.
M.SHARED_DEFAULTS = {
  { device = "pad", actions = { "select", "interact" } },
  { device = "pad", actions = { "context", "attack" } },
  { device = "pad", actions = { "select_next", "focus_next" } },
  { device = "pad", actions = { "select_prev", "focus_prev" } },
  { device = "mouse", actions = { "interact", "context", "move_to" } },
  { device = "mouse", actions = { "cancel", "ui_secondary" } },
  { device = "keyboard", actions = { "cancel", "system_menu" } },
}

local function kb(key, shift, ctrl)
  if not key then return nil end
  return { key = key, shift = shift or false, ctrl = ctrl or false }
end

local function mb(btn)
  return { btn = btn }
end

local function pb(btn, lt)
  if not btn then return nil end
  return { btn = btn, lt = lt or false }
end

local function ax(axis, dir)
  return { axis = axis, dir = dir }
end

local HOLD_PAD = { pad = true }

M.ACTIONS = {
  { id = "confirm", ctx = "U", rebindable = false, screen = { mouse = true },
    defaults = { keyboard = { kb(K.ENTER), kb(K.SPACE) }, mouse = { mb(0) }, pad = { pb(PB.a) } } },
  { id = "cancel", ctx = "U", rebindable = false, screen = { mouse = true },
    defaults = { keyboard = { kb(K.ESCAPE) }, mouse = { mb(1) }, pad = { pb(PB.b) } } },
  { id = "ui_up", ctx = "U", rebindable = false, screen = { mouse = true },
    defaults = { keyboard = { kb(K.UP), kb(K.W) }, mouse = {}, pad = { pb(PB.dpad_up) } } },
  { id = "ui_down", ctx = "U", rebindable = false, screen = { mouse = true },
    defaults = { keyboard = { kb(K.DOWN), kb(K.S) }, mouse = {}, pad = { pb(PB.dpad_down) } } },
  { id = "ui_left", ctx = "U", rebindable = false, screen = { mouse = true },
    defaults = { keyboard = { kb(K.LEFT), kb(K.A) }, mouse = {}, pad = { pb(PB.dpad_left) } } },
  { id = "ui_right", ctx = "U", rebindable = false, screen = { mouse = true },
    defaults = { keyboard = { kb(K.RIGHT), kb(K.D) }, mouse = {}, pad = { pb(PB.dpad_right) } } },
  { id = "ui_tab_prev", ctx = "U", rebindable = false, screen = { mouse = true },
    defaults = { keyboard = { kb(K.LEFT_BRACKET) }, mouse = {}, pad = { pb(PB.lb) } } },
  { id = "ui_tab_next", ctx = "U", rebindable = false, screen = { mouse = true },
    defaults = { keyboard = { kb(K.RIGHT_BRACKET) }, mouse = {}, pad = { pb(PB.rb) } } },
  { id = "ui_page_prev", ctx = "U", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K.PAGE_UP) }, mouse = {}, pad = { ax("rs", "up") } } },
  { id = "ui_page_next", ctx = "U", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K.PAGE_DOWN) }, mouse = {}, pad = { ax("rs", "down") } } },
  { id = "ui_info", ctx = "U", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K.H) }, mouse = {}, pad = { pb(PB.y) } } },
  { id = "ui_secondary", ctx = "U", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K.ENTER, true) }, mouse = { mb(1) }, pad = { pb(PB.x) } } },

  { id = "pause", ctx = "W", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K.SPACE) }, mouse = {}, pad = { pb(PB.start) } } },
  { id = "speed_down", ctx = "H", rebindable = true, screen = { mouse = true, pad = true },
    defaults = { keyboard = { kb(K.MINUS) }, mouse = {}, pad = {} } },
  { id = "speed_up", ctx = "H", rebindable = true, screen = { mouse = true, pad = true },
    defaults = { keyboard = { kb(K.EQUAL) }, mouse = {}, pad = {} } },
  { id = "interact", ctx = "W", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K.F) }, mouse = { mb(1) }, pad = { pb(PB.a) } } },
  { id = "context", ctx = "W", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K.ENTER) }, mouse = { mb(1) }, pad = { pb(PB.x) } } },
  -- cursor_free / open_wheel: planned for a later milestone, not in the M2 demo (no code reads them yet).
  -- `na` = device column is "–" in UI-UX §7.1 (no input exists there, so nothing to validate).
  { id = "cursor_free", ctx = "W", rebindable = true, na = { mouse = true },
    defaults = { keyboard = { kb(K.V) }, mouse = {}, pad = { pb(PB.lt) } } },
  { id = "sneak_toggle", ctx = "R", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K.C) }, mouse = {}, pad = { pb(PB.l3) } } },
  { id = "run_hold", ctx = "R", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K.LEFT_SHIFT) }, mouse = {}, pad = { pb(PB.rt) } } },
  { id = "attack", ctx = "C", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K.G) }, mouse = {}, pad = { pb(PB.x) } } },
  { id = "takedown", ctx = "R", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K.G, true) }, mouse = {}, pad = { pb(PB.y) } } },
  { id = "intimidate", ctx = "R", rebindable = true, screen = { mouse = true }, hold = HOLD_PAD,
    defaults = { keyboard = { kb(K.R) }, mouse = {}, pad = { pb(PB.y) } } },
  { id = "squad_wheel", ctx = "R", rebindable = true, screen = { mouse = true, pad = true },
    defaults = { keyboard = { kb(K.Q) }, mouse = {}, pad = {} } },
  { id = "evacuate", ctx = "R", rebindable = true, screen = { mouse = true }, hold = HOLD_PAD,
    defaults = { keyboard = { kb(K.E) }, mouse = {}, pad = { pb(PB.b) } } },
  { id = "open_inventory", ctx = "W", rebindable = true, screen = { mouse = true, pad = true },
    defaults = { keyboard = { kb(K.I) }, mouse = {}, pad = {} } },
  { id = "open_craft", ctx = "H", rebindable = true, screen = { mouse = true, pad = true },
    defaults = { keyboard = { kb(K.B) }, mouse = {}, pad = {} } },
  { id = "open_tech", ctx = "H", rebindable = true, screen = { mouse = true, pad = true },
    defaults = { keyboard = { kb(K.T) }, mouse = {}, pad = {} } },
  { id = "open_map", ctx = "H", rebindable = true, screen = { mouse = true, pad = true },
    defaults = { keyboard = { kb(K.M) }, mouse = {}, pad = {} } },
  { id = "open_journal", ctx = "W", rebindable = true, screen = { mouse = true, pad = true },
    defaults = { keyboard = { kb(K.J) }, mouse = {}, pad = {} } },
  { id = "open_wheel", ctx = "W", rebindable = true, na = { keyboard = true, mouse = true },
    defaults = { keyboard = {}, mouse = {}, pad = { pb(PB.back) } } },
  { id = "end_day", ctx = "H", rebindable = true, screen = { mouse = true }, hold = { keyboard = true, pad = true },
    defaults = { keyboard = { kb(K.E) }, mouse = {}, pad = { pb(PB.back) } } },
  { id = "camera_zoom_in", ctx = "W", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K.Z) }, mouse = {}, pad = { pb(PB.r3) } } },
  { id = "camera_zoom_out", ctx = "W", rebindable = true, screen = { mouse = true, pad = true },
    defaults = { keyboard = { kb(K.X) }, mouse = {}, pad = {} } },
  { id = "camera_center", ctx = "W", rebindable = true, screen = { mouse = true }, hold = HOLD_PAD,
    defaults = { keyboard = { kb(K.HOME) }, mouse = {}, pad = { pb(PB.r3) } } },
  { id = "show_overlay_info", ctx = "R", rebindable = true, screen = { mouse = true, pad = true },
    defaults = { keyboard = { kb(K.N) }, mouse = {}, pad = {} } },
  -- UI-UX §7.1 `move_dir` (PLAN §5.4): ONE action whose value is a 2D direction (M.move_vec).
  -- Keyboard = 4 named slots up/left/down/right (default W/A/S/D) in M.bindings, rebindable like any slot
  -- (conflict detection, reserved keys, save/load). Pad = whole left stick (slot "ls" = `{ axis = "ls" }`).
  -- Mouse entry: right-click ground (`move_to`); the single-button drag mode of §7.1 is not implemented yet.
  { id = "move_dir", ctx = "W", rebindable = true,
    named_slots = { keyboard = { "up", "left", "down", "right" }, mouse = {}, pad = { "ls" } },
    screen = { mouse = "move_to" },
    defaults = { keyboard = { up = kb(K.W), left = kb(K.A), down = kb(K.S), right = kb(K.D) },
                 mouse = {}, pad = { ls = { axis = "ls" } } } },
  -- `screen` values: a string naming another action (must have a binding on that device, see validate()) or a
  -- HUD widget name; true = HUD widget.
  -- select / move_to keyboard+pad: free-cursor mode (`cursor_free`: V / LT, spec §7.1) drives them.
  { id = "select", ctx = "W", rebindable = false, screen = { keyboard = "cursor_free" },
    defaults = { keyboard = {}, mouse = { mb(0) }, pad = { pb(PB.a) } } },
  { id = "move_to", ctx = "W", rebindable = true, screen = { keyboard = "cursor_free", pad = "cursor_free" },
    defaults = { keyboard = {}, mouse = { mb(1) }, pad = {} } },
  -- Esc; mouse: demo "Back" HUD button; pad: system wheel entry (`open_wheel`, Back) per §7.1.
  { id = "system_menu", ctx = "G", rebindable = false, screen = { mouse = "hud_button" }, hold = HOLD_PAD,
    defaults = { keyboard = { kb(K.ESCAPE) }, mouse = {}, pad = { pb(PB.start) } } },

  -- P0-3 additions (UI-UX §7.1).
  { id = "select_1", ctx = "W", rebindable = true, screen = { mouse = true }, na = { pad = true },
    defaults = { keyboard = { kb(K._1) }, mouse = {}, pad = {} } },
  { id = "select_2", ctx = "W", rebindable = true, screen = { mouse = true }, na = { pad = true },
    defaults = { keyboard = { kb(K._2) }, mouse = {}, pad = {} } },
  { id = "select_3", ctx = "W", rebindable = true, screen = { mouse = true }, na = { pad = true },
    defaults = { keyboard = { kb(K._3) }, mouse = {}, pad = {} } },
  { id = "select_4", ctx = "W", rebindable = true, screen = { mouse = true }, na = { pad = true },
    defaults = { keyboard = { kb(K._4) }, mouse = {}, pad = {} } },
  { id = "select_5", ctx = "W", rebindable = true, screen = { mouse = true }, na = { pad = true },
    defaults = { keyboard = { kb(K._5) }, mouse = {}, pad = {} } },
  { id = "select_6", ctx = "W", rebindable = true, screen = { mouse = true }, na = { pad = true },
    defaults = { keyboard = { kb(K._6) }, mouse = {}, pad = {} } },
  { id = "select_next", ctx = "W", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K.TAB) }, mouse = {}, pad = { pb(PB.rb) } } },
  { id = "select_prev", ctx = "W", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K.TAB, true) }, mouse = {}, pad = { pb(PB.lb) } } },
  { id = "select_all", ctx = "H", rebindable = true, screen = { mouse = true }, hold = HOLD_PAD,
    defaults = { keyboard = { kb(K.A, false, true) }, mouse = {}, pad = { pb(PB.lb) } } },
  { id = "focus_next", ctx = "W", rebindable = true, na = { mouse = true },
    defaults = { keyboard = { kb(K.PERIOD) }, mouse = {}, pad = { pb(PB.rb) } } },
  { id = "focus_prev", ctx = "W", rebindable = true, na = { mouse = true },
    defaults = { keyboard = { kb(K.COMMA) }, mouse = {}, pad = { pb(PB.lb) } } },
  -- F = free cursor: Enter / Backspace (pad A / X) act as left / right click there.
  { id = "cursor_click_l", ctx = "F", rebindable = true, na = { mouse = true },
    defaults = { keyboard = { kb(K.ENTER) }, mouse = {}, pad = { pb(PB.a) } } },
  { id = "cursor_click_r", ctx = "F", rebindable = true, na = { mouse = true },
    defaults = { keyboard = { kb(K.BACKSPACE) }, mouse = {}, pad = { pb(PB.x) } } },
  { id = "squad_follow", ctx = "R", rebindable = true, screen = { keyboard = "squad_wheel", mouse = true },
    defaults = { keyboard = {}, mouse = {}, pad = { pb(PB.dpad_up) } } },
  { id = "squad_hold", ctx = "R", rebindable = true, screen = { keyboard = "squad_wheel", mouse = true },
    defaults = { keyboard = {}, mouse = {}, pad = { pb(PB.dpad_left) } } },
  { id = "squad_lookout", ctx = "R", rebindable = true, screen = { keyboard = "squad_wheel", mouse = true },
    defaults = { keyboard = {}, mouse = {}, pad = { pb(PB.dpad_right) } } },
  { id = "squad_carry", ctx = "R", rebindable = true, screen = { keyboard = "squad_wheel", mouse = true },
    defaults = { keyboard = {}, mouse = {}, pad = { pb(PB.dpad_down) } } },
  { id = "quick_1", ctx = "W", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K._7) }, mouse = {}, pad = { pb(PB.dpad_up, true) } } },
  { id = "quick_2", ctx = "W", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K._8) }, mouse = {}, pad = { pb(PB.dpad_right, true) } } },
  { id = "quick_3", ctx = "W", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K._9) }, mouse = {}, pad = { pb(PB.dpad_down, true) } } },
  { id = "quick_4", ctx = "W", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K._0) }, mouse = {}, pad = { pb(PB.dpad_left, true) } } },
  -- Value action like move_dir (M.pan_vec): keyboard arrows in four named slots, pad right stick (slot "rs").
  { id = "camera_pan", ctx = "W", rebindable = true, screen = { mouse = true },
    named_slots = { keyboard = { "up", "left", "down", "right" }, mouse = {}, pad = { "rs" } },
    defaults = { keyboard = { up = kb(K.UP), left = kb(K.LEFT), down = kb(K.DOWN), right = kb(K.RIGHT) },
                 mouse = {}, pad = { rs = ax("rs") } } },
  -- G: reserved keys, not rebindable, no mouse / pad input.
  { id = "screenshot", ctx = "G", rebindable = false, na = { mouse = true, pad = true },
    defaults = { keyboard = { kb(K.F12) }, mouse = {}, pad = {} } },
  { id = "fullscreen", ctx = "G", rebindable = false, na = { mouse = true, pad = true },
    defaults = { keyboard = { kb(K.F11) }, mouse = {}, pad = {} } },
  { id = "dev_panel", ctx = "G", rebindable = false, na = { mouse = true, pad = true },
    defaults = { keyboard = { kb(K.F1) }, mouse = {}, pad = {} } },

  -- Dev-only demo actions (scenes/m2_demo.lua); not rebindable, never listed in the rebind UI.
  { id = "dev.time_prev", ctx = "X", rebindable = false, screen = { keyboard = true, mouse = true, pad = true },
    defaults = { keyboard = { kb(K.F2) }, mouse = {}, pad = {} } },
  { id = "dev.time_next", ctx = "X", rebindable = false, screen = { keyboard = true, mouse = true, pad = true },
    defaults = { keyboard = { kb(K.F3) }, mouse = {}, pad = {} } },
  { id = "dev.map_toggle", ctx = "X", rebindable = false, screen = { keyboard = true, mouse = true, pad = true },
    defaults = { keyboard = { kb(K.F4) }, mouse = {}, pad = {} } },
  { id = "dev.mode_toggle", ctx = "X", rebindable = false, screen = { keyboard = true, mouse = true, pad = true },
    defaults = { keyboard = { kb(K.F6) }, mouse = {}, pad = {} } },
  { id = "dev.roof_toggle", ctx = "X", rebindable = false, screen = { keyboard = true, mouse = true, pad = true },
    defaults = { keyboard = { kb(K.F7) }, mouse = {}, pad = {} } },
  { id = "dev.flashlight", ctx = "X", rebindable = false, screen = { keyboard = true, mouse = true, pad = true },
    defaults = { keyboard = { kb(K.F8) }, mouse = {}, pad = {} } },
}

local ACTION_BY_ID = {}
for _, a in ipairs(M.ACTIONS) do
  ACTION_BY_ID[a.id] = a
end

local DEFAULT_SLOTS = { 1, 2 }

--- Drop the runtime entry cache (call after any change to M.bindings).
local function invalidate()
  M._ent = nil
end

--- Slot ids an action uses on a device: { 1, 2 } (primary/secondary) or its named slots (move_dir keyboard).
local function slot_ids(act, dev)
  return act.named_slots and act.named_slots[dev] or DEFAULT_SLOTS
end

local function slot_valid(act, dev, slot)
  for _, k in ipairs(slot_ids(act, dev)) do
    if k == slot then return true end
  end
  return false
end

--- Fresh slot table for (act, dev) copied from src (defaults or loaded data); only the action's own slot ids.
local function copy_slots(act, dev, src)
  local out = {}
  for _, k in ipairs(slot_ids(act, dev)) do
    if type(src) == "table" and type(src[k]) == "table" then out[k] = util.shallow_copy(src[k]) end
  end
  return out
end

local function has_any(act, dev)
  local slots = M.bindings[dev] and M.bindings[dev][act.id]
  if not slots then return false end
  for _, k in ipairs(slot_ids(act, dev)) do
    if slots[k] ~= nil then return true end
  end
  return false
end

--- A whole-stick binding ({ axis }) may only sit in its named slot ("ls" / "rs") and those slots only take it;
--- a stick-direction binding ({ axis, dir }) is a pad button-like binding for numbered slots.
local function binding_fits(device, slot, b)
  if b == nil then return true end
  if slot == "ls" or slot == "rs" then return b.axis == slot and b.dir == nil end
  if b.axis ~= nil then return device == "pad" and b.dir ~= nil end
  return true
end

--- Slot ids of an action on a device (public for UI / tests).
function M.slot_ids(action_id, device)
  local a = ACTION_BY_ID[action_id]
  return a and slot_ids(a, device) or DEFAULT_SLOTS
end

--- i18n key for an action row; named slots get "act.<id>.<slot>" (e.g. act.move_dir.up).
function M.label_key(action_id, slot)
  local a = ACTION_BY_ID[action_id]
  if a and a.named_slots and type(slot) == "string" then return "act." .. action_id .. "." .. slot end
  return "act." .. action_id
end

-- Reverse lookup for key / pad button names
local KEY_NAMES = {}
for name, code in pairs(K) do
  KEY_NAMES[code] = name
end

local PAD_NAMES = {
  [PB.a or 0] = "A",
  [PB.b or 1] = "B",
  [PB.x or 2] = "X",
  [PB.y or 3] = "Y",
  [PB.lb or 4] = "LB",
  [PB.rb or 5] = "RB",
  [PB.back or 6] = "Back",
  [PB.start or 7] = "Start",
  [PB.l3 or 8] = "L3",
  [PB.r3 or 9] = "R3",
  [PB.dpad_up or 10] = "D-Up",
  [PB.dpad_down or 11] = "D-Down",
  [PB.dpad_left or 12] = "D-Left",
  [PB.dpad_right or 13] = "D-Right",
  [PB.lt or 14] = "LT",
  [PB.rt or 15] = "RT",
  [PB.guide or 16] = "Guide",
}

function M.init()
  M.reset_all()
end

function M.reset_all()
  invalidate()
  M.bindings = { keyboard = {}, mouse = {}, pad = {} }
  for _, a in ipairs(M.ACTIONS) do
    for _, dev in ipairs({ "keyboard", "mouse", "pad" }) do
      M.bindings[dev][a.id] = copy_slots(a, dev, a.defaults[dev])
    end
  end
end

function M.reset_action(action_id)
  local a = ACTION_BY_ID[action_id]
  if not a then return false end
  invalidate()
  for _, dev in ipairs({ "keyboard", "mouse", "pad" }) do
    M.bindings[dev][a.id] = copy_slots(a, dev, a.defaults[dev])
  end
  return true
end

function M.get_action(action_id)
  return ACTION_BY_ID[action_id]
end

function M.get_binding(device, action_id, slot)
  local d = M.bindings[device]
  if not d or not d[action_id] then return nil end
  return d[action_id][slot or 1]
end

function M.is_reserved_binding(device, b)
  if not b then return false end
  if device == "keyboard" then
    return b.key == K.ESCAPE or b.key == K.F1 or b.key == K.F5 or b.key == K.F11 or b.key == K.F12
  elseif device == "mouse" then
    return b.btn == 0
  elseif device == "pad" then
    return b.btn == PB.start
  end
  return false
end

local function same_binding(device, a, b)
  if not a or not b then return false end
  if device == "keyboard" then
    return a.key == b.key and (a.shift or false) == (b.shift or false) and (a.ctrl or false) == (b.ctrl or false)
  elseif device == "mouse" then
    return a.btn == b.btn
  elseif device == "pad" then
    if a.axis or b.axis then
      -- a whole-stick binding covers every direction of that stick
      return a.axis == b.axis and (a.dir == nil or b.dir == nil or a.dir == b.dir)
    end
    return a.btn == b.btn and (a.lt or false) == (b.lt or false)
  end
  return false
end

local function is_hold(act, device)
  return act.hold ~= nil and act.hold[device] == true
end

local function ctx_conflict(c1, c2)
  return (CTX_CONFLICTS[c1] and CTX_CONFLICTS[c1][c2]) or (CTX_CONFLICTS[c2] and CTX_CONFLICTS[c2][c1]) or false
end

--- Every binding of a context-conflicting action that equals `b` on `device`. The hold property belongs to the
--- action: a short and a hold binding on the same physical input do not conflict (they are a pair).
function M.find_conflicts(device, action_id, b)
  local out = {}
  local act = ACTION_BY_ID[action_id]
  if not act or not b then return out end
  local cmap = CTX_CONFLICTS[act.ctx] or {}
  local dev_tbl = M.bindings[device] or {}
  local hold = is_hold(act, device)
  for _, other in ipairs(M.ACTIONS) do
    if other.id ~= action_id and cmap[other.ctx] and is_hold(other, device) == hold then
      local slots = dev_tbl[other.id]
      if slots then
        for _, slot in ipairs(slot_ids(other, device)) do
          if same_binding(device, slots[slot], b) then
            out[#out + 1] = { action_id = other.id, slot = slot, rebindable = other.rebindable }
          end
        end
      end
    end
  end
  return out
end

function M.find_conflict(device, action_id, b)
  return M.find_conflicts(device, action_id, b)[1]
end

--- Input coverage check (UI-UX §7.2 "no blank" rule). Per action and device one of:
---  * a binding in some slot,
---  * `na[dev]` (spec column is "–": no input exists on that device),
---  * `screen[dev]` = true / a HUD widget name,
---  * `screen[dev]` = the id of another action, which must itself have a binding on that device.
--- Returns true, or false, action_id, device.
function M.validate()
  for _, a in ipairs(M.ACTIONS) do
    for _, dev in ipairs({ "keyboard", "mouse", "pad" }) do
      if not has_any(a, dev) and not (a.na and a.na[dev]) then
        local sc = a.screen and a.screen[dev]
        local ok = false
        if sc == true then
          ok = true
        elseif type(sc) == "string" then
          local target = ACTION_BY_ID[sc]
          ok = target == nil or has_any(target, dev) -- not an action id = HUD widget name
        end
        if not ok then return false, a.id, dev end
      end
    end
  end
  return true
end

function M.set_binding(device, action_id, slot, b)
  local a = ACTION_BY_ID[action_id]
  if not a or not a.rebindable then return false, "non_rebindable" end
  if not slot_valid(a, device, slot) then return false, "bad_slot" end
  if not binding_fits(device, slot, b) then return false, "bad_slot" end
  if M.is_reserved_binding(device, b) then return false, "reserved" end
  local prev = M.bindings[device][action_id][slot]
  invalidate()
  M.bindings[device][action_id][slot] = b and util.shallow_copy(b) or nil
  local ok, bad_act, bad_dev = M.validate()
  if not ok then
    M.bindings[device][action_id][slot] = prev
    invalidate()
    return false, "no_entry", bad_act, bad_dev
  end
  return true
end

function M.swap_bindings(device, act1, slot1, act2, slot2)
  local a1, a2 = ACTION_BY_ID[act1], ACTION_BY_ID[act2]
  if not a1 or not a2 or not a1.rebindable or not a2.rebindable then
    return false, "non_rebindable"
  end
  if not slot_valid(a1, device, slot1) or not slot_valid(a2, device, slot2) then return false, "bad_slot" end
  local b1 = M.bindings[device][act1][slot1]
  local b2 = M.bindings[device][act2][slot2]
  if not binding_fits(device, slot2, b1) or not binding_fits(device, slot1, b2) then return false, "bad_slot" end
  invalidate()
  M.bindings[device][act1][slot1] = b2
  M.bindings[device][act2][slot2] = b1
  local ok, bad_act, bad_dev = M.validate()
  if not ok then
    M.bindings[device][act1][slot1] = b1
    M.bindings[device][act2][slot2] = b2
    invalidate()
    return false, "no_entry", bad_act, bad_dev
  end
  return true
end

function M.replace_binding(device, act_new, slot_new, b, act_old, slot_old)
  if M.is_reserved_binding(device, b) then return false, "reserved" end
  local an, ao = ACTION_BY_ID[act_new], ACTION_BY_ID[act_old]
  if not an or not ao or not an.rebindable or not ao.rebindable then
    return false, "non_rebindable"
  end
  if not slot_valid(an, device, slot_new) or not slot_valid(ao, device, slot_old) then return false, "bad_slot" end
  if not binding_fits(device, slot_new, b) then return false, "bad_slot" end
  local prev_new = M.bindings[device][act_new][slot_new]
  local prev_old = M.bindings[device][act_old][slot_old]
  invalidate()
  M.bindings[device][act_new][slot_new] = util.shallow_copy(b)
  M.bindings[device][act_old][slot_old] = nil
  local ok, bad_act, bad_dev = M.validate()
  if not ok then
    M.bindings[device][act_new][slot_new] = prev_new
    M.bindings[device][act_old][slot_old] = prev_old
    invalidate()
    return false, "no_entry", bad_act, bad_dev
  end
  return true
end

function M.format_binding(device, b)
  if not b then return "—" end
  if device == "keyboard" then
    local name = KEY_NAMES[b.key] or ("K" .. tostring(b.key))
    local prefix = ""
    if b.ctrl then prefix = prefix .. "Ctrl+" end
    if b.shift then prefix = prefix .. "Shift+" end
    return prefix .. name
  elseif device == "mouse" then
    if b.btn == 0 then return "M1"
    elseif b.btn == 1 then return "M2"
    elseif b.btn == 2 then return "M3"
    else return "M" .. tostring(b.btn) end
  elseif device == "pad" then
    if b.axis then
      if not b.dir then return string.upper(b.axis) end
      return string.upper(b.axis) .. "-" .. b.dir:sub(1, 1):upper() .. b.dir:sub(2)
    end
    local name = PAD_NAMES[b.btn] or ("P" .. tostring(b.btn))
    return (b.lt and "LT+" or "") .. name
  end
  return "—"
end

function M.export_bindings()
  local out = util.deep_copy(M.bindings)
  out.version = M.BINDINGS_VERSION
  return out
end

--- Returns true, or false, "outdated" (missing / older version: defaults kept) or false, "invalid".
function M.import_bindings(tbl)
  M.reset_all()
  invalidate()
  if type(tbl) ~= "table" then return false, "invalid" end
  if type(tbl.version) ~= "number" or tbl.version < M.BINDINGS_VERSION then return false, "outdated" end
  for _, dev in ipairs({ "keyboard", "mouse", "pad" }) do
    if type(tbl[dev]) == "table" then
      for act_id, slots in pairs(tbl[dev]) do
        local a = ACTION_BY_ID[act_id]
        if a and a.rebindable and type(slots) == "table" then
          M.bindings[dev][act_id] = copy_slots(a, dev, slots)
        end
      end
    end
  end
  if not M.validate() then
    M.reset_all()
    return false, "invalid"
  end
  return true
end

-- ------------------------------------------------------------------ Runtime queries

local function shift_down()
  return iso and (iso.key_down(K.LEFT_SHIFT) or iso.key_down(K.RIGHT_SHIFT))
end

local function ctrl_down()
  return iso and (iso.key_down(K.LEFT_CONTROL) or iso.key_down(K.RIGHT_CONTROL))
end

local function match_kb(b, fn)
  if not b or not iso then return false end
  if (b.shift or false) ~= (shift_down() or false) then
    if b.shift or b.key ~= K.LEFT_SHIFT then return false end
  end
  if (b.ctrl or false) ~= (ctrl_down() or false) then
    if b.ctrl or b.key ~= K.LEFT_CONTROL then return false end
  end
  return fn(b.key)
end

local STICK_AXES = {
  ls = { PA.lx or 0, PA.ly or 1 },
  rs = { PA.rx or 2, PA.ry or 3 },
}
local STICK_DIR_THRESHOLD = 0.5

--- Is the stick-direction binding `{ axis, dir }` currently past the threshold?
local function stick_dir_active(b)
  local st = STICK_AXES[b.axis]
  if not pad or not st then return false end
  if b.dir == "up" then return pad.axis(st[2]) <= -STICK_DIR_THRESHOLD
  elseif b.dir == "down" then return pad.axis(st[2]) >= STICK_DIR_THRESHOLD
  elseif b.dir == "left" then return pad.axis(st[1]) <= -STICK_DIR_THRESHOLD
  elseif b.dir == "right" then return pad.axis(st[1]) >= STICK_DIR_THRESHOLD end
  return false
end

--- Per-binding runtime entries: M._ent[device][action_id][slot] = { kind, b, ... }.
--- kind: nil = plain short press (evaluated live), "hold" (fires once after HOLD_S), "paired" (short press whose input
--- is also a hold input of a context-conflicting action: fires on release), "stick" (stick direction with repeat).
--- Hold / paired / stick entries are advanced by M.update and keep their per-frame result in `fire`.
local function build_entries()
  local ent = { keyboard = {}, mouse = {}, pad = {} }
  local list, holds, lt_btns = {}, {}, {}
  for _, dev in ipairs(DEVICES) do
    for _, a in ipairs(M.ACTIONS) do
      local slots = M.bindings[dev] and M.bindings[dev][a.id]
      if slots then
        for _, slot in ipairs(slot_ids(a, dev)) do
          local b = slots[slot]
          if b then
            local e = { dev = dev, act = a, b = b, fire = false }
            ent[dev][a.id] = ent[dev][a.id] or {}
            ent[dev][a.id][slot] = e
            list[#list + 1] = e
            if is_hold(a, dev) then
              e.kind = "hold"
              holds[#holds + 1] = e
            elseif b.axis and b.dir then
              e.kind = "stick"
            end
            if dev == "pad" and b.lt and b.btn then lt_btns[b.btn] = true end
          end
        end
      end
    end
  end
  for _, e in ipairs(list) do
    if e.kind == nil or e.kind == "stick" then
      for _, h in ipairs(holds) do
        if h.dev == e.dev and h.act ~= e.act and ctx_conflict(e.act.ctx, h.act.ctx)
            and same_binding(e.dev, e.b, h.b) then
          e.kind = "paired"
          break
        end
      end
    end
  end
  M._ent = ent
  M._dyn = {}
  for _, e in ipairs(list) do
    if e.kind then M._dyn[#M._dyn + 1] = e end
  end
  M._lt_btns = lt_btns
  M._ent_src = M.bindings
end

local function ensure()
  if M._ent == nil or M._ent_src ~= M.bindings then build_entries() end
end

local function match_pad(b, fn)
  if not b or not b.btn or not pad then return false end
  local lt_down = pad.button_down(PB.lt)
  if b.lt and not lt_down then return false end
  -- a plain D-pad / button binding does not fire while LT is held if that button also has an LT+ binding
  if not b.lt and lt_down then
    ensure()
    if M._lt_btns[b.btn] then return false end
  end
  return fn(b.btn)
end

function M.down(action_id)
  local act = ACTION_BY_ID[action_id]
  if not act then return false end
  local kb_slots = M.bindings.keyboard[action_id]
  if kb_slots and iso then
    for _, i in ipairs(slot_ids(act, "keyboard")) do
      if match_kb(kb_slots[i], iso.key_down) then return true end
    end
  end
  local mb_slots = M.bindings.mouse[action_id]
  if mb_slots and iso then
    for _, i in ipairs(slot_ids(act, "mouse")) do
      if mb_slots[i] and iso.mouse_down(mb_slots[i].btn) then return true end
    end
  end
  local pd_slots = M.bindings.pad[action_id]
  if pd_slots and pad then
    for _, i in ipairs(slot_ids(act, "pad")) do
      if match_pad(pd_slots[i], pad.button_down) then return true end
    end
  end
  return false
end

local STICK_DEADZONE = 0.25

--- Direction of a value action with four keyboard named slots and one whole-stick pad slot: unit-clamped 2D
--- (x = screen right, y = screen down). The stick is only read while no key of the action is held.
local function slot_vec(action_id, stick_slot, stick)
  local dx, dy = 0, 0
  local slots = M.bindings.keyboard[action_id]
  if iso and slots then
    local function held(b)
      if not b or not b.key then return false end
      if b.shift and not shift_down() then return false end
      if b.ctrl and not ctrl_down() then return false end
      return iso.key_down(b.key) == true
    end
    if held(slots.up) then dy = dy - 1 end
    if held(slots.down) then dy = dy + 1 end
    if held(slots.left) then dx = dx - 1 end
    if held(slots.right) then dx = dx + 1 end
  end
  local st = M.bindings.pad[action_id]
  if dx == 0 and dy == 0 and pad and st and st[stick_slot] then
    local lx = pad.axis(stick[1])
    local ly = pad.axis(stick[2])
    if lx * lx + ly * ly >= STICK_DEADZONE * STICK_DEADZONE then dx, dy = lx, ly end
  end
  local len = math.sqrt(dx * dx + dy * dy)
  if len > 1 then dx, dy = dx / len, dy / len end
  return dx, dy
end

--- Value of the `move_dir` action: the four bound keyboard slots and the pad left stick (deadzone 0.25).
function M.move_vec()
  return slot_vec("move_dir", "ls", STICK_AXES.ls)
end

--- Value of the `camera_pan` action: four keyboard slots (default arrow keys) and the pad right stick.
function M.pan_vec()
  return slot_vec("camera_pan", "rs", STICK_AXES.rs)
end

local function live_pressed(dev, b)
  if dev == "keyboard" then
    return iso ~= nil and match_kb(b, iso.key_pressed)
  elseif dev == "mouse" then
    return iso ~= nil and b.btn ~= nil and iso.mouse_pressed(b.btn) == true
  end
  return match_pad(b, pad.button_pressed)
end

--- Down this frame or pressed this frame (a tap shorter than a frame still counts as active).
local function raw_active(dev, b)
  if dev == "keyboard" then
    return iso ~= nil and (match_kb(b, iso.key_down) or match_kb(b, iso.key_pressed)) or false
  elseif dev == "mouse" then
    return iso ~= nil and b.btn ~= nil and (iso.mouse_down(b.btn) or iso.mouse_pressed(b.btn)) == true
  elseif b.axis then
    return stick_dir_active(b)
  end
  return match_pad(b, pad.button_down) or match_pad(b, pad.button_pressed)
end

local HOLD_EPS = 1e-9
local REPEAT_FIRST, REPEAT_NEXT = 0.35, 0.09

--- Advance hold timers, release detection and stick-direction repeat. Call once per frame, before anything
--- reads `pressed` (assets/main.lua does, ahead of scene.update).
function M.update(dt)
  ensure()
  for _, e in ipairs(M._dyn) do
    local active = raw_active(e.dev, e.b)
    e.fire = false
    if e.kind == "stick" then
      if active then
        if not e.on then
          e.on, e.t, e.rep, e.fire = true, 0, false, true
        else
          e.t = e.t + dt
          local th = e.rep and REPEAT_NEXT or REPEAT_FIRST
          if e.t >= th then
            e.t = e.t - th
            e.rep = true
            e.fire = true
          end
        end
      else
        e.on = false
      end
    elseif active then
      if not e.on then
        e.on, e.t, e.long = true, 0, false
      else
        e.t = e.t + dt
      end
      if not e.long and e.t >= M.HOLD_S - HOLD_EPS then
        e.long = true
        if e.kind == "hold" then e.fire = true end
      end
    else
      if e.on and e.kind == "paired" and not e.long then e.fire = true end
      e.on = false
    end
  end
end

function M.set_hold_s(s)
  if type(s) == "number" and s > 0 then M.HOLD_S = s end
end

function M.set_dev(on)
  M._dev = on and true or false
end

--- `device` (optional): restrict to "keyboard" | "mouse" | "pad".
function M.pressed(action_id, device)
  local act = ACTION_BY_ID[action_id]
  if not act then return false end
  if (action_id == "dev_panel" or action_id:sub(1, 4) == "dev.") and not M._dev then return false end
  ensure()
  for _, dev in ipairs(DEVICES) do
    if not device or device == dev then
      local ents = M._ent[dev][action_id]
      if ents then
        for _, slot in ipairs(slot_ids(act, dev)) do
          local e = ents[slot]
          if e then
            if e.kind then
              if e.fire then return true end
            elseif live_pressed(dev, e.b) then
              return true
            end
          end
        end
      end
    end
  end
  return false
end

function M.released(action_id)
  local act = ACTION_BY_ID[action_id]
  if not act then return false end
  local kb_slots = M.bindings.keyboard[action_id]
  if kb_slots and kit_input then
    for _, i in ipairs(slot_ids(act, "keyboard")) do
      if kb_slots[i] and kb_slots[i].key and kit_input.key_released(kb_slots[i].key) then return true end
    end
  end
  local mb_slots = M.bindings.mouse[action_id]
  if mb_slots and kit_input then
    for _, i in ipairs(slot_ids(act, "mouse")) do
      if mb_slots[i] and kit_input.mouse_released(mb_slots[i].btn) then return true end
    end
  end
  local pd_slots = M.bindings.pad[action_id]
  if pd_slots and pad then
    for _, i in ipairs(slot_ids(act, "pad")) do
      if pd_slots[i] and pd_slots[i].btn and pad.button_released(pd_slots[i].btn) then return true end
    end
  end
  return false
end

function M.last_device()
  if not kit_input then return "keyboard" end
  local d = kit_input.last_device()
  if d == 1 then return "mouse"
  elseif d == 2 then return "pad"
  else return "keyboard" end
end

local function current_ui_dir()
  if M.down("ui_up") then return "up" end
  if M.down("ui_down") then return "down" end
  if M.down("ui_left") then return "left" end
  if M.down("ui_right") then return "right" end
  if pad then
    local lx = pad.axis(PA.lx or 0)
    local ly = pad.axis(PA.ly or 1)
    if math.abs(lx) >= 0.6 or math.abs(ly) >= 0.6 then
      if math.abs(lx) > math.abs(ly) then
        return lx < 0 and "left" or "right"
      else
        return ly < 0 and "up" or "down"
      end
    end
  end
  return nil
end

function M.ui_dir_repeat(dt)
  local d = current_ui_dir()
  if not d then
    M._repeat_dir = nil
    M._repeat_timer = 0
    M._repeat_fired = false
    return nil
  end
  if d ~= M._repeat_dir then
    M._repeat_dir = d
    M._repeat_timer = 0
    M._repeat_fired = false
    return d
  end
  M._repeat_timer = M._repeat_timer + dt
  local threshold = M._repeat_fired and 0.09 or 0.35
  if M._repeat_timer >= threshold then
    M._repeat_timer = M._repeat_timer - threshold
    M._repeat_fired = true
    return d
  end
  return nil
end

M.init()

return M
