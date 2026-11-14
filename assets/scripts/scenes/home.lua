-- Home scene (M4-lite): "3 days at home". Builds data/homes/ranch_a as a cutaway iso map, drives game/home_session,
-- shows the HUD, party cards and the interaction menu; dusk / dawn are modal scenes.
-- Frozen fields (tests/probe/home_play.lua): M.session, M.actors (cid -> actor), M.selected (cid),
-- M.menu (nil or { items, focus }).
-- M5-3D (tests/probe/home_floors.lua): three floors drawn from the baked model assets/models/ranch_a.wsm.
-- M.view_floor ("B1" | "F1" | "F2"), M.model (iso model id), M.actor_floor (cid -> floor). The logical map holds only the
-- viewed floor; people on other floors are ghost entities moved in a straight line from Lua.
local scene = require("core.scene")
local i18n = require("core.i18n")
local input = require("core.input")
local hs = require("game.home_session")
local mapbuild = require("view.mapbuild")
local actors = require("view.actors")
local facing = require("view.facing")
local lightfov = require("view.lightfov")
local floors = require("game.floors")
local home3d = require("view.home3d")
local theme = require("ui.theme")
local widgets = require("ui.widgets")
local hintbar = require("ui.hintbar")
local hud = require("ui.hud_home")

local M = {
  session = nil,
  actors = {},
  selected = nil,
  menu = nil,
  view_floor = "F1",
  model = nil,
  actor_floor = {},
}

local MODEL_PATH = "assets/models/ranch_a.wsm"
local WALK_SPEED = 3.0

local PPU = 90.50967
local OUT_KEY = "__out"
local TINTS = {
  { 1.00, 1.00, 1.00 }, { 0.80, 0.90, 1.10 }, { 1.10, 0.90, 0.80 },
  { 0.85, 1.05, 0.85 }, { 1.05, 0.85, 1.05 }, { 1.00, 1.00, 0.80 },
}
local SHEETS = { "assets/sprites/char_marcus.png", "assets/sprites/char_placeholder.png" }

local plan, anchors, zoom, room_of, last_speed, hint_name, ending_shown, dev_shot
local map_state, trips, model_names, model_sig, tmpl_cache

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
    { action = "floor_up", text = "home.hint.floor" },
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
-- Anchor of a room. Rooms built during play (cold cell) have no template anchor: they borrow their host's (the
-- default room on its floor), shifted to its own corner so slots stay walkable and apart from the host's people.
-- Returns anchor, borrowed.
local function anchor_of(room)
  local a = anchors[room]
  if a then return a, false end
  local st = M.session and M.session.state
  local rm = st and st.home.rooms[room]
  if not rm then return nil end
  for _, l in ipairs(rm.links or {}) do
    if anchors[l.room] then return anchors[l.room], true end
  end
  local def = anchors[st.home.default_room]
  if def then return def, true end
  return nil
end

local function slot_tile(room, idx)
  local a, borrowed = anchor_of(room)
  if not a then return nil end
  if borrowed then return a.x + 3 + (idx % 3), a.y - 1 + math.floor(idx / 3) end
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
    local rm = M.session.state.home.rooms[s.room]
    if a and rm and (rm.floor or "F1") == M.view_floor then
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

