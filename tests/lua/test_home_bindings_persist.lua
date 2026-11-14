-- 验收测试（主代理编写，实现者不得修改；认为有误时提出，由主代理裁定）。docs/M4-PLAN.md 任务 U5。
-- 改键后保存设置，重启（重新 load）后改键仍然生效；旧版本（无 version）绑定被丢弃，其余设置照常读入。
-- 背景：core/save.lua load_settings 只合并 defaults 里非 nil 的键，而 settings.DEFAULTS.bindings = nil，
-- 导致 bindings 从未被读回（P0-3 第 2 轮审查发现）。
package.path = "assets/scripts/?.lua;assets/?.lua;" .. package.path

local input = require("core.input")
local save = require("core.save")
local settings = require("ui.settings")

local T = {}

local function restore()
  sys.save_delete("settings")
  input.reset_all()
  settings.data = nil
  settings.load()
end

function T.rebind_survives_restart()
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
  assert(ok, tostring(err))
end

function T.outdated_bindings_dropped_other_settings_kept()
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
  assert(ok, tostring(err))
end

return T
