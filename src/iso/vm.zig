//! 自建 Lua VM：使用计数分配器（LuaHeap + smp_allocator）替代框架的 ArenaAllocator，
//! 避免长时间运行内存只增不减；并照搬 Delve manager.zig 绑定 7 个 scriptapi 库。
const std = @import("std");
const delve = @import("delve");
const debug = delve.debug;
const math = delve.math;
const modules = delve.modules;
const app = delve.platform.app;
const binder = delve.scripting.binder;
const lua_util = delve.scripting.lua;

pub const Lua = lua_util.Lua;

pub const LuaHeap = struct {
    backing: std.mem.Allocator,
    bytes: usize = 0,
    peak: usize = 0,
    limit: usize = 512 << 20,

    pub fn allocator(self: *LuaHeap) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    const vtable = std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };

    fn addBytes(self: *LuaHeap, n: usize) bool {
        if (n > self.limit or self.bytes > self.limit - n) return false;
        self.bytes += n;
        if (self.bytes > self.peak) self.peak = self.bytes;
        return true;
    }

    fn subBytes(self: *LuaHeap, n: usize) void {
        if (self.bytes >= n) {
            self.bytes -= n;
        } else {
            self.bytes = 0;
        }
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *LuaHeap = @ptrCast(@alignCast(ctx));
        if (!self.addBytes(len)) return null;
        const ptr = self.backing.rawAlloc(len, alignment, ret_addr) orelse {
            self.subBytes(len);
            return null;
        };
        return ptr;
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *LuaHeap = @ptrCast(@alignCast(ctx));
        if (new_len > memory.len) {
            const delta = new_len - memory.len;
            if (!self.addBytes(delta)) return false;
            if (!self.backing.rawResize(memory, alignment, new_len, ret_addr)) {
                self.subBytes(delta);
                return false;
            }
            return true;
        } else {
            if (!self.backing.rawResize(memory, alignment, new_len, ret_addr)) return false;
            self.subBytes(memory.len - new_len);
            return true;
        }
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *LuaHeap = @ptrCast(@alignCast(ctx));
        if (new_len > memory.len) {
            const delta = new_len - memory.len;
            if (!self.addBytes(delta)) return null;
            const ptr = self.backing.rawRemap(memory, alignment, new_len, ret_addr) orelse {
                self.subBytes(delta);
                return null;
            };
            return ptr;
        } else {
            const ptr = self.backing.rawRemap(memory, alignment, new_len, ret_addr) orelse return null;
            self.subBytes(memory.len - new_len);
            return ptr;
        }
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *LuaHeap = @ptrCast(@alignCast(ctx));
        self.backing.rawFree(memory, alignment, ret_addr);
        self.subBytes(memory.len);
    }
};

pub var heap: LuaHeap = .{ .backing = std.heap.smp_allocator };

var lua_state: *Lua = undefined;
var initialized: bool = false;
var scriptapi_registered: bool = false;

const functions_to_ignore = [_][:0]const u8{ "libInit", "libTick", "libDraw", "libCleanup" };

pub fn init() !void {
    if (initialized) return;
    debug.log("Lua: system starting up!", .{});

    heap.bytes = 0;
    heap.peak = 0;
    lua_state = try lua_util.initLua(heap.allocator());
    errdefer {
        lua_state.deinit();
    }

    lua_state.openLibs();
    try bindDelveLibs(lua_state);

    initialized = true;
    debug.log("Lua: ready to go!", .{});
}

pub fn deinit() void {
    if (!initialized) return;
    initialized = false;
    lua_state.deinit();
    if (heap.bytes != 0) {
        debug.err("LuaHeap leak on deinit: {d} bytes remaining", .{heap.bytes});
    }
}

pub fn get() *Lua {
    std.debug.assert(initialized);
    return lua_state;
}

pub fn ready() bool {
    return initialized;
}

pub fn runLine(code: [:0]const u8) !void {
    if (!initialized) {
        debug.log("Lua: could not run line, lua is not initialized yet.", .{});
        return;
    }
    lua_state.loadString(code) catch |err| {
        const msg = lua_state.toString(-1) catch "(no error message)";
        debug.err("Lua loadString error: {s}", .{msg});
        lua_state.pop(1);
        return err;
    };
    lua_state.protectedCall(.{ .args = 0, .results = 0 }) catch |err| {
        const msg = lua_state.toString(-1) catch "(no error message)";
        debug.err("Lua runLine error: {s}", .{msg});
        lua_state.pop(1);
        return err;
    };
}

