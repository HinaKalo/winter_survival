-- 验收测试（主代理编写，编码代理不得修改；认为有误时停下报告）。
-- P0-PLAN §3.2 / §4 P0-2：命令注册式。阶段 A 与阶段 B 都必须通过本文件。
--
-- 本文件额外冻结的接口（P0-PLAN §3.2 未写明的部分，以此为准）：
--   commands.DOMAINS                    有序列表，见 §3.2
--   commands.domain(d) -> reg           reg(short_name, fn, spec)；short_name 也可写全名 "d.x"，前缀不符 error
--   commands.reserve(kind, spec)
--   commands.list() -> { kind... }      已注册的全部新名（含预留），排序
--   commands.spec(kind) -> spec | nil   { args = { {name, type, max=?, enum_err=?}, ... }, phase=?, phase_err=? }
--   commands.aliases() -> { [old]=new } 副本
--   commands.can(state, kind) -> bool   新名或别名
--   commands.run(state, cmd) -> ok, err, extra
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local sim = require("sim.sim")
local state_mod = require("sim.state")
local commands = require("sim.commands")
local items = require("data.items").items
local recipes = require("data.recipes").recipes
local tech = require("data.tech")

local T = {}

local ALIASES = {
  eat = "needs.eat", drink = "needs.drink", use = "needs.use", sleep = "needs.sleep", wake = "needs.wake",
  treat = "needs.treat",
  equip = "home.equip", unequip = "home.unequip", assign = "home.assign", activity = "home.set_activity",
  toggle = "home.toggle", set_level = "home.set_level", set_door = "home.set_door", board = "home.board",
  end_day = "home.end_day",
  craft = "craft.start", cancel_job = "craft.cancel",
  research = "tech.start", cancel_research = "tech.cancel", learn_blueprint = "tech.learn_blueprint",
  night_roles = "night.set_roles",
  expedition = "raid.autoresolve",
}

local RESERVED = {
  "trade.offer", "trade.accept", "trade.leave", "travel.go", "raid.begin", "raid.commit",
  "story.choose", "night.set_role", "night.set_target", "night.set_loadout",
}

local DOMAINS = { "home", "needs", "craft", "tech", "night", "raid", "trade", "travel", "story" }

-- ---------------------------------------------------------------- helpers

