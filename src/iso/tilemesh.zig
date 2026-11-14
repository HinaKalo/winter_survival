//! 纯逻辑：分块地图网格生成（Quad 列表、墙檐 side_cap、平滑角点光、视锥剔除）。
const std = @import("std");
const delve = @import("delve");
const Vec3 = delve.math.Vec3;
const Allocator = std.mem.Allocator;
const tilemap = @import("tilemap.zig");
const camera = @import("camera.zig");
const TileMap = tilemap.TileMap;
const IsoCamera = camera.IsoCamera;

pub const Quad = struct {
    p: [4][3]f32, // BL, BR, TR, TL（世界坐标）
    atlas: u16,
    v_top: f32,
    v_bot: f32,
    c: [4][3]u8,
};

pub const Params = struct {
    side_levels: u8 = 2,
    light_top: f32 = 1.0,
    light_x: f32 = 0.78,
    light_z: f32 = 0.62,
};

pub const Aabb = struct { min: Vec3, max: Vec3 };

fn scaleColor(rgb: [3]u8, factor: f32) [3]u8 {
    return .{
        @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(rgb[0])) * factor, 0.0, 255.0)),
        @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(rgb[1])) * factor, 0.0, 255.0)),
        @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(rgb[2])) * factor, 0.0, 255.0)),
    };
}

/// 顶面角点 (cx, cy) 的平滑光照：只平均与 ref_height 相同高度的相邻格子，不同高不混色。
pub fn cornerLight(map: *const TileMap, rgb: []const [3]u8, cx: i32, cy: i32, ref_height: u8, fallback: [3]u8) [3]u8 {
    var sum = [3]u32{ 0, 0, 0 };
    var cnt: u32 = 0;
    const offsets = [4][2]i32{ .{ -1, -1 }, .{ 0, -1 }, .{ -1, 0 }, .{ 0, 0 } };
    for (offsets) |o| {
        const gx = cx + o[0];
        const gy = cy + o[1];
        const t = map.get(gx, gy) orelse continue;
        if (t.kind == 0 or t.height != ref_height) continue;
        const idx = @as(usize, @intCast(gy)) * map.width + @as(usize, @intCast(gx));
        const col = if (idx < rgb.len) rgb[idx] else fallback;
        sum[0] += col[0];
        sum[1] += col[1];
        sum[2] += col[2];
        cnt += 1;
    }
    if (cnt == 0) return fallback;
    return .{
        @intCast(sum[0] / cnt),
        @intCast(sum[1] / cnt),
        @intCast(sum[2] / cnt),
    };
}

