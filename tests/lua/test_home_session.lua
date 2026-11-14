-- 验收测试，编码代理不得修改（主代理编写；认为有误时停下报告）。docs/M4L-PLAN.md §3。
-- M4-lite：家园可玩会话层 game/home_session.lua（纯模型层，不碰 iso / view）。
--
-- 冻结接口：
--   hs.new(seed[, opts]) -> s          s.state = sim 状态；s.mode ∈ "day" | "dusk" | "dawn" | "ending"
--   hs.MIN_PER_SEC = 2                  1× 速度下每真实秒推进的游戏分钟
--   hs.SPEEDS = { 0, 1, 2, 4 }          倍率；hs.set_speed(s, i) 选第 i 档，s.speed_idx；新会话为第 2 档（1×）
--   hs.update(s, dt)                    只在 mode=="day" 时推进；分钟小数累积；进入 dusk 相位立刻停在 mode="dusk"
--   hs.end_day(s) -> ok, err            day 模式下直接快进到黄昏
--   hs.dusk_options(s) -> { chars = {cid...}, roles = { "sleep", "guard", "out" } }
--   hs.confirm_dusk(s, roles) -> ok, err  roles = { [cid] = role }（缺省 sleep）；跑完夜间到黎明，mode="dawn"
--                                        s.report = { day = <刚结束的天>, lines = { { key = string, args = table }, ... } }
--   hs.confirm_dawn(s) -> ok, err       推进到白天开始，mode="day"
--   hs.actions(s, cid) -> list of { id, kind, label, enabled, reason }
--        kind ∈ craft | research | eat | drink | sleep | wake | toggle；id 形如 "craft:<recipe>"、"toggle:<station>"、
--        "eat"、"sleep"；label 是 i18n 键；enabled=false 时 reason 是短错误键
--   hs.act(s, cid, action_id) -> ok, err  经 sim.command；失败时状态逐字节不变
--   hs.hud(s) -> { day, clock = "HH:MM", phase, outdoor_temp, food_days, fuel_days, rubble,
--                  rooms = { { id, temp } ... }（按 state.home.room_order），
--                  chars = { { id, name, activity, job, hp, needs = { hunger, thirst, energy, warmth? } } ... } }
--   hs.save(s) -> string；hs.load(str) -> s2（模式、速度、时钟、模型全部恢复）
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local hs = require("game.home_session")
local sim = require("sim.sim")
local serialize = require("core.serialize")

local T = {}

local function snap(s) return serialize.encode(s.state) end

local function find(list, id)
  for _, a in ipairs(list) do if a.id == id then return a end end
end

local function first_cid(s) return s.state.party.order[1] end

