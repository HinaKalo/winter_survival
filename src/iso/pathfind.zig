//! 纯逻辑：A* 寻路（支持终点相邻）与 BFS 可达范围。
const std = @import("std");
const Allocator = std.mem.Allocator;
const coords = @import("coords.zig");
const tilemap = @import("tilemap.zig");
const vision = @import("vision.zig");
const GridPos = coords.GridPos;
const TileMap = tilemap.TileMap;

/// 节点 scratch：gen != 当前代数 视为未访问（无需逐次清零）。
const Node = struct { g: u32 = 0, parent: i32 = -1, gen: u32 = 0, closed: bool = false };

/// 开集堆条目：按 (f, h, idx) 字典序，保证确定性。
const Entry = struct {
    f: u32,
    h: u32,
    idx: u32,

    fn less(a: Entry, b: Entry) bool {
        if (a.f != b.f) return a.f < b.f;
        if (a.h != b.h) return a.h < b.h;
        return a.idx < b.idx;
    }
};

pub const PathFinder = struct {
    allocator: Allocator,
    nodes: std.ArrayList(Node) = .empty,
    heap: std.ArrayList(Entry) = .empty,
    queue: std.ArrayList(u32) = .empty,
    visited: std.ArrayList(u32) = .empty,
    /// find 的当前代数（从 1 开始；0 保留为“从未使用”）。
    gen: u32 = 0,
    /// reach 的当前代数。
    visit_gen: u32 = 0,

    pub fn init(allocator: Allocator) PathFinder {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *PathFinder) void {
        self.nodes.deinit(self.allocator);
        self.heap.deinit(self.allocator);
        self.queue.deinit(self.allocator);
        self.visited.deinit(self.allocator);
    }

    fn isGoal(map: *const TileMap, cx: i32, cy: i32, to: GridPos, goal_adjacent: bool) bool {
        if (cx == to.x and cy == to.y) return true;
        if (!goal_adjacent) return false;
        const manhattan = @abs(cx - to.x) + @abs(cy - to.y);
        return manhattan == 1 and map.isWalkable(cx, cy);
    }

    fn heapPush(self: *PathFinder, e: Entry) !void {
        try self.heap.append(self.allocator, e);
        const items = self.heap.items;
        var i = items.len - 1;
        while (i > 0) {
            const p = (i - 1) / 2;
            if (!Entry.less(items[i], items[p])) break;
            std.mem.swap(Entry, &items[i], &items[p]);
            i = p;
        }
    }

    fn heapPop(self: *PathFinder) Entry {
        const items = self.heap.items;
        const top = items[0];
        const last = self.heap.pop().?;
        const len = self.heap.items.len;
        if (len > 0) {
            items[0] = last;
            var i: usize = 0;
            while (true) {
                const l = 2 * i + 1;
                const r = l + 1;
                var m = i;
                if (l < len and Entry.less(items[l], items[m])) m = l;
                if (r < len and Entry.less(items[r], items[m])) m = r;
                if (m == i) break;
                std.mem.swap(Entry, &items[i], &items[m]);
                i = m;
            }
        }
        return top;
    }

    /// 4 邻接 A*（二叉堆开集、代数戳 scratch），曼哈顿启发；out 被清空后写入从起点(不含)到终点(含)的格子序列。
    /// goal_adjacent = true 时终点可以不可走，路径止于其相邻可走格。
    pub fn find(
        self: *PathFinder,
        map: *const TileMap,
        from: GridPos,
        to: GridPos,
        goal_adjacent: bool,
        out: *std.ArrayList(GridPos),
    ) !bool {
        out.clearRetainingCapacity();
        if (!map.inBounds(from.x, from.y) or !map.inBounds(to.x, to.y)) return false;
        if (from.x == to.x and from.y == to.y) return true;
        if (goal_adjacent and !map.isWalkable(to.x, to.y) and isGoal(map, from.x, from.y, to, true)) {
            return true;
        }
        if (!goal_adjacent and !map.isWalkable(to.x, to.y)) return false;

        const n = @as(usize, map.width) * map.height;
        if (self.nodes.items.len < n) {
            const old = self.nodes.items.len;
            try self.nodes.resize(self.allocator, n);
            @memset(self.nodes.items[old..], Node{});
        }
        // 代数 +1；溢出回绕时整体清零一次。
        self.gen +%= 1;
        if (self.gen == 0) {
            @memset(self.nodes.items, Node{});
            self.gen = 1;
        }
        const gen = self.gen;
        const nodes = self.nodes.items;
        self.heap.clearRetainingCapacity();

        // 终点不可走（相邻即达）时真实剩余代价 >= 曼哈顿 - 1。
        const h_off: u32 = if (goal_adjacent and !map.isWalkable(to.x, to.y)) 1 else 0;

        const w: i32 = @intCast(map.width);
        const start_i: usize = @as(usize, @intCast(from.y)) * map.width + @as(usize, @intCast(from.x));
        nodes[start_i] = .{ .g = 0, .parent = -1, .gen = gen, .closed = false };
        {
            const h: u32 = @abs(from.x - to.x) + @abs(from.y - to.y);
            const hh = h -| h_off;
            try self.heapPush(.{ .f = hh, .h = hh, .idx = @intCast(start_i) });
        }

        var found_i: ?usize = null;
        while (self.heap.items.len > 0) {
            const e = self.heapPop();
            const cur: usize = e.idx;
            if (nodes[cur].closed) continue; // 过期的重复条目
            nodes[cur].closed = true;

            const cx: i32 = @intCast(cur % map.width);
            const cy: i32 = @intCast(cur / map.width);
            if ((!goal_adjacent and cx == to.x and cy == to.y) or
                (goal_adjacent and (if (map.isWalkable(to.x, to.y)) cx == to.x and cy == to.y else isGoal(map, cx, cy, to, true))))
            {
                found_i = cur;
                break;
            }

            const dirs = [4][2]i32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } };
            for (dirs) |d| {
                const nx = cx + d[0];
                const ny = cy + d[1];
                if (!map.inBounds(nx, ny)) continue;
                if (!map.canStep(cx, cy, nx, ny)) continue;
                const ni: usize = @intCast(ny * w + nx);
                const ng = nodes[cur].g + 1;
                if (nodes[ni].gen == gen) {
                    if (nodes[ni].closed or ng >= nodes[ni].g) continue;
                } else {
                    nodes[ni].gen = gen;
                    nodes[ni].closed = false;
                }
                nodes[ni].g = ng;
                nodes[ni].parent = @intCast(cur);
                const h: u32 = (@abs(nx - to.x) + @abs(ny - to.y)) -| h_off;
                try self.heapPush(.{ .f = ng + h, .h = h, .idx = @intCast(ni) });
            }
        }
        const goal_i = found_i orelse return false;

        var idx: i32 = @intCast(goal_i);
        var guard: usize = 0;
        while (idx >= 0 and idx != @as(i32, @intCast(start_i)) and guard <= n) : (guard += 1) {
            const u: usize = @intCast(idx);
            try out.append(self.allocator, .{ .x = @intCast(u % map.width), .y = @intCast(u / map.width) });
            idx = nodes[u].parent;
        }
        std.mem.reverse(GridPos, out.items);
        return true;
    }

    /// BFS：把 max_steps 步内可达格并入 mask；返回新并入的格数。
    pub fn reach(self: *PathFinder, map: *const TileMap, from: GridPos, max_steps: u32, mask: *vision.Mask) !u32 {
        if (!map.inBounds(from.x, from.y) or !map.isWalkable(from.x, from.y)) return 0;
        const n = @as(usize, map.width) * map.height;
        if (self.visited.items.len < n) {
            const old = self.visited.items.len;
            try self.visited.resize(self.allocator, n);
            @memset(self.visited.items[old..], 0);
        }
        self.visit_gen +%= 1;
        if (self.visit_gen == 0) {
            @memset(self.visited.items, 0);
            self.visit_gen = 1;
        }
        const vgen = self.visit_gen;
        self.queue.clearRetainingCapacity();

        const start_i: usize = @as(usize, @intCast(from.y)) * map.width + @as(usize, @intCast(from.x));
        self.visited.items[start_i] = vgen;
        try self.queue.append(self.allocator, @intCast(start_i));
        try self.queue.append(self.allocator, 0);

        var added: u32 = 0;
        var head: usize = 0;
        while (head + 1 < self.queue.items.len) : (head += 2) {
            const cur: usize = self.queue.items[head];
            const dist: u32 = self.queue.items[head + 1];
            const cx: i32 = @intCast(cur % map.width);
            const cy: i32 = @intCast(cur / map.width);

            if (!mask.get(cx, cy)) {
                mask.set(cx, cy);
                added += 1;
            }
            if (dist >= max_steps) continue;

            const dirs = [4][2]i32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } };
            for (dirs) |d| {
                const nx = cx + d[0];
                const ny = cy + d[1];
                if (!map.inBounds(nx, ny)) continue;
                if (!map.canStep(cx, cy, nx, ny)) continue;
                const ni: usize = @as(usize, @intCast(ny)) * map.width + @as(usize, @intCast(nx));
                if (self.visited.items[ni] == vgen) continue;
                self.visited.items[ni] = vgen;
                try self.queue.append(self.allocator, @intCast(ni));
                try self.queue.append(self.allocator, dist + 1);
            }
        }
        return added;
    }
};

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "PathFinder goal_adjacent and reach" {
    var m = try TileMap.init(testing.allocator, 6, 6);
    defer m.deinit();
    const floor = try m.defineTile(.{ .top = 1, .side = 1 });
    const wall = try m.defineTile(.{ .top = 2, .side = 2, .solid = true });
    m.fill(floor, 0);
    m.set(3, 2, wall, 2);

    var pf = PathFinder.init(testing.allocator);
    defer pf.deinit();
    var out: std.ArrayList(GridPos) = .empty;
    defer out.deinit(testing.allocator);

    try testing.expect(!try pf.find(&m, .{ .x = 0, .y = 2 }, .{ .x = 3, .y = 2 }, false, &out));
    try testing.expect(try pf.find(&m, .{ .x = 0, .y = 2 }, .{ .x = 3, .y = 2 }, true, &out));
    try testing.expect(out.items.len > 0);
    const last = out.items[out.items.len - 1];
    try testing.expectEqual(@as(u32, 1), @abs(last.x - 3) + @abs(last.y - 2));

    var mask = try vision.Mask.init(testing.allocator, 6, 6);
    defer mask.deinit();
    const added = try pf.reach(&m, .{ .x = 0, .y = 0 }, 2, &mask);
    try testing.expectEqual(@as(u32, 6), added);
    try testing.expect(mask.get(2, 0));
    try testing.expect(!mask.get(3, 0));
}

