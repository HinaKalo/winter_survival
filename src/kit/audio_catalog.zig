//! 音频目录（纯逻辑，只依赖 std）：解析 `assets/audio/catalog.json`。
//!
//! 契约见 docs/STARTER-PLAN.md "Catalog contract"。单行非法不会让整个目录失败：
//! 该行被跳过并在 `warnings` 中留下一条说明；重复 id 保留第一条。
const std = @import("std");

pub const Kind = enum { sfx, bgm };

pub const LoopMode = enum {
    none,
    whole_file,
    /// 目录里给了循环点，但 Delve 不支持：按整文件循环播放
    unsupported_points,
};

pub const Entry = struct {
    id: []const u8,
    /// 相对项目根，以 NUL 结尾，可直接传给 Delve
    path: [:0]const u8,
    kind: Kind,
    category: ?[]const u8,
    loop: bool,
    loop_start: u64,
    loop_length: u64,
    frames: u64,
    sample_rate: u32,
    channels: u32,
    volume: f32,
};

pub const ParseError = error{
    InvalidCatalog,
    UnsupportedVersion,
    OutOfMemory,
};

pub const Catalog = struct {
    arena: std.heap.ArenaAllocator,
    entries: []const Entry,
    /// 被跳过的行 / 重复 id 的说明（内存归 arena）
    warnings: []const []const u8,

    pub fn parse(allocator: std.mem.Allocator, json_bytes: []const u8) ParseError!Catalog {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const a = arena.allocator();

        const root = std.json.parseFromSliceLeaky(std.json.Value, a, json_bytes, .{}) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InvalidCatalog,
        };
        if (root != .object) return error.InvalidCatalog;

        const ver = root.object.get("version") orelse return error.InvalidCatalog;
        if (ver != .integer) return error.InvalidCatalog;
        if (ver.integer != 1) return error.UnsupportedVersion;

        const sounds = root.object.get("sounds") orelse return error.InvalidCatalog;
        if (sounds != .array) return error.InvalidCatalog;

        var entries: std.ArrayList(Entry) = .empty;
        var warnings: std.ArrayList([]const u8) = .empty;

        for (sounds.array.items, 0..) |row, i| {
            var reason: []const u8 = "";
            const parsed = parseRow(a, row, &reason) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.Invalid => {
                    try warnings.append(a, try std.fmt.allocPrint(a, "catalog row {d} skipped: {s}", .{ i, reason }));
                    continue;
                },
            };
            var dup = false;
            for (entries.items) |e| {
                if (std.mem.eql(u8, e.id, parsed.id)) {
                    dup = true;
                    break;
                }
            }
            if (dup) {
                try warnings.append(a, try std.fmt.allocPrint(a, "catalog row {d} skipped: duplicate id '{s}' (keeping the first)", .{ i, parsed.id }));
                continue;
            }
            try entries.append(a, parsed);
        }

        return .{
            .arena = arena,
            .entries = entries.items,
            .warnings = warnings.items,
        };
    }

    pub fn deinit(self: *Catalog) void {
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn get(self: *const Catalog, id: []const u8) ?*const Entry {
        return if (self.indexOf(id)) |i| &self.entries[i] else null;
    }

    pub fn indexOf(self: *const Catalog, id: []const u8) ?usize {
        for (self.entries, 0..) |e, i| {
            if (std.mem.eql(u8, e.id, id)) return i;
        }
        return null;
    }
};

pub fn loopMode(entry: *const Entry) LoopMode {
    if (!entry.loop) return .none;
    if (entry.loop_start == 0 and (entry.loop_length == 0 or entry.loop_length == entry.frames)) return .whole_file;
    return .unsupported_points;
}