function T.new_session_starts_day1_morning()
  local s = hs.new(7)
  assert(s.mode == "day")
  assert(s.state.clock.day == 1 and s.state.clock.minute == 360)
  assert(#s.state.party.order >= 2)
  assert(hs.SPEEDS[1] == 0 and hs.SPEEDS[2] == 1 and hs.SPEEDS[4] == 4)
  assert(s.speed_idx == 2)
  local h = hs.hud(s)
  assert(h.day == 1 and h.clock == "06:00" and h.phase == "day")
  assert(type(h.outdoor_temp) == "number" and type(h.food_days) == "number" and type(h.fuel_days) == "number")
  assert(type(h.rubble) == "number" and h.rubble > 0)
  assert(#h.rooms == #s.state.home.room_order and h.rooms[1].id == s.state.home.room_order[1])
  assert(#h.chars == #s.state.party.order)
  for _, c in ipairs(h.chars) do
    assert(type(c.id) == "string" and type(c.name) == "string" and type(c.needs) == "table")
    assert(type(c.needs.hunger) == "number" and type(c.needs.energy) == "number")
  end
end

function T.update_scales_time_and_accumulates_fractions()
  local s = hs.new(7)
  hs.update(s, 1.0)
  assert(s.state.clock.minute == 360 + hs.MIN_PER_SEC, "1x: MIN_PER_SEC minutes per second")
  for _ = 1, 4 do hs.update(s, 0.25) end
  assert(s.state.clock.minute == 360 + 2 * hs.MIN_PER_SEC, "fractions accumulate")
  hs.set_speed(s, 4)
  hs.update(s, 1.0)
  assert(s.state.clock.minute == 360 + 6 * hs.MIN_PER_SEC, "4x")
  hs.set_speed(s, 1)
  local m = s.state.clock.minute
  hs.update(s, 10)
  assert(s.state.clock.minute == m, "speed 0 pauses")
end

function T.dusk_stops_the_clock()
  local s = hs.new(8)
  hs.set_speed(s, 4)
  local guard = 0
  while s.mode == "day" and guard < 10000 do hs.update(s, 0.5); guard = guard + 1 end
  assert(s.mode == "dusk", "mode becomes dusk, got " .. tostring(s.mode))
  assert(s.state.clock.phase == "dusk")
  local m = s.state.clock.minute
  hs.update(s, 30)
  assert(s.state.clock.minute == m, "time does not run while the dusk screen is up")
end

function T.end_day_jumps_to_dusk_only_by_day()
  local s = hs.new(9)
  assert(hs.end_day(s))
  assert(s.mode == "dusk" and s.state.clock.phase == "dusk")
  local ok, err = hs.end_day(s)
  assert(not ok and type(err) == "string")
end

function T.dusk_dawn_cycle_advances_the_day()
  local s = hs.new(10)
  assert(hs.end_day(s))
  local opt = hs.dusk_options(s)
  assert(#opt.chars == #s.state.party.order)
  assert(opt.roles[1] == "sleep" and opt.roles[2] == "guard" and opt.roles[3] == "out")
  local before = snap(s)
  local ok, err = hs.confirm_dusk(s, { [first_cid(s)] = "dance" })
  assert(not ok and err == "bad_role", "bad role rejected, got " .. tostring(err))
  assert(snap(s) == before and s.mode == "dusk", "failed confirm leaves state unchanged")
  assert(hs.confirm_dusk(s, { [first_cid(s)] = "guard" }))
  assert(s.mode == "dawn", "mode " .. tostring(s.mode))
  assert(type(s.report) == "table" and s.report.day == 1 and #s.report.lines > 0)
  for _, l in ipairs(s.report.lines) do assert(type(l.key) == "string" and type(l.args) == "table") end
  assert(hs.confirm_dawn(s))
  assert(s.mode == "day" and s.state.clock.day == 2 and s.state.clock.phase == "day")
end

function T.expedition_night_runs()
  local s = hs.new(11)
  assert(hs.end_day(s))
  assert(hs.confirm_dusk(s, { [first_cid(s)] = "out" }))
  assert(s.mode == "dawn" or s.mode == "ending")
  assert(#sim.audit(s.state) == 0, table.concat(sim.audit(s.state), "; "))
end

function T.actions_are_listed_and_match_act()
  local s = hs.new(12)
  local cid = first_cid(s)
  local list = hs.actions(s, cid)
  assert(#list > 0)
  local kinds = { craft = true, research = true, eat = true, drink = true, sleep = true, wake = true, toggle = true }
  for _, a in ipairs(list) do
    assert(type(a.id) == "string" and kinds[a.kind], "bad action " .. tostring(a.id))
    assert(type(a.label) == "string" and type(a.enabled) == "boolean")
    if not a.enabled then assert(type(a.reason) == "string") end
  end
  local rub = find(list, "craft:clear_rubble")
  assert(rub and rub.enabled, "clearing rubble is available on day 1")
  assert(find(list, "toggle:f_woodstove"), "the wood stove can be switched")
  assert(find(list, "sleep"))
  -- every disabled action fails without touching the model
  for _, a in ipairs(list) do
    if not a.enabled then
      local before = snap(s)
      local ok = hs.act(s, cid, a.id)
      assert(not ok, a.id .. " is disabled but act succeeded")
      assert(snap(s) == before, a.id .. " changed state on failure")
    end
  end
  local before = snap(s)
  local ok, err = hs.act(s, cid, "craft:no_such_recipe")
  assert(not ok and type(err) == "string" and snap(s) == before)
  ok = hs.act(s, "nobody", "sleep")
  assert(not ok and snap(s) == before)
end

function T.clearing_rubble_progresses()
  local s = hs.new(13)
  local r0 = s.state.home.rubble
  for _, cid in ipairs(s.state.party.order) do
    local a = find(hs.actions(s, cid), "craft:clear_rubble")
    if a and a.enabled then assert(hs.act(s, cid, a.id)) end
  end
  assert(s.state.party.chars[first_cid(s)].job, "the first character has a job")
  hs.set_speed(s, 4)
  for _ = 1, 60 do hs.update(s, 1.0) end -- 480 game minutes
  assert(s.state.home.rubble < r0, "rubble went down: " .. r0 .. " -> " .. s.state.home.rubble)
end

function T.lighting_the_stove_warms_the_living_room()
  local a, b = hs.new(14), hs.new(14)
  local cid = first_cid(a)
  assert(hs.act(a, cid, "toggle:f_woodstove"))
  for _, s in ipairs({ a, b }) do
    hs.set_speed(s, 4)
    for _ = 1, 15 do hs.update(s, 1.0) end -- 120 game minutes
  end
  local function living(s)
    for _, r in ipairs(hs.hud(s).rooms) do if r.id == "living" then return r.temp end end
  end
  assert(living(a) >= living(b) + 1.0,
    string.format("stove on %.2f vs off %.2f", living(a), living(b)))
end

-- A simple human-like player survives three days at home through the session API alone.
function T.three_days_at_home()
  local s = hs.new(15)
  for day = 1, 3 do
    assert(s.mode == "day" and s.state.clock.day == day)
    local stove = find(hs.actions(s, first_cid(s)), "toggle:f_woodstove")
    if stove and stove.enabled and not s.state.home.stations.f_woodstove.on then
      assert(hs.act(s, first_cid(s), stove.id))
    end
    for _, cid in ipairs(s.state.party.order) do
      local ch = s.state.party.chars[cid]
      if ch.status == "alive" then
        local list = hs.actions(s, cid)
        local eat = find(list, "eat")
        if eat and eat.enabled and ch.needs.food < 60 then hs.act(s, cid, "eat") end
        local drink = find(list, "drink")
        if drink and drink.enabled and ch.needs.water < 60 then hs.act(s, cid, "drink") end
        if not ch.job then
          for _, a in ipairs(hs.actions(s, cid)) do
            if a.kind == "craft" and a.enabled then
              assert(hs.act(s, cid, a.id))
              break
            end
          end
        end
      end
    end
    hs.set_speed(s, 4)
    local guard = 0
    while s.mode == "day" and guard < 10000 do hs.update(s, 1.0); guard = guard + 1 end
    assert(s.mode == "dusk")
    assert(hs.confirm_dusk(s, {}))
    assert(s.mode == "dawn")
    assert(hs.confirm_dawn(s))
  end
  assert(s.mode == "day" and s.state.clock.day == 4)
  local alive = 0
  for _, cid in ipairs(s.state.party.order) do
    if s.state.party.chars[cid].status == "alive" then alive = alive + 1 end
  end
  assert(alive >= 1)
  local problems = sim.audit(s.state)
  assert(#problems == 0, table.concat(problems, "; "))
end

function T.save_and_load_round_trip()
  local s = hs.new(16)
  hs.act(s, first_cid(s), "craft:clear_rubble")
  hs.set_speed(s, 3)
  for _ = 1, 20 do hs.update(s, 0.7) end
  local str = hs.save(s)
  assert(type(str) == "string")
  local s2 = assert(hs.load(str))
  assert(s2.mode == s.mode and s2.speed_idx == s.speed_idx)
  assert(serialize.encode(hs.hud(s2)) == serialize.encode(hs.hud(s)))
  for _ = 1, 20 do hs.update(s, 0.7); hs.update(s2, 0.7) end
  assert(snap(s) == snap(s2), "continuing after load gives identical state")
end

-- M4L 审查第 1 轮（Codex P2）：睡觉再唤醒后，手上的任务继续推进（不白白停到下一个黎明）
function T.wake_resumes_the_job()
  local s = hs.new(17)
  local cid = first_cid(s)
  assert(hs.act(s, cid, "craft:clear_rubble"))
  local ch = s.state.party.chars[cid]
  assert(ch.job and ch.activity == "work")
  assert(hs.act(s, cid, "sleep"))
  assert(hs.act(s, cid, "wake"))
  assert(ch.job and ch.activity == "work", "woken character goes back to work, got " .. tostring(ch.activity))
  local jid = ch.job
  local w0 = s.state.jobs[jid].work_remaining
  hs.set_speed(s, 4)
  for _ = 1, 8 do hs.update(s, 1.0) end -- 64 game minutes
  local j = s.state.jobs[jid]
  assert(j == nil or j.work_remaining < w0, "job progresses after waking")
end

function T.session_is_pure_model()
  local f = assert(io.open("assets/scripts/game/home_session.lua", "r"))
  local src = f:read("a")
  f:close()
  assert(not src:find("require%(%s*[\"']view%."), "no view requires")
  assert(not src:find("require%(%s*[\"']ui%."), "no ui requires")
  assert(not src:find("iso%."), "no iso calls")
end

return T
