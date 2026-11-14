//! 纯逻辑：实体、动画、移动与路径跟随。
const std = @import("std");
const delve = @import("delve");
const math = delve.math;
const colors = delve.colors;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Allocator = std.mem.Allocator;
const coords = @import("coords.zig");
const camera = @import("camera.zig");
const tilemap = @import("tilemap.zig");
const lightmap = @import("lightmap.zig");
pub const Dir = coords.Dir;
pub const GridPos = coords.GridPos;
const IsoCamera = camera.IsoCamera;
const TileMap = tilemap.TileMap;
const LightMap = lightmap.LightMap;

pub const PickHit = struct {
    id: u32,
    u: f32,
    v: f32,
};

pub const Entity = struct {
    id: u32 = 0,
    gen: u16 = 0,
    alive: bool = false,
    visible: bool = true,
    lit: bool = true,
    pickable: bool = true,
    pos: Vec3 = Vec3.zero, // 脚底
    size: Vec2 = Vec2.new(1, 1.5),
    sheet: u32 = 0,
    frame: u16 = 0,
    flip_x: bool = false,
    tint: colors.Color = colors.white,
    light: [3]f32 = .{ 1, 1, 1 },
    anim_start: u16 = 0,
    anim_len: u16 = 0,
    anim_fps: f32 = 0,
    anim_time: f32 = 0,
    anim_loop: bool = true,
    speed: f32 = 3.0,
    path: [256]GridPos = undefined,
    path_len: u16 = 0,
    path_idx: u16 = 0,
    move_goal: ?Vec3 = null,
    facing: Dir = .down,
    last_move: Vec2 = Vec2.zero,
};

