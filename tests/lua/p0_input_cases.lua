-- 验收测试辅助（主代理编写，编码代理不得修改）。P0-PLAN §3.3 / UI-UX §7.1。
-- 由 tests/lua/test_input_actions.lua（模拟设备）与 tests/probe/p0_inputs.lua（真实注入）共用。
-- 不是测试套件：文件名不以 test_ 开头，runner 不会加载它。
local M = {}

-- UI-UX §7.1 的 65 个动作（P0-PLAN §9.1 Q4：quick_1..4 = 7 8 9 0）
M.SPEC_IDS = {
  "confirm", "cancel", "ui_up", "ui_down", "ui_left", "ui_right", "ui_tab_prev", "ui_tab_next",
  "ui_page_prev", "ui_page_next", "ui_info", "ui_secondary",
  "pause", "speed_down", "speed_up",
  "select", "select_1", "select_2", "select_3", "select_4", "select_5", "select_6",
  "select_next", "select_prev", "select_all",
  "move_dir", "move_to", "context", "interact", "focus_next", "focus_prev",
  "cursor_free", "cursor_click_l", "cursor_click_r",
  "sneak_toggle", "run_hold", "attack", "takedown", "intimidate",
  "squad_follow", "squad_hold", "squad_lookout", "squad_carry", "squad_wheel", "evacuate",
  "quick_1", "quick_2", "quick_3", "quick_4",
  "open_inventory", "open_craft", "open_tech", "open_map", "open_journal", "open_wheel", "end_day",
  "camera_pan", "camera_zoom_in", "camera_zoom_out", "camera_center", "show_overlay_info",
  "screenshot", "fullscreen", "dev_panel", "system_menu",
}

M.DEV_IDS = { "dev.time_prev", "dev.time_next", "dev.map_toggle", "dev.mode_toggle", "dev.roof_toggle",
  "dev.flashlight" }

M.DEVICES = { "keyboard", "mouse", "pad" }

-- Value actions read through move_vec / pan_vec, not pressed().
M.VALUE_ACTIONS = { move_dir = true, camera_pan = true }

-- Are two contexts mutually exclusive (may be active at the same time)?
function M.ctx_conflict(input, a, b)
  local C = input.CTX_CONFLICTS
  return (C[a] and C[a][b]) or (C[b] and C[b][a]) or false
end

-- Same physical input on a device, ignoring the hold property.
function M.same_physical(device, a, b)
  if not a or not b then return false end
  if device == "keyboard" then
    return a.key == b.key and (a.shift or false) == (b.shift or false) and (a.ctrl or false) == (b.ctrl or false)
  elseif device == "mouse" then
    return a.btn == b.btn
  else
    if a.axis or b.axis then return a.axis == b.axis and a.dir == b.dir end
    return a.btn == b.btn and (a.lt or false) == (b.lt or false)
  end
end

function M.is_hold(input, id, device)
  local a = input.get_action(id)
  return a ~= nil and a.hold ~= nil and a.hold[device] == true
end

function M.shared(input, device, id1, id2)
  for _, g in ipairs(input.SHARED_DEFAULTS) do
    if g.device == device then
      local h1, h2 = false, false
      for _, x in ipairs(g.actions) do
        h1 = h1 or x == id1
        h2 = h2 or x == id2
      end
      if h1 and h2 then return true end
    end
  end
  return false
end

-- Every default binding that can be pressed: { id, device, slot, b, hold, paired }.
-- `paired`: a short action whose input is also the hold input of a context-conflicting action
-- (it then fires on release), or a hold action (fires after HOLD_S).
function M.cases(input)
  input.reset_all()
  local out = {}
  for _, a in ipairs(input.ACTIONS) do
    if not M.VALUE_ACTIONS[a.id] then
      for _, dev in ipairs(M.DEVICES) do
        for _, slot in ipairs(input.slot_ids(a.id, dev)) do
          local b = input.get_binding(dev, a.id, slot)
          if b and not (b.axis and not b.dir) then
            local hold = M.is_hold(input, a.id, dev)
            local paired = false
            if not hold then
              for _, o in ipairs(input.ACTIONS) do
                if o.id ~= a.id and M.is_hold(input, o.id, dev) and M.ctx_conflict(input, a.ctx, o.ctx) then
                  for _, s2 in ipairs(input.slot_ids(o.id, dev)) do
                    if M.same_physical(dev, b, input.get_binding(dev, o.id, s2)) then paired = true end
                  end
                end
              end
            end
            out[#out + 1] = { id = a.id, ctx = a.ctx, device = dev, slot = slot, b = b, hold = hold,
              paired = paired }
          end
        end
      end
    end
  end
  return out
end

-- Given the set of actions that fired while `case` was pressed, return nil or an error string.
-- `fired` = { [id] = { count = n, first = seconds after press, at_release = bool } }
-- `latency`: injection-to-frame delay (0 with fake devices; one frame for real injection in the probe).
function M.judge(input, case, fired, hold_s, frame_dt, latency)
  latency = latency or 0
  local me = fired[case.id]
  if not me then return "did not fire" end
  local repeats = case.b.axis ~= nil -- stick directions repeat like ui_dir_repeat
  if not repeats and me.count ~= 1 then return "fired " .. me.count .. " times" end
  if case.hold then
    if me.first < hold_s - 1e-6 then return string.format("hold fired early at %.3f", me.first) end
    if me.first > hold_s + 2 * frame_dt + latency + 1e-3 then
      return string.format("hold fired late at %.3f", me.first)
    end
  elseif case.paired then
    if not me.at_release then return "paired short action must fire on release" end
  else
    if me.first > latency + 1e-6 then
      return string.format("unpaired short action must fire on press (%.3f)", me.first)
    end
  end
  for other in pairs(fired) do
    if other ~= case.id then
      local oa = input.get_action(other)
      if oa and M.ctx_conflict(input, case.ctx, oa.ctx) and not M.shared(input, case.device, case.id, other) then
        return "also fired " .. other
      end
    end
  end
  return nil
end

return M
