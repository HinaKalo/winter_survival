-- Health: hidden hp, three wound bands, diseases, treatment, death (CONTENT §6.4).
local balance = require("data.balance")
local items = require("data.items")
local inventory = require("sim.inventory")
local rng = require("core.rng")
local util = require("core.util")
local chars = require("sim.chars")
local state_mod = require("sim.state")

local M = {}

local H = balance.health

local function hours(minutes) return minutes / 60 end

function M.add_wound(state, ch, amount, cause)
  if not ch or ch.status ~= "alive" or amount <= 0 then return end
  ch.health.hp = math.max(0, ch.health.hp - amount)
  state_mod.log(state, "wound", { char = ch.id, amount = amount, cause = cause or "unknown" })
  if ch.health.hp <= 0 then
    chars.kill(state, ch.id, cause or "wound")
  end
end

function M.heal(state, ch, amount)
  if not ch or ch.status ~= "alive" then return end
  ch.health.hp = math.min(H.max_hp, ch.health.hp + amount)
end

function M.add_disease(state, ch, id)
  if not ch or ch.status ~= "alive" then return end
  if ch.health.disease[id] then return false end
  local def
  if id == "cold" then
    def = { kind = "cold", hours = H.cold.hours, med = false, no_pneumonia = 0, low_temp_hours = 0 }
  elseif id == "pneumonia" then
    def = { kind = "pneumonia", days = H.pneumonia.days, doses = 0 }
  elseif id == "frostbite" then
    def = { kind = "frostbite", hours = H.frostbite.days * 24, treated = false, cap_hours = 0 }
  elseif id == "food_poison" then
    def = { kind = "food_poison", hours = H.food_poison.hours, cured = false }
  else
    return false, "unknown_disease"
  end
  def.id = id
  ch.health.disease[id] = def
  state_mod.log(state, "disease", { char = ch.id, disease = id })
  return true
end

function M.remove_disease(state, ch, id)
  if ch and ch.health.disease[id] then
    ch.health.disease[id] = nil
    return true
  end
  return false
end

-- Per-tick probabilities (tick of `minutes` minutes), exposed for tests and balance.
-- Frostbite: only outdoors (CONTENT 6.2.3 / PLAN 9.1); per hour 15%, +10% when E < -20.
function M.frostbite_chance(state, ch, minutes)
  if ch.activity ~= "out" then return 0 end
  local h = hours(minutes)
  local E = require("sim.thermal").effective_temp(state, ch)
  local p = H.frostbite.per_hour * h
  if E < H.frostbite.outdoor_e then p = p + H.frostbite.outdoor_extra_per_hour * h end
  return p
end

-- Infection of a heavy wound: per_day * h / 24 per tick (antiseptic halves it).
function M.infection_chance(ch, minutes)
  local p = H.infection_chance_per_day * hours(minutes) / 24
  if ch.health.antiseptic_hours and ch.health.antiseptic_hours > 0 then
    p = p * H.antiseptic_infection_mult
  end
  return p
end

