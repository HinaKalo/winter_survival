-- 验收测试（主代理编写，编码代理不得修改；认为有误时停下报告）。
-- P0-PLAN §3.4 / §4 P0-4：契约骨架 C1、C3、C4、C6、C7、C8、C9（字段名以 PARALLEL-PLAN §2 与 P0-PLAN §9.5 为准）。
--
-- 本文件冻结的接口（§3.4 未写明的部分以此为准）：
--   deeds.record(state, t) -> id | nil, err     坏输入返回 nil, err 且不改状态
--   raid.commit(state, raid, result)            result 不合法 -> false, "bad_result"；合法 -> false, "not_implemented"
--   raid.validate_result(result) -> ok, err
--   locations.validate(loc) -> ok, err；locations.get(state, id)；locations.list(state)
--   story.SLOTS（有序，11 个）；story.pick(slot, ctx)；story.choose(state, inst, idx)
package.path = "assets/scripts/?.lua;assets/?.lua;tests/?.lua;" .. package.path

local sim = require("sim.sim")
local state_mod = require("sim.state")
local bus = require("core.bus")

local T = {}

local function new_state() return assert(sim.new(1)) end

local function day3()
  local s = new_state()
  for _ = 1, 3 do
    sim.step(s, 24 * 60)
    coroutine.yield()
  end
  return s
end

local function deep_copy(v, seen)
  if type(v) ~= "table" then return v end
  seen = seen or {}
  if seen[v] then return seen[v] end
  local o = {}
  seen[v] = o
  for k, x in pairs(v) do o[deep_copy(k, seen)] = deep_copy(x, seen) end
  return setmetatable(o, getmetatable(v))
end

-- ---------------------------------------------------------------- C1

function T.c1_version_and_new_subtrees()
  assert(state_mod.VERSION == 2, "VERSION")
  local s = new_state()
  assert(s.version == 2)
  local w = s.world
  assert(type(w) == "table" and type(w.locations) == "table" and type(w.npcs) == "table"
    and type(w.factions) == "table" and w.notoriety == 0 and type(w.traders) == "table", "world subtree")
  assert(type(s.outpost) == "table" and type(s.endings) == "table")
  assert(s.raid == nil)
  assert(state_mod.validate(s))
end

function T.c1_migration_v1_to_v2()
  assert(type(state_mod.MIGRATIONS) == "table" and type(state_mod.MIGRATIONS[1]) == "function")
  local s = new_state()
  s.world, s.outpost, s.endings = nil, nil, nil
  s.version = 1
  local text = state_mod.encode(s)
  local d, err = state_mod.decode(text)
  assert(d, "v1 save must migrate: " .. tostring(err))
  assert(d.version == 2 and type(d.world) == "table" and type(d.world.locations) == "table")
  assert(type(d.outpost) == "table" and type(d.endings) == "table")
  assert(state_mod.validate(d))
  -- unknown future version is rejected
  s.version = 99
  assert(state_mod.decode(state_mod.encode(s)) == nil, "future version rejected")
end

function T.c1_raid_never_saved()
  local s = new_state()
  s.raid = { loc = "suburb_house" }
  local ok, err = state_mod.validate(s)
  assert(not ok and tostring(err):find("raid state must not be saved", 1, true), tostring(err))
end

function T.c1_schema_files()
  local order = { "clock", "party", "home", "weather", "tech", "jobs", "night", "story", "world", "outpost",
    "endings", "stats" }
  local s = new_state()
  for _, name in ipairs(order) do
    local fn = require("sim.schema." .. name)
    assert(type(fn) == "function", "sim/schema/" .. name .. ".lua must return a function")
    local ok, err = fn(s[name], s)
    assert(ok, name .. ": " .. tostring(err))
  end
  -- new subtrees: type checks
  local bad = new_state()
  bad.world = "x"
  assert(not state_mod.validate(bad), "world must be a table")
  bad = new_state()
  bad.world.locations = 5
  assert(not state_mod.validate(bad), "world.locations must be a table")
  bad = new_state()
  bad.outpost = 1
  assert(not state_mod.validate(bad))
end

-- ---------------------------------------------------------------- C3

