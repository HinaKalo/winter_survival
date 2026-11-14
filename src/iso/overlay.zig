//! 纯逻辑：地面覆盖层（FOV 锥形、迷雾贴花、血迹/脚印贴花）。
const std = @import("std");
const Allocator = std.mem.Allocator;
const vision = @import("vision.zig");

pub const max_groups = 16;
pub const max_cells = 8192;

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
        const gx = std.math.cast(i16, x) orelse return;
        const gy = std.math.cast(i16, y) orelse return;
        self.groups[g].append(self.allocator, .{ .x = gx, .y = gy, .rgba = rgba, .atlas = atlas }) catch return;
        self.total += 1;
        self.dirty = true;
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
