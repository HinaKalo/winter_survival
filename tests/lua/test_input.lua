package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local input = require("core.input")
local serialize = require("core.serialize")

local T = {}

-- Temporarily replace functions on a library table (iso / pad) and restore them afterwards.
local function with_patch(lib, patch, fn)
  local saved = {}
  for k, v in pairs(patch) do
    saved[k] = lib[k]
    lib[k] = v
  end
  local ok, err = pcall(fn)
  for k in pairs(patch) do lib[k] = saved[k] end
  assert(ok, tostring(err))
end

local function held_keys(set)
  return function(code) return set[code] == true end
end

function T.move_dir_default_wasd_not_fixed()
  input.reset_all()
  local a = input.get_action("move_dir")
  assert(a.rebindable and a.fixed == nil)
  assert(input.get_binding("keyboard", "move_dir", "up").key == keys.W)
  assert(input.get_binding("keyboard", "move_dir", "left").key == keys.A)
  assert(input.get_binding("keyboard", "move_dir", "down").key == keys.S)
  assert(input.get_binding("keyboard", "move_dir", "right").key == keys.D)
  assert(input.get_binding("pad", "move_dir", "ls").axis == "ls")
  assert(input.validate())
end

function T.rebind_interact_to_d_conflicts_with_move_dir()
  input.reset_all()
  local c = input.find_conflict("keyboard", "interact", { key = keys.D })
  assert(c and c.action_id == "move_dir" and c.slot == "right" and c.rebindable == true)
  -- the other direction: binding a direction slot to F conflicts with interact
  local c2 = input.find_conflict("keyboard", "move_dir", { key = keys.F })
  assert(c2 and c2.action_id == "interact")
  -- replace flow: interact takes D, move_dir.right is cleared -> no key entry left on that slot, but the
  -- action still has other slots, so validate passes
  assert(input.replace_binding("keyboard", "interact", 1, { key = keys.D }, "move_dir", "right"))
  assert(input.get_binding("keyboard", "interact", 1).key == keys.D)
  assert(input.get_binding("keyboard", "move_dir", "right") == nil)
  input.reset_all()
end

function T.rebind_move_dir_slot_and_reserved()
  input.reset_all()
  assert(input.set_binding("keyboard", "move_dir", "right", { key = keys.L }))
  assert(input.get_binding("keyboard", "move_dir", "right").key == keys.L)
  local ok, err = input.set_binding("keyboard", "move_dir", "up", { key = keys.ESCAPE })
  assert(not ok and err == "reserved")
  -- numeric slots do not exist on the keyboard move_dir; pad takes only the stick axis
  assert(not input.set_binding("keyboard", "move_dir", 1, { key = keys.L }))
  assert(not input.set_binding("pad", "move_dir", "ls", { btn = pad_buttons.a }))
  assert(not input.set_binding("pad", "move_dir", 1, { btn = pad_buttons.a }))
  input.reset_all()
end

function T.move_vec_follows_bindings_and_ls()
  input.reset_all()
  local iso = require("iso")
  local down = {}
  with_patch(iso, { key_down = held_keys(down) }, function()
    with_patch(pad, { axis = function() return 0 end }, function()
      local x, y = input.move_vec()
      assert(x == 0 and y == 0)
      down[keys.D] = true
      x, y = input.move_vec()
      assert(x == 1 and y == 0)
      down[keys.D] = nil
      -- rebind right to L: D no longer moves, L does
      assert(input.set_binding("keyboard", "move_dir", "right", { key = keys.L }))
      down[keys.D] = true
      x, y = input.move_vec()
      assert(x == 0 and y == 0)
      down[keys.D] = nil
      down[keys.L] = true
      x, y = input.move_vec()
      assert(x == 1 and y == 0)
      -- diagonal is clamped to unit length
      down[keys.W] = true
      x, y = input.move_vec()
      assert(math.abs(math.sqrt(x * x + y * y) - 1) < 1e-9 and x > 0 and y < 0)
      -- opposite keys cancel
      down[keys.L], down[keys.A] = true, true
      down[keys.W] = nil
      x, y = input.move_vec()
      assert(x == 0 and y == 0)
    end)
  end)
  input.reset_all()
end

function T.move_vec_left_stick_deadzone_and_clamp()
  input.reset_all()
  local iso = require("iso")
  local ax = { lx = 0.0, ly = 0.0 }
  local function axis(i)
    if i == (pad_axes.lx or 0) then return ax.lx end
    return ax.ly
  end
  with_patch(iso, { key_down = function() return false end }, function()
    with_patch(pad, { axis = axis }, function()
      ax.lx, ax.ly = 0.2, 0.1 -- inside deadzone (0.25)
      local x, y = input.move_vec()
      assert(x == 0 and y == 0)
      ax.lx, ax.ly = 0.5, 0.0
      x, y = input.move_vec()
      assert(math.abs(x - 0.5) < 1e-9 and y == 0)
      ax.lx, ax.ly = 1.0, 1.0 -- clamped to unit length
      x, y = input.move_vec()
      assert(math.abs(math.sqrt(x * x + y * y) - 1) < 1e-9)
    end)
  end)
  input.reset_all()
end

function T.move_dir_bindings_round_trip_through_save()
  input.reset_all()
  assert(input.set_binding("keyboard", "move_dir", "up", { key = keys.I }))
  assert(input.set_binding("keyboard", "move_dir", "right", { key = keys.L, shift = true }))
  assert(input.set_binding("keyboard", "attack", 1, { key = keys.K }))
  local blob = serialize.encode(input.export_bindings())
  local ok, tbl = serialize.decode(blob)
  assert(ok)
  input.reset_all()
  assert(input.get_binding("keyboard", "move_dir", "up").key == keys.W)
  input.import_bindings(tbl)
  assert(input.get_binding("keyboard", "move_dir", "up").key == keys.I)
  local r = input.get_binding("keyboard", "move_dir", "right")
  assert(r.key == keys.L and r.shift == true)
  assert(input.get_binding("keyboard", "move_dir", "left").key == keys.A)
  assert(input.get_binding("keyboard", "attack", 1).key == keys.K)
  assert(input.get_binding("pad", "move_dir", "ls").axis == "ls")
  assert(input.validate())
  input.reset_all()
end

function T.validate_checks_string_screen_targets_and_na()
  input.reset_all()
  assert(input.validate())
  -- select/move_to keyboard entry is `cursor_free` (V): clearing V must be rejected via the string screen target
  local ok, err = input.set_binding("keyboard", "cursor_free", 1, nil)
  assert(not ok and err == "no_entry")
  assert(input.get_binding("keyboard", "cursor_free", 1).key == keys.V) -- rolled back
  -- open_wheel keyboard/mouse are "–" in UI-UX §7.1 (na), no screen claim
  local a = input.get_action("open_wheel")
  assert(a.screen == nil or (a.screen.keyboard == nil and a.screen.mouse == nil))
  assert(a.na.keyboard and a.na.mouse)
  input.reset_all()
end

return T
