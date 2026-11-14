//! 纯逻辑：A* 寻路（支持终点相邻）与 BFS 可达范围。
const std = @import("std");
const Allocator = std.mem.Allocator;
const coords = @import("coords.zig");
const tilemap = @import("tilemap.zig");
const vision = @import("vision.zig");
const GridPos = coords.GridPos;
const TileMap = tilemap.TileMap;

const Node = struct { g: u32, parent: i32, closed: bool, open: bool };

pub const PathFinder = struct {
    allocator: Allocator,
    nodes: std.ArrayList(Node) = .empty,
    open: std.ArrayList(u32) = .empty,
    queue: std.ArrayList(u32) = .empty,
    visited: std.ArrayList(u8) = .empty,

    pub fn init(allocator: Allocator) PathFinder {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *PathFinder) void {
        self.nodes.deinit(self.allocator);
        self.open.deinit(self.allocator);
        self.queue.deinit(self.allocator);
        self.visited.deinit(self.allocator);
    }

    fn isGoal(map: *const TileMap, cx: i32, cy: i32, to: GridPos, goal_adjacent: bool) bool {
        if (cx == to.x and cy == to.y) return true;
        if (!goal_adjacent) return false;
        const manhattan = @abs(cx - to.x) + @abs(cy - to.y);
        return manhattan == 1 and map.isWalkable(cx, cy);
    }

    /// 4 邻接 A*，曼哈顿启发；out 被清空后写入从起点(不含)到终点(含)的格子序列。
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
        try self.nodes.resize(self.allocator, n);
        @memset(self.nodes.items, Node{ .g = 0, .parent = -1, .closed = false, .open = false });
        self.open.clearRetainingCapacity();

        const w: i32 = @intCast(map.width);
        const start_i: usize = @as(usize, @intCast(from.y)) * map.width + @as(usize, @intCast(from.x));
        self.nodes.items[start_i].open = true;
        try self.open.append(self.allocator, @intCast(start_i));

        var expanded: usize = 0;
        var found_i: ?usize = null;
        while (self.open.items.len > 0 and expanded < n) {
            var best: usize = 0;
            var best_f: u32 = std.math.maxInt(u32);
            for (self.open.items, 0..) |oi, k| {
                const ox: i32 = @intCast(oi % map.width);
                const oy: i32 = @intCast(oi / map.width);
                const hh: u32 = @abs(ox - to.x) + @abs(oy - to.y);
                const f = self.nodes.items[oi].g + hh;
                if (f < best_f) {
                    best_f = f;
                    best = k;
                }
            }
            const cur = self.open.swapRemove(best);
            self.nodes.items[cur].open = false;
            self.nodes.items[cur].closed = true;
            expanded += 1;

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
                if (self.nodes.items[ni].closed) continue;
                const ng = self.nodes.items[cur].g + 1;
                if (!self.nodes.items[ni].open) {
                    self.nodes.items[ni].open = true;
                    self.nodes.items[ni].g = ng;
                    self.nodes.items[ni].parent = @intCast(cur);
                    try self.open.append(self.allocator, @intCast(ni));
                } else if (ng < self.nodes.items[ni].g) {
                    self.nodes.items[ni].g = ng;
                    self.nodes.items[ni].parent = @intCast(cur);
                }
            }
        }
        const goal_i = found_i orelse return false;

        var idx: i32 = @intCast(goal_i);
        var guard: usize = 0;
        while (idx >= 0 and idx != @as(i32, @intCast(start_i)) and guard <= n) : (guard += 1) {
            const u: usize = @intCast(idx);
            try out.append(self.allocator, .{ .x = @intCast(u % map.width), .y = @intCast(u / map.width) });
            idx = self.nodes.items[u].parent;
        }
        std.mem.reverse(GridPos, out.items);
        return true;
    }

    /// BFS：把 max_steps 步内可达格并入 mask；返回新并入的格数。
    pub fn reach(self: *PathFinder, map: *const TileMap, from: GridPos, max_steps: u32, mask: *vision.Mask) !u32 {
        if (!map.inBounds(from.x, from.y) or !map.isWalkable(from.x, from.y)) return 0;
        const n = @as(usize, map.width) * map.height;
        try self.visited.resize(self.allocator, n);
        @memset(self.visited.items, 0);
        self.queue.clearRetainingCapacity();

        const start_i: usize = @as(usize, @intCast(from.y)) * map.width + @as(usize, @intCast(from.x));
        self.visited.items[start_i] = 1;
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
                if (self.visited.items[ni] != 0) continue;
                self.visited.items[ni] = 1;
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
