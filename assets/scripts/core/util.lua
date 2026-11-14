local M = {}

function M.clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function M.lerp(a, b, t)
  return a + (b - a) * t
end

function M.shallow_copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do
    out[k] = v
  end
  return out
end

function M.deep_copy(t, seen)
  if type(t) ~= "table" then return t end
  seen = seen or {}
  if seen[t] then return seen[t] end
  local out = {}
  seen[t] = out
  for k, v in pairs(t) do
    out[M.deep_copy(k, seen)] = M.deep_copy(v, seen)
  end
  return out
end

function M.contains(list, val)
  for i = 1, #list do
    if list[i] == val then return true end
  end
  return false
end

function M.sorted_keys(t)
  local ks = {}
  for k in pairs(t) do
    ks[#ks + 1] = k
  end
  table.sort(ks, function(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta < tb end
    if ta == "number" or ta == "string" then return a < b end
    return tostring(a) < tostring(b)
  end)
  return ks
end

return M