// ---- R2 tests

const RefMap = struct {
    fn build(allocator: Allocator, seed: u64, w: u32, h: u32) !TileMap {
        var m = try TileMap.init(allocator, w, h);
        errdefer m.deinit();
        const floor = try m.defineTile(.{ .top = 1, .side = 1 });
        const wall = try m.defineTile(.{ .top = 2, .side = 2, .solid = true });
        m.fill(floor, 0);
        var prng = std.Random.DefaultPrng.init(seed);
        const r = prng.random();
        var y: i32 = 0;
        while (y < h) : (y += 1) {
            var x: i32 = 0;
            while (x < w) : (x += 1) {
                const roll = r.uintLessThan(u32, 100);
                if (roll < 25) {
                    m.set(x, y, wall, 0);
                } else {
                    m.set(x, y, floor, @intCast(r.uintLessThan(u32, 3)));
                }
            }
        }
        return m;
    }

    /// BFS 最短步数；不可达返回 null。goal_adjacent 且终点不可走时，到任意“相邻且可走”格即可。
    fn bfs(allocator: Allocator, m: *const TileMap, from: GridPos, to: GridPos, goal_adjacent: bool) !?u32 {
        const n = @as(usize, m.width) * m.height;
        const dist = try allocator.alloc(i32, n);
        defer allocator.free(dist);
        @memset(dist, -1);
        var q: std.ArrayList(GridPos) = .empty;
        defer q.deinit(allocator);
        dist[@intCast(from.y * @as(i32, @intCast(m.width)) + from.x)] = 0;
        try q.append(allocator, from);
        var head: usize = 0;
        while (head < q.items.len) : (head += 1) {
            const c = q.items[head];
            const cd = dist[@intCast(c.y * @as(i32, @intCast(m.width)) + c.x)];
            if (PathFinder.isGoal(m, c.x, c.y, to, goal_adjacent and !m.isWalkable(to.x, to.y))) return @intCast(cd);
            const dirs = [4][2]i32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } };
            for (dirs) |d| {
                const nx = c.x + d[0];
                const ny = c.y + d[1];
                if (!m.inBounds(nx, ny) or !m.canStep(c.x, c.y, nx, ny)) continue;
                const ni: usize = @intCast(ny * @as(i32, @intCast(m.width)) + nx);
                if (dist[ni] >= 0) continue;
                dist[ni] = cd + 1;
                try q.append(allocator, .{ .x = nx, .y = ny });
            }
        }
        return null;
    }
};

