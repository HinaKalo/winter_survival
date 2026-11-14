-- Unified action & rebinding layer (UI-UX §7.1, §7.2).
local util = require("core.util")
local ok_iso, iso_mod = pcall(require, "iso")
local iso = ok_iso and iso_mod or nil

local K = keys or {}
local PB = pad_buttons or {}
local PA = pad_axes or {}

local M = {
  bindings = {}, -- [device][action_id] = { primary, secondary }
  _repeat_dir = nil,
  _repeat_timer = 0,
  _repeat_fired = false,
}

-- Context conflict matrix (UI-UX §7.2)
local CTX_CONFLICTS = {
  G = { G = true, U = true, D = true, M = true, W = true, H = true, R = true, C = true },
  W = { W = true, H = true, R = true, C = true, G = true },
  H = { W = true, H = true, G = true },
  R = { W = true, R = true, C = true, G = true },
  C = { W = true, R = true, C = true, G = true },
  U = { U = true, D = true, M = true, G = true },
  D = { U = true, D = true, M = true, G = true },
  M = { U = true, D = true, M = true, G = true },
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
    defaults = { keyboard = { kb(K.PAGE_UP) }, mouse = {}, pad = { pb(PB.lb) } } },
  { id = "ui_page_next", ctx = "U", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K.PAGE_DOWN) }, mouse = {}, pad = { pb(PB.rb) } } },
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
  { id = "cursor_free", ctx = "W", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K.V) }, mouse = {}, pad = { pb(PB.lt) } } },
  { id = "sneak_toggle", ctx = "R", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K.C) }, mouse = {}, pad = { pb(PB.l3) } } },
  { id = "run_hold", ctx = "R", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K.LEFT_SHIFT) }, mouse = {}, pad = { pb(PB.rt) } } },
  { id = "attack", ctx = "C", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K.G) }, mouse = {}, pad = { pb(PB.x) } } },
  { id = "takedown", ctx = "R", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K.G, true) }, mouse = {}, pad = { pb(PB.y) } } },
  { id = "intimidate", ctx = "R", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K.R) }, mouse = {}, pad = { pb(PB.y, true) } } },
  { id = "squad_wheel", ctx = "R", rebindable = true, screen = { mouse = true, pad = true },
    defaults = { keyboard = { kb(K.Q) }, mouse = {}, pad = {} } },
  { id = "evacuate", ctx = "R", rebindable = true, screen = { mouse = true },
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
  { id = "open_wheel", ctx = "W", rebindable = true, screen = { keyboard = true, mouse = true },
    defaults = { keyboard = {}, mouse = {}, pad = { pb(PB.back) } } },
  { id = "end_day", ctx = "H", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K.E) }, mouse = {}, pad = { pb(PB.back) } } },
  { id = "camera_zoom_in", ctx = "W", rebindable = true, screen = { mouse = true },
    defaults = { keyboard = { kb(K.Z) }, mouse = {}, pad = { pb(PB.r3) } } },
  { id = "camera_zoom_out", ctx = "W", rebindable = true, screen = { mouse = true, pad = true },
    defaults = { keyboard = { kb(K.X) }, mouse = {}, pad = {} } },
  { id = "camera_center", ctx = "W", rebindable = true, screen = { mouse = true, pad = true },
    defaults = { keyboard = { kb(K.HOME) }, mouse = {}, pad = {} } },
  { id = "show_overlay_info", ctx = "R", rebindable = true, screen = { mouse = true, pad = true },
    defaults = { keyboard = { kb(K.N) }, mouse = {}, pad = {} } },
}

local ACTION_BY_ID = {}
for _, a in ipairs(M.ACTIONS) do
  ACTION_BY_ID[a.id] = a
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
  M.bindings = { keyboard = {}, mouse = {}, pad = {} }
  for _, a in ipairs(M.ACTIONS) do
    for _, dev in ipairs({ "keyboard", "mouse", "pad" }) do
      local src = a.defaults[dev] or {}
      M.bindings[dev][a.id] = {
        src[1] and util.shallow_copy(src[1]) or nil,
        src[2] and util.shallow_copy(src[2]) or nil,
      }
    end
  end
end

function M.reset_action(action_id)
  local a = ACTION_BY_ID[action_id]
  if not a then return false end
  for _, dev in ipairs({ "keyboard", "mouse", "pad" }) do
    local src = a.defaults[dev] or {}
    M.bindings[dev][a.id] = {
      src[1] and util.shallow_copy(src[1]) or nil,
      src[2] and util.shallow_copy(src[2]) or nil,
    }
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
    return b.key == K.ESCAPE or b.key == K.F1 or b.key == K.F11 or b.key == K.F12
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
    return a.btn == b.btn and (a.lt or false) == (b.lt or false)
  end
  return false
end

function M.find_conflict(device, action_id, b)
  local act = ACTION_BY_ID[action_id]
  if not act or not b then return nil end
  local cmap = CTX_CONFLICTS[act.ctx] or {}
  local dev_tbl = M.bindings[device] or {}
  for _, other in ipairs(M.ACTIONS) do
    if other.id ~= action_id and cmap[other.ctx] then
      local slots = dev_tbl[other.id]
      if slots then
        for slot = 1, 2 do
          if same_binding(device, slots[slot], b) then
            return { action_id = other.id, slot = slot, rebindable = other.rebindable }
          end
        end
      end
    end
  end
  return nil
end

