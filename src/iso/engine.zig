//! 引擎胶水：全局状态 + `iso_world` 模块（世界 tick 与世界渲染）。
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
const pathfind = @import("pathfind.zig");
const vision = @import("vision.zig");
const lightmap = @import("lightmap.zig");
const overlay = @import("overlay.zig");
const world_mod = @import("world.zig");
const render = @import("render.zig");
const script_host = @import("script_host.zig");

pub const Config = struct {
    main_script: [:0]const u8 = "assets/main.lua",
    map_w: u32 = 32,
    map_h: u32 = 32,
    clear_color: colors.Color = colors.Color.newBytes(40, 48, 72, 255),
    max_dt: f32 = 0.1,
    dev_hot_reload: bool = false,
    pixels_per_unit: f32 = 0,
    snap_pixels: bool = false,
};

pub var config: Config = .{};
pub var map: tilemap.TileMap = undefined;
pub var masks: vision.MaskSet = undefined;
pub var lights: lightmap.LightMap = undefined;
pub var overlays: overlay.Overlays = undefined;
pub var pathfinder: pathfind.PathFinder = undefined;
pub var world: world_mod.World = undefined;
pub var camera: camera_mod.IsoCamera = .{};
pub var renderer: render.WorldRenderer = undefined;
/// 相机跟随的实体 id（0 = 不跟随）
pub var follow_entity: u32 = 0;

var initialized: bool = false;

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
    masks = try vision.MaskSet.init(allocator, config.map_w, config.map_h);
    errdefer masks.deinit();
    lights = try lightmap.LightMap.init(allocator, config.map_w, config.map_h);
    errdefer lights.deinit();
    overlays = overlay.Overlays.init(allocator);
    errdefer overlays.deinit();
    pathfinder = pathfind.PathFinder.init(allocator);
    errdefer pathfinder.deinit();
    world = world_mod.World.init(allocator);
    errdefer world.deinit();
    renderer = try render.WorldRenderer.init(allocator);
    camera = .{
        .pixels_per_unit = config.pixels_per_unit,
        .snap_pixels = config.snap_pixels,
    };
    follow_entity = 0;
    graphics.setClearColor(config.clear_color);
    initialized = true;
}

fn onCleanup() !void {
    if (!initialized) return;
    initialized = false;
    renderer.deinit();
    world.deinit();
    pathfinder.deinit();
    overlays.deinit();
    lights.deinit();
    masks.deinit();
    map.deinit();
}

fn viewportW() f32 {
    return @floatFromInt(@max(papp.getWidth(), 1));
}

fn viewportH() f32 {
    return @floatFromInt(@max(papp.getHeight(), 1));
}

fn onTick(raw_dt: f32) void {
    const dt = @min(raw_dt, config.max_dt);
    world.tick(dt, &map, camera.yaw);
    _ = lights.update(&map, &masks);
    world.applyLight(&lights, &map, dt);
    if (follow_entity != 0) {
        if (world.get(follow_entity)) |e| {
            camera.follow_goal = e.pos;
        } else {
            follow_entity = 0;
            camera.follow_goal = null;
        }
    }
    camera.tick(dt);
    camera.update(viewportW(), viewportH());
}

fn onDraw() void {
    camera.update(viewportW(), viewportH());
    renderer.draw(&map, &world, &camera, &lights, &overlays);
}

pub fn clearWorld() void {
    world.clear();
    follow_entity = 0;
    camera.follow_goal = null;
}

pub fn resetMapSize(w: u32, h: u32) !void {
    try map.resize(w, h);
    try masks.resize(w, h);
    try lights.resize(w, h);
    overlays.clearAll();
    renderer.dropChunks();
}

pub fn resetState() void {
    const allocator = mem.getAllocator();
    if (tilemap.TileMap.init(allocator, config.map_w, config.map_h)) |fresh| {
        map.deinit();
        map = fresh;
    } else |_| {
        map.fill(0, 0);
        debug.err("iso: failed to recreate map on reload", .{});
    }
    masks.resize(config.map_w, config.map_h) catch {};
    lights.resize(config.map_w, config.map_h) catch {};
    lights.clear();
    lights.setAmbient(1, 1, 1);
    lights.fog = .{};
    overlays.clearAll();
    world.clear();
    follow_entity = 0;
    camera = .{
        .pixels_per_unit = config.pixels_per_unit,
        .snap_pixels = config.snap_pixels,
    };
    renderer.resetResources();
}
