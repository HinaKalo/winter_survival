-- Inventory: stacking, tags, value order, fuel fractions, spoilage, capacity.
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local inventory = require("sim.inventory")
local items = require("data.items")
local sim = require("sim.sim")

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

function T.consume_tag_from_bags_when_stash_lacks_tag()
  local s = assert(sim.new(61))
  local order = s.party.order
  local a, b = s.party.chars[order[1]], s.party.chars[order[2]]
  s.home.stash.items = {}
  inventory.add(a.inv, "canned_beans", 2, { force = true })
  inventory.add(b.inv, "canned_beans", 1, { force = true })
  local ok, rem = inventory.consume_tag(s, "food_any", 3)
  assert(ok == true and rem == 0)
  assert(inventory.count(a.inv, "canned_beans") == 0 and inventory.count(b.inv, "canned_beans") == 0)
end

function T.consume_tag_stash_first_then_bags()
  local s = assert(sim.new(62))
  local a = s.party.chars[s.party.order[1]]
  s.home.stash.items = {}
  inventory.add(s.home.stash, "canned_beans", 1, { force = true })
  inventory.add(a.inv, "canned_beans", 2, { force = true })
  assert(inventory.consume_tag(s, "food_any", 2))
  assert(inventory.count(s.home.stash, "canned_beans") == 0)
  assert(inventory.count(a.inv, "canned_beans") == 1)
end

function T.consume_tag_all_or_nothing()
  local s = assert(sim.new(63))
  local a = s.party.chars[s.party.order[1]]
  s.home.stash.items = {}
  inventory.add(a.inv, "canned_beans", 2, { force = true })
  local ok, err = inventory.consume_tag(s, "food_any", 5)
  assert(ok == false and err == "missing")
  assert(inventory.count(a.inv, "canned_beans") == 2, "nothing consumed on failure")
  local ok2 = inventory.consume_tag(s, "melee_any", 1)
  assert(ok2 == false)
end

function T.weight_and_value_are_stable()
  local b = inventory.new(20, 100)
  inventory.add(b, "canned_beans", 3, { force = true })
  inventory.add(b, "firewood", 2, { force = true })
  inventory.add(b, "canned_meat", 1, { force = true })
  local w1, v1 = inventory.weight(b), inventory.value(b)
  assert(w1 == inventory.weight(b) and v1 == inventory.value(b))
  assert(w1 > 0 and v1 > 0)
end


function T.burn_fuel_validates_before_mutating()
  local b = inventory.new(10, 100)
  inventory.add(b, "firewood", 1, { force = true })
  b.fuel_frac.firewood = 0.75
  local ok, err = inventory.burn_fuel(b, "firewood", 1.25)
  assert(ok == false and err == "missing_fuel")
  assert(inventory.count(b, "firewood") == 1 and b.fuel_frac.firewood == 0.75, "no partial burn")
  assert(not inventory.can_burn(b, "firewood", 1.25))
  assert(inventory.can_burn(b, "firewood", 1.2))
  local whole, rest = inventory.fuel_cost(b, "firewood", 1.25)
  assert(whole == 2 and rest == 0, "floor(pool + amount) whole items")
end

function T.flow_books_every_add_remove_by_reason()
  local b = inventory.new(10, 100)
  inventory.add(b, "scrap", 4, { force = true, reason = "loot" })
  inventory.remove(b, "scrap", 1, "craft_input")
  local prev = inventory.set_reason("eat")
  inventory.remove(b, "scrap", 1)
  inventory.set_reason(prev)
  assert(b.flow.src.loot.scrap == 4)
  assert(b.flow.snk.craft_input.scrap == 1 and b.flow.snk.eat.scrap == 1)
  assert(not inventory.remove(b, "scrap", 9) and b.flow.snk.craft_input.scrap == 1, "failed remove books nothing")
  local c = inventory.new(10, 100)
  assert(inventory.move(b, c, "scrap", 2))
  assert(b.flow.snk.transfer.scrap == 2 and c.flow.src.transfer.scrap == 2)
  assert(inventory.validate(b) and inventory.validate(c))
end

function T.validate_rejects_fractional_and_bad_flow()
  local b = inventory.new(10, 100)
  inventory.add(b, "scrap", 2, { force = true })
  b.items.scrap.count = 1.5
  assert(not inventory.validate(b))
  b.items.scrap.count = 2
  b.flow.src.start = { scrap = -1 }
  assert(not inventory.validate(b))
end

return T