fn checkPath(m: *const TileMap, from: GridPos, path: []const GridPos) !void {
    var cur = from;
    for (path) |p| {
        try testing.expect(m.canStep(cur.x, cur.y, p.x, p.y));
        try testing.expectEqual(@as(u32, 1), @abs(cur.x - p.x) + @abs(cur.y - p.y));
        cur = p;
    }
}

test "A* length equals BFS on 200 seeded random maps" {
    var pf = PathFinder.init(testing.allocator);
    defer pf.deinit();
    var out: std.ArrayList(GridPos) = .empty;
    defer out.deinit(testing.allocator);
    var seed: u64 = 0;
    while (seed < 200) : (seed += 1) {
        var m = try RefMap.build(testing.allocator, seed, 14 + @as(u32, @intCast(seed % 7)), 12 + @as(u32, @intCast(seed % 5)));
        defer m.deinit();
        var prng = std.Random.DefaultPrng.init(seed *% 7919 +% 1);
        const r = prng.random();
        var k: usize = 0;
        while (k < 6) : (k += 1) {
            const from = GridPos{ .x = r.intRangeLessThan(i32, 0, @intCast(m.width)), .y = r.intRangeLessThan(i32, 0, @intCast(m.height)) };
            const to = GridPos{ .x = r.intRangeLessThan(i32, 0, @intCast(m.width)), .y = r.intRangeLessThan(i32, 0, @intCast(m.height)) };
            const adj = k % 2 == 1;
            const found = try pf.find(&m, from, to, adj, &out);
            const ref: ?u32 = if (!adj and !m.isWalkable(to.x, to.y) and !(from.x == to.x and from.y == to.y))
                null
            else
                try RefMap.bfs(testing.allocator, &m, from, to, adj);
            if (ref) |len| {
                try testing.expect(found);
                try testing.expectEqual(len, @as(u32, @intCast(out.items.len)));
                try checkPath(&m, from, out.items);
            } else {
                try testing.expect(!found);
            }
        }
    }
}

