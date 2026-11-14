//! 屏幕空间 UI 渲染模块 `kit_ui`（优先级 -55）：
//! 持有单个 Batcher 与有序 run 表，按提交顺序用 drawSubsetWithMaterial 绘制；
//! 支持 CPU 矩形+UV 裁剪、位图字体（WSFN）、整数缩放、硬阴影，并在 headless 下正常计数。
const std = @import("std");
const delve = @import("delve");
const batcher = delve.graphics.batcher;
const colors = delve.colors;
const debug = delve.debug;
const graphics = delve.platform.graphics;
const math = delve.math;
const mem = delve.mem;
const modules = delve.modules;
const papp = delve.platform.app;
const sprites = delve.graphics.sprites;
const assets = delve.api.assets;

const text_mod = @import("text.zig");
const ui_geom = @import("ui_geom.zig");

pub const max_fonts = 8;
pub const max_quads: u32 = 10_000;

const Run = struct {
    tex_id: u32,
    index_start: u32,
    index_end: u32,
};

const FontSlot = struct {
    used: bool = false,
    tex_id: u32 = 0,
    font: text_mod.Font = undefined,
};

pub const ImageSize = struct {
    w: u32,
    h: u32,
};

var allocator: std.mem.Allocator = undefined;
var initialized: bool = false;
var batch: batcher.Batcher = undefined;
var runs: std.ArrayList(Run) = .empty;
var materials: std.AutoHashMap(u32, graphics.Material) = undefined;
var tex_cache: std.StringHashMap(u32) = undefined;
var tex_sizes: std.AutoHashMap(u32, ImageSize) = undefined;
var fonts: [max_fonts]FontSlot = .{FontSlot{}} ** max_fonts;
var missing_warned: std.AutoHashMap(u32, void) = undefined;

var quad_count: u32 = 0;
var warned_quad_limit: bool = false;
var scale: f32 = 1.0;
var text_scale: f32 = 1.0;
var cur_color: [4]f32 = .{ 1, 1, 1, 1 };
var clip_rect: ?ui_geom.Rect = null;
var shadow_enabled: bool = false;
var shadow_dx: f32 = 1.0;
var shadow_dy: f32 = 1.0;
var shadow_rgba: [4]f32 = .{ 0, 0, 0, 0.6 };

pub fn register() !void {
    try modules.registerModule(.{
        .name = "kit_ui",
        .priority = -55,
        .init_fn = onInit,
        .pre_draw_fn = onPreDraw,
        .draw_fn = onDraw,
        .cleanup_fn = onCleanup,
    });
}

fn onInit() !void {
    allocator = mem.getAllocator();
    // UI projection is y-down (top-left origin), but Batcher.addQuad assigns the
    // texture's bottom edge (v_2) to rect.(x,y) assuming y-up. Flip so that
    // v0 maps to the quad's top edge on screen.
    batch = try batcher.Batcher.init(.{ .flip_tex_y = true });
    errdefer batch.deinit();

    materials = std.AutoHashMap(u32, graphics.Material).init(allocator);
    tex_cache = std.StringHashMap(u32).init(allocator);
    tex_sizes = std.AutoHashMap(u32, ImageSize).init(allocator);
    missing_warned = std.AutoHashMap(u32, void).init(allocator);

    // 0 号纹理为纯白 2x2
    const white_mat = try graphics.Material.init(.{
        .texture_0 = graphics.tex_white,
        .cull_mode = .NONE,
        .blend_mode = .BLEND,
        .depth_write_enabled = false,
        .depth_compare = .ALWAYS,
        .samplers = &[_]graphics.FilterMode{.NEAREST},
    });
    try materials.put(0, white_mat);
    try tex_sizes.put(0, .{ .w = 2, .h = 2 });

    initialized = true;
}

