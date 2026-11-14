const std = @import("std");
const delve = @import("delve");
const iso = @import("iso");
const kit = @import("kit");

const usage = "usage: winter_survival [--probe <file.lua>] [--no-audio]\n";

var probe_buf: [1024]u8 = undefined;

pub fn main(init: std.process.Init) !void {
    // 使用默认（DebugAllocator）分配器，可检测内存泄漏
    try delve.init(init, delve.mem.createDefaultAllocator());
    const allocator = delve.mem.getAllocator();

    // CLI：[--probe <file.lua>] [--no-audio]
    // 探针路径放静态缓冲：delve 的 DebugAllocator 在 app.start 内部就已 deinit，
    // 之后再 free 会出问题，且泄漏检查也会提前触发。
    var probe_path: ?[:0]const u8 = null;
    var no_audio = false;
    {
        var it = try init.minimal.args.iterateAllocator(allocator);
        defer it.deinit();
        _ = it.skip(); // argv[0]
        while (it.next()) |arg| {
            if (std.mem.eql(u8, arg, "--no-audio")) {
                no_audio = true;
            } else if (std.mem.eql(u8, arg, "--probe")) {
                const path = it.next() orelse {
                    std.debug.print("--probe needs a file argument\n{s}", .{usage});
                    return error.BadArguments;
                };
                if (path.len >= probe_buf.len) {
                    std.debug.print("--probe path too long\n", .{});
                    return error.BadArguments;
                }
                @memcpy(probe_buf[0..path.len], path);
                probe_buf[path.len] = 0;
                probe_path = probe_buf[0..path.len :0];
            } else {
                std.debug.print("unknown argument: {s}\n{s}", .{ arg, usage });
                return error.BadArguments;
            }
        }
    }

    if (!no_audio) {
        if (init.environ_map.get("STARTER_NO_AUDIO")) |v| {
            no_audio = std.ascii.eqlIgnoreCase(v, "1") or std.ascii.eqlIgnoreCase(v, "true") or
                std.ascii.eqlIgnoreCase(v, "yes");
        }
    }

    try iso.engine.register(.{ .main_script = "assets/main.lua" });

    // kit：音频 + Lua 绑定（探针先于世界/脚本宿主注册，优先级 -80）
    try kit.audio.register(.{ .playback = !no_audio });
    iso.script_host.addBinder(kit.lua_audio.bind);
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
