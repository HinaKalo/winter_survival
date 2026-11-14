//! 纯逻辑：视线判定 (LOS)、视野掩码 (Mask / MaskSet) 与锥形 FOV。
const std = @import("std");
const Allocator = std.mem.Allocator;
const tilemap = @import("tilemap.zig");
const TileMap = tilemap.TileMap;

pub const max_masks = 16;
pub const max_radius: i32 = 32;

pub const Mask = struct {
    allocator: Allocator,
    cells: []u8,
    w: u32,
    h: u32,
    count: u32 = 0,
    version: u32 = 0,
    min_x: i32 = 0,
    min_y: i32 = 0,
    max_x: i32 = -1,
    max_y: i32 = -1,

    pub fn init(allocator: Allocator, w: u32, h: u32) !Mask {
        const cells = try allocator.alloc(u8, @as(usize, w) * h);
        @memset(cells, 0);
        return .{ .allocator = allocator, .cells = cells, .w = w, .h = h };
    }

    pub fn deinit(self: *Mask) void {
        self.allocator.free(self.cells);
        self.cells = &.{};
        self.w = 0;
        self.h = 0;
        self.count = 0;
    }

    pub fn resize(self: *Mask, w: u32, h: u32) !void {
        const cells = try self.allocator.alloc(u8, @as(usize, w) * h);
        @memset(cells, 0);
        self.allocator.free(self.cells);
        self.cells = cells;
        self.w = w;
        self.h = h;
        self.count = 0;
        self.min_x = 0;
        self.min_y = 0;
        self.max_x = -1;
        self.max_y = -1;
        self.version +%= 1;
    }

    pub fn inBounds(self: *const Mask, x: i32, y: i32) bool {
        return x >= 0 and y >= 0 and x < @as(i32, @intCast(self.w)) and y < @as(i32, @intCast(self.h));
    }

    pub fn get(self: *const Mask, x: i32, y: i32) bool {
        if (!self.inBounds(x, y)) return false;
        const idx = @as(usize, @intCast(y)) * self.w + @as(usize, @intCast(x));
        return self.cells[idx] != 0;
    }

    pub fn set(self: *Mask, x: i32, y: i32) void {
        if (!self.inBounds(x, y)) return;
        const idx = @as(usize, @intCast(y)) * self.w + @as(usize, @intCast(x));
        if (self.cells[idx] != 0) return;
        self.cells[idx] = 1;
        self.count += 1;
        self.version +%= 1;
        if (self.max_x < self.min_x) {
            self.min_x = x;
            self.max_x = x;
            self.min_y = y;
            self.max_y = y;
        } else {
            if (x < self.min_x) self.min_x = x;
            if (x > self.max_x) self.max_x = x;
            if (y < self.min_y) self.min_y = y;
            if (y > self.max_y) self.max_y = y;
        }
    }

    pub fn clear(self: *Mask) void {
        if (self.count == 0) return;
        const x0: usize = @intCast(@max(0, self.min_x));
        const y0: usize = @intCast(@max(0, self.min_y));
        const x1: usize = @intCast(@min(@as(i32, @intCast(self.w)) - 1, self.max_x));
        const y1: usize = @intCast(@min(@as(i32, @intCast(self.h)) - 1, self.max_y));
        var y = y0;
        while (y <= y1) : (y += 1) {
            const row = y * self.w;
            @memset(self.cells[row + x0 .. row + x1 + 1], 0);
        }
        self.count = 0;
        self.min_x = 0;
        self.min_y = 0;
        self.max_x = -1;
        self.max_y = -1;
        self.version +%= 1;
    }

    pub fn orWith(self: *Mask, other: *const Mask) void {
        if (other.count == 0) return;
        const x0 = @max(0, other.min_x);
        const y0 = @max(0, other.min_y);
        const x1 = @min(@as(i32, @intCast(@min(self.w, other.w))) - 1, other.max_x);
        const y1 = @min(@as(i32, @intCast(@min(self.h, other.h))) - 1, other.max_y);
        if (x0 > x1 or y0 > y1) return;
        var y = y0;
        while (y <= y1) : (y += 1) {
            var x = x0;
            while (x <= x1) : (x += 1) {
                if (other.get(x, y)) self.set(x, y);
            }
        }
    }
};

