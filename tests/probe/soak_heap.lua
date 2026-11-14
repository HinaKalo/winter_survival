-- M1 memory soak probe: generate ~1 MB Lua garbage/frame for 30s, then verify GC reclaims below peak and < 64 MB.
local probe = require("kit_probe")

probe.timeout(45)

local now = 0

local function scenario()
  local start_t = now
  local end_t = start_t + 30.0
  local chunk = string.rep("x", 64 * 1024) -- 64 KB base string (unique per concat)
  local frame = 0

  while now < end_t do
    frame = frame + 1
    -- Allocate ~1 MB of short-lived garbage per frame (16 x ~64 KB strings + table)
    local trash = {}
    for i = 1, 16 do
      trash[i] = chunk .. tostring(frame) .. "_" .. tostring(i)
    end
    coroutine.yield()
  end

  collectgarbage("collect")
  collectgarbage("collect")
  for _ = 1, 3 do
    coroutine.yield()
  end

  local h = sys.lua_heap()
  local mb = 1024 * 1024
  probe.info(string.format("soak_heap: frames=%d bytes=%.2f MB peak=%.2f MB", frame, h.bytes / mb, h.peak / mb))
  probe.check("lua_heap().bytes < peak after soak", h.bytes < h.peak)
  probe.check("lua_heap().bytes < 64 MB", h.bytes < 64 * mb)
  probe.finish()
end

local co = coroutine.create(scenario)

function _probe(t, dt)
  now = t
  if coroutine.status(co) == "dead" then
    return
  end
  local ok, err = coroutine.resume(co)
  if not ok then
    error(err, 0)
  end
end
