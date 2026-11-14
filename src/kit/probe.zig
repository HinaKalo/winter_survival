//! 模块 `kit_probe`（优先级 -80）+ Lua 原始库 `kit_probe`：由 Lua 脚本驱动的 headless CI 探针。
//!
//! 先于 iso_world(-70) 和脚本宿主(-60) 运行，所以注入的输入在同一帧对游戏 `_update` 可见。
//! 探针文件在第一次 tick 时（主脚本此时已加载）载入同一个 Lua 状态，必须定义全局
//! `_probe(t, dt)`，之后每个 tick 调用一次（t = 自启动起的游戏时间，秒）。
//!
//! 注意：binder 会把本文件里所有 `pub fn` 绑定为 Lua 函数；非 Lua 的公开函数在 `ignore_fns` 里列出。
const std = @import("std");
const delve = @import("delve");
const iso = @import("iso");
const input = delve.platform.input;
const papp = delve.platform.app;
const binder = delve.scripting.binder;
const lua_util = delve.scripting.lua;
const modules = delve.modules;
const gamepad = @import("gamepad.zig");
const pad_logic = @import("pad_logic.zig");

const Reg = binder.Registry(.{ .entries = &[_]binder.BoundType{} });
const ignore_fns = [_][:0]const u8{ "bind", "register", "result", "startWatchdog", "stopWatchdog" };

pub const Config = struct {
    script: [:0]const u8,
};

pub const ProbeFailed = error{ProbeFailed};

const default_timeout_s: f64 = 60.0;
const max_taps = 16;

var script_path: [:0]const u8 = "";
var active: bool = false;
var loaded: bool = false;
var finished: bool = false;
var t: f64 = 0;
var timeout_s: f64 = default_timeout_s;
// checks/failures 由看门狗线程读取，故用原子量
var checks = std.atomic.Value(u32).init(0);
var failures = std.atomic.Value(u32).init(0);
var taps: [max_taps]i32 = undefined;
var tap_n: usize = 0;

pub fn register(cfg: Config) !void {
    script_path = cfg.script;
    active = true;
    gamepad.setAllowHardware(false);
    try modules.registerModule(.{
        .name = "kit_probe",
        .priority = -80,
        .tick_fn = onTick,
    });
}

/// 由 Lua 宿主在 Lua 启动后调用
pub fn bind(lua: *lua_util.Lua) void {
    const fns = comptime Reg.findLibraryFunctions(@This(), &ignore_fns);
    Reg.bindLibrary(lua, "kit_probe", fns);
}

/// `app.start` 返回后由 main 调用：打印 `PROBE SUMMARY`，失败或没有任何检查时返回错误。
pub fn result() ProbeFailed!void {
    if (!active) return;
    if (!finished) {
        record("probe ended before finish()", false);
    }
    const c = checks.load(.monotonic);
    const f = failures.load(.monotonic);
    std.debug.print("PROBE SUMMARY {d}/{d} passed\n", .{ c - f, c });
    if (f > 0 or c == 0) return error.ProbeFailed;
}

// ------------------------------------------------------------------ 模块

fn record(name: []const u8, ok: bool) void {
    _ = checks.fetchAdd(1, .monotonic);
    if (!ok) _ = failures.fetchAdd(1, .monotonic);
    std.debug.print("PROBE {s} {s}\n", .{ if (ok) "PASS" else "FAIL", name });
}

fn finishNow() void {
    if (finished) return;
    finished = true;
    wd_armed.store(false, .release);
    const c = checks.load(.monotonic);
    std.debug.print("PROBE done: {d}/{d} checks passed after {d:.2}s\n", .{ c - failures.load(.monotonic), c, t });
    papp.exit();
}

fn scriptError(lua: *lua_util.Lua, what: []const u8) void {
    const msg = lua.toString(-1) catch "(no message)";
    var buf: [512]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "probe script error: {s}: {s}", .{ what, msg }) catch "probe script error";
    record(text, false);
    lua.setTop(0);
    finishNow();
}

