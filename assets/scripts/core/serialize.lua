-- Deterministic Lua literal serializer & sandboxed decoder.
local util = require("core.util")

local M = {}

local function is_ident(s)
  return type(s) == "string" and s:match("^[A-Za-z_][A-Za-z0-9_]*$") ~= nil
end

local function encode_val(v, buf, indent, seen)
  local tv = type(v)
  if tv == "nil" then
    buf[#buf + 1] = "nil"
  elseif tv == "boolean" then
    buf[#buf + 1] = v and "true" or "false"
  elseif tv == "number" then
    if v ~= v then
      buf[#buf + 1] = "0/0"
    elseif v == math.huge then
      buf[#buf + 1] = "math.huge"
    elseif v == -math.huge then
      buf[#buf + 1] = "-math.huge"
    elseif math.type(v) == "integer" then
      if v == math.mininteger then
        -- the literal -9223372036854775808 parses as a float in Lua
        buf[#buf + 1] = "(-9223372036854775807-1)"
      else
        buf[#buf + 1] = string.format("%d", v)
      end
    else
      -- shortest round-tripping representation (deterministic)
      local str = string.format("%.15g", v)
      if tonumber(str) ~= v then
        str = string.format("%.16g", v)
        if tonumber(str) ~= v then
          str = string.format("%.17g", v)
        end
      end
      if v == 0 then
        str = (1 / v < 0) and "-0.0" or "0.0"
      elseif not str:find("[%.eE]") then
        str = str .. ".0"
      end
      buf[#buf + 1] = str
    end
  elseif tv == "string" then
    buf[#buf + 1] = string.format("%q", v)
  elseif tv == "table" then
    if seen[v] then
      error("cannot serialize cyclic table")
    end
    seen[v] = true

    local n = #v
    local keys = util.sorted_keys(v)
    if #keys == 0 then
      buf[#buf + 1] = "{}"
      seen[v] = nil
      return
    end

    buf[#buf + 1] = "{\n"
    local pad = string.rep("  ", indent + 1)
    -- Array part 1..n first if contiguous
    local array_done = {}
    for i = 1, n do
      if v[i] ~= nil then
        array_done[i] = true
        buf[#buf + 1] = pad
        encode_val(v[i], buf, indent + 1, seen)
        buf[#buf + 1] = ",\n"
      end
    end
    for _, k in ipairs(keys) do
      if not array_done[k] then
        buf[#buf + 1] = pad
        if is_ident(k) then
          buf[#buf + 1] = k .. " = "
        else
          buf[#buf + 1] = "["
          encode_val(k, buf, indent + 1, seen)
          buf[#buf + 1] = "] = "
        end
        encode_val(v[k], buf, indent + 1, seen)
        buf[#buf + 1] = ",\n"
      end
    end
    buf[#buf + 1] = string.rep("  ", indent) .. "}"
    seen[v] = nil
  else
    error("unsupported type for serialization: " .. tv)
  end
end

function M.encode(val)
  local buf = { "return " }
  encode_val(val, buf, 0, {})
  buf[#buf + 1] = "\n"
  return table.concat(buf)
end

function M.decode(str)
  if type(str) ~= "string" then
    return false, "expected string"
  end
  local env = { math = { huge = math.huge } }
  local chunk, err = load(str, "save", "t", env)
  if not chunk then
    return false, err
  end
  local ok, val = pcall(chunk)
  if not ok then
    return false, val
  end
  return true, val
end

return M
