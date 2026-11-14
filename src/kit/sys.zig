//! 存档系统与运行环境助手 `sys`：原子写入、目录列表、删除、Lua 堆统计与平台名。
const builtin = @import("builtin");
const std = @import("std");
const delve = @import("delve");
const iso = @import("iso");
const lua_util = delve.scripting.lua;
const mem = delve.mem;
const zlua = @import("zlua");

const save_name = @import("save_name.zig");
const file_paths = @import("file_paths.zig");

const max_save_bytes: usize = 8 * 1024 * 1024;
var save_dir_buf: [512]u8 = undefined;
var save_dir_len: usize = 5;

fn initDefaultDir() void {
    @memcpy(save_dir_buf[0..5], "saves");
    save_dir_len = 5;
}

var dir_initialized: bool = false;

fn getSaveDir() []const u8 {
    if (!dir_initialized) {
        initDefaultDir();
        dir_initialized = true;
    }
    return save_dir_buf[0..save_dir_len];
}

pub fn configure(dir: []const u8) void {
    if (dir.len == 0 or dir.len >= save_dir_buf.len) return;
    @memcpy(save_dir_buf[0..dir.len], dir);
    save_dir_len = dir.len;
    dir_initialized = true;
}

var launch_dev = false;
var launch_scene_buf: [32]u8 = undefined;
var launch_scene_len: usize = 0;
var launch_fixture_buf: [32]u8 = undefined;
var launch_fixture_len: usize = 0;

pub fn configureLaunch(dev: bool, scene: ?[]const u8, fixture: ?[]const u8) void {
    launch_dev = dev;
    launch_scene_len = 0;
    launch_fixture_len = 0;
    if (scene) |v| if (save_name.isValid(v)) {
        @memcpy(launch_scene_buf[0..v.len], v);
        launch_scene_len = v.len;
    };
    if (fixture) |v| if (save_name.isValid(v)) {
        @memcpy(launch_fixture_buf[0..v.len], v);
        launch_fixture_len = v.len;
    };
}

pub fn bind(lua: *lua_util.Lua) void {
    lua.createTable(0, 9);
    setFn(lua, "save_write", zlua.wrap(l_saveWrite));
    setFn(lua, "save_read", zlua.wrap(l_saveRead));
    setFn(lua, "save_list", zlua.wrap(l_saveList));
    setFn(lua, "save_delete", zlua.wrap(l_saveDelete));
    setFn(lua, "save_exists", zlua.wrap(l_saveExists));
    setFn(lua, "lua_heap", zlua.wrap(l_luaHeap));
    setFn(lua, "platform", zlua.wrap(l_platform));
    setFn(lua, "launch_opts", zlua.wrap(l_launchOpts));
    setFn(lua, "list_files", zlua.wrap(l_listFiles));
    lua.setGlobal("sys");
}

fn setFn(lua: *lua_util.Lua, name: [:0]const u8, func: zlua.CFn) void {
    lua.pushFunction(func);
    lua.setField(-2, name);
}

fn l_saveWrite(lua: *zlua.Lua) i32 {
    const name = lua.toString(1) catch {
        lua.pushBoolean(false);
        return 1;
    };
    const text = lua.toString(2) catch {
        lua.pushBoolean(false);
        return 1;
    };
    if (!save_name.isValid(name) or text.len > max_save_bytes) {
        lua.pushBoolean(false);
        return 1;
    }
    if (std.mem.indexOfScalar(u8, text, 0) != null) {
        lua.pushBoolean(false);
        return 1;
    }

    const io = delve.io.getIo();
    const dir_path = getSaveDir();
    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(io, dir_path) catch {
        lua.pushBoolean(false);
        return 1;
    };

    var tmp_buf: [600]u8 = undefined;
    var dst_buf: [600]u8 = undefined;
    const tmp_rel = std.fmt.bufPrint(&tmp_buf, "{s}/{s}.tmp", .{ dir_path, name }) catch {
        lua.pushBoolean(false);
        return 1;
    };
    const dst_rel = std.fmt.bufPrint(&dst_buf, "{s}/{s}.sav", .{ dir_path, name }) catch {
        lua.pushBoolean(false);
        return 1;
    };

    cwd.writeFile(io, .{ .sub_path = tmp_rel, .data = text }) catch {
        lua.pushBoolean(false);
        return 1;
    };
    std.Io.Dir.rename(cwd, tmp_rel, cwd, dst_rel, io) catch {
        cwd.deleteFile(io, tmp_rel) catch {};
        lua.pushBoolean(false);
        return 1;
    };

    lua.pushBoolean(true);
    return 1;
}

fn l_saveRead(lua: *zlua.Lua) i32 {
    const name = lua.toString(1) catch {
        lua.pushNil();
        return 1;
    };
    if (!save_name.isValid(name)) {
        lua.pushNil();
        return 1;
    }

    const io = delve.io.getIo();
    const dir_path = getSaveDir();
    var path_buf: [600]u8 = undefined;
    const rel = std.fmt.bufPrint(&path_buf, "{s}/{s}.sav", .{ dir_path, name }) catch {
        lua.pushNil();
        return 1;
    };

    const alloc = mem.getAllocator();
    const data = std.Io.Dir.cwd().readFileAlloc(io, rel, alloc, .limited(max_save_bytes)) catch {
        lua.pushNil();
        return 1;
    };
    defer alloc.free(data);

    _ = lua.pushString(data);
    return 1;
}

