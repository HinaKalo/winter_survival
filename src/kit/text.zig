//! 纯逻辑文本排版：WSFN 二进制字体解析、UTF-8 解码、宽度测量、CJK/韩文/英文自动换行与禁则。
const std = @import("std");

pub const Glyph = struct {
    cp: u32,
    x: u16,
    y: u16,
    w: u8,
    h: u8,
    xoff: i8,
    yoff: i8,
    advance: u8,
};

pub const Font = struct {
    px: u16,
    line_height: u16,
    ascent: u16,
    atlas_w: u16,
    atlas_h: u16,
    fallback: u32,
    glyphs: []Glyph,

    pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) !Font {
        if (bytes.len < 32) return error.InvalidFontHeader;
        if (!std.mem.eql(u8, bytes[0..4], "WSFN")) return error.InvalidFontMagic;

        const version = std.mem.readInt(u16, bytes[4..6], .little);
        if (version != 1) return error.UnsupportedFontVersion;

        const px = std.mem.readInt(u16, bytes[6..8], .little);
        const line_height = std.mem.readInt(u16, bytes[8..10], .little);
        const ascent = std.mem.readInt(u16, bytes[10..12], .little);
        const atlas_w = std.mem.readInt(u16, bytes[12..14], .little);
        const atlas_h = std.mem.readInt(u16, bytes[14..16], .little);
        const glyph_count = std.mem.readInt(u32, bytes[16..20], .little);
        const fallback = std.mem.readInt(u32, bytes[20..24], .little);

        if (atlas_w == 0 or atlas_h == 0) return error.InvalidAtlasSize;

        const expected_len = 32 + @as(usize, glyph_count) * 16;
        if (bytes.len != expected_len) return error.InvalidFontLength;

        const glyphs = try allocator.alloc(Glyph, glyph_count);
        errdefer allocator.free(glyphs);

        var prev_cp: u32 = 0;
        for (0..glyph_count) |i| {
            const off = 32 + i * 16;
            const rec = bytes[off .. off + 16];
            const cp = std.mem.readInt(u32, rec[0..4], .little);
            const gx = std.mem.readInt(u16, rec[4..6], .little);
            const gy = std.mem.readInt(u16, rec[6..8], .little);
            const gw = rec[8];
            const gh = rec[9];
            const xoff: i8 = @bitCast(rec[10]);
            const yoff: i8 = @bitCast(rec[11]);
            const advance = rec[12];

            if (i > 0 and cp <= prev_cp) return error.UnsortedGlyphs;
            prev_cp = cp;

            if (@as(u32, gx) + @as(u32, gw) > @as(u32, atlas_w) or
                @as(u32, gy) + @as(u32, gh) > @as(u32, atlas_h))
            {
                return error.GlyphOutOfAtlasBounds;
            }

            glyphs[i] = .{
                .cp = cp,
                .x = gx,
                .y = gy,
                .w = gw,
                .h = gh,
                .xoff = xoff,
                .yoff = yoff,
                .advance = advance,
            };
        }

        return .{
            .px = px,
            .line_height = line_height,
            .ascent = ascent,
            .atlas_w = atlas_w,
            .atlas_h = atlas_h,
            .fallback = fallback,
            .glyphs = glyphs,
        };
    }

    pub fn deinit(self: *Font, allocator: std.mem.Allocator) void {
        allocator.free(self.glyphs);
        self.glyphs = &.{};
    }

    fn findExact(self: *const Font, cp: u32) ?Glyph {
        var lo: usize = 0;
        var hi: usize = self.glyphs.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            const g = self.glyphs[mid];
            if (g.cp < cp) {
                lo = mid + 1;
            } else if (g.cp > cp) {
                hi = mid;
            } else {
                return g;
            }
        }
        return null;
    }

    pub fn has(self: *const Font, cp: u32) bool {
        return self.findExact(cp) != null;
    }

    pub fn glyph(self: *const Font, cp: u32) ?Glyph {
        if (self.findExact(cp)) |g| return g;
        if (cp != self.fallback) {
            if (self.findExact(self.fallback)) |fb| return fb;
        }
        return null;
    }
};

