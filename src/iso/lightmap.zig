//! 纯逻辑：2D 网格光照（环境光 + 动态点光源 + LOS 遮挡 + 三态战争迷雾）。
const std = @import("std");
const Allocator = std.mem.Allocator;
const tilemap = @import("tilemap.zig");
const vision = @import("vision.zig");
const TileMap = tilemap.TileMap;
const MaskSet = vision.MaskSet;

pub const max_lights = 64;
pub const max_light_radius: i32 = 16;

pub const Light = struct {
    used: bool = false,
    enabled: bool = true,
    x: f32 = 0,
    z: f32 = 0,
    radius: f32 = 1,
    color: [3]f32 = .{ 1, 1, 1 },
    dirty: bool = true,
};

pub const Fog = struct {
    visible: u32 = 0,
    explored: u32 = 0,
    explored_k: f32 = 0.4,
    unknown_k: f32 = 0.0,
};

pub const LightMap = struct {
    allocator: Allocator,
    w: u32,
    h: u32,
    ambient: [3]u8 = .{ 255, 255, 255 },
    fog: Fog = .{},
    rgb: [][3]u8,
    lit: [][3]u8,
    lights: [max_lights]Light = [_]Light{.{}} ** max_lights,
    dirty_all: bool = true,
    last_opacity_version: u32 = 0,
    last_vis_ver: u32 = 0,
    last_exp_ver: u32 = 0,

    pub fn init(allocator: Allocator, w: u32, h: u32) !LightMap {
        const n = @as(usize, w) * h;
        const rgb = try allocator.alloc([3]u8, n);
        errdefer allocator.free(rgb);
        const lit = try allocator.alloc([3]u8, n);
        @memset(rgb, .{ 255, 255, 255 });
        @memset(lit, .{ 255, 255, 255 });
        return .{ .allocator = allocator, .w = w, .h = h, .rgb = rgb, .lit = lit };
    }

    pub fn deinit(self: *LightMap) void {
        self.allocator.free(self.rgb);
        self.allocator.free(self.lit);
        self.rgb = &.{};
        self.lit = &.{};
    }

    pub fn resize(self: *LightMap, w: u32, h: u32) !void {
        const n = @as(usize, w) * h;
        const rgb = try self.allocator.alloc([3]u8, n);
        errdefer self.allocator.free(rgb);
        const lit = try self.allocator.alloc([3]u8, n);
        @memset(rgb, self.ambient);
        @memset(lit, self.ambient);
        self.allocator.free(self.rgb);
        self.allocator.free(self.lit);
        self.rgb = rgb;
        self.lit = lit;
        self.w = w;
        self.h = h;
        self.dirty_all = true;
    }

    pub fn add(self: *LightMap, l: Light) u32 {
        for (&self.lights, 0..) |*slot, i| {
            if (!slot.used) {
                slot.* = l;
                slot.used = true;
                slot.dirty = true;
                self.dirty_all = true;
                return @intCast(i + 1);
            }
        }
        return 0;
    }

    pub fn get(self: *LightMap, id: u32) ?*Light {
        if (id < 1 or id > max_lights) return null;
        const l = &self.lights[id - 1];
        if (!l.used) return null;
        return l;
    }

    pub fn remove(self: *LightMap, id: u32) void {
        const l = self.get(id) orelse return;
        l.* = .{};
        self.dirty_all = true;
    }

    pub fn clear(self: *LightMap) void {
        self.lights = [_]Light{.{}} ** max_lights;
        self.dirty_all = true;
    }

    pub fn setAmbient(self: *LightMap, r: f32, g: f32, b: f32) void {
        const nr: u8 = @intFromFloat(std.math.clamp(if (std.math.isFinite(r)) r * 255.0 else 255.0, 0.0, 255.0));
        const ng: u8 = @intFromFloat(std.math.clamp(if (std.math.isFinite(g)) g * 255.0 else 255.0, 0.0, 255.0));
        const nb: u8 = @intFromFloat(std.math.clamp(if (std.math.isFinite(b)) b * 255.0 else 255.0, 0.0, 255.0));
        if (self.ambient[0] != nr or self.ambient[1] != ng or self.ambient[2] != nb) {
            self.ambient = .{ nr, ng, nb };
            self.dirty_all = true;
        }
    }

    pub fn update(self: *LightMap, map: *TileMap, masks: *const MaskSet) u32 {
        const vis_m = masks.getConst(self.fog.visible);
        const exp_m = masks.getConst(self.fog.explored);
        const vis_ver: u32 = if (vis_m) |m| m.version else 0;
        const exp_ver: u32 = if (exp_m) |m| m.version else 0;

        var any_light_dirty = false;
        for (self.lights) |l| {
            if (l.used and l.dirty) {
                any_light_dirty = true;
                break;
            }
        }
        if (!self.dirty_all and !any_light_dirty and
            self.last_opacity_version == map.opacity_version and
            self.last_vis_ver == vis_ver and
            self.last_exp_ver == exp_ver)
        {
            return 0;
        }

        // 先写入基础环境光
        const amb_r: f32 = @floatFromInt(self.ambient[0]);
        const amb_g: f32 = @floatFromInt(self.ambient[1]);
        const amb_b: f32 = @floatFromInt(self.ambient[2]);
        for (self.lit) |*c| c.* = self.ambient;

        // 叠加所有启用的点光源（受地图 LOS 遮挡）
        for (&self.lights) |*l| {
            if (!l.used or !l.enabled) {
                l.dirty = false;
                continue;
            }
            if (!std.math.isFinite(l.x) or !std.math.isFinite(l.z) or !std.math.isFinite(l.radius) or l.radius <= 0 or
                @abs(l.x) > 1e6 or @abs(l.z) > 1e6)
            {
                l.dirty = false;
                continue;
            }
            const r = @min(l.radius, @as(f32, @floatFromInt(max_light_radius)));
            const ri: i32 = @intFromFloat(@ceil(r));
            const ox: i32 = @intFromFloat(@floor(l.x));
            const oz: i32 = @intFromFloat(@floor(l.z));
            const x0 = @max(0, ox - ri);
            const y0 = @max(0, oz - ri);
            const x1 = @min(@as(i32, @intCast(self.w)) - 1, ox + ri);
            const y1 = @min(@as(i32, @intCast(self.h)) - 1, oz + ri);
            if (x0 <= x1 and y0 <= y1) {
                var y = y0;
                while (y <= y1) : (y += 1) {
                    var x = x0;
                    while (x <= x1) : (x += 1) {
                        const dx = (@as(f32, @floatFromInt(x)) + 0.5) - l.x;
                        const dy = (@as(f32, @floatFromInt(y)) + 0.5) - l.z;
                        const dist = @sqrt(dx * dx + dy * dy);
                        if (dist >= r) continue;
                        if (map.inBounds(ox, oz) and !vision.los(map, ox, oz, x, y)) continue;
                        const att = (1.0 - dist / r);
                        const k = att * att * 255.0;
                        const idx = @as(usize, @intCast(y)) * self.w + @as(usize, @intCast(x));
                        const cur = self.lit[idx];
                        const cr = @as(f32, @floatFromInt(cur[0])) + @max(0.0, l.color[0]) * k;
                        const cg = @as(f32, @floatFromInt(cur[1])) + @max(0.0, l.color[1]) * k;
                        const cb = @as(f32, @floatFromInt(cur[2])) + @max(0.0, l.color[2]) * k;
                        self.lit[idx] = .{
                            @intFromFloat(std.math.clamp(cr, 0.0, 255.0)),
                            @intFromFloat(std.math.clamp(cg, 0.0, 255.0)),
                            @intFromFloat(std.math.clamp(cb, 0.0, 255.0)),
                        };
                    }
                }
            }
            l.dirty = false;
        }
        _ = amb_r;
        _ = amb_g;
        _ = amb_b;

        var changed: u32 = 0;
        var y: i32 = 0;
        while (y < @as(i32, @intCast(self.h))) : (y += 1) {
            var x: i32 = 0;
            while (x < @as(i32, @intCast(self.w))) : (x += 1) {
                const idx = @as(usize, @intCast(y)) * self.w + @as(usize, @intCast(x));
                const k: f32 = if (vis_m == null and exp_m == null)
                    1.0
                else if (vis_m != null and vis_m.?.get(x, y))
                    1.0
                else if (exp_m != null and exp_m.?.get(x, y))
                    self.fog.explored_k
                else
                    self.fog.unknown_k;

                const src = self.lit[idx];
                const next = [3]u8{
                    @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(src[0])) * k, 0.0, 255.0)),
                    @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(src[1])) * k, 0.0, 255.0)),
                    @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(src[2])) * k, 0.0, 255.0)),
                };
                if (!std.mem.eql(u8, &self.rgb[idx], &next)) {
                    self.rgb[idx] = next;
                    changed += 1;
                    map.markDirtyAround(x, y);
                }
            }
        }

        self.dirty_all = false;
        self.last_opacity_version = map.opacity_version;
        self.last_vis_ver = vis_ver;
        self.last_exp_ver = exp_ver;
        return changed;
    }

    pub fn level(self: *const LightMap, x: i32, y: i32) f32 {
        if (x < 0 or y < 0 or x >= @as(i32, @intCast(self.w)) or y >= @as(i32, @intCast(self.h))) return 0;
        const c = self.lit[@as(usize, @intCast(y)) * self.w + @as(usize, @intCast(x))];
        const m = @max(c[0], @max(c[1], c[2]));
        return @as(f32, @floatFromInt(m)) / 255.0;
    }

    pub fn sample(self: *const LightMap, x: i32, y: i32) [3]f32 {
        if (x < 0 or y < 0 or x >= @as(i32, @intCast(self.w)) or y >= @as(i32, @intCast(self.h))) {
            return .{
                @as(f32, @floatFromInt(self.ambient[0])) / 255.0,
                @as(f32, @floatFromInt(self.ambient[1])) / 255.0,
                @as(f32, @floatFromInt(self.ambient[2])) / 255.0,
            };
        }
        const c = self.rgb[@as(usize, @intCast(y)) * self.w + @as(usize, @intCast(x))];
        return .{
            @as(f32, @floatFromInt(c[0])) / 255.0,
            @as(f32, @floatFromInt(c[1])) / 255.0,
            @as(f32, @floatFromInt(c[2])) / 255.0,
        };
    }
};

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "lightmap occlusion, fog states, and cache hit" {
    var m = try TileMap.init(testing.allocator, 10, 10);
    defer m.deinit();
    const floor = try m.defineTile(.{ .top = 1, .side = 1 });
    const wall = try m.defineTile(.{ .top = 2, .side = 2, .solid = true, .@"opaque" = true });
    m.fill(floor, 0);
    m.set(5, 5, wall, 6);

    var masks = try MaskSet.init(testing.allocator, 10, 10);
    defer masks.deinit();
    masks.get(1).?.set(2, 5); // visible
    masks.get(2).?.set(8, 5); // explored

    var lm = try LightMap.init(testing.allocator, 10, 10);
    defer lm.deinit();
    lm.setAmbient(0.1, 0.1, 0.2);
    lm.fog = .{ .visible = 1, .explored = 2, .explored_k = 0.4, .unknown_k = 0.0 };
    _ = lm.add(.{ .x = 2.5, .z = 5.5, .radius = 8, .color = .{ 1, 0.6, 0.2 } });

    const c1 = lm.update(&m, &masks);
    try testing.expect(c1 > 0);
    try testing.expect(lm.level(2, 5) > 0.5);
    // 墙后受遮挡，只有环境光
    try testing.expect(lm.level(7, 5) < 0.25);
    // 可见格全亮，未知格为 0
    try testing.expect(lm.sample(2, 5)[0] > 0.5);
    try testing.expectEqual(@as(f32, 0.0), lm.sample(0, 0)[0]);
    // 再次更新无变化返回 0
    try testing.expectEqual(@as(u32, 0), lm.update(&m, &masks));
}

