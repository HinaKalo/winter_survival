-- M1 smoke probe: verifies Title scene, UI rendering, audio, focus audit, Settings modal, and F5 hot reload.
local probe = require("kit_probe")
local audio = require("audio")
local scene = require("core.scene")
local focus = require("ui.focus")

probe.timeout(30)

local now = 0
local function wait(sec)
  local untl = now + sec
  while now < untl do
    coroutine.yield()
  end
end

local function scenario()
  wait(0.5)
  probe.check("lua script running (no Lua error)", probe.script_ok())
  probe.check("ui.quad_count() > 0 on title", ui.quad_count() > 0)
  probe.check("bgm/street_chip is the current BGM", audio.current_bgm() == "bgm/street_chip")
  local audit0 = focus.audit()
  probe.check("title focus.audit().ok", audit0.ok)

  -- Navigate from btn_new_game -> btn_load -> btn_settings and activate
  probe.tap(keys.DOWN)
  wait(0.1)
  probe.tap(keys.DOWN)
  wait(0.1)
  probe.tap(keys.ENTER)
  wait(0.25)

  probe.check("settings modal opened via keyboard", scene.has_modal())
  probe.check("settings ui.quad_count() > 0", ui.quad_count() > 0)
  local audit1 = focus.audit()
  probe.check("settings focus.audit().ok", audit1.ok)

  -- Close settings modal
  probe.tap(keys.ESCAPE)
  wait(0.25)
  probe.check("settings modal closed via ESCAPE", not scene.has_modal())

  -- F5 hot reload keeps script healthy and BGM uninterrupted
  local b0 = audio.stats().bgm_started
  probe.tap(keys.F5)
  wait(0.5)
  probe.check("F5 hot reload keeps script healthy", probe.script_ok())
  probe.check("ui.quad_count() > 0 after F5", ui.quad_count() > 0)
  probe.check("BGM still bgm/street_chip after F5", audio.current_bgm() == "bgm/street_chip")
  probe.check("bgm_started did not increase after F5", audio.stats().bgm_started == b0)

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