-- Health tick of `minutes` minutes (sim.lua uses 5): healing, bleeding, disease timers, cold/frostbite rolls.
function M.tick(state, minutes)
  minutes = minutes or 1
  local h = hours(minutes)
  local thermal = require("sim.thermal")
  for _, ch in ipairs(chars.alive(state)) do
    local health = ch.health
    local wound = chars.wound(ch)
    local rest = ch.activity == "sleep" or ch.activity == "idle"

    -- natural healing / critical bleeding
    if wound == "healthy" then
      if ch.needs.food > 30 and ch.needs.water > 30 and rest then
        health.hp = math.min(H.max_hp, health.hp + H.heal.healthy * h)
      end
    elseif wound == "light" then
      local rate = H.heal.light
      if health.bandage_hours > 0 then rate = rate * H.bandage_light_mult end
      health.hp = math.min(H.max_hp, health.hp + rate * h)
    elseif wound == "heavy" then
      local rate = H.heal.heavy
      if health.heavy_bandage_hours > 0 then rate = rate + H.bandage_heavy_bonus end
      health.hp = math.min(H.max_hp, health.hp + rate * h)
    elseif wound == "critical" then
      if health.stabilized_until and health.stabilized_until > state.clock.day * 1440 + state.clock.minute then
        health.hp = math.min(H.max_hp, health.hp + H.critical_stabilized_heal * h)
      else
        health.hp = math.max(0, health.hp + H.heal.critical * h)
      end
    end

    if health.bandage_hours > 0 then health.bandage_hours = math.max(0, health.bandage_hours - h) end
    if health.heavy_bandage_hours > 0 then health.heavy_bandage_hours = math.max(0, health.heavy_bandage_hours - h) end
    if health.painkiller_until and health.painkiller_until > 0 then
      health.painkiller_until = math.max(0, health.painkiller_until - minutes)
    end

    -- hypothermia damage
    if ch.needs.temp < balance.thermal.bands.hypothermia then
      health.hp = math.max(0, health.hp - balance.thermal.hypothermia_hp_per_hour * h)
      if ch.needs.temp <= balance.thermal.bands.dying then
        health.critical_hours = (health.critical_hours or 0) + h
        if health.critical_hours >= H.dying_cap_hours then
          health.hp = math.min(health.hp, H.dying_cap_hp)
        end
      end
    else
      health.critical_hours = 0
    end

    -- disease timers
    for _, id in ipairs(util.sorted_keys(health.disease)) do
      local d = health.disease[id]
      if id == "cold" then
        d.hours = d.hours - h
        if d.hours <= 0 then health.disease[id] = nil end
        if d.no_pneumonia and d.no_pneumonia > 0 then d.no_pneumonia = math.max(0, d.no_pneumonia - h) end
      elseif id == "pneumonia" then
        d.days = d.days - h / 24
        health.hp = math.max(0, health.hp - H.pneumonia.hp_per_day * h / 24)
        if d.days <= 0 then health.disease[id] = nil end
      elseif id == "frostbite" then
        d.hours = d.hours - h
        if not d.treated then
          d.cap_hours = (d.cap_hours or 0) + h
          if d.cap_hours >= H.frostbite.cap_hours then
            health.hp = math.min(health.hp, H.frostbite.cap_hp)
          end
        end
        if d.hours <= 0 then health.disease[id] = nil end
      elseif id == "food_poison" then
        d.hours = d.hours - h
        if d.hours <= 0 then health.disease[id] = nil end
      end
    end

    -- frostbite: body temp < trigger for >= 30 min, outdoors only
    if ch.needs.temp < H.frostbite.trigger_temp then
      health.frost_hours = (health.frost_hours or 0) + h
    else
      health.frost_hours = 0
    end
    if health.frost_hours >= H.frostbite.trigger_minutes / 60 then
      local p = M.frostbite_chance(state, ch, minutes)
      if p > 0 and rng.float(state.rng.health) < p then
        M.add_disease(state, ch, "frostbite")
      end
    end

    -- infection of heavy wounds
    if wound == "heavy" and not health.infection then
      if rng.float(state.rng.health) < M.infection_chance(ch, minutes) then
        health.infection = true
        state_mod.log(state, "infection", { char = ch.id })
      end
    end
    if health.antiseptic_hours and health.antiseptic_hours > 0 then
      health.antiseptic_hours = math.max(0, health.antiseptic_hours - h)
    end

    if health.hp <= 0 then
      chars.kill(state, ch.id, "health")
    end
  end
end

-- Daily disease rolls: cold and pneumonia (called at 06:00).
function M.daily(state)
  local home = state.home
  local H2 = balance.health
  -- contagion is per room (CONTENT 6.4.2: +1%/h per sick person in the SAME room)
  local sick_in_room = {}
  for _, ch in ipairs(chars.alive(state)) do
    if ch.health.disease.cold and ch.activity ~= "out" then
      sick_in_room[ch.room] = (sick_in_room[ch.room] or 0) + 1
    end
  end
  for _, ch in ipairs(chars.alive(state)) do
    -- cold
    if not ch.health.disease.cold then
      local f_dry = 1 + math.max(0, H2.cold.dry_ref - home.humidity) / H2.cold.dry_scale
      local f_wet = 1
      local room_t = require("sim.thermal").room_temp(state, ch.room)
      if home.humidity > H2.cold.wet_ref and room_t < H2.cold.wet_room then
        f_wet = 1 + (home.humidity - H2.cold.wet_ref) / H2.cold.wet_scale
      end
      local f_cold = 1
      if ch.needs.temp < H2.cold.cold_temp then f_cold = H2.cold.f_cold_body end
      if ch.activity == "sleep" and room_t < H2.cold.cold_room then f_cold = f_cold * H2.cold.f_cold_sleep end
      local trait = (ch.traits.illness_risk or 1)
      local p_day = (H2.cold.base_per_hour * 24) * f_dry * f_wet * f_cold * trait
        + (ch.activity ~= "out" and sick_in_room[ch.room] or 0) * H2.cold.spread_per_sick_per_hour * 24
      if rng.float(state.rng.health) < p_day then
        M.add_disease(state, ch, "cold")
      end
    end
    -- pneumonia roll for cold patients
    local cold = ch.health.disease.cold
    if cold and not ch.health.disease.pneumonia and (cold.no_pneumonia or 0) <= 0 then
      local p = H2.pneumonia.base_per_day
      if ch.needs.temp < H2.pneumonia_low_body_temp then p = p + H2.pneumonia.low_temp_bonus end
      if home.humidity < H2.pneumonia.dry_humidity then p = p + H2.pneumonia.dry_bonus end
      p = math.min(H2.pneumonia.cap, p)
      if rng.float(state.rng.health) < p then
        M.add_disease(state, ch, "pneumonia")
      end
    end
    -- infection progress
    if ch.health.infection == true then
      M.add_wound(state, ch, H.infection_daily_damage, "infection")
    end
  end