pub const Utf8Iter = struct {
    bytes: []const u8,
    i: usize = 0,

    pub fn next(self: *Utf8Iter) ?u32 {
        if (self.i >= self.bytes.len) return null;
        const b0 = self.bytes[self.i];
        if (b0 < 0x80) {
            self.i += 1;
            return b0;
        } else if ((b0 & 0xE0) == 0xC0) {
            if (self.i + 1 >= self.bytes.len) {
                self.i += 1;
                return 0xFFFD;
            }
            const b1 = self.bytes[self.i + 1];
            if ((b1 & 0xC0) != 0x80) {
                self.i += 1;
                return 0xFFFD;
            }
            const cp = (@as(u32, b0 & 0x1F) << 6) | @as(u32, b1 & 0x3F);
            if (cp < 0x80) {
                self.i += 2;
                return 0xFFFD;
            }
            self.i += 2;
            return cp;
        } else if ((b0 & 0xF0) == 0xE0) {
            if (self.i + 2 >= self.bytes.len) {
                self.i += 1;
                return 0xFFFD;
            }
            const b1 = self.bytes[self.i + 1];
            const b2 = self.bytes[self.i + 2];
            if ((b1 & 0xC0) != 0x80 or (b2 & 0xC0) != 0x80) {
                self.i += 1;
                return 0xFFFD;
            }
            const cp = (@as(u32, b0 & 0x0F) << 12) | (@as(u32, b1 & 0x3F) << 6) | @as(u32, b2 & 0x3F);
            if (cp < 0x800 or (cp >= 0xD800 and cp <= 0xDFFF)) {
                self.i += 3;
                return 0xFFFD;
            }
            self.i += 3;
            return cp;
        } else if ((b0 & 0xF8) == 0xF0) {
            if (self.i + 3 >= self.bytes.len) {
                self.i += 1;
                return 0xFFFD;
            }
            const b1 = self.bytes[self.i + 1];
            const b2 = self.bytes[self.i + 2];
            const b3 = self.bytes[self.i + 3];
            if ((b1 & 0xC0) != 0x80 or (b2 & 0xC0) != 0x80 or (b3 & 0xC0) != 0x80) {
                self.i += 1;
                return 0xFFFD;
            }
            const cp = (@as(u32, b0 & 0x07) << 18) | (@as(u32, b1 & 0x3F) << 12) | (@as(u32, b2 & 0x3F) << 6) | @as(u32, b3 & 0x3F);
            if (cp < 0x10000 or cp > 0x10FFFF) {
                self.i += 4;
                return 0xFFFD;
            }
            self.i += 4;
            return cp;
        } else {
            self.i += 1;
            return 0xFFFD;
        }
    }
};

pub fn isCjkBreakable(cp: u32) bool {
    // CJK 统一表意文字、扩展 A、兼容表意文字、假名、CJK 标点/全角符号（不含韩文音节）
    return (cp >= 0x4E00 and cp <= 0x9FFF) or
        (cp >= 0x3400 and cp <= 0x4DBF) or
        (cp >= 0x20000 and cp <= 0x2A6DF) or
        (cp >= 0xF900 and cp <= 0xFAFF) or
        (cp >= 0x3040 and cp <= 0x30FF) or
        (cp >= 0x3000 and cp <= 0x303F) or
        (cp >= 0xFF00 and cp <= 0xFFEF) or
        cp == 0x2026; // …
}

pub fn noLineStart(cp: u32) bool {
    return switch (cp) {
        0xFF0C, // ，
        0x3002, // 。
        0x3001, // 、
        0xFF01, // ！
        0xFF1F, // ？
        0xFF1B, // ；
        0xFF1A, // ：
        0xFF09, // ）
        0x300D, // 」
        0x300F, // 』
        0x300B, // 》
        0x2026, // …
        => true,
        else => false,
    };
}

pub fn noLineEnd(cp: u32) bool {
    return switch (cp) {
        0xFF08, // （
        0x300C, // 「
        0x300E, // 『
        0x300A, // 《
        => true,
        else => false,
    };
}

fn glyphAdvance(font: *const Font, cp: u32) u32 {
    if (font.glyph(cp)) |g| return g.advance;
    return 0;
}

