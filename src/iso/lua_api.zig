//! Lua 模块 `iso`：把引擎能力暴露给 Lua（`local iso = require("iso")`）。
//!
//! 注意：binder 会把本文件里所有 `pub fn` 自动绑定为 Lua 函数（Lua 名 = Zig 名），
//! 因此内部辅助函数一律不要加 pub。参数个数必须与 Lua 调用完全一致。
//! 返回元组/数组 -> Lua 数组表；返回可选 -> 无结果时为 nil。
const std = @import("std");
const delve = @import("delve");
const math = delve.math;
const colors = delve.colors;
const graphics = delve.platform.graphics;
const input = delve.platform.input;
const papp = delve.platform.app;
const binder = delve.scripting.binder;
const lua_util = delve.scripting.lua;
const mem = delve.mem;

const engine = @import("engine.zig");
const render = @import("render.zig");
const world_mod = @import("world.zig");
const coords = @import("coords.zig");

const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Entity = world_mod.Entity;
const GridPos = coords.GridPos;

const Reg = binder.Registry(.{ .entries = &[_]binder.BoundType{} });
const ignore_fns = [_][:0]const u8{"bind"};

/// 绑定 `iso` 库与全局 `keys` 表；由 script_host 在 Lua 启动后调用。
pub fn bind(lua: *lua_util.Lua) void {
    const fns = comptime Reg.findLibraryFunctions(@This(), &ignore_fns);
    Reg.bindLibrary(lua, "iso", fns);

    // keys.W / keys.ESCAPE / keys.F5 ...（名称与 Delve 的 KeyCodes 枚举一致）
    lua.createTable(0, 128);
    inline for (@typeInfo(input.KeyCodes).@"enum".fields) |f| {
        lua.pushInteger(f.value);
        lua.setField(-2, f.name);
    }
    lua.setGlobal("keys");
}

// ------------------------------------------------------------------ 内部辅助（非 pub）

fn ent(id: i64) ?*Entity {
    return engine.world.get(idOf(id) orelse return null);
}

fn idOf(v: i64) ?u32 {
    return std.math.cast(u32, v);
}

fn i32Of(v: i64) i32 {
    return @intCast(std.math.clamp(v, std.math.minInt(i32), std.math.maxInt(i32)));
}

fn clampU16(v: i64) u16 {
    return @intCast(std.math.clamp(v, 0, std.math.maxInt(u16)));
}

fn clampU8(v: i64) u8 {
    return @intCast(std.math.clamp(v, 0, 255));
}

fn fin(v: f32) bool {
    // 同时限制量级：下游 floor->i32 转换在极大值时会越界
    return std.math.isFinite(v) and @abs(v) <= 1.0e7;
}

fn fin3(a: f32, b: f32, c: f32) bool {
    return fin(a) and fin(b) and fin(c);
}

fn fin4(a: f32, b: f32, c: f32, d: f32) bool {
    return fin(a) and fin(b) and fin(c) and fin(d);
}

fn colorOf(r: f32, g: f32, b: f32, a: f32) colors.Color {
    return colors.Color.new(r, g, b, a);
}

/// path_find 的静态结果缓冲
var path_buf: [1024][2]i32 = undefined;

// ------------------------------------------------------------------ 地图

pub fn map_create(w: i64, h: i64) void {
    const ww = std.math.clamp(w, 1, 1024);
    const hh = std.math.clamp(h, 1, 1024);
    engine.map.resize(@intCast(ww), @intCast(hh)) catch {};
}

pub fn map_size() [2]i32 {
    return .{ @intCast(engine.map.width), @intCast(engine.map.height) };
}

pub fn tileset_load(path: [*:0]const u8, cols: i64, rows: i64) bool {
    if (cols <= 0 or rows <= 0 or cols > 4096 or rows > 4096) return false;
    const h = engine.renderer.loadTexture(std.mem.span(path));
    if (h == 0) return false;
    const img = delve.api.assets._getImageFromHandle(h) orelse return false;
    engine.renderer.setTileAtlas(.{
        .texture_handle = h,
        .cols = @intCast(cols),
        .rows = @intCast(rows),
        .tex_w = img.width,
        .tex_h = img.height,
    }) catch return false;
    engine.map.dirty = true;
    return true;
}

