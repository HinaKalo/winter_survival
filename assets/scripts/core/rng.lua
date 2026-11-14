-- Deterministic 32-bit PRNG (Mulberry32) with plain-table state for serialization.
local M = {}

function M.new(seed)
  local s = math.floor(tonumber(seed) or 1) & 0xFFFFFFFF
  if s == 0 then s = 0x6D2B79F5 end
  return { s = s }
end

function M.next_u32(r)
  r.s = (r.s + 0x6D2B79F5) & 0xFFFFFFFF
  local t = r.s
  t = ((t ~ (t >> 15)) * (t | 1)) & 0xFFFFFFFF
  t = (t ~ (t + ((t ~ (t >> 7)) * (t | 61)) & 0xFFFFFFFF)) & 0xFFFFFFFF
  return (t ~ (t >> 14)) & 0xFFFFFFFF
end

function M.float(r)
  return M.next_u32(r) / 4294967296.0
end

function M.int(r, lo, hi)
  if hi <= lo then return lo end
  local span = hi - lo + 1
  return lo + (M.next_u32(r) % span)
end

function M.choice(r, list)
  if #list == 0 then return nil end
  return list[M.int(r, 1, #list)]
end

function M.shuffle(r, list)
  for i = #list, 2, -1 do
    local j = M.int(r, 1, i)
    list[i], list[j] = list[j], list[i]
  end
  return list
end

return M