function M.validate()
  for _, a in ipairs(M.ACTIONS) do
    for _, dev in ipairs({ "keyboard", "mouse", "pad" }) do
      local slots = M.bindings[dev][a.id]
      local has_bind = slots and (slots[1] ~= nil or slots[2] ~= nil)
      local has_screen = a.screen and a.screen[dev]
      if not has_bind and not has_screen then
        return false, a.id, dev
      end
    end
  end
  return true
end

function M.set_binding(device, action_id, slot, b)
  local a = ACTION_BY_ID[action_id]
  if not a or not a.rebindable then return false, "non_rebindable" end
  if M.is_reserved_binding(device, b) then return false, "reserved" end
  local prev = M.bindings[device][action_id][slot]
  M.bindings[device][action_id][slot] = b and util.shallow_copy(b) or nil
  local ok, bad_act, bad_dev = M.validate()
  if not ok then
    M.bindings[device][action_id][slot] = prev
    return false, "no_entry", bad_act, bad_dev
  end
  return true
end

function M.swap_bindings(device, act1, slot1, act2, slot2)
  local a1, a2 = ACTION_BY_ID[act1], ACTION_BY_ID[act2]
  if not a1 or not a2 or not a1.rebindable or not a2.rebindable then
    return false, "non_rebindable"
  end
  local b1 = M.bindings[device][act1][slot1]
  local b2 = M.bindings[device][act2][slot2]
  M.bindings[device][act1][slot1] = b2
  M.bindings[device][act2][slot2] = b1
  local ok, bad_act, bad_dev = M.validate()
  if not ok then
    M.bindings[device][act1][slot1] = b1
    M.bindings[device][act2][slot2] = b2
    return false, "no_entry", bad_act, bad_dev
  end
  return true
end

function M.replace_binding(device, act_new, slot_new, b, act_old, slot_old)
  local an, ao = ACTION_BY_ID[act_new], ACTION_BY_ID[act_old]
  if not an or not ao or not an.rebindable or not ao.rebindable then
    return false, "non_rebindable"
  end
  local prev_new = M.bindings[device][act_new][slot_new]
  local prev_old = M.bindings[device][act_old][slot_old]
  M.bindings[device][act_new][slot_new] = util.shallow_copy(b)
  M.bindings[device][act_old][slot_old] = nil
  local ok, bad_act, bad_dev = M.validate()
  if not ok then
    M.bindings[device][act_new][slot_new] = prev_new
    M.bindings[device][act_old][slot_old] = prev_old
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
    local name = PAD_NAMES[b.btn] or ("P" .. tostring(b.btn))
    return (b.lt and "LT+" or "") .. name
  end
  return "—"
end

function M.export_bindings()
  return util.deep_copy(M.bindings)
end

function M.import_bindings(tbl)
  M.reset_all()
  if type(tbl) ~= "table" then return end
  for _, dev in ipairs({ "keyboard", "mouse", "pad" }) do
    if type(tbl[dev]) == "table" then
      for act_id, slots in pairs(tbl[dev]) do
        local a = ACTION_BY_ID[act_id]
        if a and a.rebindable and type(slots) == "table" then
          M.bindings[dev][act_id] = {
            slots[1] and util.shallow_copy(slots[1]) or nil,
            slots[2] and util.shallow_copy(slots[2]) or nil,
          }
        end
      end
    end
  end
  if not M.validate() then
    M.reset_all()
  end
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

local function match_pad(b, fn)
  if not b or not pad then return false end
  if b.lt and not pad.button_down(PB.lt) then return false end
  return fn(b.btn)
end

function M.down(action_id)
  local kb_slots = M.bindings.keyboard[action_id]
  if kb_slots and iso then
    for i = 1, 2 do
      if match_kb(kb_slots[i], iso.key_down) then return true end
    end
  end
  local mb_slots = M.bindings.mouse[action_id]
  if mb_slots and iso then
    for i = 1, 2 do
      if mb_slots[i] and iso.mouse_down(mb_slots[i].btn) then return true end
    end
  end
  local pd_slots = M.bindings.pad[action_id]
  if pd_slots and pad then
    for i = 1, 2 do
      if match_pad(pd_slots[i], pad.button_down) then return true end
    end
  end
  return false
end

function M.pressed(action_id)
  local kb_slots = M.bindings.keyboard[action_id]
  if kb_slots and iso then
    for i = 1, 2 do
      if match_kb(kb_slots[i], iso.key_pressed) then return true end
    end
  end
  local mb_slots = M.bindings.mouse[action_id]
  if mb_slots and iso then
    for i = 1, 2 do
      if mb_slots[i] and iso.mouse_pressed(mb_slots[i].btn) then return true end
    end
  end
  local pd_slots = M.bindings.pad[action_id]
  if pd_slots and pad then
    for i = 1, 2 do
      if match_pad(pd_slots[i], pad.button_pressed) then return true end
    end
  end
  return false
end

function M.released(action_id)
  local kb_slots = M.bindings.keyboard[action_id]
  if kb_slots and kit_input then
    for i = 1, 2 do
      if kb_slots[i] and kit_input.key_released(kb_slots[i].key) then return true end
    end
  end
  local mb_slots = M.bindings.mouse[action_id]
  if mb_slots and kit_input then
    for i = 1, 2 do
      if mb_slots[i] and kit_input.mouse_released(mb_slots[i].btn) then return true end
    end
  end
  local pd_slots = M.bindings.pad[action_id]
  if pd_slots and pad then
    for i = 1, 2 do
      if pd_slots[i] and pad.button_released(pd_slots[i].btn) then return true end
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
