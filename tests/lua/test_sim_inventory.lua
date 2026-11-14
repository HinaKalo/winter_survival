-- Inventory: stacking, tags, value order, fuel fractions, spoilage, capacity.
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local inventory = require("sim.inventory")
local items = require("data.items")

local T = {}

function T.add_remove_and_weight()
  local b = inventory.new(10, 20)
  assert(inventory.add(b, "canned_beans", 5))
  assert(inventory.count(b, "canned_beans") == 5)
  assert(math.abs(inventory.weight(b) - 2.25) < 1e-9)
  assert(inventory.remove(b, "canned_beans", 2))
  assert(inventory.count(b, "canned_beans") == 3)
  assert(not inventory.remove(b, "canned_beans", 9))
end

function T.tags_and_consume_order()
  local b = inventory.new(20, 100)
  inventory.add(b, "canned_beans", 2, { force = true })
  inventory.add(b, "canned_meat", 2, { force = true })
  assert(inventory.count_tag(b, "food_any") == 4)
  -- beans are cheaper than meat, so they go first
  local left = inventory.consume_tag_from(b, "food_any", 3)
  assert(left == 0)
  assert(inventory.count(b, "canned_beans") == 0)
  assert(inventory.count(b, "canned_meat") == 1)
end

function T.spoilage()
  local b = inventory.new(10, 20)
  inventory.add(b, "cooked_meal", 2, { force = true })
  inventory.spoil_tick(b, 12, 20)
  assert(not b.items.cooked_meal.spoiled)
  inventory.spoil_tick(b, 30, 20)
  assert(b.items.cooked_meal.spoiled, "36h at >5C spoils")
  local cold = inventory.new(10, 20)
  inventory.add(cold, "stew", 1, { force = true })
  inventory.spoil_tick(cold, 100, -5)
  assert(not cold.items.stew.spoiled, "freezing keeps food")
end

function T.fractional_fuel()
  local b = inventory.new(10, 100)
  inventory.add(b, "firewood", 2, { force = true })
  assert(inventory.burn_fuel(b, "firewood", 0.5))
  assert(inventory.count(b, "firewood") == 2)
  assert(inventory.burn_fuel(b, "firewood", 0.5))
  assert(inventory.count(b, "firewood") == 1, "fractions accumulate to one item")
end

function T.slots()
  local b = inventory.new(3, 100)
  assert(inventory.add(b, "canned_beans", 12, { force = true }))
  assert(inventory.slots_used(b) == 1)
  assert(inventory.add(b, "canned_beans", 1))
  assert(inventory.slots_used(b) == 2)
end

function T.item_count()
  assert(items.count == 104)
end

return T