pub fn buildChunk(
    allocator: Allocator,
    map: *const TileMap,
    rgb: []const [3]u8,
    cx: u32,
    cy: u32,
    params: Params,
    out: *std.ArrayList(Quad),
) !void {
    out.clearRetainingCapacity();
    const x0 = cx * tilemap.chunk_size;
    const y0 = cy * tilemap.chunk_size;
    const x1 = @min(map.width, x0 + tilemap.chunk_size);
    const y1 = @min(map.height, y0 + tilemap.chunk_size);
    if (x0 >= x1 or y0 >= y1) return;

    const side_levels = @max(@as(u8, 1), params.side_levels);
    const seg_h = @as(f32, @floatFromInt(side_levels)) * map.height_unit;

    var gy_u = y0;
    while (gy_u < y1) : (gy_u += 1) {
        var gx_u = x0;
        while (gx_u < x1) : (gx_u += 1) {
            const gx: i32 = @intCast(gx_u);
            const gy: i32 = @intCast(gy_u);
            const tile = map.get(gx, gy).?;
            const def = map.getDef(tile.kind) orelse continue;
            const top = map.topY(gx, gy);
            const fx: f32 = @floatFromInt(gx);
            const fz: f32 = @floatFromInt(gy);

            const idx = gy_u * map.width + gx_u;
            const cell_rgb = if (idx < rgb.len) rgb[idx] else [3]u8{ 255, 255, 255 };

            // 顶面：BL(gx,top,gy+1), BR(gx+1,top,gy+1), TR(gx+1,top,gy), TL(gx,top,gy)
            const c_bl = scaleColor(cornerLight(map, rgb, gx, gy + 1, tile.height, cell_rgb), params.light_top);
            const c_br = scaleColor(cornerLight(map, rgb, gx + 1, gy + 1, tile.height, cell_rgb), params.light_top);
            const c_tr = scaleColor(cornerLight(map, rgb, gx + 1, gy, tile.height, cell_rgb), params.light_top);
            const c_tl = scaleColor(cornerLight(map, rgb, gx, gy, tile.height, cell_rgb), params.light_top);
            try out.append(allocator, .{
                .p = .{
                    .{ fx, top, fz + 1 },
                    .{ fx + 1, top, fz + 1 },
                    .{ fx + 1, top, fz },
                    .{ fx, top, fz },
                },
                .atlas = def.top,
                .v_top = 0,
                .v_bot = 1,
                .c = .{ c_bl, c_br, c_tr, c_tl },
            });

            // 四个侧面
            const Side = struct { dx: i32, dy: i32, p0: [2]f32, p1: [2]f32, light: f32 };
            const sides = [4]Side{
                .{ .dx = 1, .dy = 0, .p0 = .{ fx + 1, fz + 1 }, .p1 = .{ fx + 1, fz }, .light = params.light_x },
                .{ .dx = -1, .dy = 0, .p0 = .{ fx, fz }, .p1 = .{ fx, fz + 1 }, .light = params.light_x },
                .{ .dx = 0, .dy = 1, .p0 = .{ fx, fz + 1 }, .p1 = .{ fx + 1, fz + 1 }, .light = params.light_z },
                .{ .dx = 0, .dy = -1, .p0 = .{ fx + 1, fz }, .p1 = .{ fx, fz }, .light = params.light_z },
            };
            for (sides) |s| {
                const nx = gx + s.dx;
                const ny = gy + s.dy;
                // 邻格为空/越界：视为地面（topY=0 / -base_depth），光照只用本格角点。
                const nb_top: f32 = if (!map.inBounds(nx, ny)) -map.base_depth else map.topY(nx, ny);
                if (nb_top >= top) continue;

                // 角点光（ENGINE-PLAN §A1-12）：取朝向邻格在该角的角点光（以邻格高度为基准、
                // 邻格 rgb 为回退）；邻格越界或为空时用本格高度与本格 rgb。竖直边上两端同色。
                var ref_h = tile.height;
                var fb = cell_rgb;
                if (map.get(nx, ny)) |nt| {
                    if (nt.kind != 0) {
                        ref_h = nt.height;
                        const nidx = @as(usize, @intCast(ny)) * map.width + @as(usize, @intCast(nx));
                        fb = if (nidx < rgb.len) rgb[nidx] else cell_rgb;
                    }
                }
                const k0 = scaleColor(cornerLight(map, rgb, @intFromFloat(s.p0[0]), @intFromFloat(s.p0[1]), ref_h, fb), s.light);
                const k1 = scaleColor(cornerLight(map, rgb, @intFromFloat(s.p1[0]), @intFromFloat(s.p1[1]), ref_h, fb), s.light);

                // 始终从 level 0 起按 side_levels 分段，保证贴图跨格对齐；
                // 完全藏在邻格内部的段（段顶 <= 邻格顶）剔除。
                const seg_count: u32 = (@as(u32, tile.height) + side_levels - 1) / side_levels;
                var si: u32 = 0;
                while (si < seg_count) : (si += 1) {
                    const sy = @as(f32, @floatFromInt(si)) * seg_h;
                    const seg = @min(seg_h, top - sy);
                    if (sy + seg <= nb_top + 1e-4) continue;
                    const frac = std.math.clamp(seg / seg_h, 0.0, 1.0);
                    try out.append(allocator, .{
                        .p = .{
                            .{ s.p0[0], sy, s.p0[1] },
                            .{ s.p1[0], sy, s.p1[1] },
                            .{ s.p1[0], sy + seg, s.p1[1] },
                            .{ s.p0[0], sy + seg, s.p0[1] },
                        },
                        .atlas = sideAtlas(def, si, seg_count),
                        // render.zig：v_top 对应世界顶点、v_bot 对应世界底点；
                        // 部分段保留贴图下半（地面线在世界底部）。
                        .v_top = 1.0 - frac,
                        .v_bot = 1.0,
                        .c = .{ k0, k1, k1, k0 },
                    });
                }

                // 地下裙边（越界邻格视为 -base_depth）：自 y=0 向下按段高分段，截到邻格顶。
                if (nb_top < 0) {
                    var hi: f32 = 0;
                    while (hi > nb_top + 1e-4) {
                        const lo = @max(hi - seg_h, nb_top);
                        const frac = std.math.clamp((hi - lo) / seg_h, 0.0, 1.0);
                        try out.append(allocator, .{
                            .p = .{
                                .{ s.p0[0], lo, s.p0[1] },
                                .{ s.p1[0], lo, s.p1[1] },
                                .{ s.p1[0], hi, s.p1[1] },
                                .{ s.p0[0], hi, s.p0[1] },
                            },
                            .atlas = def.side,
                            .v_top = 0,
                            .v_bot = frac,
                            .c = .{ k0, k1, k1, k0 },
                        });
                        hi = lo;
                    }
                }
            }
        }
    }
}