pub fn measure(font: *const Font, s: []const u8) u32 {
    var iter = Utf8Iter{ .bytes = s };
    var max_w: u32 = 0;
    var cur_w: u32 = 0;
    while (iter.next()) |cp| {
        if (cp == '\n') {
            if (cur_w > max_w) max_w = cur_w;
            cur_w = 0;
            continue;
        }
        if (cp == '\r') continue;
        cur_w += glyphAdvance(font, cp);
    }
    if (cur_w > max_w) max_w = cur_w;
    return max_w;
}

pub const Line = struct {
    start: u32,
    end: u32,
    width: u32,
};

pub const max_lines: usize = 256;
pub const max_text_bytes: usize = 16 * 1024;

pub fn wrap(font: *const Font, s: []const u8, max_w: u32, out: []Line) usize {
    const cap = @min(out.len, max_lines);
    if (cap == 0) return 0;

    const text = if (s.len > max_text_bytes) s[0..max_text_bytes] else s;
    if (text.len == 0) return 0;

    var line_count: usize = 0;
    var line_start: usize = 0;
    var cur_w: u32 = 0;

    // 最近一个合法断点：break_end 为本行结束字节（不含），next_start 为下一行起始字节，break_w 为本行宽度
    var has_break: bool = false;
    var break_end: usize = 0;
    var break_next_start: usize = 0;
    var break_w: u32 = 0;

    var iter = Utf8Iter{ .bytes = text };
    var prev_cp: u32 = 0;
    var prev_start: usize = 0;
    var prev_w_before: u32 = 0;
    var has_prev: bool = false;

    while (true) {
        const cp_start = iter.i;
        const maybe_cp = iter.next();
        if (maybe_cp == null) {
            if (line_count < cap) {
                out[line_count] = .{
                    .start = @intCast(line_start),
                    .end = @intCast(text.len),
                    .width = cur_w,
                };
                line_count += 1;
            }
            break;
        }
        const cp = maybe_cp.?;
        const cp_end = iter.i;

        if (cp == '\r') continue;

        if (cp == '\n') {
            if (line_count < cap) {
                out[line_count] = .{
                    .start = @intCast(line_start),
                    .end = @intCast(cp_start),
                    .width = cur_w,
                };
                line_count += 1;
            }
            if (line_count >= cap) break;
            line_start = cp_end;
            cur_w = 0;
            has_break = false;
            has_prev = false;
            continue;
        }

        const adv = glyphAdvance(font, cp);

        // 检查在 cp_start 之前（即 prev_cp 与 cp 之间）是否是一个合法断点
        if (has_prev and cp_start > line_start) {
            if (prev_cp == ' ' or prev_cp == '\t') {
                // 空格之后可断（行尾空格不计入下一行，且可从当前宽度中减去空格宽度或保留；这里保留行内已有字符，跳过空格）
                if (!noLineStart(cp)) {
                    has_break = true;
                    break_end = prev_start;
                    break_next_start = cp_start;
                    break_w = prev_w_before;
                }
            } else if ((isCjkBreakable(prev_cp) or isCjkBreakable(cp)) and cp != ' ' and cp != '\t') {
                if (!noLineEnd(prev_cp) and !noLineStart(cp)) {
                    has_break = true;
                    break_end = cp_start;
                    break_next_start = cp_start;
                    break_w = cur_w;
                }
            }
        }

        const is_space = (cp == ' ' or cp == '\t');
        if (max_w > 0 and !is_space and cur_w + adv > max_w and cp_start > line_start) {
            if (has_break) {
                out[line_count] = .{
                    .start = @intCast(line_start),
                    .end = @intCast(break_end),
                    .width = break_w,
                };
                line_count += 1;
                if (line_count >= cap) break;
                line_start = break_next_start;
                iter.i = line_start;
                cur_w = 0;
                has_break = false;
                has_prev = false;
                continue;
            } else {
                // 超长单词强制逐字断：如果前一个字符是 noLineEnd 且本行不止一个字符，可尝试退一步；否则直接在此处断
                var split_pos = cp_start;
                var split_w = cur_w;
                if (has_prev and noLineEnd(prev_cp) and prev_start > line_start) {
                    split_pos = prev_start;
                    split_w = prev_w_before;
                }
                out[line_count] = .{
                    .start = @intCast(line_start),
                    .end = @intCast(split_pos),
                    .width = split_w,
                };
                line_count += 1;
                if (line_count >= cap) break;
                line_start = split_pos;
                iter.i = line_start;
                cur_w = 0;
                has_break = false;
                has_prev = false;
                continue;
            }
        }

        prev_w_before = cur_w;
        cur_w += adv;
        prev_cp = cp;
        prev_start = cp_start;
        has_prev = true;
    }

    return line_count;
}

