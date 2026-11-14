package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local lightfov = require("view.lightfov")
local mapbuild = require("view.mapbuild")
local lights = require("data.lights")
local suburb_house = require("data.locations.suburb_house")
local street_block = require("data.locations.street_block")

local T = {}

local function near(a, b) return math.abs(a - b) < 1e-9 end

-- Fake engine: every call is a no-op unless overridden; records light_* calls.
local function with_fake_iso(overrides, fn)
  local saved = _G.iso
  local noop = function() end
  local fake = setmetatable(overrides, { __index = function() return noop end })
  _G.iso = fake
  local ok, err = pcall(fn, fake)
  _G.iso = saved
  assert(ok, tostring(err))
end

local function light_recorder()
  local rec = { next_id = 0, lights = {}, ambient = nil }
  rec.api = {
    light_add = function(x, z, radius, r, g, b)
      rec.next_id = rec.next_id + 1
      rec.lights[rec.next_id] = { x = x, z = z, radius = radius, color = { r, g, b }, name = nil }
      return rec.next_id
    end,
    light_set_color = function(id, r, g, b) rec.lights[id].color = { r, g, b } end,
    light_set_radius = function(id, r) rec.lights[id].radius = r end,
    light_set_ambient = function(r, g, b) rec.ambient = { r, g, b } end,
    tile_define_ex2 = function() return 1 end,
    sheet_load = function() return 1 end,
    entity_spawn = function() return 1 end,
  }
  return rec
end

function T.ambient_at_table_rows_and_interpolation()
  local noon = lightfov.ambient_at(12, false)
  assert(near(noon[1], 0.89) and near(noon[2], 0.92) and near(noon[3], 0.95))
  local noon_in = lightfov.ambient_at(12, true)
  assert(near(noon_in[1], 138 / 255) and near(noon_in[2], 134 / 255))
  -- midpoint 6..9 is the average of the two rows
  local mid = lightfov.ambient_at(7.5, false)
  assert(near(mid[1], (0.47 + 0.77) / 2) and near(mid[2], (0.46 + 0.80) / 2) and near(mid[3], (0.50 + 0.85) / 2))
  -- wraps 21 -> 24 towards the 00:00 row; 24 == 0
  local late = lightfov.ambient_at(22.5, false)
  assert(near(late[1], (0.20 + 0.12) / 2) and near(late[3], (0.32 + 0.24) / 2))
  local m0 = lightfov.ambient_at(24, false)
  assert(near(m0[1], 0.12) and near(m0[3], 0.24))
  local neg = lightfov.ambient_at(-3, false) -- -3 % 24 == 21
  assert(near(neg[1], 0.20))
  -- night is never zero (ART-AUDIO §3.1)
  for h = 0, 23.5, 0.5 do
    local c = lightfov.ambient_at(h, false)
    assert(c[1] > 0 and c[2] > 0 and c[3] > 0)
  end
  -- returned table is a copy
  noon[1] = 0
  assert(near(lightfov.ambient_at(12, false)[1], 0.89))
end

function T.phase_of_boundaries()
  local cases = { { 0, "night" }, { 3, "night" }, { 4.99, "night" }, { 5, "dawn" }, { 5.99, "dawn" },
    { 6, "day" }, { 12, "day" }, { 18.99, "day" }, { 19, "dusk" }, { 20.99, "dusk" }, { 21, "night" },
    { 23.5, "night" }, { 24, "night" }, { 29, "dawn" } }
  for _, c in ipairs(cases) do
    assert(lightfov.phase_of(c[1]) == c[2], c[1] .. " -> " .. lightfov.phase_of(c[1]))
  end
end

function T.fov_recompute_throttled_to_10hz_with_fake_clock()
  local fov_calls = 0
  with_fake_iso({ fov_compute = function() fov_calls = fov_calls + 1 end }, function()
    lightfov.clear_lights()
    lightfov.init({ hour = 12 })
    lightfov.recompute_count = 0
    lightfov.set_player(5, 5, 12)
    -- first tick computes immediately
    lightfov.tick(0.01)
    assert(fov_calls == 1)
    -- player tile changes every tick for one simulated second at 100 Hz: at most 1 + 10 more computes
    local x = 5
    for _ = 1, 100 do
      x = x + 1
      lightfov.set_player(x, 5, 12)
      lightfov.tick(0.01)
    end
    assert(fov_calls <= 12, "computed " .. fov_calls .. " times in ~1 s")
    assert(fov_calls >= 9, "throttle too aggressive: " .. fov_calls)
    -- explicit gap check: after a compute, a change within < 0.1 s waits, then is applied
    lightfov.tick(0.2) -- settle
    local before = fov_calls
    lightfov.set_player(40, 5, 12)
    lightfov.tick(0.1) -- time since last compute >= 0.1 -> computes
    assert(fov_calls == before + 1)
    lightfov.set_player(41, 5, 12)
    lightfov.tick(0.04)
    assert(fov_calls == before + 1) -- too soon, pending
    lightfov.tick(0.04)
    assert(fov_calls == before + 1)
    lightfov.tick(0.04) -- 0.12 s since the last compute
    assert(fov_calls == before + 2)
    -- no change + no dirty flag: no compute no matter how long we wait
    lightfov.tick(1.0)
    assert(fov_calls == before + 2)
    -- mark_dirty is applied at the next allowed tick, not faster than 10 Hz either
    lightfov.mark_dirty()
    lightfov.tick(0.02)
    lightfov.tick(0.02)
    lightfov.tick(0.02)
  end)
