-- 手柄/键盘焦点目标自动选择（UI-UX §6.4，纯函数模块）。
local M = {}

M.R = {
  home = 3.0,
  raid = 2.5,
  combat = 4.0,
}

M.PRIO = {
  urgent = 2.0,
  npc = 1.2,
  container = 1.0,
  door = 0.8,
  station = 0.8,
  item = 0.5,
  deco = 0,
}

local function dist(ax, ay, bx, by)
  local dx, dy = bx - ax, by - ay
  return math.sqrt(dx * dx + dy * dy), dx, dy
end

--- 计算单个候选目标的得分；若被淘汰（如背后过远）则返回 nil。
function M.score(actor, cand, f)
  local d, dx, dy = dist(actor.x, actor.y, cand.x, cand.y)
  local cos_theta = 1.0
  if d > 0 then
    local flen = math.sqrt(f.x * f.x + f.y * f.y)
    if flen > 0 then
      cos_theta = (dx * f.x + dy * f.y) / (d * flen)
      if cos_theta > 1.0 then cos_theta = 1.0 end
      if cos_theta < -1.0 then cos_theta = -1.0 end
    end
  end
  if cos_theta < -0.2 and d > 1.0 then
    return nil
  end
  local prio = M.PRIO[cand.kind] or 0
  return d + 2.0 * (1.0 - cos_theta) - prio
end

local function is_valid(cand)
  return cand.enabled ~= false and cand.reachable ~= false
end

--- 从候选列表里挑选最佳焦点目标（含滞回与确定性平局处理）。
function M.pick(actor, cands, opts)
  if not cands or #cands == 0 then return nil end
  opts = opts or {}
  local radius = M.R[opts.mode or "home"] or M.R.home

  local f = actor.face or { x = 1, y = 0 }
  if opts.stick then
    local slen = math.sqrt(opts.stick.x * opts.stick.x + opts.stick.y * opts.stick.y)
    if slen > 0.3 then
      f = opts.stick
    end
  end

  local cur_cand, cur_score = nil, nil
  local best_cand, best_score = nil, nil

  for i = 1, #cands do
    local c = cands[i]
    if is_valid(c) then
      local d = dist(actor.x, actor.y, c.x, c.y)
      if opts.current ~= nil and c.id == opts.current and d <= radius + 0.5 then
        local s = M.score(actor, c, f)
        if s ~= nil then
          cur_cand, cur_score = c, s
        end
      end
      if d <= radius then
        local s = M.score(actor, c, f)
        if s ~= nil then
          if best_cand == nil
            or s < best_score - 1e-9
            or (math.abs(s - best_score) <= 1e-9 and tostring(c.id) < tostring(best_cand.id)) then
            best_cand, best_score = c, s
          end
        end
      end
    end
  end

  if cur_cand ~= nil then
    if best_cand ~= nil and best_score < cur_score - 0.5 then
      return best_cand
    end
    return cur_cand
  end

  return best_cand
end

return M
