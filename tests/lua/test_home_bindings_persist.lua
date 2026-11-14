-- 验收测试（主代理编写，实现者不得修改；认为有误时提出，由主代理裁定）。docs/M4-PLAN.md 任务 U5。
-- 改键后保存设置，重启（重新 load）后改键仍然生效；旧版本（无 version）绑定被丢弃，其余设置照常读入。
-- 背景：core/save.lua load_settings 只合并 defaults 里非 nil 的键，而 settings.DEFAULTS.bindings = nil，
-- 导致 bindings 从未被读回（P0-3 第 2 轮审查发现）。
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local input = require("core.input")
local save = require("core.save")
local settings = require("ui.settings")

local i18n = require("core.i18n")

local T = {}

-- settings.load() applies everything (hold threshold, language, ...); put the globals back so later
-- suites see the same state as before this file ran.
local function restore()
  sys.save_delete("settings")
  input.reset_all()
  settings.data = nil
  settings.load()
end

function T.rebind_survives_restart()
  local hold, lang = input.HOLD_S, i18n.get_lang()
  local ok, err = pcall(function()
    sys.save_delete("settings")
    input.reset_all()
    settings.load()
    local b = { key = keys.SEMICOLON }
    assert(input.set_binding("keyboard", "open_journal", 1, b))
    assert(settings.save())
    -- "restart": wipe the in-memory state, then load from disk
    input.reset_all()
    settings.data = nil
    local def = input.get_binding("keyboard", "open_journal", 1)
    assert(not (def and def.key == keys.SEMICOLON), "reset_all restored the default")
    settings.load()
    local got = input.get_binding("keyboard", "open_journal", 1)
    assert(got and got.key == keys.SEMICOLON, "saved binding is loaded back after restart")
  end)
  restore()
  input.set_hold_s(hold)
  i18n.set_lang(lang)
  assert(ok, tostring(err))
end

function T.outdated_bindings_dropped_other_settings_kept()
  local hold, lang = input.HOLD_S, i18n.get_lang()
  local ok, err = pcall(function()
    sys.save_delete("settings")
    input.reset_all()
    settings.load()
    local data = {}
    for k, v in pairs(settings.data) do data[k] = v end
    data.lang = "ko"
    local old = input.export_bindings()
    old.version = nil -- pre-P0-3 save
    old.keyboard = old.keyboard or {}
    data.bindings = old
    assert(save.save_settings(data))
    input.reset_all()
    settings.data = nil
    settings.load()
    assert(settings.data.lang == "ko", "other settings still load")
    assert(settings.data.bindings == nil, "outdated bindings are discarded")
  end)
  restore()
  input.set_hold_s(hold)
  i18n.set_lang(lang)
  assert(ok, tostring(err))
end

-- M4-user 审查第 1 轮（Codex P1/P2）：损坏的绑定在导入时被拒绝（返回 false, "invalid"，保留默认），
-- 不会让改键界面在 format_binding 时崩溃，也不会让之后的保存失败。
-- 合法绑定字段：key（数字）、shift/ctrl（布尔）；btn（数字）、lt（布尔）；axis（"ls"|"rs"）、dir（"up"|"down"|"left"|"right"）。
-- 出现其它字段或类型不符 = 非法。
function T.malformed_bindings_are_rejected()
  local serialize = require("core.serialize")
  local ok, err = pcall(function()
    local cyc = { key = keys.J }
    cyc.self = cyc
    local cases = {
      { pad = { open_journal = { { axis = "ls", dir = 42 } } } },
      { pad = { open_journal = { { axis = 7, dir = "up" } } } },
      { pad = { open_journal = { { axis = "ls", dir = "sideways" } } } },
      { keyboard = { open_journal = { { key = "J" } } } },
      { keyboard = { open_journal = { { key = keys.J, shift = "yes" } } } },
      { mouse = { open_journal = { { btn = {} } } } },
      { keyboard = { open_journal = { cyc } } },
    }
    for i, tbl in ipairs(cases) do
      tbl.version = input.BINDINGS_VERSION
      input.reset_all()
      local good, why = input.import_bindings(tbl)
      assert(not good and why == "invalid", "case " .. i .. " rejected, got " .. tostring(good) .. "/" .. tostring(why))
      for _, a in ipairs(input.ACTIONS) do
        for _, dev in ipairs({ "keyboard", "mouse", "pad" }) do
          for _, slot in ipairs(input.slot_ids(a.id, dev)) do
            local b = input.get_binding(dev, a.id, slot)
            if b then
              local fine, e = pcall(input.format_binding, dev, b)
              assert(fine, "case " .. i .. ": format_binding " .. dev .. " " .. a.id .. ": " .. tostring(e))
            end
          end
        end
      end
      local enc = pcall(serialize.encode, input.export_bindings())
      assert(enc, "case " .. i .. ": bindings still serialize after a rejected import")
    end
  end)
  restore()
  assert(ok, tostring(err))
end

return T
