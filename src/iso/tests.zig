// 测试根：引用四个纯逻辑文件，使其内部 test 块被执行。
const std = @import("std");

test {
    std.testing.refAllDecls(@import("coords.zig"));
    std.testing.refAllDecls(@import("camera.zig"));
    std.testing.refAllDecls(@import("tilemap.zig"));
    std.testing.refAllDecls(@import("pathfind.zig"));
    std.testing.refAllDecls(@import("vision.zig"));
    std.testing.refAllDecls(@import("lightmap.zig"));
    std.testing.refAllDecls(@import("tilemesh.zig"));
    std.testing.refAllDecls(@import("overlay.zig"));
    std.testing.refAllDecls(@import("world.zig"));
    std.testing.refAllDecls(@import("vm.zig"));
    std.testing.refAllDecls(@import("model.zig"));
    _ = @import("model_accept_test.zig");
}
