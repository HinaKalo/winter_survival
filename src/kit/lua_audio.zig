//! Lua 原始库 `kit_audio`（固定参数个数；友好默认值在 assets/scripts/audio.lua）。
//!
//! 注意：binder 会把本文件里所有 `pub fn` 绑定为 Lua 函数，辅助函数不要加 pub。
const std = @import("std");
const delve = @import("delve");
const binder = delve.scripting.binder;
const lua_util = delve.scripting.lua;
const kit_audio = @import("audio.zig");

const Reg = binder.Registry(.{ .entries = &[_]binder.BoundType{} });
const ignore_fns = [_][:0]const u8{"bind"};

/// 由 Lua 宿主在 Lua 启动后调用（见 iso.script_host 的 kit 钩子）
pub fn bind(lua: *lua_util.Lua) void {
    const fns = comptime Reg.findLibraryFunctions(@This(), &ignore_fns);
    Reg.bindLibrary(lua, "kit_audio", fns);
}

pub fn sfx(id: [*:0]const u8, vol: f32, pitch: f32) bool {
    return kit_audio.sfx(std.mem.span(id), vol, pitch);
}

pub fn bgm(id: [*:0]const u8, fade: f32) bool {
    return kit_audio.bgm(std.mem.span(id), fade);
}

pub fn stop_bgm(fade: f32) void {
    kit_audio.stopBgm(fade);
}

pub fn amb(layer: i64, id: [*:0]const u8, fade: f32) bool {
    if (layer < 1 or layer > 3) return false;
    return kit_audio.amb(@intCast(layer), std.mem.span(id), fade);
}

pub fn stop_amb(layer: i64, fade: f32) void {
    if (layer < 1 or layer > 3) return;
    kit_audio.stopAmb(@intCast(layer), fade);
}

pub fn amb_gain(layer: i64, v: f32, fade: f32) bool {
    if (layer < 1 or layer > 3) return false;
    return kit_audio.ambGain(@intCast(layer), v, fade);
}

pub fn current_amb(layer: i64) ?[]const u8 {
    if (layer < 1 or layer > 3) return null;
    return kit_audio.currentAmb(@intCast(layer));
}

pub fn set_bus(name: [*:0]const u8, v: f32) bool {
    return kit_audio.setBus(std.mem.span(name), v);
}

pub fn has(id: [*:0]const u8) bool {
    return kit_audio.has(std.mem.span(id));
}

pub fn current_bgm() ?[]const u8 {
    return kit_audio.currentBgm();
}

/// {sfx_played, sfx_rejected, bgm_started}
pub fn stats() [3]i64 {
    const s = kit_audio.stats();
    return .{ s.sfx_played, s.sfx_rejected, s.bgm_started };
}

pub fn enabled() bool {
    return kit_audio.playbackEnabled();
}