test "serpentine maze returns full path" {
    var m = try TileMap.init(testing.allocator, 64, 64);
    defer m.deinit();
    const floor = try m.defineTile(.{ .top = 1, .side = 1 });
    const wall = try m.defineTile(.{ .top = 2, .side = 2, .solid = true });
    m.fill(floor, 0);
    // 奇数行（y<62）为墙，交替在两端留缺口 -> 64×64 蛇形
    var y: i32 = 1;
    while (y < 62) : (y += 2) {
        var x: i32 = 0;
        while (x < 64) : (x += 1) m.set(x, y, wall, 0);
        const gap: i32 = if (@mod(@divFloor(y, 2), 2) == 0) 0 else 63;
        m.set(gap, y, floor, 0);
    }
    var pf = PathFinder.init(testing.allocator);
    defer pf.deinit();
    var out: std.ArrayList(GridPos) = .empty;
    defer out.deinit(testing.allocator);
    const from = GridPos{ .x = 0, .y = 0 };
    const to = GridPos{ .x = 0, .y = 63 };
    try testing.expect(try pf.find(&m, from, to, false, &out));
    const ref = (try RefMap.bfs(testing.allocator, &m, from, to, false)).?;
    try testing.expectEqual(ref, @as(u32, @intCast(out.items.len)));
    try testing.expect(out.items.len > 64);
    try checkPath(&m, from, out.items);
    try testing.expectEqual(to, out.items[out.items.len - 1]);
}