fn onCleanup() !void {
    if (!initialized) return;
    initialized = false;

    for (&fonts) |*slot| {
        if (slot.used) {
            slot.font.deinit(allocator);
            slot.used = false;
        }
    }

    var mat_it = materials.valueIterator();
    while (mat_it.next()) |m| m.deinit();
    materials.deinit();

    var key_it = tex_cache.keyIterator();
    while (key_it.next()) |k| {
        allocator.free(k.*.ptr[0 .. k.*.len + 1]);
    }
    tex_cache.deinit();
    tex_sizes.deinit();
    missing_warned.deinit();
    runs.deinit(allocator);
    batch.deinit();
}

fn onPreDraw() void {
    if (!initialized) return;
    batch.reset();
    runs.clearRetainingCapacity();
    quad_count = 0;
    warned_quad_limit = false;
    clip_rect = null;
    cur_color = .{ 1, 1, 1, 1 };
    shadow_enabled = false;
}

fn onDraw() void {
    if (!initialized or runs.items.len == 0) return;

    const vw = @max(@as(f32, @floatFromInt(@max(papp.getWidth(), 1))) / scale, 1.0);
    const vh = @max(@as(f32, @floatFromInt(@max(papp.getHeight(), 1))) / scale, 1.0);
    const view = math.Mat4.lookat(.{ .x = 0.0, .y = 0.0, .z = 5.0 }, math.Vec3.zero, math.Vec3.up);
    const proj = graphics.getProjectionOrthoCustom(0.0, vw, vh, 0.0, 0.001, 10.0);
    const model = math.Mat4.translate(.{ .x = 0.0, .y = 0.0, .z = -2.5 });

    batch.apply();
    for (runs.items) |run| {
        if (materials.getPtr(run.tex_id)) |mat| {
            graphics.drawSubsetWithMaterial(
                &batch.bindings,
                run.index_start,
                // The framework forwards its 3rd arg to sg.draw(base, num_elements, ...): a COUNT, not an end index.
                run.index_end - run.index_start,
                mat,
                .{ .view = view, .proj = proj },
                model,
            );
        }
    }
}

// ------------------------------------------------------------------ 资源加载

pub fn loadImage(path: []const u8) u32 {
    if (!initialized or path.len == 0) return 0;
    if (tex_cache.get(path)) |h| return h;

    const owned = allocator.dupeZ(u8, path) catch return 0;
    const h = assets.get_texture(owned.ptr);
    if (h == 0) {
        allocator.free(owned);
        return 0;
    }

    const tex = assets._getTextureFromHandle(h) orelse {
        allocator.free(owned);
        return 0;
    };

    const mat = graphics.Material.init(.{
        .texture_0 = tex,
        .cull_mode = .NONE,
        .blend_mode = .BLEND,
        .depth_write_enabled = false,
        .depth_compare = .ALWAYS,
        .samplers = &[_]graphics.FilterMode{.NEAREST},
    }) catch {
        allocator.free(owned);
        return 0;
    };

    materials.put(h, mat) catch {
        var m = mat;
        m.deinit();
        allocator.free(owned);
        return 0;
    };
    tex_sizes.put(h, .{ .w = tex.width, .h = tex.height }) catch {};
    tex_cache.put(owned[0..path.len], h) catch {
        allocator.free(owned);
        return h;
    };
    return h;
}

pub fn imageSize(tex_id: u32) ?ImageSize {
    if (!initialized) return null;
    return tex_sizes.get(tex_id);
}

