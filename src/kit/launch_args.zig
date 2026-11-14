//! Pure command-line validation shared by the entry point and unit tests.
const std = @import("std");
const save_name = @import("save_name.zig");

pub const Options = struct {
    probe: ?[]const u8 = null,
    script: ?[]const u8 = null,
    save_dir: ?[]const u8 = null,
    scene: ?[]const u8 = null,
    fixture: ?[]const u8 = null,
    dev: bool = false,
    no_audio: bool = false,
};

pub fn parse(args: []const []const u8) error{BadArguments}!Options {
    var opts: Options = .{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--dev")) {
            opts.dev = true;
        } else if (std.mem.eql(u8, arg, "--no-audio")) {
            opts.no_audio = true;
        } else {
            const is_probe = std.mem.eql(u8, arg, "--probe");
            const is_script = std.mem.eql(u8, arg, "--script");
            const is_save = std.mem.eql(u8, arg, "--save-dir");
            const is_scene = std.mem.eql(u8, arg, "--scene");
            const is_fixture = std.mem.eql(u8, arg, "--fixture");
            if (!is_probe and !is_script and !is_save and !is_scene and !is_fixture) return error.BadArguments;
            i += 1;
            if (i >= args.len or args[i].len == 0 or std.mem.startsWith(u8, args[i], "--")) return error.BadArguments;
            const value = args[i];
            if (is_scene or is_fixture) {
                if (!save_name.isValid(value)) return error.BadArguments;
                if (is_scene) opts.scene = value else opts.fixture = value;
            } else if (is_probe) opts.probe = value else if (is_script) opts.script = value else opts.save_dir = value;
        }
    }
    if (!opts.dev and (opts.scene != null or opts.fixture != null)) return error.BadArguments;
    return opts;
}

test "launch arguments require valid names and dev mode" {
    try std.testing.expectError(error.BadArguments, parse(&.{"--scene"}));
    try std.testing.expectError(error.BadArguments, parse(&.{ "--scene", "home" }));
    try std.testing.expectError(error.BadArguments, parse(&.{ "--dev", "--fixture", "../bad" }));
    try std.testing.expectError(error.BadArguments, parse(&.{ "--scene", "--dev" }));
    const opts = try parse(&.{ "--scene", "home", "--fixture", "day3_1900", "--dev" });
    try std.testing.expect(opts.dev);
    try std.testing.expectEqualStrings("home", opts.scene.?);
    try std.testing.expectEqualStrings("day3_1900", opts.fixture.?);
}
