-- Light source table (ART-AUDIO §3.3) and hourly ambient table (ART-AUDIO §3.1).
-- radius in tiles (<= 16); color 0..1; flicker = { period_s, amplitude_in_tiles }.
return {
  sources = {
    stove     = { radius = 7, color = { 1.00, 0.55, 0.22 }, flicker = { 0.15, 0.4 } },
    campfire  = { radius = 8, color = { 1.00, 0.60, 0.26 }, flicker = { 0.15, 0.6 } },
    e_heater  = { radius = 4, color = { 1.00, 0.42, 0.20 } },
    lp_heater = { radius = 4, color = { 0.90, 0.50, 0.30 } },
    lamp      = { radius = 6, color = { 1.00, 0.85, 0.55 } },
    torch     = { radius = 8, color = { 0.85, 0.92, 1.00 } },
    candle    = { radius = 3, color = { 1.00, 0.72, 0.38 }, flicker = { 0.25, 0.3 } },
    street    = { radius = 7, color = { 0.90, 0.88, 0.70 } },
    window    = { radius = 3, color = nil, ambient_scale = 0.6 }, -- ambient colour x 0.6
    radio_led = { radius = 1, color = { 0.20, 0.90, 0.30 } },
  },

  -- { hour, outdoor rgb (0..1), indoor rgb (0..1) }; 24h wraps to the 00:00 row.
  ambient = {
    { 0,  { 0.12, 0.14, 0.24 }, { 14 / 255, 16 / 255, 26 / 255 } },
    { 3,  { 0.13, 0.15, 0.24 }, { 15 / 255, 17 / 255, 27 / 255 } },
    { 5,  { 0.15, 0.18, 0.27 }, { 18 / 255, 22 / 255, 34 / 255 } },
    { 6,  { 0.47, 0.46, 0.50 }, { 70 / 255, 66 / 255, 64 / 255 } },
    { 9,  { 0.77, 0.80, 0.85 }, { 120 / 255, 116 / 255, 108 / 255 } },
    { 12, { 0.89, 0.92, 0.95 }, { 138 / 255, 134 / 255, 124 / 255 } },
    { 16, { 0.80, 0.78, 0.81 }, { 118 / 255, 108 / 255, 98 / 255 } },
    { 19, { 0.50, 0.38, 0.38 }, { 62 / 255, 46 / 255, 40 / 255 } },
    { 21, { 0.20, 0.22, 0.32 }, { 22 / 255, 24 / 255, 34 / 255 } },
  },
}