pub const World = struct {
    allocator: Allocator,
    entities: std.ArrayList(Entity),
    free: std.ArrayList(u32),

    pub const Iterator = struct {
        items: []Entity,
        i: usize = 0,
        pub fn next(self: *Iterator) ?*Entity {
            while (self.i < self.items.len) {
                const e = &self.items[self.i];
                self.i += 1;
                if (e.alive) return e;
            }
            return null;
        }
    };

    pub fn init(allocator: Allocator) World {
        return .{ .allocator = allocator, .entities = .empty, .free = .empty };
    }

    pub fn deinit(self: *World) void {
        self.entities.deinit(self.allocator);
        self.free.deinit(self.allocator);
    }

    pub fn spawn(self: *World, e: Entity) !u32 {
        var ent = e;
        ent.alive = true;
        sanitizeEntity(&ent);
        if (self.free.items.len > 0) {
            const slot = self.free.pop().?;
            const gen = self.entities.items[slot].gen;
            ent.gen = gen;
            ent.id = (@as(u32, gen) << 16) | (slot + 1);
            self.entities.items[slot] = ent;
            return ent.id;
        }
        // slot + 1 必须能放入低 16 位且不为 0（1..65535）
        const slot: u32 = std.math.cast(u32, self.entities.items.len) orelse return error.TooManyEntities;
        if (slot >= 65535) return error.TooManyEntities;
        ent.gen = 0;
        ent.id = slot + 1;
        try self.entities.append(self.allocator, ent);
        return ent.id;
    }

    pub fn despawn(self: *World, id: u32) void {
        const e = self.get(id) orelse return;
        const slot: u32 = (id & 0xFFFF) - 1;
        e.alive = false;
        e.gen +%= 1;
        // 空间已预留不会失败的情况下才回收；失败则槽位仅不复用
        self.free.append(self.allocator, slot) catch {};
    }

    pub fn clear(self: *World) void {
        for (self.entities.items) |*e| {
            if (e.alive) self.despawn(e.id);
        }
    }

    pub fn get(self: *World, id: u32) ?*Entity {
        const low = id & 0xFFFF;
        if (low == 0 or low > self.entities.items.len) return null;
        const e = &self.entities.items[low - 1];
        const gen: u16 = @intCast(id >> 16);
        if (!e.alive or e.gen != gen) return null;
        return e;
    }

    pub fn setPath(self: *World, id: u32, path: []const GridPos) void {
        const e = self.get(id) orelse return;
        const n = @min(path.len, e.path.len);
        for (0..n) |i| e.path[i] = path[i];
        e.path_len = std.math.cast(u16, n) orelse 0; // n <= 256
        e.path_idx = 0;
        e.move_goal = null;
    }

    pub fn moveTo(self: *World, id: u32, goal: Vec3) void {
        const e = self.get(id) orelse return;
        // 非有限目标忽略（保持原状态）
        if (!finite3(goal)) return;
        e.path_len = 0;
        e.path_idx = 0;
        e.move_goal = goal;
    }

    pub fn isMoving(self: *World, id: u32) bool {
        const e = self.get(id) orelse return false;
        return e.path_idx < e.path_len or e.move_goal != null;
    }

    pub fn iterator(self: *World) Iterator {
        return .{ .items = self.entities.items };
    }

    pub fn tick(self: *World, dt_in: f32, map: *const TileMap, cam_yaw: f32) void {
        const dt = sanitizeDt(dt_in);
        for (self.entities.items) |*e| {
            if (!e.alive) continue;
            tickAnim(e, dt);
            tickMove(e, dt, map, cam_yaw);
        }
    }

    pub fn applyLight(self: *World, lm: *const LightMap, map: *const TileMap, dt_in: f32) void {
        const dt = sanitizeDt(dt_in);
        const k = std.math.clamp(dt * 12.0, 0.0, 1.0);
        for (self.entities.items) |*e| {
            if (!e.alive) continue;
            if (!e.lit) {
                e.light = .{ 1, 1, 1 };
                continue;
            }
            const target: [3]f32 = if (map.worldToTile(e.pos)) |g|
                lm.sample(g.x, g.y)
            else
                .{ 1, 1, 1 };
            for (0..3) |c| {
                e.light[c] += (target[c] - e.light[c]) * k;
            }
        }
    }

    pub fn pickCandidates(self: *const World, cam: *const IsoCamera, sx: f32, sy: f32, out: []PickHit) usize {
        if (out.len == 0 or !std.math.isFinite(sx) or !std.math.isFinite(sy)) return 0;
        const ray = cam.screenToRay(sx, sy);
        const right = cam.right();
        const up = Vec3.up;
        const normal = right.cross(up);
        const denom = ray.dir.dot(normal);
        if (!std.math.isFinite(denom) or @abs(denom) < 1e-6) return 0;

        const Candidate = struct { hit: PickHit, t: f32 };
        var count: usize = 0;
        var buf: [256]Candidate = undefined;

        for (self.entities.items) |e| {
            if (!e.alive or !e.visible or !e.pickable) continue;
            if (e.size.x <= 0 or e.size.y <= 0) continue;
            const t = e.pos.sub(ray.origin).dot(normal) / denom;
            if (!std.math.isFinite(t) or t < 0) continue;
            const p = ray.origin.add(ray.dir.scale(t));
            const d = p.sub(e.pos);
            const lx = d.dot(right);
            const ly = d.y;
            const half_w = e.size.x * 0.5;
            if (lx < -half_w or lx > half_w or ly < 0 or ly > e.size.y) continue;
            const u = std.math.clamp(lx / e.size.x + 0.5, 0.0, 1.0);
            const v = std.math.clamp(1.0 - ly / e.size.y, 0.0, 1.0);
            const cand = Candidate{ .hit = .{ .id = e.id, .u = u, .v = v }, .t = t };

            // 插入排序，保持由近到远（t 升序）
            var pos = count;
            if (count == buf.len) {
                if (t >= buf[count - 1].t) continue;
                pos = count - 1;
            } else {
                count += 1;
            }
            while (pos > 0 and buf[pos - 1].t > t) : (pos -= 1) {
                buf[pos] = buf[pos - 1];
            }
            buf[pos] = cand;
        }

        const n = @min(count, out.len);
        for (0..n) |i| out[i] = buf[i].hit;
        return n;
    }
};