test "no lights leaves only ambient" {
    var m = try TileMap.init(testing.allocator, 12, 12);
    defer m.deinit();
    const floor = try m.defineTile(.{ .top = 1, .side = 1 });
    const wall = try m.defineTile(.{ .top = 2, .side = 2, .solid = true, .@"opaque" = true });
    m.fill(floor, 0);
    m.set(3, 3, wall, 4);

    var lm = try LightMap.init(testing.allocator, 12, 12);
    defer lm.deinit();
    lm.setAmbient(0.2, 0.3, 0.4);
    var masks = try MaskSet.init(testing.allocator, 12, 12);
    defer masks.deinit();

    _ = lm.update(&m, &masks);
    // 无可见性掩码时 lit 应与 ambient 完全一致
    for (lm.lit) |c| try testing.expectEqualSlices(u8, &lm.ambient, &c);
    for (lm.rgb) |c| try testing.expectEqualSlices(u8, &lm.ambient, &c);

    const s = lm.sample(5, 5);
    try testing.expectApproxEqAbs(@as(f32, 0.2), s[0], 1.0 / 255.0);
    try testing.expectApproxEqAbs(@as(f32, 0.3), s[1], 1.0 / 255.0);
    try testing.expectApproxEqAbs(@as(f32, 0.4), s[2], 1.0 / 255.0);
    try testing.expectApproxEqAbs(@as(f32, 0.4), lm.level(5, 5), 1.0 / 255.0);

    // 禁用的光源也不产生光照
    lm.setAmbient(0, 0, 0);
    const id = lm.add(.{ .x = 5.5, .z = 5.5, .radius = 4, .enabled = false });
    try testing.expect(id != 0);
    _ = lm.update(&m, &masks);
    try testing.expectEqual(@as(f32, 0), lm.level(5, 5));
}