pub const MaskSet = struct {
    masks: [max_masks]Mask,
    w: u32,
    h: u32,

    pub fn init(allocator: Allocator, w: u32, h: u32) !MaskSet {
        var set: MaskSet = .{ .masks = undefined, .w = w, .h = h };
        var inited_n: usize = 0;
        errdefer for (set.masks[0..inited_n]) |*m| m.deinit();
        for (&set.masks) |*m| {
            m.* = try Mask.init(allocator, w, h);
            inited_n += 1;
        }
        return set;
    }

    pub fn deinit(self: *MaskSet) void {
        for (&self.masks) |*m| m.deinit();
    }

    pub fn resize(self: *MaskSet, w: u32, h: u32) !void {
        for (&self.masks) |*m| try m.resize(w, h);
        self.w = w;
        self.h = h;
    }

    pub fn get(self: *MaskSet, id: u32) ?*Mask {
        if (id < 1 or id > max_masks) return null;
        return &self.masks[id - 1];
    }

    pub fn getConst(self: *const MaskSet, id: u32) ?*const Mask {
        if (id < 1 or id > max_masks) return null;
        return &self.masks[id - 1];
    }
};

pub const Cone = struct {
    fx: f32 = 0,
    fy: f32 = 0,
    half_angle_deg: f32 = 180,
};

/// 对称 Bresenham 视线判定：任意端点越界返回 false；2×2 墙角斜穿时若两侧皆不透明则阻挡。
pub fn los(map: *const TileMap, x0: i32, y0: i32, x1: i32, y1: i32) bool {
    if (!map.inBounds(x0, y0) or !map.inBounds(x1, y1)) return false;
    if (x0 == x1 and y0 == y1) return true;

    // 规范化起止点方向，保证 los(a, b) == los(b, a)
    var ax = x0;
    var ay = y0;
    var bx = x1;
    var by = y1;
    if (ax > bx or (ax == bx and ay > by)) {
        std.mem.swap(i32, &ax, &bx);
        std.mem.swap(i32, &ay, &by);
    }

    const dx: i32 = @intCast(@abs(bx - ax));
    const dy: i32 = @intCast(@abs(by - ay));
    const sx: i32 = if (ax < bx) 1 else -1;
    const sy: i32 = if (ay < by) 1 else -1;
    var err: i32 = dx - dy;
    var cx = ax;
    var cy = ay;

    while (cx != bx or cy != by) {
        const e2 = err * 2;
        const step_x = e2 > -dy;
        const step_y = e2 < dx;
        const px = cx;
        const py = cy;
        if (step_x) {
            err -= dy;
            cx += sx;
        }
        if (step_y) {
            err += dx;
            cy += sy;
        }
        if (step_x and step_y) {
            if (map.isOpaque(cx, py) and map.isOpaque(px, cy)) return false;
        }
        if (cx == bx and cy == by) break;
        if (map.isOpaque(cx, cy)) return false;
    }
    return true;
}

pub fn canSee(map: *const TileMap, ox: i32, oy: i32, radius: f32, cone: Cone, tx: i32, ty: i32) bool {
    if (!std.math.isFinite(radius) or radius < 0) return false;
    if (!map.inBounds(ox, oy) or !map.inBounds(tx, ty)) return false;

    const dx: f32 = @floatFromInt(tx - ox);
    const dy: f32 = @floatFromInt(ty - oy);
    const d2 = dx * dx + dy * dy;
    if (d2 > radius * radius) return false;
    if (dx == 0 and dy == 0) return true;

    if (std.math.isFinite(cone.half_angle_deg) and cone.half_angle_deg < 180.0) {
        if (cone.half_angle_deg <= 0.0) return false;
        const flen2 = cone.fx * cone.fx + cone.fy * cone.fy;
        if (flen2 > 0) {
            const cos_half = @cos(cone.half_angle_deg * (std.math.pi / 180.0));
            const dot = dx * cone.fx + dy * cone.fy;
            if (cos_half >= 0) {
                if (dot < 0) return false;
                if (dot * dot < cos_half * cos_half * d2 * flen2) return false;
            } else if (dot < 0) {
                if (dot * dot > cos_half * cos_half * d2 * flen2) return false;
            }
        }
    }

    return los(map, ox, oy, tx, ty);
}

