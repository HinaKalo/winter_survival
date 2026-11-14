//! 纯逻辑存档名校验：白名单 `[a-z0-9_-]{1,32}`。
const std = @import("std");

pub fn isValid(name: []const u8) bool {
    if (name.len == 0 or name.len > 32) return false;
    for (name) |c| {
        const ok = (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9') or
            c == '_' or c == '-';
        if (!ok) return false;
    }
    return true;
}

test "save_name accepts valid names and rejects traversal, empty, too long, uppercase, dots" {
    try std.testing.expect(isValid("run_1"));
    try std.testing.expect(isValid("settings"));
    try std.testing.expect(isValid("a-b_09"));
    try std.testing.expect(isValid("12345678901234567890123456789012")); // 32 chars

    try std.testing.expect(!isValid(""));
    try std.testing.expect(!isValid("123456789012345678901234567890123")); // 33 chars
    try std.testing.expect(!isValid("../x"));
    try std.testing.expect(!isValid("Run_1"));
    try std.testing.expect(!isValid("run.sav"));
    try std.testing.expect(!isValid("a/b"));
}
