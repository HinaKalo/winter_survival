local serialize = require("core.serialize")
local util = require("core.util")

local M = {
  SETTINGS_VERSION = 1,
}

function M.write(name, data)
  local ok, text = pcall(serialize.encode, data)
  if not ok then return false, text end
  return sys.save_write(name, text)
end

function M.read(name)
  local raw = sys.save_read(name)
  if not raw then return false, "not_found" end
  local ok, data = serialize.decode(raw)
  if not ok or type(data) ~= "table" then
    return false, "corrupt"
  end
  return true, data
end

function M.exists(name)
  return sys.save_exists(name)
end

function M.delete(name)
  return sys.save_delete(name)
end

function M.list()
  return sys.save_list()
end

function M.load_settings(defaults)
  local out = util.deep_copy(defaults)
  local ok, data = M.read("settings")
  if not ok then return out, false end
  if type(data.version) ~= "number" then return out, false end
  for k, v in pairs(data) do
    if k ~= "version" and out[k] ~= nil and type(out[k]) == type(v) then
      if type(v) == "table" then
        out[k] = util.deep_copy(v)
      else
        out[k] = v
      end
    end
  end
  if type(data.bindings) == "table" then
    out.bindings = util.deep_copy(data.bindings)
  end
  return out, true
end

function M.save_settings(settings)
  local payload = util.deep_copy(settings)
  payload.version = M.SETTINGS_VERSION
  return M.write("settings", payload)
end

return M