test "moving a light updates affected cells and clears old ones" {
    var m = try TileMap.init(testing.allocator, 24, 24);
    defer m.deinit();
    const floor = try m.defineTile(.{ .top = 1, .side = 1 });
    m.fill(floor, 0);

    var lm = try LightMap.init(testing.allocator, 24, 24);
    defer lm.deinit();
    lm.setAmbient(0, 0, 0);
    var masks = try MaskSet.init(testing.allocator, 24, 24);
    defer masks.deinit();

    const id = lm.add(.{ .x = 4.5, .z = 4.5, .radius = 3, .color = .{ 1, 1, 1 } });
    try testing.expect(id != 0);
    _ = lm.update(&m, &masks);
    try testing.expect(lm.level(4, 4) > 0.5);
    try testing.expectEqual(@as(f32, 0), lm.level(20, 20));
    try testing.expect(!lm.get(id).?.dirty);

    // 移动光源到另一角
    const before = try testing.allocator.dupe([3]u8, lm.rgb);
    defer testing.allocator.free(before);
    const l = lm.get(id).?;
    l.x = 19.5;
    l.z = 19.5;
    l.dirty = true;

    const changed = lm.update(&m, &masks);
    try testing.expect(changed > 0);
    try testing.expect(changed < 24 * 24);

    // 返回值 == 实际变化格数
    var diff: u32 = 0;
    for (before, lm.rgb) |a, b| {
        if (!std.mem.eql(u8, &a, &b)) diff += 1;
    }
    try testing.expectEqual(diff, changed);

    // 旧位置被清空，新位置被照亮
    try testing.expectEqual(@as(f32, 0), lm.level(4, 4));
    try testing.expect(lm.level(19, 19) > 0.5);
    try testing.expect(!lm.get(id).?.dirty);

    // 无变化再次更新返回 0
    try testing.expectEqual(@as(u32, 0), lm.update(&m, &masks));
}

