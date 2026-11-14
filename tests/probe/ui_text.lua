-- M1 UI & trilingual text probe (zh/en/ko + large text + quad budget + focus audit).
local probe = require("kit_probe")
local i18n = require("core.i18n")
local scene = require("core.scene")
local focus = require("ui.focus")
local settings = require("ui.settings")

probe.timeout(20)

local now = 0
local function wait(sec)
  local untl = now + sec
  while now < untl do
    coroutine.yield()
  end
end

local function scenario()
  wait(0.3)
  scene.push_modal(settings)
  wait(0.2)
  probe.check("settings modal active", scene.has_modal())

  local langs = { "zh", "en", "ko" }
  for _, lang in ipairs(langs) do
    settings.data.lang = lang
    settings.apply(settings.data)
    wait(0.2)
    local qc = ui.quad_count()
    local audit = focus.audit()
    probe.check("lang " .. lang .. " active", i18n.get_lang() == lang)
    probe.check("lang " .. lang .. " quad_count in (0, 6000)", qc > 0 and qc < 6000)
    probe.check("lang " .. lang .. " focus.audit().ok", audit.ok)
  end

  -- Large text mode
  settings.data.accessibility.large_text = true
  settings.apply(settings.data)
  wait(0.2)
  local qc_lg = ui.quad_count()
  probe.check("large_text quad_count in (0, 6000)", qc_lg > 0 and qc_lg < 6000)
  probe.check("large_text focus.audit().ok", focus.audit().ok)

  -- Restore default language without polluting saves
  settings.data.lang = "zh"
  settings.data.accessibility.large_text = false
  settings.apply(settings.data)
  scene.pop_modal()
  wait(0.1)
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
