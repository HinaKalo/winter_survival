//! 模块 `kit_audio`：总线、BGM 状态、SFX 语音环、统计。
//!
//! 优先级 -65；需在 `delve.init` 之后、`app.start` 之前 `register`。
//! 播放通过 `delve.platform.audio`（要求 `app.start(.{ .enable_audio = true })`）。
//! 无声模式（`playback = false`）：校验、统计、BGM 记账与有声模式完全一致，只是不真正播放。
//! 热重载（F5）不会触碰本模块；Lua 对外函数永不 panic。
//!
//! 注意：本文件不是 Lua 绑定文件（绑定在 lua_audio.zig），但仍保持非必要函数私有。
const std = @import("std");
const delve = @import("delve");
const audio = delve.platform.audio;
const debug = delve.debug;
const modules = delve.modules;
const mem = delve.mem;
const delve_io = delve.io;
const cat_mod = @import("audio_catalog.zig");

pub const Config = struct {
    /// false = 无声模式（--no-audio）
    playback: bool = true,
    catalog_path: []const u8 = "assets/audio/catalog.json",
};

pub const Stats = struct {
    sfx_played: i64 = 0,
    sfx_rejected: i64 = 0,
    bgm_started: i64 = 0,
};

pub const Bus = enum { master, sfx, bgm };

const voice_count = 24;
const throttle_s: f64 = 0.03;
const max_fade_s: f32 = 60.0;
const max_fading = 4;
const max_warned = 64;

const Fading = struct { sound: audio.Sound, left: f32 };

var cfg: Config = .{};
var registered: bool = false;
var inited: bool = false;
var catalog: ?cat_mod.Catalog = null;
/// 与 catalog.entries 平行：上次播放的游戏时间
var last_play: []f64 = &.{};
var now: f64 = 0;
var bus_vol = [3]f32{ 1, 1, 1 };
var stat: Stats = .{};

var voices: [voice_count]?audio.Sound = [_]?audio.Sound{null} ** voice_count;
var next_voice: usize = 0;

var cur_idx: ?usize = null;
var cur_sound: ?audio.Sound = null;
var fading: [max_fading]?Fading = [_]?Fading{null} ** max_fading;

var warned: [max_warned]u64 = undefined;
var warned_n: usize = 0;

pub fn register(c: Config) !void {
    if (registered) return;
    cfg = c;
    try modules.registerModule(.{
        .name = "kit_audio",
        .priority = -65,
        .init_fn = onInit,
        .tick_fn = onTick,
        .cleanup_fn = onCleanup,
    });
    registered = true;
}

// ------------------------------------------------------------------ 生命周期

fn resetState() void {
    now = 0;
    bus_vol = .{ 1, 1, 1 };
    stat = .{};
    voices = [_]?audio.Sound{null} ** voice_count;
    next_voice = 0;
    cur_idx = null;
    cur_sound = null;
    fading = [_]?Fading{null} ** max_fading;
    warned_n = 0;
}

fn onInit() !void {
    const allocator = mem.getAllocator();
    resetState();

    const empty = "{\"version\": 1, \"sounds\": []}";
    const bytes: ?[]u8 = std.Io.Dir.cwd().readFileAlloc(delve_io.getIo(), cfg.catalog_path, allocator, .limited(4 * 1024 * 1024)) catch |err| blk: {
        debug.warning("kit_audio: cannot read {s} ({s}); audio catalog is empty", .{ cfg.catalog_path, @errorName(err) });
        break :blk null;
    };
    defer if (bytes) |b| allocator.free(b);

    catalog = cat_mod.Catalog.parse(allocator, bytes orelse empty) catch |err| blk: {
        if (err == error.OutOfMemory) return err;
        debug.err("kit_audio: invalid catalog {s} ({s}); audio catalog is empty", .{ cfg.catalog_path, @errorName(err) });
        break :blk try cat_mod.Catalog.parse(allocator, empty);
    };
    errdefer {
        catalog.?.deinit();
        catalog = null;
    }
    for (catalog.?.warnings) |w| debug.warning("kit_audio: {s}", .{w});

    last_play = try allocator.alloc(f64, catalog.?.entries.len);
    @memset(last_play, -1.0e9);
    inited = true;
    debug.log("kit_audio: {d} sounds in catalog, playback {s}", .{
        catalog.?.entries.len,
        if (cfg.playback) "on" else "off",
    });
}

fn onCleanup() !void {
    if (!inited) return;
    inited = false;
    // 停止一切
    for (&voices) |*slot| {
        if (slot.*) |*s| {
            s.stop();
            s.requestDestroy();
        }
        slot.* = null;
    }
    if (cur_sound) |*s| {
        s.stop();
        s.requestDestroy();
    }
    cur_sound = null;
    cur_idx = null;
    for (&fading) |*slot| {
        if (slot.*) |*f| {
            f.sound.stop();
            f.sound.requestDestroy();
        }
        slot.* = null;
    }
    const allocator = mem.getAllocator();
    allocator.free(last_play);
    last_play = &.{};
    if (catalog) |*c| c.deinit();
    catalog = null;
}

fn onTick(dt: f32) void {
    if (!inited) return;
    if (std.math.isFinite(dt) and dt > 0) now += dt;
    for (&fading) |*slot| {
        if (slot.*) |*f| {
            f.left -= dt;
            if (f.left <= 0) {
                f.sound.stop();
                f.sound.requestDestroy();
                slot.* = null;
            }
        }
    }
}

// ------------------------------------------------------------------ 辅助

fn finite(v: f32) bool {
    return std.math.isFinite(v);
}