local function sorted_keys(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  table.sort(out)
  return out
end

local FIRST_ITEM = sorted_keys(items)[1]
local FIRST_RECIPE = sorted_keys(recipes)[1]
local FIRST_TECH = sorted_keys(tech.by_id)[1]

local function new_state()
  return assert(sim.new(1))
end

local function to_phase(s, phase)
  for _ = 1, 400 do
    if s.clock.phase == phase then return s end
    sim.step(s, 10)
  end
  error("could not reach phase " .. phase)
end

local function c1(s) return s.party.order[1] end
local function c2(s) return s.party.order[2] end

-- encoding without log/errors: "failed commands leave the model untouched"
local function model_bytes(s)
  local log, errors = s.log, s.errors
  s.log, s.errors = nil, nil
  local ok, text = pcall(state_mod.encode, s)
  s.log, s.errors = log, errors
  assert(ok, text)
  return text
end

local function run(s, cmd)
  return commands.run(s, cmd)
end

local function expect_err(s, cmd, want, label)
  local ok, err = run(s, cmd)
  assert(ok == false, (label or cmd.kind) .. ": expected failure " .. want)
  assert(err == want, (label or cmd.kind) .. ": expected " .. want .. ", got " .. tostring(err))
end

-- ---------------------------------------------------------------- registry shape

function T.domains_and_names()
  assert(type(commands.DOMAINS) == "table", "DOMAINS")
  assert(#commands.DOMAINS == #DOMAINS, "DOMAINS length")
  for i, d in ipairs(DOMAINS) do assert(commands.DOMAINS[i] == d, "DOMAINS[" .. i .. "]") end
  local list = commands.list()
  assert(#list > 0)
  local seen = {}
  for i, kind in ipairs(list) do
    assert(kind:match("^[a-z]+%.[a-z_]+$"), "bad name " .. kind)
    assert(not seen[kind], "duplicate in list " .. kind)
    seen[kind] = true
    if i > 1 then assert(list[i - 1] < kind, "list() must be sorted") end
    local dom = kind:match("^([a-z]+)%.")
    local known = false
    for _, d in ipairs(DOMAINS) do known = known or d == dom end
    assert(known, "unknown domain in " .. kind)
    local sp = commands.spec(kind)
    assert(type(sp) == "table" and type(sp.args) == "table", "spec " .. kind)
    for _, a in ipairs(sp.args) do
      assert(type(a[1]) == "string" and a[2] ~= nil, "arg entry " .. kind)
    end
  end
  for _, new in pairs(ALIASES) do assert(seen[new], "missing new name " .. new) end
  for _, r in ipairs(RESERVED) do assert(seen[r], "missing reserved " .. r) end
  assert(commands.spec("zz.nothing") == nil)
end

function T.aliases_exact()
  local a = commands.aliases()
  for old, new in pairs(ALIASES) do
    assert(a[old] == new, "alias " .. old .. " -> " .. tostring(a[old]))
  end
  for old, new in pairs(a) do
    assert(ALIASES[old] == new, "unexpected alias " .. old)
    assert(commands.spec(new), "alias target not registered " .. new)
  end
  a.eat = "zz.mutated"
  assert(commands.aliases().eat == "needs.eat", "aliases() must return a copy")
end

function T.can()
  local s = new_state()
  assert(commands.can(s, "needs.eat"))
  assert(commands.can(s, "eat"), "aliases are accepted")
  assert(commands.can(s, "trade.offer"), "reserved commands are registered")
  assert(not commands.can(s, "zz.nothing"))
  assert(not commands.can(s, 42))
end

function T.registration_errors()
  local fn = function() return true end
  local reg = commands.domain("needs")
  assert(not pcall(reg, "eat", fn, { args = {} }), "duplicate registration must error")
  assert(not pcall(reg, "home.zz_test", fn, { args = {} }), "prefix mismatch must error")
  assert(not pcall(reg, "Bad-Name", fn, { args = {} }), "bad name must error")
  assert(not pcall(commands.reserve, "trade.offer", { args = {} }), "duplicate reserve must error")
  assert(not pcall(commands.domain, "zzdomain"), "domain not in DOMAINS must error")
  assert(commands.spec("home.zz_test") == nil, "failed registration leaves no trace")
end

-- ---------------------------------------------------------------- run(): envelope

function T.envelope_errors()
  local s = new_state()
  local before = model_bytes(s)
  expect_err(s, { kind = 42 }, "bad_command", "kind=42")
  local ok, err = run(s, "eat")
  assert(ok == false and err == "bad_command")
  ok, err = run(s, {})
  assert(ok == false and err == "bad_command")
  expect_err(s, { kind = "zz.nothing" }, "unknown_command")
  expect_err(s, { kind = "sleep_until_dawn" }, "unknown_command")
  -- cmd[1] is accepted for the kind (M3 compatibility)
  ok, err = run(s, { "needs.eat", char = "nobody" })
  assert(ok == false and err == "no_char", tostring(err))
  assert(model_bytes(s) == before, "envelope failures do not touch the model")
end

function T.error_codes_are_short_keys()
  local s = new_state()
  local cases = {
    { kind = "zz.nothing" }, { kind = "needs.eat", char = "nobody" }, { kind = "craft.start", char = c1(s), recipe = "zz" },
    { kind = "home.set_activity", char = c1(s), value = "zz" }, { kind = "raid.autoresolve", squad = { c1(s) } },
  }
  for _, cmd in ipairs(cases) do
    local ok, err = run(s, cmd)
    assert(ok == false and type(err) == "string" and err:match("^[a-z_]+$"), cmd.kind .. ": " .. tostring(err))
  end
end

function T.failure_log_uses_submitted_name()
  local s = new_state()
  run(s, { kind = "eat", char = "nobody" })
  local e = s.log[#s.log]
  assert(e.event == "command_failed" and e.kind == "eat" and e.err == "no_char", "old name logged as submitted")
  run(s, { kind = "needs.eat", char = "nobody" })
  e = s.log[#s.log]
  assert(e.event == "command_failed" and e.kind == "needs.eat" and e.err == "no_char")
end

function T.aliases_behave_like_new_names()
  local a, b = new_state(), new_state()
  local ok1 = run(a, { kind = "activity", char = c1(a), value = "work" })
  local ok2 = run(b, { kind = "home.set_activity", char = c1(b), value = "work" })
  assert(ok1 and ok2)
  assert(a.party.chars[c1(a)].activity == "work")
  assert(model_bytes(a) == model_bytes(b), "alias and new name give the same model")
end

-- ---------------------------------------------------------------- phases

function T.phase_checks()
  local s = new_state()
  assert(s.clock.phase == "day")
  expect_err(s, { kind = "night.set_roles" }, "not_dusk")
  expect_err(s, { kind = "raid.autoresolve", squad = { c1(s) } }, "not_night")
  local ok, err = run(s, { kind = "home.end_day" })
  assert(ok, tostring(err))
  assert(s.clock.phase == "dusk", "home.end_day runs to dusk through commands.run")
  expect_err(s, { kind = "home.end_day" }, "not_day")
  ok, err = run(s, { kind = "night.set_roles", roles = {} })
  assert(ok, tostring(err))
end

function T.sim_command_end_day_goes_through_registry()
  local s = new_state()
  local ok = sim.command(s, { kind = "end_day" })
  assert(ok and s.clock.phase == "dusk")
  local ok2, err = sim.command(s, { kind = "end_day" })
  assert(ok2 == false and err == "not_day")
  local e = s.log[#s.log]
  assert(e.event == "command_failed" and e.kind == "end_day" and e.err == "not_day")
end

-- ---------------------------------------------------------------- argument types

function T.arg_types_negative()
  local s = new_state()
  local c = c1(s)
  -- char
  expect_err(s, { kind = "needs.eat", char = "nobody" }, "no_char")
  expect_err(s, { kind = "needs.eat", char = 42 }, "no_char")
  expect_err(s, { kind = "needs.eat" }, "no_char", "missing required char")
  -- item / recipe / tech
  expect_err(s, { kind = "needs.eat", char = c, item = "zz_no_item" }, "unknown_item")
  expect_err(s, { kind = "craft.start", char = c, recipe = "zz_no_recipe" }, "unknown_recipe")
  expect_err(s, { kind = "tech.start", char = c, tech = "zz_no_tech" }, "unknown_tech")
  -- room / station / job
  expect_err(s, { kind = "home.assign", char = c, room = "zz_no_room" }, "bad_room")
  expect_err(s, { kind = "home.toggle", station = "zz_no_station", on = true }, "no_station")
  expect_err(s, { kind = "craft.cancel", job = "zz_no_job" }, "no_job")
  -- enums with enum_err
  expect_err(s, { kind = "home.set_activity", char = c, value = "dance" }, "bad_activity")
  expect_err(s, { kind = "home.set_level", station = "f_hearth", level = "max" }, "bad_level")
  -- enum without enum_err, boolean, int, string, table
  expect_err(s, { kind = "night.set_role", char = c, role = "dance" }, "bad_arg")
  expect_err(s, { kind = "home.toggle", station = "f_hearth", on = "yes" }, "bad_arg")
  expect_err(s, { kind = "home.set_door", x = 1.5, y = 1, open = true }, "bad_arg")
  expect_err(s, { kind = "home.set_door", x = 0 / 0, y = 1, open = true }, "bad_arg")
  expect_err(s, { kind = "story.choose", instance = 5, option = 1 }, "bad_arg")
  expect_err(s, { kind = "story.choose", instance = "i1", option = 1.5 }, "bad_arg")
  expect_err(s, { kind = "raid.commit", result = "won" }, "bad_arg")
  -- loc / npc / item_counts / char_list
  expect_err(s, { kind = "travel.go", loc = "Bad Loc", squad = { c } }, "bad_loc")
  expect_err(s, { kind = "travel.go", loc = 42, squad = { c } }, "bad_loc")
  expect_err(s, { kind = "trade.accept", trader = "Bad Npc!" }, "bad_npc")
  expect_err(s, { kind = "trade.offer", trader = "npc.a", give = { [FIRST_ITEM] = 0 }, want = {} }, "bad_items")
  expect_err(s, { kind = "trade.offer", trader = "npc.a", give = { [FIRST_ITEM] = 1.5 }, want = {} }, "bad_items")
  expect_err(s, { kind = "trade.offer", trader = "npc.a", give = "x", want = {} }, "bad_items")
  expect_err(s, { kind = "travel.go", loc = "suburb_house", squad = {} }, "bad_squad")
  expect_err(s, { kind = "travel.go", loc = "suburb_house", squad = "x" }, "bad_squad")
  expect_err(s, { kind = "travel.go", loc = "suburb_house", squad = { c, c } }, "bad_squad")
  expect_err(s, { kind = "travel.go", loc = "suburb_house", squad = { "nobody" } }, "no_char")
  -- number + char_list max, at night
  to_phase(s, "night")
  expect_err(s, { kind = "raid.autoresolve", squad = { c, c2(s), s.party.order[3] } }, "bad_squad", "max 2")
  expect_err(s, { kind = "raid.autoresolve", squad = { c }, hours = "x" }, "bad_arg")
  expect_err(s, { kind = "raid.autoresolve", squad = { c }, hours = 30 }, "bad_hours", "range stays in handler")
end

function T.args_validated_in_spec_order()
  local s = new_state()
  -- both char and item bad: the first arg in the spec decides
  expect_err(s, { kind = "needs.eat", char = "nobody", item = "zz_no_item" }, "no_char")
  expect_err(s, { kind = "needs.treat", patient = "nobody", actor = "nobody2" }, "no_char")
  expect_err(s, { kind = "craft.start", char = c1(s), recipe = "zz", room = "zz_room" }, "unknown_recipe")
end

-- ---------------------------------------------------------------- reserved commands

local function reserved_cmds(s)
  local c = c1(s)
  return {
    { kind = "trade.offer", trader = "npc.a", give = { [FIRST_ITEM] = 1 }, want = {} },
    { kind = "trade.accept", trader = "npc.a" },
    { kind = "trade.leave", trader = "npc_b" },
    { kind = "travel.go", loc = "suburb_house", squad = { c } },
    { kind = "raid.begin", loc = "suburb_house", squad = { c } },
    { kind = "raid.commit", result = {} },
    { kind = "story.choose", instance = "i1", option = 1 },
    { kind = "night.set_role", char = c, role = "guard" },
    { kind = "night.set_target" },
    { kind = "night.set_loadout", char = c, items = { [FIRST_ITEM] = 2 } },
  }
end

function T.reserved_not_implemented_and_pure()
  for _, s in ipairs({ new_state(), to_phase(new_state(), "night") }) do
    local cmds = reserved_cmds(s)
    assert(#cmds == #RESERVED)
    for _, cmd in ipairs(cmds) do
      local before = state_mod.checksum(s)
      local ok, err = run(s, cmd)
      assert(ok == false and err == "not_implemented", cmd.kind .. ": " .. tostring(err))
      assert(state_mod.checksum(s) == before, cmd.kind .. " changed state (log included)")
    end
  end
end

-- ---------------------------------------------------------------- fuzz: validate before mutate

local BAD = {
  char = { 42, "nobody", {}, true },
  char_list = { "x", {}, { "nobody" }, 42 },
  item = { 42, "zz_no_item", {} },
  recipe = { 42, "zz_no_recipe" },
  tech = { 42, "zz_no_tech" },
  room = { 42, "zz_no_room" },
  station = { 42, "zz_no_station" },
  job = { 42, "zz_no_job" },
  loc = { 42, "Bad Loc", "" },
  npc = { 42, "Bad Npc!", "" },
  item_counts = { "x", 42 },
  number = { "x", 0 / 0, math.huge, -math.huge },
  int = { "x", 1.5, 0 / 0, math.huge },
  boolean = { "yes", 1 },
  string = { 42, {}, true },
  table = { "x", 42, true },
}
local ENUM_BAD = { "zz_bad", 42, true }

local function base_type(t)
  if type(t) == "table" then return "enum" end
  return (t:gsub("%?$", ""))
end

local function good_value(s, t)
  if type(t) == "table" then return t[1] end
  local bt = base_type(t)
  local any_room = sorted_keys(s.home.rooms)[1]
  local any_station = sorted_keys(s.home.stations)[1]
  local any_job = sorted_keys(s.jobs or {})[1]
  local v = ({
    char = c1(s), char_list = { c1(s) }, item = FIRST_ITEM, recipe = FIRST_RECIPE, tech = FIRST_TECH,
    room = any_room, station = any_station, job = any_job, loc = "suburb_house", npc = "npc.a",
    item_counts = { [FIRST_ITEM] = 1 }, number = 1, int = 1, boolean = false, string = "x", table = {},
  })[bt]
  return v
end

local function fuzz_state(s, label)
  local list = commands.list()
  local tried = 0
  for _, kind in ipairs(list) do
    local sp = commands.spec(kind)
    -- put the state into an allowed phase so the argument checks are actually reached
    local target = s
    if sp.phase then
      local allowed = false
      for _, p in ipairs(sp.phase) do allowed = allowed or p == s.clock.phase end
      if not allowed then target = nil end
    end
    if target then
      for i, a in ipairs(sp.args) do
        local bads = type(a[2]) == "table" and ENUM_BAD or BAD[base_type(a[2])]
        assert(bads, kind .. ": no fuzz values for type " .. tostring(a[2]))
        for _, bad in ipairs(bads) do
          local cmd = { kind = kind }
          for j, b in ipairs(sp.args) do
            if j ~= i then cmd[b[1]] = good_value(target, b[2]) end
          end
          cmd[a[1]] = bad
          local before = model_bytes(target)
          local ok, err = run(target, cmd)
          assert(ok == false, label .. " " .. kind .. "." .. a[1] .. "=" .. tostring(bad) .. " accepted")
          assert(type(err) == "string" and err:match("^[a-z_]+$"), kind .. " err " .. tostring(err))
          assert(model_bytes(target) == before,
            label .. " " .. kind .. "." .. a[1] .. "=" .. tostring(bad) .. " (" .. err .. ") mutated the model")
          tried = tried + 1
        end
        coroutine.yield()
      end
    end
  end
  return tried
end

function T.fuzz_fresh_day1()
  local n = fuzz_state(new_state(), "day1")
  assert(n > 100, "fuzz too small: " .. n)
end

function T.fuzz_after_one_day()
  local s = new_state()
  sim.step(s, 24 * 60)
  coroutine.yield()
  local n = fuzz_state(s, "day2")
  assert(n > 100, "fuzz too small: " .. n)
end

function T.fuzz_dusk_and_night()
  local s = new_state()
  assert(run(s, { kind = "home.end_day" }))
  fuzz_state(s, "dusk")
  to_phase(s, "night")
  fuzz_state(s, "night")
end

return T
