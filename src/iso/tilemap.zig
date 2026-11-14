//! 纯逻辑：瓦片地图、高度、A* 寻路、射线拾取。
const std = @import("std");
const delve = @import("delve");
const Vec3 = delve.math.Vec3;
const Allocator = std.mem.Allocator;
const coords = @import("coords.zig");
const camera = @import("camera.zig");
pub const GridPos = coords.GridPos;
pub const Ray = camera.Ray;

pub const TileDef = struct {
    top: u16,
    side: u16,
    solid: bool = false,
    liquid: bool = false,
    @"opaque": bool = false,
    tag: u8 = 0,
    side_cap: u16 = 0xFFFF,
    /// 最下面一段（level 0–1）侧面的图集格；0xFFFF = 同 `side`。用于外观模式的门/窗列（M2-PLAN §5.1）。
    side_base: u16 = 0xFFFF,
};
pub const Flag = struct {
    pub const blocked: u8 = 1;
    pub const @"opaque": u8 = 2;
};
pub const chunk_size: u32 = 16;
/// kind 0 = 空（不绘制、不可走）
pub const Tile = struct { kind: u16 = 0, height: u8 = 0 };
pub const TileHit = struct { x: i32, y: i32, point: Vec3 };

/// 浮点转格子下标；NaN/Inf/超范围返回 null，避免 @intFromFloat 未检查 UB。
fn cellOf(v: f32) ?i32 {
    if (!std.math.isFinite(v) or @abs(v) > 1e6) return null;
    return @intFromFloat(@floor(v));
}

