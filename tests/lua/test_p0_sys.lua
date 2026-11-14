-- 验收测试，编码代理不得修改（P0-0，主代理编写；见 docs/P0-PLAN.md §3.0）。
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local T = {}

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("a")
  f:close()
  return s
end

local function index_of(list, v)
  for i, x in ipairs(list) do if x == v then return i end end
end

function T.launch_opts_shape()
  assert(type(sys) == "table" and type(sys.launch_opts) == "function", "sys.launch_opts missing")
  local o = sys.launch_opts()
  assert(type(o) == "table", "launch_opts returns a table")
  assert(type(o.dev) == "boolean", "dev is a boolean")
  -- luatest is started without --dev / --scene / --fixture
  assert(o.dev == false and o.scene == nil and o.fixture == nil, "luatest has no dev/scene/fixture options")
end

function T.list_files_recursive_sorted_forward_slashes()
  assert(type(sys.list_files) == "function", "sys.list_files missing")
  local l = assert(sys.list_files("assets/scripts", ".lua"))
  assert(index_of(l, "assets/scripts/data/locations/street_block.lua"), "recursive: nested file listed")
  assert(index_of(l, "assets/scripts/sim/sim.lua"), "sim/sim.lua listed")
  for i, p in ipairs(l) do
    assert(not p:find("\\", 1, true), "forward slashes only: " .. p)
    assert(p:sub(-4) == ".lua", "suffix filter: " .. p)
    assert(p:sub(1, 15) == "assets/scripts/", "paths are relative to the project root: " .. p)
    if i > 1 then assert(l[i - 1] < p, "byte order: " .. l[i - 1] .. " !< " .. p) end
  end
  -- directories are never listed, files only
  assert(not index_of(l, "assets/scripts/data"), "no directories")
end

function T.list_files_without_suffix_and_missing_dir()
  local all = assert(sys.list_files("tests/lua"))
  assert(index_of(all, "tests/lua/runner.lua") and index_of(all, "tests/lua/test_p0_sys.lua"))
  local none = sys.list_files("tests/does_not_exist", ".lua")
  assert(type(none) == "table" and #none == 0, "missing directory -> empty table")
end

function T.list_files_rejects_bad_dirs()
  for _, d in ipairs({ "src", "/etc", "../winter_survival", "assets/../src", "tests/..", "assets\\scripts",
    "", "zig-out", "C:/Windows", "assets/scripts/../../src" }) do
    local r, err = sys.list_files(d, ".lua")
    assert(r == nil and err == "bad_dir", "must reject " .. d .. " (got " .. tostring(r) .. ", " .. tostring(err) .. ")")
  end
end

function T.runner_discovers_suites()
  local src = read("tests/lua/runner.lua")
  assert(src:find("list_files", 1, true), "runner uses sys.list_files")
  assert(not src:find('"test_core"', 1, true), "runner has no hand-written suite list")
  -- every test_*.lua on disk is a suite the runner will pick up
  local n = 0
  for _, p in ipairs(sys.list_files("tests/lua", ".lua")) do
    if p:match("^tests/lua/test_[%w_]+%.lua$") then n = n + 1 end
  end
  assert(n >= 23, "expected the merged suites on disk, found " .. n)
end

function T.layering_has_no_popen()
  local src = read("tests/lua/test_layering.lua")
  assert(not src:find("popen", 1, true), "test_layering must not use io.popen (fails on Windows)")
  assert(src:find("list_files", 1, true), "test_layering lists files with sys.list_files")
end

return T
