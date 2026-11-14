//! 纯逻辑：正交等距相机。
const std = @import("std");
const delve = @import("delve");
const math = delve.math;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Mat4 = math.Mat4;

pub const Ray = struct { origin: Vec3, dir: Vec3 };

fn rad(deg: f32) f32 {
    return std.math.degreesToRadians(deg);
}

fn finiteOr(v: f32, d: f32) f32 {
    return if (std.math.isFinite(v)) v else d;
}

const min_pitch: f32 = 1.0;
const max_pitch: f32 = 89.0;

/// dt 非有限或 < 0 视为 0；并限上限，防止后续乘法溢出为 Inf。
fn sanitizeDt(dt: f32) f32 {
    if (!std.math.isFinite(dt) or dt < 0) return 0;
    return @min(dt, 3600.0);
}

/// 屏幕坐标：非有限 -> 0，并限幅，保证射线有限。
fn sanitizeScreen(v: f32) f32 {
    if (!std.math.isFinite(v)) return 0;
    return std.math.clamp(v, -1.0e7, 1.0e7);
}

fn vec3Finite(v: Vec3) bool {
    return std.math.isFinite(v.x) and std.math.isFinite(v.y) and std.math.isFinite(v.z);
}

/// 世界坐标限幅：保证与相机距离/半宽相加减后不会溢出为 Inf。
const max_world: f32 = 1.0e6;

fn clampWorld(v: Vec3) Vec3 {
    if (!vec3Finite(v)) return Vec3.zero;
    return Vec3.new(
        std.math.clamp(v.x, -max_world, max_world),
        std.math.clamp(v.y, -max_world, max_world),
        std.math.clamp(v.z, -max_world, max_world),
    );
}

/// 绕 Y 轴旋转 yaw_deg 度的矩阵：作用于 (0,0,1) 得 (sin yaw, 0, cos yaw)。
/// （实测 Delve 的 Mat4.rotate 方向正确，无需取反。）
pub fn billboardRotation(yaw_deg: f32) Mat4 {
    return Mat4.rotate(finiteOr(yaw_deg, 0), Vec3.up);
}

/// M * v（Delve 的 Vec4.mulMat4 因 Vec4.zero.w == 1 会使结果 w 多加 1，故自行实现）。
pub fn transform4(m: Mat4, v: Vec4) Vec4 {
    var r: [4]f32 = .{ 0, 0, 0, 0 };
    const va = v.toArray();
    for (0..4) |row| {
        for (0..4) |col| r[row] += m.m[col][row] * va[col];
    }
    return Vec4.fromArray(r);
}

pub const iso_ppu: f32 = 90.50967; // 128 / sqrt(2)
pub const iso_height_unit: f32 = 0.408248; // 1 / sqrt(6)