fn sanitizeDt(dt: f32) f32 {
    if (!std.math.isFinite(dt) or dt < 0) return 0;
    return @min(dt, 3600.0);
}

fn finite3(v: Vec3) bool {
    return std.math.isFinite(v.x) and std.math.isFinite(v.y) and std.math.isFinite(v.z);
}

fn finiteOr(v: f32, d: f32) f32 {
    return if (std.math.isFinite(v)) v else d;
}

/// 把实体中的浮点/索引字段修复为安全值，保证 NaN/Inf 不进入持久状态。
fn sanitizeEntity(e: *Entity) void {
    e.pos = Vec3.new(finiteOr(e.pos.x, 0), finiteOr(e.pos.y, 0), finiteOr(e.pos.z, 0));
    e.size = Vec2.new(finiteOr(e.size.x, 1), finiteOr(e.size.y, 1.5));
    e.speed = if (std.math.isFinite(e.speed) and e.speed >= 0) e.speed else 0;
    e.anim_fps = if (std.math.isFinite(e.anim_fps) and e.anim_fps >= 0) e.anim_fps else 0;
    e.anim_time = if (std.math.isFinite(e.anim_time) and e.anim_time >= 0) @min(e.anim_time, 1.0e9) else 0;
    e.last_move = Vec2.new(finiteOr(e.last_move.x, 0), finiteOr(e.last_move.y, 0));
    if (e.move_goal) |g| {
        if (!finite3(g)) e.move_goal = null;
    }
    // path 内容未初始化（undefined），新实体不携带路径
    e.path_len = 0;
    e.path_idx = 0;
}

fn tickAnim(e: *Entity, dt: f32) void {
    if (!std.math.isFinite(e.anim_fps)) e.anim_fps = 0; // 修复持久状态
    if (e.anim_len == 0 or e.anim_fps <= 0) return;
    if (!std.math.isFinite(e.anim_time) or e.anim_time < 0) e.anim_time = 0;
    e.anim_time = @min(e.anim_time + dt, 1.0e9);
    var v = e.anim_time * e.anim_fps;
    if (!std.math.isFinite(v)) v = 1.0e9; // 溢出 = 极大值，下面再钳制（不回跳到第 0 帧）
    const raw = @floor(std.math.clamp(v, 0.0, 1.0e9)); // 有限且 [0, 1e9]，可安全转 u32
    const n: u32 = @intFromFloat(raw);
    const idx: u32 = if (e.anim_loop) n % e.anim_len else @min(n, @as(u32, e.anim_len) - 1);
    const sum: u32 = @as(u32, e.anim_start) + idx;
    e.frame = std.math.cast(u16, sum) orelse std.math.maxInt(u16);
}

