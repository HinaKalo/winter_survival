-- Settings modal panel (UI-UX §2.3).
local i18n = require("core.i18n")
local input = require("core.input")
local save = require("core.save")
local scene = require("core.scene")
local util = require("core.util")
local theme = require("ui.theme")
local focus = require("ui.focus")
local widgets = require("ui.widgets")
local rebind = require("ui.rebind")

local M = {
  DEFAULTS = {
    lang = "zh",
    audio = { master = 0.8, bgm = 0.7, amb = 0.7, sfx = 0.8, ui = 0.8 },
    display = { fullscreen = false, scale = "auto", vsync = true, shake = 1.0, flash = true },
    input_km = { one_button = false, edge_scroll = true, sensitivity = 1.0 },
    input_pad = { deadzone = 0.24, trigger = 0.50, cursor_speed = 1.0, auto_focus = true },
    accessibility = {
      large_text = false,
      colorblind = "off",
      hold_confirm = false,
      hold_duration = 0.8,
      reduce_flash = false,
      high_contrast = false,
    },
    game = { soft_narration = false, auto_pause = true, tutorials = true },
    bindings = nil,
  },
  data = nil,
  tab_idx = 1,
  confirm_reset = false,
}

local TABS = {
  "lang", "audio", "display", "input_km", "input_pad", "rebind", "accessibility", "game"
}

function M.apply(s)
  M.data = s
  i18n.set_lang(s.lang)
  theme.large_text = s.accessibility.large_text
  theme.reduce_flash = s.accessibility.reduce_flash
  theme.high_contrast = s.accessibility.high_contrast
  theme.scale_mode = s.display.scale
  theme.apply_scale()

  if kit_audio then
    kit_audio.set_bus("master", s.audio.master)
    kit_audio.set_bus("bgm", s.audio.bgm)
    kit_audio.set_bus("amb", s.audio.amb)
    kit_audio.set_bus("sfx", s.audio.sfx)
  end
  if pad and pad.set_tuning then
    pad.set_tuning(s.input_pad.deadzone, 0.12, s.input_pad.trigger, math.max(0.1, s.input_pad.trigger - 0.1))
  end
  if s.bindings then
    input.import_bindings(s.bindings)
  end
end

function M.load()
  local loaded = save.load_settings(M.DEFAULTS)
  M.apply(loaded)
  return M.data
end

function M.save()
  if not M.data then return false end
  M.data.bindings = input.export_bindings()
  return save.save_settings(M.data)
end

function M:on_enter(args)
  if not M.data then M.load() end
  M.tab_idx = (args and args.tab) or 1
  M.confirm_reset = false
  rebind.init()
  focus.push_group("settings", {
    modal = true,
    default = "set_lang",
    on_cancel = function()
      if M.confirm_reset then
        M.confirm_reset = false
        return
      end
      if rebind.is_modal_active() then return end
      M.save()
      scene.pop_modal()
    end,
  })
end

function M:on_exit()
  focus.pop_group()
end

