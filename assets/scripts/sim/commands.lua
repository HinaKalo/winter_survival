-- Command registry (P0-PLAN 3.2, PARALLEL-PLAN C2): every player/bot change to the model goes
-- through commands.run. Handlers live in sim/cmd/<domain>.lua and register themselves here:
--
--   local reg = require("sim.commands").domain("needs")
--   reg("eat", function(state, cmd) ... end, {
--     args = { { "char", "char" }, { "item", "item?" } },  -- ordered; "?" = optional
--     phase = nil, phase_err = nil,                         -- e.g. { "day" }, "not_day"
--   })
--
-- Arg entry: { name, type, max = (char_list), enum_err = (enum), missing_err = (required), optional = (enum) }.
-- Types: char char_list item recipe tech room station job loc npc item_counts number int boolean
-- string table, or an enum list such as { "low", "high" }.
-- Rule for handlers: every check happens before the first write to the state.
local inventory = require("sim.inventory")
local state_mod = require("sim.state")
local items_data = require("data.items")
local recipes_data = require("data.recipes")
local tech_data = require("data.tech")

local M = {}
package.loaded["sim.commands"] = M -- domain files require this module while it is still loading

-- Adding a domain is a contract change (P0-PLAN 3.2).
M.DOMAINS = { "home", "needs", "craft", "tech", "night", "raid", "trade", "travel", "story" }

-- Old M3 names, kept until the end of M4. The failure log records the name as submitted.
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

local registry = {} -- kind -> { fn = function, spec = table }

-- ------------------------------------------------------------------ argument types

