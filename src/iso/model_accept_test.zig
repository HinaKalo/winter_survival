// 验收测试，编码代理不得修改（主代理编写；认为有误时停下报告）。docs/M5-3D-PLAN.md §2、§3、§7。
// src/iso/model.zig 纯逻辑：WSM1 解析、错误、节点查找、可见性（完整名 / "前缀*"）、面数、明暗。
const std = @import("std");
const testing = std.testing;
const model = @import("model.zig");

const NodeSpec = struct { name: []const u8, tris: u32 };

/// 按 §2 拼出一个 WSM1 字节串：每个节点 tris 个三角形，顶点坐标随序号递增。
fn build(allocator: std.mem.Allocator, specs: []const NodeSpec) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var total: u32 = 0;
    for (specs) |s| total += s.tris * 3;
    try out.appendSlice(allocator, "WSM1");
    try appendInt(allocator, &out, u32, 1);
    try appendInt(allocator, &out, u32, @intCast(specs.len));
    try appendInt(allocator, &out, u32, total);
    var first: u32 = 0;
    for (specs) |s| {
        try appendInt(allocator, &out, u16, @intCast(s.name.len));
        try out.appendSlice(allocator, s.name);
        try appendInt(allocator, &out, u32, first);
        try appendInt(allocator, &out, u32, s.tris * 3);
        for (0..6) |_| try appendF32(allocator, &out, 0);
        first += s.tris * 3;
    }
    var i: u32 = 0;
    while (i < total) : (i += 1) {
        try appendF32(allocator, &out, @floatFromInt(i));
        try appendF32(allocator, &out, 0);
        try appendF32(allocator, &out, 1);
        try out.appendSlice(allocator, &[_]u8{ 0, 127, 0, 0, 10, 20, 30, 255 });
    }
    return out.toOwnedSlice(allocator);
}

fn appendInt(allocator: std.mem.Allocator, out: *std.ArrayList(u8), comptime T: type, v: T) !void {
    var buf: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &buf, v, .little);
    try out.appendSlice(allocator, &buf);
}

fn appendF32(allocator: std.mem.Allocator, out: *std.ArrayList(u8), v: f32) !void {
    try appendInt(allocator, out, u32, @bitCast(v));
}

const sample = [_]NodeSpec{
    .{ .name = "F1_floor", .tris = 2 },
    .{ .name = "F1_wall_high", .tris = 3 },
    .{ .name = "F1_wall_low", .tris = 1 },
    .{ .name = "F2_floor", .tris = 4 },
};

test "WSM1: parse nodes, vertices and fields" {
    const a = testing.allocator;
    const bytes = try build(a, &sample);
    defer a.free(bytes);
    var m = try model.Model.parse(a, bytes);
    defer m.deinit(a);
    try testing.expectEqual(@as(usize, 4), m.nodes.len);
    try testing.expectEqual(@as(usize, 30), m.verts.len);
    try testing.expectEqual(@as(usize, 4), m.visible.len);
    try testing.expectEqualStrings("F1_wall_high", m.nodes[1].name);
    try testing.expectEqual(@as(u32, 6), m.nodes[1].first);
    try testing.expectEqual(@as(u32, 9), m.nodes[1].count);
    const v = m.verts[7];
    try testing.expectEqual(@as(f32, 7), v.x);
    try testing.expectEqual(@as(f32, 1), v.z);
    try testing.expectEqual(@as(i8, 127), v.ny);
    try testing.expectEqual(@as(u8, 20), v.g);
    try testing.expectEqual(@as(u8, 255), v.a);
    try testing.expectEqual(@as(usize, 20), @sizeOf(model.Vertex));
}

test "WSM1: new model is fully visible; tri counts" {
    const a = testing.allocator;
    const bytes = try build(a, &sample);
    defer a.free(bytes);
    var m = try model.Model.parse(a, bytes);
    defer m.deinit(a);
    for (m.visible) |vis| try testing.expect(vis);
    try testing.expectEqual(@as(u32, 10), m.triCount());
    try testing.expectEqual(@as(u32, 10), m.visibleTris());
}

test "WSM1: findNode" {
    const a = testing.allocator;
    const bytes = try build(a, &sample);
    defer a.free(bytes);
    var m = try model.Model.parse(a, bytes);
    defer m.deinit(a);
    try testing.expectEqual(@as(?usize, 3), m.findNode("F2_floor"));
    try testing.expectEqual(@as(?usize, null), m.findNode("F2"));
    try testing.expectEqual(@as(?usize, null), m.findNode("nope"));
}

