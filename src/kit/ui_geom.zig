//! 纯逻辑 UI 几何：矩形 + UV 裁剪、九宫格切分。
const std = @import("std");

pub const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

pub const UvQuad = struct {
    dst: Rect,
    u0: f32,
    v0: f32,
    u1: f32,
    v1: f32,
};

pub const NineSlice = struct {
    src: Rect,
    dst: Rect,
};

pub fn clip(q: UvQuad, c: Rect) ?UvQuad {
    if (q.dst.w <= 0 or q.dst.h <= 0 or c.w <= 0 or c.h <= 0) return null;

    const x0 = @max(q.dst.x, c.x);
    const y0 = @max(q.dst.y, c.y);
    const x1 = @min(q.dst.x + q.dst.w, c.x + c.w);
    const y1 = @min(q.dst.y + q.dst.h, c.y + c.h);

    if (x1 <= x0 or y1 <= y0) return null;

    const tx0 = (x0 - q.dst.x) / q.dst.w;
    const ty0 = (y0 - q.dst.y) / q.dst.h;
    const tx1 = (x1 - q.dst.x) / q.dst.w;
    const ty1 = (y1 - q.dst.y) / q.dst.h;

    const du = q.u1 - q.u0;
    const dv = q.v1 - q.v0;

    return .{
        .dst = .{
            .x = x0,
            .y = y0,
            .w = x1 - x0,
            .h = y1 - y0,
        },
        .u0 = q.u0 + du * tx0,
        .v0 = q.v0 + dv * ty0,
        .u1 = q.u0 + du * tx1,
        .v1 = q.v0 + dv * ty1,
    };
}

pub fn nineSlice(src: Rect, l: f32, t: f32, r: f32, b: f32, dst: Rect, out: *[9]NineSlice) usize {
    if (src.w <= 0 or src.h <= 0 or dst.w <= 0 or dst.h <= 0) return 0;

    const sl = @max(0.0, @min(l, src.w));
    const sr = @max(0.0, @min(r, src.w - sl));
    const sw_mid = @max(0.0, src.w - sl - sr);

    const st = @max(0.0, @min(t, src.h));
    const sb = @max(0.0, @min(b, src.h - st));
    const sh_mid = @max(0.0, src.h - st - sb);

    var dl = @max(0.0, l);
    var dr = @max(0.0, r);
    if (dl + dr > dst.w and (dl + dr) > 0) {
        const k = dst.w / (dl + dr);
        dl *= k;
        dr *= k;
    }
    const dw_mid = @max(0.0, dst.w - dl - dr);

    var dt = @max(0.0, t);
    var db = @max(0.0, b);
    if (dt + db > dst.h and (dt + db) > 0) {
        const k = dst.h / (dt + db);
        dt *= k;
        db *= k;
    }
    const dh_mid = @max(0.0, dst.h - dt - db);

    const sx = [3]f32{ src.x, src.x + sl, src.x + sl + sw_mid };
    const sw = [3]f32{ sl, sw_mid, sr };
    const sy = [3]f32{ src.y, src.y + st, src.y + st + sh_mid };
    const sh = [3]f32{ st, sh_mid, sb };

    const dx = [3]f32{ dst.x, dst.x + dl, dst.x + dl + dw_mid };
    const dw = [3]f32{ dl, dw_mid, dr };
    const dy = [3]f32{ dst.y, dst.y + dt, dst.y + dt + dh_mid };
    const dh = [3]f32{ dt, dh_mid, db };

    var count: usize = 0;
    for (0..3) |row| {
        if (sh[row] <= 0 or dh[row] <= 0) continue;
        for (0..3) |col| {
            if (sw[col] <= 0 or dw[col] <= 0) continue;
            out[count] = .{
                .src = .{ .x = sx[col], .y = sy[row], .w = sw[col], .h = sh[row] },
                .dst = .{ .x = dx[col], .y = dy[row], .w = dw[col], .h = dh[row] },
            };
            count += 1;
        }
    }
    return count;
}

// ------------------------------------------------------------------ 单元测试

test "clip handles inside, outside, and 4-way partial clipping" {
    const q = UvQuad{
        .dst = .{ .x = 10, .y = 20, .w = 100, .h = 50 },
        .u0 = 0.0,
        .v0 = 0.0,
        .u1 = 1.0,
        .v1 = 1.0,
    };

    // Fully inside
    const inside = clip(q, .{ .x = 0, .y = 0, .w = 200, .h = 200 }).?;
    try std.testing.expectEqual(q.dst, inside.dst);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), inside.u0, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), inside.u1, 1e-5);

    // Fully outside
    try std.testing.expect(clip(q, .{ .x = 110, .y = 20, .w = 50, .h = 50 }) == null);
    try std.testing.expect(clip(q, .{ .x = 10, .y = 70, .w = 50, .h = 50 }) == null);

    // Partial on all 4 sides: x=[35, 85] (0.25..0.75), y=[30, 60] (0.2..0.8)
    const part = clip(q, .{ .x = 35, .y = 30, .w = 50, .h = 30 }).?;
    try std.testing.expectApproxEqAbs(@as(f32, 35), part.dst.x, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 30), part.dst.y, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 50), part.dst.w, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 30), part.dst.h, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), part.u0, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.20), part.v0, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), part.u1, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.80), part.v1, 1e-5);
}

test "nineSlice emits expected slices and compresses when dst is smaller than borders" {
    var out: [9]NineSlice = undefined;
    const src = Rect{ .x = 0, .y = 0, .w = 32, .h = 32 };

    // Full 9 slices
    const n9 = nineSlice(src, 8, 8, 8, 8, .{ .x = 10, .y = 20, .w = 100, .h = 60 }, &out);
    try std.testing.expectEqual(@as(usize, 9), n9);
    try std.testing.expectApproxEqAbs(@as(f32, 84), out[4].dst.w, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 44), out[4].dst.h, 1e-5);

    // 3-slice horizontal bar (t=0, b=0)
    const n3 = nineSlice(src, 4, 0, 4, 0, .{ .x = 0, .y = 0, .w = 40, .h = 8 }, &out);
    try std.testing.expectEqual(@as(usize, 3), n3);

    // 1-slice (all borders 0)
    const n1 = nineSlice(src, 0, 0, 0, 0, .{ .x = 0, .y = 0, .w = 20, .h = 20 }, &out);
    try std.testing.expectEqual(@as(usize, 1), n1);

    // Compressed dst smaller than l + r (8 + 8 = 16 > 10) -> middle omitted, 4 corners remain
    const nc = nineSlice(src, 8, 8, 8, 8, .{ .x = 0, .y = 0, .w = 10, .h = 10 }, &out);
    try std.testing.expectEqual(@as(usize, 4), nc);
    try std.testing.expectApproxEqAbs(@as(f32, 5), out[0].dst.w, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 5), out[1].dst.w, 1e-5);
}