pub const IsoCamera = struct {
    target: Vec3 = Vec3.zero,
    yaw: f32 = 45.0,
    pitch: f32 = 30.0,
    yaw_goal: f32 = 45.0,
    distance: f32 = 60.0,
    zoom: f32 = 1.0,
    min_zoom: f32 = 0.25,
    max_zoom: f32 = 4.0,
    view_height: f32 = 14.0,
    pixels_per_unit: f32 = 0, // 0 = 旧 view_height 模式
    snap_pixels: bool = false,
    view_target: Vec3 = Vec3.zero,
    near: f32 = 0.1,
    far: f32 = 200.0,
    follow_smoothing: f32 = 8.0,
    follow_goal: ?Vec3 = null,
    view: Mat4 = Mat4.identity,
    proj: Mat4 = Mat4.identity,
    viewport_w: f32 = 1,
    viewport_h: f32 = 1,

    /// pitch 钳制到 [1,89]（非有限 -> 30），保证 cos(pitch) > 0、forward 非零。
    fn safePitch(self: *const IsoCamera) f32 {
        return std.math.clamp(finiteOr(self.pitch, 30.0), min_pitch, max_pitch);
    }

    fn safeDistance(self: *const IsoCamera) f32 {
        const d = finiteOr(self.distance, 60.0);
        return if (d > 0.01) @min(d, 1.0e6) else 60.0;
    }

    fn zoomRange(self: *const IsoCamera) struct { lo: f32, hi: f32 } {
        const lo = if (std.math.isFinite(self.min_zoom) and self.min_zoom > 0) self.min_zoom else 0.25;
        const hi = if (std.math.isFinite(self.max_zoom) and self.max_zoom >= lo) self.max_zoom else @max(lo, 4.0);
        return .{ .lo = lo, .hi = hi };
    }

    /// 始终返回 (0, +inf) 内的有限缩放。
    fn safeZoom(self: *const IsoCamera) f32 {
        const r = self.zoomRange();
        return std.math.clamp(finiteOr(self.zoom, 1.0), r.lo, r.hi);
    }

    pub fn effectivePpu(self: *const IsoCamera) f32 {
        if (!std.math.isFinite(self.pixels_per_unit) or self.pixels_per_unit <= 0) return 0;
        return @min(self.pixels_per_unit, 1.0e5);
    }

    fn eyeFor(self: *const IsoCamera, tgt: Vec3) Vec3 {
        const y = rad(finiteOr(self.yaw, 45.0));
        const p = rad(self.safePitch());
        const off = Vec3.new(@cos(p) * @sin(y), @sin(p), @cos(p) * @cos(y)).scale(self.safeDistance());
        return tgt.add(off);
    }

    pub fn eyePosition(self: *const IsoCamera) Vec3 {
        return self.eyeFor(self.target);
    }

    /// eye -> target 单位向量
    pub fn forward(self: *const IsoCamera) Vec3 {
        return self.target.sub(self.eyePosition()).norm();
    }

    pub fn right(self: *const IsoCamera) Vec3 {
        return self.forward().cross(Vec3.up).norm();
    }

    pub fn camUp(self: *const IsoCamera) Vec3 {
        return self.right().cross(self.forward()).norm();
    }

    pub fn rotateStep(self: *IsoCamera, steps: i32) void {
        const base = if (std.math.isFinite(self.yaw_goal)) self.yaw_goal else self.yaw;
        const next = base + 90.0 * @as(f32, @floatFromInt(steps));
        if (std.math.isFinite(next)) self.yaw_goal = next;
    }

    /// 非有限输入忽略（zoom 不变）。
    pub fn setZoom(self: *IsoCamera, z: f32) void {
        if (!std.math.isFinite(z)) return;
        const r = self.zoomRange();
        self.zoom = std.math.clamp(z, r.lo, r.hi);
    }

    pub fn tick(self: *IsoCamera, dt_in: f32) void {
        const dt = sanitizeDt(dt_in);
        if (!std.math.isFinite(self.yaw)) self.yaw = 45.0;
        if (!std.math.isFinite(self.yaw_goal)) self.yaw_goal = self.yaw;
        const k = @min(1.0, 8.0 * dt);
        const diff = self.yaw_goal - self.yaw;
        // diff 溢出为 Inf 时直接对齐，避免 Inf*0 = NaN 写入 yaw
        if (!std.math.isFinite(diff) or @abs(diff) < 0.01) {
            self.yaw = self.yaw_goal;
        } else {
            const ny = self.yaw + diff * k;
            if (std.math.isFinite(ny)) self.yaw = ny else self.yaw = self.yaw_goal;
        }
        if (self.follow_goal) |g_raw| {
            if (vec3Finite(g_raw)) { // 非有限目标忽略
                const g = clampWorld(g_raw);
                const nt = if (!(std.math.isFinite(self.follow_smoothing) and self.follow_smoothing > 0))
                    g
                else
                    Vec3.lerp(clampWorld(self.target), g, @min(1.0, self.follow_smoothing * dt));
                // 只写入有限结果，绝不把 NaN/Inf 写入 target
                if (vec3Finite(nt)) self.target = nt;
            }
        }
    }

    /// 视口限幅到 [1, 1e5]：aspect 有界，hw 不会溢出为 Inf（否则 ortho 中 Inf-Inf = NaN）。
    fn safeViewport(_: *const IsoCamera, v: f32) f32 {
        return if (std.math.isFinite(v)) std.math.clamp(v, 1.0, 1.0e5) else 1.0;
    }

    pub fn halfExtents(self: *const IsoCamera) Vec2 {
        const ppu = self.effectivePpu();
        if (ppu > 0) {
            const eff = ppu * self.safeZoom();
            const hw = (self.safeViewport(self.viewport_w) * 0.5) / eff;
            const hh = (self.safeViewport(self.viewport_h) * 0.5) / eff;
            return Vec2.new(hw, hh);
        }
        const vh = finiteOr(self.view_height, 14.0);
        const vh_ok = if (vh > 0) @min(vh, 1.0e6) else 14.0;
        const hh = vh_ok / (2.0 * self.safeZoom()); // safeZoom > 0
        const aspect = self.safeViewport(self.viewport_w) / self.safeViewport(self.viewport_h);
        return Vec2.new(hh * aspect, hh);
    }

    pub fn snapToPixel(self: *const IsoCamera, p: Vec3) Vec3 {
        if (!vec3Finite(p)) return Vec3.zero;
        const ppu_base = self.effectivePpu();
        const ppu = if (ppu_base > 0)
            ppu_base * self.safeZoom()
        else
            self.safeViewport(self.viewport_h) / (2.0 * self.halfExtents().y);
        if (!std.math.isFinite(ppu) or ppu <= 0) return p;

        const r = self.right();
        const u = self.camUp();
        const f = self.forward();
        const sx = @round(p.dot(r) * ppu) / ppu;
        const sy = @round(p.dot(u) * ppu) / ppu;
        const sz = p.dot(f);
        const out = r.scale(sx).add(u.scale(sy)).add(f.scale(sz));
        return if (vec3Finite(out)) out else p;
    }

    pub fn update(self: *IsoCamera, viewport_w: f32, viewport_h: f32) void {
        // 先把可被外部直接写入的 pub 字段修复为合法值（不写入 NaN）。
        self.viewport_w = self.safeViewport(viewport_w);
        self.viewport_h = self.safeViewport(viewport_h);
        self.pitch = self.safePitch();
        self.zoom = self.safeZoom();
        self.target = clampWorld(self.target);
        if (!(std.math.isFinite(self.near) and self.near > 0)) self.near = 0.1;
        if (!(std.math.isFinite(self.far) and self.far > self.near)) self.far = self.near + 200.0;
        self.view_target = if (self.snap_pixels) self.snapToPixel(self.target) else self.target;
        const he = self.halfExtents();
        self.view = Mat4.lookat(self.eyeFor(self.view_target), self.view_target, Vec3.up);
        self.proj = Mat4.ortho(-he.x, he.x, -he.y, he.y, self.near, self.far);
    }

    pub fn screenToRay(self: *const IsoCamera, sx: f32, sy: f32) Ray {
        const he = self.halfExtents();
        const ndc_x = sanitizeScreen(sx) / self.safeViewport(self.viewport_w) * 2.0 - 1.0;
        const ndc_y = 1.0 - sanitizeScreen(sy) / self.safeViewport(self.viewport_h) * 2.0;
        const base_tgt = if (self.snap_pixels) self.view_target else self.target;
        const origin = self.eyeFor(base_tgt)
            .add(self.right().scale(ndc_x * he.x))
            .add(self.camUp().scale(ndc_y * he.y));
        return .{ .origin = origin, .dir = self.forward() };
    }

    pub fn screenToPlane(self: *const IsoCamera, sx: f32, sy: f32, plane_y: f32) ?Vec3 {
        if (!std.math.isFinite(plane_y)) return null;
        const ray = self.screenToRay(sx, sy);
        if (@abs(ray.dir.y) < 1e-6) return null;
        const t = (plane_y - ray.origin.y) / ray.dir.y;
        if (!std.math.isFinite(t)) return null;
        const p = ray.origin.add(ray.dir.scale(t));
        if (!vec3Finite(p)) return null;
        return p;
    }

    pub fn worldToScreen(self: *const IsoCamera, p: Vec3) Vec2 {
        // 非有限输入 -> 屏幕原点（有限值）
        if (!vec3Finite(p)) return Vec2.zero;
        const clip = transform4(self.proj.mul(self.view), Vec4.new(p.x, p.y, p.z, 1.0));
        if (!std.math.isFinite(clip.w) or @abs(clip.w) < 1e-12) return Vec2.zero;
        const nx = clip.x / clip.w;
        const ny = clip.y / clip.w;
        const out = Vec2.new((nx + 1.0) * 0.5 * self.safeViewport(self.viewport_w), (1.0 - ny) * 0.5 * self.safeViewport(self.viewport_h));
        if (!std.math.isFinite(out.x) or !std.math.isFinite(out.y)) return Vec2.zero;
        return out;
    }
};