pub fn heapBytes() usize {
    return heap.bytes;
}

pub fn heapPeak() usize {
    return heap.peak;
}

fn bindDelveLibs(lua: *Lua) !void {
    const bound_types = &[_]binder.BoundType{
        .{ .Type = math.Vec2, .name = "delve.math.Vec2", .ignore_fields = &[_][:0]const u8{} },
        .{ .Type = math.Vec3, .name = "delve.math.Vec3", .ignore_fields = &[_][:0]const u8{} },
        .{ .Type = math.Vec4, .name = "delve.math.Vec4", .ignore_fields = &[_][:0]const u8{} },
        .{ .Type = math.Mat4, .name = "delve.math.Mat4", .ignore_fields = &[_][:0]const u8{} },
        .{ .Type = math.Quaternion, .name = "delve.math.Quaternion", .ignore_fields = &[_][:0]const u8{} },
        .{ .Type = app, .name = "delve.platform.App", .ignore_fields = &[_][:0]const u8{} },
    };

    const registry = binder.Registry(.{ .entries = bound_types });
    try registry.bindTypes(lua);

    try bindZigLibrary(lua, "assets", delve.api.assets, registry);
    try bindZigLibrary(lua, "display", delve.api.display, registry);
    try bindZigLibrary(lua, "draw", delve.api.draw, registry);
    try bindZigLibrary(lua, "text", delve.api.text, registry);
    try bindZigLibrary(lua, "graphics", delve.api.graphics, registry);
    try bindZigLibrary(lua, "input.mouse", delve.api.mouse, registry);
    try bindZigLibrary(lua, "input.keyboard", delve.api.keyboard, registry);

    scriptapi_registered = true;
}

fn bindZigLibrary(lua: *Lua, comptime name: [:0]const u8, comptime zigfile: anytype, comptime registry: anytype) !void {
    const found_fns = comptime registry.findLibraryFunctions(zigfile, &functions_to_ignore);
    registry.bindLibrary(lua, name, found_fns);

    if (scriptapi_registered) return;

    var scriptApiModule = modules.Module{
        .name = "scriptapi." ++ name,
        .priority = modules.Priority.first,
    };

    if (@hasDecl(zigfile, "libInit")) {
        scriptApiModule.init_fn = zigfile.libInit;
    }
    if (@hasDecl(zigfile, "libTick")) {
        scriptApiModule.tick_fn = zigfile.libTick;
    }
    if (@hasDecl(zigfile, "libDraw")) {
        scriptApiModule.draw_fn = zigfile.libDraw;
    }
    if (@hasDecl(zigfile, "libPreDraw")) {
        scriptApiModule.pre_draw_fn = zigfile.libPreDraw;
    }
    if (@hasDecl(zigfile, "libPostDraw")) {
        scriptApiModule.post_draw_fn = zigfile.libPostDraw;
    }
    if (@hasDecl(zigfile, "libCleanup")) {
        scriptApiModule.cleanup_fn = zigfile.libCleanup;
    }

    try modules.registerModule(scriptApiModule);
}

test "LuaHeap counts allocations, frees to zero, enforces limit, and tracks realloc" {
    var h = LuaHeap{
        .backing = std.testing.allocator,
        .limit = 1024,
    };
    const alloc = h.allocator();

    const buf1 = try alloc.alloc(u8, 256);
    try std.testing.expectEqual(@as(usize, 256), h.bytes);
    try std.testing.expectEqual(@as(usize, 256), h.peak);

    // Resize up via realloc (allocates new 512 before freeing old 256, so peak reaches 768)
    var buf = try alloc.realloc(buf1, 512);
    errdefer alloc.free(buf);
    try std.testing.expectEqual(@as(usize, 512), h.bytes);
    try std.testing.expectEqual(@as(usize, 768), h.peak);

    // Exceeding limit returns OutOfMemory (null from rawAlloc/rawRemap)
    try std.testing.expectError(error.OutOfMemory, alloc.alloc(u8, 600));
    try std.testing.expectEqual(@as(usize, 512), h.bytes);

    // Shrink
    buf = try alloc.realloc(buf, 128);
    try std.testing.expectEqual(@as(usize, 128), h.bytes);
    try std.testing.expectEqual(@as(usize, 768), h.peak);

    alloc.free(buf);
    try std.testing.expectEqual(@as(usize, 0), h.bytes);
    try std.testing.expectEqual(@as(usize, 768), h.peak);
}