local function finite(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local TYPE_ERR = {
  char = "no_char", char_list = "bad_squad", item = "unknown_item", recipe = "unknown_recipe",
  tech = "unknown_tech", room = "bad_room", station = "no_station", job = "no_job", loc = "bad_loc",
  npc = "bad_npc", item_counts = "bad_items", number = "bad_arg", int = "bad_arg", boolean = "bad_arg",
  string = "bad_arg", table = "bad_arg",
}

local function alive(state, id)
  if type(id) ~= "string" then return false end
  local ch = state.party.chars[id]
  return ch ~= nil and ch.status == "alive"
end

local CHECKS = {}

function CHECKS.char(state, v) return alive(state, v) end

function CHECKS.item(_, v) return type(v) == "string" and items_data.items[v] ~= nil end
function CHECKS.recipe(_, v) return type(v) == "string" and recipes_data.recipes[v] ~= nil end
function CHECKS.tech(_, v) return type(v) == "string" and tech_data.by_id[v] ~= nil end
function CHECKS.room(state, v) return type(v) == "string" and state.home.rooms[v] ~= nil end
function CHECKS.station(state, v) return type(v) == "string" and state.home.stations[v] ~= nil end
function CHECKS.job(state, v) return type(v) == "string" and state.jobs[v] ~= nil end

function CHECKS.loc(state, v)
  if type(v) ~= "string" or not v:match("^[a-z0-9_]+$") then return false end
  local locs = state.world and state.world.locations
  if type(locs) == "table" and next(locs) ~= nil then return locs[v] ~= nil end
  return true
end

function CHECKS.npc(_, v) return type(v) == "string" and v:match("^[a-z0-9_.]+$") ~= nil end

function CHECKS.item_counts(_, v)
  if type(v) ~= "table" then return false end
  for id, n in pairs(v) do
    if type(id) ~= "string" or items_data.items[id] == nil then return false end
    if not finite(n) or n < 1 or n ~= math.floor(n) then return false end
  end
  return true
end

function CHECKS.number(_, v) return finite(v) end
function CHECKS.int(_, v) return finite(v) and v == math.floor(v) end
function CHECKS.boolean(_, v) return type(v) == "boolean" end
function CHECKS.string(_, v) return type(v) == "string" end
function CHECKS.table(_, v) return type(v) == "table" end

-- Returns nil or an error code.
local function check_char_list(state, v, entry)
  if type(v) ~= "table" then return "bad_squad" end
  local n = 0
  for _ in pairs(v) do n = n + 1 end
  if n < 1 or n > (entry.max or math.huge) or n ~= #v then return "bad_squad" end
  local seen = {}
  for _, cid in ipairs(v) do
    if not alive(state, cid) then return "no_char" end
    if seen[cid] then return "bad_squad" end
    seen[cid] = true
  end
  return nil
end

local function base_type(t)
  if type(t) == "table" then return nil end
  local bt = t:gsub("%?$", "")
  return bt
end

local function is_optional(entry)
  local t = entry[2]
  if type(t) == "table" then return entry.optional == true end
  return t:sub(-1) == "?"
end

local function check_arg(state, cmd, entry)
  local v = cmd[entry[1]]
  local t = entry[2]
  if v == nil then
    if is_optional(entry) then return nil end
    if type(t) == "table" then return entry.enum_err or "bad_arg" end
    return entry.missing_err or TYPE_ERR[base_type(t)]
  end
  if type(t) == "table" then
    for _, e in ipairs(t) do
      if v == e then return nil end
    end
    return entry.enum_err or "bad_arg"
  end
  local bt = base_type(t)
  if bt == "char_list" then return check_char_list(state, v, entry) end
  if not CHECKS[bt](state, v) then return TYPE_ERR[bt] end
  return nil
end

-- ------------------------------------------------------------------ registration

local function valid_spec(spec)
  if type(spec) ~= "table" or type(spec.args) ~= "table" then return false end
  for _, a in ipairs(spec.args) do
    if type(a) ~= "table" or type(a[1]) ~= "string" then return false end
    local t = a[2]
    if type(t) == "string" then
      local bt = base_type(t)
      if not (CHECKS[bt] or bt == "char_list") then return false end
    elseif type(t) ~= "table" then
      return false
    end
  end
  if spec.phase ~= nil and type(spec.phase) ~= "table" then return false end
  return true
end

local function register(kind, fn, spec)
  if type(kind) ~= "string" or not kind:match("^[a-z]+%.[a-z_]+$") then
    error("commands: bad command name " .. tostring(kind), 3)
  end
  local dom = kind:match("^([a-z]+)%.")
  local known = false
  for _, d in ipairs(M.DOMAINS) do known = known or d == dom end
  if not known then error("commands: unknown domain in " .. kind, 3) end
  if registry[kind] then error("commands: duplicate command " .. kind, 3) end
  if type(fn) ~= "function" then error("commands: handler for " .. kind .. " must be a function", 3) end
  if not valid_spec(spec) then error("commands: bad spec for " .. kind, 3) end
  registry[kind] = { fn = fn, spec = spec }
end

-- Returns reg(short_name, fn, spec); short_name may also be the full "domain.name".
function M.domain(d)
  local known = false
  for _, name in ipairs(M.DOMAINS) do known = known or name == d end
  if not known then error("commands: domain " .. tostring(d) .. " is not in DOMAINS", 2) end
  return function(name, fn, spec)
    if type(name) ~= "string" then error("commands: bad command name " .. tostring(name), 2) end
    local full = name:find(".", 1, true) and name or (d .. "." .. name)
    if full:match("^([^.]*)%.") ~= d then
      error("commands: " .. full .. " does not belong to domain " .. d, 2)
    end
    register(full, fn, spec)
  end
end

-- Registers the signature only; the handler always fails with not_implemented (no state, no log).
function M.reserve(kind, spec)
  register(kind, function() return false, "not_implemented" end, spec)
end

function M.list()
  local out = {}
  for kind in pairs(registry) do out[#out + 1] = kind end
  table.sort(out)
  return out
end

function M.spec(kind)
  local e = type(kind) == "string" and registry[kind] or nil
  return e and e.spec or nil
end

function M.aliases()
  local out = {}
  for old, new in pairs(ALIASES) do out[old] = new end
  return out
end

function M.can(_, kind)
  if type(kind) ~= "string" then return false end
  return registry[ALIASES[kind] or kind] ~= nil
end

-- ------------------------------------------------------------------ run

-- Returns ok, err, extra. Unknown kinds, garbage fields and handler faults give false, err and
-- never raise; faults are also recorded in state.errors so audits see them.
function M.run(state, cmd)
  if type(cmd) ~= "table" then return false, "bad_command" end
  local kind = cmd.kind
  if kind == nil then kind = cmd[1] end
  if type(kind) ~= "string" then return false, "bad_command" end
  local entry = registry[ALIASES[kind] or kind]
  if not entry then return false, "unknown_command" end
  local spec = entry.spec

  local function fail(err)
    state_mod.log(state, "command_failed", { kind = kind, err = err })
    return false, err
  end

  if spec.phase then
    local allowed = false
    for _, p in ipairs(spec.phase) do allowed = allowed or p == state.clock.phase end
    if not allowed then return fail(spec.phase_err or "wrong_phase") end
  end
  for _, a in ipairs(spec.args) do
    local err = check_arg(state, cmd, a)
    if err then return fail(err) end
  end

  -- Inventory flow ledger: everything this command moves is booked under the submitted kind
  -- (craft/research override with finer reasons).
  local prev_reason = inventory.set_reason(kind)
  local called, ok, err, extra = pcall(entry.fn, state, cmd)
  inventory.set_reason(prev_reason)
  if not called then
    state_mod.error(state, "command " .. kind .. " raised: " .. tostring(ok))
    return false, "internal_error"
  end
  if not ok then
    if err == "not_implemented" then return false, err end
    state_mod.log(state, "command_failed", { kind = kind, err = tostring(err) })
  end
  return ok and true or false, err, extra
end

for _, d in ipairs(M.DOMAINS) do require("sim.cmd." .. d) end

return M