test "WSM1: setVisible exact name and prefix pattern" {
    const a = testing.allocator;
    const bytes = try build(a, &sample);
    defer a.free(bytes);
    var m = try model.Model.parse(a, bytes);
    defer m.deinit(a);
    try testing.expectEqual(@as(u32, 1), m.setVisible("F1_wall_high", false));
    try testing.expectEqual(@as(u32, 7), m.visibleTris());
    try testing.expectEqual(@as(u32, 3), m.setVisible("F1_*", false));
    try testing.expectEqual(@as(u32, 4), m.visibleTris());
    try testing.expectEqual(@as(u32, 2), m.setVisible("F1_wall*", true));
    try testing.expectEqual(@as(u32, 8), m.visibleTris());
    try testing.expect(!m.visible[0]);
    try testing.expectEqual(@as(u32, 0), m.setVisible("B1_*", false));
    try testing.expectEqual(@as(u32, 0), m.setVisible("F1_wall", false)); // 不带 * 时必须完全相等
    try testing.expectEqual(@as(u32, 4), m.setVisible("*", true)); // 空前缀匹配全部
    try testing.expectEqual(@as(u32, 10), m.visibleTris());
}

test "WSM1: errors" {
    const a = testing.allocator;
    const bytes = try build(a, &sample);
    defer a.free(bytes);

    try testing.expectError(error.Truncated, model.Model.parse(a, bytes[0..10]));
    try testing.expectError(error.Truncated, model.Model.parse(a, bytes[0 .. bytes.len - 1]));

    const bad_magic = try a.dupe(u8, bytes);
    defer a.free(bad_magic);
    bad_magic[0] = 'X';
    try testing.expectError(error.BadMagic, model.Model.parse(a, bad_magic));

    const bad_ver = try a.dupe(u8, bytes);
    defer a.free(bad_ver);
    std.mem.writeInt(u32, bad_ver[4..8], 2, .little);
    try testing.expectError(error.BadVersion, model.Model.parse(a, bad_ver));

    // 第一个节点的 count 改成 5（不是 3 的倍数）
    const bad_count = try a.dupe(u8, bytes);
    defer a.free(bad_count);
    const count_off = 16 + 2 + "F1_floor".len + 4;
    std.mem.writeInt(u32, bad_count[count_off..][0..4], 5, .little);
    try testing.expectError(error.BadRange, model.Model.parse(a, bad_count));

    // 第一个节点的 count 越过顶点总数
    const bad_over = try a.dupe(u8, bytes);
    defer a.free(bad_over);
    std.mem.writeInt(u32, bad_over[count_off..][0..4], 300, .little);
    try testing.expectError(error.BadRange, model.Model.parse(a, bad_over));

    // 末尾多余字节
    const extra = try a.alloc(u8, bytes.len + 3);
    defer a.free(extra);
    @memcpy(extra[0..bytes.len], bytes);
    @memset(extra[bytes.len..], 0);
    try testing.expectError(error.BadRange, model.Model.parse(a, extra));
}

test "WSM1: empty model is valid" {
    const a = testing.allocator;
    const bytes = try build(a, &[_]NodeSpec{});
    defer a.free(bytes);
    var m = try model.Model.parse(a, bytes);
    defer m.deinit(a);
    try testing.expectEqual(@as(usize, 0), m.nodes.len);
    try testing.expectEqual(@as(u32, 0), m.visibleTris());
}

test "shade: up >= side >= down, within [0.55, 1]" {
    const up = model.shade(0, 127, 0);
    const down = model.shade(0, -127, 0);
    const sides = [_]f32{
        model.shade(127, 0, 0), model.shade(-127, 0, 0),
        model.shade(0, 0, 127), model.shade(0, 0, -127),
    };
    try testing.expect(up <= 1.0 and up >= 0.55);
    try testing.expect(down <= 1.0 and down >= 0.55);
    for (sides) |s| {
        try testing.expect(s >= 0.55 and s <= 1.0);
        try testing.expect(up >= s);
        try testing.expect(s >= down);
    }
    try testing.expect(up - down >= 0.2);
    // 光从左上（西北，-X / -Z 方向）来：朝 -X 的面不比朝 +X 的面暗
    try testing.expect(model.shade(-127, 0, 0) >= model.shade(127, 0, 0));
}
