-- luatest runner: runs all tests/lua/test_*.lua suites in headless mode.
-- Each test function runs in a coroutine so long acceptance suites (test_sim_30d)
-- can yield between game days and keep the probe/watchdog tick alive.
package.path = "tests/lua/?.lua;" .. package.path

local test_files = {
  "test_core",
  "test_data_locations",
  "test_facing",
  "test_input",
  "test_lightfov",
  "test_mapbuild",
  "test_layout",
  "test_layering",
  "test_data",
  "test_sim_state",
  "test_sim_clock",
  "test_sim_inventory",
  "test_sim_needs",
  "test_sim_health",
  "test_sim_thermal",
  "test_sim_power",
  "test_sim_craft",
  "test_sim_tech",
  "test_sim_bot",
  "test_sim_weather",
  "test_sim_30d",
  "test_m3_final",
  "test_input_actions",
}

local queue = {}
local current = nil
local started = false
local finished = false

local function enqueue_suite(mod_name)
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
    queue[#queue + 1] = { label = mod_name .. "." .. name, fn = suite[name] }
  end
end

local function start_next()
  local item = table.remove(queue, 1)
  if not item then return false end
  current = { label = item.label, co = coroutine.create(item.fn) }
  return true
end

local function pump()
  local deadline = os.clock() + 0.25
  while not finished do
    if not current and not start_next() then
      finished = true
      kit_probe.finish()
      return
    end
    local ok, err = coroutine.resume(current.co)
    if not ok then
      kit_probe.info(current.label .. " failed: " .. tostring(err))
      kit_probe.check(current.label, false)
      current = nil
    elseif coroutine.status(current.co) == "dead" then
      kit_probe.check(current.label, true)
      current = nil
    else
      -- yielded: let the engine tick the probe/watchdog, resume next frame
      return
    end
    if os.clock() > deadline then return end
  end
end

function _probe(_t, _dt)
  if finished then return end
  if not started then
    started = true
    -- test_sim_30d drives two full reference-bot runs plus save/load checkpoints.
    kit_probe.timeout(900)
    for _, mod_name in ipairs(test_files) do
      enqueue_suite(mod_name)
    end
  end
  pump()
end
