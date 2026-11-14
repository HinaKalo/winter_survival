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
                const nb_top: f32 = if (!map.inBounds(nx, ny)) -map.base_depth else map.topY(nx, ny);
                if (nb_top >= top) continue;

                const nb_idx: ?usize = if (map.inBounds(nx, ny)) @as(usize, @intCast(ny)) * map.width + @as(usize, @intCast(nx)) else null;
                const nb_rgb = if (nb_idx) |ni| (if (ni < rgb.len) rgb[ni] else cell_rgb) else cell_rgb;
                const sc = scaleColor(.{
                    @intCast((@as(u16, cell_rgb[0]) + nb_rgb[0]) / 2),
                    @intCast((@as(u16, cell_rgb[1]) + nb_rgb[1]) / 2),
                    @intCast((@as(u16, cell_rgb[2]) + nb_rgb[2]) / 2),
                }, s.light);

                var sy = nb_top;
                while (sy < top - 1e-4) {
                    const seg = @min(seg_h, top - sy);
                    const is_top_seg = (sy + seg >= top - 1e-4);
                    const atlas = if (is_top_seg and def.side_cap != 0xFFFF) def.side_cap else def.side;
                    const frac = std.math.clamp(seg / seg_h, 0.0, 1.0);
                    try out.append(allocator, .{
                        .p = .{
                            .{ s.p0[0], sy, s.p0[1] },
                            .{ s.p1[0], sy, s.p1[1] },
                            .{ s.p1[0], sy + seg, s.p1[1] },
                            .{ s.p0[0], sy + seg, s.p0[1] },
                        },
                        .atlas = atlas,
                        .v_top = 0,
                        .v_bot = frac,
                        .c = .{ sc, sc, sc, sc },
                    });
                    sy += seg;
                }
            }
        }
    }
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

    // 奇数高度 3：最上一段 V 裁剪 0.5
    m.set(8, 8, wall, 3);
    try buildChunk(testing.allocator, &m, rgb, 0, 0, .{}, &out);
    var half_v_count: usize = 0;
    for (out.items) |q| {
        if (q.atlas == 60 and @abs(q.v_bot - 0.5) < 1e-4) half_v_count += 1;
    }
    try testing.expectEqual(@as(usize, 4), half_v_count);

    // cornerLight：同高平均、不同高不混色
    rgb[8 * 16 + 7] = .{ 100, 100, 100 }; // (7,8) height 0
    rgb[7 * 16 + 7] = .{ 200, 200, 200 }; // (7,7) height 0
    const cl = cornerLight(&m, rgb, 8, 8, 0, .{ 0, 0, 0 });
    try testing.expect(cl[0] > 100 and cl[0] < 200);
}