// ------------------------------------------------------------------ 单元测试

fn makeTestFont(allocator: std.mem.Allocator, glyphs_in: []const Glyph, fallback: u32) ![]u8 {
    const total = 32 + glyphs_in.len * 16;
    const buf = try allocator.alloc(u8, total);
    @memset(buf, 0);
    @memcpy(buf[0..4], "WSFN");
    std.mem.writeInt(u16, buf[4..6], 1, .little);
    std.mem.writeInt(u16, buf[6..8], 16, .little);
    std.mem.writeInt(u16, buf[8..10], 18, .little);
    std.mem.writeInt(u16, buf[10..12], 14, .little);
    std.mem.writeInt(u16, buf[12..14], 256, .little);
    std.mem.writeInt(u16, buf[14..16], 256, .little);
    std.mem.writeInt(u32, buf[16..20], @intCast(glyphs_in.len), .little);
    std.mem.writeInt(u32, buf[20..24], fallback, .little);
    for (glyphs_in, 0..) |g, i| {
        const off = 32 + i * 16;
        std.mem.writeInt(u32, buf[off..][0..4], g.cp, .little);
        std.mem.writeInt(u16, buf[off + 4 ..][0..2], g.x, .little);
        std.mem.writeInt(u16, buf[off + 6 ..][0..2], g.y, .little);
        buf[off + 8] = g.w;
        buf[off + 9] = g.h;
        buf[off + 10] = @bitCast(g.xoff);
        buf[off + 11] = @bitCast(g.yoff);
        buf[off + 12] = g.advance;
    }
    return buf;
}

test "Font.parse rejects bad magic, length, unsorted, out-of-bounds" {
    const alloc = std.testing.allocator;
    const valid = try makeTestFont(alloc, &.{
        .{ .cp = 'A', .x = 0, .y = 0, .w = 8, .h = 12, .xoff = 0, .yoff = 0, .advance = 8 },
        .{ .cp = 'B', .x = 8, .y = 0, .w = 8, .h = 12, .xoff = 0, .yoff = 0, .advance = 8 },
    }, 'A');
    defer alloc.free(valid);

    var font = try Font.parse(alloc, valid);
    defer font.deinit(alloc);
    try std.testing.expect(font.has('A'));
    try std.testing.expect(!font.has('Z'));
    try std.testing.expectEqual(@as(u32, 'A'), font.glyph('Z').?.cp);

    // Bad magic
    var bad = try alloc.dupe(u8, valid);
    defer alloc.free(bad);
    bad[0] = 'X';
    try std.testing.expectError(error.InvalidFontMagic, Font.parse(alloc, bad));

    // Truncated length
    try std.testing.expectError(error.InvalidFontLength, Font.parse(alloc, valid[0 .. valid.len - 1]));

    // Unsorted
    const unsorted = try makeTestFont(alloc, &.{
        .{ .cp = 'B', .x = 0, .y = 0, .w = 8, .h = 12, .xoff = 0, .yoff = 0, .advance = 8 },
        .{ .cp = 'A', .x = 8, .y = 0, .w = 8, .h = 12, .xoff = 0, .yoff = 0, .advance = 8 },
    }, 'A');
    defer alloc.free(unsorted);
    try std.testing.expectError(error.UnsortedGlyphs, Font.parse(alloc, unsorted));

    // Out of atlas bounds
    const oob = try makeTestFont(alloc, &.{
        .{ .cp = 'A', .x = 250, .y = 0, .w = 10, .h = 12, .xoff = 0, .yoff = 0, .advance = 8 },
    }, 'A');
    defer alloc.free(oob);
    try std.testing.expectError(error.GlyphOutOfAtlasBounds, Font.parse(alloc, oob));
}