test "flipping a cell opaque and back changes lit result after update" {
    var m = try TileMap.init(testing.allocator, 12, 12);
    defer m.deinit();
    const floor = try m.defineTile(.{ .top = 1, .side = 1 });
    m.fill(floor, 0);

    var lm = try LightMap.init(testing.allocator, 12, 12);
    defer lm.deinit();
    lm.setAmbient(0, 0, 0);
    var masks = try MaskSet.init(testing.allocator, 12, 12);
    defer masks.deinit();
    _ = lm.add(.{ .x = 2.5, .z = 5.5, .radius = 8 });

    _ = lm.update(&m, &masks);
    try testing.expect(lm.level(6, 5) > 0.1);

    // 中间格变不透明：后方被遮挡
    m.setFlag(4, 5, tilemap.Flag.@"opaque", true);
    try testing.expect(lm.update(&m, &masks) > 0);
    try testing.expectEqual(@as(f32, 0), lm.level(6, 5));
    // 墙格本身作为终点仍被照亮
    try testing.expect(lm.level(4, 5) > 0.1);

    // 恢复透明：后方重新被照亮
    m.setFlag(4, 5, tilemap.Flag.@"opaque", false);
    try testing.expect(lm.update(&m, &masks) > 0);
    try testing.expect(lm.level(6, 5) > 0.1);
    try testing.expectEqual(@as(u32, 0), lm.update(&m, &masks));
}

