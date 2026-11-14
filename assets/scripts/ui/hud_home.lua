-- Home HUD (M4-lite): top bar, party cards, action menu, room temperature labels, station markers.
-- Pure presentation: takes the data tables of game/home_session (hud / actions) and draws them. Hit-test
-- rectangles are exposed so the scene can resolve mouse input.
local i18n = require("core.i18n")
local theme = require("ui.theme")
local widgets = require("ui.widgets")

local M = {}

M.TOP_H = 34
M.CARD_W = 200
M.CARD_H = 82
M.CARD_GAP = 4
M.MENU_W = 330
M.MENU_ROW = 26
M.TAB_W = 150
M.TAB_H = 46
M.TAB_GAP = 4

local NEED_COLORS = {
  hunger = { 0.91, 0.65, 0.24, 1 },
  thirst = { 0.38, 0.66, 0.88, 1 },
  energy = { 0.90, 0.85, 0.35, 1 },
  warmth = { 0.85, 0.40, 0.30, 1 },
}
local NEED_ORDER = { "hunger", "thirst", "energy", "warmth" }

local STATION_COLORS = {
  hearth = { 0.85, 0.45, 0.20 }, woodstove = { 0.80, 0.35, 0.25 }, bed = { 0.40, 0.55, 0.80 },
  electric_heater = { 0.85, 0.75, 0.30 }, generator = { 0.60, 0.60, 0.65 }, humidifier = { 0.45, 0.75, 0.85 },
}

-- ------------------------------------------------------------------ layout (shared with the scene)
function M.card_rect(i)
  return {
    x = 8,
    y = M.TOP_H + 8 + (i - 1) * (M.CARD_H + M.CARD_GAP),
    w = M.CARD_W,
    h = M.CARD_H,
  }
end

function M.card_at(n, mx, my)
  for i = 1, n do
    local r = M.card_rect(i)
    if mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h then return i end
  end
  return nil
end

--- Menu panel + visible item rows. Scrolls so that the focused row stays visible.
function M.menu_layout(menu)
  local sw, sh = ui.screen_size()
  local head = 34
  local foot = 8
  local top = M.TOP_H + 8
  local avail = sh - top - 28 - head - foot - 8
  local rows = math.max(3, math.floor(avail / M.MENU_ROW))
  local n = #menu.items
  local vis = math.min(n, rows)
  local first = 1
  if n > vis then
    first = (menu.focus or 1) - math.floor(vis / 2)
    first = math.max(1, math.min(first, n - vis + 1))
  end
  local panel = { x = sw - M.MENU_W - 8, y = top, w = M.MENU_W, h = head + vis * M.MENU_ROW + foot }
  local list = {}
  for k = 0, vis - 1 do
    local idx = first + k
    list[#list + 1] = {
      index = idx,
      x = panel.x + 6, y = panel.y + head + k * M.MENU_ROW, w = panel.w - 12, h = M.MENU_ROW - 2,
    }
  end
  return panel, list, first, vis
end

function M.menu_item_at(menu, mx, my)
  local _, list = M.menu_layout(menu)
  for _, r in ipairs(list) do
    if mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h then return r.index end
  end
  return nil
end

-- ------------------------------------------------------------------ drawing
local function fmt1(v)
  if type(v) ~= "number" then return "-" end
  return string.format("%.1f", v)
end

local function fmt0(v)
  if type(v) ~= "number" then return "-" end
  return string.format("%d", math.floor(v + 0.5))
end

--- Short human text for an action failure code (home_session reasons / sim errors).
function M.reason_text(code)
  local key = "home.reason." .. tostring(code)
  local txt = i18n.t(key)
  if txt == key then return i18n.t("home.reason.unknown", { code = tostring(code) }) end
  return txt
end

function M.draw_top(h, speed_idx, speeds)
  local sw = ui.screen_size()
  local sf = theme.font("s")
  widgets.panel(0, 0, sw, M.TOP_H, 0.9)
  local speed = speeds and speeds[speed_idx] or 1
  local speed_txt = speed == 0 and i18n.t("home.hud.paused") or i18n.t("home.hud.speed", { n = speed })
  local parts = {
    i18n.t("home.hud.day", { day = h.day }),
    h.clock,
    i18n.t("home.phase." .. tostring(h.phase)),
    i18n.t("home.hud.outdoor", { t = fmt1(h.outdoor_temp) }),
    i18n.t("home.hud.food", { d = fmt1(h.food_days) }),
    i18n.t("home.hud.fuel", { d = fmt1(h.fuel_days) }),
    i18n.t("home.hud.rubble", { p = fmt0(h.rubble) }),
    speed_txt,
  }
  local lh = ui.font_line_height(sf)
  local x = 14
  local y = math.floor((M.TOP_H - lh) / 2)
  for i, p in ipairs(parts) do
    local col = theme.colors.text
    if i == 2 then col = theme.colors.accent end
    if i == 4 then col = theme.colors.cold end
    theme.set_color(col)
    ui.text(sf, p, x, y)
    x = x + ui.text_width(sf, p) + 22
  end