/// `^(sfx|bgm)/[a-z0-9_]+(/[a-z0-9_]+)*$`
pub fn validId(id: []const u8) bool {
    var it = std.mem.splitScalar(u8, id, '/');
    const head = it.next() orelse return false;
    if (!std.mem.eql(u8, head, "sfx") and !std.mem.eql(u8, head, "bgm")) return false;
    var n: usize = 0;
    while (it.next()) |seg| {
        if (seg.len == 0) return false;
        for (seg) |c| {
            const ok = (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '_';
            if (!ok) return false;
        }
        n += 1;
    }
    return n >= 1;
}

/// 以 assets/audio/ 开头、不含 ".."、以 .wav/.ogg 结尾
pub fn validPath(path: []const u8) bool {
    if (!std.mem.startsWith(u8, path, "assets/audio/")) return false;
    if (std.mem.indexOf(u8, path, "..") != null) return false;
    if (std.mem.indexOfScalar(u8, path, 0) != null) return false;
    return std.mem.endsWith(u8, path, ".wav") or std.mem.endsWith(u8, path, ".ogg");
}

const RowError = error{ Invalid, OutOfMemory };

fn fail(reason: *[]const u8, msg: []const u8) RowError {
    reason.* = msg;
    return error.Invalid;
}

fn getUint(obj: std.json.ObjectMap, key: []const u8, default: u64, reason: *[]const u8) RowError!u64 {
    const v = obj.get(key) orelse return default;
    if (v != .integer or v.integer < 0) return fail(reason, "bad integer field");
    return @intCast(v.integer);
}

fn parseRow(a: std.mem.Allocator, row: std.json.Value, reason: *[]const u8) RowError!Entry {
    if (row != .object) return fail(reason, "not an object");
    const obj = row.object;

    const id_v = obj.get("id") orelse return fail(reason, "missing id");
    if (id_v != .string) return fail(reason, "id is not a string");
    const id = id_v.string;
    if (!validId(id)) return fail(reason, "invalid id");

    const kind_v = obj.get("kind") orelse return fail(reason, "missing kind");
    if (kind_v != .string) return fail(reason, "kind is not a string");
    const kind: Kind = if (std.mem.eql(u8, kind_v.string, "sfx"))
        .sfx
    else if (std.mem.eql(u8, kind_v.string, "bgm"))
        .bgm
    else
        return fail(reason, "kind must be sfx or bgm");
    if (!std.mem.startsWith(u8, id, @tagName(kind)) or id[@tagName(kind).len] != '/') {
        return fail(reason, "kind does not match id prefix");
    }

    const path_v = obj.get("path") orelse return fail(reason, "missing path");
    if (path_v != .string) return fail(reason, "path is not a string");
    if (!validPath(path_v.string)) return fail(reason, "invalid path");

    var category: ?[]const u8 = null;
    if (obj.get("category")) |c| switch (c) {
        .string => |s| category = try a.dupe(u8, s),
        .null => {},
        else => return fail(reason, "category must be a string or null"),
    };

    var loop = false;
    if (obj.get("loop")) |l| {
        if (l != .bool) return fail(reason, "loop must be a bool");
        loop = l.bool;
    }

    const loop_start = try getUint(obj, "loop_start", 0, reason);
    const loop_length = try getUint(obj, "loop_length", 0, reason);
    const frames = try getUint(obj, "frames", 0, reason);
    const sample_rate = std.math.cast(u32, try getUint(obj, "sample_rate", 0, reason)) orelse return fail(reason, "sample_rate out of range");
    const channels = std.math.cast(u32, try getUint(obj, "channels", 0, reason)) orelse return fail(reason, "channels out of range");

    var volume: f32 = 1.0;
    if (obj.get("volume")) |v| {
        const f: f64 = switch (v) {
            .integer => |i| @floatFromInt(i),
            .float => |x| x,
            else => return fail(reason, "volume must be a number"),
        };
        if (!std.math.isFinite(f) or f < 0 or f > 4) return fail(reason, "volume out of range 0..4");
        volume = @floatCast(f);
    }

    return .{
        .id = try a.dupe(u8, id),
        .path = try a.dupeZ(u8, path_v.string),
        .kind = kind,
        .category = category,
        .loop = loop,
        .loop_start = loop_start,
        .loop_length = loop_length,
        .frames = frames,
        .sample_rate = sample_rate,
        .channels = channels,
        .volume = volume,
    };
}

// ------------------------------------------------------------------ tests

const testing = std.testing;

const good_json =
    \\{"version": 1, "sounds": [
    \\ {"id": "bgm/loop", "path": "assets/audio/bgm/loop.ogg", "kind": "bgm", "category": null, "loop": true,
    \\  "loop_start": 0, "loop_length": 100, "frames": 100, "sample_rate": 48000, "channels": 2, "volume": 1.0, "extra": 5},
    \\ {"id": "sfx/ui/click", "path": "assets/audio/sfx/ui/click.wav", "kind": "sfx", "category": "ui", "loop": false,
    \\  "loop_start": 0, "loop_length": 0, "frames": 10, "sample_rate": 48000, "channels": 1, "volume": 2}
    \\]}
;

test "parse good catalog" {
    var cat = try Catalog.parse(testing.allocator, good_json);
    defer cat.deinit();
    try testing.expectEqual(@as(usize, 2), cat.entries.len);
    try testing.expectEqual(@as(usize, 0), cat.warnings.len);
    const e = cat.get("sfx/ui/click").?;
    try testing.expectEqual(Kind.sfx, e.kind);
    try testing.expectEqualStrings("ui", e.category.?);
    try testing.expectEqual(@as(f32, 2.0), e.volume);
    try testing.expectEqualStrings("assets/audio/sfx/ui/click.wav", e.path);
    try testing.expect(cat.get("bgm/loop").?.category == null);
    try testing.expect(cat.get("sfx/nope") == null);
}

test "invalid rows are skipped with warnings" {
    const json =
        \\{"version": 1, "sounds": [
        \\ {"id": "sfx/ok", "path": "assets/audio/sfx/ok.wav", "kind": "sfx"},
        \\ {"id": "Sfx/Bad", "path": "assets/audio/sfx/a.wav", "kind": "sfx"},
        \\ {"id": "sfx/a", "path": "assets/audio/sfx/a.wav", "kind": "bgm"},
        \\ {"id": "sfx/b", "path": "assets/other/b.wav", "kind": "sfx"},
        \\ {"id": "sfx/c", "path": "assets/audio/../c.wav", "kind": "sfx"},
        \\ {"id": "sfx/d", "path": "assets/audio/d.mp3", "kind": "sfx"},
        \\ {"id": "sfx/e", "path": "assets/audio/e.wav", "kind": "sfx", "volume": 5},
        \\ {"id": "sfx/f", "path": "assets/audio/f.wav", "kind": "sfx", "volume": -1},
        \\ {"id": "sfx/g", "path": "assets/audio/g.wav", "kind": "sfx", "frames": -3},
        \\ {"id": "sfx/h", "path": "assets/audio/h.wav", "kind": "sfx", "loop": "yes"},
        \\ {"id": "sfx//x", "path": "assets/audio/x.wav", "kind": "sfx"},
        \\ {"id": "sfx", "path": "assets/audio/x.wav", "kind": "sfx"},
        \\ {"path": "assets/audio/x.wav", "kind": "sfx"},
        \\ 42
        \\]}
    ;
    var cat = try Catalog.parse(testing.allocator, json);
    defer cat.deinit();
    try testing.expectEqual(@as(usize, 1), cat.entries.len);
    try testing.expectEqualStrings("sfx/ok", cat.entries[0].id);
    try testing.expectEqual(@as(usize, 13), cat.warnings.len);
}

test "duplicate ids keep the first" {
    const json =
        \\{"version": 1, "sounds": [
        \\ {"id": "sfx/a", "path": "assets/audio/sfx/first.wav", "kind": "sfx"},
        \\ {"id": "sfx/a", "path": "assets/audio/sfx/second.wav", "kind": "sfx"}
        \\]}
    ;
    var cat = try Catalog.parse(testing.allocator, json);
    defer cat.deinit();
    try testing.expectEqual(@as(usize, 1), cat.entries.len);
    try testing.expectEqualStrings("assets/audio/sfx/first.wav", cat.get("sfx/a").?.path);
    try testing.expectEqual(@as(usize, 1), cat.warnings.len);
}

test "bad version and bad documents" {
    try testing.expectError(error.UnsupportedVersion, Catalog.parse(testing.allocator, "{\"version\": 2, \"sounds\": []}"));
    try testing.expectError(error.InvalidCatalog, Catalog.parse(testing.allocator, "{\"sounds\": []}"));
    try testing.expectError(error.InvalidCatalog, Catalog.parse(testing.allocator, "{\"version\": 1}"));
    try testing.expectError(error.InvalidCatalog, Catalog.parse(testing.allocator, "{\"version\": 1, \"sounds\": 3}"));
    try testing.expectError(error.InvalidCatalog, Catalog.parse(testing.allocator, "[1,2]"));
    try testing.expectError(error.InvalidCatalog, Catalog.parse(testing.allocator, "not json"));
    try testing.expectError(error.InvalidCatalog, Catalog.parse(testing.allocator, ""));
}

test "empty catalog" {
    var cat = try Catalog.parse(testing.allocator, "{\"version\": 1, \"sounds\": []}");
    defer cat.deinit();
    try testing.expectEqual(@as(usize, 0), cat.entries.len);
}

fn mk(loop: bool, start: u64, len: u64, frames: u64) Entry {
    return .{
        .id = "bgm/x",
        .path = "assets/audio/bgm/x.ogg",
        .kind = .bgm,
        .category = null,
        .loop = loop,
        .loop_start = start,
        .loop_length = len,
        .frames = frames,
        .sample_rate = 48000,
        .channels = 2,
        .volume = 1.0,
    };
}

test "loopMode" {
    try testing.expectEqual(LoopMode.none, loopMode(&mk(false, 0, 0, 100)));
    try testing.expectEqual(LoopMode.none, loopMode(&mk(false, 5, 50, 100)));
    try testing.expectEqual(LoopMode.whole_file, loopMode(&mk(true, 0, 0, 100)));
    try testing.expectEqual(LoopMode.whole_file, loopMode(&mk(true, 0, 100, 100)));
    try testing.expectEqual(LoopMode.unsupported_points, loopMode(&mk(true, 10, 90, 100)));
    try testing.expectEqual(LoopMode.unsupported_points, loopMode(&mk(true, 0, 60, 100)));
}

test "validId and validPath" {
    try testing.expect(validId("sfx/a"));
    try testing.expect(validId("bgm/a/b_c1"));
    try testing.expect(!validId("sfx/"));
    try testing.expect(!validId("sfx"));
    try testing.expect(!validId("foo/a"));
    try testing.expect(!validId("sfx/A"));
    try testing.expect(!validId("sfx/a b"));
    try testing.expect(validPath("assets/audio/sfx/a.wav"));
    try testing.expect(validPath("assets/audio/bgm/a.ogg"));
    try testing.expect(!validPath("/assets/audio/a.wav"));
    try testing.expect(!validPath("assets/audio/a.flac"));
}

test "real seeded catalog parses without warnings" {
    // 测试在项目根运行（build.zig 设置 cwd）；找不到则跳过
    const io = testing.io;
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, "assets/audio/catalog.json", testing.allocator, .limited(1 << 20)) catch return error.SkipZigTest;
    defer testing.allocator.free(bytes);
    var cat = try Catalog.parse(testing.allocator, bytes);
    defer cat.deinit();
    try testing.expectEqual(@as(usize, 0), cat.warnings.len);
    try testing.expect(cat.entries.len > 0);
}