test "65th light is rejected and first 64 stay intact" {
    try testing.expectEqual(@as(usize, 64), max_lights);
    var m = try TileMap.init(testing.allocator, 40, 40);
    defer m.deinit();
    const floor = try m.defineTile(.{ .top = 1, .side = 1 });
    m.fill(floor, 0);

    var lm = try LightMap.init(testing.allocator, 40, 40);
    defer lm.deinit();
    lm.setAmbient(0, 0, 0);
    var masks = try MaskSet.init(testing.allocator, 40, 40);
    defer masks.deinit();

    // 8×8 网格布置 64 盏光源，半径 2，彼此不重叠
    var i: u32 = 0;
    while (i < max_lights) : (i += 1) {
        const x: f32 = @as(f32, @floatFromInt(i % 8)) * 4.0 + 2.5;
        const z: f32 = @as(f32, @floatFromInt(i / 8)) * 4.0 + 2.5;
        const id = lm.add(.{ .x = x, .z = z, .radius = 2, .color = .{ 1, 1, 1 } });
        try testing.expectEqual(i + 1, id);
    }
    _ = lm.update(&m, &masks);
    try testing.expect(lm.level(2, 2) > 0.9);
    try testing.expect(lm.level(30, 30) > 0.9);
    try testing.expectEqual(@as(f32, 0), lm.level(4, 4));

    const snapshot = try testing.allocator.dupe([3]u8, lm.lit);
    defer testing.allocator.free(snapshot);

    // 第 65 盏被拒绝
    try testing.expectEqual(@as(u32, 0), lm.add(.{ .x = 4.5, .z = 4.5, .radius = 2, .color = .{ 1, 0, 0 } }));
    try testing.expectEqual(@as(u32, 0), lm.update(&m, &masks));
    try testing.expectEqualSlices([3]u8, snapshot, lm.lit);
    try testing.expectEqual(@as(f32, 0), lm.level(4, 4));

    // 前 64 盏数据未被破坏
    var id: u32 = 1;
    while (id <= max_lights) : (id += 1) {
        const l = lm.get(id) orelse return error.TestUnexpectedResult;
        try testing.expect(l.used);
        try testing.expectEqual(@as(f32, 2.5 + @as(f32, @floatFromInt((id - 1) % 8)) * 4.0), l.x);
    }
    try testing.expect(lm.get(max_lights + 1) == null);
}
