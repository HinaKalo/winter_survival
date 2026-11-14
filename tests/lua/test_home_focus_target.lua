-- 验收测试（主代理编写，实现者不得修改；认为有误时提出，由主代理裁定）。docs/M4-PLAN.md 任务 U1；UI-UX §6.4。
-- 手柄/键盘焦点目标自动选择：view/focus_target.lua（纯函数，不碰 iso）。
--
-- 冻结接口：
--   ft.R = { home = 3.0, raid = 2.5, combat = 4.0 }
--   ft.PRIO = { urgent = 2.0, npc = 1.2, container = 1.0, door = 0.8, station = 0.8, item = 0.5, deco = 0 }
--   ft.score(actor, cand, f) -> number | nil      nil = 淘汰
--   ft.pick(actor, cands, opts) -> cand | nil
--     actor = { x, y, face = { x, y } }            格坐标；face 为当前朝向（不必归一化）
--     cand  = { id, x, y, kind, enabled = bool, reachable = bool }
--     opts  = { mode = "home"|"raid"|"combat", stick = { x, y } | nil, current = <id> | nil }
--   规则（UI-UX §6.4）：
--     候选 = 距离 d ≤ R、enabled、reachable
--     f = stick（偏移长度 > 0.3 时）否则 actor.face
--     cosθ = f 与 (cand − actor) 的夹角余弦；cosθ < −0.2 且 d > 1.0 → 淘汰；d == 0 时 cosθ 视为 1
--     score = d + 2.0·(1 − cosθ) − PRIO[kind]
--     取最小；current 仍在 R+0.5 内且未被淘汰时，新候选须比它低 0.5 以上才切换；
--     current 走出 R+0.5（或被淘汰、消失）→ 按无 current 处理
--     同分取 id 字典序较小者（确定性）
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local ft = require("view.focus_target")

local T = {}

local function A(x, y, fx, fy) return { x = x, y = y, face = { x = fx or 1, y = fy or 0 } } end
local function C(id, x, y, kind, extra)
  local c = { id = id, x = x, y = y, kind = kind or "station", enabled = true, reachable = true }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end
local function near(a, b) return math.abs(a - b) < 1e-6 end

function T.constants()
  assert(ft.R.home == 3.0 and ft.R.raid == 2.5 and ft.R.combat == 4.0)
  assert(ft.PRIO.urgent == 2.0 and ft.PRIO.npc == 1.2 and ft.PRIO.container == 1.0)
  assert(ft.PRIO.door == 0.8 and ft.PRIO.station == 0.8 and ft.PRIO.item == 0.5 and ft.PRIO.deco == 0)
end

function T.score_formula()
  local a = A(0, 0, 1, 0)
  -- straight ahead, d = 2: 2 + 0 - 0.8
  assert(near(ft.score(a, C("s", 2, 0), { x = 1, y = 0 }), 1.2))
  -- 90 degrees, d = 1: 1 + 2*(1-0) - 1.0
  assert(near(ft.score(a, C("c", 0, 1, "container"), { x = 1, y = 0 }), 2.0))
  -- behind and far: eliminated
  assert(ft.score(a, C("b", -2, 0), { x = 1, y = 0 }) == nil)
  -- behind but adjacent (d <= 1): kept, cos = -1 -> 1 + 4 - 0.8
  assert(near(ft.score(a, C("b", -1, 0), { x = 1, y = 0 }), 4.2))
  -- same tile
  assert(near(ft.score(a, C("z", 0, 0, "item"), { x = 1, y = 0 }), -0.5))
end

function T.filters_radius_enabled_reachable()
  local a = A(0, 0)
  assert(ft.pick(a, { C("far", 3.5, 0) }, { mode = "home" }) == nil, "outside R home")
  assert(ft.pick(a, { C("far", 3.5, 0) }, { mode = "combat" }).id == "far", "inside R combat")
  assert(ft.pick(a, { C("off", 1, 0, "station", { enabled = false }) }, { mode = "home" }) == nil)
  assert(ft.pick(a, { C("wall", 1, 0, "station", { reachable = false }) }, { mode = "home" }) == nil)
  assert(ft.pick(a, {}, { mode = "home" }) == nil)