/// 返回 R*proj，使 clip 空间 z' = 0.25 z + 0.75 w（世界深度压到 NDC [0.5, 1]）。
pub fn remapDepthToBackHalf(proj: Mat4) Mat4 {
    var r = Mat4.identity;
    r.m[2][2] = 0.25; // row 2, col 2
    r.m[3][2] = 0.75; // row 2, col 3 (w)
    return r.mul(proj);
}

// ---------------------------------------------------------------- tests

const eps = 1e-3;

fn approx(a: f32, b: f32) !void {
    try std.testing.expectApproxEqAbs(a, b, eps);
}

test "rotate / billboard convention" {
    const yaws = [_]f32{ 0, 45, 90, 135, 200, 315 };
    for (yaws) |yaw| {
        const m = billboardRotation(yaw);
        const v = transform4(m, Vec4.new(0, 0, 1, 0));
        try approx(v.x, @sin(rad(yaw)));
        try approx(v.y, 0);
        try approx(v.z, @cos(rad(yaw)));
        // 与 Mat4.rotate 一致
        const v2 = transform4(Mat4.rotate(yaw, Vec3.up), Vec4.new(0, 0, 1, 0));
        try approx(v2.x, v.x);
        // 与相机 eye-target 水平分量同向
        var cam = IsoCamera{};
        cam.yaw = yaw;
        const d = cam.eyePosition().sub(cam.target);
        const h = Vec2.new(d.x, d.z).norm();
        try approx(h.x, v.x);
        try approx(h.y, v.z);
    }
}