fn tickMove(e: *Entity, dt: f32, map: *const TileMap, cam_yaw: f32) void {
    // pub 字段可能被外部直接写入：先修复，再运算
    if (!finite3(e.pos)) {
        e.pos = Vec3.new(finiteOr(e.pos.x, 0), finiteOr(e.pos.y, 0), finiteOr(e.pos.z, 0));
        e.move_goal = null;
        e.path_len = 0;
        e.path_idx = 0;
    }
    if (e.path_len > e.path.len) e.path_len = @intCast(e.path.len);
    var tx: f32 = 0;
    var tz: f32 = 0;
    var from_path = false;
    if (e.path_idx < e.path_len) {
        const p = e.path[e.path_idx];
        const c = map.tileCenter(p.x, p.y);
        tx = c.x;
        tz = c.z;
        from_path = true;
    } else if (e.move_goal) |g| {
        if (!std.math.isFinite(g.x) or !std.math.isFinite(g.z)) {
            e.move_goal = null;
            return;
        }
        tx = g.x;
        tz = g.z;
    } else return;

    const dx = tx - e.pos.x;
    const dz = tz - e.pos.z;
    const dist = @sqrt(dx * dx + dz * dz);
    if (!std.math.isFinite(dist)) {
        // 距离溢出（位置/目标极端）：放弃本次移动目标，保持状态有限
        e.move_goal = null;
        e.path_len = 0;
        e.path_idx = 0;
        return;
    }
    if (!(std.math.isFinite(e.speed) and e.speed >= 0)) e.speed = 0; // 修复持久状态
    const speed = e.speed;
    const step = speed * dt; // 有限或 +Inf（均可比较）；dt 已规范化，不会产生 NaN
    var mx: f32 = undefined;
    var mz: f32 = undefined;
    if (dist <= step) {
        mx = dx;
        mz = dz;
        e.pos.x = tx;
        e.pos.z = tz;
        if (from_path) {
            e.path_idx += 1;
            if (e.path_idx >= e.path_len) {
                e.path_idx = 0;
                e.path_len = 0;
            }
        } else {
            e.move_goal = null;
        }
    } else {
        // 此分支 dist > step >= 0，故 dist > 0，无除零
        mx = dx / dist * step;
        mz = dz / dist * step;
        e.pos.x += mx;
        e.pos.z += mz;
    }

    if (mx * mx + mz * mz > 1e-12) {
        e.last_move = Vec2.new(mx, mz);
        if (coords.screenDirection(mx, mz, cam_yaw)) |d| e.facing = d;
    }

    if (map.worldToTile(e.pos)) |g| {
        const top = map.topY(g.x, g.y);
        e.pos.y += (top - e.pos.y) * @min(1.0, 15.0 * dt);
    }
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

fn testMap() !TileMap {
    var m = try TileMap.init(testing.allocator, 8, 8);
    errdefer m.deinit();
    _ = try m.defineTile(.{ .top = 1, .side = 1 });
    m.fill(1, 0);
    return m;
}

test "spawn / despawn / reuse" {
    var w = World.init(testing.allocator);
    defer w.deinit();
    const a = try w.spawn(.{});
    const b = try w.spawn(.{ .sheet = 7 });
    try testing.expectEqual(@as(u32, 1), a);
    try testing.expectEqual(@as(u32, 2), b);
    try testing.expectEqual(@as(u32, 7), w.get(b).?.sheet);
    w.despawn(a);
    try testing.expect(w.get(a) == null);
    w.despawn(a); // 重复无害
    const c = try w.spawn(.{ .sheet = 9 });
    try testing.expectEqual(@as(u32, (1 << 16) | 1), c);
    try testing.expect(w.get(a) == null);
    try testing.expectEqual(@as(u32, 9), w.get(c).?.sheet);
    try testing.expect(w.get(c).?.alive);
    try testing.expect(w.get(0) == null);
    try testing.expect(w.get(99) == null);
    var it = w.iterator();
    var n: usize = 0;
    while (it.next()) |_| n += 1;
    try testing.expectEqual(@as(usize, 2), n);
}

test "moveTo arrives" {
    var m = try testMap();
    defer m.deinit();
    var w = World.init(testing.allocator);
    defer w.deinit();
    const id = try w.spawn(.{ .pos = Vec3.new(0.5, 0, 0.5), .speed = 4 });
    try testing.expect(!w.isMoving(id));
    w.moveTo(id, Vec3.new(3.5, 0, 0.5));
    try testing.expect(w.isMoving(id));
    var i: usize = 0;
    while (i < 200 and w.isMoving(id)) : (i += 1) w.tick(1.0 / 60.0, &m, 45);
    try testing.expect(!w.isMoving(id));
    const e = w.get(id).?;
    try testing.expectApproxEqAbs(@as(f32, 3.5), e.pos.x, 1e-4);
    try testing.expect(e.last_move.x > 0);
}

test "setPath completes, height follows, facing" {
    var m = try testMap();
    defer m.deinit();
    m.set(2, 0, 1, 2); // top = 1
    var w = World.init(testing.allocator);
    defer w.deinit();
    const id = try w.spawn(.{ .pos = m.tileCenter(0, 0) });
    const path = [_]GridPos{ .{ .x = 1, .y = 0 }, .{ .x = 2, .y = 0 }, .{ .x = 2, .y = 1 } };
    w.setPath(id, &path);
    try testing.expect(w.isMoving(id));
    var i: usize = 0;
    var saw_right = false;
    while (i < 1000 and w.isMoving(id)) : (i += 1) {
        w.tick(1.0 / 60.0, &m, 0);
        if (w.get(id).?.facing == .right) saw_right = true;
    }
    try testing.expect(saw_right); // yaw 0 下 +X = right
    try testing.expect(!w.isMoving(id));
    try testing.expectApproxEqAbs(@as(f32, 2.5), w.get(id).?.pos.x, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 1.5), w.get(id).?.pos.z, 1e-4);
    for (0..120) |_| w.tick(1.0 / 60.0, &m, 0); // 静止不改变
    // 最后一段 +Z => down（yaw 0）
    try testing.expectEqual(Dir.down, w.get(id).?.facing);
    // 经过高台后回到平地，y 平滑回 0（至少已接近）
    try testing.expect(w.get(id).?.pos.y < 0.5);
}