pub const TileMap = struct {
    allocator: Allocator,
    width: u32,
    height: u32,
    tiles: []Tile,
    flags: []u8,
    tag: []u8,
    chunk_dirty: []bool,
    chunks_w: u32,
    chunks_h: u32,
    opacity_version: u32 = 0,
    defs: std.ArrayList(TileDef),
    height_unit: f32 = 0.5,
    base_depth: f32 = 1.0,
    max_step: u8 = 1,
    dirty: bool = true,

    /// 不变量：w、h 及 w*h 均 <= maxInt(i32)，使所有 u32/i32/usize 下标转换不会溢出。
    fn checkDims(w: u32, h: u32) !void {
        const max: u64 = std.math.maxInt(i32);
        if (w > max or h > max or @as(u64, w) * h > max) return error.MapTooLarge;
    }

    fn chunkDims(w: u32, h: u32) struct { cw: u32, ch: u32 } {
        return .{
            .cw = if (w == 0) 0 else (w + chunk_size - 1) / chunk_size,
            .ch = if (h == 0) 0 else (h + chunk_size - 1) / chunk_size,
        };
    }

    pub fn init(allocator: Allocator, w: u32, h: u32) !TileMap {
        try checkDims(w, h);
        const n = @as(usize, w) * h;
        const tiles = try allocator.alloc(Tile, n);
        errdefer allocator.free(tiles);
        @memset(tiles, Tile{});
        const flags = try allocator.alloc(u8, n);
        errdefer allocator.free(flags);
        @memset(flags, 0);
        const tag = try allocator.alloc(u8, n);
        errdefer allocator.free(tag);
        @memset(tag, 0);
        const cd = chunkDims(w, h);
        const chunk_dirty = try allocator.alloc(bool, @as(usize, cd.cw) * cd.ch);
        errdefer allocator.free(chunk_dirty);
        @memset(chunk_dirty, true);
        var defs: std.ArrayList(TileDef) = .empty;
        errdefer defs.deinit(allocator);
        try defs.append(allocator, .{ .top = 0, .side = 0 }); // 下标 0 预留为空
        return .{
            .allocator = allocator,
            .width = w,
            .height = h,
            .tiles = tiles,
            .flags = flags,
            .tag = tag,
            .chunk_dirty = chunk_dirty,
            .chunks_w = cd.cw,
            .chunks_h = cd.ch,
            .defs = defs,
        };
    }

    pub fn deinit(self: *TileMap) void {
        self.allocator.free(self.tiles);
        self.allocator.free(self.flags);
        self.allocator.free(self.tag);
        self.allocator.free(self.chunk_dirty);
        self.defs.deinit(self.allocator);
        self.tiles = &.{};
        self.flags = &.{};
        self.tag = &.{};
        self.chunk_dirty = &.{};
    }

    pub fn resize(self: *TileMap, w: u32, h: u32) !void {
        try checkDims(w, h);
        const n = @as(usize, w) * h;
        const tiles = try self.allocator.alloc(Tile, n);
        errdefer self.allocator.free(tiles);
        @memset(tiles, Tile{});
        const flags = try self.allocator.alloc(u8, n);
        errdefer self.allocator.free(flags);
        @memset(flags, 0);
        const tag = try self.allocator.alloc(u8, n);
        errdefer self.allocator.free(tag);
        @memset(tag, 0);
        const cd = chunkDims(w, h);
        const chunk_dirty = try self.allocator.alloc(bool, @as(usize, cd.cw) * cd.ch);
        @memset(chunk_dirty, true);

        self.allocator.free(self.tiles);
        self.allocator.free(self.flags);
        self.allocator.free(self.tag);
        self.allocator.free(self.chunk_dirty);
        self.tiles = tiles;
        self.flags = flags;
        self.tag = tag;
        self.chunk_dirty = chunk_dirty;
        self.chunks_w = cd.cw;
        self.chunks_h = cd.ch;
        self.width = w;
        self.height = h;
        self.opacity_version +%= 1;
        self.dirty = true;
    }

    pub fn defineTile(self: *TileMap, def: TileDef) !u16 {
        const idx = self.defs.items.len;
        if (idx > std.math.maxInt(u16)) return error.TooManyTileDefs;
        try self.defs.append(self.allocator, def);
        return std.math.cast(u16, idx) orelse error.TooManyTileDefs;
    }

    pub fn getDef(self: *const TileMap, kind: u16) ?TileDef {
        if (kind == 0 or kind >= self.defs.items.len) return null;
        return self.defs.items[kind];
    }

    pub fn inBounds(self: *const TileMap, x: i32, y: i32) bool {
        // width/height <= maxInt(i32)（checkDims 保证），转换不会溢出
        return x >= 0 and y >= 0 and x < @as(i32, @intCast(self.width)) and y < @as(i32, @intCast(self.height));
    }

    fn index(self: *const TileMap, x: i32, y: i32) usize {
        return @as(usize, @intCast(y)) * self.width + @as(usize, @intCast(x));
    }

    pub fn get(self: *const TileMap, x: i32, y: i32) ?Tile {
        if (!self.inBounds(x, y)) return null;
        return self.tiles[self.index(x, y)];
    }

    pub fn set(self: *TileMap, x: i32, y: i32, kind: u16, height: u8) void {
        if (!self.inBounds(x, y)) return;
        const old_op = self.isOpaque(x, y);
        self.tiles[self.index(x, y)] = .{ .kind = kind, .height = height };
        if (old_op != self.isOpaque(x, y)) self.opacity_version +%= 1;
        self.markDirtyAround(x, y);
    }

    pub fn fill(self: *TileMap, kind: u16, height: u8) void {
        @memset(self.tiles, Tile{ .kind = kind, .height = height });
        self.opacity_version +%= 1;
        self.markAllDirty();
    }

    pub fn getFlags(self: *const TileMap, x: i32, y: i32) u8 {
        if (!self.inBounds(x, y)) return Flag.blocked | Flag.@"opaque";
        return self.flags[self.index(x, y)];
    }

    pub fn setFlag(self: *TileMap, x: i32, y: i32, mask: u8, on: bool) void {
        if (!self.inBounds(x, y)) return;
        const idx = self.index(x, y);
        const old = self.flags[idx];
        const next = if (on) old | mask else old & ~mask;
        self.flags[idx] = next;
        if (((old ^ next) & Flag.@"opaque") != 0) self.opacity_version +%= 1;
    }

    pub fn getTag(self: *const TileMap, x: i32, y: i32) u8 {
        if (!self.inBounds(x, y)) return 0;
        return self.tag[self.index(x, y)];
    }

    pub fn setTag(self: *TileMap, x: i32, y: i32, v: u8) void {
        if (!self.inBounds(x, y)) return;
        self.tag[self.index(x, y)] = v;
    }

    pub fn isOpaque(self: *const TileMap, x: i32, y: i32) bool {
        if (!self.inBounds(x, y)) return true;
        const idx = self.index(x, y);
        if ((self.flags[idx] & Flag.@"opaque") != 0) return true;
        const t = self.tiles[idx];
        if (t.kind == 0) return false;
        const def = self.getDef(t.kind) orelse return false;
        return def.@"opaque";
    }

    pub fn markDirtyAround(self: *TileMap, x: i32, y: i32) void {
        if (self.chunks_w == 0 or self.chunks_h == 0) return;
        const x0 = @max(0, x - 1);
        const y0 = @max(0, y - 1);
        const x1 = @min(@as(i32, @intCast(self.width)) - 1, x + 1);
        const y1 = @min(@as(i32, @intCast(self.height)) - 1, y + 1);
        if (x0 > x1 or y0 > y1) return;
        const cx0: u32 = @intCast(@divTrunc(x0, @as(i32, @intCast(chunk_size))));
        const cy0: u32 = @intCast(@divTrunc(y0, @as(i32, @intCast(chunk_size))));
        const cx1: u32 = @intCast(@divTrunc(x1, @as(i32, @intCast(chunk_size))));
        const cy1: u32 = @intCast(@divTrunc(y1, @as(i32, @intCast(chunk_size))));
        var cy = cy0;
        while (cy <= cy1) : (cy += 1) {
            var cx = cx0;
            while (cx <= cx1) : (cx += 1) {
                self.chunk_dirty[@as(usize, cy) * self.chunks_w + cx] = true;
            }
        }
        self.dirty = true;
    }

    pub fn markAllDirty(self: *TileMap) void {
        @memset(self.chunk_dirty, true);
        self.dirty = true;
    }

    pub fn topY(self: *const TileMap, x: i32, y: i32) f32 {
        const t = self.get(x, y) orelse return 0;
        if (t.kind == 0) return 0;
        return @as(f32, @floatFromInt(t.height)) * self.height_unit;
    }

    pub fn isWalkable(self: *const TileMap, x: i32, y: i32) bool {
        const t = self.get(x, y) orelse return false;
        if (t.kind == 0) return false;
        if ((self.flags[self.index(x, y)] & Flag.blocked) != 0) return false;
        const def = self.getDef(t.kind) orelse return false;
        return !def.solid and !def.liquid;
    }

    pub fn canStep(self: *const TileMap, fx: i32, fy: i32, tx: i32, ty: i32) bool {
        if (!self.isWalkable(fx, fy) or !self.isWalkable(tx, ty)) return false;
        const a: i32 = self.get(fx, fy).?.height;
        const b: i32 = self.get(tx, ty).?.height;
        return @abs(a - b) <= self.max_step;
    }

    pub fn worldToTile(self: *const TileMap, p: Vec3) ?GridPos {
        const gx = cellOf(p.x) orelse return null;
        const gy = cellOf(p.z) orelse return null;
        if (!self.inBounds(gx, gy)) return null;
        return .{ .x = gx, .y = gy };
    }

    pub fn tileCenter(self: *const TileMap, x: i32, y: i32) Vec3 {
        return Vec3.new(@as(f32, @floatFromInt(x)) + 0.5, self.topY(x, y), @as(f32, @floatFromInt(y)) + 0.5);
    }

    pub fn raycastPick(self: *const TileMap, ray: Ray, max_dist: f32) ?TileHit {
        const step: f32 = 0.02;
        // 非有限 / 负的 max_dist：无结果
        if (!std.math.isFinite(max_dist) or max_dist < 0) return null;
        const o = ray.origin;
        const d = ray.dir;
        if (!std.math.isFinite(o.x) or !std.math.isFinite(o.y) or !std.math.isFinite(o.z)) return null;
        if (!std.math.isFinite(d.x) or !std.math.isFinite(d.y) or !std.math.isFinite(d.z)) return null;
        const len2 = d.x * d.x + d.y * d.y + d.z * d.z;
        if (!std.math.isFinite(len2) or len2 <= 0) return null;
        const dir = d.norm();
        // 整数步数计数器，上限与输入无关；t = i*step 不会因 f32 累加停滞。
        const max_steps: u32 = 200_000;
        const steps_f = @min(@ceil(max_dist / step), @as(f32, @floatFromInt(max_steps)));
        const n_steps: u32 = @intFromFloat(steps_f); // 有限且在 [0, max_steps]
        var i: u32 = 0;
        while (i <= n_steps) : (i += 1) {
            const t = @as(f32, @floatFromInt(i)) * step;
            const p = o.add(dir.scale(t));
            const gx = cellOf(p.x) orelse continue;
            const gy = cellOf(p.z) orelse continue;
            if (!self.inBounds(gx, gy)) continue;
            const tile = self.tiles[self.index(gx, gy)];
            if (tile.kind != 0 and p.y <= self.topY(gx, gy)) {
                return .{ .x = gx, .y = gy, .point = p };
            }
        }
        return null;
    }

    const Node = struct { g: u32, parent: i32, closed: bool, open: bool };

    /// 4 邻接 A*，曼哈顿启发；out 被清空后写入从起点(不含)到终点(含)的格子序列
    pub fn findPath(self: *const TileMap, allocator: Allocator, from: GridPos, to: GridPos, out: *std.ArrayList(GridPos)) !bool {
        out.clearRetainingCapacity();
        if (!self.inBounds(from.x, from.y) or !self.inBounds(to.x, to.y)) return false;
        if (from.x == to.x and from.y == to.y) return true;
        if (!self.isWalkable(to.x, to.y)) return false;

        const n = @as(usize, self.width) * self.height;
        const nodes = try allocator.alloc(Node, n);
        defer allocator.free(nodes);
        @memset(nodes, Node{ .g = 0, .parent = -1, .closed = false, .open = false });
        var open: std.ArrayList(u32) = .empty;
        defer open.deinit(allocator);

        // checkDims 保证 n <= maxInt(i32)，下方 u32/i32 下标转换安全
        const w: i32 = @intCast(self.width);
        const start_i = self.index(from.x, from.y);
        const goal_i = self.index(to.x, to.y);
        nodes[start_i].open = true;
        try open.append(allocator, @intCast(start_i));

        var expanded: usize = 0;
        var found = false;
        while (open.items.len > 0 and expanded < n) {
            // 取 f 最小
            var best: usize = 0;
            var best_f: u32 = std.math.maxInt(u32);
            for (open.items, 0..) |oi, k| {
                const ox: i32 = @intCast(oi % self.width);
                const oy: i32 = @intCast(oi / self.width);
                const hh: u32 = @abs(ox - to.x) + @abs(oy - to.y);
                const f = nodes[oi].g + hh;
                if (f < best_f) {
                    best_f = f;
                    best = k;
                }
            }
            const cur = open.swapRemove(best);
            nodes[cur].open = false;
            nodes[cur].closed = true;
            expanded += 1;
            if (cur == goal_i) {
                found = true;
                break;
            }
            const cx: i32 = @intCast(cur % self.width);
            const cy: i32 = @intCast(cur / self.width);
            const dirs = [4][2]i32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } };
            for (dirs) |d| {
                const nx = cx + d[0];
                const ny = cy + d[1];
                if (!self.inBounds(nx, ny)) continue;
                if (!self.canStep(cx, cy, nx, ny)) continue;
                const ni: usize = @intCast(ny * w + nx);
                if (nodes[ni].closed) continue;
                const ng = nodes[cur].g + 1;
                if (!nodes[ni].open) {
                    nodes[ni].open = true;
                    nodes[ni].g = ng;
                    nodes[ni].parent = @intCast(cur);
                    try open.append(allocator, @intCast(ni));
                } else if (ng < nodes[ni].g) {
                    nodes[ni].g = ng;
                    nodes[ni].parent = @intCast(cur);
                }
            }
        }
        if (!found) return false;

        var idx: i32 = @intCast(goal_i);
        var guard: usize = 0; // 父链理论上无环；仍以 n 为上限
        while (idx >= 0 and idx != @as(i32, @intCast(start_i)) and guard <= n) : (guard += 1) {
            const u: usize = @intCast(idx);
            try out.append(allocator, .{ .x = @intCast(u % self.width), .y = @intCast(u / self.width) });
            idx = nodes[u].parent;
        }
        std.mem.reverse(GridPos, out.items);
        return true;
    }
};