test "depth remap" {
    var cam = IsoCamera{};
    cam.update(1280, 720);
    const m = remapDepthToBackHalf(cam.proj);
    const near_c = transform4(m, Vec4.new(0, 0, -cam.near, 1));
    const far_c = transform4(m, Vec4.new(0, 0, -cam.far, 1));
    try approx(near_c.z / near_c.w, 0.5);
    try approx(far_c.z / far_c.w, 1.0);
}

test "worldToScreen / screenToPlane inverse" {
    var cam = IsoCamera{};
    cam.target = Vec3.new(10, 1, 12);
    cam.yaw = 135;
    cam.zoom = 1.5;
    cam.update(1280, 720);
    const c = cam.worldToScreen(cam.target);
    try std.testing.expectApproxEqAbs(c.x, 640, eps);
    try std.testing.expectApproxEqAbs(c.y, 360, eps);

    var prng = std.Random.DefaultPrng.init(1234);
    const rnd = prng.random();
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        const p = Vec3.new(
            cam.target.x + (rnd.float(f32) - 0.5) * 10,
            rnd.float(f32) * 4,
            cam.target.z + (rnd.float(f32) - 0.5) * 10,
        );
        const s = cam.worldToScreen(p);
        const q = cam.screenToPlane(s.x, s.y, p.y).?;
        try std.testing.expectApproxEqAbs(p.x, q.x, eps);
        try std.testing.expectApproxEqAbs(p.y, q.y, eps);
        try std.testing.expectApproxEqAbs(p.z, q.z, eps);
    }
}

