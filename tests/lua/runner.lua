-- luatest runner: runs all tests/lua/test_*.lua suites in headless mode.
package.path = "tests/lua/?.lua;" .. package.path

local ran = false

local test_files = {
  "test_core",
  "test_data_locations",
  "test_facing",
  "test_input",
  "test_lightfov",
  "test_mapbuild",
}

local function run_suite(mod_name)
  local ok_req, suite = pcall(require, mod_name)
  if not ok_req then
    kit_probe.check(mod_name .. " (load)", false)
    kit_probe.info("load error: " .. tostring(suite))
    return
  end
  if type(suite) ~= "table" then
    kit_probe.check(mod_name .. " (table)", false)
    return
  end
  local names = {}
  for k, v in pairs(suite) do
    if type(v) == "function" then
      names[#names + 1] = k
    end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local ok, err = pcall(suite[name])
    if not ok then
      kit_probe.info(mod_name .. "." .. name .. " failed: " .. tostring(err))
    end
    kit_probe.check(mod_name .. "." .. name, ok)
  end
end

function _probe(_t, _dt)
  if ran then return end
  ran = true
  for _, mod_name in ipairs(test_files) do
    run_suite(mod_name)
  end
  kit_probe.finish()
end
