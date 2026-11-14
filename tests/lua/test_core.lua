package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local rng = require("core.rng")
local serialize = require("core.serialize")
local save = require("core.save")
local i18n = require("core.i18n")
local bus = require("core.bus")
local scene = require("core.scene")
local input = require("core.input")

local T = {}

function T.rng_deterministic()
  local r1 = rng.new(12345)
  local r2 = rng.new(12345)
  for _ = 1, 20 do
    assert(rng.next_u32(r1) == rng.next_u32(r2))
    local v = rng.int(r1, 1, 6)
    local v2 = rng.int(r2, 1, 6)
    assert(v == v2 and v >= 1 and v <= 6)
  end
end

function T.serialize_deterministic_roundtrip()
  local a = { z = 1, a = { true, "hi\n\"x\"", 3.5 }, m = -42 }
  local s1 = serialize.encode(a)
  local s2 = serialize.encode({ m = -42, a = { true, "hi\n\"x\"", 3.5 }, z = 1 })
  assert(s1 == s2, "key order must be deterministic")
  local ok, b = serialize.decode(s1)
  assert(ok and b.z == 1 and b.m == -42 and b.a[1] == true and b.a[2] == 'hi\n"x"')
end

function T.sys_save_roundtrip_and_invalid_names()
  assert(sys.save_write("../evil", "nope") == false)
  assert(sys.save_write("BAD_NAME", "nope") == false)
  assert(sys.save_write("a.sav", "nope") == false)
  assert(sys.save_write("", "nope") == false)

  local ok = save.write("luatest_tmp", { hello = "world", n = 7 })
  assert(ok == true)
  assert(save.exists("luatest_tmp") == true)
  local ok_r, data = save.read("luatest_tmp")
  assert(ok_r and data.hello == "world" and data.n == 7)

  local list = save.list()
  local found = false
  for _, name in ipairs(list) do
    if name == "luatest_tmp" then found = true end
  end
  assert(found)
  assert(save.delete("luatest_tmp") == true)
  assert(save.exists("luatest_tmp") == false)
end

function T.i18n_substitution_and_plural()
  i18n.tables = {
    zh = { greet = "你好 {name}", items = "{n} 件" },
    en = { greet = "Hello {name}", items = "{n} {n|item|items}" },
  }
  i18n.lang = "en"
  assert(i18n.t("items", { n = 1 }) == "1 item")
  assert(i18n.t("items", { n = 3 }) == "3 items")
  assert(i18n.t("greet", { name = "Lin" }) == "Hello Lin")
  i18n.lang = "zh"
  assert(i18n.t("greet", { name = "林" }) == "你好 林")
end

function T.bus_emit_and_unsub()
  bus.clear()
  local count = 0
  local unsub
  unsub = bus.on("ping", function(d)
    count = count + d
    unsub()
  end)
  bus.emit("ping", 2)
  bus.emit("ping", 5)
  assert(count == 2)
end

function T.scene_stack_and_modal()
  scene.clear()
  local log = {}
  local s1 = {
    on_enter = function() log[#log + 1] = "s1_enter" end,
    on_pause = function() log[#log + 1] = "s1_pause" end,
    on_resume = function() log[#log + 1] = "s1_resume" end,
    on_exit = function() log[#log + 1] = "s1_exit" end,
    update = function() log[#log + 1] = "s1_upd" end,
  }
  local m1 = {
    on_enter = function() log[#log + 1] = "m1_enter" end,
    on_exit = function() log[#log + 1] = "m1_exit" end,
    update = function() log[#log + 1] = "m1_upd" end,
  }
  scene.push(s1)
  scene.update(0.016)
  scene.push_modal(m1)
  assert(scene.has_modal())
  scene.update(0.016)
  scene.pop_modal()
  assert(not scene.has_modal())
  scene.update(0.016)
  scene.pop()
  assert(table.concat(log, ",") == "s1_enter,s1_upd,m1_enter,m1_upd,m1_exit,s1_upd,s1_exit")
end

function T.serialize_shortest_float()
  assert(serialize.encode(0.7) == "return " .. "0.7" .. "\n")
  assert(serialize.encode(0.1 + 0.2) == "return " .. "0.30000000000000004" .. "\n")
  assert(serialize.encode(3.5) == "return " .. "3.5" .. "\n")
  assert(serialize.encode(1 / 0) == "return " .. "math.huge" .. "\n")
  assert(serialize.encode(-1 / 0) == "return " .. "-math.huge" .. "\n")
  assert(serialize.encode(0 / 0) == "return " .. "0/0" .. "\n")
  for _, v in ipairs({ 0.7, 0.1 + 0.2, 1 / 3, 1e-300, 123456.789, 2 ^ 0.5 }) do
    local s = serialize.encode(v)
    assert(s == serialize.encode(v))
    local ok, back = serialize.decode(s)
    assert(ok and back == v, s)
  end
  for _, v in ipairs({ -0.0, 0.0, 3.0, -2.0, 1e16, 2 ^ 53, 0.7, -0.7, 1e-300, 1.7976931348623157e308 }) do
    local s = serialize.encode(v)
    local ok, back = serialize.decode(s)
    assert(ok and math.type(back) == "float" and back == v, s)
    if v == 0 then
      assert((1 / back < 0) == (1 / v < 0), s)
    end
  end
  for _, v in ipairs({ 0, 3, -7, math.maxinteger, math.mininteger }) do
    local ok, back = serialize.decode(serialize.encode(v))
    assert(ok and math.type(back) == "integer" and back == v)
  end
end

function T.input_rebind_conflict_and_validate()
  input.init()
  assert(input.validate())
  -- W/H conflict vs R: 'interact' (W) default F, 'attack' (C) default G
  local c = input.find_conflict("keyboard", "attack", { key = keys.F })
  assert(c ~= nil and c.action_id == "interact")
  -- Reserved key Esc rejected
  local ok_esc, err_esc = input.set_binding("keyboard", "attack", 1, { key = keys.ESCAPE })
  assert(not ok_esc and err_esc == "reserved")
  -- Valid rebind
  assert(input.set_binding("keyboard", "attack", 1, { key = keys.K }))
  assert(input.get_binding("keyboard", "attack", 1).key == keys.K)
  input.reset_all()
end

return T