end

function M.treat(state, patient, actor, item_id)
  local def = items.get(item_id)
  if not def or not items.has_tag(item_id, "med_any") and not (item_id == "first_aid_kit") then
    return false, "not_medicine"
  end
  local src = state.home.stash
  if inventory.count(src, item_id) <= 0 then
    src = actor.inv
    if inventory.count(src, item_id) <= 0 then return false, "missing" end
  end
  local elena = actor.traits.treat and actor.traits.treat > 1
  local wound = chars.wound(patient)
  local ok = false

  local frost = patient.health.disease.frostbite
  local frost_open = frost ~= nil and not frost.treated
  local warm_room = require("sim.thermal").room_temp(state, patient.room) >= H.frostbite.treat_room_temp
  if item_id == "bandage" and frost_open and wound ~= "critical" and wound ~= "heavy"
    and (warm_room or wound == "healthy") then
    -- frostbite (CONTENT 6.4.2): room >= 12 C + one bandage; stops the 72 h hp cap
    if not warm_room then return false, "too_cold" end
    inventory.remove(src, item_id, 1)
    frost.treated = true
    frost.cap_hours = 0
    ok = true
  elseif item_id == "bandage" then
    if wound == "critical" then
      inventory.remove(src, item_id, 1)
      patient.health.stabilized_until = state.clock.day * 1440 + state.clock.minute + H.stabilize_minutes
      patient.needs.temp = math.max(patient.needs.temp, H.stabilize_body_temp)
      ok = true
    elseif wound == "heavy" then
      local need = elena and 1 or 2
      if inventory.count(src, item_id) >= need then
        inventory.remove(src, item_id, need)
        patient.health.heavy_bandage_hours = H.heavy_bandage_hours
        ok = true
      end
    elseif wound == "light" then
      inventory.remove(src, item_id, 1)
      patient.health.bandage_hours = H.bandage_hours
      ok = true
    else
      return false, "not_injured"
    end
  elseif item_id == "antibiotics" then
    local disease = patient.health.disease.pneumonia
    if not disease then return false, "no_pneumonia" end
    -- at most one dose per day (CONTENT 6.4.2)
    local today = state.clock.day
    if disease.last_dose_day == today then return false, "dose_today" end
    inventory.remove(src, item_id, 1)
    disease.last_dose_day = today
    disease.doses = (disease.doses or 0) + 1
    local need = elena and H.pneumonia.elena_doses or H.pneumonia.doses
    if disease.doses >= need then patient.health.disease.pneumonia = nil end
    ok = true
  elseif item_id == "cold_medicine" then
    local cold = patient.health.disease.cold
    if not cold then return false, "no_cold" end
    inventory.remove(src, item_id, 1)
    cold.hours = math.min(cold.hours, H.cold.med_hours)
    cold.no_pneumonia = H.cold_medicine_no_pneumonia_hours
    ok = true
  elseif item_id == "painkillers" then
    if wound == "healthy" then return false, "not_injured" end
    inventory.remove(src, item_id, 1)
    patient.health.painkiller_until = H.painkiller_minutes
    ok = true
  elseif item_id == "antiseptic" then
    inventory.remove(src, item_id, 1)
    patient.health.antiseptic_hours = H.antiseptic_hours
    patient.health.infection = false
    local frost = patient.health.disease.frostbite
    if frost then
      frost.treated = true
      frost.hours = math.min(frost.hours, H.frostbite.med_days * 24)
      frost.cap_hours = 0
    end
    ok = true
  elseif item_id == "first_aid_kit" then
    inventory.remove(src, item_id, 1)
    if wound == "critical" then
      patient.health.stabilized_until = state.clock.day * 1440 + state.clock.minute + H.first_aid_stabilize_minutes
    end
    patient.health.bandage_hours = H.bandage_hours
    patient.health.heavy_bandage_hours = H.heavy_bandage_hours
    patient.health.painkiller_until = H.painkiller_minutes
    patient.health.infection = false
    ok = true
  else
    return false, "unsupported"
  end

  if ok then
    state_mod.log(state, "treat", { patient = patient.id, actor = actor.id, item = item_id })
  end
  return ok
end

return M