test "Utf8Iter handles valid, truncated, and overlong sequences" {
    // 'A' + '中'(E4 B8 AD) + truncated(E4 B8) + overlong(C0 AF) + '가'(EA B0 80)
    const input = "A\xE4\xB8\xAD\xE4\xB8\xC0\xAF\xEA\xB0\x80";
    var it = Utf8Iter{ .bytes = input };
    try std.testing.expectEqual(@as(?u32, 'A'), it.next());
    try std.testing.expectEqual(@as(?u32, 0x4E2D), it.next());
    // \xE4\xB8 followed by \xC0: \xE4 sees \xC0 as non-continuation -> 0xFFFD, then \xB8 -> 0xFFFD, then \xC0\xAF -> 0xFFFD
    try std.testing.expectEqual(@as(?u32, 0xFFFD), it.next());
    try std.testing.expectEqual(@as(?u32, 0xFFFD), it.next());
    try std.testing.expectEqual(@as(?u32, 0xFFFD), it.next());
    try std.testing.expectEqual(@as(?u32, 0xAC00), it.next());
    try std.testing.expectEqual(@as(?u32, null), it.next());
}

test "wrap handles CJK, English word wrap, Korean space wrap, kinsoku, and max_lines" {
    const alloc = std.testing.allocator;
    // All glyphs fallback to '?' with advance = 10
    const bytes = try makeTestFont(alloc, &.{
        .{ .cp = ' ', .x = 0, .y = 0, .w = 0, .h = 0, .xoff = 0, .yoff = 0, .advance = 5 },
        .{ .cp = '?', .x = 0, .y = 0, .w = 8, .h = 12, .xoff = 0, .yoff = 0, .advance = 10 },
    }, '?');
    defer alloc.free(bytes);
    var font = try Font.parse(alloc, bytes);
    defer font.deinit(alloc);

    var lines: [max_lines]Line = undefined;

    // English word wrap: "hello world" (50 + 5 + 50 = 105), max_w = 80 -> "hello" | "world"
    const en = "hello world";
    const en_n = wrap(&font, en, 80, &lines);
    try std.testing.expectEqual(@as(usize, 2), en_n);
    try std.testing.expectEqualStrings("hello", en[lines[0].start..lines[0].end]);
    try std.testing.expectEqualStrings("world", en[lines[1].start..lines[1].end]);

    // Super long word force-breaks character by character
    const long = "abcdefgh"; // 80 px
    const long_n = wrap(&font, long, 30, &lines);
    try std.testing.expectEqual(@as(usize, 3), long_n);
    try std.testing.expectEqualStrings("abc", long[lines[0].start..lines[0].end]);
    try std.testing.expectEqualStrings("def", long[lines[1].start..lines[1].end]);
    try std.testing.expectEqualStrings("gh", long[lines[2].start..lines[2].end]);

    // CJK breaks anywhere, but respects kinsoku (noLineStart '，')
    // "甲乙丙，丁" -> each 10px. max_w = 30: at '，'(30..40), normally would break before '，',
    // but '，' is noLineStart, so last valid break was after '乙' (20px)!
    const zh = "甲乙丙，丁";
    const zh_n = wrap(&font, zh, 30, &lines);
    try std.testing.expectEqual(@as(usize, 2), zh_n);
    try std.testing.expectEqualStrings("甲乙", zh[lines[0].start..lines[0].end]);
    try std.testing.expectEqualStrings("丙，丁", zh[lines[1].start..lines[1].end]);

    // Korean breaks only at spaces, not between Hangul syllables
    const ko = "안녕 하세요"; // 20 + 5 + 30
    const ko_n = wrap(&font, ko, 40, &lines);
    try std.testing.expectEqual(@as(usize, 2), ko_n);
    try std.testing.expectEqualStrings("안녕", ko[lines[0].start..lines[0].end]);
    try std.testing.expectEqualStrings("하세요", ko[lines[1].start..lines[1].end]);

    // 256-line limit
    var many_buf: [600]u8 = undefined;
    for (0..300) |i| {
        many_buf[i * 2] = 'a';
        many_buf[i * 2 + 1] = '\n';
    }
    const many_n = wrap(&font, &many_buf, 100, &lines);
    try std.testing.expectEqual(@as(usize, max_lines), many_n);
}