pub fn fov(map: *const TileMap, ox: i32, oy: i32, radius: f32, cone: Cone, mask: *Mask) u32 {
    if (!std.math.isFinite(radius) or radius < 0) return 0;
    if (!map.inBounds(ox, oy)) return 0;
    const r = @min(radius, @as(f32, @floatFromInt(max_radius)));
    const ri: i32 = @intFromFloat(@ceil(r));
    const x0 = @max(0, ox - ri);
    const y0 = @max(0, oy - ri);
    const x1 = @min(@as(i32, @intCast(@min(map.width, mask.w))) - 1, ox + ri);
    const y1 = @min(@as(i32, @intCast(@min(map.height, mask.h))) - 1, oy + ri);
    if (x0 > x1 or y0 > y1) return 0;

    var added: u32 = 0;
    var y = y0;
    while (y <= y1) : (y += 1) {
        var x = x0;
        while (x <= x1) : (x += 1) {
            if (!mask.get(x, y) and canSee(map, ox, oy, r, cone, x, y)) {
                mask.set(x, y);
                added += 1;
            }
        }
    }
    return added;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "los symmetry, bounds, and 2x2 corner blocking" {
    var m = try TileMap.init(testing.allocator, 8, 8);
    defer m.deinit();
    const floor = try m.defineTile(.{ .top = 1, .side = 1 });
    const wall = try m.defineTile(.{ .top = 2, .side = 2, .solid = true, .@"opaque" = true });
    m.fill(floor, 0);
    m.set(2, 1, wall, 4);
    m.set(1, 2, wall, 4);

    // 越界端返回 false
    try testing.expect(!los(&m, -1, 0, 2, 2));
    try testing.expect(!los(&m, 1, 1, 8, 2));

    // 2x2 墙角不可斜穿
    try testing.expect(!los(&m, 1, 1, 2, 2));
    try testing.expect(!los(&m, 2, 2, 1, 1));

    // 对称性检查
    var y: i32 = 0;
    while (y < 6) : (y += 1) {
        var x: i32 = 0;
        while (x < 6) : (x += 1) {
            try testing.expectEqual(los(&m, 0, 0, x, y), los(&m, x, y, 0, 0));
        }
    }
}

test "cone fov and mask merge" {
    var m = try TileMap.init(testing.allocator, 12, 12);
    defer m.deinit();
    const floor = try m.defineTile(.{ .top = 1, .side = 1 });
    m.fill(floor, 0);

    var set = try MaskSet.init(testing.allocator, 12, 12);
    defer set.deinit();
    const m1 = set.get(1).?;
    const m2 = set.get(2).?;

    // 全向视野
    _ = fov(&m, 5, 5, 3.0, .{ .half_angle_deg = 180 }, m1);
    try testing.expect(m1.get(5, 5));
    try testing.expect(m1.get(2, 5));
    try testing.expect(m1.get(8, 5));

    // 朝东 45 度半角锥形
    _ = fov(&m, 5, 5, 4.0, .{ .fx = 1, .fy = 0, .half_angle_deg = 45 }, m2);
    try testing.expect(m2.get(8, 5));
    try testing.expect(!m2.get(2, 5));
    try testing.expect(!m2.get(5, 8));

    const before = m2.count;
    m2.orWith(m1);
    try testing.expect(m2.count > before);
    try testing.expect(m2.get(2, 5));
}
