-- Data integrity: items, recipes, tech, characters, values, weather, home template.
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local items = require("data.items")
local recipes = require("data.recipes")
local tech = require("data.tech")
local cards = require("data.characters")
local values = require("data.values")
local weather = require("data.weather")
local balance = require("data.balance")
local layout = require("core.layout")
local ranch = require("data.homes.ranch_a")

local T = {}

local KNOWN_TAGS = {
  food_any = true, food_raw = true, food_ingredient = true, water_any = true,
  fuel_any = true, heat_fuel = true, med_any = true, luxury_any = true,
  alcohol_any = true, parts_any = true, tool_any = true, weapon_any = true,
  melee_any = true, gun_any = true, ammo_any = true, wear_any = true,
  car_part = true, blueprint_any = true,
}

function T.items_complete()
  assert(items.count == 104, "item count " .. tostring(items.count))
  for id, def in pairs(items.items) do
    assert(def.cat, id .. " cat")
    assert(type(def.kg) == "number" and def.kg >= 0, id .. " kg")
    assert(type(def.stack) == "number" and def.stack >= 1, id .. " stack")
    assert(type(def.vp) == "number" and def.vp >= 0, id .. " vp")
    for _, tag in ipairs(def.tags) do
      assert(KNOWN_TAGS[tag], id .. " unknown tag " .. tag)
    end
  end
end

function T.start_stash_items_exist()
  for id, n in pairs(balance.start_stash) do
    assert(items.get(id), "start stash unknown item " .. id)
    assert(n > 0, id .. " count")
  end
end

function T.recipes_reference_valid()
  assert(recipes.count >= 50, "recipe count " .. tostring(recipes.count))
  for id, r in pairs(recipes.recipes) do
    assert(r.station, id .. " station")
    assert(type(r.minutes) == "number", id .. " minutes")
    if r.tech then assert(tech.get(r.tech), id .. " tech " .. r.tech) end
    for item, n in pairs(r.inputs or {}) do
      assert(items.get(item), id .. " input " .. item)
      assert(n > 0, id .. " input count")
    end
    for item, n in pairs(r.outputs or {}) do
      assert(items.get(item), id .. " output " .. item)
      assert(n > 0, id .. " output count")
    end
    for item in pairs(r.fuel or {}) do assert(items.get(item), id .. " fuel " .. item) end
    for _, group in ipairs(r.input_any or {}) do
      if group.tag then assert(KNOWN_TAGS[group.tag], id .. " input tag " .. group.tag)
      else for _, item in ipairs(group) do assert(items.get(item), id .. " any input " .. item) end end
    end
    for _, tool in ipairs(r.tools_all or {}) do assert(items.get(tool), id .. " tool " .. tool) end
  end
end

function T.tech_reference_valid()
  assert(#tech.list == 40, "tech node count " .. tostring(#tech.list))
  for _, node in ipairs(tech.list) do
    for _, pre in ipairs(node.prereq or {}) do assert(tech.get(pre), node.id .. " prereq " .. pre) end
    for item in pairs(node.cost or {}) do assert(items.get(item), node.id .. " cost " .. item) end
    if node.tool then assert(items.get(node.tool), node.id .. " tool") end
    if node.exclusive then assert(cards.get(node.exclusive), node.id .. " exclusive") end
  end
end

function T.characters_complete()
  assert(#cards.order == 10)
  for _, id in ipairs(cards.order) do
    local c = cards.get(id)
    assert(c and c.id == id)
    assert(c.role == "home" or c.role == "field" or c.role == "either", id .. " role")
    for _, dim in ipairs(values.dimensions) do
      assert(type(c.values[dim]) == "number", id .. " value " .. dim)
    end
    for item in pairs(c.start_items or {}) do end
    for _, item in ipairs(c.start_items or {}) do assert(items.get(item), id .. " start item " .. item) end
  end
end

function T.weather_config()
  assert(type(weather.base_mean) == "number")
  assert(weather.big_severity == 4)
  assert(weather.forecast[3].lead >= 3)
end

function T.home_template_parses()
  local l, err = layout.parse(ranch, "A")
  assert(l, err)
  assert(l.rooms.living and l.rooms.kitchen and l.rooms.bedroom and l.rooms.workshop)
  for _, room in pairs(l.rooms) do assert(room.area > 0) end
end

return T