test "scratch isolation across maps, targets and generation wraparound" {
    var pf = PathFinder.init(testing.allocator);
    defer pf.deinit();
    var a: std.ArrayList(GridPos) = .empty;
    defer a.deinit(testing.allocator);
    var b: std.ArrayList(GridPos) = .empty;
    defer b.deinit(testing.allocator);
    var fresh: PathFinder = PathFinder.init(testing.allocator);
    defer fresh.deinit();
    var c: std.ArrayList(GridPos) = .empty;
    defer c.deinit(testing.allocator);

    pf.gen = std.math.maxInt(u32) - 2;
    pf.visit_gen = std.math.maxInt(u32) - 2;
    var seed: u64 = 1000;
    while (seed < 1012) : (seed += 1) {
        var m1 = try RefMap.build(testing.allocator, seed, 16, 16);
        defer m1.deinit();
        var m2 = try RefMap.build(testing.allocator, seed + 500, 9, 21);
        defer m2.deinit();
        const f1 = GridPos{ .x = 0, .y = 0 };
        const t1 = GridPos{ .x = 15, .y = 15 };
        const f2 = GridPos{ .x = 8, .y = 0 };
        const t2 = GridPos{ .x = 1, .y = 20 };
        const ok1 = try pf.find(&m1, f1, t1, true, &a);
        const ok2 = try pf.find(&m2, f2, t2, true, &b);
        // 以全新 PathFinder 为基准
        var fresh2 = PathFinder.init(testing.allocator);
        defer fresh2.deinit();
        const r1 = try fresh2.find(&m1, f1, t1, true, &c);
        try testing.expectEqual(r1, ok1);
        try testing.expectEqualSlices(GridPos, c.items, a.items);
        const r2 = try fresh2.find(&m2, f2, t2, true, &c);
        try testing.expectEqual(r2, ok2);
        try testing.expectEqualSlices(GridPos, c.items, b.items);
        // 再查 m1，结果应与第一次相同
        const ok1b = try pf.find(&m1, f1, t1, true, &c);
        try testing.expectEqual(ok1, ok1b);
        try testing.expectEqualSlices(GridPos, a.items, c.items);
        var mask = try vision.Mask.init(testing.allocator, 16, 16);
        defer mask.deinit();
        const got = try pf.reach(&m1, f1, 5, &mask);
        var mask_ref = try vision.Mask.init(testing.allocator, 16, 16);
        defer mask_ref.deinit();
        const want = try fresh2.reach(&m1, f1, 5, &mask_ref);
        try testing.expectEqual(want, got);
    }
    // 回绕后 gen 必然已越过 0
    try testing.expect(pf.gen < 100);
    try testing.expect(pf.visit_gen < 100);
}