// ---------------------------------------------------------------- tests

const testing = std.testing;

fn makeMap(w: u32, h: u32) !TileMap {
    var m = try TileMap.init(testing.allocator, w, h);
    errdefer m.deinit();
    _ = try m.defineTile(.{ .top = 1, .side = 1 }); // 1 grass
    _ = try m.defineTile(.{ .top = 2, .side = 2, .solid = true }); // 2 wall
    _ = try m.defineTile(.{ .top = 3, .side = 3, .liquid = true }); // 3 water
    return m;
}

test "set/get/bounds" {
    var m = try makeMap(4, 3);
    defer m.deinit();
    try testing.expectEqual(@as(usize, 4), m.defs.items.len);
    try testing.expect(m.get(0, 0).?.kind == 0);
    m.dirty = false;
    m.set(2, 1, 1, 3);
    try testing.expect(m.dirty);
    try testing.expectEqual(@as(u8, 3), m.get(2, 1).?.height);
    try testing.expect(m.get(4, 0) == null);
    try testing.expect(m.get(-1, 0) == null);
    m.set(10, 10, 1, 1); // 忽略
    m.fill(1, 2);
    try testing.expectEqual(@as(u8, 2), m.get(3, 2).?.height);
    try m.resize(2, 2);
    try testing.expectEqual(@as(u16, 0), m.get(1, 1).?.kind);
    try testing.expect(m.getDef(0) == null);
    try testing.expect(m.getDef(1) != null);
    try testing.expect(m.getDef(99) == null);
}

