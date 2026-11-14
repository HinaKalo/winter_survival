//! Lua 库 `ui`：屏幕空间绘制、字体、图片、九宫格、裁剪与文本测量。
const std = @import("std");
const delve = @import("delve");
const binder = delve.scripting.binder;
const input = delve.platform.input;
const lua_util = delve.scripting.lua;
const zlua = @import("zlua");

const text_mod = @import("text.zig");
const ui = @import("ui.zig");

const Reg = binder.Registry(.{ .entries = &[_]binder.BoundType{} });
const ignore_fns = [_][:0]const u8{"bind"};

pub fn bind(lua: *lua_util.Lua) void {
    const fns = comptime Reg.findLibraryFunctions(@This(), &ignore_fns);
    Reg.bindLibrary(lua, "ui", fns);

    // 补充多返回值 / 返回表的函数到 `ui` 表
    _ = lua.getGlobal("ui") catch return;
    setFn(lua, "image_size", zlua.wrap(l_imageSize));
    setFn(lua, "screen_size", zlua.wrap(l_screenSize));
    setFn(lua, "mouse_pos", zlua.wrap(l_mousePos));
    setFn(lua, "text_measure", zlua.wrap(l_textMeasure));
    setFn(lua, "text_wrap", zlua.wrap(l_textWrap));
    lua.pop(1);
}

fn setFn(lua: *lua_util.Lua, name: [:0]const u8, func: zlua.CFn) void {
    lua.pushFunction(func);
    lua.setField(-2, name);
}

fn finiteOr(v: f32, fallback: f32) f32 {
    return if (std.math.isFinite(v)) v else fallback;
}

pub fn font_load(png: [*:0]const u8, fnt: [*:0]const u8) u32 {
    return ui.loadFont(std.mem.span(png), std.mem.span(fnt));
}

pub fn font_line_height(font: i64) f32 {
    if (font <= 0) return 0;
    return ui.fontLineHeight(@intCast(font));
}

pub fn image_load(path: [*:0]const u8) u32 {
    return ui.loadImage(std.mem.span(path));
}

pub fn color(r: f32, g: f32, b: f32, a: f32) void {
    ui.setColor(finiteOr(r, 1), finiteOr(g, 1), finiteOr(b, 1), finiteOr(a, 1));
}

pub fn color_hex(rgba: i64) void {
    const u: u32 = @truncate(@as(u64, @bitCast(rgba)));
    ui.setColorHex(u);
}

pub fn set_scale(n: f32) void {
    ui.setScale(n);
}

pub fn set_text_scale(n: f32) void {
    ui.setTextScale(n);
}

pub fn text_shadow(dx: f32, dy: f32, r: f32, g: f32, b: f32, a: f32) void {
    ui.setTextShadow(finiteOr(dx, 1), finiteOr(dy, 1), finiteOr(r, 0), finiteOr(g, 0), finiteOr(b, 0), finiteOr(a, 0.6));
}

pub fn text_shadow_off() void {
    ui.textShadowOff();
}

pub fn text(font: i64, str: [*:0]const u8, x: f32, y: f32) void {
    if (font <= 0) return;
    ui.drawText(@intCast(font), std.mem.span(str), finiteOr(x, 0), finiteOr(y, 0), -1);
}

pub fn text_width(font: i64, str: [*:0]const u8) f32 {
    if (font <= 0) return 0;
    const f = ui.getFont(@intCast(font)) orelse return 0;
    return @as(f32, @floatFromInt(text_mod.measure(f, std.mem.span(str)))) * ui.getTextScale();
}

pub fn text_box(font: i64, str: [*:0]const u8, x: f32, y: f32, w: f32, alignment: i64, max_glyphs: i64) f32 {
    if (font <= 0) return 0;
    const a: u8 = if (alignment >= 0 and alignment <= 2) @intCast(alignment) else 0;
    const mg: i32 = if (max_glyphs < 0) -1 else @intCast(@min(max_glyphs, std.math.maxInt(i32)));
    return ui.drawTextBox(@intCast(font), std.mem.span(str), finiteOr(x, 0), finiteOr(y, 0), finiteOr(w, 0), a, mg);
}

pub fn rect(x: f32, y: f32, w: f32, h: f32) void {
    ui.drawRect(finiteOr(x, 0), finiteOr(y, 0), finiteOr(w, 0), finiteOr(h, 0));
}

pub fn image(tex: i64, sx: f32, sy: f32, sw: f32, sh: f32, dx: f32, dy: f32, dw: f32, dh: f32) void {
    if (tex < 0) return;
    ui.drawImage(
        @intCast(tex),
        finiteOr(sx, 0),
        finiteOr(sy, 0),
        finiteOr(sw, 0),
        finiteOr(sh, 0),
        finiteOr(dx, 0),
        finiteOr(dy, 0),
        finiteOr(dw, 0),
        finiteOr(dh, 0),
    );
}

