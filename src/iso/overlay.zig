//! 纯逻辑：地面覆盖层（FOV 锥形、迷雾贴花、血迹/脚印贴花）。
const std = @import("std");
const Allocator = std.mem.Allocator;
const vision = @import("vision.zig");

pub const max_groups = 16;
pub const max_cells = 8192;
/// 图集格号上限（8x8 图集，0..63）；0xFFFF = 纯色。
pub const max_atlas_cells: u16 = 64;
/// 高亮格专用覆盖层组（最后一组）。
pub const highlight_group: u32 = 15;

pub const Cell = struct {
    x: i16,
    y: i16,
    rgba: [4]u8,
    atlas: u16 = 0xFFFF, // 地块图集格号；0xFFFF = 纯色
};

pub const Overlays = struct {
    allocator: Allocator,
    groups: [max_groups]std.ArrayList(Cell),
    total: u32 = 0,
    /// 因图集格越界/容量满而被拒绝的 addTex 次数（统计用）
    rejected_atlas: u32 = 0,
    dirty: bool = true,

    pub fn init(allocator: Allocator) Overlays {
        return .{
            .allocator = allocator,
            .groups = [_]std.ArrayList(Cell){.empty} ** max_groups,
        };
    }

    pub fn deinit(self: *Overlays) void {
        for (&self.groups) |*g| g.deinit(self.allocator);
        self.total = 0;
    }

    pub fn add(self: *Overlays, g: u32, x: i32, y: i32, rgba: [4]u8) void {
        self.addTex(g, x, y, 0xFFFF, rgba);
    }

    pub fn addTex(self: *Overlays, g: u32, x: i32, y: i32, atlas: u16, rgba: [4]u8) void {
        if (g >= max_groups or self.total >= max_cells) return;
        if (atlas != 0xFFFF and atlas >= max_atlas_cells) {
            self.rejected_atlas +%= 1;
            return;
        }
        const gx = std.math.cast(i16, x) orelse return;
        const gy = std.math.cast(i16, y) orelse return;
        self.groups[g].append(self.allocator, .{ .x = gx, .y = gy, .rgba = rgba, .atlas = atlas }) catch return;
        self.total += 1;
        self.dirty = true;
    }

    /// 组 g 只保留一个纯色格（高亮格用）；内容相同则不动，避免每帧重建覆盖层。
    pub fn setSingle(self: *Overlays, g: u32, x: i32, y: i32, rgba: [4]u8) void {
        if (g >= max_groups) return;
        const items = self.groups[g].items;
        if (items.len == 1 and items[0].x == x and items[0].y == y and items[0].atlas == 0xFFFF and
            std.mem.eql(u8, &items[0].rgba, &rgba)) return;
        self.clear(g);
        self.add(g, x, y, rgba);
    }

    pub fn addMask(self: *Overlays, g: u32, m: *const vision.Mask, rgba: [4]u8) void {
        if (g >= max_groups or m.count == 0) return;
        const x0 = @max(0, m.min_x);
        const y0 = @max(0, m.min_y);
        const x1 = @min(@as(i32, @intCast(m.w)) - 1, m.max_x);
        const y1 = @min(@as(i32, @intCast(m.h)) - 1, m.max_y);
        if (x0 > x1 or y0 > y1) return;
        var y = y0;
        while (y <= y1) : (y += 1) {
            var x = x0;
            while (x <= x1) : (x += 1) {
                if (self.total >= max_cells) return;
                if (m.get(x, y)) self.add(g, x, y, rgba);
            }
        }
    }

    pub fn clear(self: *Overlays, g: u32) void {
        if (g >= max_groups) return;
        const n: u32 = @intCast(self.groups[g].items.len);
        if (n == 0) return;
        self.groups[g].clearRetainingCapacity();
        self.total -|= n;
        self.dirty = true;
    }

    pub fn clearAll(self: *Overlays) void {
        for (&self.groups) |*g| g.clearRetainingCapacity();
        self.total = 0;
        self.dirty = true;
    }
};

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "overlays add, addMask, clear, and total cap" {
    var ov = Overlays.init(testing.allocator);
    defer ov.deinit();
    ov.add(0, 1, 2, .{ 255, 0, 0, 128 });
    ov.addTex(1, 3, 4, 62, .{ 255, 255, 255, 255 });
    try testing.expectEqual(@as(u32, 2), ov.total);

    var mask = try vision.Mask.init(testing.allocator, 8, 8);
    defer mask.deinit();
    mask.set(0, 0);
    mask.set(1, 0);
    ov.addMask(2, &mask, .{ 255, 200, 0, 80 });
    try testing.expectEqual(@as(u32, 4), ov.total);

    ov.clear(2);
    try testing.expectEqual(@as(u32, 2), ov.total);
    ov.clearAll();
    try testing.expectEqual(@as(u32, 0), ov.total);
}

test "overlays capacity limit and addTex atlas validation" {
    var ov = Overlays.init(testing.allocator);
    defer ov.deinit();
    ov.addTex(0, 0, 0, 63, .{ 1, 2, 3, 4 });
    ov.addTex(0, 1, 0, 0xFFFF, .{ 1, 2, 3, 4 });
    try testing.expectEqual(@as(u32, 2), ov.total);
    try testing.expectEqual(@as(u32, 0), ov.rejected_atlas);
    ov.addTex(0, 2, 0, 64, .{ 1, 2, 3, 4 });
    ov.addTex(0, 2, 0, 9999, .{ 1, 2, 3, 4 });
    try testing.expectEqual(@as(u32, 2), ov.total);
    try testing.expectEqual(@as(u32, 2), ov.rejected_atlas);
    // 组号越界、坐标越 i16 均忽略
    ov.add(16, 0, 0, .{ 0, 0, 0, 0 });
    ov.add(0, 40000, 0, .{ 0, 0, 0, 0 });
    try testing.expectEqual(@as(u32, 2), ov.total);

    ov.clearAll();
    var i: u32 = 0;
    while (i < max_cells + 100) : (i += 1) ov.add(i % max_groups, 0, 0, .{ 9, 9, 9, 9 });
    try testing.expectEqual(@as(u32, max_cells), ov.total);
    ov.clear(0);
    try testing.expect(ov.total < max_cells);
    ov.add(0, 0, 0, .{ 9, 9, 9, 9 }); // 腾出空间后可再加
    ov.clearAll();
    try testing.expectEqual(@as(u32, 0), ov.total);
    for (ov.groups) |g| try testing.expectEqual(@as(usize, 0), g.items.len);
}

test "setSingle replaces and is idempotent" {
    var ov = Overlays.init(testing.allocator);
    defer ov.deinit();
    ov.setSingle(highlight_group, 3, 4, .{ 1, 2, 3, 4 });
    ov.dirty = false;
    ov.setSingle(highlight_group, 3, 4, .{ 1, 2, 3, 4 });
    try testing.expect(!ov.dirty);
    ov.setSingle(highlight_group, 5, 4, .{ 1, 2, 3, 4 });
    try testing.expectEqual(@as(u32, 1), ov.total);
    try testing.expectEqual(@as(i16, 5), ov.groups[highlight_group].items[0].x);
}
