-- Lighting, fog-of-war, and NPC FOV cone overlay controller.
-- Ambient: ART-AUDIO §3.1 hourly table (data/lights.lua), linear between hours.
-- Light sources: ART-AUDIO §3.3 table. FOV/fog: recomputed at most 10 Hz, on tile change / mark_dirty() (applied at the next allowed tick).
local lights = require("data.lights")

local M = {
  MASK_PLAYER_FOV = 1,
  MASK_EXPLORED = 2,
  MASK_NPC_FOV = 3,
  OVERLAY_NPC_FOV = 3, -- ENGINE-PLAN A1.13: NPC vision cone = overlay group 3
  MIN_INTERVAL = 0.1,  -- 10 Hz cap
  hour = 12.0,
  indoor = false,
  _clock = 0,
  _player = nil, -- { x, y, radius, last_t, tx, ty }
  _npc = nil,    -- { x, y, dx, dy, radius, half, last_t }
  _dirty = false,
  _flicker = {},
  _tinted = {}, -- lights whose colour follows the outdoor ambient (e.g. window): { id, scale }
  recompute_count = 0,
}

local function lerp(a, b, t) return a + (b - a) * t end

--- Ambient colour at a game hour (0..24), outdoor or indoor column.
function M.ambient_at(hour, indoor)
  local tbl = lights.ambient
  local col = indoor and 3 or 2
  local h = hour % 24
  local n = #tbl
  for i = 1, n do
    local a = tbl[i]
    local b = tbl[i + 1]
    local bh = b and b[1] or 24
    if h >= a[1] and h < bh then
      local bc = b and b[col] or tbl[1][col]
      local t = (h - a[1]) / (bh - a[1])
      local ac = a[col]
      return { lerp(ac[1], bc[1], t), lerp(ac[2], bc[2], t), lerp(ac[3], bc[3], t) }
    end
  end
  local c = tbl[1][col]
  return { c[1], c[2], c[3] }
end

--- Name of the day phase for a game hour (HUD label key suffix).
function M.phase_of(hour)
  local h = hour % 24
  if h >= 21 or h < 5 then return "night" end
  if h < 6 then return "dawn" end
  if h >= 19 then return "dusk" end
  return "day"
end

function M.set_time(hour, indoor)
  M.hour = hour % 24
  if indoor ~= nil then M.indoor = indoor == true end
  local c = M.ambient_at(M.hour, M.indoor)
  iso.light_set_ambient(c[1], c[2], c[3])
  -- Ambient-tinted lights (window) follow the slider; they always use the outdoor column.
  local o = M.ambient_at(M.hour, false)
  for _, t in ipairs(M._tinted) do
    iso.light_set_color(t.id, o[1] * t.scale, o[2] * t.scale, o[3] * t.scale)
  end
end

--- Forget all tracked lights (flicker / tinted). Call when the world is cleared (engine lights are gone).
function M.clear_lights()
  M._flicker = {}
  M._tinted = {}
end

function M.init(opts)
  opts = opts or {}
  iso.mask_clear(M.MASK_PLAYER_FOV)
  iso.mask_clear(M.MASK_EXPLORED)
  iso.mask_clear(M.MASK_NPC_FOV)
  iso.overlay_clear(M.OVERLAY_NPC_FOV)
  iso.fog_set(M.MASK_PLAYER_FOV, M.MASK_EXPLORED)
  iso.fog_set_levels(opts.explored_k or 0.36, opts.unknown_k or 0.08)
  M._player, M._npc = nil, nil
  M._dirty = true
  -- Lights added before init() stay tracked (flicker / tinted); use clear_lights() on world clear.
  M.set_time(opts.hour or 12.0, opts.indoor)
end