end

function T.location_lights_use_table_radius_and_colour()
  local rec = light_recorder()
  with_fake_iso(rec.api, function()
    lightfov.clear_lights()
    lightfov.init({ hour = 12, indoor = false })
    local plan = mapbuild.plan(street_block, { mode = "exterior" })
    assert(#plan.lights == 4)
    for _, lt in ipairs(plan.lights) do
      assert(lt.name and lt.radius == nil and lt.color == nil, "location data must carry name + position only")
    end
    rec.next_id, rec.lights = 0, {}
    local state = mapbuild.apply(plan, { add_light = lightfov.add_light })
    assert(#state.light_ids == 4)
    for i, lt in ipairs(plan.lights) do
      local got = rec.lights[state.light_ids[i]]
      local def = lights.sources[lt.name]
      assert(got.radius == def.radius, lt.name)
      for k = 1, 3 do assert(near(got.color[k], def.color[k])) end
      assert(near(got.x, lt.x + 0.5) and near(got.z, lt.y + 0.5))
    end
  end)
end

function T.house_cutaway_window_lights_follow_time()
  local rec = light_recorder()
  with_fake_iso(rec.api, function()
    lightfov.clear_lights()
    lightfov.init({ hour = 12, indoor = true })
    local plan = mapbuild.plan(suburb_house, { mode = "cutaway" })
    local windows = 0
    for _, c in ipairs(plan.cells) do
      if c.kind == "window" then windows = windows + 1 end
    end
    assert(windows >= 1)
    local win_plan = {}
    for _, lt in ipairs(plan.lights) do
      if lt.name == "window" then win_plan[#win_plan + 1] = lt end
    end
    assert(#win_plan == windows)
    -- exterior mode has no window lights
    for _, lt in ipairs(mapbuild.plan(suburb_house, { mode = "exterior" }).lights) do
      assert(lt.name ~= "window")
    end

    local created = {}
    local state = mapbuild.apply(plan, {
      add_light = function(name, x, z)
        local id = lightfov.add_light(name, x, z)
        created[#created + 1] = { name = name, id = id }
        return id
      end,
    })
    assert(#state.light_ids == #plan.lights)
    local win_ids = {}
    for _, c in ipairs(created) do
      if c.name == "window" then win_ids[#win_ids + 1] = c.id end
    end
    assert(#win_ids == windows)
    local def = lights.sources.window
    local o12 = lightfov.ambient_at(12, false)
    for _, id in ipairs(win_ids) do
      local l = rec.lights[id]
      assert(l.radius == 3 and def.radius == 3)
      for k = 1, 3 do assert(near(l.color[k], o12[k] * 0.6)) end
    end
    -- the house lamp keeps its table colour at any time
    local lamp_id
    for _, c in ipairs(created) do if c.name == "lamp" then lamp_id = c.id end end
    assert(lamp_id and rec.lights[lamp_id].radius == lights.sources.lamp.radius)

    lightfov.set_time(21, true)
    local o21 = lightfov.ambient_at(21, false)
    for _, id in ipairs(win_ids) do
      local col = rec.lights[id].color
      for k = 1, 3 do
        assert(near(col[k], o21[k] * 0.6))
      end
      assert(col[1] < o12[1] * 0.6 * 0.5, "window light should be much dimmer at night")
    end
    for k = 1, 3 do assert(near(rec.lights[lamp_id].color[k], lights.sources.lamp.color[k])) end
    -- indoor ambient follows the indoor column
    assert(near(rec.ambient[1], lightfov.ambient_at(21, true)[1]))
  end)
end

function T.apply_without_hook_uses_table_values()
  local rec = light_recorder()
  with_fake_iso(rec.api, function()
    local plan = mapbuild.plan(street_block, { mode = "exterior" })
    local state = mapbuild.apply(plan) -- old call signature (probes)
    assert(#state.light_ids == 4)
    local got = rec.lights[state.light_ids[1]]
    assert(got.radius == lights.sources[plan.lights[1].name].radius)
  end)
end


function T.apply_without_hook_tints_window_lights()
  local rec = light_recorder()
  with_fake_iso(rec.api, function()
    lightfov.clear_lights()
    lightfov.init({ hour = 12, indoor = true })
    local plan = mapbuild.plan(suburb_house, { mode = "cutaway" })
    local state = mapbuild.apply(plan) -- no add_light hook
    assert(#state.light_ids == #plan.lights)
    local win = {}
    for i, lt in ipairs(plan.lights) do
      if lt.name == "window" then win[#win + 1] = state.light_ids[i] end
    end
    assert(#win >= 1)
    local o12 = lightfov.ambient_at(12, false)
    for _, id in ipairs(win) do
      for k = 1, 3 do assert(near(rec.lights[id].color[k], o12[k] * 0.6)) end
    end
    lightfov.set_time(21, true)
    local o21 = lightfov.ambient_at(21, false)
    for _, id in ipairs(win) do
      for k = 1, 3 do assert(near(rec.lights[id].color[k], o21[k] * 0.6)) end
    end
  end)
end

return T
