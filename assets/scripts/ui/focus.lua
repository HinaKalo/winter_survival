-- Immediate-mode spatial & modal focus navigation (UI-UX §5).
local input = require("core.input")
local theme = require("ui.theme")

local M = {
  groups = {},
  current = nil,
  hover = nil,
  visible = false,
  _last_mx = nil,
  _last_my = nil,
  _from_dir = {}, -- [id] = last element id we came from
}

local function top_group()
  return M.groups[#M.groups]
end

local function find_group(id)
  for i = #M.groups, 1, -1 do
    if M.groups[i].id == id then return M.groups[i] end
  end
  return nil
end

-- While a modal/panel draws, it owns registration. Without an explicit target,
-- registrations from screens below a modal are ignored (UI-UX §5.5).
function M.set_target(group_id)
  M._target = group_id
end

function M.clear_target()
  M._target = nil
end

function M.push_group(id, opts)
  opts = opts or {}
  local g = {
    id = id,
    modal = opts.modal or false,
    default = opts.default,
    remember = opts.default,
    on_cancel = opts.on_cancel,
    wrap = opts.wrap or false,
    items = {},
    by_id = {},
  }
  M.groups[#M.groups + 1] = g
  M.current = g.default
  return g
end

function M.pop_group()
  local popped = table.remove(M.groups)
  local g = top_group()
  if g then
    M.current = g.remember or g.default
  else
    M.current = nil
  end
  return popped
end

function M.clear()
  M.groups = {}
  M.current = nil
  M.hover = nil
  M._target = nil
end

function M.begin_frame()
  for i = 1, #M.groups do
    M.groups[i].items = {}
    M.groups[i].by_id = {}
  end
end

function M.register(elem)
  local g
  if M._target then
    g = find_group(M._target)
  else
    g = top_group()
    if g and g.modal then return end
  end
  if not g then return end
  -- Only top group accepts registrations when modal or active
  if elem.focusable == false then return end
  g.items[#g.items + 1] = elem
  g.by_id[elem.id] = elem
end

local function point_in(mx, my, r)
  return mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h
end

local DIR_VEC = {
  up    = { 0, -1 },
  down  = { 0,  1 },
  left  = { -1, 0 },
  right = { 1,  0 },
}

local function rect_center(r)
  return r.x + r.w * 0.5, r.y + r.h * 0.5
end

local function edge_gap(a, b, dir)
  if dir == "right" then return math.max(0, b.x - (a.x + a.w))
  elseif dir == "left" then return math.max(0, a.x - (b.x + b.w))
  elseif dir == "down" then return math.max(0, b.y - (a.y + a.h))
  else return math.max(0, a.y - (b.y + b.h)) end
end

function M.find_next(g, cur_elem, dir)
  if not g or #g.items == 0 then return nil end
  if not cur_elem then
    return g.by_id[g.remember] or g.by_id[g.default] or g.items[1]
  end

  if cur_elem.nav and cur_elem.nav[dir] and g.by_id[cur_elem.nav[dir]] then
    return g.by_id[cur_elem.nav[dir]]
  end

  local d = DIR_VEC[dir]
  local c0x, c0y = rect_center(cur_elem.rect)

  local function pick(cone_strict)
    local best = nil
    local best_score = math.huge
    for _, cand in ipairs(g.items) do
      if cand.id ~= cur_elem.id then
        local cix, ciy = rect_center(cand.rect)
        local vx, vy = cix - c0x, ciy - c0y
        local a = vx * d[1] + vy * d[2]
        if a > 0 then
          local off = math.abs(vx * (-d[2]) + vy * d[1])
          local in_cone = (not cone_strict) or (off <= 1.5 * (a + 8))
          if in_cone then
            local gap = edge_gap(cur_elem.rect, cand.rect, dir)
            local cross_group = (cand.sub_group ~= cur_elem.sub_group) and 120 or 0
            local cone_pen = cone_strict and 0 or 400
            local score = gap + 2.0 * off + 0.25 * a + cross_group + cone_pen
            local tie = false
            if math.abs(score - best_score) < 1.0 and best then
              if M._from_dir[cur_elem.id] == cand.id then
                tie = true
              elseif cand.rect.y ~= best.rect.y then
                tie = cand.rect.y < best.rect.y
              else
                tie = cand.rect.x < best.rect.x
              end
            end
            if score < best_score - 1.0 or tie then
              best_score = score
              best = cand
            end
          end
        end
      end
    end
    return best
  end

  local nxt = pick(true) or pick(false)
  if not nxt and g.wrap and #g.items > 1 then
    if dir == "down" or dir == "right" then
      nxt = g.items[1]
    else
      nxt = g.items[#g.items]
    end
  end
  return nxt
end

function M.update(dt)
  local g = top_group()
  if not g then return end

  -- Update hover from mouse position
  local mx, my = ui.mouse_pos()
  local moved = false
  if M._last_mx == nil then
    M._last_mx, M._last_my = mx, my
  else
    local dx, dy = mx - M._last_mx, my - M._last_my
    if dx * dx + dy * dy >= 9 then
      M._last_mx, M._last_my = mx, my
      moved = true
    end
  end

  local hovered = nil
  for i = #g.items, 1, -1 do
    local it = g.items[i]
    if point_in(mx, my, it.rect) then
      hovered = it
      break
    end
  end
  M.hover = hovered and hovered.id or nil

  if moved and hovered then
    M.visible = false
    M.current = hovered.id
    g.remember = hovered.id
  end

  -- Device visibility sync
  local dev = input.last_device()
  if dev == "mouse" then
    M.visible = false
  elseif dev == "keyboard" or dev == "pad" then
    if input.pressed("ui_up") or input.pressed("ui_down") or
       input.pressed("ui_left") or input.pressed("ui_right") or
       input.pressed("confirm") or input.pressed("cancel") then
      M.visible = true
    end
  end

  -- Ensure current points to a valid item if possible
  local cur_elem = M.current and g.by_id[M.current] or nil
  if not cur_elem and #g.items > 0 then
    cur_elem = g.by_id[g.remember] or g.by_id[g.default] or g.items[1]
    M.current = cur_elem and cur_elem.id or nil
  end

  -- Directional navigation
  local dir = input.ui_dir_repeat(dt)
  if dir and cur_elem then
    M.visible = true
    local handled = cur_elem.on_dir and cur_elem.on_dir(dir)
    if not handled then
      local nxt = M.find_next(g, cur_elem, dir)
      if nxt then
        M._from_dir[nxt.id] = cur_elem.id
        M.current = nxt.id
        g.remember = nxt.id
        cur_elem = nxt
      end
    end
  end

  -- Confirm (keyboard/pad)
  if (dev ~= "mouse" or M.visible) and input.pressed("confirm") and cur_elem then
    if cur_elem.enabled == false then
      kit_audio.sfx("sfx/ui", 0.5, 0.7)
    elseif cur_elem.on_activate then
      kit_audio.sfx("sfx/ui", 0.7, 1.0)
      cur_elem.on_activate()
    end
  end

  -- Cancel (Esc / B / mouse right click)
  if input.pressed("cancel") and g.on_cancel then
    g.on_cancel()
  end
end

function M.is_focused(id)
  return M.current == id
end

function M.is_hovered(id)
  return M.hover == id
end

function M.show_ring(id)
  return M.visible and M.current == id
end

function M.draw_ring(r)
  local pulse = 1.0
  if not theme.reduce_flash then
    pulse = 0.7 + 0.3 * math.sin(theme._blink_t * 6.0)
  end
  local col = theme.high_contrast and theme.colors.white or theme.colors.accent
  theme.set_color(col, pulse)
  -- 2px outer ring
  ui.rect(r.x - 2, r.y - 2, r.w + 4, 2)
  ui.rect(r.x - 2, r.y + r.h, r.w + 4, 2)
  ui.rect(r.x - 2, r.y, 2, r.h)
  ui.rect(r.x + r.w, r.y, 2, r.h)
end

-- Reachability audit (UI-UX §5.7): BFS from default/first item using 4 directions.
function M.audit()
  local g = top_group()
  if not g or #g.items == 0 then return { ok = true, visited = 0, total = 0 } end
  local start = g.by_id[g.default] or g.items[1]
  local visited = {}
  local queue = { start }
  visited[start.id] = true
  local head = 1
  while head <= #queue do
    local cur = queue[head]
    head = head + 1
    for _, dir in ipairs({ "up", "down", "left", "right" }) do
      local nxt = M.find_next(g, cur, dir)
      if nxt and not visited[nxt.id] then
        visited[nxt.id] = true
        queue[#queue + 1] = nxt
      end
    end
  end
  local unreachable = {}
  for _, it in ipairs(g.items) do
    if not visited[it.id] and it.enabled ~= false then
      unreachable[#unreachable + 1] = it.id
    end
  end
  return {
    ok = #unreachable == 0,
    visited = #queue,
    total = #g.items,
    unreachable = unreachable,
  }
end

return M