fn releaseTaps() void {
    for (taps[0..tap_n]) |code| input.onKeyUp(code);
    tap_n = 0;
}

fn loadProbe(lua: *lua_util.Lua) void {
    loaded = true;
    lua.setTop(0);
    lua.doFile(script_path) catch {
        scriptError(lua, "loading probe file");
        return;
    };
    lua.setTop(0);
    const ty = lua.getGlobal("_probe") catch {
        lua.setTop(0);
        record("probe script error: probe file does not define _probe(t, dt)", false);
        finishNow();
        return;
    };
    lua.setTop(0);
    if (ty != .function) {
        record("probe script error: probe file does not define _probe(t, dt)", false);
        finishNow();
    }
}

fn onTick(dt: f32) void {
    if (finished) return;
    if (!iso.vm.ready()) return;
    const lua = iso.vm.get();
    _ = wd_ticks.fetchAdd(1, .monotonic);
    if (!loaded) {
        loadProbe(lua);
        if (finished) return;
    }
    // dt 非法或为 0 时按 60fps 推进，保证游戏时间超时仍会触发（墙钟看门狗是最终兜底）
    t += if (std.math.isFinite(dt) and dt > 0) dt else 1.0 / 60.0;
    releaseTaps();

    if (t > timeout_s) {
        record("probe timed out", false);
        finishNow();
        return;
    }

    const top = lua.getTop();
    const ty = lua.getGlobal("_probe") catch {
        lua.setTop(top);
        return;
    };
    if (ty != .function) {
        lua.setTop(top);
        record("probe script error: _probe is no longer a function", false);
        finishNow();
        return;
    }
    lua.pushNumber(t);
    lua.pushNumber(dt);
    lua.protectedCall(.{ .args = 2 }) catch {
        scriptError(lua, "_probe");
        return;
    };
    lua.setTop(top);
}

// ------------------------------------------------------------------ Lua API

fn keyOf(code: i64) ?i32 {
    const c = std.math.cast(i32, code) orelse return null;
    _ = std.enums.fromInt(input.KeyCodes, c) orelse return null;
    return c;
}

fn buttonOf(btn: i64) ?i32 {
    const c = std.math.cast(i32, btn) orelse return null;
    _ = std.enums.fromInt(input.MouseButtons, c) orelse return null;
    return c;
}

pub fn key(code: i64, down: bool) void {
    const c = keyOf(code) orelse return;
    if (down) input.onKeyDown(c) else input.onKeyUp(c);
}

pub fn tap(code: i64) void {
    const c = keyOf(code) orelse return;
    input.onKeyDown(c);
    if (tap_n < max_taps) {
        taps[tap_n] = c;
        tap_n += 1;
    } else {
        input.onKeyUp(c);
    }
}

pub fn mouse_move(x: f32, y: f32) void {
    if (!std.math.isFinite(x) or !std.math.isFinite(y)) return;
    if (@abs(x) > 1.0e7 or @abs(y) > 1.0e7) return;
    input.onMouseMoved(x, y, 0, 0);
}

pub fn click(button: i64) void {
    const b = buttonOf(button) orelse return;
    input.onMouseDown(b);
    input.onMouseUp(b); // pressed 在本帧 post_draw 才清，just_pressed 当帧可见
}

pub fn mouse_button(button: i64, down: bool) void {
    const b = buttonOf(button) orelse return;
    if (down) input.onMouseDown(b) else input.onMouseUp(b);
}

pub fn pad_button(b: i64, down: bool) void {
    const u = std.math.cast(u8, b) orelse return;
    const btn = std.enums.fromInt(pad_logic.Button, u) orelse return;
    gamepad.injectButton(btn, down);
}

pub fn pad_axis(a: i64, v: f32) void {
    const u = std.math.cast(u8, a) orelse return;
    const ax = std.enums.fromInt(pad_logic.Axis, u) orelse return;
    gamepad.injectAxis(ax, v);
}

pub fn check(name: [*:0]const u8, ok: bool) void {
    record(std.mem.span(name), ok);
}