end

local function need_bar_color(key, v)
  if v < 20 then return theme.colors.danger end
  return NEED_COLORS[key] or theme.colors.accent
end

function M.draw_cards(h, selected)
  local sf = theme.font("s")
  for i, c in ipairs(h.chars) do
    local r = M.card_rect(i)
    local sel = c.id == selected
    widgets.panel(r.x, r.y, r.w, r.h, sel and 0.98 or 0.8)
    if sel then
      theme.set_color(theme.colors.accent)
      ui.rect(r.x, r.y, r.w, 2)
      ui.rect(r.x, r.y + r.h - 2, r.w, 2)
      ui.rect(r.x, r.y, 2, r.h)
      ui.rect(r.x + r.w - 2, r.y, 2, r.h)
    end
    widgets.label(sf, i18n.t(tostring(c.name)), r.x + 8, r.y + 4, r.w - 16, theme.colors.text, 0)
    if c.floor then
      widgets.label(sf, i18n.t("home.floor.badge." .. tostring(c.floor)), r.x, r.y + 4, r.w - 8, theme.colors.accent, 2)
    end
    local act = i18n.t("home.activity." .. tostring(c.activity))
    if type(c.job) == "string" and c.job ~= "" then
      act = act .. "  " .. i18n.t("home.job", { job = i18n.t(c.job) })
    end
    widgets.label(sf, widgets.ellipsize(sf, act, r.w - 16), r.x + 8, r.y + 20, r.w - 16, theme.colors.text_dim, 0)
    local k = 0
    for _, key in ipairs(NEED_ORDER) do
      local v = c.needs and c.needs[key]
      if type(v) == "number" then
        local col, row = k % 2, math.floor(k / 2)
        local bw = math.floor((r.w - 20) / 2)
        widgets.progress_bar(
          { x = r.x + 8 + col * (bw + 4), y = r.y + 42 + row * 18, w = bw, h = 16 },
          v, 100,
          { color = need_bar_color(key, v), text = i18n.t("home.need." .. key), text_color = theme.colors.text })
        k = k + 1
      end
    end
  end
end

function M.draw_menu(menu, title)
  local panel, list = M.menu_layout(menu)
  local sf = theme.font("s")
  widgets.panel(panel.x, panel.y, panel.w, panel.h, 0.96)
  widgets.label(sf, title, panel.x + 10, panel.y + 8, panel.w - 20, theme.colors.accent, 0)
  local n = #menu.items
  if n > #list then
    local cnt = string.format("%d/%d", menu.focus or 1, n)
    widgets.label(sf, cnt, panel.x, panel.y + 8, panel.w - 12, theme.colors.text_dim, 2)
  end
  for _, r in ipairs(list) do
    local it = menu.items[r.index]
    local focused = r.index == menu.focus
    if focused then
      theme.set_color(theme.colors.accent, 0.28)
      ui.rect(r.x, r.y, r.w, r.h)
      theme.set_color(theme.colors.accent)
      ui.rect(r.x, r.y, 3, r.h)
    end
    local col = it.enabled and theme.colors.text or theme.colors.disabled
    local label = i18n.t(it.label)
    local ty = r.y + math.floor((r.h - ui.font_line_height(sf)) / 2)
    local reason = ""
    if not it.enabled and it.reason then reason = M.reason_text(it.reason) end
    local rw = reason ~= "" and ui.text_width(sf, reason) or 0
    widgets.label(sf, widgets.ellipsize(sf, label, r.w - 14 - rw - 8), r.x + 8, ty, 0, col, 0)
    if reason ~= "" then
      theme.set_color(theme.colors.disabled)
      ui.text(sf, reason, r.x + r.w - rw - 6, ty)
    end
  end
end

local function project(wx, wz)
  local p = iso.world_to_screen(wx, 0, wz)
  if not p then return nil end
  return p[1], p[2]
end

