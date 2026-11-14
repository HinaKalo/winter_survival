//! 纯逻辑：屏幕方向、格子坐标。
const std = @import("std");

/// 屏幕空间方向，对应精灵表行号。
pub const Dir = enum(u8) { down = 0, left = 1, right = 2, up = 3 };

pub const GridPos = struct { x: i32, y: i32 };

/// 世界水平位移 (dx,dz) 在当前相机 yaw 下对应的屏幕朝向；零向量返回 null。
/// 相机水平 right = (cos yaw, -sin yaw)；朝向相机（屏幕下方）= (sin yaw, cos yaw)。
pub fn screenDirection(dx: f32, dz: f32, yaw_deg: f32) ?Dir {
    // 输入健壮性：非有限一律 null；按最大分量归一化，避免平方溢出。
    if (!std.math.isFinite(dx) or !std.math.isFinite(dz) or !std.math.isFinite(yaw_deg)) return null;
    const m = @max(@abs(dx), @abs(dz));
    if (m < 1e-6) return null;
    const ux = dx / m;
    const uz = dz / m;
    const yaw = std.math.degreesToRadians(yaw_deg);
    const s = @sin(yaw);
    const c = @cos(yaw);
    const r = ux * c - uz * s; // 屏幕右分量
    const t = ux * s + uz * c; // 朝向相机（屏幕下）分量
    if (@abs(r) > @abs(t)) {
        return if (r > 0) .right else .left;
    }
    return if (t > 0) .down else .up;
}

test "screenDirection four directions at yaw 0" {
    // yaw=0: 朝向相机 = +Z => down; right = +X
    try std.testing.expectEqual(Dir.down, screenDirection(0, 1, 0).?);
    try std.testing.expectEqual(Dir.up, screenDirection(0, -1, 0).?);
    try std.testing.expectEqual(Dir.right, screenDirection(1, 0, 0).?);
    try std.testing.expectEqual(Dir.left, screenDirection(-1, 0, 0).?);
    try std.testing.expect(screenDirection(0, 0, 0) == null);
}

test "screenDirection at yaw 45" {
    const s = @sin(std.math.degreesToRadians(@as(f32, 45)));
    const c = @cos(std.math.degreesToRadians(@as(f32, 45)));
    try std.testing.expectEqual(Dir.down, screenDirection(s, c, 45).?);
    try std.testing.expectEqual(Dir.up, screenDirection(-s, -c, 45).?);
    try std.testing.expectEqual(Dir.right, screenDirection(c, -s, 45).?);
    try std.testing.expectEqual(Dir.left, screenDirection(-c, s, 45).?);
}

test "screenDirection garbage input" {
    const nan = std.math.nan(f32);
    const inf = std.math.inf(f32);
    try std.testing.expect(screenDirection(nan, 1, 0) == null);
    try std.testing.expect(screenDirection(1, nan, 0) == null);
    try std.testing.expect(screenDirection(1, 0, nan) == null);
    try std.testing.expect(screenDirection(inf, 0, 0) == null);
    try std.testing.expect(screenDirection(0, -inf, 0) == null);
    try std.testing.expect(screenDirection(1, 0, inf) == null);
    try std.testing.expect(screenDirection(1e-30, 0, 0) == null);
    // 极大有限值：平方会溢出，但方向仍应正确
    try std.testing.expectEqual(Dir.right, screenDirection(3e38, 0, 0).?);
    try std.testing.expectEqual(Dir.down, screenDirection(0, 3e38, 0).?);
    try std.testing.expect(screenDirection(1, 0, 1e30) != null); // 巨大 yaw 仍有限
}
