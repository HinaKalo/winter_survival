-- M1 input parity probe: keyboard-only, mouse-only, and gamepad-only flows
-- Title -> Settings -> change language -> Rebind tab -> Back (save settings.sav).
local probe = require("kit_probe")
local i18n = require("core.i18n")
local scene = require("core.scene")
local theme = require("ui.theme")
local settings = require("ui.settings")

probe.timeout(30)

local now = 0
local function wait(sec)
  local untl = now + sec
  while now < untl do
    coroutine.yield()
  end
end

local function pad_tap(btn)
  probe.pad_button(btn, true)
  wait(0.06)
  probe.pad_button(btn, false)
  wait(0.08)
end

local function mouse_click(x, y)
  probe.mouse_move(x, y)
  wait(0.05)
  probe.click(0)
  wait(0.08)
end

local function scenario()
  sys.save_delete("settings")
  settings.load()
  wait(0.3)

  -- === 1. KEYBOARD-ONLY ===
  probe.tap(keys.DOWN) -- -> btn_load
  wait(0.08)
  probe.tap(keys.DOWN) -- -> btn_settings
  wait(0.08)
  probe.tap(keys.ENTER)
  wait(0.2)
  probe.check("[kb] settings modal opened", scene.has_modal())

  -- set_lang is default-focused; ENTER cycles zh -> en
  probe.tap(keys.ENTER)
  wait(0.12)
  probe.check("[kb] language switched to en", i18n.get_lang() == "en")

  -- Switch to Rebind tab (tab 6: lang=1 -> +5)
  for _ = 1, 5 do
    probe.tap(keys.RIGHT_BRACKET)
    wait(0.06)
  end
  probe.check("[kb] switched to rebind tab", settings.tab_idx == 6)

  -- Close Settings (auto-saves)
  probe.tap(keys.ESCAPE)
  wait(0.2)
  probe.check("[kb] settings modal closed", not scene.has_modal())
  local raw1 = sys.save_read("settings")
  probe.check("[kb] settings.sav persisted en", raw1 ~= nil and raw1:find('lang = "en"') ~= nil)

  -- === 2. MOUSE-ONLY ===
  local sw, sh = ui.screen_size()
  local u = 1
  local btn_h = math.floor(36 * u)
  local gap = math.floor(10 * u)
  local pad = math.floor(20 * u)
  local panel_y = math.floor(sh * 0.36)
  local settings_y = panel_y + pad + 3 * (btn_h + gap) + math.floor(btn_h * 0.5)

  mouse_click(math.floor(sw * 0.5), settings_y)
  wait(0.2)
  probe.check("[mouse] settings modal opened", scene.has_modal())

  local pw = math.min(1040, sw - 64)
  local ph = math.min(620, sh - 64)
  local px = math.floor((sw - pw) * 0.5)
  local py = math.floor((sh - ph) * 0.5)
  local tab_x = px + 20
  local tab_y = py + 64

  -- Click Language tab (tab 1)
  mouse_click(tab_x + 100, tab_y + 20)
  wait(0.1)
  probe.check("[mouse] switched to lang tab", settings.tab_idx == 1)

  -- Click set_lang right side to cycle en -> ko
  local cx = tab_x + 220
  local cw = pw - 260
  mouse_click(cx + cw - 20, tab_y + 22)
  wait(0.12)
  probe.check("[mouse] language switched to ko", i18n.get_lang() == "ko")

  -- Click Rebind tab (tab 6)
  mouse_click(tab_x + 100, tab_y + 5 * 44 + 20)
  wait(0.1)
  probe.check("[mouse] switched to rebind tab", settings.tab_idx == 6)

  -- Click Back button (saves)
  mouse_click(px + pw - 100, py + ph - 38)
  wait(0.2)
  probe.check("[mouse] settings modal closed", not scene.has_modal())
  local raw2 = sys.save_read("settings")
  probe.check("[mouse] settings.sav persisted ko", raw2 ~= nil and raw2:find('lang = "ko"') ~= nil)

  -- === 3. GAMEPAD-ONLY ===
  -- Title focus was last on btn_settings (or move down to it if needed; click didn't move focus away from btn_settings)
  pad_tap(pad_buttons.a)
  wait(0.2)
  probe.check("[pad] settings modal opened", scene.has_modal())

  -- Already on lang tab (tab 1) with set_lang default-focused
  probe.check("[pad] on lang tab", settings.tab_idx == 1)

  -- Cycle set_lang ko -> zh
  pad_tap(pad_buttons.a)
  wait(0.12)
  probe.check("[pad] language switched to zh", i18n.get_lang() == "zh")

  -- Switch to Rebind tab via RB x 5
  for _ = 1, 5 do
    pad_tap(pad_buttons.rb)
  end
  probe.check("[pad] switched to rebind tab", settings.tab_idx == 6)

  -- Close Settings via B (saves)
  pad_tap(pad_buttons.b)
  wait(0.2)
  probe.check("[pad] settings modal closed", not scene.has_modal())
  local raw3 = sys.save_read("settings")
  probe.check("[pad] settings.sav persisted zh", raw3 ~= nil and raw3:find('lang = "zh"') ~= nil)

  probe.finish()
end

local co = coroutine.create(scenario)

function _probe(t, dt)
  now = t
  if coroutine.status(co) == "dead" then
    return
  end
  local ok, err = coroutine.resume(co)
  if not ok then
    error(err, 0)
  end
end
