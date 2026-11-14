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
/// 已加载的模型实例（id 从 1 起，运行期内不复用）；resetState 清空，clearWorld 不动
pub var models: std.ArrayList(*render.ModelInstance) = .empty;
var next_model_id: u32 = 1;
/// 相机跟随的实体 id（0 = 不跟随）
pub var follow_entity: u32 = 0;

var initialized: bool = false;
var last_dt: f32 = 0;

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
    // 在 Lua update（script_host，-60）之后更新光照，Lua 本帧对光源/迷雾/不透明格的改动当帧生效
    try modules.registerModule(.{
        .name = "iso_world_post",
        .priority = -50,
        .tick_fn = onLateTick,
    });
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
    dropModels();
    models.deinit(mem.getAllocator());
    models = .empty;
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
    last_dt = dt;
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
    camera.update(viewportW(), viewportH());
}

/// Lua update 之后：光照缓存重算 + 实体受光插值。
fn onLateTick(_: f32) void {
    if (!initialized) return;
    _ = lights.update(&map, &masks);
    world.applyLight(&lights, &map, last_dt);
}

fn onDraw() void {
    camera.update(viewportW(), viewportH());
    renderer.draw(&map, &world, &camera, &lights, &overlays, models.items);
}

pub fn addModel(m: @import("model.zig").Model) ?u32 {
    const allocator = mem.getAllocator();
    const inst = allocator.create(render.ModelInstance) catch return null;
    inst.* = .{ .id = next_model_id, .model = m };
    models.append(allocator, inst) catch {
        allocator.destroy(inst);
        return null;
    };
    next_model_id += 1;
    return inst.id;
}

pub fn findModel(id: i64) ?*render.ModelInstance {
    const u = std.math.cast(u32, id) orelse return null;
    for (models.items) |m| {
        if (m.id == u) return m;
    }
    return null;
}

pub fn removeModel(id: i64) void {
    const u = std.math.cast(u32, id) orelse return;
    const allocator = mem.getAllocator();
    for (models.items, 0..) |m, i| {
        if (m.id != u) continue;
        _ = models.orderedRemove(i);
        m.deinit(allocator);
        allocator.destroy(m);
        return;
    }
}

pub fn dropModels() void {
    const allocator = mem.getAllocator();
    for (models.items) |m| {
        m.deinit(allocator);
        allocator.destroy(m);
    }
    models.clearRetainingCapacity();
}

pub fn clearWorld() void {
    world.clearScene(&lights, &overlays);
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
    dropModels();
    renderer.draw_tiles = true;
    follow_entity = 0;
    camera = .{
        .pixels_per_unit = config.pixels_per_unit,
        .snap_pixels = config.snap_pixels,
    };
    renderer.resetResources();
}
