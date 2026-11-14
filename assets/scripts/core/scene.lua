-- Scene & modal stack manager (UI-UX §2.2).
local M = {
  stack = {},
  modals = {},
}

local function call_enter(s, args)
  if s and s.on_enter then s:on_enter(args) end
end

local function call_exit(s)
  if s and s.on_exit then s:on_exit() end
end

function M.push(s, args)
  local top = M.stack[#M.stack]
  if top and top.on_pause then top:on_pause() end
  M.stack[#M.stack + 1] = s
  call_enter(s, args)
end

function M.pop()
  local top = table.remove(M.stack)
  call_exit(top)
  local next_top = M.stack[#M.stack]
  if next_top and next_top.on_resume then next_top:on_resume() end
  return top
end

function M.replace(s, args)
  local top = table.remove(M.stack)
  call_exit(top)
  M.stack[#M.stack + 1] = s
  call_enter(s, args)
end

function M.push_modal(m, args)
  M.modals[#M.modals + 1] = m
  call_enter(m, args)
end

function M.pop_modal()
  local top = table.remove(M.modals)
  call_exit(top)
  return top
end

function M.has_modal()
  return #M.modals > 0
end

function M.top()
  if #M.modals > 0 then return M.modals[#M.modals] end
  return M.stack[#M.stack]
end

function M.clear()
  while #M.modals > 0 do
    call_exit(table.remove(M.modals))
  end
  while #M.stack > 0 do
    call_exit(table.remove(M.stack))
  end
end

function M.update(dt)
  if #M.modals > 0 then
    local m = M.modals[#M.modals]
    if m.update then m:update(dt) end
    return
  end
  local top = M.stack[#M.stack]
  if top and top.update then top:update(dt) end
end

function M.draw()
  local top = M.stack[#M.stack]
  if top and top.draw then top:draw() end
  for i = 1, #M.modals do
    local m = M.modals[i]
    if m and m.draw then m:draw() end
  end
end

return M