/// 侧面分段图集格：只有一段时 side_base > side_cap > side；
/// 否则第 0 段 side_base，最上段 side_cap，其余 side（缺省都回退 side）。
pub fn sideAtlas(def: tilemap.TileDef, seg: u32, seg_count: u32) u16 {
    const none: u16 = 0xFFFF;
    if (seg_count <= 1) {
        if (def.side_base != none) return def.side_base;
        if (def.side_cap != none) return def.side_cap;
        return def.side;
    }
    if (seg == 0 and def.side_base != none) return def.side_base;
    if (seg + 1 == seg_count and def.side_cap != none) return def.side_cap;
    return def.side;
}

pub fn chunkBounds(map: *const TileMap, cx: u32, cy: u32) Aabb {
    const x0 = cx * tilemap.chunk_size;
    const y0 = cy * tilemap.chunk_size;
    const x1 = @min(map.width, x0 + tilemap.chunk_size);
    const y1 = @min(map.height, y0 + tilemap.chunk_size);
    var max_y: f32 = 0;
    var y = y0;
    while (y < y1) : (y += 1) {
        var x = x0;
        while (x < x1) : (x += 1) {
            max_y = @max(max_y, map.topY(@intCast(x), @intCast(y)));
        }
    }
    return .{
        .min = Vec3.new(@floatFromInt(x0), -map.base_depth, @floatFromInt(y0)),
        .max = Vec3.new(@floatFromInt(x1), max_y + 0.5, @floatFromInt(y1)),
    };
}