pub fn loadFont(png_path: []const u8, fnt_path: []const u8) u32 {
    if (!initialized) return 0;
    var free_idx: ?usize = null;
    for (&fonts, 0..) |*slot, i| {
        if (!slot.used) {
            free_idx = i;
            break;
        }
    }
    const idx = free_idx orelse {
        debug.err("kit_ui: font limit ({d}) reached", .{max_fonts});
        return 0;
    };

    const tex_id = loadImage(png_path);
    if (tex_id == 0) {
        debug.err("kit_ui: failed to load font png: {s}", .{png_path});
        return 0;
    }

    const bytes = std.Io.Dir.cwd().readFileAlloc(delve.io.getIo(), fnt_path, allocator, .limited(8 << 20)) catch |err| {
        debug.err("kit_ui: failed to read font fnt {s}: {s}", .{ fnt_path, @errorName(err) });
        return 0;
    };
    defer allocator.free(bytes);

    const font = text_mod.Font.parse(allocator, bytes) catch |err| {
        debug.err("kit_ui: failed to parse font {s}: {s}", .{ fnt_path, @errorName(err) });
        return 0;
    };

    fonts[idx] = .{
        .used = true,
        .tex_id = tex_id,
        .font = font,
    };
    return @intCast(idx + 1);
}

pub fn getFont(font_id: u32) ?*const text_mod.Font {
    if (!initialized or font_id == 0 or font_id > max_fonts) return null;
    const slot = &fonts[font_id - 1];
    if (!slot.used) return null;
    return &slot.font;
}

pub fn fontLineHeight(font_id: u32) f32 {
    const f = getFont(font_id) orelse return 0;
    return @as(f32, @floatFromInt(f.line_height)) * text_scale;
}

// ------------------------------------------------------------------ 状态与绘制

pub fn setScale(n: f32) void {
    if (!std.math.isFinite(n) or n < 1.0) {
        scale = 1.0;
    } else {
        scale = @floor(n);
    }
}

pub fn getScale() f32 {
    return scale;
}

pub fn setTextScale(n: f32) void {
    if (std.math.isFinite(n) and n > 0.0) {
        text_scale = n;
    }
}

pub fn getTextScale() f32 {
    return text_scale;
}

pub fn screenSize() [2]f32 {
    const w = @as(f32, @floatFromInt(@max(papp.getWidth(), 1))) / scale;
    const h = @as(f32, @floatFromInt(@max(papp.getHeight(), 1))) / scale;
    return .{ w, h };
}

pub fn setColor(r: f32, g: f32, b: f32, a: f32) void {
    cur_color = .{ r, g, b, a };
}

pub fn setColorHex(rgba: u32) void {
    const r: f32 = @as(f32, @floatFromInt((rgba >> 24) & 0xFF)) / 255.0;
    const g: f32 = @as(f32, @floatFromInt((rgba >> 16) & 0xFF)) / 255.0;
    const b: f32 = @as(f32, @floatFromInt((rgba >> 8) & 0xFF)) / 255.0;
    const a: f32 = @as(f32, @floatFromInt(rgba & 0xFF)) / 255.0;
    cur_color = .{ r, g, b, a };
}

pub fn setTextShadow(dx: f32, dy: f32, r: f32, g: f32, b: f32, a: f32) void {
    shadow_enabled = true;
    shadow_dx = dx;
    shadow_dy = dy;
    shadow_rgba = .{ r, g, b, a };
}

pub fn textShadowOff() void {
    shadow_enabled = false;
}

pub fn setClip(x: f32, y: f32, w: f32, h: f32) void {
    clip_rect = .{ .x = x, .y = y, .w = w, .h = h };
}

pub fn clipOff() void {
    clip_rect = null;
}

pub fn quadCount() u32 {
    return quad_count;
}