pub fn tile_define(top: i64, side: i64, solid: bool, liquid: bool) i64 {
    const kind = engine.map.defineTile(.{
        .top = clampU16(top),
        .side = clampU16(side),
        .solid = solid,
        .liquid = liquid,
    }) catch return 0;
    return kind;
}

pub fn map_set(x: i64, y: i64, kind: i64, height: i64) void {
    if (kind < 0 or kind > std.math.maxInt(u16)) return;
    engine.map.set(i32Of(x), i32Of(y), clampU16(kind), clampU8(height));
}

pub fn map_get(x: i64, y: i64) ?[2]i32 {
    const t = engine.map.get(i32Of(x), i32Of(y)) orelse return null;
    return .{ t.kind, t.height };
}

pub fn map_fill(kind: i64, height: i64) void {
    if (kind < 0 or kind > std.math.maxInt(u16)) return;
    engine.map.fill(clampU16(kind), clampU8(height));
}

pub fn map_top_y(x: i64, y: i64) f32 {
    return engine.map.topY(i32Of(x), i32Of(y));
}

pub fn map_walkable(x: i64, y: i64) bool {
    return engine.map.isWalkable(i32Of(x), i32Of(y));
}

pub fn map_can_step(fx: i64, fy: i64, tx: i64, ty: i64) bool {
    return engine.map.canStep(i32Of(fx), i32Of(fy), i32Of(tx), i32Of(ty));
}

pub fn path_find(x0: i64, y0: i64, x1: i64, y1: i64) ?[]const [2]i32 {
    const allocator = mem.getAllocator();
    var out: std.ArrayList(GridPos) = .empty;
    defer out.deinit(allocator);
    const found = engine.map.findPath(allocator, .{ .x = i32Of(x0), .y = i32Of(y0) }, .{ .x = i32Of(x1), .y = i32Of(y1) }, &out) catch return null;
    if (!found) return null;
    const n = @min(out.items.len, path_buf.len);
    for (out.items[0..n], 0..) |p, i| path_buf[i] = .{ p.x, p.y };
    return path_buf[0..n];
}

// ------------------------------------------------------------------ 相机

pub fn camera_set_target(x: f32, y: f32, z: f32) void {
    if (!fin3(x, y, z)) return;
    engine.camera.target = Vec3.new(x, y, z);
}

pub fn camera_get_target() [3]f32 {
    const t = engine.camera.target;
    return .{ t.x, t.y, t.z };
}

pub fn camera_follow(id: i64) void {
    if (id == 0) {
        engine.follow_entity = 0;
        engine.camera.follow_goal = null;
        return;
    }
    const u = idOf(id) orelse return;
    engine.follow_entity = u;
}

pub fn camera_rotate(steps: i64) void {
    engine.camera.rotateStep(@intCast(std.math.clamp(steps, -1000, 1000)));
}

pub fn camera_set_angles(yaw: f32, pitch: f32) void {
    if (!fin(yaw) or !fin(pitch)) return;
    engine.camera.yaw = yaw;
    engine.camera.yaw_goal = yaw;
    engine.camera.pitch = std.math.clamp(pitch, 5.0, 85.0);
}

pub fn camera_get_yaw() f32 {
    return engine.camera.yaw;
}

pub fn camera_set_zoom(z: f32) void {
    if (!fin(z)) return;
    engine.camera.setZoom(z);
}

pub fn camera_get_zoom() f32 {
    return engine.camera.zoom;
}

pub fn camera_set_view_height(h: f32) void {
    if (fin(h) and h > 0.1 and h < 1.0e5) engine.camera.view_height = h;
}

// ------------------------------------------------------------------ 拾取 / 投影

pub fn screen_to_tile(sx: f32, sy: f32) ?[2]i32 {
    if (!fin(sx) or !fin(sy)) return null;
    const cam = &engine.camera;
    const ray = cam.screenToRay(sx, sy);
    const hit = engine.map.raycastPick(ray, cam.far) orelse return null;
    return .{ hit.x, hit.y };
}

