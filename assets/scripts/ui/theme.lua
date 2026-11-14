-- UI visual tokens, font handles, skin atlas regions, and formatting helpers (UI-UX §1.2, §1.3).
local M = {
  large_text = false,
  high_contrast = false,
  reduce_flash = false,
  scale_mode = "auto", -- "auto" | "1x" | "2x" | "3x"
  skin = 0,
  fonts = {},
  _blink_t = 0,
}

M.colors = {
  bg       = { 0x1B / 255, 0x1F / 255, 0x24 / 255, 0.88 },
  bg_hi    = { 0x26 / 255, 0x2C / 255, 0x33 / 255, 0.92 },
  bg_dark  = { 0x12 / 255, 0x15 / 255, 0x19 / 255, 0.95 },
  edge     = { 0x3A / 255, 0x42 / 255, 0x4A / 255, 1.00 },
  text     = { 0xE8 / 255, 0xEC / 255, 0xEF / 255, 1.00 },
  text_dim = { 0x9A / 255, 0xA4 / 255, 0xAD / 255, 1.00 },
  accent   = { 0xE8 / 255, 0xA6 / 255, 0x3C / 255, 1.00 },
  danger   = { 0xD8 / 255, 0x45 / 255, 0x3A / 255, 1.00 },
  ok       = { 0x7F / 255, 0xAE / 255, 0x6A / 255, 1.00 },
  cold     = { 0x8F / 255, 0xC3 / 255, 0xE0 / 255, 1.00 },
  disabled = { 0x5B / 255, 0x64 / 255, 0x6C / 255, 1.00 },
  white    = { 1, 1, 1, 1 },
}

M.skin_rects = {
  panel        = { 0, 0, 48, 48, 12, 12, 12, 12 },
  btn_normal   = { 48, 0, 32, 32, 8, 8, 8, 8 },
  btn_hover    = { 48, 32, 32, 32, 8, 8, 8, 8 },
  btn_pressed  = { 48, 64, 32, 32, 8, 8, 8, 8 },
  btn_disabled = { 48, 96, 32, 32, 8, 8, 8, 8 },
  tab_normal   = { 80, 0, 24, 40, 8, 8, 8, 0 },
  tab_active   = { 80, 40, 24, 40, 8, 8, 8, 0 },
  slider_track = { 0, 48, 24, 8, 4, 0, 4, 0 },
  slider_thumb = { 0, 56, 16, 24, 2, 2, 2, 2 },
  tip          = { 0, 80, 16, 16, 4, 4, 4, 4 },
  row          = { 16, 80, 16, 40, 4, 4, 4, 4 },
}

function M.init()
  if M.skin == 0 then
    M.skin = ui.image_load("assets/ui/skin.png")
  end
  local sizes = { 14, 16, 18, 20, 24, 30 }
  for _, px in ipairs(sizes) do
    if not M.fonts[px] or M.fonts[px] == 0 then
      local name = "assets/fonts/ui_" .. tostring(px)
      M.fonts[px] = ui.font_load(name .. ".png", name .. ".fnt")
    end
  end
end

function M.font(kind)
  if M.large_text then
    if kind == "s" then return M.fonts[18] or 0 end
    if kind == "t" then return M.fonts[30] or 0 end
    return M.fonts[20] or 0
  else
    if kind == "s" then return M.fonts[14] or 0 end
    if kind == "t" then return M.fonts[24] or 0 end
    return M.fonts[16] or 0
  end
end

function M.set_color(c, alpha_mul)
  local a = (c[4] or 1) * (alpha_mul or 1)
  ui.color(c[1], c[2], c[3], a)
end

function M.nine(key, x, y, w, h, c, alpha_mul)
  local r = M.skin_rects[key]
  if not r or M.skin == 0 then
    M.set_color(c or M.colors.bg, alpha_mul)
    ui.rect(x, y, w, h)
    return
  end
  M.set_color(c or M.colors.white, alpha_mul)
  ui.nine_slice(M.skin, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], x, y, w, h)
end

function M.apply_scale()
  if M.scale_mode == "1x" then
    ui.set_scale(1)
  elseif M.scale_mode == "2x" then
    ui.set_scale(2)
  elseif M.scale_mode == "3x" then
    ui.set_scale(3)
  else
    ui.set_scale(1)
    local _, h = ui.screen_size()
    local n = math.max(1, math.floor((h or 720) / 720))
    ui.set_scale(n)
  end
end

function M.update(dt)
  M._blink_t = M._blink_t + dt
end

return M