pub fn pushQuad(tex_id: u32, q_in: ui_geom.UvQuad, rgba: [4]f32) void {
    if (!initialized) return;
    if (quad_count >= max_quads) {
        if (!warned_quad_limit) {
            warned_quad_limit = true;
            debug.warning("kit_ui: quad limit ({d}) reached", .{max_quads});
        }
        return;
    }

    const q = if (clip_rect) |c| (ui_geom.clip(q_in, c) orelse return) else q_in;
    if (q.dst.w <= 0 or q.dst.h <= 0) return;

    const vtx_save = batch.vertex_pos;
    const idx_save = batch.index_pos;
    const idx_start: u32 = @intCast(batch.index_pos);
    const region = sprites.TextureRegion{
        .u = q.u0,
        .v = q.v0,
        .u_2 = q.u1,
        .v_2 = q.v1,
    };
    const col = colors.Color.new(rgba[0], rgba[1], rgba[2], rgba[3]);
    batch.addRectangle(.{ .x = q.dst.x, .y = q.dst.y, .width = q.dst.w, .height = q.dst.h }, region, col);
    const idx_end: u32 = @intCast(batch.index_pos);

    if (idx_end > idx_start) {
        quad_count += 1;
        if (runs.items.len > 0 and runs.items[runs.items.len - 1].tex_id == tex_id) {
            runs.items[runs.items.len - 1].index_end = idx_end;
        } else {
            runs.append(allocator, .{
                .tex_id = tex_id,
                .index_start = idx_start,
                .index_end = idx_end,
            }) catch {
                batch.vertex_pos = vtx_save;
                batch.index_pos = idx_save;
                quad_count -= 1;
            };
        }
    }
}

pub fn drawRect(x: f32, y: f32, w: f32, h: f32) void {
    pushQuad(0, .{
        .dst = .{ .x = x, .y = y, .w = w, .h = h },
        .u0 = 0,
        .v0 = 0,
        .u1 = 1,
        .v1 = 1,
    }, cur_color);
}

pub fn drawImage(tex_id: u32, sx: f32, sy: f32, sw: f32, sh: f32, dx: f32, dy: f32, dw: f32, dh: f32) void {
    const sz = imageSize(tex_id) orelse return;
    if (sz.w == 0 or sz.h == 0) return;
    const tw: f32 = @floatFromInt(sz.w);
    const th: f32 = @floatFromInt(sz.h);
    pushQuad(tex_id, .{
        .dst = .{ .x = dx, .y = dy, .w = dw, .h = dh },
        .u0 = sx / tw,
        .v0 = sy / th,
        .u1 = (sx + sw) / tw,
        .v1 = (sy + sh) / th,
    }, cur_color);
}

pub fn drawNineSlice(
    tex_id: u32,
    sx: f32,
    sy: f32,
    sw: f32,
    sh: f32,
    l: f32,
    t: f32,
    r: f32,
    b: f32,
    dx: f32,
    dy: f32,
    dw: f32,
    dh: f32,
) void {
    const sz = imageSize(tex_id) orelse return;
    if (sz.w == 0 or sz.h == 0) return;
    const tw: f32 = @floatFromInt(sz.w);
    const th: f32 = @floatFromInt(sz.h);

    var slices: [9]ui_geom.NineSlice = undefined;
    const n = ui_geom.nineSlice(
        .{ .x = sx, .y = sy, .w = sw, .h = sh },
        l,
        t,
        r,
        b,
        .{ .x = dx, .y = dy, .w = dw, .h = dh },
        &slices,
    );
    for (slices[0..n]) |sl| {
        pushQuad(tex_id, .{
            .dst = sl.dst,
            .u0 = sl.src.x / tw,
            .v0 = sl.src.y / th,
            .u1 = (sl.src.x + sl.src.w) / tw,
            .v1 = (sl.src.y + sl.src.h) / th,
        }, cur_color);
    }
}

