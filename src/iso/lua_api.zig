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
const tilemap = @import("tilemap.zig");
const vision = @import("vision.zig");
const world_mod = @import("world.zig");
const coords = @import("coords.zig");
const overlay_mod = @import("overlay.zig");
const model_mod = @import("model.zig");

const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Entity = world_mod.Entity;
const GridPos = coords.GridPos;

const Reg = binder.Registry(.{ .entries = &[_]binder.BoundType{} });
const ignore_fns = [_][:0]const u8{"bind"};

/// 绑定 `iso` 库与全局 `keys` 表；由 script_host 在 Lua 启动后调用。
pub fn bind(lua: *lua_util.Lua) void {
    @setEvalBranchQuota(5000);
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
    const ww: u32 = @intCast(std.math.clamp(w, 1, 128));
    const hh: u32 = @intCast(std.math.clamp(h, 1, 128));
    engine.resetMapSize(ww, hh) catch {};
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
    return tile_define_ex(top, side, -1, solid, liquid, solid, 0);
}

pub fn tile_define_ex(top: i64, side: i64, side_cap: i64, solid: bool, liquid: bool, opaque_flag: bool, tag: i64) i64 {
    return tile_define_ex2(top, side, side_cap, -1, solid, liquid, opaque_flag, tag);
}

/// 同 tile_define_ex，另带 `side_base`（最下一段侧面的图集格；< 0 = 同 side）。
pub fn tile_define_ex2(top: i64, side: i64, side_cap: i64, side_base: i64, solid: bool, liquid: bool, opaque_flag: bool, tag: i64) i64 {
    const cap: u16 = if (side_cap < 0) 0xFFFF else clampU16(side_cap);
    const base: u16 = if (side_base < 0) 0xFFFF else clampU16(side_base);
    const kind = engine.map.defineTile(.{
        .top = clampU16(top),
        .side = clampU16(side),
        .side_cap = cap,
        .side_base = base,
        .solid = solid,
        .liquid = liquid,
        .@"opaque" = opaque_flag,
        .tag = clampU8(tag),
    }) catch return 0;
    return kind;
}

pub fn map_set_height_unit(u: f32) void {
    if (!fin(u) or u <= 0) return;
    engine.map.height_unit = u;
    engine.map.markAllDirty();
}

pub fn map_set_base_depth(d: f32) void {
    if (!fin(d) or d < 0) return;
    engine.map.base_depth = d;
    engine.map.markAllDirty();
}

pub fn tile_set_blocked(x: i64, y: i64, b: bool) void {
    engine.map.setFlag(i32Of(x), i32Of(y), tilemap.Flag.blocked, b);
}

pub fn tile_set_opaque(x: i64, y: i64, b: bool) void {
    engine.map.setFlag(i32Of(x), i32Of(y), tilemap.Flag.@"opaque", b);
}

pub fn tile_set_tag(x: i64, y: i64, v: i64) void {
    engine.map.setTag(i32Of(x), i32Of(y), clampU8(v));
}