test "rotateStep and tick converge" {
    var cam = IsoCamera{};
    cam.rotateStep(1);
    try std.testing.expectEqual(@as(f32, 135), cam.yaw_goal);
    cam.rotateStep(-3);
    try std.testing.expectEqual(@as(f32, -135), cam.yaw_goal);
    var i: usize = 0;
    while (i < 600) : (i += 1) cam.tick(1.0 / 60.0);
    try std.testing.expectEqual(cam.yaw_goal, cam.yaw);
}

test "zoom clamp" {
    var cam = IsoCamera{};
    cam.setZoom(100);
    try approx(cam.zoom, 4);
    cam.setZoom(0.01);
    try approx(cam.zoom, 0.25);
}

test "follow smoothing" {
    var cam = IsoCamera{};
    cam.follow_goal = Vec3.new(10, 0, 10);
    cam.tick(1.0 / 60.0);
    try std.testing.expect(cam.target.x > 0 and cam.target.x < 10);
    var i: usize = 0;
    while (i < 600) : (i += 1) cam.tick(1.0 / 60.0);
    try std.testing.expectApproxEqAbs(@as(f32, 10), cam.target.x, 0.01);
    cam.follow_smoothing = 0;
    cam.follow_goal = Vec3.new(-3, 1, 5);
    cam.tick(1.0 / 60.0);
    try approx(cam.target.x, -3);
    try approx(cam.target.z, 5);
}

test "tick does not overshoot yaw_goal for large dt" {
    for ([_]f32{ 1.0, 10.0 }) |dt| {
        var cam = IsoCamera{};
        cam.yaw_goal = 135;
        cam.tick(dt);
        try std.testing.expect(cam.yaw <= 135 and cam.yaw >= 45);
        cam.yaw = 45;
        cam.yaw_goal = -90;
        cam.tick(dt);
        try std.testing.expect(cam.yaw >= -90 and cam.yaw <= 45);
    }
}

test "update(0,0) yields finite ray" {
    var cam = IsoCamera{};
    cam.update(0, 0);
    const r = cam.screenToRay(0, 0);
    for ([_]f32{ r.origin.x, r.origin.y, r.origin.z, r.dir.x, r.dir.y, r.dir.z }) |v| {
        try std.testing.expect(std.math.isFinite(v));
    }
}

fn camFinite(cam: *const IsoCamera) !void {
    const vals = [_]f32{ cam.target.x, cam.target.y, cam.target.z, cam.yaw, cam.yaw_goal, cam.zoom, cam.pitch, cam.viewport_w, cam.viewport_h };
    for (vals) |v| try std.testing.expect(std.math.isFinite(v));
}