fn emitTextSpan(slot: *const FontSlot, s: []const u8, x: f32, y: f32, rgba: [4]f32, max_glyphs: i32) void {
    const f = &slot.font;
    const aw: f32 = @floatFromInt(f.atlas_w);
    const ah: f32 = @floatFromInt(f.atlas_h);
    const ts = text_scale;

    var pen_x = x;
    const base_y = y;
    var iter = text_mod.Utf8Iter{ .bytes = s };
    var count: i32 = 0;

    while (iter.next()) |cp| {
        if (max_glyphs >= 0 and count >= max_glyphs) break;
        if (cp == '\r' or cp == '\n') continue;
        count += 1;

        if (!f.has(cp)) {
            if (!missing_warned.contains(cp)) {
                missing_warned.put(cp, {}) catch {};
                debug.warning("kit_ui: missing glyph U+{X:0>4} in font", .{cp});
            }
        }

        const g = f.glyph(cp) orelse continue;
        if (g.w > 0 and g.h > 0) {
            const gx = @floor(pen_x + @as(f32, @floatFromInt(g.xoff)) * ts);
            const gy = @floor(base_y + @as(f32, @floatFromInt(g.yoff)) * ts);
            const gw = @as(f32, @floatFromInt(g.w)) * ts;
            const gh = @as(f32, @floatFromInt(g.h)) * ts;
            const gu0 = @as(f32, @floatFromInt(g.x)) / aw;
            const gv0 = @as(f32, @floatFromInt(g.y)) / ah;
            const gu1 = @as(f32, @floatFromInt(g.x + g.w)) / aw;
            const gv1 = @as(f32, @floatFromInt(g.y + g.h)) / ah;
            pushQuad(slot.tex_id, .{
                .dst = .{ .x = gx, .y = gy, .w = gw, .h = gh },
                .u0 = gu0,
                .v0 = gv0,
                .u1 = gu1,
                .v1 = gv1,
            }, rgba);
        }
        pen_x += @as(f32, @floatFromInt(g.advance)) * ts;
    }
}

pub fn drawText(font_id: u32, s: []const u8, x: f32, y: f32, max_glyphs: i32) void {
    if (!initialized or font_id == 0 or font_id > max_fonts) return;
    const slot = &fonts[font_id - 1];
    if (!slot.used) return;

    if (shadow_enabled) {
        const s_col = [4]f32{ shadow_rgba[0], shadow_rgba[1], shadow_rgba[2], shadow_rgba[3] * cur_color[3] };
        emitTextSpan(slot, s, x + shadow_dx, y + shadow_dy, s_col, max_glyphs);
    }
    emitTextSpan(slot, s, x, y, cur_color, max_glyphs);
}

pub fn drawTextBox(font_id: u32, s: []const u8, x: f32, y: f32, w: f32, alignment: u8, max_glyphs: i32) f32 {
    if (!initialized or font_id == 0 or font_id > max_fonts) return 0;
    const slot = &fonts[font_id - 1];
    if (!slot.used) return 0;

    const ts = text_scale;
    const scaled_max_w: u32 = if (w > 0) @intFromFloat(@max(1.0, w / ts)) else 0;

    var lines: [text_mod.max_lines]text_mod.Line = undefined;
    const n = text_mod.wrap(&slot.font, s, scaled_max_w, &lines);
    const lh = @as(f32, @floatFromInt(slot.font.line_height)) * ts;

    var remaining = max_glyphs;
    for (lines[0..n], 0..) |ln, i| {
        if (max_glyphs >= 0 and remaining <= 0) break;
        const slice = s[ln.start..ln.end];
        const line_w = @as(f32, @floatFromInt(ln.width)) * ts;
        const lx = switch (alignment) {
            1 => x + @floor((w - line_w) * 0.5),
            2 => x + @floor(w - line_w),
            else => x,
        };
        const ly = y + @as(f32, @floatFromInt(i)) * lh;

        if (shadow_enabled) {
            const s_col = [4]f32{ shadow_rgba[0], shadow_rgba[1], shadow_rgba[2], shadow_rgba[3] * cur_color[3] };
            emitTextSpan(slot, slice, lx + shadow_dx, ly + shadow_dy, s_col, remaining);
        }
        emitTextSpan(slot, slice, lx, ly, cur_color, remaining);

        if (max_glyphs >= 0) {
            var it = text_mod.Utf8Iter{ .bytes = slice };
            while (it.next()) |_| {
                remaining -= 1;
                if (remaining <= 0) break;
            }
        }
    }

    return @as(f32, @floatFromInt(n)) * lh;
}
