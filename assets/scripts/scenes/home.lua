-- Home scene (M4-lite): "3 days at home". Builds data/homes/ranch_a as a cutaway iso map, drives game/home_session,
-- shows the HUD, party cards and the interaction menu; dusk / dawn are modal scenes.
-- Frozen fields (tests/probe/home_play.lua): M.session, M.actors (cid -> actor), M.selected (cid),
-- M.menu (nil or { items, focus }).
local scene = require("core.scene")
local i18n = require("core.i18n")
local input = require("core.input")
local hs = require("game.home_session")
local mapbuild = require("view.mapbuild")
local actors = require("view.actors")
local facing = require("view.facing")
local lightfov = require("view.lightfov")
local theme = require("ui.theme")
local widgets = require("ui.widgets")
local hintbar = require("ui.hintbar")
local hud = require("ui.hud_home")

local M = {
  session = nil,
  actors = {},
  selected = nil,
  menu = nil,
}

local PPU = 90.50967
local OUT_KEY = "__out"
local TINTS = {
  { 1.00, 1.00, 1.00 }, { 0.80, 0.90, 1.10 }, { 1.10, 0.90, 0.80 },
  { 0.85, 1.05, 0.85 }, { 1.05, 0.85, 1.05 }, { 1.00, 1.00, 0.80 },
}
local SHEETS = { "assets/sprites/char_marcus.png", "assets/sprites/char_placeholder.png" }

local plan, anchors, zoom, room_of, last_speed, hint_name, ending_shown, dev_shot

local function hints(name)
  if name == "menu" then
    return {
      { action = "ui_up", text = "hint.select_option" },
      { action = "confirm", text = "hint.confirm" },
      { action = "cancel", text = "hint.back" },
    }
  end
  return {
    { action = "select_next", text = "hint.select" },
    { action = "interact", text = "home.hint.act" },
    { action = "pause", text = "hint.pause" },
    { action = "speed_up", text = "home.hint.speed" },
    { action = "end_day", text = "home.hint.end_day", hold = true },
  }
end

local function set_hints(name)
  if hint_name == name then return end
  if hint_name then hintbar.pop() end
  hintbar.push("home_" .. name, hints(name))
  hint_name = name
end

-- ------------------------------------------------------------------ world
local function slot_tile(room, idx)
  local a = anchors[room]
  if not a then return nil end
  return a.x - 1 + (idx % 4), a.y + 1 + math.floor(idx / 4)
end

