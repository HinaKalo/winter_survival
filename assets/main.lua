-- M1 entry point: UI & core infrastructure bootstrap.
local iso = require("iso")
local i18n = require("core.i18n")
local input = require("core.input")
local scene = require("core.scene")
local theme = require("ui.theme")
local focus = require("ui.focus")
local widgets = require("ui.widgets")
local settings = require("ui.settings")
local log = require("core.log")
local title = require("scenes.title")

local autoquit_after = tonumber(os.getenv("ISO_AUTOQUIT") or "")
-- --scene (sys.launch_opts) wins; WS_SCENE remains the legacy alias through M4.
local start_scene = sys.launch_opts().scene or os.getenv("WS_SCENE") or "title"
local elapsed = 0

function _init()
  i18n.init("zh")
  input.init()
  theme.init()
  settings.load()
  local dev = false
  if sys and sys.launch_opts then -- P0-0 provides sys.launch_opts
    local opts = sys.launch_opts()
    dev = opts ~= nil and opts.dev or false
  end
  input.set_dev(dev)
  if os.getenv("WS_LANG") then i18n.set_lang(os.getenv("WS_LANG")) end -- dev/screenshot override
  if start_scene == "m2_demo" then
    scene.push(require("scenes.m2_demo")) -- dev entry; the title menu never enters the demo
  else
    scene.push(title)
  end
end

-- G-context actions (UI-UX §7.1): reserved keys, handled here so they work in every scene.
local function handle_global_actions()
  if input.pressed("fullscreen") then
    local d = settings.data and settings.data.display
    if d then
      d.fullscreen = not d.fullscreen
      settings.save()
    end
    log.info("fullscreen -> %s", tostring(d and d.fullscreen))
  end
  if input.pressed("screenshot") then
    log.info("screenshot: 未实现（引擎尚无截图接口，留给 M12）")
  end
  if input.pressed("dev_panel") then -- only fires in dev mode (input.set_dev)
    log.info("dev_panel: 未实现")
  end
end

function _update(dt)
  elapsed = elapsed + dt
  if autoquit_after and elapsed >= autoquit_after then
    iso.quit()
  end

  input.update(dt)
  handle_global_actions()
  theme.update(dt)
  widgets.update_toast(dt)
  scene.update(dt)
  focus.update(dt)
end

function _draw()
  focus.begin_frame()
  scene.draw()
  widgets.draw_toast()
end

function _shutdown()
  scene.clear()
end
