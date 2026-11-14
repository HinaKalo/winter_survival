// 测试根：引用四个纯逻辑文件，使其内部 test 块被执行。
const std = @import("std");

test {
    std.testing.refAllDecls(@import("coords.zig"));
    std.testing.refAllDecls(@import("camera.zig"));
    std.testing.refAllDecls(@import("tilemap.zig"));
    std.testing.refAllDecls(@import("world.zig"));
    std.testing.refAllDecls(@import("vm.zig"));
}
