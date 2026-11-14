-- Technology research and blueprint learning (CONTENT §4).
local tech_data = require("data.tech")
local items = require("data.items")
local inventory = require("sim.inventory")
local util = require("core.util")
local state_mod = require("sim.state")

local M = {}

local BENCH_LEVEL = { bench1 = 1, bench2 = 2, bench3 = 3 }

local function bench_level(state)
  local best = 0
  for _, id in ipairs(util.sorted_keys(state.home.stations)) do
    local st = state.home.stations[id]
    if st.hp > 0 and BENCH_LEVEL[st.kind] and BENCH_LEVEL[st.kind] > best then
      best = BENCH_LEVEL[st.kind]
    end
  end
  return best
end

local function team_count(state, item_id)
  local n = inventory.count(state.home.stash, item_id)
  for _, c in ipairs(require("sim.chars").alive(state)) do
    n = n + inventory.count(c.inv, item_id)
  end
  return n
end

local function has_tool(state, item_id)
  return team_count(state, item_id) > 0
end

function M.unlocked(state, id)
  return state.tech.unlocked[id] == true
end

function M.blueprint(state, id)
  return state.tech.blueprints[id] == true
end

-- Whether the exclusive character is unavailable, triggering cost/work x1.5.
function M.exclusive_missing(state, node)
  if not node.exclusive then return false end
  local c = state.party.chars[node.exclusive]
  return c == nil or c.status ~= "alive"
end

function M.cost_for(state, node, actor)
  local mult = M.exclusive_missing(state, node) and 1.5 or 1.0
  local cost = {}
  for id, n in pairs(node.cost or {}) do
    local v = n * mult
    if actor and actor.traits and actor.traits.electric_cost and node.layer and node.layer:sub(1, 1) == "G" then
      v = v * actor.traits.electric_cost
    end
    cost[id] = math.max(1, math.ceil(v - 0.0001))
  end
  return cost
end

function M.work_for(state, node, actor)
  local mult = M.exclusive_missing(state, node) and 1.5 or 1.0
  local w = node.work * mult
  if actor and actor.traits and actor.traits.electric_work and node.layer and node.layer:sub(1, 1) == "G" then
    w = w * actor.traits.electric_work
  end
  return w
end

function M.can(state, node_id, actor_id)
  local node = tech_data.get(node_id)
  if not node then return false, "unknown_tech" end
  if state.tech.unlocked[node_id] then return false, "unlocked" end
  if state.tech.research then return false, "busy" end
  for _, pre in ipairs(node.prereq or {}) do
    if not state.tech.unlocked[pre] then return false, "prereq:" .. pre end
  end
  if node.blueprint and not state.tech.blueprints[node_id] then
    return false, "blueprint"
  end
  local level = bench_level(state)
  if (node.bench or 0) > level then return false, "bench" end
  if node.tool and not has_tool(state, node.tool) then return false, "tool:" .. node.tool end
  local actor = actor_id and state.party.chars[actor_id] or nil
  local cost = M.cost_for(state, node, actor)
  for id, n in pairs(cost) do
    if team_count(state, id) < n then return false, "material:" .. id end
  end
  return true
end

function M.start(state, node_id, actor_id)
  local ok, err = M.can(state, node_id, actor_id)
  if not ok then return false, err end
  local node = tech_data.get(node_id)
  local actor = state.party.chars[actor_id]
  if not actor or actor.status ~= "alive" then return false, "no_actor" end
  if actor.job then return false, "actor_busy" end
  local cost = M.cost_for(state, node, actor)
  for id, n in pairs(cost) do
    local left = n
    local from_stash = math.min(left, inventory.count(state.home.stash, id))
    if from_stash > 0 then
      inventory.remove(state.home.stash, id, from_stash)
      left = left - from_stash
    end
    if left > 0 then
      for _, c in ipairs(require("sim.chars").alive(state)) do
        if left <= 0 then break end
        local take = math.min(left, inventory.count(c.inv, id))
        if take > 0 then
          inventory.remove(c.inv, id, take)
          left = left - take
        end
      end
    end
    if left > 0 then return false, "material:" .. id end
  end
  state.job_seq = (state.job_seq or 0) + 1
  local work = M.work_for(state, node, actor)
  local job = {
    id = "job_" .. state.job_seq,
    kind = "research",
    tech = node_id,
    actor = actor_id,
    remaining = work,
    total = work,
  }
  state.jobs[job.id] = job
  state.tech.research = job.id
  actor.job = job.id
  actor.activity = "work"
  state_mod.log(state, "research_started", { tech = node_id, actor = actor_id })
  return true, job
end

function M.cancel(state, reason)
  local job_id = state.tech.research
  if not job_id then return false, "no_research" end
  local job = state.jobs[job_id]
  if job then
    local actor = state.party.chars[job.actor]
    if actor and actor.job == job_id then
      actor.job = nil
      actor.activity = "idle"
    end
    state.jobs[job_id] = nil
  end
  state.tech.research = nil
  state_mod.log(state, "research_cancelled", { tech = job and job.tech, reason = reason })
  return true
end

function M.tick(state, minutes)
  local job_id = state.tech.research
  if not job_id then return end
  local job = state.jobs[job_id]
  if not job then state.tech.research = nil return end
  local actor = state.party.chars[job.actor]
  if not actor or actor.status ~= "alive" then
    M.cancel(state, "actor_dead")
    return
  end
  local eff = require("sim.chars").efficiency(state, actor)
  job.remaining = job.remaining - minutes * math.max(0.05, eff)
  if job.remaining <= 0 then
    local node = tech_data.get(job.tech)
    state.tech.unlocked[job.tech] = true
    state.jobs[job_id] = nil
    state.tech.research = nil
    actor.job = nil
    actor.activity = "idle"
    state.stats.researches = (state.stats.researches or 0) + 1
    if node and node.star then
      require("sim.home").add_station(state, node.star, require("sim.home").station_kind(node.star), nil, 100, false)
    end
    state_mod.log(state, "research_done", { tech = job.tech })
  end
end

function M.learn_blueprint(state, actor_id, item_id)
  local def = items.get(item_id)
  if not def or not def.tech then return false, "not_blueprint" end
  local actor = state.party.chars[actor_id]
  if not actor then return false, "no_actor" end
  local bag = inventory.count(actor.inv, item_id) > 0 and actor.inv or state.home.stash
  if inventory.count(bag, item_id) <= 0 then return false, "missing" end
  inventory.remove(bag, item_id, 1)
  state.tech.blueprints[def.tech] = true
  state_mod.log(state, "blueprint_learned", { tech = def.tech, actor = actor_id })
  return true
end

function M.available(state, actor_id)
  local out = {}
  for _, node in ipairs(tech_data.list) do
    if M.can(state, node.id, actor_id) then out[#out + 1] = node.id end
  end
  table.sort(out)
  return out
end

return M