local EVENTS = {
  phase_changed = { "from", "to", "day" },
  day_started = { "day" },
  char_died = { "id", "cause", "day" },
  char_wounded = { "id", "amount", "cause" },
  char_left_party = { "id", "reason" },
  char_joined_party = { "id" },
  station_changed = { "id", "on", "hp" },
  room_temp_alert = { "room", "temp", "level" },
  snap_warning = { "start_day", "severity" },
  storylet_ready = { "slot", "id" },
  raid_ended = { "loc", "exit" },
}

function T.c3_catalog()
  local cat = require("sim.events")
  for name, fields in pairs(EVENTS) do
    local f = cat[name]
    assert(type(f) == "table", "missing event " .. name)
    assert(#f == #fields, name .. " field count")
    for i, x in ipairs(fields) do assert(f[i] == x, name .. " field " .. i) end
  end
  for name in pairs(cat) do
    assert(type(name) == "string" and name:match("^[a-z]+_?[a-z_]*$") and not name:find("__")
      and not name:find("_$") and not name:find("%."), "bad event name " .. tostring(name))
  end
end

function T.c3_emit_checks()
  local emit = require("sim.emit")
  local fn = type(emit) == "function" and emit or emit.emit
  assert(type(fn) == "function", "sim.emit exports emit(name, data)")
  assert(not pcall(fn, "no_such_event", {}), "unknown event must error")
  assert(not pcall(fn, "day_started", {}), "missing field must error")
  assert(not pcall(fn, "char.died", { id = "a", cause = "x", day = 1 }), "prefixed names are not events")
  local got
  local h = function(d) got = d end
  bus.on("day_started", h)
  fn("day_started", { day = 7 })
  bus.off("day_started", h)
  assert(got and got.day == 7, "emit forwards to core.bus")
end

function T.c3_wiring_and_purity()
  local seen = {}
  local hs = {}
  for _, name in ipairs({ "phase_changed", "day_started", "char_died", "char_wounded" }) do
    hs[name] = function(d) seen[name] = (seen[name] or 0) + 1; seen[name .. "_data"] = d end
    bus.on(name, hs[name])
  end
  local ok, err = pcall(function()
    local s = new_state()
    local quiet = new_state()
    sim.step(s, 24 * 60 + 60)
    assert(seen.phase_changed and seen.day_started, "phase_changed / day_started wired")
    local pd = seen.phase_changed_data
    assert(pd.from and pd.to and pd.day, "phase_changed payload")
    local cid = s.party.order[1]
    require("sim.health").add_wound(s, s.party.chars[cid], 5, "test")
    assert(seen.char_wounded and seen.char_wounded_data.id == cid, "char_wounded wired")
    require("sim.chars").kill(s, s.party.order[2], "test")
    assert(seen.char_died and seen.char_died_data.id == s.party.order[2], "char_died wired")
    -- emitting never writes state: same run with no subscribers gives the same checksum
    for name, h in pairs(hs) do bus.off(name, h) end
    sim.step(quiet, 24 * 60 + 60)
    local a = new_state()
    for name, h in pairs(hs) do bus.on(name, h) end
    sim.step(a, 24 * 60 + 60)
    assert(state_mod.checksum(a) == state_mod.checksum(quiet), "events do not change state")
  end)
  for name, h in pairs(hs) do bus.off(name, h) end
  assert(ok, tostring(err))
end

-- ---------------------------------------------------------------- C4

local function strings_are_keys(v, path, seen)
  seen = seen or {}
  if type(v) == "string" then
    assert(v:match("^[%w_%.:%-]*$"), path .. ": not an id/enum/i18n key: " .. v)
  elseif type(v) == "table" then
    assert(not seen[v], path .. ": cycle")
    seen[v] = true
    for k, x in pairs(v) do strings_are_keys(x, path .. "." .. tostring(k), seen) end
  else
    local t = type(v)
    assert(t == "number" or t == "boolean" or t == "nil", path .. ": bad type " .. t)
  end
end

local function has(t, fields, label)
  assert(type(t) == "table", label .. " not a table")
  for _, f in ipairs(fields) do assert(t[f] ~= nil, label .. " missing " .. f) end
end

local function check_queries(s, label)
  local q = {
    party = require("sim.query.party"), home = require("sim.query.home"), inv = require("sim.query.inv"),
    craft = require("sim.query.craft"), tech = require("sim.query.tech"), clock = require("sim.query.clock"),
    night = require("sim.query.night"),
  }
  local before = state_mod.checksum(s)
  local cid = s.party.order[1]
  local out = {}

  local cards = q.party.cards(s)
  assert(#cards == #s.party.order, label .. " cards")
  for i, c in ipairs(cards) do
    assert(c.id == s.party.order[i], "cards in party order")
    has(c, { "id", "name_key", "hp_band", "needs", "activity", "flags" }, label .. " card")
    assert(({ ok = 1, light = 1, heavy = 1, critical = 1 })[c.hp_band], "hp_band " .. tostring(c.hp_band))
    has(c.needs, { "food", "water", "energy", "temp", "mood" }, "card.needs")
    for _, k in ipairs({ "food", "water", "energy", "temp", "mood" }) do
      assert(c.needs[k] == math.floor(c.needs[k]), "needs are integers")
    end
  end
  out.cards = cards

  local d = q.party.detail(s, cid)
  has(d, { "id", "name_key", "role", "traits", "needs", "health", "wear", "relations", "psyche" }, "detail")
  has(d.health, { "hp_band", "diseases" }, "detail.health")
  local nd, nerr = q.party.detail(s, "nobody")
  assert(nd == nil and nerr == "no_char")
  out.detail = d

  local rooms = q.home.rooms(s)
  assert(#rooms > 0)
  for i, r in ipairs(rooms) do
    has(r, { "id", "name_key", "temp", "occupants" }, "room")
    if i > 1 then assert(rooms[i - 1].id < r.id, "rooms sorted by id") end
    assert(math.abs(r.temp * 10 - math.floor(r.temp * 10 + 0.5)) < 1e-6, "temp one decimal")
  end
  out.rooms = rooms

  local st = q.home.stations(s)
  assert(#st > 0)
  for i, x in ipairs(st) do
    has(x, { "id", "kind", "name_key", "room", "hp", "on", "usable" }, "station")
    assert(x.name_key == "station." .. x.kind .. ".name")
    if i > 1 then assert(st[i - 1].id < x.id, "stations sorted") end
  end
  out.stations = st

  for _, ref in ipairs({ "stash", "char:" .. cid }) do
    local g = q.inv.grid(s, ref)
    has(g, { "ref", "slots", "slots_used", "kg", "kg_cap", "entries" }, "grid " .. ref)
    assert(g.ref == ref)
    for i, e in ipairs(g.entries) do
      has(e, { "item", "name_key", "count", "kg", "cat" }, "entry")
      if i > 1 then
        local p = g.entries[i - 1]
        assert(p.cat < e.cat or (p.cat == e.cat and p.item < e.item), "entries sorted by (cat, item)")
      end
    end
    out["grid_" .. ref] = g
  end
  local bg, berr = q.inv.grid(s, "char:nobody")
  assert(bg == nil and type(berr) == "string")

  local cl = q.craft.list(s, nil)
  assert(type(cl) == "table")
  for _, r in ipairs(cl) do
    has(r, { "recipe", "name_key", "minutes", "can", "inputs", "outputs" }, "craft row")
    assert(type(r.can) == "boolean")
    if not r.can then assert(type(r.reason) == "string", "reason when not craftable") end
  end
  out.craft = cl

  local tt = q.tech.tree(s)
  assert(#tt > 0)
  for _, t in ipairs(tt) do
    has(t, { "id", "name_key", "prereqs", "status" }, "tech row")
    assert(({ unlocked = 1, available = 1, locked = 1, researching = 1 })[t.status], t.status)
  end
  out.tech = tt

  local h = q.clock.hud(s)
  has(h, { "day", "days_total", "minute", "hh", "mm", "phase", "outdoor_temp" }, "hud")
  assert(h.hh == math.floor(s.clock.minute / 60) and h.mm == s.clock.minute % 60)
  out.hud = h

  local np = q.night.plan(s)
  has(np, { "roles", "loadout", "editable" }, "night.plan")
  out.night = np

  strings_are_keys(out, label)
  assert(state_mod.checksum(s) == before, label .. ": queries must not change state")
end

function T.c4_queries_fresh()
  check_queries(new_state(), "day1")
end

function T.c4_queries_day3()
  check_queries(day3(), "day3")
end

-- ---------------------------------------------------------------- C6

local function good_deed(s)
  return {
    verb = "steal", actor = s.party.order[1], squad = { s.party.order[1], s.party.order[2] },
    target = "npc.old_man", target_kind = "civilian", loc = "suburb_house",
    tags = { occupied = true }, witnesses = { "npc.girl" }, magnitude = 0.5,
  }
end

function T.c6_verbs()
  local kinds = require("data.deed_kinds")
  local set = {}
  for k, v in pairs(kinds) do
    if type(k) == "string" then set[k] = true elseif type(v) == "string" then set[v] = true end
  end
  for _, v in ipairs({ "steal", "rob", "assault", "knockout", "kill", "spare", "help", "give", "trade_fair",
    "trade_cheat", "refuse_help", "abandon", "betray", "rescue", "bury", "confess", "return_goods", "inform",
    "die" }) do
    assert(set[v], "verb " .. v)
  end
  assert(not set.break_in and not set.intimidate, "break_in / intimidate are tags, not verbs")
end

function T.c6_record_and_query()
  local deeds = require("sim.deeds")
  local s = new_state()
  local id1 = deeds.record(s, good_deed(s))
  local id2 = deeds.record(s, good_deed(s))
  assert(type(id1) == "number" and id2 == id1 + 1, "ids increase")
  local d = s.story.deeds[#s.story.deeds]
  assert(d.id == id2 and d.day == s.clock.day and d.phase == "day", "record fills id/day/phase")
  local die = { verb = "die", actor = nil, squad = {}, target = s.party.order[3], target_kind = "teammate",
    loc = "home", tags = {}, witnesses = {}, magnitude = 1 }
  assert(deeds.record(s, die), "die has no actor")
  assert(#deeds.query(s, { verb = "steal" }) == 2)
  assert(#deeds.query(s, { actor = s.party.order[1] }) == 2)
  assert(#deeds.query(s, { loc = "suburb_house", verb = "steal" }) == 2)
  assert(#deeds.query(s, { day = 99 }) == 0)
  local all = deeds.query(s, {})
  for i = 2, #all do assert(all[i - 1].id < all[i].id, "query sorted by id") end
end

function T.c6_bad_fields_rejected()
  local deeds = require("sim.deeds")
  local s = new_state()
  local mutations = {
    function(t) t.verb = "break_in" end,
    function(t) t.verb = nil end,
    function(t) t.kind = "steal"; t.verb = nil end,
    function(t) t.target_kind = "alien" end,
    function(t) t.magnitude = 2 end,
    function(t) t.magnitude = -0.1 end,
    function(t) t.squad = "x" end,
    function(t) t.witnesses = "npc.a" end,
    function(t) t.tags = "occupied" end,
    function(t) t.target = { type = "npc", id = "a" } end,
    function(t) t.severity = 1 end,
    function(t) t.actor = 42 end,
  }
  for i, m in ipairs(mutations) do
    local t = good_deed(s)
    m(t)
    local before = state_mod.checksum(s)
    local id, err = deeds.record(s, t)
    assert(id == nil and type(err) == "string", "mutation " .. i .. " accepted")
    assert(state_mod.checksum(s) == before, "mutation " .. i .. " changed state")
  end
end

-- ---------------------------------------------------------------- C7

local function good_result()
  return { loot = {}, wounds = {}, deaths = {}, deeds = {}, minutes_used = 120, exit = "evac" }
end

function T.c7_validate_result()
  local raid = require("sim.raid")
  assert(raid.validate_result(good_result()))
  for _, ex in ipairs({ "evac", "timeout", "wiped" }) do
    local r = good_result(); r.exit = ex
    assert(raid.validate_result(r), ex)
  end
  local bads = {
    function(r) r.loot = nil end, function(r) r.wounds = "x" end, function(r) r.deaths = nil end,
    function(r) r.deeds = 1 end, function(r) r.minutes_used = -1 end, function(r) r.minutes_used = "x" end,
    function(r) r.minutes_used = 0 / 0 end, function(r) r.exit = "fled" end, function(r) r.exit = nil end,
  }
  for i, b in ipairs(bads) do
    local r = good_result(); b(r)
    local ok, err = raid.validate_result(r)
    assert(not ok and type(err) == "string", "bad result " .. i .. " accepted")
  end
  assert(not raid.validate_result("x"))
end

function T.c7_begin_commit_stubs()
  local raid = require("sim.raid")
  local s = new_state()
  local before = state_mod.checksum(s)
  local r, err = raid.begin(s, "suburb_house", { s.party.order[1] })
  assert(r == nil and err == "not_implemented")
  local ok, err2 = raid.commit(s, {}, good_result())
  assert(ok == false and err2 == "not_implemented")
  local bad = good_result(); bad.exit = "fled"
  ok, err2 = raid.commit(s, {}, bad)
  assert(ok == false and err2 == "bad_result")
  assert(state_mod.checksum(s) == before, "stubs do not change state")
end

function T.c7_autoresolve_replaces_expedition()
  assert(package.searchpath("sim.expedition", package.path) == nil, "sim/expedition.lua must be deleted")
  local raid = require("sim.raid")
  local s = new_state()
  while s.clock.phase ~= "night" do sim.step(s, 10) end
  local res = raid.autoresolve(s, "suburb_house", { s.party.order[1] }, { hours = 2 })
  assert(type(res) == "table" and res.applied == true and res.placeholder == true)
  assert(raid.validate_result(res), "autoresolve returns a C7 result")
  -- the registered command still works through the registry
  local s2 = new_state()
  while s2.clock.phase ~= "night" do sim.step(s2, 10) end
  local ok, err = require("sim.commands").run(s2, { kind = "raid.autoresolve", squad = { s2.party.order[1] } })
  assert(ok, tostring(err))
end

-- ---------------------------------------------------------------- C8

local function fixture_loc()
  local f = assert(loadfile("tests/fixtures/locations/suburb_house_a.lua", "t", {}))
  return f()
end

function T.c8_fixture_and_validate()
  local locations = require("sim.locations")
  local loc = fixture_loc()
  local ok, err = locations.validate(loc)
  assert(ok, tostring(err))
  assert(loc.id == "suburb_house" and loc.archetype == "suburb_house" and loc.variant == "A")
  assert(loc.layout == nil, "no numeric layout field")
  local bads = {
    function(l) l.id = nil end, function(l) l.occ = "official" end, function(l) l.occ = "raiders" end,
    function(l) l.state = "hostile" end, function(l) l.state = "empty" end, function(l) l.alert = "yes" end,
    function(l) l.variant = 1 end, function(l) l.variant = "C" end, function(l) l.travel_min = -5 end,
    function(l) l.raid_difficulty = 0 end, function(l) l.raid_difficulty = 6 end, function(l) l.guard = 4 end,
    function(l) l.attitude = -4 end, function(l) l.containers = "x" end, function(l) l.unlocked = nil end,
    function(l) l.distance_min = 30; l.travel_min = nil end, function(l) l.danger = 2; l.raid_difficulty = nil end,
  }
  for i, b in ipairs(bads) do
    local l = deep_copy(loc); b(l)
    local okb, errb = locations.validate(l)
    assert(not okb and type(errb) == "string", "bad location " .. i .. " accepted")
  end
  local l = deep_copy(loc); l.unlock_day = nil
  assert(locations.validate(l), "unlock_day may be nil (clue unlock)")
end

function T.c8_get_list()
  local locations = require("sim.locations")
  local s = new_state()
  local a = fixture_loc()
  local b = deep_copy(a); b.id = "corner_store"; b.archetype = "corner_store"
  s.world.locations[a.id] = a
  s.world.locations[b.id] = b
  assert(locations.get(s, "suburb_house") == a)
  assert(locations.get(s, "nowhere") == nil)
  local list = locations.list(s)
  assert(#list == 2 and list[1].id == "corner_store" and list[2].id == "suburb_house", "sorted by id")
end

-- ---------------------------------------------------------------- C9

function T.c9_slots_and_pick()
  local story = require("sim.story")
  local want = { "door_day", "radio", "dawn", "dusk", "home_idle", "raid_enter", "raid_found", "travel", "dream",
    "talk", "crisis" }
  assert(#story.SLOTS == #want, "11 slots")
  for i, n in ipairs(want) do assert(story.SLOTS[i] == n, "slot " .. i) end
  local s = new_state()
  for _, n in ipairs(want) do
    assert(story.pick(n, { state = s, loc = nil, chars = s.party.order }) == nil, n)
  end
  for _, old in ipairs({ "door", "day_start", "raid_container", "raid_npc", "raid_after", "trade_open", "zz" }) do
    assert(not pcall(story.pick, old, { state = s }), "unknown slot " .. old .. " must error")
  end
  local ok, err = story.choose(s, {}, 1)
  assert(ok == false and err == "not_implemented")
end

return T
