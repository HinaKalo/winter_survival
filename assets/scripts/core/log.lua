local M = {
  level = 1, -- 0=debug, 1=info, 2=warn, 3=error
}

local function emit(tag, fmt, ...)
  if select("#", ...) > 0 then
    print(string.format("[%s] " .. fmt, tag, ...))
  else
    print(string.format("[%s] %s", tag, tostring(fmt)))
  end
end

function M.debug(fmt, ...)
  if M.level <= 0 then emit("DBG", fmt, ...) end
end

function M.info(fmt, ...)
  if M.level <= 1 then emit("INF", fmt, ...) end
end

function M.warn(fmt, ...)
  if M.level <= 2 then emit("WRN", fmt, ...) end
end

function M.err(fmt, ...)
  if M.level <= 3 then emit("ERR", fmt, ...) end
end

return M
