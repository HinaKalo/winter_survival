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
  -- Recursive enumeration includes sim/cmd, sim/query and sim/schema when present.
  return assert(sys.list_files(dir, ".lua"))
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

-- Strip comments and return every double-quoted string literal in a Lua source (line, text).
local function string_literals(src)
  local out = {}
  local lineno = 1
  local i, n = 1, #src
  while i <= n do
    local c = src:sub(i, i)
    if c == "\n" then
      lineno = lineno + 1
      i = i + 1
    elseif c == "-" and src:sub(i, i + 1) == "--" then
      local long = src:match("^%[(=*)%[", i + 2)
      if long then
        local close = "]" .. long .. "]"
        local e = src:find(close, i + 2, true) or n
        for _ in src:sub(i, e):gmatch("\n") do lineno = lineno + 1 end
        i = e + #close
      else
        local e = src:find("\n", i, true) or n + 1
        i = e
      end
    elseif c == '"' then
      local j = i + 1
      local buf = {}
      while j <= n do
        local d = src:sub(j, j)
        if d == "\\" then
          buf[#buf + 1] = src:sub(j, j + 1)
          j = j + 2
        elseif d == '"' or d == "\n" then
          break
        else
          buf[#buf + 1] = d
          j = j + 1
        end
      end
      out[#out + 1] = { line = lineno, text = table.concat(buf) }
      i = j + 1
    elseif c == "'" then
      local j = src:find("'", i + 1, true) or n
      i = j + 1
    else
      i = i + 1
    end
  end
  return out
end

-- Every double-quoted literal in data/ must be an identifier-like key (item ids, i18n keys,
-- station kinds, ...), never a sentence. Exempt: template grid rows (homes/*.lua) and
-- legend.lua symbol keys, which are map pictures, not text.
function T.data_literals_are_identifiers()
  local checked = 0
  for _, path in ipairs(file_list("assets/scripts/data")) do
    -- map templates (homes, M2 locations) contain grid rows / grid fill characters
    local is_template = path:find("/data/homes/", 1, true) ~= nil or path:find("/data/locations/", 1, true) ~= nil
    local is_legend = path:match("/legend%.lua$") ~= nil
    if not is_legend then
      for _, lit in ipairs(string_literals(read_file(path))) do
        local exempt = is_template and (lit.text:match("^[#=%.,%+Dw%a ]+$") ~= nil and lit.text:find("[#%.,]") ~= nil)
        if not exempt then
          checked = checked + 1
          -- identifiers / i18n keys, or asset paths (M2 data/props.lua sprite sheets)
          assert(lit.text:match("^[A-Za-z0-9_.%-]+$") or lit.text:match("^assets/[A-Za-z0-9_.%-/]+$"),
            path .. ":" .. lit.line .. " literal is not an identifier/i18n key: \"" .. lit.text .. "\"")
        end
      end
    end
  end
  assert(checked > 100, "literal scan looked at too few strings: " .. checked)
end

function T.literal_scanner_ignores_comments()
  local lits = string_literals('local x = "a_b" -- "free text here"\n--[[ "block text" ]] local y = "c.d"')
  assert(#lits == 2 and lits[1].text == "a_b" and lits[2].text == "c.d", #lits)
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
