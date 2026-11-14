-- 验收测试，编码代理不得修改（主代理编写；认为有误时停下报告）。docs/M5-3D-PLAN.md §3、§7。
-- 引擎模型接口（iso.model_* / map_set_draw_tiles / entity_set_ghost）的 Lua 契约。
local probe = require("kit_probe")

probe.timeout(60)

local now = 0
local function wait(sec)
  local untl = now + sec
  while now < untl do coroutine.yield() end
end

local PATH = "assets/models/ranch_a.wsm"

local function has(list, x)
  for _, v in ipairs(list or {}) do if v == x then return true end end
  return false
end

local function scenario()
  wait(0.3)

  local id = iso.model_load(PATH)
  probe.check("model_load returns a positive id", type(id) == "number" and id >= 1)

  local info = iso.model_info(id)
  probe.check("model_info has nodes / tris / visible_tris",
    type(info) == "table" and type(info.nodes) == "number" and type(info.tris) == "number"
    and type(info.visible_tris) == "number")
  probe.check("fresh model: all tris visible, within budget",
    info and info.tris > 1000 and info.tris <= 30000 and info.visible_tris == info.tris)

  local names = iso.model_nodes(id)
  probe.check("model_nodes lists every node", type(names) == "table" and info and #names == info.nodes)
  probe.check("node names include floors, walls and stairs",
    has(names, "F1_floor") and has(names, "B1_wall_low") and has(names, "F2_wall_high")
    and has(names, "stair_B1_1F") and has(names, "F1_woodstove_on"))

  probe.check("model_node_visible: existing node visible", iso.model_node_visible(id, "F1_floor") == true)
  probe.check("model_node_visible: unknown node is nil", iso.model_node_visible(id, "no_such_node") == nil)

  local n = iso.model_set_visible(id, "F2_*", false)
  probe.check("prefix pattern hides several nodes (" .. tostring(n) .. ")", type(n) == "number" and n >= 5)
  local info2 = iso.model_info(id)
  probe.check("visible_tris drops after hiding F2", info2.visible_tris < info.tris)
  probe.check("hidden node reports false", iso.model_node_visible(id, "F2_floor") == false)
  probe.check("other floors untouched", iso.model_node_visible(id, "F1_floor") == true)

  probe.check("exact name matches one node", iso.model_set_visible(id, "F1_wall_high", false) == 1)
  probe.check("no match returns 0", iso.model_set_visible(id, "Z9_*", false) == 0)
  probe.check("name without * must match exactly", iso.model_set_visible(id, "F1_wall", false) == 0)

  iso.model_set_visible(id, "*", true)
  probe.check("'*' shows everything again", iso.model_info(id).visible_tris == info.tris)

  iso.model_set_offset(id, 0, 3, 0)
  probe.check("set_offset keeps the model alive", iso.model_info(id) ~= nil)

  -- a second instance is independent
  local id2 = iso.model_load(PATH)
  probe.check("second load gives a different id", type(id2) == "number" and id2 ~= id)
  iso.model_set_visible(id2, "*", false)
  probe.check("instances are independent", iso.model_info(id).visible_tris == info.tris
    and iso.model_info(id2).visible_tris == 0)

  -- bad input
  local bad = iso.model_load("assets/models/does_not_exist.wsm")
  probe.check("missing file returns nil", bad == nil)
  local bad2 = iso.model_load("assets/main.lua")
  probe.check("non-wsm file returns nil", bad2 == nil)

  -- tiles can be hidden without breaking map logic
  iso.map_set_draw_tiles(false)
  probe.check("map logic still works with tiles hidden", iso.map_walkable ~= nil)
  iso.map_set_draw_tiles(true)

  -- ghost entities
  local e = iso.entity_spawn and iso.entity_spawn(0, 2.5, 2.5, 1.0, 1.5) or nil
  if e then
    probe.check("entity starts as non-ghost", iso.entity_get_ghost(e) == false)
    iso.entity_set_ghost(e, true)
    probe.check("entity_set_ghost(true) sticks", iso.entity_get_ghost(e) == true)
    iso.entity_set_ghost(e, false)
    probe.check("entity_set_ghost(false) clears", iso.entity_get_ghost(e) == false)
  else
    probe.check("iso.entity_spawn available for the ghost check", false)
  end

  -- frames keep rendering with models loaded
  wait(0.5)

  iso.model_unload(id2)
  probe.check("unloaded model has no info", iso.model_info(id2) == nil)
  probe.check("unloaded model: set_visible returns 0", iso.model_set_visible(id2, "*", true) == 0)
  iso.model_unload(id)
  iso.model_unload(id) -- double unload is harmless
  wait(0.2)

  probe.check("script healthy", probe.script_ok())
  probe.finish()
end

local co = coroutine.create(scenario)

function _probe(t, dt)
  now = t
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then error(err, 0) end
end
