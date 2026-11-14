//! 引擎胶水：全局状态 + `iso_world` 模块（世界 tick 与世界渲染）。
//!
//! 模块优先级（数值越小越先）：
//!   iso_world(-70) -> iso_script_host(-60) -> Delve scriptapi 库(-50)
//! tick：先推进实体，再调用 Lua `_update(dt)`；
//! draw：先画世界，再由 Lua `_draw()` 排入 HUD 指令，随后由 -50 的 libDraw 提交。
const std = @import("std");
const delve = @import("delve");
const colors = delve.colors;
const graphics = delve.platform.graphics;
const papp = delve.platform.app;
const modules = delve.modules;
const debug = delve.debug;
const mem = delve.mem;

const camera_mod = @import("camera.zig");
const tilemap = @import("tilemap.zig");
const world_mod = @import("world.zig");
const render = @import("render.zig");
const script_host = @import("script_host.zig");

pub const Config = struct {
    main_script: [:0]const u8 = "assets/main.lua",
    map_w: u32 = 32,
    map_h: u32 = 32,
    clear_color: colors.Color = colors.Color.newBytes(40, 48, 72, 255),
};

pub var config: Config = .{};
pub var map: tilemap.TileMap = undefined;
pub var world: world_mod.World = undefined;
pub var camera: camera_mod.IsoCamera = .{};
pub var renderer: render.WorldRenderer = undefined;
/// 相机跟随的实体 id（0 = 不跟随）
pub var follow_entity: u32 = 0;

var initialized: bool = false;

/// 注册引擎模块；需在 `delve.init` 之后、`app.start` 之前调用。
pub fn register(cfg: Config) !void {
    config = cfg;
    try modules.registerModule(.{
        .name = "iso_world",
        .priority = -70,
        .init_fn = onInit,
        .tick_fn = onTick,
        .draw_fn = onDraw,
        .cleanup_fn = onCleanup,
    });
    try script_host.register(cfg.main_script);
}

fn onInit() !void {
    const allocator = mem.getAllocator();
    map = try tilemap.TileMap.init(allocator, config.map_w, config.map_h);
    errdefer map.deinit();
    world = world_mod.World.init(allocator);
    errdefer world.deinit();
    renderer = try render.WorldRenderer.init(allocator);
    camera = .{};
    follow_entity = 0;
    graphics.setClearColor(config.clear_color);
    initialized = true;
}

fn onCleanup() !void {
    if (!initialized) return;
    initialized = false;
    renderer.deinit();
    world.deinit();
    map.deinit();
}

fn viewportW() f32 {
    return @floatFromInt(@max(papp.getWidth(), 1));
}

fn viewportH() f32 {
    return @floatFromInt(@max(papp.getHeight(), 1));
}

fn onTick(dt: f32) void {
    world.tick(dt, &map, camera.yaw);
    if (follow_entity != 0) {
        if (world.get(follow_entity)) |e| {
            camera.follow_goal = e.pos;
        } else {
            follow_entity = 0;
            camera.follow_goal = null;
        }
    }
    camera.tick(dt);
    // 刷新矩阵，保证本帧 Lua 的鼠标拾取使用最新相机
    camera.update(viewportW(), viewportH());
}

fn onDraw() void {
    camera.update(viewportW(), viewportH());
    renderer.draw(&map, &world, &camera);
}

/// 热重载时重置全部引擎状态（地图 / 实体 / 相机 / 渲染器资源）。
pub fn resetState() void {
    const allocator = mem.getAllocator();
    if (tilemap.TileMap.init(allocator, config.map_w, config.map_h)) |fresh| {
        map.deinit();
        map = fresh;
    } else |_| {
        // 内存不足：保留旧地图，仅清空
        map.fill(0, 0);
        debug.err("iso: failed to recreate map on reload", .{});
    }
    map.dirty = true;
    world.entities.clearRetainingCapacity();
    world.free.clearRetainingCapacity();
    follow_entity = 0;
    camera = .{};
    renderer.resetResources();
}