test "topY" {
    var m = try makeMap(4, 4);
    defer m.deinit();
    m.set(1, 1, 1, 4);
    try testing.expectEqual(@as(f32, 2.0), m.topY(1, 1));
    try testing.expectEqual(@as(f32, 0), m.topY(0, 0)); // 空
    try testing.expectEqual(@as(f32, 0), m.topY(-1, 0)); // 越界
}

test "isWalkable and canStep" {
    var m = try makeMap(4, 4);
    defer m.deinit();
    m.set(0, 0, 1, 0);
    m.set(1, 0, 1, 1);
    m.set(2, 0, 1, 3);
    m.set(0, 1, 2, 0); // solid
    m.set(1, 1, 3, 0); // liquid
    try testing.expect(m.isWalkable(0, 0));
    try testing.expect(!m.isWalkable(0, 1));
    try testing.expect(!m.isWalkable(1, 1));
    try testing.expect(!m.isWalkable(3, 3)); // 空
    try testing.expect(!m.isWalkable(-1, 0));
    try testing.expect(m.canStep(0, 0, 1, 0));
    try testing.expect(!m.canStep(1, 0, 2, 0)); // 高差 2
    try testing.expect(!m.canStep(0, 0, 0, 1)); // solid
    m.max_step = 2;
    try testing.expect(m.canStep(1, 0, 2, 0));
}

