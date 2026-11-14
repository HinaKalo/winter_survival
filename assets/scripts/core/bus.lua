-- Simple synchronous event bus.
local M = {
  listeners = {},
}

function M.on(evt, fn)
  local list = M.listeners[evt]
  if not list then
    list = {}
    M.listeners[evt] = list
  end
  list[#list + 1] = fn
  return function()
    M.off(evt, fn)
  end
end

function M.off(evt, fn)
  local list = M.listeners[evt]
  if not list then return end
  for i = #list, 1, -1 do
    if list[i] == fn then
      table.remove(list, i)
    end
  end
end

function M.emit(evt, data)
  local list = M.listeners[evt]
  if not list then return end
  -- Iterate a snapshot in case listeners unsubscribe during emit
  local snap = {}
  for i = 1, #list do snap[i] = list[i] end
  for i = 1, #snap do
    snap[i](data)
  end
end

function M.clear()
  M.listeners = {}
end

return M