test "garbage input: setZoom / rotateStep / tick" {
    const nan = std.math.nan(f32);
    const inf = std.math.inf(f32);
    var cam = IsoCamera{};
    cam.setZoom(2);
    cam.setZoom(nan);
    try std.testing.expectEqual(@as(f32, 2), cam.zoom);
    cam.setZoom(inf);
    try approx(cam.zoom, 2); // Inf 视为非法，忽略
    cam.setZoom(-5);
    try approx(cam.zoom, 0.25);
    cam.rotateStep(std.math.maxInt(i32));
    cam.rotateStep(std.math.minInt(i32));
    try camFinite(&cam);
    // 非法 dt 视为 0：状态不变
    cam.yaw = 45;
    cam.yaw_goal = 135;
    cam.follow_goal = Vec3.new(10, 0, 10);
    for ([_]f32{ nan, inf, -inf, -1 }) |dt| {
        cam.tick(dt);
        try std.testing.expectEqual(@as(f32, 45), cam.yaw);
        try std.testing.expectEqual(@as(f32, 0), cam.target.x);
    }
    cam.tick(1e30); // 巨大 dt 仍有限且不越过目标
    try camFinite(&cam);
    // follow_goal / smoothing 为 NaN 不得污染 target
    cam.target = Vec3.zero;
    cam.follow_goal = Vec3.new(nan, 0, 0);
    cam.tick(0.1);
    try std.testing.expectEqual(@as(f32, 0), cam.target.x);
    cam.follow_goal = Vec3.new(1, 2, 3);
    cam.follow_smoothing = nan;
    cam.tick(0.1);
    try camFinite(&cam);
    cam.yaw = nan;
    cam.yaw_goal = nan;
    cam.tick(0.1);
    try camFinite(&cam);
}

test "extreme finite values never write NaN/Inf into camera state" {
    // update: 超大视口 / view_height / target
    const sizes = [_][2]f32{ .{ 3e38, 1 }, .{ 1, 3e38 }, .{ 3e38, 3e38 } };
    for (sizes) |s| {
        var cam = IsoCamera{};
        cam.update(s[0], s[1]);
        for (cam.proj.m) |col| for (col) |v| try std.testing.expect(std.math.isFinite(v));
        for (cam.view.m) |col| for (col) |v| try std.testing.expect(std.math.isFinite(v));
    }
    {
        var cam = IsoCamera{};
        cam.view_height = 3e38;
        cam.target = Vec3.new(3e38, -3e38, 3e38);
        cam.update(1280, 720);
        for (cam.proj.m) |col| for (col) |v| try std.testing.expect(std.math.isFinite(v));
        for (cam.view.m) |col| for (col) |v| try std.testing.expect(std.math.isFinite(v));
    }
    // tick: yaw 差值溢出
    for ([_]f32{ 0, 0.016, 1 }) |dt| {
        var cam = IsoCamera{};
        cam.yaw = 3e38;
        cam.yaw_goal = -3e38;
        cam.tick(dt);
        try std.testing.expect(std.math.isFinite(cam.yaw));
    }
    // tick: follow 插值溢出
    for ([_]f32{ 0, 0.016, 1 }) |dt| {
        var cam = IsoCamera{};
        cam.target = Vec3.new(3e38, 0, 0);
        cam.follow_goal = Vec3.new(-3e38, 0, 0);
        cam.tick(dt);
        try std.testing.expect(vec3Finite(cam.target));
    }
}