/// 同一 (原因, id) 只记一次日志；总数有上限
fn warnOnce(reason: []const u8, id: []const u8) void {
    var h = std.hash.Wyhash.init(0);
    h.update(reason);
    h.update("\x00");
    h.update(id);
    const key = h.final();
    for (warned[0..warned_n]) |k| {
        if (k == key) return;
    }
    if (warned_n >= max_warned) return;
    warned[warned_n] = key;
    warned_n += 1;
    debug.warning("kit_audio: {s}: '{s}'", .{ reason, id });
}

fn busIndex(b: Bus) usize {
    return @intFromEnum(b);
}

fn effectiveVolume(entry_volume: f32, bus: Bus, call_volume: f32) f32 {
    const v = entry_volume * bus_vol[busIndex(bus)] * bus_vol[0] * call_volume;
    return std.math.clamp(v, 0, 4);
}

fn rejectSfx() bool {
    stat.sfx_rejected += 1;
    return false;
}

fn retireCurrent(fade_s: f32) void {
    if (cur_sound) |*s| {
        if (fade_s > 0) {
            s.fade(-1, 0, fade_s);
            var placed = false;
            for (&fading) |*slot| {
                if (slot.* == null) {
                    slot.* = .{ .sound = s.*, .left = fade_s };
                    placed = true;
                    break;
                }
            }
            if (!placed) {
                // 槽位满：直接杀掉最老的一个，腾出位置
                if (fading[0]) |*f| {
                    f.sound.stop();
                    f.sound.requestDestroy();
                }
                fading[0] = .{ .sound = s.*, .left = fade_s };
            }
        } else {
            s.stop();
            s.requestDestroy();
        }
    }
    cur_sound = null;
    cur_idx = null;
}

// ------------------------------------------------------------------ 对外 API

pub fn sfx(id: []const u8, volume: f32, pitch: f32) bool {
    if (!inited) return false;
    if (catalog == null) return rejectSfx();
    const c = &catalog.?;
    if (!finite(volume) or !finite(pitch)) {
        warnOnce("non-finite volume/pitch for sfx", id);
        return rejectSfx();
    }
    const idx = c.indexOf(id) orelse {
        warnOnce("unknown sound id", id);
        return rejectSfx();
    };
    const e = &c.entries[idx];
    if (e.kind != .sfx) {
        warnOnce("not an sfx id", id);
        return rejectSfx();
    }
    if (now - last_play[idx] < throttle_s) return rejectSfx();

    const vol = effectiveVolume(e.volume, .sfx, std.math.clamp(volume, 0, 4));
    const pit = std.math.clamp(pitch, 0.25, 4.0);

    if (cfg.playback) {
        var snd = audio.playSound(e.path, .{ .stream = false, .volume = vol, .loop = false }) orelse {
            warnOnce("failed to load sound", id);
            return rejectSfx();
        };
        snd.setPitch(pit);
        if (voices[next_voice]) |*old| old.requestDestroy();
        voices[next_voice] = snd;
        next_voice = (next_voice + 1) % voice_count;
    }
    last_play[idx] = now;
    stat.sfx_played += 1;
    return true;
}

pub fn bgm(id: []const u8, fade_s: f32) bool {
    if (!inited) return false;
    if (catalog == null) return false;
    const c = &catalog.?;
    if (!finite(fade_s)) {
        warnOnce("non-finite fade for bgm", id);
        return false;
    }
    const idx = c.indexOf(id) orelse {
        warnOnce("unknown sound id", id);
        return false;
    };
    const e = &c.entries[idx];
    if (e.kind != .bgm) {
        warnOnce("not a bgm id", id);
        return false;
    }
    if (cur_idx != null and cur_idx.? == idx) return true;

    const f = std.math.clamp(fade_s, 0, max_fade_s);
    var new_sound: ?audio.Sound = null;
    const mode = cat_mod.loopMode(e);
    if (mode == .unsupported_points) {
        warnOnce("intro+loop points not supported by Delve audio; looping whole file", id);
    }
    if (cfg.playback) {
        new_sound = audio.playSound(e.path, .{
            .stream = true,
            .volume = effectiveVolume(e.volume, .bgm, 1.0),
            .loop = mode != .none,
            .fade_in_time = if (f > 0) f else null,
        }) orelse {
            warnOnce("failed to load sound", id);
            return false;
        };
    }
    retireCurrent(f);
    cur_idx = idx;
    cur_sound = new_sound;
    stat.bgm_started += 1;
    return true;
}

pub fn stopBgm(fade_s: f32) void {
    if (!inited) return;
    if (!finite(fade_s)) return;
    retireCurrent(std.math.clamp(fade_s, 0, max_fade_s));
}

pub fn setBus(name: []const u8, v: f32) bool {
    if (!inited or !finite(v)) return false;
    const b = std.meta.stringToEnum(Bus, name) orelse return false;
    bus_vol[busIndex(b)] = std.math.clamp(v, 0, 1);
    if (cur_sound) |*s| {
        if (catalog == null) return true;
        const c = &catalog.?;
        if (cur_idx) |i| s.setVolume(effectiveVolume(c.entries[i].volume, .bgm, 1.0));
    }
    return true;
}

pub fn has(id: []const u8) bool {
    if (!inited) return false;
    if (catalog == null) return false;
    const c = &catalog.?;
    return c.indexOf(id) != null;
}

pub fn currentBgm() ?[]const u8 {
    if (!inited) return null;
    if (catalog == null) return null;
    const c = &catalog.?;
    const i = cur_idx orelse return null;
    return c.entries[i].id;
}

pub fn stats() Stats {
    return stat;
}

pub fn playbackEnabled() bool {
    return inited and cfg.playback;
}