pub fn chunkVisible(cam: *const IsoCamera, box: Aabb) bool {
    const ext = cam.halfExtents();
    const right = cam.right();
    const up = right.cross(cam.forward()).norm();
    var min_rx: f32 = std.math.inf(f32);
    var max_rx: f32 = -std.math.inf(f32);
    var min_ry: f32 = std.math.inf(f32);
    var max_ry: f32 = -std.math.inf(f32);

    const xs = [2]f32{ box.min.x, box.max.x };
    const ys = [2]f32{ box.min.y, box.max.y };
    const zs = [2]f32{ box.min.z, box.max.z };
    for (xs) |x| {
        for (ys) |y| {
            for (zs) |z| {
                const d = Vec3.new(x, y, z).sub(cam.target);
                const rx = d.dot(right);
                const ry = d.dot(up);
                min_rx = @min(min_rx, rx);
                max_rx = @max(max_rx, rx);
                min_ry = @min(min_ry, ry);
                max_ry = @max(max_ry, ry);
            }
        }
    }
    return max_rx >= -ext.x and min_rx <= ext.x and max_ry >= -ext.y and min_ry <= ext.y;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "tilemesh quad count, side_cap, odd height V clip, and cornerLight" {
    var m = try TileMap.init(testing.allocator, 16, 16);
    defer m.deinit();
    const floor = try m.defineTile(.{ .top = 0, .side = 48 });
    const wall = try m.defineTile(.{ .top = 52, .side = 24, .side_cap = 60, .solid = true, .@"opaque" = true });
    m.fill(floor, 0);

    var rgb = try testing.allocator.alloc([3]u8, 16 * 16);
    defer testing.allocator.free(rgb);
    @memset(rgb, .{ 200, 200, 200 });

    var out: std.ArrayList(Quad) = .empty;
    defer out.deinit(testing.allocator);

    // 平地 16x16（忽略边缘外墙下探：只测内部平地顶面数 = 256，外周 60 个侧面）
    m.base_depth = 0;
    try buildChunk(testing.allocator, &m, rgb, 0, 0, .{}, &out);
    try testing.expectEqual(@as(usize, 256), out.items.len);

    // 单格高 6 的墙：每露出面 3 段且最上一段用 side_cap(60)
    m.set(8, 8, wall, 6);
    try buildChunk(testing.allocator, &m, rgb, 0, 0, .{}, &out);
    var cap_count: usize = 0;
    for (out.items) |q| {
        if (q.atlas == 60) cap_count += 1;
    }
    try testing.expectEqual(@as(usize, 4), cap_count);

    // 奇数高度 3：最上一段只显示贴图下半（v_top=0.5, v_bot=1）
    m.set(8, 8, wall, 3);
    try buildChunk(testing.allocator, &m, rgb, 0, 0, .{}, &out);
    var half_v_count: usize = 0;
    for (out.items) |q| {
        if (q.atlas == 60 and @abs(q.v_top - 0.5) < 1e-4 and @abs(q.v_bot - 1.0) < 1e-4) half_v_count += 1;
    }
    try testing.expectEqual(@as(usize, 4), half_v_count);

    // cornerLight：同高平均、不同高不混色
    rgb[8 * 16 + 7] = .{ 100, 100, 100 }; // (7,8) height 0
    rgb[7 * 16 + 7] = .{ 200, 200, 200 }; // (7,7) height 0
    const cl = cornerLight(&m, rgb, 8, 8, 0, .{ 0, 0, 0 });
    try testing.expect(cl[0] > 100 and cl[0] < 200);
}

fn findQuad(items: []const Quad, x: f32, z: f32, y0: f32) ?Quad {
    for (items) |q| {
        if (q.p[0][0] == x and q.p[1][0] == x and q.p[0][2] == z and q.p[0][1] == y0 and q.p[0][1] != q.p[3][1]) return q;
    }
    return null;
}

test "tilemesh side segments atlas indices from level 0" {
    var m = try TileMap.init(testing.allocator, 16, 16);
    defer m.deinit();
    m.base_depth = 0;
    const floor = try m.defineTile(.{ .top = 0, .side = 48 });
    const plain = try m.defineTile(.{ .top = 1, .side = 10 });
    const capped = try m.defineTile(.{ .top = 1, .side = 10, .side_cap = 11 });
    const based = try m.defineTile(.{ .top = 1, .side = 10, .side_base = 12 });
    const both = try m.defineTile(.{ .top = 1, .side = 10, .side_cap = 11, .side_base = 12 });
    m.fill(floor, 0);
    const rgb = try testing.allocator.alloc([3]u8, 256);
    defer testing.allocator.free(rgb);
    @memset(rgb, .{ 200, 200, 200 });
    var out: std.ArrayList(Quad) = .empty;
    defer out.deinit(testing.allocator);

    const Case = struct { kind: u16, h: u8, want: []const u16 };
    const cases = [_]Case{
        .{ .kind = plain, .h = 2, .want = &.{10} },
        .{ .kind = capped, .h = 2, .want = &.{11} },
        .{ .kind = based, .h = 2, .want = &.{12} },
        .{ .kind = both, .h = 2, .want = &.{12} },
        .{ .kind = plain, .h = 4, .want = &.{ 10, 10 } },
        .{ .kind = capped, .h = 4, .want = &.{ 10, 11 } },
        .{ .kind = based, .h = 4, .want = &.{ 12, 10 } },
        .{ .kind = both, .h = 4, .want = &.{ 12, 11 } },
        .{ .kind = plain, .h = 6, .want = &.{ 10, 10, 10 } },
        .{ .kind = both, .h = 6, .want = &.{ 12, 10, 11 } },
        .{ .kind = based, .h = 6, .want = &.{ 12, 10, 10 } },
        .{ .kind = capped, .h = 6, .want = &.{ 10, 10, 11 } },
        .{ .kind = plain, .h = 3, .want = &.{ 10, 10 } },
        .{ .kind = capped, .h = 3, .want = &.{ 10, 11 } },
        .{ .kind = based, .h = 3, .want = &.{ 12, 10 } },
        .{ .kind = both, .h = 3, .want = &.{ 12, 11 } },
        .{ .kind = plain, .h = 5, .want = &.{ 10, 10, 10 } },
        .{ .kind = capped, .h = 5, .want = &.{ 10, 10, 11 } },
        .{ .kind = based, .h = 5, .want = &.{ 12, 10, 10 } },
        .{ .kind = both, .h = 5, .want = &.{ 12, 10, 11 } },
    };
    for (cases) |c| {
        m.set(8, 8, c.kind, c.h);
        try buildChunk(testing.allocator, &m, rgb, 0, 0, .{}, &out);
        // +X 面位于 x=9, z=9 起（p0 = (fx+1, fz+1)）
        for (c.want, 0..) |a, i| {
            const y0 = @as(f32, @floatFromInt(i * 2)) * m.height_unit;
            const q = findQuad(out.items, 9, 9, y0) orelse return error.TestUnexpectedResult;
            try testing.expectEqual(a, q.atlas);
            try testing.expectApproxEqAbs(@as(f32, 1.0), q.v_bot, 1e-4);
            const partial = (i + 1 == c.want.len) and (c.h % 2 == 1);
            try testing.expectApproxEqAbs(if (partial) @as(f32, 0.5) else @as(f32, 0.0), q.v_top, 1e-4);
        }
        // 段数正好等于期望（+X 面 x=9 的侧面 quad 数）
        var n: usize = 0;
        for (out.items) |q| {
            if (q.p[0][0] == 9 and q.p[1][0] == 9 and q.p[0][1] != q.p[3][1]) n += 1;
        }
        try testing.expectEqual(c.want.len, n);
    }
}

test "tilemesh side hidden segments culled but alignment from level 0" {
    var m = try TileMap.init(testing.allocator, 16, 16);
    defer m.deinit();
    m.base_depth = 0;
    const floor = try m.defineTile(.{ .top = 0, .side = 48 });
    const wall = try m.defineTile(.{ .top = 1, .side = 10, .side_cap = 11, .side_base = 12 });
    m.fill(floor, 0);
    const rgb = try testing.allocator.alloc([3]u8, 256);
    defer testing.allocator.free(rgb);
    @memset(rgb, .{ 200, 200, 200 });
    var out: std.ArrayList(Quad) = .empty;
    defer out.deinit(testing.allocator);
    m.set(8, 8, wall, 6);
    m.set(9, 8, floor, 2); // 邻格高 2：+X 面第 0 段被藏
    try buildChunk(testing.allocator, &m, rgb, 0, 0, .{}, &out);
    try testing.expect(findQuad(out.items, 9, 9, 0) == null);
    const q = findQuad(out.items, 9, 9, 2 * m.height_unit) orelse return error.TestUnexpectedResult;
    try testing.expectEqual(@as(u16, 10), q.atlas);
}

test "tilemesh corner light on top and side faces" {
    var m = try TileMap.init(testing.allocator, 16, 16);
    defer m.deinit();
    m.base_depth = 0;
    const floor = try m.defineTile(.{ .top = 0, .side = 48 });
    const wall = try m.defineTile(.{ .top = 1, .side = 10 });
    m.fill(floor, 0);
    const rgb = try testing.allocator.alloc([3]u8, 256);
    defer testing.allocator.free(rgb);
    @memset(rgb, .{ 100, 100, 100 });
    m.set(8, 8, wall, 2);
    m.set(8, 9, wall, 2);
    rgb[8 * 16 + 8] = .{ 200, 200, 200 };
    var out: std.ArrayList(Quad) = .empty;
    defer out.deinit(testing.allocator);
    const p: Params = .{};
    try buildChunk(testing.allocator, &m, rgb, 0, 0, p, &out);

    // (8,8) 顶面 BL(8,9) BR(9,9) TR(9,8) TL(8,8)：角点 (8,9)(9,9) 混入 (8,9)=100 -> 150
    var found_top = false;
    for (out.items) |q| {
        if (q.atlas == 1 and q.p[0][0] == 8 and q.p[0][2] == 9) {
            found_top = true;
            try testing.expectEqual([4]u8{ 150, 150, 200, 200 }, [4]u8{ q.c[0][0], q.c[1][0], q.c[2][0], q.c[3][0] });
        }
    }
    try testing.expect(found_top);

    // +X 侧面朝向邻格 (9,8)（地面、高 0、rgb=100）：两角点均只由高 0 的 100 号格平均 -> 100，
    // 乘 light_x（旧的本格高度基准会得到 150/200）；上下边同色。
    const q = findQuad(out.items, 9, 9, 0) orelse return error.TestUnexpectedResult;
    const g: u8 = @intFromFloat(100.0 * p.light_x);
    for (q.c) |c| try testing.expectEqual(g, c[0]);
}

fn findSide(items: []const Quad, a: [2]f32, b: [2]f32, y0: f32) ?Quad {
    for (items) |q| {
        if (q.p[0][0] == a[0] and q.p[0][2] == a[1] and q.p[1][0] == b[0] and q.p[1][2] == b[1] and
            q.p[0][1] == y0 and q.p[3][1] > q.p[0][1]) return q;
    }
    return null;
}

test "tilemesh corner light matrix over four side directions and vertex order" {
    var m = try TileMap.init(testing.allocator, 16, 16);
    defer m.deinit();
    m.base_depth = 0;
    const floor = try m.defineTile(.{ .top = 0, .side = 48 });
    const wall = try m.defineTile(.{ .top = 1, .side = 10 });
    m.fill(floor, 0);
    const rgb = try testing.allocator.alloc([3]u8, 256);
    defer testing.allocator.free(rgb);
    // 地面格 rgb = 3x + 5y（各不相同）；侧面取朝向邻格（地面，高 0）的角点光。
    for (rgb, 0..) |*c, i| {
        const v: u8 = @intCast(3 * (i % 16) + 5 * (i / 16));
        c.* = .{ v, v, v };
    }
    m.set(8, 8, wall, 2);
    m.set(9, 8, wall, 2);
    m.set(8, 9, wall, 2);
    m.set(9, 9, wall, 2);
    rgb[8 * 16 + 8] = .{ 40, 40, 40 };
    rgb[8 * 16 + 9] = .{ 80, 80, 80 };
    rgb[9 * 16 + 8] = .{ 120, 120, 120 };
    rgb[9 * 16 + 9] = .{ 200, 200, 200 };
    var out: std.ArrayList(Quad) = .empty;
    defer out.deinit(testing.allocator);
    const p: Params = .{};
    try buildChunk(testing.allocator, &m, rgb, 0, 0, p, &out);

    // 规格变更后期望值：侧面顶点 = 邻格（地面高 0）在该角的角点光，只平均高 0 的格：
    // (8,8)=(56+59+61)/3=58  (8,9)=(61+66)/2=63  (9,8)=(59+62)/2=60
    // (10,10)=(75+77+80)/3=77  (10,9)=(70+75)/2=72  (9,10)=(74+77)/2=75
    const Case = struct { a: [2]f32, b: [2]f32, ka: u8, kb: u8, light: f32 };
    const cases = [_]Case{
        // 格 (8,8) 的 -X：p0=(8,8) p1=(8,9)
        .{ .a = .{ 8, 8 }, .b = .{ 8, 9 }, .ka = 58, .kb = 63, .light = p.light_x },
        // 格 (8,8) 的 -Z：p0=(9,8) p1=(8,8)
        .{ .a = .{ 9, 8 }, .b = .{ 8, 8 }, .ka = 60, .kb = 58, .light = p.light_z },
        // 格 (9,9) 的 +X：p0=(10,10) p1=(10,9)
        .{ .a = .{ 10, 10 }, .b = .{ 10, 9 }, .ka = 77, .kb = 72, .light = p.light_x },
        // 格 (9,9) 的 +Z：p0=(9,10) p1=(10,10)
        .{ .a = .{ 9, 10 }, .b = .{ 10, 10 }, .ka = 75, .kb = 77, .light = p.light_z },
    };
    for (cases) |c| {
        const q = findSide(out.items, c.a, c.b, 0) orelse return error.TestUnexpectedResult;
        const ea = scaleColor(.{ c.ka, c.ka, c.ka }, c.light)[0];
        const eb = scaleColor(.{ c.kb, c.kb, c.kb }, c.light)[0];
        try testing.expectEqual(ea, q.c[0][0]);
        try testing.expectEqual(eb, q.c[1][0]);
        try testing.expectEqual(eb, q.c[2][0]);
        try testing.expectEqual(ea, q.c[3][0]);
    }
}

test "tilemesh side vertices take neighbour ground corner light, not own height" {
    var m = try TileMap.init(testing.allocator, 16, 16);
    defer m.deinit();
    m.base_depth = 0;
    const floor = try m.defineTile(.{ .top = 0, .side = 48 });
    const wall = try m.defineTile(.{ .top = 1, .side = 10 });
    m.fill(floor, 0);
    const rgb = try testing.allocator.alloc([3]u8, 256);
    defer testing.allocator.free(rgb);
    @memset(rgb, .{ 100, 100, 100 });
    m.set(8, 8, wall, 2);
    rgb[8 * 16 + 8] = .{ 200, 200, 200 };
    rgb[8 * 16 + 9] = .{ 60, 60, 60 }; // (9,8) 地面
    rgb[9 * 16 + 9] = .{ 90, 90, 90 }; // (9,9) 地面
    rgb[9 * 16 + 8] = .{ 30, 30, 30 }; // (8,9) 地面
    var out: std.ArrayList(Quad) = .empty;
    defer out.deinit(testing.allocator);
    const p: Params = .{};
    try buildChunk(testing.allocator, &m, rgb, 0, 0, p, &out);

    // +X 面（邻格 (9,8) 高 0）：p0=(9,9) p1=(9,8)
    // 角 (9,9)：地面 (9,8)60 (8,9)30 (9,9)90 -> 60；本格高度基准则只有墙 -> 200
    // 角 (9,8)：地面 (8,7)100 (9,7)100 (9,8)60 -> 86；本格高度基准则 -> 200
    const q = findQuad(out.items, 9, 9, 0) orelse return error.TestUnexpectedResult;
    const k0 = scaleColor(.{ 60, 60, 60 }, p.light_x)[0];
    const k1 = scaleColor(.{ 86, 86, 86 }, p.light_x)[0];
    const old = scaleColor(.{ 200, 200, 200 }, p.light_x)[0];
    try testing.expect(k0 != old and k1 != old);
    try testing.expectEqual(k0, q.c[0][0]);
    try testing.expectEqual(k1, q.c[1][0]);
    try testing.expectEqual(k1, q.c[2][0]);
    try testing.expectEqual(k0, q.c[3][0]);
}

test "tilemesh skirt partial bottom segment UV" {
    var m = try TileMap.init(testing.allocator, 16, 16);
    defer m.deinit();
    m.base_depth = 1.25; // seg_h = 1.0：段 [-1,0] 满，段 [-1.25,-1] frac=0.25
    const floor = try m.defineTile(.{ .top = 0, .side = 48 });
    m.fill(floor, 0);
    const rgb = try testing.allocator.alloc([3]u8, 256);
    defer testing.allocator.free(rgb);
    @memset(rgb, .{ 200, 200, 200 });
    var out: std.ArrayList(Quad) = .empty;
    defer out.deinit(testing.allocator);
    try buildChunk(testing.allocator, &m, rgb, 0, 0, .{}, &out);

    // (0,5) 的 -X 面：p0=(0,5) p1=(0,6)，在 x=0 平面
    var full: usize = 0;
    var partial: usize = 0;
    for (out.items) |q| {
        if (q.p[0][0] == 0 and q.p[1][0] == 0 and q.p[0][2] == 5 and q.p[1][2] == 6 and q.p[3][1] > q.p[0][1]) {
            try testing.expectApproxEqAbs(@as(f32, 0.0), q.v_top, 1e-4);
            if (@abs(q.p[0][1] - -1.25) < 1e-4) {
                partial += 1;
                try testing.expectApproxEqAbs(@as(f32, -1.0), q.p[3][1], 1e-4);
                try testing.expectApproxEqAbs(@as(f32, 0.25), q.v_bot, 1e-4);
            } else {
                full += 1;
                try testing.expectApproxEqAbs(@as(f32, 1.0), q.v_bot, 1e-4);
            }
        }
    }
    try testing.expectEqual(@as(usize, 1), partial);
    try testing.expectEqual(@as(usize, 1), full);
}

test "tilemesh edge skirt extends below ground to -base_depth" {
    var m = try TileMap.init(testing.allocator, 16, 16);
    defer m.deinit();
    m.base_depth = 1;
    const floor = try m.defineTile(.{ .top = 0, .side = 48 });
    const wall = try m.defineTile(.{ .top = 1, .side = 10, .side_cap = 11, .side_base = 12 });
    m.fill(floor, 0);
    const rgb = try testing.allocator.alloc([3]u8, 256);
    defer testing.allocator.free(rgb);
    @memset(rgb, .{ 200, 200, 200 });
    var out: std.ArrayList(Quad) = .empty;
    defer out.deinit(testing.allocator);

    // 高 0 的边缘格 (0,5)：-X 面在 x=0 平面，覆盖 y in [-1, 0]
    try buildChunk(testing.allocator, &m, rgb, 0, 0, .{}, &out);
    var min_y: f32 = 1e9;
    var max_y: f32 = -1e9;
    var n: usize = 0;
    for (out.items) |q| {
        if (q.p[0][0] == 0 and q.p[1][0] == 0 and q.p[0][2] == 5 and q.p[1][2] == 6 and q.p[3][1] != q.p[0][1]) {
            n += 1;
            min_y = @min(min_y, q.p[0][1]);
            max_y = @max(max_y, q.p[3][1]);
            try testing.expectEqual(@as(u16, 48), q.atlas);
        }
    }
    try testing.expect(n >= 1);
    try testing.expectApproxEqAbs(@as(f32, -1.0), min_y, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 0.0), max_y, 1e-4);

    // 高 4 的边缘墙：地上段（锚定 0）+ 地下段（atlas = side）
    m.set(0, 5, wall, 4);
    try buildChunk(testing.allocator, &m, rgb, 0, 0, .{}, &out);
    min_y = 1e9;
    max_y = -1e9;
    var above: usize = 0;
    var below: usize = 0;
    for (out.items) |q| {
        if (q.p[0][0] == 0 and q.p[1][0] == 0 and q.p[0][2] == 5 and q.p[1][2] == 6 and q.p[3][1] != q.p[0][1]) {
            min_y = @min(min_y, q.p[0][1]);
            max_y = @max(max_y, q.p[3][1]);
            if (q.p[0][1] >= 0) above += 1 else {
                below += 1;
                try testing.expectEqual(@as(u16, 10), q.atlas);
            }
        }
    }
    try testing.expectEqual(@as(usize, 2), above);
    try testing.expect(below >= 1);
    try testing.expectApproxEqAbs(@as(f32, -1.0), min_y, 1e-4);
    try testing.expectApproxEqAbs(4 * m.height_unit, max_y, 1e-4);
    const b = chunkBounds(&m, 0, 0);
    try testing.expect(b.min.y <= min_y and b.max.y >= max_y);
}