pub fn mouse_tile() ?[2]i32 {
    const p = input.getMousePosition();
    return screen_to_tile(p.x, p.y);
}

pub fn world_to_screen(x: f32, y: f32, z: f32) ?[2]f32 {
    if (!fin3(x, y, z)) return null;
    const s = engine.camera.worldToScreen(Vec3.new(x, y, z));
    return .{ s.x, s.y };
}

// ------------------------------------------------------------------ 精灵表 / 实体

pub fn sheet_load(path: [*:0]const u8, frame_w: i64, frame_h: i64) i64 {
    if (frame_w <= 0 or frame_h <= 0 or frame_w > 65536 or frame_h > 65536) return 0;
    const h = engine.renderer.loadTexture(std.mem.span(path));
    if (h == 0) return 0;
    const img = delve.api.assets._getImageFromHandle(h) orelse return 0;
    const fw: u32 = @intCast(frame_w);
    const fh: u32 = @intCast(frame_h);
    return engine.renderer.addSheet(.{
        .texture_handle = h,
        .frame_w = fw,
        .frame_h = fh,
        .cols = @max(img.width / fw, 1),
        .rows = @max(img.height / fh, 1),
        .tex_w = img.width,
        .tex_h = img.height,
    }) catch 0;
}

/// x、z 为世界坐标（格子中心 = 格坐标 + 0.5）；脚底 y 贴合地图高度。
pub fn entity_spawn(sheet: i64, x: f32, z: f32, w: f32, h: f32) i64 {
    if (!fin4(x, z, w, h)) return 0;
    const sh = idOf(sheet) orelse return 0;
    const y = if (engine.map.worldToTile(Vec3.new(x, 0, z))) |g| engine.map.topY(g.x, g.y) else 0;
    return engine.world.spawn(.{
        .pos = Vec3.new(x, y, z),
        .size = Vec2.new(w, h),
        .sheet = sh,
    }) catch 0;
}

pub fn entity_despawn(id: i64) void {
    const u = idOf(id) orelse return;
    if (engine.follow_entity == u) engine.follow_entity = 0;
    engine.world.despawn(u);
}

pub fn entity_exists(id: i64) bool {
    return ent(id) != null;
}

pub fn entity_set_pos(id: i64, x: f32, y: f32, z: f32) void {
    if (!fin3(x, y, z)) return;
    const e = ent(id) orelse return;
    e.pos = Vec3.new(x, y, z);
    e.path_len = 0;
    e.path_idx = 0;
    e.move_goal = null;
}

pub fn entity_get_pos(id: i64) ?[3]f32 {
    const e = ent(id) orelse return null;
    return .{ e.pos.x, e.pos.y, e.pos.z };
}

pub fn entity_get_tile(id: i64) ?[2]i32 {
    const e = ent(id) orelse return null;
    const g = engine.map.worldToTile(e.pos) orelse return null;
    return .{ g.x, g.y };
}

pub fn entity_move_to(id: i64, x: f32, z: f32) void {
    if (!fin(x) or !fin(z)) return;
    const u = idOf(id) orelse return;
    engine.world.moveTo(u, Vec3.new(x, 0, z));
}

/// 寻路到目标格并开始沿路径走；无路返回 false。
/// 路径最长 64 格（超出截断，Lua 侧可在到达后再次调用继续）。
pub fn entity_path_to(id: i64, tx: i64, ty: i64) bool {
    const u = idOf(id) orelse return false;
    const e = ent(id) orelse return false;
    const from = engine.map.worldToTile(e.pos) orelse return false;
    const allocator = mem.getAllocator();
    var out: std.ArrayList(GridPos) = .empty;
    defer out.deinit(allocator);
    const found = engine.map.findPath(allocator, from, .{ .x = i32Of(tx), .y = i32Of(ty) }, &out) catch return false;
    if (!found) return false;
    engine.world.setPath(u, out.items);
    return true;
}

pub fn entity_is_moving(id: i64) bool {
    const u = idOf(id) orelse return false;
    return engine.world.isMoving(u);
}

pub fn entity_stop(id: i64) void {
    const e = ent(id) orelse return;
    e.path_len = 0;
    e.path_idx = 0;
    e.move_goal = null;
}