pub fn nine_slice(tex: i64, sx: f32, sy: f32, sw: f32, sh: f32, l: f32, t: f32, r: f32, b: f32, dx: f32, dy: f32, dw: f32, dh: f32) void {
    if (tex < 0) return;
    ui.drawNineSlice(
        @intCast(tex),
        finiteOr(sx, 0),
        finiteOr(sy, 0),
        finiteOr(sw, 0),
        finiteOr(sh, 0),
        finiteOr(l, 0),
        finiteOr(t, 0),
        finiteOr(r, 0),
        finiteOr(b, 0),
        finiteOr(dx, 0),
        finiteOr(dy, 0),
        finiteOr(dw, 0),
        finiteOr(dh, 0),
    );
}

pub fn clip(x: f32, y: f32, w: f32, h: f32) void {
    ui.setClip(finiteOr(x, 0), finiteOr(y, 0), finiteOr(w, 0), finiteOr(h, 0));
}

pub fn clip_off() void {
    ui.clipOff();
}

pub fn quad_count() u32 {
    return ui.quadCount();
}

// ------------------------------------------------------------------ 表 / 多返回值函数

fn l_imageSize(lua: *zlua.Lua) i32 {
    const tex = lua.optInteger(1) orelse 0;
    if (tex < 0) {
        lua.pushNil();
        return 1;
    }
    const sz = ui.imageSize(@intCast(tex)) orelse {
        lua.pushNil();
        return 1;
    };
    lua.createTable(0, 2);
    lua.pushInteger(@intCast(sz.w));
    lua.setField(-2, "w");
    lua.pushInteger(@intCast(sz.h));
    lua.setField(-2, "h");
    return 1;
}

fn l_screenSize(lua: *zlua.Lua) i32 {
    const sz = ui.screenSize();
    lua.pushNumber(sz[0]);
    lua.pushNumber(sz[1]);
    return 2;
}

fn l_mousePos(lua: *zlua.Lua) i32 {
    const mp = input.getMousePosition();
    const sc = ui.getScale();
    lua.pushNumber(mp.x / sc);
    lua.pushNumber(mp.y / sc);
    return 2;
}

fn l_textMeasure(lua: *zlua.Lua) i32 {
    const font_id = lua.optInteger(1) orelse 0;
    const str = lua.toString(2) catch "";
    const w_f = finiteOr(@floatCast(lua.optNumber(3) orelse 0), 0);

    if (font_id <= 0) {
        lua.createTable(0, 3);
        lua.pushNumber(0);
        lua.setField(-2, "w");
        lua.pushNumber(0);
        lua.setField(-2, "h");
        lua.pushInteger(0);
        lua.setField(-2, "lines");
        return 1;
    }

    const f = ui.getFont(@intCast(font_id)) orelse {
        lua.createTable(0, 3);
        lua.pushNumber(0);
        lua.setField(-2, "w");
        lua.pushNumber(0);
        lua.setField(-2, "h");
        lua.pushInteger(0);
        lua.setField(-2, "lines");
        return 1;
    };

    const ts = ui.getTextScale();
    const max_w: u32 = if (w_f > 0) @intFromFloat(@max(1.0, w_f / ts)) else 0;
    var lines: [text_mod.max_lines]text_mod.Line = undefined;
    const n = text_mod.wrap(f, str, max_w, &lines);

    var max_line_w: u32 = 0;
    for (lines[0..n]) |ln| {
        if (ln.width > max_line_w) max_line_w = ln.width;
    }

    const total_w = @as(f32, @floatFromInt(max_line_w)) * ts;
    const total_h = @as(f32, @floatFromInt(n)) * @as(f32, @floatFromInt(f.line_height)) * ts;

    lua.createTable(0, 3);
    lua.pushNumber(total_w);
    lua.setField(-2, "w");
    lua.pushNumber(total_h);
    lua.setField(-2, "h");
    lua.pushInteger(@intCast(n));
    lua.setField(-2, "lines");
    return 1;
}

fn l_textWrap(lua: *zlua.Lua) i32 {
    const font_id = lua.optInteger(1) orelse 0;
    const str = lua.toString(2) catch "";
    const w_f = finiteOr(@floatCast(lua.optNumber(3) orelse 0), 0);

    lua.createTable(0, 0);
    if (font_id <= 0) return 1;
    const f = ui.getFont(@intCast(font_id)) orelse return 1;

    const ts = ui.getTextScale();
    const max_w: u32 = if (w_f > 0) @intFromFloat(@max(1.0, w_f / ts)) else 0;
    var lines: [text_mod.max_lines]text_mod.Line = undefined;
    const n = text_mod.wrap(f, str, max_w, &lines);

    for (lines[0..n], 0..) |ln, i| {
        lua.createTable(0, 3);
        lua.pushInteger(@intCast(ln.start + 1)); // Lua 1-based inclusive start
        lua.setField(-2, "start");
        lua.pushInteger(@intCast(ln.end)); // Lua 1-based inclusive end
        lua.setField(-2, "end");
        lua.pushNumber(@as(f32, @floatFromInt(ln.width)) * ts);
        lua.setField(-2, "width");
        lua.rawSetIndex(-2, @intCast(i + 1));
    }
    return 1;
}