test "garbage input: update / pitch / projections" {
    const nan = std.math.nan(f32);
    const inf = std.math.inf(f32);
    var cam = IsoCamera{};
    for ([_]f32{ 90, 0, -10, 1000, nan, inf }) |pitch| {
        cam.pitch = pitch;
        cam.update(1280, 720);
        try std.testing.expect(cam.pitch >= 1 and cam.pitch <= 89);
        const f = cam.forward();
        try std.testing.expect(std.math.isFinite(f.x) and std.math.isFinite(f.y) and std.math.isFinite(f.z));
        const q = cam.screenToPlane(640, 360, 0);
        try std.testing.expect(q != null and std.math.isFinite(q.?.x));
    }
    cam = IsoCamera{};
    cam.update(nan, inf);
    try camFinite(&cam);
    cam.update(-5, 0);
    try camFinite(&cam);
    cam.zoom = nan;
    cam.min_zoom = 0;
    cam.max_zoom = nan;
    cam.view_height = -3;
    cam.near = nan;
    cam.far = 0;
    cam.distance = nan;
    cam.target = Vec3.new(nan, 0, 0);
    cam.update(800, 600);
    try camFinite(&cam);
    for (cam.proj.m) |col| for (col) |v| try std.testing.expect(std.math.isFinite(v));
    for (cam.view.m) |col| for (col) |v| try std.testing.expect(std.math.isFinite(v));

    cam = IsoCamera{};
    cam.update(1280, 720);
    const bad = [_]f32{ nan, inf, -inf, 1e30, -1e30 };
    for (bad) |a| for (bad) |b| {
        const r = cam.screenToRay(a, b);
        for ([_]f32{ r.origin.x, r.origin.y, r.origin.z, r.dir.x, r.dir.y, r.dir.z }) |v| try std.testing.expect(std.math.isFinite(v));
        if (cam.screenToPlane(a, b, 0)) |p| try std.testing.expect(std.math.isFinite(p.x + p.y + p.z));
        const s = cam.worldToScreen(Vec3.new(a, b, 0));
        try std.testing.expect(std.math.isFinite(s.x) and std.math.isFinite(s.y));
    };
    try std.testing.expect(cam.screenToPlane(1, 1, nan) == null);
    try std.testing.expect(cam.screenToPlane(1, 1, inf) == null);
    const m = billboardRotation(nan);
    for (m.m) |col| for (col) |v| try std.testing.expect(std.math.isFinite(v));
}

test "iso_ppu produces 128x64 tile diamond and 32px height unit" {
    var cam = IsoCamera{
        .yaw = 45.0,
        .pitch = 30.0,
        .pixels_per_unit = iso_ppu,
        .snap_pixels = false,
    };
    cam.update(1280, 720);

    const p00 = cam.worldToScreen(Vec3.new(0, 0, 0));
    const p10 = cam.worldToScreen(Vec3.new(1, 0, 0));
    const p01 = cam.worldToScreen(Vec3.new(0, 0, 1));
    const p11 = cam.worldToScreen(Vec3.new(1, 0, 1));
    const ph1 = cam.worldToScreen(Vec3.new(0, iso_height_unit, 0));

    // Horizontal diamond width |p10.x - p01.x| == 128 px
    try std.testing.expectApproxEqAbs(@as(f32, 128.0), @abs(p10.x - p01.x), 0.05);
    // Vertical diamond height |p00.y - p11.y| == 64 px
    try std.testing.expectApproxEqAbs(@as(f32, 64.0), @abs(p00.y - p11.y), 0.05);
    // 1 height unit == 32 px vertically
    try std.testing.expectApproxEqAbs(@as(f32, 32.0), @abs(p00.y - ph1.y), 0.05);
}

test "effectivePpu and snapToPixel" {
    var cam = IsoCamera{ .pixels_per_unit = -5 };
    try std.testing.expectEqual(@as(f32, 0), cam.effectivePpu());
    cam.pixels_per_unit = std.math.nan(f32);
    try std.testing.expectEqual(@as(f32, 0), cam.effectivePpu());

    cam.pixels_per_unit = iso_ppu;
    cam.snap_pixels = true;
    cam.target = Vec3.new(1.2345, 0.123, 2.3456);
    cam.update(1280, 720);

    // snapToPixel is idempotent
    const s1 = cam.snapToPixel(cam.target);
    const s2 = cam.snapToPixel(s1);
    try approx(s1.x, s2.x);
    try approx(s1.y, s2.y);
    try approx(s1.z, s2.z);

    // view_target matches snapped target
    try approx(cam.view_target.x, s1.x);
    try approx(cam.view_target.y, s1.y);
    try approx(cam.view_target.z, s1.z);

    // Non-finite input returns zero
    const sz = cam.snapToPixel(Vec3.new(std.math.nan(f32), 0, 0));
    try approx(sz.x, 0);
    try approx(sz.y, 0);
    try approx(sz.z, 0);
}