test "setPath truncates to 64" {
    var w = World.init(testing.allocator);
    defer w.deinit();
    const id = try w.spawn(.{});
    var big: [300]GridPos = undefined;
    for (&big, 0..) |*p, i| p.* = .{ .x = @intCast(i), .y = 0 };
    w.setPath(id, &big);
    try testing.expectEqual(@as(u16, 256), w.get(id).?.path_len);
}

test "animation loop and non-loop" {
    var m = try testMap();
    defer m.deinit();
    var w = World.init(testing.allocator);
    defer w.deinit();
    const a = try w.spawn(.{ .anim_start = 4, .anim_len = 4, .anim_fps = 10, .anim_loop = true });
    const b = try w.spawn(.{ .anim_start = 4, .anim_len = 4, .anim_fps = 10, .anim_loop = false });
    w.tick(0.25, &m, 0); // t=0.25 -> idx 2
    try testing.expectEqual(@as(u16, 6), w.get(a).?.frame);
    try testing.expectEqual(@as(u16, 6), w.get(b).?.frame);
    w.tick(0.25, &m, 0); // t=0.5 -> idx 5
    try testing.expectEqual(@as(u16, 5), w.get(a).?.frame); // 5%4=1 -> 5
    try testing.expectEqual(@as(u16, 7), w.get(b).?.frame); // 停在最后一帧
    const c = try w.spawn(.{ .frame = 3 }); // 无动画不动
    w.tick(1, &m, 0);
    try testing.expectEqual(@as(u16, 3), w.get(c).?.frame);
}

test "spawn reuse fully resets fields" {
    var w = World.init(testing.allocator);
    defer w.deinit();
    const a = try w.spawn(.{ .pos = Vec3.new(9, 9, 9), .frame = 7, .sheet = 3, .speed = 8 });
    {
        const e = w.get(a).?;
        e.path_len = 5;
        e.path_idx = 2;
        e.anim_len = 3;
        e.move_goal = Vec3.new(1, 2, 3);
        e.facing = .up;
    }
    w.despawn(a);
    const c = try w.spawn(.{});
    try testing.expectEqual(@as(u32, (1 << 16) | 1), c);
    try testing.expect(w.get(a) == null);
    const e = w.get(c).?;
    try testing.expectEqual(@as(f32, 0), e.pos.x);
    try testing.expectEqual(@as(f32, 0), e.pos.y);
    try testing.expectEqual(@as(f32, 0), e.pos.z);
    try testing.expectEqual(@as(u16, 0), e.frame);
    try testing.expectEqual(@as(u32, 0), e.sheet);
    try testing.expectEqual(@as(f32, 3.0), e.speed);
    try testing.expectEqual(@as(u8, 0), e.path_len);
    try testing.expectEqual(@as(u8, 0), e.path_idx);
    try testing.expectEqual(@as(u16, 0), e.anim_len);
    try testing.expect(e.move_goal == null);
    try testing.expectEqual(Dir.down, e.facing);
}