pub fn tile_flags(x: i64, y: i64) ?[3]i32 {
    const gx = i32Of(x);
    const gy = i32Of(y);
    if (!engine.map.inBounds(gx, gy)) return null;
    const f = engine.map.getFlags(gx, gy);
    return .{
        if ((f & tilemap.Flag.blocked) != 0) 1 else 0,
        if (engine.map.isOpaque(gx, gy)) 1 else 0,
        engine.map.getTag(gx, gy),
    };
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

fn findPathCommon(x0: i64, y0: i64, x1: i64, y1: i64, goal_adjacent: bool) ?[]const [2]i32 {
    const allocator = mem.getAllocator();
    var out: std.ArrayList(GridPos) = .empty;
    defer out.deinit(allocator);
    const found = engine.pathfinder.find(&engine.map, .{ .x = i32Of(x0), .y = i32Of(y0) }, .{ .x = i32Of(x1), .y = i32Of(y1) }, goal_adjacent, &out) catch return null;
    if (!found) return null;
    const n = @min(out.items.len, path_buf.len);
    for (out.items[0..n], 0..) |p, i| path_buf[i] = .{ p.x, p.y };
    return path_buf[0..n];
}

pub fn path_find(x0: i64, y0: i64, x1: i64, y1: i64) ?[]const [2]i32 {
    return findPathCommon(x0, y0, x1, y1, false);
}

pub fn path_find_adjacent(x0: i64, y0: i64, x1: i64, y1: i64) ?[]const [2]i32 {
    return findPathCommon(x0, y0, x1, y1, true);
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

/// 恒为 45（D6：相机朝向锁定，无旋转接口）。
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
    const found = engine.pathfinder.find(&engine.map, from, .{ .x = i32Of(tx), .y = i32Of(ty) }, false, &out) catch return false;
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

pub fn entity_set_visible(id: i64, b: bool) void {
    const e = ent(id) orelse return;
    e.visible = b;
}

pub fn entity_set_lit(id: i64, b: bool) void {
    const e = ent(id) orelse return;
    e.lit = b;
}

pub fn entity_set_pickable(id: i64, b: bool) void {
    const e = ent(id) orelse return;
    e.pickable = b;
}

pub fn entity_set_ghost(id: i64, b: bool) void {
    const e = ent(id) orelse return;
    e.ghost = b;
}

pub fn entity_get_ghost(id: i64) bool {
    const e = ent(id) orelse return false;
    return e.ghost;
}

pub fn entity_set_size(id: i64, w: f32, h: f32) void {
    if (!fin(w) or !fin(h) or w <= 0 or h <= 0) return;
    const e = ent(id) orelse return;
    e.size = Vec2.new(w, h);
}

pub fn entity_set_size_px(id: i64, wpx: f32, hpx: f32) void {
    if (!fin(wpx) or !fin(hpx) or wpx <= 0 or hpx <= 0) return;
    const e = ent(id) orelse return;
    const ppu = engine.camera.effectivePpu();
    if (ppu <= 0) return;
    e.size = Vec2.new(wpx / ppu, hpx / ppu);
}

pub fn entity_get_size(id: i64) ?[2]f32 {
    const e = ent(id) orelse return null;
    return .{ e.size.x, e.size.y };
}

pub fn entity_set_sheet(id: i64, sheet: i64) void {
    const e = ent(id) orelse return;
    const s = idOf(sheet) orelse return;
    e.sheet = s;
    e.anim_len = 0;
    e.anim_fps = 0;
}

pub fn entity_pick(sx: f32, sy: f32, alpha_test: bool) ?i64 {
    if (!fin(sx) or !fin(sy)) return null;
    var hits: [32]world_mod.PickHit = undefined;
    const n = engine.world.pickCandidates(&engine.camera, sx, sy, &hits);
    if (n == 0) return null;
    const tile_hit = engine.map.raycastPick(engine.camera.screenToRay(sx, sy), 200.0);
    for (hits[0..n]) |hit| {
        const e = engine.world.get(hit.id) orelse continue;
        if (tile_hit) |th| {
            const dist_e = e.pos.sub(engine.camera.screenToRay(sx, sy).origin).dot(engine.camera.forward());
            const dist_t = th.point.sub(engine.camera.screenToRay(sx, sy).origin).dot(engine.camera.forward());
            if (dist_t + 0.15 < dist_e) continue;
        }
        if (alpha_test) {
            if (engine.renderer.alphaAt(e.sheet, e.frame, e.flip_x, hit.u, hit.v)) |a| {
                if (a < 128) continue;
            }
        }
        return hit.id;
    }
    return null;
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

/// 高亮格走覆盖层组 15（最后绘制，盖在其它覆盖层之上）。
pub fn highlight_tile(x: i64, y: i64, r: f32, g: f32, b: f32, a: f32) void {
    if (!fin4(r, g, b, a)) return;
    // 只对非空格子绘制：越界或 kind 0 时清掉高亮（cursor.lua 每帧对悬停格调用）
    const t = engine.map.get(i32Of(x), i32Of(y)) orelse return engine.overlays.clear(overlay_mod.highlight_group);
    if (t.kind == 0) return engine.overlays.clear(overlay_mod.highlight_group);
    engine.overlays.setSingle(overlay_mod.highlight_group, i32Of(x), i32Of(y), colorBytes(r, g, b, a));
}

pub fn highlight_clear() void {
    engine.overlays.clear(overlay_mod.highlight_group);
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

// ------------------------------------------------------------------ 相机像素基准

pub fn camera_set_ppu(ppu: f32) void {
    if (!std.math.isFinite(ppu) or ppu <= 0) {
        engine.camera.pixels_per_unit = 0;
        return;
    }
    engine.camera.pixels_per_unit = ppu;
}

pub fn camera_get_ppu() f32 {
    return engine.camera.effectivePpu();
}

pub fn camera_set_snap(b: bool) void {
    engine.camera.snap_pixels = b;
}

pub fn px_to_world(px: f32) f32 {
    if (!fin(px)) return 0;
    const ppu = engine.camera.effectivePpu();
    if (ppu <= 0) return 0;
    return px / ppu;
}

// ------------------------------------------------------------------ 视野 / 寻路 / 迷雾

pub fn los(x0: i64, y0: i64, x1: i64, y1: i64) bool {
    return vision.los(&engine.map, i32Of(x0), i32Of(y0), i32Of(x1), i32Of(y1));
}

pub fn vision_can_see(ox: i64, oy: i64, radius: f32, fx: f32, fy: f32, half_deg: f32, tx: i64, ty: i64) bool {
    if (!fin(radius) or !fin(fx) or !fin(fy) or !fin(half_deg)) return false;
    return vision.canSee(&engine.map, i32Of(ox), i32Of(oy), radius, .{ .fx = fx, .fy = fy, .half_angle_deg = half_deg }, i32Of(tx), i32Of(ty));
}

pub fn mask_clear(m: i64) void {
    const id = idOf(m) orelse return;
    const mask = engine.masks.get(id) orelse return;
    mask.clear();
}

pub fn mask_or(dst: i64, src: i64) void {
    const d_id = idOf(dst) orelse return;
    const s_id = idOf(src) orelse return;
    const dm = engine.masks.get(d_id) orelse return;
    const sm = engine.masks.getConst(s_id) orelse return;
    dm.orWith(sm);
}

pub fn mask_count(m: i64) i64 {
    const id = idOf(m) orelse return 0;
    const mask = engine.masks.getConst(id) orelse return 0;
    return mask.count;
}

pub fn fov_compute(m: i64, ox: i64, oy: i64, radius: f32, fx: f32, fy: f32, half_deg: f32) i64 {
    if (!fin(radius) or !fin(fx) or !fin(fy) or !fin(half_deg)) return 0;
    const id = idOf(m) orelse return 0;
    const mask = engine.masks.get(id) orelse return 0;
    return vision.fov(&engine.map, i32Of(ox), i32Of(oy), radius, .{ .fx = fx, .fy = fy, .half_angle_deg = half_deg }, mask);
}

pub fn fov_visible(m: i64, x: i64, y: i64) bool {
    const id = idOf(m) orelse return false;
    const mask = engine.masks.getConst(id) orelse return false;
    return mask.get(i32Of(x), i32Of(y));
}

pub fn reach_compute(m: i64, x: i64, y: i64, max_steps: i64) i64 {
    const id = idOf(m) orelse return 0;
    const mask = engine.masks.get(id) orelse return 0;
    const steps: u32 = @intCast(std.math.clamp(max_steps, 0, 1024));
    return engine.pathfinder.reach(&engine.map, .{ .x = i32Of(x), .y = i32Of(y) }, steps, mask) catch 0;
}

pub fn fog_set(visible_m: i64, explored_m: i64) void {
    engine.lights.fog.visible = idOf(visible_m) orelse 0;
    engine.lights.fog.explored = idOf(explored_m) orelse 0;
    engine.lights.dirty_all = true;
}

pub fn fog_set_levels(explored_k: f32, unknown_k: f32) void {
    if (!fin(explored_k) or !fin(unknown_k)) return;
    engine.lights.fog.explored_k = std.math.clamp(explored_k, 0.0, 1.0);
    engine.lights.fog.unknown_k = std.math.clamp(unknown_k, 0.0, 1.0);
    engine.lights.dirty_all = true;
}

// ------------------------------------------------------------------ 光照

pub fn light_set_ambient(r: f32, g: f32, b: f32) void {
    if (!fin3(r, g, b)) return;
    engine.lights.setAmbient(r, g, b);
}

pub fn light_add(x: f32, z: f32, radius: f32, r: f32, g: f32, b: f32) i64 {
    if (!fin(x) or !fin(z) or !fin(radius) or !fin3(r, g, b)) return 0;
    return engine.lights.add(.{
        .x = x,
        .z = z,
        .radius = radius,
        .color = .{ r, g, b },
    });
}

pub fn light_set_pos(id: i64, x: f32, z: f32) void {
    if (!fin(x) or !fin(z)) return;
    const l = engine.lights.get(idOf(id) orelse return) orelse return;
    l.x = x;
    l.z = z;
    l.dirty = true;
}

pub fn light_set_radius(id: i64, radius: f32) void {
    if (!fin(radius)) return;
    const l = engine.lights.get(idOf(id) orelse return) orelse return;
    l.radius = radius;
    l.dirty = true;
}

pub fn light_set_color(id: i64, r: f32, g: f32, b: f32) void {
    if (!fin3(r, g, b)) return;
    const l = engine.lights.get(idOf(id) orelse return) orelse return;
    l.color = .{ r, g, b };
    l.dirty = true;
}

pub fn light_set_enabled(id: i64, b: bool) void {
    const l = engine.lights.get(idOf(id) orelse return) orelse return;
    l.enabled = b;
    l.dirty = true;
}

pub fn light_remove(id: i64) void {
    engine.lights.remove(idOf(id) orelse return);
}

pub fn light_clear() void {
    engine.lights.clear();
}

pub fn light_level(x: i64, y: i64) f32 {
    return engine.lights.level(i32Of(x), i32Of(y));
}

// ------------------------------------------------------------------ 世界与覆盖层

pub fn world_set_tint(r: f32, g: f32, b: f32) void {
    if (!fin3(r, g, b)) return;
    engine.renderer.setTint(colorOf(r, g, b, 1.0));
}

pub fn world_clear() void {
    engine.clearWorld();
    for (1..vision.max_masks + 1) |i| {
        if (engine.masks.get(@intCast(i))) |m| m.clear();
    }
}

fn colorBytes(r: f32, g: f32, b: f32, a: f32) [4]u8 {
    return .{
        @intFromFloat(std.math.clamp(r * 255.0, 0.0, 255.0)),
        @intFromFloat(std.math.clamp(g * 255.0, 0.0, 255.0)),
        @intFromFloat(std.math.clamp(b * 255.0, 0.0, 255.0)),
        @intFromFloat(std.math.clamp(a * 255.0, 0.0, 255.0)),
    };
}

pub fn overlay_add(g: i64, x: i64, y: i64, r: f32, g2: f32, b: f32, a: f32) void {
    if (!fin4(r, g2, b, a)) return;
    const gi = idOf(g) orelse return;
    engine.overlays.add(gi, i32Of(x), i32Of(y), colorBytes(r, g2, b, a));
}

pub fn overlay_add_tex(g: i64, x: i64, y: i64, atlas: i64, r: f32, g2: f32, b: f32, a: f32) void {
    if (!fin4(r, g2, b, a)) return;
    const gi = idOf(g) orelse return;
    if (atlas < 0 or atlas >= overlay_mod.max_atlas_cells) {
        engine.overlays.rejected_atlas +%= 1;
        return;
    }
    engine.overlays.addTex(gi, i32Of(x), i32Of(y), @intCast(atlas), colorBytes(r, g2, b, a));
}

pub fn overlay_add_mask(g: i64, m: i64, r: f32, g2: f32, b: f32, a: f32) void {
    if (!fin4(r, g2, b, a)) return;
    const gi = idOf(g) orelse return;
    const mask = engine.masks.getConst(idOf(m) orelse return) orelse return;
    engine.overlays.addMask(gi, mask, colorBytes(r, g2, b, a));
}

pub fn overlay_clear(g: i64) void {
    const gi = idOf(g) orelse return;
    engine.overlays.clear(gi);
}

pub fn overlay_clear_all() void {
    engine.overlays.clearAll();
}

/// {tile_quads, chunks_rebuilt_last, chunks_drawn_last}
pub fn render_stats() [3]i32 {
    return .{
        @intCast(engine.renderer.tile_quads),
        @intCast(engine.renderer.chunks_rebuilt_last),
        @intCast(engine.renderer.chunks_drawn_last),
    };
}

/// {overlay_cells, rejected_atlas_cells}：被 overlay_add_tex 因图集格越界而忽略的累计次数
pub fn overlay_stats() [2]i32 {
    return .{
        @intCast(@min(engine.overlays.total, std.math.maxInt(i32))),
        @intCast(@min(engine.overlays.rejected_atlas, std.math.maxInt(i32))),
    };
}

// ------------------------------------------------------------------ 3D 模型（.wsm）

pub fn map_set_draw_tiles(b: bool) void {
    engine.renderer.draw_tiles = b;
}

const ModelInfo = struct { nodes: i64, tris: i64, visible_tris: i64 };

pub fn model_load(path: [*:0]const u8) ?i64 {
    const allocator = mem.getAllocator();
    const p = std.mem.span(path);
    const bytes = std.Io.Dir.cwd().readFileAlloc(delve.io.getIo(), p, allocator, .limited(64 << 20)) catch |err| {
        delve.debug.warning("iso: model_load: cannot read '{s}': {s}", .{ p, @errorName(err) });
        return null;
    };
    defer allocator.free(bytes);
    const m = model_mod.Model.parse(allocator, bytes) catch |err| {
        delve.debug.warning("iso: model_load: bad model '{s}': {s}", .{ p, @errorName(err) });
        return null;
    };
    const id = engine.addModel(m) orelse {
        var mm = m;
        mm.deinit(allocator);
        delve.debug.warning("iso: model_load: out of memory for '{s}'", .{p});
        return null;
    };
    return id;
}

pub fn model_unload(id: i64) void {
    engine.removeModel(id);
}

pub fn model_info(id: i64) ?ModelInfo {
    const inst = engine.findModel(id) orelse return null;
    return .{
        .nodes = @intCast(inst.model.nodes.len),
        .tris = inst.model.triCount(),
        .visible_tris = inst.model.visibleTris(),
    };
}

var node_name_buf: [4096][]const u8 = undefined;

pub fn model_nodes(id: i64) []const []const u8 {
    const inst = engine.findModel(id) orelse return node_name_buf[0..0];
    const n = @min(inst.model.nodes.len, node_name_buf.len);
    for (inst.model.nodes[0..n], 0..) |node, i| node_name_buf[i] = node.name;
    return node_name_buf[0..n];
}

pub fn model_set_visible(id: i64, pattern: [*:0]const u8, on: bool) i64 {
    const inst = engine.findModel(id) orelse return 0;
    return inst.setVisible(mem.getAllocator(), std.mem.span(pattern), on);
}

pub fn model_node_visible(id: i64, name: [*:0]const u8) ?bool {
    const inst = engine.findModel(id) orelse return null;
    const i = inst.model.findNode(std.mem.span(name)) orelse return null;
    return inst.model.visible[i];
}

pub fn model_set_offset(id: i64, x: f32, y: f32, z: f32) void {
    if (!fin3(x, y, z)) return;
    const inst = engine.findModel(id) orelse return;
    inst.setOffset(x, y, z);
}