end

function T.prefers_low_score_and_priority()
  local a = A(0, 0)
  local got = ft.pick(a, { C("deco", 1, 0, "deco"), C("npc", 1.5, 0, "npc") }, { mode = "home" })
  assert(got.id == "npc", "npc priority beats nearer decoration")
  got = ft.pick(a, { C("hurt", 1.5, 0, "urgent"), C("box", 1, 0, "container") }, { mode = "home" })
  assert(got.id == "hurt", "urgent wins")
end

function T.stick_overrides_facing()
  local a = A(0, 0, 1, 0)
  local cands = { C("east", 2, 0), C("north", 0, -2) }
  assert(ft.pick(a, cands, { mode = "home" }).id == "east")
  assert(ft.pick(a, cands, { mode = "home", stick = { x = 0, y = -1 } }).id == "north")
  assert(ft.pick(a, cands, { mode = "home", stick = { x = 0, y = -0.2 } }).id == "east", "small stick ignored")
end

function T.hysteresis()
  local a = A(0, 0)
  -- current scores 1.2 (d 2 ahead); challenger 1.0 is better by only 0.2 -> keep current
  local cur = C("cur", 2, 0)
  local ch = C("ch", 1.8, 0, "station")
  assert(ft.pick(a, { cur, ch }, { mode = "home", current = "cur" }).id == "cur")
  -- challenger better by > 0.5 -> switch
  local strong = C("strong", 1, 0, "container") -- 1 - 1.0 = 0
  assert(ft.pick(a, { cur, strong }, { mode = "home", current = "cur" }).id == "strong")
  -- current between R and R+0.5 is still held
  local edge = C("edge", 3.3, 0)
  assert(ft.pick(a, { edge }, { mode = "home", current = "edge" }).id == "edge")
  -- current beyond R+0.5 is dropped; nothing else in range
  local gone = C("gone", 3.6, 0)
  assert(ft.pick(a, { gone }, { mode = "home", current = "gone" }) == nil)
  -- current missing from the list -> plain pick
  assert(ft.pick(a, { ch }, { mode = "home", current = "nope" }).id == "ch")
end

function T.deterministic_ties()
  local a = A(0, 0, 0, 1)
  local got = ft.pick(a, { C("b", 1, 1), C("a", -1, 1) }, { mode = "home" })
  assert(got.id == "a")
end

function T.pure_module()
  local f = assert(io.open("assets/scripts/view/focus_target.lua", "r"))
  local src = f:read("a")
  f:close()
  assert(not src:find("iso%."), "no engine calls")
end

-- M4-user 审查第 1 轮（Codex P2）：非有限的朝向或摇杆（inf / NaN）按“无朝向”处理（cosθ = 1）或忽略摇杆，
-- 结果不依赖候选顺序；score 永不返回 NaN。
function T.non_finite_direction_is_ignored()
  local inf, nan = math.huge, 0 / 0
  local cands = { C("far", 2, 0), C("near", 1, 0) }
  local rev = { cands[2], cands[1] }
  for _, face in ipairs({ { x = inf, y = 0 }, { x = nan, y = 1 }, { x = -inf, y = inf } }) do
    local a = { x = 0, y = 0, face = face }
    local s = ft.score(a, cands[1], face)
    assert(s == nil or s == s, "score is never NaN")
    local p1, p2 = ft.pick(a, cands, { mode = "home" }), ft.pick(a, rev, { mode = "home" })
    assert(p1 and p2 and p1.id == "near" and p2.id == "near", "nearest wins regardless of order")
  end
  local a = A(0, 0, 1, 0)
  local east, north = C("east", 2, 0), C("north", 0, -1.5)
  for _, st in ipairs({ { x = inf, y = 0 }, { x = 0, y = nan } }) do
    local got = ft.pick(a, { north, east }, { mode = "home", stick = st })
    assert(got and got.id == "east", "non-finite stick is ignored, facing used")
  end
end

return T
