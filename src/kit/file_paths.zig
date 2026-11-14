//! Pure validation and sorting for project-relative file enumeration.
const std = @import("std");

pub fn validDir(path: []const u8) bool {
    if (!(std.mem.eql(u8, path, "assets") or std.mem.eql(u8, path, "tests") or
        std.mem.startsWith(u8, path, "assets/") or std.mem.startsWith(u8, path, "tests/"))) return false;
    if (std.mem.indexOfScalar(u8, path, '\\') != null or std.mem.indexOfScalar(u8, path, 0) != null or std.mem.indexOf(u8, path, "..") != null) return false;
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| if (std.mem.eql(u8, part, "..") or std.mem.eql(u8, part, ".") or part.len == 0) return false;
    return true;
}

pub fn sort(paths: [][]u8) void {
    std.mem.sort([]u8, paths, {}, struct {
        fn less(_: void, a: []u8, b: []u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.less);
}

test "directory validation and byte ordering" {
    try std.testing.expect(validDir("assets/scripts"));
    try std.testing.expect(validDir("tests/lua"));
    for ([_][]const u8{ "", "src", "/etc", "assets/../src", "assets/name..txt", "tests/..", "assets\\scripts", "assets//foo", "assets/./foo" }) |bad| try std.testing.expect(!validDir(bad));
    var paths = [_][]u8{ @constCast("tests/z"), @constCast("tests/A"), @constCast("tests/a") };
    sort(&paths);
    try std.testing.expectEqualStrings("tests/A", paths[0]);
    try std.testing.expectEqualStrings("tests/a", paths[1]);
    try std.testing.expectEqualStrings("tests/z", paths[2]);
}