test "worldToTile and tileCenter" {
    var m = try makeMap(4, 4);
    defer m.deinit();
    m.set(2, 3, 1, 2);
    const g = m.worldToTile(Vec3.new(2.7, 5, 3.1)).?;
    try testing.expectEqual(@as(i32, 2), g.x);
    try testing.expectEqual(@as(i32, 3), g.y);
    try testing.expect(m.worldToTile(Vec3.new(-0.1, 0, 0)) == null);
    try testing.expect(m.worldToTile(Vec3.new(4.0, 0, 0)) == null);
    const c = m.tileCenter(2, 3);
    try testing.expectEqual(@as(f32, 2.5), c.x);
    try testing.expectEqual(@as(f32, 1.0), c.y);
    try testing.expectEqual(@as(f32, 3.5), c.z);
}

test "raycastPick prefers raised tile over lower ground behind" {
    var m = try makeMap(10, 10);
    defer m.deinit();
    m.fill(1, 0);
    m.set(5, 5, 1, 6); // top y = 3
    var cam = camera.IsoCamera{};
    cam.target = Vec3.new(5.5, 3, 5.5);
    cam.update(1280, 720);
    // 看向高台顶面中心附近
    const s = cam.worldToScreen(Vec3.new(5.5, 3.0, 5.5));
    const ray = cam.screenToRay(s.x, s.y);
    const hit = m.raycastPick(ray, 200).?;
    try testing.expectEqual(@as(i32, 5), hit.x);
    try testing.expectEqual(@as(i32, 5), hit.y);
    // 瞄准高台后方（沿视线方向延伸）的地面点：地面点被高台遮挡则应命中高台
    const behind = Vec3.new(5.5, 0, 5.5); // 高台正下方地面
    const s2 = cam.worldToScreen(behind);
    const hit2 = m.raycastPick(cam.screenToRay(s2.x, s2.y), 200).?;
    try testing.expect(hit2.x == 5 and hit2.y == 5);
    try testing.expect(hit2.point.y <= 3.0);
    // 无命中
    const miss = m.raycastPick(.{ .origin = Vec3.new(50, 10, 50), .dir = Vec3.new(0, 1, 0) }, 100);
    try testing.expect(miss == null);
}