test "tickAnim with anim_len 0 keeps frame; frame clamps at u16" {
    var m = try testMap();
    defer m.deinit();
    var w = World.init(testing.allocator);
    defer w.deinit();
    const a = try w.spawn(.{ .frame = 5, .anim_len = 0, .anim_fps = 10 });
    const b = try w.spawn(.{ .anim_start = 65535, .anim_len = 4, .anim_fps = 10 });
    w.tick(0.5, &m, 0);
    try testing.expectEqual(@as(u16, 5), w.get(a).?.frame);
    try testing.expectEqual(@as(u16, 65535), w.get(b).?.frame);
}

test "huge entity pos does not crash" {
    var m = try testMap();
    defer m.deinit();
    var w = World.init(testing.allocator);
    defer w.deinit();
    const id = try w.spawn(.{ .pos = Vec3.new(1e10, 0, 0.5) });
    w.moveTo(id, Vec3.new(3.5, 0, 0.5));
    for (0..10) |_| w.tick(1.0 / 60.0, &m, 45);
    try entFinite(w.get(id).?);
    const nan = std.math.nan(f32);
    w.get(id).?.pos = Vec3.new(nan, 0, nan);
    for (0..3) |_| w.tick(1.0 / 60.0, &m, 45);
    try entFinite(w.get(id).?);
}

fn entFinite(e: *const Entity) !void {
    const vals = [_]f32{ e.pos.x, e.pos.y, e.pos.z, e.size.x, e.size.y, e.speed, e.anim_fps, e.anim_time, e.last_move.x, e.last_move.y };
    for (vals) |v| try testing.expect(std.math.isFinite(v));
}

test "garbage input: tick dt" {
    var m = try testMap();
    defer m.deinit();
    var w = World.init(testing.allocator);
    defer w.deinit();
    const id = try w.spawn(.{ .pos = Vec3.new(0.5, 0, 0.5), .anim_start = 1, .anim_len = 3, .anim_fps = 10 });
    w.moveTo(id, Vec3.new(5.5, 0, 0.5));
    const nan = std.math.nan(f32);
    const inf = std.math.inf(f32);
    for ([_]f32{ nan, inf, -inf, -1, -1e30 }) |dt| {
        w.tick(dt, &m, 45);
        const e = w.get(id).?;
        try testing.expectEqual(@as(f32, 0.5), e.pos.x); // dt 视为 0：不动
        try testing.expectEqual(@as(u16, 1), e.frame);
        try entFinite(e);
    }
    w.tick(1e30, &m, nan); // 巨大 dt、NaN yaw
    try entFinite(w.get(id).?);
    try testing.expect(w.get(id).?.frame >= 1 and w.get(id).?.frame <= 3);
}