pub fn info(msg: [*:0]const u8) void {
    std.debug.print("PROBE info {s}\n", .{std.mem.span(msg)});
}

pub fn script_ok() bool {
    return !iso.script_host.script_failed;
}

pub fn finish() void {
    finishNow();
}

pub fn timeout(seconds: f32) void {
    if (!std.math.isFinite(seconds) or seconds <= 0 or seconds > 1.0e6) return;
    timeout_s = seconds;
    wd_limit_ms.store(totalLimitMs(seconds), .release);
}

// ------------------------------------------------------------------ 墙钟看门狗
//
// 独立线程，只碰原子量与 stderr，不碰 Lua / Delve 状态。选择“app.start 返回后 join”而非 detach：
// 线程每 100ms 轮询 wd_stop，正常退出最多延迟 100ms，且不会在进程收尾阶段仍访问 Io。
// 若主线程卡死（app.start 永不返回），join 不会被执行，由看门狗 exit(3) 终止进程。

const wd_stall_ms: u64 = 20_000;
const wd_poll_ms: i64 = 100;

var wd_thread: ?std.Thread = null;
var wd_io: std.Io = undefined;
var wd_ticks = std.atomic.Value(u64).init(0);
var wd_armed = std.atomic.Value(bool).init(false);
var wd_stop = std.atomic.Value(bool).init(false);
var wd_limit_ms = std.atomic.Value(u64).init(0);

fn totalLimitMs(timeout_seconds: f64) u64 {
    const secs = @max(timeout_seconds * 3.0, 120.0);
    return @intFromFloat(secs * 1000.0);
}

/// 在 `--probe` 下于 app.start 之前调用。
pub fn startWatchdog(io: std.Io) !void {
    wd_io = io;
    wd_limit_ms.store(totalLimitMs(timeout_s), .release);
    wd_armed.store(true, .release);
    wd_thread = try std.Thread.spawn(.{}, watchdogMain, .{});
}

/// app.start 返回后调用：解除并 join 线程。
pub fn stopWatchdog() void {
    wd_armed.store(false, .release);
    wd_stop.store(true, .release);
    if (wd_thread) |th| th.join();
    wd_thread = null;
}

fn watchdogMain() void {
    const io = wd_io;
    const start = std.Io.Clock.awake.now(io);
    var last_tick_at = start;
    var last_ticks: u64 = 0;
    while (!wd_stop.load(.acquire)) {
        io.sleep(.fromMilliseconds(wd_poll_ms), .awake) catch return;
        if (!wd_armed.load(.acquire)) continue;
        const now_ts = std.Io.Clock.awake.now(io);
        const ticks = wd_ticks.load(.monotonic);
        if (ticks != last_ticks) {
            last_ticks = ticks;
            last_tick_at = now_ts;
        }
        const total_ms: u64 = @intCast(@max(0, @divTrunc(start.durationTo(now_ts).nanoseconds, std.time.ns_per_ms)));
        const stall_ms: u64 = @intCast(@max(0, @divTrunc(last_tick_at.durationTo(now_ts).nanoseconds, std.time.ns_per_ms)));
        var reason: ?[]const u8 = null;
        if (stall_ms > wd_stall_ms) {
            reason = if (ticks == 0) "no probe tick within 20s" else "probe stopped ticking for 20s";
        } else if (total_ms > wd_limit_ms.load(.acquire)) {
            reason = "total wall time limit exceeded";
        }
        if (reason) |r| {
            // 与 finish()/正常退出竞争：只有成功把 armed 从 true 改为 false 的一方才继续
            if (wd_armed.cmpxchgStrong(true, false, .acq_rel, .acquire) != null) continue;
            const c = checks.load(.monotonic);
            const f = failures.load(.monotonic);
            std.debug.print("PROBE FAIL probe watchdog: {s} (device-less machine? use --no-audio)\n", .{r});
            std.debug.print("PROBE SUMMARY {d}/{d} passed\n", .{ c - f, c + 1 });
            std.process.exit(3);
        }
    }
}