local function station_tiles()
  local out = {}
  local st = M.session.state.home.stations
  local ids = {}
  for id in pairs(st) do ids[#ids + 1] = id end
  table.sort(ids)
  local used = {}
  for _, id in ipairs(ids) do
    local s = st[id]
    local a = anchors[s.room]
    if a then
      local n = used[s.room] or 0
      used[s.room] = n + 1
      out[#out + 1] = {
        tx = a.x - 2 + (n % 3) * 2, ty = a.y - 1 + math.floor(n / 3) * 2,
        kind = s.kind, on = s.on, hp = s.hp or 0,
      }
    end
  end
  return out
end

local function front_door_tile()
  for _, d in ipairs(plan.doors or {}) do
    if d.outer then
      if iso.map_walkable(d.x, d.y - 1) then return d.x, d.y - 1 end
      return d.x, d.y
    end
  end
  return math.floor(plan.w / 2), math.floor(plan.h / 2)
end

local function fit_zoom()
  local sw = ui.screen_size()
  local avail = sw - hud.CARD_W - 32
  local ext = (plan.w + plan.h) * 0.7071 * PPU
  return math.max(0.3, math.min(1.0, avail / ext))
end

local function build_world()
  iso.camera_set_ppu(PPU)
  iso.camera_set_snap(true)
  lightfov.clear_lights()
  local tmpl = require("data.homes.ranch_a")
  plan = mapbuild.plan(tmpl, { mode = "cutaway" })
  mapbuild.apply(plan, { add_light = function() return nil end })
  anchors = {}
  for id, p in pairs(tmpl.variants.A.rooms) do anchors[id] = { x = p.x, y = p.y } end
  zoom = fit_zoom()
  iso.camera_set_zoom(zoom)
  iso.camera_set_target(plan.w / 2, 0, plan.h / 2)

  M.actors = {}
  room_of = {}
  local s = M.session
  local default = s.state.home.default_room
  for i, cid in ipairs(s.state.party.order) do
    local tx, ty = slot_tile(default, i - 1)
    local a = actors.spawn({
      sheet = SHEETS[((i - 1) % #SHEETS) + 1],
      x = (tx or 10) + 0.5, z = (ty or 4) + 0.5,
      wpx = 64, hpx = 96, speed = 3.0, facing = facing.SE,
    })
    local t = TINTS[((i - 1) % #TINTS) + 1]
    iso.entity_set_tint(a.id, t[1], t[2], t[3], 1.0)
    M.actors[cid] = a
    room_of[cid] = default
  end
end

local function bed_room(state)
  for _, st in pairs(state.home.stations) do
    if st.kind == "bed" then return st.room end
  end
  return "bedroom"
end

local function station_room(state, kind)
  local ids = {}
  for id in pairs(state.home.stations) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local st = state.home.stations[id]
    if st.kind == kind and st.hp > 0 then return st.room end
  end
  return nil
end

local function desired_room(cid)
  local state = M.session.state
  local ch = state.party.chars[cid]
  if not ch or ch.status ~= "alive" then return nil end
  if ch.activity == "out" then return OUT_KEY end
  if ch.activity == "sleep" then return bed_room(state) end
  if ch.job then
    local job = state.jobs and state.jobs[ch.job]
    if job then
      local rec = job.recipe and require("data.recipes").get(job.recipe)
      local r = rec and rec.station and station_room(state, rec.station)
      return r or job.room or ch.room
    end
  end
  return ch.room
end

local function sync_actors(dt)
  for i, cid in ipairs(M.session.state.party.order) do
    local a = M.actors[cid]
    local want = desired_room(cid)
    if want and a and room_of[cid] ~= want then
      local tx, ty
      if want == OUT_KEY then
        tx, ty = front_door_tile()
      else
        tx, ty = slot_tile(want, i - 1)
      end
      if tx then
        actors.move_to_tile(a, tx, ty)
        room_of[cid] = want
      end
    end
    if a then actors.update(a) end
  end
end

-- ------------------------------------------------------------------ selection / menu
local function select_index(i)
  local order = M.session.state.party.order
  if #order == 0 then return end
  i = ((i - 1) % #order) + 1
  if M.selected ~= order[i] then M.menu = nil end
  M.selected = order[i]
end

local function selected_index()
  for i, cid in ipairs(M.session.state.party.order) do
    if cid == M.selected then return i end
  end
  return 1
end

-- The full list holds every recipe / tech; the menu hides craft / research entries that cannot be started now.
local function visible_actions(s, cid)
  local out = {}
  for _, it in ipairs(hs.actions(s, cid)) do
    if it.enabled or (it.kind ~= "craft" and it.kind ~= "research") then out[#out + 1] = it end
  end
  return out
end

local function open_menu()
  local items = visible_actions(M.session, M.selected)
  if #items == 0 then return end
  local focus = 1
  for i, it in ipairs(items) do
    if it.enabled then focus = i; break end
  end
  M.menu = { items = items, focus = focus, cid = M.selected }
end

local function run_menu_item(idx)
  local menu = M.menu
  local it = menu and menu.items[idx]
  if not it then return end
  if not it.enabled then
    widgets.show_toast(i18n.t("home.toast.cannot", { reason = hud.reason_text(it.reason) }), 1.6)
    return
  end
  local ok, err = hs.act(M.session, menu.cid, it.id)
  if ok then
    M.menu = nil
  else
    widgets.show_toast(i18n.t("home.toast.cannot", { reason = hud.reason_text(err) }), 1.6)
    menu.items = visible_actions(M.session, menu.cid)
    menu.focus = math.min(menu.focus, math.max(1, #menu.items))
  end
end

local function move_focus(d)
  local menu = M.menu
  local n = #menu.items
  menu.focus = ((menu.focus - 1 + d) % n) + 1
end

local function handle_menu_input()
  local menu = M.menu
  if input.pressed("cancel") or input.pressed("interact") then
    M.menu = nil
    return
  end
  if input.pressed("ui_up") then move_focus(-1) end
  if input.pressed("ui_down") then move_focus(1) end
  if input.pressed("ui_page_prev") then menu.focus = math.max(1, menu.focus - 8) end
  if input.pressed("ui_page_next") then menu.focus = math.min(#menu.items, menu.focus + 8) end
  if input.pressed("confirm", "keyboard") or input.pressed("confirm", "pad") then
    run_menu_item(menu.focus)
    return
  end
  if input.pressed("confirm", "mouse") then
    local mx, my = ui.mouse_pos()
    local idx = hud.menu_item_at(menu, mx, my)
    if idx then
      menu.focus = idx
      run_menu_item(idx)
    else
      local n = #M.session.state.party.order
      local card = hud.card_at(n, mx, my)
      if card then select_index(card) else
        local panel = hud.menu_layout(menu)
        if not (mx >= panel.x and mx < panel.x + panel.w and my >= panel.y and my < panel.y + panel.h) then
          M.menu = nil
        end
      end
    end
  end
end

-- ------------------------------------------------------------------ modals
local function ensure_modal()
  if scene.has_modal() then return end
  local s = M.session
  if s.mode == "dusk" then
    M.menu = nil
    scene.push_modal(require("scenes.dusk"), { session = s })
  elseif s.mode == "dawn" then
    M.menu = nil
    scene.push_modal(require("scenes.dawn"), { session = s })
  end
end

-- ------------------------------------------------------------------ scene hooks
function M:on_enter(args)
  args = args or {}
  local seed = tonumber(os.getenv("WS_SEED") or "") or os.time()
  M.session = args.session or hs.new(seed)
  M.menu = nil
  hint_name, ending_shown, last_speed = nil, false, 3
  build_world()
  M.selected = M.session.state.party.order[1]
  set_hints("day")
  -- dev / screenshot hook: WS_HOME_SHOT = menu | dusk | dawn
  dev_shot = os.getenv("WS_HOME_SHOT")
  if dev_shot == "dusk" or dev_shot == "dawn" then
    hs.end_day(M.session)
    if dev_shot == "dawn" then hs.confirm_dusk(M.session, {}) end
  elseif dev_shot == "menu" then
    open_menu()
  end
end

function M:on_exit()
  if hint_name then hintbar.pop() end
  hint_name = nil
  M.menu = nil
  iso.world_clear()
  lightfov.clear_lights()
  lightfov.set_time(12.0, false)
end

function M:on_resume()
  -- back from a modal: clocks/animations just continue
end

local function handle_world_input()
  local s = M.session
  if input.pressed("select_next") then select_index(selected_index() + 1) end
  if input.pressed("select_prev") then select_index(selected_index() - 1) end
  for i = 1, 6 do
    if input.pressed("select_" .. i) then select_index(i) end
  end
  if input.pressed("interact") then
    open_menu()
    return
  end
  if input.pressed("confirm", "mouse") then
    local mx, my = ui.mouse_pos()
    local card = hud.card_at(#s.state.party.order, mx, my)
    if card then select_index(card) end
  end
  if input.pressed("pause") then
    if s.speed_idx == 1 then
      hs.set_speed(s, last_speed)
    else
      last_speed = s.speed_idx
      hs.set_speed(s, 1)
    end
  end
  if input.pressed("speed_up") then hs.set_speed(s, math.min(#hs.SPEEDS, s.speed_idx + 1)) end
  if input.pressed("speed_down") then hs.set_speed(s, math.max(1, s.speed_idx - 1)) end
  if input.pressed("camera_zoom_in") then
    zoom = math.min(1.6, zoom * 1.15)
    iso.camera_set_zoom(zoom)
  end
  if input.pressed("camera_zoom_out") then
    zoom = math.max(0.25, zoom / 1.15)
    iso.camera_set_zoom(zoom)
  end
  if input.pressed("end_day") then hs.end_day(s) end
end

function M:update(dt)
  local s = M.session
  if s.mode == "ending" then
    sync_actors(dt)
    if input.pressed("confirm") or input.pressed("cancel") then
      scene.replace(require("scenes.title"))
    end
    return
  end
  if M.menu then
    set_hints("menu")
    handle_menu_input()
  else
    set_hints("day")
    handle_world_input()
    if s.mode == "day" then hs.update(s, dt) end
  end
  if s.mode == "day" then
    local h = s.state.clock.minute / 60
    lightfov.set_time(math.max(8, math.min(17, h)), true)
  end
  sync_actors(dt)
  ensure_modal()
end

local function draw_selection_marker()
  local a = M.actors[M.selected]
  if not a then return end
  local p = actors.pos(a)
  if not p then return end
  local sp = iso.world_to_screen(p[1], 0, p[3])
  if not sp then return end
  local sx, sy = math.floor(sp[1]), math.floor(sp[2])
  local r = math.floor(30 * zoom + 8)
  theme.set_color(theme.colors.accent, 0.9)
  ui.rect(sx - 6, sy - r - 4, 12, 3)
  ui.rect(sx - 3, sy - r - 1, 6, 3)
  ui.rect(sx - 1, sy - r + 2, 2, 3)
end

local function draw_ending()
  local sw, sh = ui.screen_size()
  widgets.modal_dim()
  local pw, ph = math.min(560, sw - 40), 220
  local px, py = math.floor((sw - pw) / 2), math.floor((sh - ph) / 2)
  widgets.panel(px, py, pw, ph, 0.97)
  widgets.label(theme.font("t"), i18n.t("home.ending.title"), px, py + 24, pw, theme.colors.accent, 1)
  widgets.label(theme.font("b"), i18n.t("home.ending.body", { day = M.session.state.clock.day }),
    px + 24, py + 80, pw - 48, theme.colors.text, 1)
  widgets.label(theme.font("s"), i18n.t("home.ending.hint"), px, py + ph - 36, pw, theme.colors.text_dim, 1)
end

function M:draw()
  local s = M.session
  if not s then return end
  local h = hs.hud(s)
  hud.draw_room_labels(h, anchors)
  hud.draw_stations(station_tiles())
  draw_selection_marker()
  hud.draw_top(h, s.speed_idx, hs.SPEEDS)
  hud.draw_cards(h, M.selected)
  if M.menu then
    local name = M.selected
    for _, c in ipairs(h.chars) do
      if c.id == M.selected then name = i18n.t(c.name) end
    end
    hud.draw_menu(M.menu, i18n.t("home.menu.title", { name = name }))
  end
  if s.mode == "ending" then draw_ending() end
  hintbar.draw()
end

return M
