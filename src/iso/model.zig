//! WSM1 模型（docs/M5-3D-PLAN.md §2、§3）：纯逻辑，仅解析与可见性，不碰图形。
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Vertex = extern struct { x: f32, y: f32, z: f32, nx: i8, ny: i8, nz: i8, pad: u8, r: u8, g: u8, b: u8, a: u8 };
pub const Node = struct { name: []const u8, first: u32, count: u32, min: [3]f32, max: [3]f32 };
pub const ParseError = error{ BadMagic, BadVersion, Truncated, BadRange, OutOfMemory };

comptime {
    std.debug.assert(@sizeOf(Vertex) == 20);
}

const Reader = struct {
    bytes: []const u8,
    pos: usize = 0,

    fn take(self: *Reader, n: usize) ParseError![]const u8 {
        if (self.bytes.len - self.pos < n) return error.Truncated;
        const s = self.bytes[self.pos..][0..n];
        self.pos += n;
        return s;
    }

    fn int(self: *Reader, comptime T: type) ParseError!T {
        const s = try self.take(@sizeOf(T));
        return std.mem.readInt(T, s[0..@sizeOf(T)], .little);
    }

    fn f32le(self: *Reader) ParseError!f32 {
        return @bitCast(try self.int(u32));
    }
};

pub const Model = struct {
    nodes: []Node,
    verts: []Vertex,
    visible: []bool,

    pub fn parse(allocator: Allocator, bytes: []const u8) ParseError!Model {
        var r = Reader{ .bytes = bytes };
        const magic = try r.take(4);
        if (!std.mem.eql(u8, magic, "WSM1")) return error.BadMagic;
        const version = try r.int(u32);
        if (version != 1) return error.BadVersion;
        const node_count = try r.int(u32);
        const vert_count = try r.int(u32);

        // 先用文件大小约束数量，避免恶意头部触发巨量分配
        if (@as(u64, vert_count) * 20 > bytes.len) return error.Truncated;
        if (@as(u64, node_count) * 36 > bytes.len) return error.Truncated;

        const nodes = try allocator.alloc(Node, node_count);
        var made: usize = 0;
        errdefer {
            for (nodes[0..made]) |n| allocator.free(n.name);
            allocator.free(nodes);
        }
        var expect_first: u32 = 0;
        while (made < node_count) {
            const name_len = try r.int(u16);
            const name = try r.take(name_len);
            const first = try r.int(u32);
            const count = try r.int(u32);
            var mm: [6]f32 = undefined;
            for (&mm) |*f| f.* = try r.f32le();
            if (count % 3 != 0) return error.BadRange;
            if (first != expect_first) return error.BadRange;
            const end = @as(u64, first) + count;
            if (end > vert_count) return error.BadRange;
            expect_first = @intCast(end);
            const owned = try allocator.dupe(u8, name);
            nodes[made] = .{ .name = owned, .first = first, .count = count, .min = mm[0..3].*, .max = mm[3..6].* };
            made += 1;
        }
        if (expect_first != vert_count) return error.BadRange;

        const vbytes = try r.take(@as(usize, vert_count) * 20);
        if (r.pos != bytes.len) return error.BadRange;

        const verts = try allocator.alloc(Vertex, vert_count);
        errdefer allocator.free(verts);
        for (verts, 0..) |*v, i| {
            const s = vbytes[i * 20 ..][0..20];
            v.* = .{
                .x = @bitCast(std.mem.readInt(u32, s[0..4], .little)),
                .y = @bitCast(std.mem.readInt(u32, s[4..8], .little)),
                .z = @bitCast(std.mem.readInt(u32, s[8..12], .little)),
                .nx = @bitCast(s[12]),
                .ny = @bitCast(s[13]),
                .nz = @bitCast(s[14]),
                .pad = s[15],
                .r = s[16],
                .g = s[17],
                .b = s[18],
                .a = s[19],
            };
        }
        const visible = try allocator.alloc(bool, node_count);
        @memset(visible, true);
        return .{ .nodes = nodes, .verts = verts, .visible = visible };
    }

    pub fn deinit(self: *Model, allocator: Allocator) void {
        for (self.nodes) |n| allocator.free(n.name);
        allocator.free(self.nodes);
        allocator.free(self.verts);
        allocator.free(self.visible);
        self.* = .{ .nodes = &.{}, .verts = &.{}, .visible = &.{} };
    }

    pub fn findNode(self: *const Model, name: []const u8) ?usize {
        for (self.nodes, 0..) |n, i| {
            if (std.mem.eql(u8, n.name, name)) return i;
        }
        return null;
    }

    /// pattern：完整节点名，或以 `*` 结尾的前缀（`*` 单独 = 全部）。返回匹配的节点数。
    pub fn setVisible(self: *Model, pattern: []const u8, on: bool) u32 {
        var n: u32 = 0;
        const prefix_mode = pattern.len > 0 and pattern[pattern.len - 1] == '*';
        const prefix = if (prefix_mode) pattern[0 .. pattern.len - 1] else pattern;
        for (self.nodes, 0..) |node, i| {
            const hit = if (prefix_mode) std.mem.startsWith(u8, node.name, prefix) else std.mem.eql(u8, node.name, prefix);
            if (!hit) continue;
            self.visible[i] = on;
            n += 1;
        }
        return n;
    }

    pub fn triCount(self: *const Model) u32 {
        var t: u32 = 0;
        for (self.nodes) |n| t += n.count / 3;
        return t;
    }

    pub fn visibleTris(self: *const Model) u32 {
        var t: u32 = 0;
        for (self.nodes, self.visible) |n, v| {
            if (v) t += n.count / 3;
        }
        return t;
    }
};

/// 朝向明暗：光从左上（-X / -Z 偏上）来，范围 [0.55, 1.0]。
pub fn shade(nx: i8, ny: i8, nz: i8) f32 {
    const fx = @as(f32, @floatFromInt(nx)) / 127.0;
    const fy = @as(f32, @floatFromInt(ny)) / 127.0;
    const fz = @as(f32, @floatFromInt(nz)) / 127.0;
    const l = [3]f32{ -0.3311, 0.8830, -0.3311 }; // 归一化 (-0.3, 0.8, -0.3)
    const d = std.math.clamp(fx * l[0] + fy * l[1] + fz * l[2], -1.0, 1.0);
    return 0.775 + 0.225 * d;
}