pub fn entity_set_speed(id: i64, s: f32) void {
    if (!fin(s)) return;
    const e = ent(id) orelse return;
    e.speed = s;
}

/// 播放帧动画 [start, start+count)。参数不变时重复调用不会重置动画。
pub fn entity_play(id: i64, start: i64, count: i64, rate: f32, loop: bool) void {
    if (!fin(rate)) return;
    if (start < 0 or count < 0 or start > std.math.maxInt(u16) or count > std.math.maxInt(u16)) return;
    const e = ent(id) orelse return;
    const s = clampU16(start);
    const c = clampU16(count);
    if (e.anim_start == s and e.anim_len == c and e.anim_fps == rate and e.anim_loop == loop) return;
    e.anim_start = s;
    e.anim_len = c;
    e.anim_fps = rate;
    e.anim_loop = loop;
    e.anim_time = 0;
    e.frame = s;
}

/// 设置固定帧（同时停止动画）
pub fn entity_set_frame(id: i64, f: i64) void {
    const e = ent(id) orelse return;
    e.anim_len = 0;
    e.anim_fps = 0;
    e.frame = clampU16(f);
}

pub fn entity_set_flip(id: i64, b: bool) void {
    const e = ent(id) orelse return;
    e.flip_x = b;
}

pub fn entity_set_tint(id: i64, r: f32, g: f32, b: f32, a: f32) void {
    if (!fin4(r, g, b, a)) return;
    const e = ent(id) orelse return;
    e.tint = colorOf(r, g, b, a);
}

/// 0..3 = down, left, right, up；实体不存在返回 0
pub fn entity_facing(id: i64) i64 {
    const e = ent(id) orelse return 0;
    return @intFromEnum(e.facing);
}

pub fn entity_last_move(id: i64) [2]f32 {
    const e = ent(id) orelse return .{ 0, 0 };
    return .{ e.last_move.x, e.last_move.y };
}

// ------------------------------------------------------------------ 高亮

pub fn highlight_tile(x: i64, y: i64, r: f32, g: f32, b: f32, a: f32) void {
    if (!fin4(r, g, b, a)) return;
    engine.renderer.setHighlight(.{ .x = i32Of(x), .y = i32Of(y) }, colorOf(r, g, b, a));
}

pub fn highlight_clear() void {
    engine.renderer.setHighlight(null, colors.white);
}

// ------------------------------------------------------------------ 输入

pub fn key_down(code: i64) bool {
    const c = std.math.cast(i32, code) orelse return false;
    const k = std.enums.fromInt(input.KeyCodes, c) orelse return false;
    return input.isKeyPressed(k);
}

pub fn key_pressed(code: i64) bool {
    const c = std.math.cast(i32, code) orelse return false;
    const k = std.enums.fromInt(input.KeyCodes, c) orelse return false;
    return input.isKeyJustPressed(k);
}

pub fn mouse_pressed(btn: i64) bool {
    const c = std.math.cast(i32, btn) orelse return false;
    const b = std.enums.fromInt(input.MouseButtons, c) orelse return false;
    return input.isMouseButtonJustPressed(b);
}

pub fn mouse_down(btn: i64) bool {
    const c = std.math.cast(i32, btn) orelse return false;
    const b = std.enums.fromInt(input.MouseButtons, c) orelse return false;
    return input.isMouseButtonPressed(b);
}

pub fn mouse_pos() [2]f32 {
    const p = input.getMousePosition();
    return .{ p.x, p.y };
}

// ------------------------------------------------------------------ 其它

pub fn set_clear_color(r: f32, g: f32, b: f32) void {
    if (!fin3(r, g, b)) return;
    graphics.setClearColor(colors.Color.new(r, g, b, 1.0));
}

// ---- 以下为 PLAN 之外的少量扩展 ----

/// 退出游戏
pub fn quit() void {
    papp.exit();
}

/// 当前帧率（Delve 统计）
pub fn fps() i32 {
    return papp.getFPS();
}

/// 窗口尺寸 {w, h}（像素）
pub fn window_size() [2]i32 {
    return .{ papp.getWidth(), papp.getHeight() };
}
