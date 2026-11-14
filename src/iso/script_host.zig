//! Lua 宿主：生命周期（_init/_update/_draw/_shutdown）、F5 热重载、错误恢复。
//!
//! Lua 运行时错误只会打印并置 `script_failed = true`（暂停调用 Lua），
//! 按 F5 重载成功后恢复；绝不崩溃，也不调用 showErrorScreen。
const std = @import("std");
const delve = @import("delve");
const debug = delve.debug;
const modules = delve.modules;
const input = delve.platform.input;
const lua_util = delve.scripting.lua;
const manager = delve.scripting.manager;
const lua_api = @import("lua_api.zig");
const engine = @import("engine.zig");

pub var script_failed: bool = false;

/// 额外的 Lua 库绑定钩子（如 kit 的 kit_audio / kit_probe）：在 Lua 启动、`iso` 绑定之后调用。
/// 需在 `delve.app.start` 之前通过 `addBinder` 注册。
const max_binders = 8;
var binders: [max_binders]*const fn (*lua_util.Lua) void = undefined;
var binder_count: usize = 0;

pub fn addBinder(f: *const fn (*lua_util.Lua) void) void {
    if (binder_count >= max_binders) return;
    binders[binder_count] = f;
    binder_count += 1;
}
var main_script: [:0]const u8 = "assets/main.lua";
var did_init: bool = false;

pub fn register(script: [:0]const u8) !void {
    main_script = script;
    try modules.registerModule(.{
        .name = "iso_script_host",
        .priority = -60,
        .init_fn = onInit,
        .start_fn = onStart,
        .stop_fn = onStop,
        .tick_fn = onTick,
        .draw_fn = onDraw,
        .cleanup_fn = onCleanup,
    });
}

fn onInit() !void {
    try debug.registerConsoleCommand("lua", doLuaCommand, "Runs Lua string");
    try manager.init(); // 启动 Lua 并绑定 Delve 自带库
    did_init = true;
    const lua = lua_util.getLua();
    lua_api.bind(lua);
    for (binders[0..binder_count]) |f| f(lua);

    // 脚本搜索路径 + 记录内置模块（热重载时据此清理用户模块缓存）
    runSnippet(
        \\package.path = "assets/?.lua;assets/scripts/?.lua;" .. package.path
        \\__iso_builtin = {}
        \\for k in pairs(package.loaded) do __iso_builtin[k] = true end
    );
}

fn onCleanup() !void {
    if (!did_init) return;
    did_init = false;
    manager.deinit();
}

fn onStart() void {
    loadMainScript();
}

fn onStop() void {
    callGlobal("_shutdown", null);
}

fn onTick(dt: f32) void {
    if (input.isKeyJustPressed(.F5)) {
        reload();
    }
    callGlobal("_update", dt);
}

fn onDraw() void {
    callGlobal("_draw", null);
}

/// 执行一小段内部 Lua 代码，失败只打印
fn runSnippet(code: [:0]const u8) void {
    lua_util.runLine(code) catch {
        debug.err("iso: internal lua snippet failed", .{});
    };
}

/// 运行入口脚本并调用 `_init`
fn loadMainScript() void {
    const lua = lua_util.getLua();
    lua.setTop(0);
    lua.doFile(main_script) catch {
        reportError(lua, "running main script");
        return;
    };
    script_failed = false;
    callGlobal("_init", null);
}

/// F5 热重载
fn reload() void {
    debug.log("iso: hot reload", .{});
    const lua = lua_util.getLua();
    // 失败状态下不再调用旧的 _shutdown
    if (!script_failed) callGlobal("_shutdown", null);

    engine.resetState();
    runSnippet(
        \\_init, _update, _draw, _shutdown = nil, nil, nil, nil
        \\for k in pairs(package.loaded) do
        \\  if not __iso_builtin[k] then package.loaded[k] = nil end
        \\end
    );
    lua.setTop(0);
    script_failed = false;
    loadMainScript();
}

fn reportError(lua: *lua_util.Lua, what: []const u8) void {
    const msg = lua.toString(-1) catch "(no message)";
    debug.err("Lua error while {s}: {s}", .{ what, msg });
    lua.setTop(0);
    script_failed = true;
}

/// 调用 Lua 全局函数；不存在则静默跳过；出错则置 script_failed。
fn callGlobal(name: [:0]const u8, dt: ?f32) void {
    if (script_failed or !did_init) return;
    const lua = lua_util.getLua();
    const top = lua.getTop();
    const t = lua.getGlobal(name) catch {
        lua.setTop(top);
        return;
    };
    if (t != .function) {
        lua.setTop(top);
        return;
    }
    var nargs: i32 = 0;
    if (dt) |d| {
        lua.pushNumber(d);
        nargs = 1;
    }
    lua.protectedCall(.{ .args = nargs }) catch {
        reportError(lua, name);
        return;
    };
    lua.setTop(top);
}

fn doLuaCommand(cmd: [:0]const u8) void {
    if (lua_util.did_init) {
        lua_util.runLine(cmd) catch {};
    } else {
        debug.log("Lua is not yet initialized.", .{});
    }
}