--- Add a light from the §3.3 table. Returns the engine light id, or nil for unknown names / engine failure (id 0).
function M.add_light(name, x, z, enabled)
  local def = lights.sources[name]
  if not def then return nil end
  local col = def.color
  if not col then
    local a = M.ambient_at(M.hour, false)
    local s = def.ambient_scale or 1
    col = { a[1] * s, a[2] * s, a[3] * s }
  end
  local id = iso.light_add(x, z, def.radius, col[1], col[2], col[3])
  if not id or id == 0 then return nil end
  if not def.color then
    M._tinted[#M._tinted + 1] = { id = id, scale = def.ambient_scale or 1 }
  end
  if def.flicker then
    M._flicker[#M._flicker + 1] = { id = id, base = def.radius, period = def.flicker[1], amp = def.flicker[2] }
  end
  if enabled == false then iso.light_set_enabled(id, false) end
  return id
end

--- Force a recompute of both FOV/fog results on the next tick (door toggled, map changed).
function M.mark_dirty()
  M._dirty = true
end

--- Set the player FOV source. Takes effect in M.tick().
function M.set_player(x, y, radius)
  M._player = M._player or { last_t = -1, tx = nil, ty = nil }
  M._player.x, M._player.y, M._player.radius = x, y, radius or 12
end

--- Set the NPC cone source (tile + facing vector). Takes effect in M.tick().
function M.set_npc(x, y, dx, dy, radius, half_deg)
  M._npc = M._npc or { last_t = -1 }
  local n = M._npc
  n.x, n.y, n.dx, n.dy = x, y, dx, dy
  n.radius, n.half = radius or 8, half_deg or 40
end

local function compute_player(p)
  iso.mask_clear(M.MASK_PLAYER_FOV)
  iso.fov_compute(M.MASK_PLAYER_FOV, p.x, p.y, p.radius, 1, 0, 180)
  iso.mask_or(M.MASK_EXPLORED, M.MASK_PLAYER_FOV)
  M.recompute_count = M.recompute_count + 1
end

local function compute_npc(n, color)
  iso.mask_clear(M.MASK_NPC_FOV)
  iso.fov_compute(M.MASK_NPC_FOV, n.x, n.y, n.radius, n.dx, n.dy, n.half)
  iso.overlay_clear(M.OVERLAY_NPC_FOV)
  local c = color or { 1.0, 0.72, 0.20, 0.34 }
  iso.overlay_add_mask(M.OVERLAY_NPC_FOV, M.MASK_NPC_FOV, c[1], c[2], c[3], c[4])
  M.recompute_count = M.recompute_count + 1
end

--- Per-frame update. Player FOV and NPC cone: recomputed on change or pending mark_dirty(),
--- never faster than 10 Hz (MIN_INTERVAL). Also drives light flicker.
function M.tick(dt)
  M._clock = M._clock + dt
  local now = M._clock
  local p, n = M._player, M._npc
  -- A dirty request stays pending per source until that source is allowed to recompute (>= MIN_INTERVAL).
  if M._dirty then
    if p then p.dirty = true end
    if n then n.dirty = true end
    M._dirty = false
  end
  if p then
    local changed = p.tx ~= p.x or p.ty ~= p.y
    if (changed or p.dirty) and now - p.last_t >= M.MIN_INTERVAL then
      compute_player(p)
      p.tx, p.ty, p.last_t, p.dirty = p.x, p.y, now, false
    end
  end
  if n then
    local changed = n.cx ~= n.x or n.cy ~= n.y or n.cdx ~= n.dx or n.cdy ~= n.dy
    if (changed or n.dirty) and now - n.last_t >= M.MIN_INTERVAL then
      compute_npc(n)
      n.cx, n.cy, n.cdx, n.cdy, n.last_t, n.dirty = n.x, n.y, n.dx, n.dy, now, false
    end
  end

  -- Flicker (§3.3): radius jitter per source period.
  for _, f in ipairs(M._flicker) do
    f.t = (f.t or 0) + dt
    if f.t >= f.period then
      f.t = f.t - f.period
      f.k = ((f.k or 0) * 1103515245 + 12345 + f.id) % 2147483648
      local r = (f.k / 2147483648) * 2 - 1
      iso.light_set_radius(f.id, f.base + r * f.amp)
    end
  end
end

return M
