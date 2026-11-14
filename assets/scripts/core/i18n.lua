-- Runtime i18n module: loads assets/i18n/{zh,en,ko}.lua, supports {name} substitution
-- and English pluralization {n|one|other}.
local M = {
  lang = "zh",
  langs = { "zh", "en", "ko" },
  tables = {},
}

local function load_lang(code)
  if M.tables[code] then return M.tables[code] end
  local ok, tbl = pcall(dofile, "assets/i18n/" .. code .. ".lua")
  if ok and type(tbl) == "table" then
    M.tables[code] = tbl
    return tbl
  end
  M.tables[code] = {}
  return M.tables[code]
end

function M.init(lang)
  load_lang("zh")
  load_lang("en")
  load_lang("ko")
  M.set_lang(lang or "zh")
end

function M.set_lang(lang)
  for _, c in ipairs(M.langs) do
    if c == lang then
      M.lang = lang
      load_lang(lang)
      return true
    end
  end
  return false
end

function M.get_lang()
  return M.lang
end

function M.t(key, vars)
  local tbl = M.tables[M.lang] or load_lang(M.lang)
  local str = tbl[key]
  if str == nil and M.lang ~= "zh" then
    local zh = M.tables["zh"] or load_lang("zh")
    str = zh[key]
  end
  if str == nil then return tostring(key) end
  if not vars then return str end

  -- Plural pattern: {var|singular|plural}
  str = str:gsub("{([%w_]+)|([^|{}]+)|([^|{}]+)}", function(k, one, other)
    local n = tonumber(vars[k]) or 0
    if M.lang == "en" and n == 1 then
      return one
    end
    return other
  end)

  -- Simple placeholder: {var}
  str = str:gsub("{([%w_]+)}", function(k)
    local v = vars[k]
    if v == nil then return "{" .. k .. "}" end
    return tostring(v)
  end)
  return str
end

return M
