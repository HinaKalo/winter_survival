-- Key/Mouse/Gamepad rebinding UI (UI-UX §7.3).
local iso = require("iso")
local i18n = require("core.i18n")
local input = require("core.input")
local theme = require("ui.theme")
local focus = require("ui.focus")
local widgets = require("ui.widgets")

local M = {
  device_idx = 1, -- 1=keyboard, 2=mouse, 3=pad
  devices = { "keyboard", "mouse", "pad" },
  selected_idx = 1,
  scroll = 0,
  capture = nil,  -- { action_id, slot, timer, mod_wait, pending_mod }
  conflict = nil, -- { action_id, slot, binding, other_id, other_slot, can_replace }
  flash_action = nil,
  flash_t = 0,
  rows = {},
  _rows_dev = nil,
}

-- Rows of the current device tab: { id, slot, ctx, label_key }. Actions with named slots on that device
-- (move_dir on keyboard: up/left/down/right) get one row per slot; move_dir has no button rows on mouse / pad
-- (LS is the whole-axis pad entry, right-click is `move_to`).
local function rebuild_rows()
  M.rows = {}
  local dev = M.devices[M.device_idx]
  for _, a in ipairs(input.ACTIONS) do
    if a.rebindable then
      if a.named_slots then
        if dev == "keyboard" then
          for _, slot in ipairs(input.slot_ids(a.id, dev)) do
            M.rows[#M.rows + 1] = { id = a.id, slot = slot, ctx = a.ctx, label_key = input.label_key(a.id, slot), named = true }
          end
        end
      else
        M.rows[#M.rows + 1] = { id = a.id, slot = 1, ctx = a.ctx, label_key = input.label_key(a.id) }
      end
    end
  end
  M._rows_dev = dev
  if M.selected_idx > #M.rows then M.selected_idx = 1 end
end

function M.init()
  rebuild_rows()
  M.capture = nil
  M.conflict = nil
end

local function start_capture(action_id, slot)
  M.capture = {
    action_id = action_id,
    slot = slot or 1,
    label_key = input.label_key(action_id, slot),
    timer = 5.0,
    ignore_first = true,
  }
end

-- Toast text for an input.set_binding error code; unknown codes fall back to the reserved-key message.
local ERR_KEYS = {
  no_entry = "rebind.err_no_entry",
  non_rebindable = "rebind.err_non_rebindable",
  reserved = "rebind.err_reserved",
}
local function err_text(err)
  return i18n.t(ERR_KEYS[err] or "rebind.err_reserved")
end

local function try_commit_binding(dev, action_id, slot, binding)
  if input.is_reserved_binding(dev, binding) then
    widgets.show_toast(i18n.t("rebind.err_reserved"))
    return
  end
  local conf = input.find_conflict(dev, action_id, binding)
  if conf then
    if not conf.rebindable then
      widgets.show_toast(err_text("non_rebindable"))
      return
    end
    M.conflict = {
      dev = dev,
      action_id = action_id,
      slot = slot,
      binding = binding,
      other_id = conf.action_id,
      other_slot = conf.slot,
      other_label_key = input.label_key(conf.action_id, conf.slot),
    }
    return
  end
  local ok, err = input.set_binding(dev, action_id, slot, binding)
  if not ok then
    widgets.show_toast(err_text(err))
    return
  end
  M.flash_action = action_id
  M.flash_t = 0.6
end

function M.is_modal_active()
  return M.capture ~= nil or M.conflict ~= nil
end

function M.update(dt)
  if M.flash_t > 0 then
    M.flash_t = M.flash_t - dt
    if M.flash_t <= 0 then M.flash_action = nil end
  end

  if M.capture then
    local cap = M.capture
    cap.timer = cap.timer - dt
    if cap.ignore_first then
      cap.ignore_first = false
      return true
    end
    if cap.timer <= 0 then
      M.capture = nil
      widgets.show_toast(i18n.t("rebind.cancelled"))
      return true
    end
    if iso.key_pressed(keys.ESCAPE) or pad.button_pressed(pad_buttons.start) then
      M.capture = nil
      widgets.show_toast(i18n.t("rebind.cancelled"))
      return true
    end

    local dev = M.devices[M.device_idx]
    if dev == "keyboard" then
      local k = kit_input.last_key()
      if k and k ~= keys.LEFT_SHIFT and k ~= keys.RIGHT_SHIFT and k ~= keys.LEFT_CONTROL and k ~= keys.RIGHT_CONTROL then
        local sh = iso.key_down(keys.LEFT_SHIFT) or iso.key_down(keys.RIGHT_SHIFT)
        local ct = iso.key_down(keys.LEFT_CONTROL) or iso.key_down(keys.RIGHT_CONTROL)
        M.capture = nil
        try_commit_binding(dev, cap.action_id, cap.slot, { key = k, shift = sh, ctrl = ct })
        return true
      end
    elseif dev == "mouse" then
      local mb = kit_input.last_mouse_button()
      if mb then
        M.capture = nil
        try_commit_binding(dev, cap.action_id, cap.slot, { btn = mb })
        return true
      end
    elseif dev == "pad" then
      local pb = pad.last_button()
      if pb and pb ~= pad_buttons.lt then
        local lt = pad.button_down(pad_buttons.lt)
        M.capture = nil
        try_commit_binding(dev, cap.action_id, cap.slot, { btn = pb, lt = lt })
        return true
      end
    end
    return true
  end

  if M.conflict then
    return true
  end
  return false
end

function M.draw(area)
  if #M.rows == 0 or M._rows_dev ~= M.devices[M.device_idx] then rebuild_rows() end
  local dev = M.devices[M.device_idx]
  local f = theme.font("b")
  local fs = theme.font("s")
  local lh = ui.font_line_height(f)

  -- Device selector cycle at top of rebind area
  local dev_opts = {
    { label = i18n.t("rebind.dev_keyboard") },
    { label = i18n.t("rebind.dev_mouse") },
    { label = i18n.t("rebind.dev_pad") },
  }
  local new_dev, d_changed = widgets.cycle("rb_dev", { x = area.x, y = area.y, w = area.w, h = 40 },
    i18n.t("rebind.col_ctx"), dev_opts, M.device_idx, { sub_group = "content" })
  if d_changed then M.device_idx = new_dev end

  -- Header row
  local hy = area.y + 46
  widgets.label(fs, i18n.t("rebind.col_action"), area.x + 12, hy, 220, theme.colors.text_dim, 0)
  widgets.label(fs, i18n.t("rebind.col_ctx"), area.x + 240, hy, 70, theme.colors.text_dim, 1)
  widgets.label(fs, i18n.t("rebind.col_primary"), area.x + 320, hy, 140, theme.colors.text_dim, 1)
  widgets.label(fs, i18n.t("rebind.col_secondary"), area.x + 470, hy, 140, theme.colors.text_dim, 1)

  -- List viewport
  local list_y = hy + 24
  local row_h = 36
  local list_h = area.h - 122
  local visible_rows = math.max(1, math.floor(list_h / row_h))
  local max_scroll = math.max(0, #M.rows - visible_rows)
  M.scroll = math.max(0, math.min(max_scroll, M.scroll))

  ui.clip(area.x, list_y, area.w, visible_rows * row_h)
  for i = 1, visible_rows do
    local idx = M.scroll + i
    local a = M.rows[idx]
    if not a then break end
    local ry = list_y + (i - 1) * row_h
    local row_rect = { x = area.x, y = ry, w = area.w - 24, h = row_h - 2 }

    local is_sel = (idx == M.selected_idx)
    local is_flash = (M.flash_action == a.id)
    if is_flash then
      theme.set_color(theme.colors.ok, 0.35)
      ui.rect(row_rect.x, row_rect.y, row_rect.w, row_rect.h)
    elseif is_sel then
      theme.set_color(theme.colors.bg_hi, 0.9)
      ui.rect(row_rect.x, row_rect.y, row_rect.w, row_rect.h)
      theme.set_color(theme.colors.accent)
      ui.rect(row_rect.x, row_rect.y, 4, row_rect.h)
    end

    widgets.button("rb_row_" .. a.id, row_rect, "", {
      variant = "link",
      sub_group = "content",
      on_click = function()
        if M.selected_idx == idx then
          start_capture(a.id, a.slot)
        else
          M.selected_idx = idx
        end
      end,
    })

    -- Ensure selected row stays visible when navigated via focus
    if focus.is_focused("rb_row_" .. a.id) and M.selected_idx ~= idx then
      M.selected_idx = idx
    end

    local b1 = input.format_binding(dev, input.get_binding(dev, a.id, a.slot))
    local b2 = a.named and "—" or input.format_binding(dev, input.get_binding(dev, a.id, 2))
    local ty = ry + math.floor((row_h - lh) * 0.5)
    widgets.label(f, widgets.ellipsize(f, i18n.t(a.label_key), 210), area.x + 12, ty, 210, theme.colors.text, 0)
    widgets.label(fs, i18n.t("ctx." .. a.ctx), area.x + 240, ty, 70, theme.colors.text_dim, 1)
    widgets.label(f, b1, area.x + 320, ty, 140, theme.colors.accent, 1)
    widgets.label(f, b2, area.x + 470, ty, 140, theme.colors.text_dim, 1)
  end
  ui.clip_off()

  -- Scroll up / down buttons
  local sb_x = area.x + area.w - 20
  if widgets.button("rb_up", { x = sb_x, y = list_y, w = 20, h = 24 }, "▲", { font_kind = "s", sub_group = "content" }) then
    M.scroll = math.max(0, M.scroll - 1)
  end
  if widgets.button("rb_dn", { x = sb_x, y = list_y + visible_rows * row_h - 24, w = 20, h = 24 }, "▼", { font_kind = "s", sub_group = "content" }) then
    M.scroll = math.min(max_scroll, M.scroll + 1)
  end

  -- Action buttons row for selected action
  local by = area.y + area.h - 44
  local sel = M.rows[M.selected_idx]
  if sel then
    widgets.button("rb_bind", { x = area.x, y = by, w = 130, h = 40 }, i18n.t("rebind.btn_bind"), {
      variant = "primary",
      sub_group = "rebind_actions",
      on_click = function() start_capture(sel.id, sel.slot) end,
    })
    widgets.button("rb_clear", { x = area.x + 140, y = by, w = 130, h = 40 }, i18n.t("rebind.btn_clear"), {
      sub_group = "rebind_actions",
      on_click = function()
        local ok, err = input.set_binding(dev, sel.id, sel.slot, nil)
        if not ok then
          widgets.show_toast(err_text(err))
        end
      end,
    })
    widgets.button("rb_reset_one", { x = area.x + 280, y = by, w = 140, h = 40 }, i18n.t("rebind.btn_reset_one"), {
      sub_group = "rebind_actions",
      on_click = function() input.reset_action(sel.id) end,
    })
  end

  -- Capture overlay
  if M.capture then
    local cap = M.capture
    widgets.modal_dim()
    local sw, sh = ui.screen_size()
    local mw, mh = 560, 180
    local mx, my = math.floor((sw - mw) * 0.5), math.floor((sh - mh) * 0.5)
    widgets.panel(mx, my, mw, mh, 0.98)
    local msg = i18n.t("rebind.prompt", {
      action = i18n.t(cap.label_key),
      sec = string.format("%.1f", math.max(0, cap.timer)),
    })
    widgets.label(f, msg, mx + 24, my + 32, mw - 48, theme.colors.text, 1)
    -- Countdown bar
    local ratio = math.max(0, math.min(1, cap.timer / 5.0))
    theme.set_color(theme.colors.bg_dark)
    ui.rect(mx + 32, my + 100, mw - 64, 10)
    theme.set_color(theme.colors.accent)
    ui.rect(mx + 32, my + 100, math.floor((mw - 64) * ratio), 10)

    if M.devices[M.device_idx] == "mouse" then
      widgets.button("rb_cap_cancel", { x = mx + mw - 144, y = my + 126, w = 120, h = 36 }, i18n.t("ui.cancel"), {
        on_click = function()
          M.capture = nil
          widgets.show_toast(i18n.t("rebind.cancelled"))
        end,
      })
    end
  end

  -- Conflict modal
  if M.conflict then
    local c = M.conflict
    widgets.modal_dim()
    local sw, sh = ui.screen_size()
    local mw, mh = 540, 200
    local mx, my = math.floor((sw - mw) * 0.5), math.floor((sh - mh) * 0.5)
    widgets.panel(mx, my, mw, mh, 0.98)
    widgets.label(theme.font("t"), i18n.t("rebind.conflict_title"), mx + 24, my + 20, mw - 48, theme.colors.accent, 0)
    widgets.label(f, i18n.t("rebind.conflict_msg", { other = i18n.t(c.other_label_key) }),
      mx + 24, my + 68, mw - 48, theme.colors.text, 0)

    widgets.button("rb_conf_cancel", { x = mx + 24, y = my + 140, w = 130, h = 40 }, i18n.t("ui.cancel"), {
      on_click = function() M.conflict = nil end,
    })
    widgets.button("rb_conf_replace", { x = mx + 190, y = my + 140, w = 140, h = 40 }, i18n.t("rebind.replace"), {
      on_click = function()
        local ok, err = input.replace_binding(c.dev, c.action_id, c.slot, c.binding, c.other_id, c.other_slot)
        M.conflict = nil
        if not ok then
          widgets.show_toast(err_text(err))
        else
          M.flash_action = c.action_id
          M.flash_t = 0.6
        end
      end,
    })
    widgets.button("rb_conf_swap", { x = mx + 360, y = my + 140, w = 150, h = 40 }, i18n.t("rebind.swap"), {
      variant = "primary",
      on_click = function()
        local ok, err = input.swap_bindings(c.dev, c.action_id, c.slot, c.other_id, c.other_slot)
        M.conflict = nil
        if not ok then
          widgets.show_toast(err_text(err))
        else
          M.flash_action = c.action_id
          M.flash_t = 0.6
        end
      end,
    })
  end
end

return M