--- Temperature label above every room. anchors[room_id] = { x, y } tile (room centre-ish).
function M.draw_room_labels(h, anchors, floor)
  local sf = theme.font("s")
  for _, r in ipairs(h.rooms) do
    local a = anchors[r.id]
    if a and type(r.temp) == "number" and (floor == nil or r.floor == floor) then
      local sx, sy = project(a.x + 0.5, a.y - 1.5)
      if sx then
        local txt = i18n.t("home.room." .. r.id) .. "  " .. string.format("%.1f°C", r.temp)
        local tw = ui.text_width(sf, txt)
        local col = r.temp < 0 and theme.colors.cold or (r.temp < 10 and theme.colors.text or theme.colors.ok)
        theme.set_color(theme.colors.bg, 0.75)
        ui.rect(math.floor(sx - tw / 2) - 4, math.floor(sy) - 2, tw + 8, ui.font_line_height(sf) + 4)
        theme.set_color(col)
        ui.text(sf, txt, math.floor(sx - tw / 2), math.floor(sy))
      end
    end
  end
end

--- Placeholder station markers: a coloured block and a name under it. items = list of { tx, ty, kind, on, hp }.
function M.draw_stations(items)
  local sf = theme.font("s")
  for _, it in ipairs(items) do
    local sx, sy = project(it.tx + 0.5, it.ty + 0.5)
    if sx then
      local c = STATION_COLORS[it.kind] or { 0.6, 0.6, 0.6 }
      local alive = it.hp > 0
      local a = alive and 1 or 0.35
      ui.color(0, 0, 0, 0.5 * a)
      ui.rect(math.floor(sx) - 11, math.floor(sy) - 17, 22, 22)
      ui.color(c[1], c[2], c[3], a)
      ui.rect(math.floor(sx) - 9, math.floor(sy) - 19, 18, 18)
      if it.on and alive then
        ui.color(1.0, 0.85, 0.35, 1)
        ui.rect(math.floor(sx) - 4, math.floor(sy) - 14, 8, 8)
      end
      local name = i18n.t("home.station." .. it.kind)
      local tw = ui.text_width(sf, name)
      theme.set_color(alive and theme.colors.text or theme.colors.disabled)
      ui.text(sf, name, math.floor(sx - tw / 2), math.floor(sy) + 6)
    end
  end
end

-- ------------------------------------------------------------------ floor tabs (right edge, top = highest floor)
--- Rect of tab i (1 = top) among n tabs, vertically centred on the right edge.
function M.floor_tab_rect(i, n)
  local sw, sh = ui.screen_size()
  local total = n * M.TAB_H + (n - 1) * M.TAB_GAP
  return {
    x = sw - M.TAB_W - 8,
    y = math.floor((sh - total) / 2) + (i - 1) * (M.TAB_H + M.TAB_GAP),
    w = M.TAB_W, h = M.TAB_H,
  }
end

function M.floor_tab_at(n, mx, my)
  for i = 1, n do
    local r = M.floor_tab_rect(i, n)
    if mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h then return i end
  end
  return nil
end

--- { [floor] = { people, temp } }: people from h.chars[].floor, temp = mean temperature of that floor's rooms.
function M.floor_summary(h, order)
  local out = {}
  for _, f in ipairs(order) do
    local people, sum, n = 0, 0, 0
    for _, c in ipairs(h.chars) do if c.floor == f then people = people + 1 end end
    for _, r in ipairs(h.rooms) do
      if r.floor == f and type(r.temp) == "number" then sum, n = sum + r.temp, n + 1 end
    end
    out[f] = { people = people, temp = n > 0 and sum / n or nil }
  end
  return out
end

--- order = floors bottom -> top; the tabs are drawn top floor first.
function M.draw_floor_tabs(order, current, summary)
  local sf = theme.font("s")
  local n = #order
  for i = 1, n do
    local f = order[n + 1 - i]
    local r = M.floor_tab_rect(i, n)
    local sel = f == current
    widgets.panel(r.x, r.y, r.w, r.h, sel and 0.98 or 0.75)
    if sel then
      theme.set_color(theme.colors.accent)
      ui.rect(r.x, r.y, 3, r.h)
    end
    local info = summary and summary[f] or {}
    widgets.label(sf, i18n.t("home.floor.badge." .. f) .. "  " .. i18n.t("home.floor." .. f),
      r.x + 10, r.y + 4, r.w - 14, sel and theme.colors.accent or theme.colors.text, 0)
    local line = i18n.t("home.hud.floor_people", { n = info.people or 0 })
    if type(info.temp) == "number" then line = line .. "  " .. string.format("%.1f°C", info.temp) end
    widgets.label(sf, line, r.x + 10, r.y + 24, r.w - 14, theme.colors.text_dim, 0)
  end
end

return M