test "garbage input: moveTo / spawn / speed" {
    var m = try testMap();
    defer m.deinit();
    var w = World.init(testing.allocator);
    defer w.deinit();
    const nan = std.math.nan(f32);
    const inf = std.math.inf(f32);
    const id = try w.spawn(.{ .pos = Vec3.new(1.5, 0, 1.5) });
    w.moveTo(id, Vec3.new(nan, 0, 1));
    w.moveTo(id, Vec3.new(1, 0, inf));
    w.moveTo(id, Vec3.new(1, -inf, 1));
    try testing.expect(!w.isMoving(id));
    w.moveTo(id, Vec3.new(1, 0, 3.0e38)); // 有限但极端：不得产生 NaN / 挂起
    for (0..5) |_| w.tick(1.0 / 60.0, &m, 0);
    try entFinite(w.get(id).?);
    w.moveTo(id, Vec3.new(-3.0e38, 0, 1));
    w.get(id).?.pos.x = 3.0e38;
    for (0..5) |_| w.tick(1.0 / 60.0, &m, 0);
    try entFinite(w.get(id).?);

    // spawn 带垃圾字段 -> 被修复
    const b = try w.spawn(.{
        .pos = Vec3.new(nan, inf, 2),
        .size = Vec2.new(nan, -inf),
        .speed = nan,
        .anim_fps = inf,
        .anim_time = nan,
        .anim_len = 2,
        .move_goal = Vec3.new(nan, 0, 0),
        .path_len = 200,
        .path_idx = 199,
    });
    const eb = w.get(b).?;
    try entFinite(eb);
    try testing.expect(eb.move_goal == null and !w.isMoving(b));
    for (0..5) |_| w.tick(0.1, &m, 0);
    try entFinite(w.get(b).?);

    // speed 在 spawn 之后被写成 NaN / Inf / 负：不得污染 pos
    const c = try w.spawn(.{ .pos = Vec3.new(1.5, 0, 1.5) });
    for ([_]f32{ nan, inf, -inf, -3 }) |sp| {
        const e = w.get(c).?;
        e.speed = sp;
        e.pos = Vec3.new(1.5, 0, 1.5);
        w.moveTo(c, Vec3.new(4.5, 0, 1.5));
        w.tick(0.1, &m, 0);
        try entFinite(w.get(c).?);
        try testing.expectEqual(@as(f32, 1.5), w.get(c).?.pos.x);
    }
    // tamper：path_len 越界、anim_fps NaN
    const e = w.get(c).?;
    e.path_len = 255;
    e.path_idx = 100;
    e.anim_fps = nan;
    e.anim_len = 2;
    w.tick(0.1, &m, 0);
    try entFinite(w.get(c).?);
}

test "generational ids, clear, path 256 cap, and pickCandidates" {
    var w = World.init(testing.allocator);
    defer w.deinit();

    const id1 = try w.spawn(.{ .pos = Vec3.new(2, 0, 2) });
    try testing.expectEqual(@as(u32, 1), id1);
    w.despawn(id1);
    try testing.expect(w.get(id1) == null);

    const id2 = try w.spawn(.{ .pos = Vec3.new(2, 0, 2) });
    try testing.expect(id2 != id1);
    try testing.expect(w.get(id1) == null);
    try testing.expect(w.get(id2) != null);

    var long_path: [300]GridPos = undefined;
    for (&long_path, 0..) |*p, i| p.* = .{ .x = @intCast(i), .y = 0 };
    w.setPath(id2, &long_path);
    try testing.expectEqual(@as(u16, 256), w.get(id2).?.path_len);

    w.clear();
    try testing.expect(w.get(id2) == null);

    // pickCandidates：近到远排序与 visible/pickable 过滤
    var cam = IsoCamera{};
    cam.target = Vec3.new(5, 0, 5);
    cam.update(1280, 720);
    const front = try w.spawn(.{ .pos = Vec3.new(5.5, 0, 5.5), .size = Vec2.new(1.5, 2.0) });
    const back = try w.spawn(.{ .pos = Vec3.new(4.5, 0, 4.5), .size = Vec2.new(1.5, 2.0) });
    _ = try w.spawn(.{ .pos = Vec3.new(5.0, 0, 5.0), .size = Vec2.new(1.5, 2.0), .visible = false });
    _ = try w.spawn(.{ .pos = Vec3.new(5.0, 0, 5.0), .size = Vec2.new(1.5, 2.0), .pickable = false });

    const sp = cam.worldToScreen(Vec3.new(5.0, 0.5, 5.0));
    var hits: [8]PickHit = undefined;
    const n = w.pickCandidates(&cam, sp.x, sp.y, &hits);
    try testing.expectEqual(@as(usize, 2), n);
    try testing.expectEqual(front, hits[0].id);
    try testing.expectEqual(back, hits[1].id);
}