test "worldToTile and raycastPick reject non-finite / huge" {
    var m = try makeMap(4, 4);
    defer m.deinit();
    m.fill(1, 0);
    const nan = std.math.nan(f32);
    const inf = std.math.inf(f32);
    try testing.expect(m.worldToTile(Vec3.new(nan, 0, 0)) == null);
    try testing.expect(m.worldToTile(Vec3.new(0, 0, nan)) == null);
    try testing.expect(m.worldToTile(Vec3.new(1e10, 0, 0)) == null);
    try testing.expect(m.worldToTile(Vec3.new(0, 0, -inf)) == null);
    try testing.expect(m.raycastPick(.{ .origin = Vec3.new(1, 5, 1), .dir = Vec3.new(nan, -1, 0) }, 100) == null);
    try testing.expect(m.raycastPick(.{ .origin = Vec3.new(1, 5, 1), .dir = Vec3.new(inf, -1, 0) }, 100) == null);
    try testing.expect(m.raycastPick(.{ .origin = Vec3.new(1, 5, 1), .dir = Vec3.zero }, 100) == null);
    try testing.expect(m.raycastPick(.{ .origin = Vec3.new(nan, 5, 1), .dir = Vec3.new(0, -1, 0) }, 100) == null);
    try testing.expect(m.raycastPick(.{ .origin = Vec3.new(1, 5, 1), .dir = Vec3.new(0, -1, 0) }, 100) != null);
}

test "findPath around wall" {
    var m = try makeMap(5, 5);
    defer m.deinit();
    m.fill(1, 0);
    // 竖墙 x=2，y=0..3，留 y=4 通路
    var y: i32 = 0;
    while (y < 4) : (y += 1) m.set(2, y, 2, 0);
    var out: std.ArrayList(GridPos) = .empty;
    defer out.deinit(testing.allocator);
    try testing.expect(try m.findPath(testing.allocator, .{ .x = 0, .y = 0 }, .{ .x = 4, .y = 0 }, &out));
    // 最短：下 4，右 4，上 4 = 12 步
    try testing.expectEqual(@as(usize, 12), out.items.len);
    const last = out.items[out.items.len - 1];
    try testing.expectEqual(@as(i32, 4), last.x);
    try testing.expectEqual(@as(i32, 0), last.y);
    for (out.items) |p| try testing.expect(m.isWalkable(p.x, p.y));
}

test "findPath same, unreachable, height block" {
    var m = try makeMap(5, 5);
    defer m.deinit();
    m.fill(1, 0);
    var out: std.ArrayList(GridPos) = .empty;
    defer out.deinit(testing.allocator);
    try out.append(testing.allocator, .{ .x = 9, .y = 9 });
    try testing.expect(try m.findPath(testing.allocator, .{ .x = 1, .y = 1 }, .{ .x = 1, .y = 1 }, &out));
    try testing.expectEqual(@as(usize, 0), out.items.len);
    // 目标不可走
    m.set(4, 4, 2, 0);
    try testing.expect(!try m.findPath(testing.allocator, .{ .x = 0, .y = 0 }, .{ .x = 4, .y = 4 }, &out));
    // 越界
    try testing.expect(!try m.findPath(testing.allocator, .{ .x = 0, .y = 0 }, .{ .x = 9, .y = 9 }, &out));
    // 墙隔断
    var i: i32 = 0;
    while (i < 5) : (i += 1) m.set(2, i, 2, 0);
    try testing.expect(!try m.findPath(testing.allocator, .{ .x = 0, .y = 0 }, .{ .x = 4, .y = 0 }, &out));
    // 高差阻断
    m.fill(1, 0);
    i = 0;
    while (i < 5) : (i += 1) m.set(2, i, 1, 3);
    try testing.expect(!try m.findPath(testing.allocator, .{ .x = 0, .y = 0 }, .{ .x = 4, .y = 0 }, &out));
    m.max_step = 3;
    try testing.expect(try m.findPath(testing.allocator, .{ .x = 0, .y = 0 }, .{ .x = 4, .y = 0 }, &out));
}

