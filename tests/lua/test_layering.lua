-- Layering guard (M3-PLAN G1): sim/ and data/ are pure Lua model code.
-- They may only require core/, data/ and sim/ modules, never engine libraries.
-- data/ may not require sim/ (tables are leaves) and carries i18n keys, not prose.
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local T = {}

local SIM_PREFIXES = { "core.", "data.", "sim." }
local DATA_PREFIXES = { "core.", "data." }
local NAME_PREFIXES = { "item.", "recipe.", "tech.", "char.", "room.", "ui.", "world." }

local function starts_with(value, prefix)
  return value:sub(1, #prefix) == prefix
end

local function file_list(dir)
  local files = {}
  local pipe = io.popen("find " .. dir .. " -type f -name '*.lua' | sort")
  if not pipe then return files end
  for path in pipe:lines() do
    files[#files + 1] = path
  end
  pipe:close()
  return files
end

local function read_file(path)
  local f = assert(io.open(path, "rb"), "cannot read " .. path)
  local text = f:read("*a")
  f:close()
  return text
end

local function check_dir(dir, prefixes)
  local files = file_list(dir)
  assert(#files > 0, "no Lua files under " .. dir)
  for _, path in ipairs(files) do
    local src = read_file(path)
    for dep in src:gmatch('require%s*%(?%s*["\']([^"\']+)["\']%s*%)?') do
      local ok = false
      for _, prefix in ipairs(prefixes) do
        if starts_with(dep, prefix) then ok = true break end
      end
      assert(ok, path .. " requires non-model module: " .. dep)
    end
  end
  return #files
end

function T.sim_is_pure_model()
  local n = check_dir("assets/scripts/sim", SIM_PREFIXES)
  assert(n >= 15, "expected the M3 sim modules, found " .. n)
end

function T.data_is_pure_model()
  local n = check_dir("assets/scripts/data", DATA_PREFIXES)
  assert(n >= 8, "expected the M3 data tables, found " .. n)
end

local function walk_names(value, path)
  if type(value) ~= "table" then return end
  for k, v in pairs(value) do
    if k == "name" and type(v) == "string" then
      local ok = false
      for _, prefix in ipairs(NAME_PREFIXES) do
        if starts_with(v, prefix) then ok = true break end
      end
      assert(ok, path .. ".name is not an i18n key: " .. v)
    elseif type(v) == "table" then
      walk_names(v, path .. "." .. tostring(k))
    end
  end
end

function T.data_names_are_i18n_keys()
  walk_names(require("data.recipes").recipes, "recipes")
  for _, node in ipairs(require("data.tech").list) do
    assert(starts_with(node.name, "tech."), node.id .. " name key")
  end
  walk_names(require("data.characters").cards, "characters")
end

function T.data_sources_have_no_prose_fields()
  for _, path in ipairs(file_list("assets/scripts/data")) do
    for line in read_file(path):gmatch("[^\n]+") do
      local value = line:match('name%s*=%s*"([^"]+)"')
      if value then
        local ok = false
        for _, prefix in ipairs(NAME_PREFIXES) do
          if starts_with(value, prefix) then ok = true break end
        end
        assert(ok, path .. " literal name: " .. value)
      end
    end
  end
end

return T
