// 测试根：kit 的纯逻辑文件。
const std = @import("std");

test {
    std.testing.refAllDecls(@import("audio_catalog.zig"));
}