test "generation wraparound clears stale stamps (find and reach)" {
    var m1 = try TileMap.init(testing.allocator, 24, 24);
    defer m1.deinit();
    const floor = try m1.defineTile(.{ .top = 1, .side = 1 });
    const wall = try m1.defineTile(.{ .top = 2, .side = 2, .solid = true });
    m1.fill(floor, 0);
    // 两道带缺口的墙，保证存在较长的绕行路径。
    var wy: i32 = 0;
    while (wy < 20) : (wy += 1) m1.set(12, wy, wall, 0);
    wy = 4;
    while (wy < 24) : (wy += 1) m1.set(6, wy, wall, 0);
    // 起点取各行第一个可走格（reach 起点不可走会提前返回，不会盖戳）。
    var starts: [4]GridPos = undefined;
    for (&starts, 0..) |*st, row| {
        var x: i32 = 0;
        while (!m1.isWalkable(x, @intCast(row))) x += 1;
        st.* = .{ .x = x, .y = @intCast(row) };
    }
    var pf = PathFinder.init(testing.allocator);
    defer pf.deinit();
    var out: std.ArrayList(GridPos) = .empty;
    defer out.deinit(testing.allocator);
    var ref_out: std.ArrayList(GridPos) = .empty;
    defer ref_out.deinit(testing.allocator);

    // 先以全新 gen 跑一遍，让节点带上 gen=1 / visit_gen=1 的戳。
    var k: i32 = 0;
    while (k < 4) : (k += 1) {
        pf.gen = 0;
        pf.visit_gen = 0;
        // 在 (k,k) 附近若不可走则 goal_adjacent 兜底；起终点均取 goal_adjacent=true。
        _ = try pf.find(&m1, starts[@intCast(k)], .{ .x = 23, .y = 23 }, true, &out);
        var mk = try vision.Mask.init(testing.allocator, 24, 24);
        defer mk.deinit();
        _ = try pf.reach(&m1, starts[@intCast(k)], 60, &mk);
        try testing.expectEqual(@as(u32, 1), pf.gen);
        try testing.expectEqual(@as(u32, 1), pf.visit_gen);

        // 令下一次查询回绕到 1，与上面的戳碰撞。
        pf.gen = std.math.maxInt(u32);
        pf.visit_gen = std.math.maxInt(u32);
        var fresh = PathFinder.init(testing.allocator);
        defer fresh.deinit();
        // 与盖戳那次相同的起终点：被旧戳误判为“已关闭”的节点会直接堵死搜索。
        const from = starts[@intCast(k)];
        const to = GridPos{ .x = 23, .y = 23 };
        const got = try pf.find(&m1, from, to, true, &out);
        const want = try fresh.find(&m1, from, to, true, &ref_out);
        try testing.expect(want and ref_out.items.len > 8); // 基准必须真的找到长路径
        try testing.expectEqual(want, got);
        try testing.expectEqualSlices(GridPos, ref_out.items, out.items);
        try testing.expectEqual(@as(u32, 1), pf.gen);

        var mask_a = try vision.Mask.init(testing.allocator, 24, 24);
        defer mask_a.deinit();
        var mask_b = try vision.Mask.init(testing.allocator, 24, 24);
        defer mask_b.deinit();
        const ra = try pf.reach(&m1, from, 60, &mask_a);
        const rb = try fresh.reach(&m1, from, 60, &mask_b);
        try testing.expectEqual(rb, ra);
        try testing.expectEqual(@as(u32, 1), pf.visit_gen);
    }
}

test "A* is deterministic" {
    var m = try RefMap.build(testing.allocator, 4242, 20, 20);
    defer m.deinit();
    var pf = PathFinder.init(testing.allocator);
    defer pf.deinit();
    var a: std.ArrayList(GridPos) = .empty;
    defer a.deinit(testing.allocator);
    var b: std.ArrayList(GridPos) = .empty;
    defer b.deinit(testing.allocator);
    var open_map = try TileMap.init(testing.allocator, 20, 20);
    defer open_map.deinit();
    const fl = try open_map.defineTile(.{ .top = 1, .side = 1 });
    open_map.fill(fl, 0);
    const from = GridPos{ .x = 1, .y = 1 };
    const to = GridPos{ .x = 18, .y = 17 };
    // 小开阔图：(f, h, idx) 平局决定唯一路径。
    {
        var small = try TileMap.init(testing.allocator, 4, 3);
        defer small.deinit();
        const sf = try small.defineTile(.{ .top = 1, .side = 1 });
        small.fill(sf, 0);
        try testing.expect(try pf.find(&small, .{ .x = 0, .y = 0 }, .{ .x = 2, .y = 1 }, false, &a));
        const expected = [_]GridPos{ .{ .x = 1, .y = 0 }, .{ .x = 2, .y = 0 }, .{ .x = 2, .y = 1 } };
        try testing.expectEqualSlices(GridPos, &expected, a.items);
    }
    for ([_]*const TileMap{ &m, &open_map }) |mp| {
        const r1 = try pf.find(mp, from, to, true, &a);
        const r2 = try pf.find(mp, from, to, true, &b);
        try testing.expectEqual(r1, r2);
        try testing.expectEqualSlices(GridPos, a.items, b.items);
    }
}