function M:update(dt)
  if M.tab_idx == 6 and rebind.update(dt) then
    return
  end
  if not M.confirm_reset then
    if input.pressed("ui_tab_prev") then
      M.tab_idx = ((M.tab_idx - 2) % #TABS) + 1
      kit_audio.sfx("sfx/ui", 0.6, 1.0)
    elseif input.pressed("ui_tab_next") then
      M.tab_idx = (M.tab_idx % #TABS) + 1
      kit_audio.sfx("sfx/ui", 0.6, 1.0)
    end
  end
end

local function idx_of(list, val)
  for i, v in ipairs(list) do
    if v.val == val then return i end
  end
  return 1
end

function M:draw()
  if not M.data then M.load() end
  local s = M.data
  focus.set_target("settings")
  widgets.modal_dim()

  local sw, sh = ui.screen_size()
  local pw = math.min(1040, sw - 64)
  local ph = math.min(620, sh - 64)
  local px = math.floor((sw - pw) * 0.5)
  local py = math.floor((sh - ph) * 0.5)

  widgets.panel(px, py, pw, ph, 0.96)

  -- Title
  widgets.label(theme.font("t"), i18n.t("settings.title"), px + 24, py + 16, pw - 48, theme.colors.text, 0)

  -- Left tab list
  local tab_w = 200
  local tab_x = px + 20
  local tab_y = py + 64
  for i, key in ipairs(TABS) do
    local tr = { x = tab_x, y = tab_y + (i - 1) * 44, w = tab_w, h = 40 }
    local active = (i == M.tab_idx)
    widgets.button("set_tab_" .. key, tr, i18n.t("settings.tab." .. key), {
      variant = active and "primary" or nil,
      sub_group = "tabs",
      align = 0,
      on_click = function() M.tab_idx = i end,
    })
  end

  -- Content panel area
  local cx = tab_x + tab_w + 20
  local cy = tab_y
  local cw = pw - tab_w - 60
  local ch = ph - 144
  theme.set_color(theme.colors.bg_dark, 0.7)
  ui.rect(cx - 8, cy - 8, cw + 16, ch + 16)

  local tab = TABS[M.tab_idx]
  local ry = cy

  if tab == "lang" then
    local opts = {
      { val = "zh", label = i18n.t("settings.lang.zh") },
      { val = "en", label = i18n.t("settings.lang.en") },
      { val = "ko", label = i18n.t("settings.lang.ko") },
    }
    widgets.cycle("set_lang", { x = cx, y = ry, w = cw, h = 44 },
      i18n.t("settings.lang"), opts, idx_of(opts, s.lang), {
        sub_group = "content",
        on_change = function(_, opt)
          s.lang = opt.val
          M.apply(s)
        end,
      })
  elseif tab == "audio" then
    local items = {
      { key = "master", lbl = "settings.audio.master" },
      { key = "bgm",    lbl = "settings.audio.bgm" },
      { key = "amb",    lbl = "settings.audio.amb" },
      { key = "sfx",    lbl = "settings.audio.sfx" },
      { key = "ui",     lbl = "settings.audio.ui" },
    }
    for i, it in ipairs(items) do
      widgets.slider("set_aud_" .. it.key, { x = cx, y = ry + (i - 1) * 48, w = cw, h = 44 },
        i18n.t(it.lbl), s.audio[it.key], 0, 1, 0.05, {
          sub_group = "content",
          on_change = function(nv)
            s.audio[it.key] = nv
            M.apply(s)
          end,
        })
    end
  elseif tab == "display" then
    widgets.toggle("set_disp_fs", { x = cx, y = ry, w = cw, h = 44 },
      i18n.t("settings.display.fullscreen"), s.display.fullscreen, {
        sub_group = "content",
        on_change = function(v) s.display.fullscreen = v end,
      })
    local sc_opts = {
      { val = "auto", label = i18n.t("settings.display.scale.auto") },
      { val = "1x",   label = i18n.t("settings.display.scale.1x") },
      { val = "2x",   label = i18n.t("settings.display.scale.2x") },
      { val = "3x",   label = i18n.t("settings.display.scale.3x") },
    }
    widgets.cycle("set_disp_sc", { x = cx, y = ry + 48, w = cw, h = 44 },
      i18n.t("settings.display.scale"), sc_opts, idx_of(sc_opts, s.display.scale), {
        sub_group = "content",
        on_change = function(_, opt)
          s.display.scale = opt.val
          M.apply(s)
        end,
      })
    widgets.toggle("set_disp_vs", { x = cx, y = ry + 96, w = cw, h = 44 },
      i18n.t("settings.display.vsync"), s.display.vsync, {
        sub_group = "content",
        on_change = function(v) s.display.vsync = v end,
      })
    widgets.slider("set_disp_shk", { x = cx, y = ry + 144, w = cw, h = 44 },
      i18n.t("settings.display.shake"), s.display.shake, 0, 1, 0.05, {
        sub_group = "content",
        on_change = function(nv) s.display.shake = nv end,
      })
    widgets.toggle("set_disp_fl", { x = cx, y = ry + 192, w = cw, h = 44 },
      i18n.t("settings.display.flash"), s.display.flash, {
        sub_group = "content",
        on_change = function(v) s.display.flash = v end,
      })
  elseif tab == "input_km" then
    widgets.toggle("set_km_1b", { x = cx, y = ry, w = cw, h = 44 },
      i18n.t("settings.km.one_button"), s.input_km.one_button, {
        sub_group = "content",
        on_change = function(v) s.input_km.one_button = v end,
      })
    widgets.toggle("set_km_edge", { x = cx, y = ry + 48, w = cw, h = 44 },
      i18n.t("settings.km.edge_scroll"), s.input_km.edge_scroll, {
        sub_group = "content",
        on_change = function(v) s.input_km.edge_scroll = v end,
      })
    widgets.slider("set_km_sens", { x = cx, y = ry + 96, w = cw, h = 44 },
      i18n.t("settings.km.sensitivity"), s.input_km.sensitivity, 0.5, 2.0, 0.1, {
        sub_group = "content",
        format = function(v) return string.format("%.1f×", v) end,
        on_change = function(nv) s.input_km.sensitivity = nv end,
      })
    widgets.button("set_km_rb", { x = cx, y = ry + 156, w = 240, h = 40 }, i18n.t("settings.km.open_rebind"), {
      sub_group = "content",
      on_click = function() M.tab_idx = 6 end,
    })
  elseif tab == "input_pad" then
    widgets.slider("set_pad_dz", { x = cx, y = ry, w = cw, h = 44 },
      i18n.t("settings.pad.deadzone"), s.input_pad.deadzone, 0.10, 0.45, 0.02, {
        sub_group = "content",
        format = function(v) return string.format("%.2f", v) end,
        on_change = function(nv) s.input_pad.deadzone = nv; M.apply(s) end,
      })
    widgets.slider("set_pad_trig", { x = cx, y = ry + 48, w = cw, h = 44 },
      i18n.t("settings.pad.trigger"), s.input_pad.trigger, 0.25, 0.85, 0.05, {
        sub_group = "content",
        format = function(v) return string.format("%.2f", v) end,
        on_change = function(nv) s.input_pad.trigger = nv; M.apply(s) end,
      })
    widgets.slider("set_pad_spd", { x = cx, y = ry + 96, w = cw, h = 44 },
      i18n.t("settings.pad.cursor_speed"), s.input_pad.cursor_speed, 0.5, 2.0, 0.1, {
        sub_group = "content",
        format = function(v) return string.format("%.1f×", v) end,
        on_change = function(nv) s.input_pad.cursor_speed = nv end,
      })
    widgets.toggle("set_pad_af", { x = cx, y = ry + 144, w = cw, h = 44 },
      i18n.t("settings.pad.auto_focus"), s.input_pad.auto_focus, {
        sub_group = "content",
        on_change = function(v) s.input_pad.auto_focus = v end,
      })
    local status_str = pad.connected() and i18n.t("settings.pad.connected", { name = pad.name() })
      or i18n.t("settings.pad.disconnected")
    widgets.label(theme.font("s"), status_str, cx + 8, ry + 204, cw - 16, theme.colors.text_dim, 0)
  elseif tab == "rebind" then
    rebind.draw({ x = cx, y = cy, w = cw, h = ch })
  elseif tab == "accessibility" then
    local ts_opts = {
      { val = false, label = i18n.t("settings.acc.text_size.standard") },
      { val = true,  label = i18n.t("settings.acc.text_size.large") },
    }
    widgets.cycle("set_acc_ts", { x = cx, y = ry, w = cw, h = 44 },
      i18n.t("settings.acc.text_size"), ts_opts, s.accessibility.large_text and 2 or 1, {
        sub_group = "content",
        on_change = function(_, opt) s.accessibility.large_text = opt.val; M.apply(s) end,
      })

    local cb_opts = {
      { val = "off", label = i18n.t("settings.acc.colorblind.off") },
      { val = "rg",  label = i18n.t("settings.acc.colorblind.rg") },
      { val = "by",  label = i18n.t("settings.acc.colorblind.by") },
    }
    widgets.cycle("set_acc_cb", { x = cx, y = ry + 48, w = cw, h = 44 },
      i18n.t("settings.acc.colorblind"), cb_opts, idx_of(cb_opts, s.accessibility.colorblind), {
        sub_group = "content",
        on_change = function(_, opt) s.accessibility.colorblind = opt.val end,
      })

    widgets.toggle("set_acc_hc", { x = cx, y = ry + 96, w = cw, h = 44 },
      i18n.t("settings.acc.hold_confirm"), s.accessibility.hold_confirm, {
        sub_group = "content",
        on_change = function(v) s.accessibility.hold_confirm = v end,
      })
    widgets.slider("set_acc_hd", { x = cx, y = ry + 144, w = cw, h = 44 },
      i18n.t("settings.acc.hold_duration"), s.accessibility.hold_duration, 0.4, 1.5, 0.1, {
        sub_group = "content",
        format = function(v) return string.format("%.1fs", v) end,
        on_change = function(nv) s.accessibility.hold_duration = nv end,
      })
    widgets.toggle("set_acc_rf", { x = cx, y = ry + 192, w = cw, h = 44 },
      i18n.t("settings.acc.reduce_flash"), s.accessibility.reduce_flash, {
        sub_group = "content",
        on_change = function(v) s.accessibility.reduce_flash = v; M.apply(s) end,
      })

    widgets.toggle("set_acc_hcf", { x = cx, y = ry + 240, w = cw, h = 44 },
      i18n.t("settings.acc.high_contrast"), s.accessibility.high_contrast, {
        sub_group = "content",
        on_change = function(v) s.accessibility.high_contrast = v; M.apply(s) end,
      })
  elseif tab == "game" then
    widgets.toggle("set_gm_sn", { x = cx, y = ry, w = cw, h = 44 },
      i18n.t("settings.game.soft_narration"), s.game.soft_narration, {
        sub_group = "content",
        on_change = function(v) s.game.soft_narration = v end,
      })
    widgets.toggle("set_gm_ap", { x = cx, y = ry + 48, w = cw, h = 44 },
      i18n.t("settings.game.auto_pause"), s.game.auto_pause, {
        sub_group = "content",
        on_change = function(v) s.game.auto_pause = v end,
      })
    widgets.toggle("set_gm_tut", { x = cx, y = ry + 96, w = cw, h = 44 },
      i18n.t("settings.game.tutorials"), s.game.tutorials, {
        sub_group = "content",
        on_change = function(v) s.game.tutorials = v end,
      })
  end

  -- Bottom bar: Reset Defaults & Back
  local by = py + ph - 60
  widgets.button("set_reset", { x = px + 20, y = by, w = 200, h = 44 }, i18n.t("ui.reset_default"), {
    variant = "danger",
    sub_group = "bottom",
    on_click = function() M.confirm_reset = true end,
  })
  widgets.button("set_back", { x = px + pw - 180, y = by, w = 160, h = 44 }, i18n.t("ui.back"), {
    variant = "primary",
    sub_group = "bottom",
    on_click = function()
      M.save()
      scene.pop_modal()
    end,
  })

  -- Confirm reset modal
  if M.confirm_reset then
    widgets.modal_dim()
    local mw, mh = 480, 170
    local mx, my = math.floor((sw - mw) * 0.5), math.floor((sh - mh) * 0.5)
    widgets.panel(mx, my, mw, mh, 0.98)
    widgets.label(theme.font("b"), i18n.t("settings.reset_confirm"), mx + 24, my + 28, mw - 48, theme.colors.text, 0)
    widgets.button("set_rst_cancel", { x = mx + mw - 280, y = my + 110, w = 120, h = 40 }, i18n.t("ui.cancel"), {
      on_click = function() M.confirm_reset = false end,
    })
    widgets.button("set_rst_ok", { x = mx + mw - 144, y = my + 110, w = 120, h = 40 }, i18n.t("ui.confirm"), {
      variant = "danger",
      on_click = function()
        input.reset_all()
        M.apply(util.deep_copy(M.DEFAULTS))
        M.save()
        M.confirm_reset = false
      end,
    })
  end
  focus.clear_target()
end

return M