-- The front door of the main floor: the tile just inside (north of) the outer door, from the template grid.
local function front_door_tile_f1()
  local grid = tmpl_cache.variants.A.grid
  for y = 1, #grid do
    for x = 1, #grid[y] do
      if grid[y]:sub(x, x) == "D" then return x - 1, y - 2 end
    end
  end
  return math.floor(#grid[1] / 2), math.floor(#grid / 2)
end

local function fit_zoom()
  local sw = ui.screen_size()
  local avail = sw - hud.CARD_W - 32
  local ext = (plan.w + plan.h) * 0.7071 * PPU
  return math.max(0.3, math.min(1.0, avail / ext))
end

local function util_sorted(t)
  local ids = {}
  for id in pairs(t) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end

local function despawn_map_entities()
  if not map_state then return end
  for _, d in pairs(map_state.doors_by_key or {}) do
    if d.entity_id then iso.entity_despawn(d.entity_id) end
  end
  for _, id in ipairs(map_state.prop_ids or {}) do iso.entity_despawn(id) end
  map_state = nil
end

-- Logical map of one floor (walk / light / view only; the baked model is what is drawn).
local function build_floor_map(floor, first)
  despawn_map_entities()
  plan = mapbuild.plan(tmpl_cache, { mode = "cutaway", level = floor })
  map_state = mapbuild.apply(plan, { add_light = function() return nil end, keep_world = not first })
  -- the model has its own doors and props: no billboard sprites for them
  for _, d in pairs(map_state.doors_by_key or {}) do
    if d.entity_id then iso.entity_set_visible(d.entity_id, false) end
  end
  for _, id in ipairs(map_state.prop_ids or {}) do iso.entity_set_visible(id, false) end
  if M.model then iso.map_set_draw_tiles(false) end
end

local function nearest_walkable(x, z)
  local cx, cz = math.floor(x), math.floor(z)
  for r = 0, 8 do
    for dx = -r, r do
      for dz = -r, r do
        if math.max(math.abs(dx), math.abs(dz)) == r and iso.map_walkable(cx + dx, cz + dz) then
          return cx + dx + 0.5, cz + dz + 0.5
        end
      end
    end
  end
  return x, z
end

local function actor_pos(a)
  local p = iso.entity_get_pos(a.id)
  if p then return p[1], p[3] end
  return 0, 0
end

local function put_actor(a, x, z)
  iso.entity_stop(a.id)
  local p = iso.entity_get_pos(a.id)
  iso.entity_set_pos(a.id, x, p and p[2] or 0, z)
end

-- Entities of the viewed floor are normal; everyone else is a ghost (x-ray outline).
local function apply_actor_floor(cid, snap)
  local a = M.actors[cid]
  if not a then return end
  local ghost = M.actor_floor[cid] ~= M.view_floor
  iso.entity_set_ghost(a.id, ghost)
  if not ghost and snap then
    local x, z = actor_pos(a)
    if not iso.map_walkable(math.floor(x), math.floor(z)) then
      x, z = nearest_walkable(x, z)
      put_actor(a, x, z)
    end
  end
  if ghost then iso.entity_stop(a.id) end
  local t = trips[cid]
  if t then t.pathed = nil end
end

local function sync_model(force)
  if not M.model then return end
  local state = M.session.state
  local parts = { M.view_floor, tostring(state.home.rubble or 0) }
  for _, id in ipairs(util_sorted(state.home.stations)) do
    local st = state.home.stations[id]
    if st.kind == "woodstove" or st.kind == "hearth" then
      parts[#parts + 1] = id .. (st.on and st.hp > 0 and "1" or "0")
    end
  end
  local sig = table.concat(parts, "|")
  if not force and sig == model_sig then return end
  model_sig = sig
  local vis = home3d.visibility(model_names, M.view_floor, state)
  for _, n in ipairs(model_names) do
    if iso.model_node_visible(M.model, n) ~= vis[n] then iso.model_set_visible(M.model, n, vis[n]) end
  end
end

local function set_view(floor)
  if not floor or (map_state and floor == M.view_floor) then return end
  M.view_floor = floor
  M.menu = nil
  build_floor_map(floor, false)
  if M.model then iso.model_set_offset(M.model, 0, -floors.BASE_Y[floor], 0) end
  for _, cid in ipairs(M.session.state.party.order) do apply_actor_floor(cid, true) end
  sync_model(true)
end

local function build_world()
  iso.camera_set_ppu(PPU)
  iso.camera_set_snap(true)
  lightfov.clear_lights()
  tmpl_cache = require("data.homes.ranch_a")
  local va = tmpl_cache.variants.A
  anchors = {}
  for id, p in pairs(va.rooms) do anchors[id] = { x = p.x, y = p.y } end
  for _, lv in pairs(va.levels or {}) do
    for id, p in pairs(lv.rooms or {}) do anchors[id] = { x = p.x, y = p.y } end
  end

  M.model, model_names, model_sig = nil, {}, nil
  if iso.model_load then
    M.model = iso.model_load(MODEL_PATH)
    if M.model then model_names = iso.model_nodes(M.model) or {} end
  end
  M.view_floor = "F1"
  map_state, trips = nil, {}
  build_floor_map("F1", true)
  zoom = fit_zoom()
  iso.camera_set_zoom(zoom)
  iso.camera_set_target(plan.w / 2, 0, plan.h / 2)

  M.actors = {}
  M.actor_floor = {}
  room_of = {}
  local s = M.session
  local default = s.state.home.default_room
  for i, cid in ipairs(s.state.party.order) do
    local tx, ty = slot_tile(default, i - 1)
    local a = actors.spawn({
      sheet = SHEETS[((i - 1) % #SHEETS) + 1],
      x = (tx or 10) + 0.5, z = (ty or 4) + 0.5,
      wpx = 64, hpx = 96, speed = WALK_SPEED, facing = facing.SE,
    })
    local t = TINTS[((i - 1) % #TINTS) + 1]
    iso.entity_set_tint(a.id, t[1], t[2], t[3], 1.0)
    M.actors[cid] = a
    M.actor_floor[cid] = "F1"
    room_of[cid] = default
  end
  if M.model then
    iso.model_set_offset(M.model, 0, -floors.BASE_Y.F1, 0)
    sync_model(true)
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

-- Where an actor goes for room `want`: target floor and tile (nil tile = no anchor).
local function trip_target(want, i)
  if want == OUT_KEY then
    local f = "F1"
    local x, y = front_door_tile_f1()
    return f, x, y
  end
  local f = floors.of_room(M.session.state, want) or "F1"
  local tx, ty = slot_tile(want, i - 1)
  return f, tx, ty
end

-- One step of an actor's trip: walk (viewed floor, pathfinding) or glide (other floors) to the goal; take the stairs
-- when the goal is on another floor.
local function step_trip(cid, a, dt)
  local trip = trips[cid]
  if not trip then return end
  local af = M.actor_floor[cid]
  local gx, gy, stair = trip.tx, trip.ty, nil
  if af ~= trip.floor then
    stair = floors.route(tmpl_cache, af, trip.floor)[1]
    if stair then
      gx, gy = stair.from_cell[1], stair.from_cell[2]
    else
      -- no route (should not happen): jump
      M.actor_floor[cid] = trip.floor
      apply_actor_floor(cid, true)
      return
    end
  end
  local arrived = false
  if af == M.view_floor then
    if trip.pathed ~= gx .. "," .. gy .. af then
      if actors.move_to_tile(a, gx, gy) then
        trip.pathed = gx .. "," .. gy .. af
        trip.wait = 3
      else
        put_actor(a, gx + 0.5, gy + 0.5)
        arrived = true
      end
    elseif trip.wait and trip.wait > 0 then
      trip.wait = trip.wait - 1
    elseif not iso.entity_is_moving(a.id) then
      arrived = true
    end
  else
    local x, z = actor_pos(a)
    local dx, dz = gx + 0.5 - x, gy + 0.5 - z
    local dist = math.sqrt(dx * dx + dz * dz)
    local step = WALK_SPEED * (dt or 0)
    if dist <= step or dist < 0.05 then
      put_actor(a, gx + 0.5, gy + 0.5)
      arrived = true
    else
      local p = iso.entity_get_pos(a.id)
      iso.entity_set_pos(a.id, x + dx / dist * step, p and p[2] or 0, z + dz / dist * step)
    end
  end
  if arrived then
    if stair then
      M.actor_floor[cid] = stair.to
      put_actor(a, stair.to_cell[1] + 0.5, stair.to_cell[2] + 0.5)
      apply_actor_floor(cid, false)
      trip.pathed = nil
    else
      trips[cid] = nil
    end
  end
end

local function sync_actors(dt)
  for i, cid in ipairs(M.session.state.party.order) do
    local a = M.actors[cid]
    local want = desired_room(cid)
    if want and a and room_of[cid] ~= want then
      local f, tx, ty = trip_target(want, i)
      if not tx then
        -- never drop a move: fall back to the floor's default-room anchor, then the home's
        local st = M.session.state
        local def = st.home.default_room
        local df = floors.of_room(st, def) or "F1"
        local a = anchors[def]
        if f ~= df then
          local best
          for id in pairs(anchors) do
            if floors.of_room(st, id) == f and (not best or id < best) then best = id end
          end
          a = best and anchors[best] or a
        end
        a = a or anchors[def]
        if a then tx, ty = a.x - 1 + ((i - 1) % 4), a.y + 1 end
      end
      if tx then
        trips[cid] = { floor = f, tx = tx, ty = ty }
        room_of[cid] = want
      end
    end
    if a then
      step_trip(cid, a, dt)
      actors.update(a)
    end
  end
end

-- ------------------------------------------------------------------ selection / menu
local function select_index(i)
  local order = M.session.state.party.order
  if #order == 0 then return end
  i = ((i - 1) % #order) + 1
  if M.selected ~= order[i] then M.menu = nil end
  M.selected = order[i]
  local f = M.actor_floor[M.selected]
  if f and f ~= M.view_floor then set_view(f) end
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
  -- dev / screenshot hooks (M5-3D): WS_HOME_SPLIT=1 sends the 2nd / 3rd character to B1 / 2F rooms;
  -- WS_HOME_FLOOR = B1 | F1 | F2 picks the viewed floor.
  if os.getenv("WS_HOME_SPLIT") == "1" then
    local order = M.session.state.party.order
    if order[2] then hs.act(M.session, order[2], "move:shelter") end
    if order[3] then hs.act(M.session, order[3], "move:attic_bed") end
  end
  local f = os.getenv("WS_HOME_FLOOR")
  if f == "B1" or f == "F1" or f == "F2" then set_view(f) end
end

function M:on_exit()
  if hint_name then hintbar.pop() end
  hint_name = nil
  M.menu = nil
  if M.model then
    iso.model_unload(M.model)
    M.model = nil
  end
  if iso.map_set_draw_tiles then iso.map_set_draw_tiles(true) end
  map_state = nil
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
  if input.pressed("floor_up") then set_view(floors.step(M.view_floor, 1)) end
  if input.pressed("floor_down") then set_view(floors.step(M.view_floor, -1)) end
  if input.pressed("confirm", "mouse") then
    local mx, my = ui.mouse_pos()
    local card = hud.card_at(#s.state.party.order, mx, my)
    if card then
      select_index(card)
    else
      local tab = hud.floor_tab_at(#floors.ORDER, mx, my)
      if tab then set_view(floors.ORDER[#floors.ORDER + 1 - tab]) end
    end
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
  sync_model(false)
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
  for _, c in ipairs(h.chars) do c.floor = M.actor_floor[c.id] or c.floor end
  hud.draw_room_labels(h, anchors, M.view_floor)
  hud.draw_stations(station_tiles())
  draw_selection_marker()
  hud.draw_top(h, s.speed_idx, hs.SPEEDS)
  hud.draw_cards(h, M.selected)
  hud.draw_floor_tabs(floors.ORDER, M.view_floor, hud.floor_summary(h, floors.ORDER))
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
