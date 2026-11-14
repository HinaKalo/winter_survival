const std = @import("std");
const delve = @import("delve");
const iso = @import("iso");
const kit = @import("kit");

const usage = "usage: winter_survival [--probe <file.lua>] [--script <file.lua>] [--save-dir <dir>] [--no-audio] [--dev] [--scene <name>] [--fixture <name>]\n";

var probe_buf: [1024]u8 = undefined;
var script_buf: [1024]u8 = undefined;
var save_dir_buf: [1024]u8 = undefined;

pub fn main(init: std.process.Init) !void {
    // 使用默认（DebugAllocator）分配器，可检测内存泄漏
    try delve.init(init, delve.mem.createDefaultAllocator());
    const allocator = delve.mem.getAllocator();

    // Copy parsed values before the argument iterator releases its storage.
    var probe_path: ?[:0]const u8 = null;
    var main_script: [:0]const u8 = "assets/main.lua";
    var save_dir: ?[:0]const u8 = null;
    var no_audio = false;
    var dev_mode = false;
    {
        var it = try init.minimal.args.iterateAllocator(allocator);
        defer it.deinit();
        _ = it.skip();
        var args: std.ArrayList([]const u8) = .empty;
        defer args.deinit(allocator);
        while (it.next()) |arg| try args.append(allocator, arg);
        const opts = kit.launch_args.parse(args.items) catch {
            std.debug.print("{s}", .{usage});
            return error.BadArguments;
        };
        if (opts.probe) |p| probe_path = copyArg(&probe_buf, p) catch {
            std.debug.print("{s}", .{usage});
            return error.BadArguments;
        };
        if (opts.script) |p| main_script = copyArg(&script_buf, p) catch {
            std.debug.print("{s}", .{usage});
            return error.BadArguments;
        };
        if (opts.save_dir) |p| save_dir = copyArg(&save_dir_buf, p) catch {
            std.debug.print("{s}", .{usage});
            return error.BadArguments;
        };
        no_audio = opts.no_audio;
        dev_mode = opts.dev;
        kit.sys.configureLaunch(opts.dev, opts.scene, opts.fixture);
    }
    if (save_dir) |d| {
        kit.sys.configure(d);
    }

    if (!no_audio) {
        if (init.environ_map.get("STARTER_NO_AUDIO")) |v| {
            no_audio = std.ascii.eqlIgnoreCase(v, "1") or std.ascii.eqlIgnoreCase(v, "true") or
                std.ascii.eqlIgnoreCase(v, "yes");
        }
    }

    try iso.engine.register(.{
        .main_script = main_script,
        .dev_hot_reload = dev_mode,
    });

    // kit：输入(-75)、音频(-65)、UI(-55) + Lua 绑定（探针 -80）
    try kit.rawinput.register(.{ .dev_console = dev_mode });
    try kit.audio.register(.{ .playback = !no_audio });
    try kit.ui.register();
    iso.script_host.addBinder(kit.lua_audio.bind);
    iso.script_host.addBinder(kit.lua_ui.bind);
    iso.script_host.addBinder(kit.lua_input.bind);
    iso.script_host.addBinder(kit.sys.bind);
    if (probe_path) |p| {
        iso.script_host.addBinder(kit.probe.bind);
        try kit.probe.register(.{ .script = p });
        try kit.probe.startWatchdog(init.io);
    }
    defer if (probe_path != null) kit.probe.stopWatchdog(); // 幂等

    try delve.app.start(.{
        .title = "Thirty Below",
        .width = 1280,
        .height = 720,
        .enable_audio = !no_audio,
    });

    if (probe_path != null) {
        kit.probe.stopWatchdog();
        try kit.probe.result();
    }
}

fn copyArg(buffer: []u8, value: []const u8) error{BadArguments}![:0]const u8 {
    if (value.len >= buffer.len) return error.BadArguments;
    @memcpy(buffer[0..value.len], value);
    buffer[value.len] = 0;
    return buffer[0..value.len :0];
}