test "tilemesh empty neighbour does not leak neighbour rgb" {
    var m = try TileMap.init(testing.allocator, 16, 16);
    defer m.deinit();
    m.base_depth = 0;
    const wall = try m.defineTile(.{ .top = 1, .side = 10 });
    m.set(3, 3, wall, 2); // 其余格 kind 0
    const rgb = try testing.allocator.alloc([3]u8, 256);
    defer testing.allocator.free(rgb);
    @memset(rgb, .{ 0, 0, 0 });
    rgb[3 * 16 + 3] = .{ 200, 200, 200 };
    var out: std.ArrayList(Quad) = .empty;
    defer out.deinit(testing.allocator);
    const p: Params = .{};
    try buildChunk(testing.allocator, &m, rgb, 0, 0, p, &out);
    try testing.expectEqual(@as(usize, 5), out.items.len); // 顶 + 4 侧
    const want: u8 = @intFromFloat(200.0 * p.light_x);
    const q = findQuad(out.items, 4, 4, 0) orelse return error.TestUnexpectedResult;
    for (q.c) |c| try testing.expectEqual(want, c[0]);
}

test "tilemesh chunkVisible" {
    var cam = IsoCamera{ .viewport_w = 640, .viewport_h = 360, .view_height = 14.0 };
    cam.target = Vec3.new(8, 0, 8);
    const near_box = Aabb{ .min = Vec3.new(6, 0, 6), .max = Vec3.new(10, 1, 10) };
    try testing.expect(chunkVisible(&cam, near_box));
    const far_box = Aabb{ .min = Vec3.new(500, 0, 500), .max = Vec3.new(516, 1, 516) };
    try testing.expect(!chunkVisible(&cam, far_box));
    // 摄像机移过去后可见
    cam.target = Vec3.new(508, 0, 508);
    try testing.expect(chunkVisible(&cam, far_box));
    try testing.expect(!chunkVisible(&cam, near_box));
    // 跨视野边缘的大盒（一端在视野内、一端在外）与包住相机的盒都可见
    cam.target = Vec3.new(8, 0, 8);
    const straddle = Aabb{ .min = Vec3.new(6, 0, 6), .max = Vec3.new(500, 1, 500) };
    try testing.expect(chunkVisible(&cam, straddle));
    const around = Aabb{ .min = Vec3.new(-300, 0, -300), .max = Vec3.new(300, 1, 300) };
    try testing.expect(chunkVisible(&cam, around));
    cam.target = Vec3.new(508, 0, 508);
    // 恰好在相机目标上的退化（零体积）盒也可见
    const point = Aabb{ .min = Vec3.new(508, 0, 508), .max = Vec3.new(508, 0, 508) };
    try testing.expect(chunkVisible(&cam, point));
}