fn l_saveList(lua: *zlua.Lua) i32 {
    lua.createTable(0, 0);
    const io = delve.io.getIo();
    const dir_path = getSaveDir();

    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch return 1;
    defer dir.close(io);

    const alloc = mem.getAllocator();
    var names: std.ArrayList([]u8) = .empty;
    defer {
        for (names.items) |n| alloc.free(n);
        names.deinit(alloc);
    }

    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".sav")) continue;
        const base = entry.name[0 .. entry.name.len - 4];
        if (!save_name.isValid(base)) continue;
        const copy = alloc.dupe(u8, base) catch continue;
        names.append(alloc, copy) catch {
            alloc.free(copy);
            continue;
        };
    }

    std.mem.sort([]u8, names.items, {}, struct {
        fn lessThan(_: void, a: []u8, b: []u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    for (names.items, 0..) |n, i| {
        _ = lua.pushString(n);
        lua.rawSetIndex(-2, @intCast(i + 1));
    }
    return 1;
}

fn l_saveDelete(lua: *zlua.Lua) i32 {
    const name = lua.toString(1) catch {
        lua.pushBoolean(false);
        return 1;
    };
    if (!save_name.isValid(name)) {
        lua.pushBoolean(false);
        return 1;
    }

    const io = delve.io.getIo();
    const dir_path = getSaveDir();
    var path_buf: [600]u8 = undefined;
    const rel = std.fmt.bufPrint(&path_buf, "{s}/{s}.sav", .{ dir_path, name }) catch {
        lua.pushBoolean(false);
        return 1;
    };

    std.Io.Dir.cwd().deleteFile(io, rel) catch {
        lua.pushBoolean(false);
        return 1;
    };
    lua.pushBoolean(true);
    return 1;
}

fn l_saveExists(lua: *zlua.Lua) i32 {
    const name = lua.toString(1) catch {
        lua.pushBoolean(false);
        return 1;
    };
    if (!save_name.isValid(name)) {
        lua.pushBoolean(false);
        return 1;
    }

    const io = delve.io.getIo();
    const dir_path = getSaveDir();
    var path_buf: [600]u8 = undefined;
    const rel = std.fmt.bufPrint(&path_buf, "{s}/{s}.sav", .{ dir_path, name }) catch {
        lua.pushBoolean(false);
        return 1;
    };

    const file = std.Io.Dir.cwd().openFile(io, rel, .{}) catch {
        lua.pushBoolean(false);
        return 1;
    };
    file.close(io);
    lua.pushBoolean(true);
    return 1;
}

fn l_luaHeap(lua: *zlua.Lua) i32 {
    lua.createTable(0, 2);
    lua.pushInteger(@intCast(iso.vm.heapBytes()));
    lua.setField(-2, "bytes");
    lua.pushInteger(@intCast(iso.vm.heapPeak()));
    lua.setField(-2, "peak");
    return 1;
}

fn l_platform(lua: *zlua.Lua) i32 {
    _ = lua.pushString(@tagName(builtin.os.tag));
    return 1;
}

fn l_launchOpts(lua: *zlua.Lua) i32 {
    lua.createTable(0, 3);
    lua.pushBoolean(launch_dev);
    lua.setField(-2, "dev");
    if (launch_scene_len > 0) _ = lua.pushString(launch_scene_buf[0..launch_scene_len]) else lua.pushNil();
    lua.setField(-2, "scene");
    if (launch_fixture_len > 0) _ = lua.pushString(launch_fixture_buf[0..launch_fixture_len]) else lua.pushNil();
    lua.setField(-2, "fixture");
    return 1;
}

fn l_listFiles(lua: *zlua.Lua) i32 {
    const root = lua.toString(1) catch return badDir(lua);
    if (!file_paths.validDir(root)) return badDir(lua);
    const suffix = lua.toString(2) catch "";
    const io = delve.io.getIo();
    var dir = std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            lua.createTable(0, 0); // missing directory: empty list (P0-PLAN 3.0)
            return 1;
        }
        return ioError(lua);
    };
    defer dir.close(io);
    const alloc = mem.getAllocator();
    var paths: std.ArrayList([]u8) = .empty;
    defer {
        for (paths.items) |path| alloc.free(path);
        paths.deinit(alloc);
    }
    var walker = dir.walk(alloc) catch return ioError(lua);
    defer walker.deinit();
    while (true) {
        const entry = (walker.next(io) catch return ioError(lua)) orelse break;
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.path, suffix)) continue;
        const path = std.fmt.allocPrint(alloc, "{s}/{s}", .{ root, entry.path }) catch return ioError(lua);
        for (path) |*c| if (c.* == '\\') {
            c.* = '/';
        };
        paths.append(alloc, path) catch {
            alloc.free(path);
            return ioError(lua);
        };
    }
    file_paths.sort(paths.items);
    lua.createTable(0, 0);
    for (paths.items, 0..) |path, i| {
        _ = lua.pushString(path);
        lua.rawSetIndex(-2, @intCast(i + 1));
    }
    return 1;
}

fn ioError(lua: *zlua.Lua) i32 {
    lua.pushNil();
    _ = lua.pushString("io_error");
    return 2;
}

fn badDir(lua: *zlua.Lua) i32 {
    lua.pushNil();
    _ = lua.pushString("bad_dir");
    return 2;
}
