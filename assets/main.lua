-- M1 entry point: UI & core infrastructure bootstrap.
local iso = require("iso")
local i18n = require("core.i18n")
local input = require("core.input")
local scene = require("core.scene")
local theme = require("ui.theme")
local focus = require("ui.focus")
local widgets = require("ui.widgets")
local settings = require("ui.settings")
local title = require("scenes.title")

local autoquit_after = tonumber(os.getenv("ISO_AUTOQUIT") or "")
local elapsed = 0

function _init()
  i18n.init("zh")
  input.init()
  theme.init()
  settings.load()
  scene.push(title)
end

function _update(dt)
  elapsed = elapsed + dt
  if autoquit_after and elapsed >= autoquit_after then
    iso.quit()
  end

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
