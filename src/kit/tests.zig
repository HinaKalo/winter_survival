// 测试根：kit 的纯逻辑文件。
const std = @import("std");

test {
    std.testing.refAllDecls(@import("audio_catalog.zig"));
    std.testing.refAllDecls(@import("text.zig"));
    std.testing.refAllDecls(@import("ui_geom.zig"));
    std.testing.refAllDecls(@import("pad_logic.zig"));
    std.testing.refAllDecls(@import("save_name.zig"));
}