test "cellOf boundary: -0.5 is cell -1" {
    var m = try makeMap(4, 4);
    defer m.deinit();
    try testing.expect(m.worldToTile(Vec3.new(-0.5, 0, 0.5)) == null);
    const g = m.worldToTile(Vec3.new(0.5, 0, 0.5)).?;
    try testing.expectEqual(@as(i32, 0), g.x);
    try testing.expectEqual(@as(i32, 0), g.y);
}

test "raycastPick terminates for huge / inf / negative max_dist" {
    var m = try makeMap(4, 4);
    defer m.deinit();
    m.fill(1, 0);
    const inf = std.math.inf(f32);
    const nan = std.math.nan(f32);
    const miss = Ray{ .origin = Vec3.new(50, 10, 50), .dir = Vec3.new(0, 1, 0) };
    try testing.expect(m.raycastPick(miss, 1e7) == null);
    try testing.expect(m.raycastPick(miss, 524288) == null);
    try testing.expect(m.raycastPick(miss, 3.0e38) == null);
    try testing.expect(m.raycastPick(miss, inf) == null);
    try testing.expect(m.raycastPick(miss, -inf) == null);
    try testing.expect(m.raycastPick(miss, nan) == null);
    try testing.expect(m.raycastPick(miss, -1) == null);
    // max_dist = 0 仍检查起点
    try testing.expect(m.raycastPick(.{ .origin = Vec3.new(1, 0, 1), .dir = Vec3.new(0, -1, 0) }, 0) != null);
    // 极端射线数值
    try testing.expect(m.raycastPick(.{ .origin = Vec3.new(1e30, 1e30, 1e30), .dir = Vec3.new(1, 1, 1) }, 1e7) == null);
    try testing.expect(m.raycastPick(.{ .origin = Vec3.new(1, 5, 1), .dir = Vec3.new(3e38, 3e38, 3e38) }, 100) == null);
}

test "tileCenter / worldToTile / map dims garbage" {
    var m = try makeMap(4, 4);
    defer m.deinit();
    const c = m.tileCenter(std.math.minInt(i32), std.math.maxInt(i32));
    try testing.expect(std.math.isFinite(c.x) and std.math.isFinite(c.y) and std.math.isFinite(c.z));
    try testing.expect(m.worldToTile(Vec3.new(std.math.inf(f32), 0, 0)) == null);
    try testing.expect(m.worldToTile(Vec3.new(0, 0, 3.0e38)) == null);
    try testing.expectError(error.MapTooLarge, TileMap.init(testing.allocator, 100_000, 100_000));
    try testing.expectError(error.MapTooLarge, m.resize(std.math.maxInt(u32), 1));
    try testing.expectEqual(@as(u32, 4), m.width); // resize 失败不改变状态
}

test "flags, tags, opacity_version, and chunk_dirty" {
    var m = try TileMap.init(testing.allocator, 32, 32);
    defer m.deinit();
    const floor = try m.defineTile(.{ .top = 1, .side = 1 });
    m.fill(floor, 0);
    @memset(m.chunk_dirty, false);
    m.dirty = false;

    const v0 = m.opacity_version;
    m.setFlag(15, 15, Flag.blocked | Flag.@"opaque", true);
    try testing.expect(!m.dirty);
    for (m.chunk_dirty) |d| try testing.expect(!d);
    try testing.expect(!m.isWalkable(15, 15));
    try testing.expect(m.isOpaque(15, 15));
    try testing.expect(m.opacity_version != v0);
    try testing.expectEqual(Flag.blocked | Flag.@"opaque", m.getFlags(-1, 0));

    m.setTag(3, 4, 7);
    try testing.expectEqual(@as(u8, 7), m.getTag(3, 4));
    try testing.expectEqual(@as(u8, 0), m.getTag(99, 99));

    m.set(16, 16, floor, 1);
    var dirty_n: usize = 0;
    for (m.chunk_dirty) |d| if (d) {
        dirty_n += 1;
    };
    try testing.expectEqual(@as(usize, 4), dirty_n);
}
