//! 图形层：瓦片图集、精灵表、世界渲染器。
//!
//! 设计要点（见 docs/PLAN.md 第 0 节）：
//! - 真 3D 世界 + 深度缓冲，精灵用 alpha_cutoff 镂空，不做手工排序；
//! - 瓦片批次是静态的，仅在 `map.dirty` 时重建；精灵批次每帧重建；
//! - 世界投影左乘深度重映射矩阵，使 HUD（Delve 2D API）永远在世界之上。
const std = @import("std");
const delve = @import("delve");
const math = delve.math;
const colors = delve.colors;
const debug = delve.debug;
const graphics = delve.platform.graphics;
const assets = delve.api.assets;
const batcher = delve.graphics.batcher;
const sprites = delve.graphics.sprites;
const Rect = delve.spatial.Rect;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Color = colors.Color;
const TextureRegion = sprites.TextureRegion;
const Allocator = std.mem.Allocator;

const camera_mod = @import("camera.zig");
const tilemap = @import("tilemap.zig");
const world_mod = @import("world.zig");
const coords = @import("coords.zig");
const IsoCamera = camera_mod.IsoCamera;
const TileMap = tilemap.TileMap;
const World = world_mod.World;
pub const GridPos = coords.GridPos;

/// 在图集中取第 (col,row) 格的 UV 区域，四周内缩半个像素防止渗色。
/// TextureRegion 的 v 方向：v=0 为图像顶部（与批次器的顶点映射一致，无需 flip_tex_y）。
fn gridRegion(col: u32, row: u32, cell_w: u32, cell_h: u32, tex_w: u32, tex_h: u32) TextureRegion {
    const tw: f32 = @floatFromInt(@max(tex_w, 1));
    const th: f32 = @floatFromInt(@max(tex_h, 1));
    const x0: f32 = @floatFromInt(col * cell_w);
    const y0: f32 = @floatFromInt(row * cell_h);
    const cw: f32 = @floatFromInt(cell_w);
    const ch: f32 = @floatFromInt(cell_h);
    return .{
        .u = (x0 + 0.5) / tw,
        .v = (y0 + 0.5) / th,
        .u_2 = (x0 + cw - 0.5) / tw,
        .v_2 = (y0 + ch - 0.5) / th,
    };
}

pub const TileAtlas = struct {
    texture_handle: u32,
    cols: u32,
    rows: u32,
    tex_w: u32,
    tex_h: u32,

    pub fn region(self: TileAtlas, index: u16) TextureRegion {
        const cols = @max(self.cols, 1);
        const col: u32 = index % cols;
        const row: u32 = index / cols;
        return gridRegion(col, row, self.tex_w / cols, self.tex_h / @max(self.rows, 1), self.tex_w, self.tex_h);
    }
};

pub const SpriteSheet = struct {
    texture_handle: u32,
    frame_w: u32,
    frame_h: u32,
    cols: u32,
    rows: u32,
    tex_w: u32,
    tex_h: u32,

    pub fn region(self: SpriteSheet, frame: u16, flip_x: bool) TextureRegion {
        const cols = @max(self.cols, 1);
        const col: u32 = frame % cols;
        const row: u32 = @min(frame / cols, if (self.rows > 0) self.rows - 1 else 0);
        const r = gridRegion(col, row, self.frame_w, self.frame_h, self.tex_w, self.tex_h);
        return if (flip_x) r.flipX() else r;
    }
};

/// 假光照系数
const light_top: f32 = 1.0;
const light_x: f32 = 0.78;
const light_z: f32 = 0.62;

/// 单个批次的四边形预算（Delve 上限约 10922 个）
pub const max_quads_per_batch: u32 = 10_000;

pub const WorldRenderer = struct {
    allocator: Allocator,
    tile_batch: batcher.SpriteBatcher,
    sprite_batch: batcher.SpriteBatcher,
    hl_batch: batcher.SpriteBatcher,
    atlas: ?TileAtlas = null,
    sheets: std.ArrayList(SpriteSheet) = .empty,
    /// 每个纹理句柄一个材质（NEAREST、不剔除、alpha_cutoff 0.5、不混合）
    materials: std.AutoHashMap(u32, graphics.Material),
    hl_material: graphics.Material,
    highlight: ?GridPos = null,
    highlight_color: Color = colors.white,
    /// 路径 -> 纹理句柄缓存。Delve 的 assets 以字符串"指针"为键，
    /// 这里用稳定的自有字符串，避免 Lua 字符串被 GC 后地址复用导致取错纹理。
    texture_cache: std.StringHashMap(u32),
    /// 各批次本帧已加入的四边形数及是否已警告（Delve 单批次上限 65536 索引）
    tile_quads: u32 = 0,
    sprite_quads: u32 = 0,
    hl_quads: u32 = 0,
    warned_tiles: bool = false,
    warned_sprites: bool = false,

    pub fn init(allocator: Allocator) !WorldRenderer {
        var tile_batch = try batcher.SpriteBatcher.init(.{});
        errdefer tile_batch.deinit();
        var sprite_batch = try batcher.SpriteBatcher.init(.{});
        errdefer sprite_batch.deinit();
        var hl_batch = try batcher.SpriteBatcher.init(.{});
        errdefer hl_batch.deinit();

        // 高亮：半透明混合，不写深度
        const hl_material = try graphics.Material.init(.{
            .texture_0 = graphics.tex_white,
            .cull_mode = .NONE,
            .blend_mode = .BLEND,
            .depth_write_enabled = false,
            .samplers = &[_]graphics.FilterMode{.NEAREST},
        });

        return .{
            .allocator = allocator,
            .tile_batch = tile_batch,
            .sprite_batch = sprite_batch,
            .hl_batch = hl_batch,
            .materials = std.AutoHashMap(u32, graphics.Material).init(allocator),
            .hl_material = hl_material,
            .texture_cache = std.StringHashMap(u32).init(allocator),
        };
    }

    pub fn deinit(self: *WorldRenderer) void {
        self.tile_batch.deinit();
        self.sprite_batch.deinit();
        self.hl_batch.deinit();
        var it = self.materials.valueIterator();
        while (it.next()) |m| m.deinit();
        self.materials.deinit();
        self.hl_material.deinit();
        self.sheets.deinit(self.allocator);
        var kit = self.texture_cache.keyIterator();
        while (kit.next()) |k| self.allocator.free(@as([:0]const u8, k.*.ptr[0..k.*.len :0]));
        self.texture_cache.deinit();
    }

    /// 热重载时调用：清掉图集 / 精灵表 / 高亮（材质与纹理缓存保留，仍然有效）。
    pub fn resetResources(self: *WorldRenderer) void {
        self.atlas = null;
        self.sheets.clearRetainingCapacity();
        self.highlight = null;
        self.tile_batch.reset();
        self.tile_batch.apply();
    }

    /// 通过路径取得纹理句柄（0 = 失败）。同一路径只加载一次。
    pub fn loadTexture(self: *WorldRenderer, path: []const u8) u32 {
        if (self.texture_cache.get(path)) |h| return h;
        const owned = self.allocator.dupeZ(u8, path) catch return 0;
        const h = assets.get_texture(owned.ptr);
        if (h == 0) {
            self.allocator.free(owned);
            return 0;
        }
        self.texture_cache.put(owned[0..path.len], h) catch {
            self.allocator.free(owned);
            return h;
        };
        return h;
    }

    /// 取（或创建）纹理句柄对应的材质
    fn materialFor(self: *WorldRenderer, handle: u32) ?graphics.Material {
        if (self.materials.get(handle)) |m| return m;
        const tex = assets._getTextureFromHandle(handle) orelse return null;
        var mat = graphics.Material.init(.{
            .texture_0 = tex,
            .cull_mode = .NONE,
            .blend_mode = .NONE,
            .samplers = &[_]graphics.FilterMode{.NEAREST},
        }) catch return null;
        mat.state.params.alpha_cutoff = 0.5;
        self.materials.put(handle, mat) catch {
            mat.deinit();
            return null;
        };
        return mat;
    }

    pub fn setTileAtlas(self: *WorldRenderer, atlas: TileAtlas) !void {
        self.atlas = atlas;
        _ = self.materialFor(atlas.texture_handle) orelse return error.TextureUnavailable;
    }

    pub fn addSheet(self: *WorldRenderer, sheet: SpriteSheet) !u32 {
        _ = self.materialFor(sheet.texture_handle) orelse return error.TextureUnavailable;
        try self.sheets.append(self.allocator, sheet);
        return @intCast(self.sheets.items.len);
    }

    pub fn setHighlight(self: *WorldRenderer, tile: ?GridPos, color: Color) void {
        self.highlight = tile;
        self.highlight_color = color;
    }

    pub fn draw(self: *WorldRenderer, map: *TileMap, world: *World, cam: *IsoCamera) void {
        if (self.atlas != null and map.dirty) {
            self.rebuildTiles(map);
            map.dirty = false;
        }
        self.rebuildSprites(world, cam);
        self.rebuildHighlight(map);

        const mats = graphics.CameraMatrices{
            .view = cam.view,
            .proj = camera_mod.remapDepthToBackHalf(cam.proj),
        };
        self.tile_batch.draw(mats, Mat4.identity);
        self.sprite_batch.draw(mats, Mat4.identity);
        self.hl_batch.draw(mats, Mat4.identity); // 最后画：半透明且不写深度
    }

    // ------------------------------------------------------------ 瓦片

    fn rebuildTiles(self: *WorldRenderer, map: *TileMap) void {
        const atlas = self.atlas.?;
        const mat = self.materialFor(atlas.texture_handle) orelse return;
        const b = &self.tile_batch;
        b.reset();
        self.tile_quads = 0;
        b.useMaterial(mat);

        const w: i32 = @intCast(map.width);
        const h: i32 = @intCast(map.height);
        var gy: i32 = 0;
        while (gy < h) : (gy += 1) {
            var gx: i32 = 0;
            while (gx < w) : (gx += 1) {
                const tile = map.get(gx, gy).?;
                const def = map.getDef(tile.kind) orelse continue;
                const top = map.topY(gx, gy);
                const fx: f32 = @floatFromInt(gx);
                const fz: f32 = @floatFromInt(gy);

                // 顶面：translate(gx, top, gy+1) * rotateX(-90)，Rect(0,0,1,1)
                const top_m = Mat4.translate(Vec3.new(fx, top, fz + 1)).mul(Mat4.rotate(-90, Vec3.x_axis));
                b.setTransformMatrix(top_m);
                self.tileQuad(Rect.new(Vec2.zero, Vec2.new(1, 1)), atlas.region(def.top), shade(light_top));

                // 四个侧面：(邻格dx, 邻格dz, 平移, 绕Y旋转角, 亮度)
                const sides = [_]struct { dx: i32, dy: i32, ox: f32, oz: f32, rot: f32, light: f32 }{
                    .{ .dx = 1, .dy = 0, .ox = 1, .oz = 1, .rot = 90, .light = light_x },
                    .{ .dx = -1, .dy = 0, .ox = 0, .oz = 0, .rot = -90, .light = light_x },
                    .{ .dx = 0, .dy = 1, .ox = 0, .oz = 1, .rot = 0, .light = light_z },
                    .{ .dx = 0, .dy = -1, .ox = 1, .oz = 0, .rot = 180, .light = light_z },
                };
                for (sides) |s| {
                    const nx = gx + s.dx;
                    const ny = gy + s.dy;
                    const nb_top: f32 = if (!map.inBounds(nx, ny)) -map.base_depth else map.topY(nx, ny);
                    if (nb_top >= top) continue;
                    const region = atlas.region(def.side);
                    var y0 = nb_top;
                    while (y0 < top - 1e-4) {
                        const seg = @min(map.height_unit, top - y0);
                        const m = Mat4.translate(Vec3.new(fx + s.ox, y0, fz + s.oz)).mul(Mat4.rotate(s.rot, Vec3.up));
                        b.setTransformMatrix(m);
                        self.tileQuad(Rect.new(Vec2.zero, Vec2.new(1, seg)), region, shade(s.light));
                        y0 += seg;
                    }
                }
            }
        }
        b.apply();
    }

    fn tileQuad(self: *WorldRenderer, rect: Rect, region: TextureRegion, color: Color) void {
        if (self.tile_quads >= max_quads_per_batch) {
            if (!self.warned_tiles) {
                self.warned_tiles = true;
                debug.warning("iso: tile quad budget ({d}) exceeded, remaining tiles skipped", .{max_quads_per_batch});
            }
            return;
        }
        self.tile_quads += 1;
        self.tile_batch.addRectangle(rect, region, color);
    }

    fn shade(l: f32) Color {
        return Color.new(l, l, l, 1.0);
    }

    // ------------------------------------------------------------ 精灵

    fn rebuildSprites(self: *WorldRenderer, world: *World, cam: *const IsoCamera) void {
        const b = &self.sprite_batch;
        b.reset();
        self.sprite_quads = 0;

        const pitch_rad = std.math.degreesToRadians(cam.pitch);
        const vscale = 1.0 / @cos(pitch_rad);
        const rot = camera_mod.billboardRotation(cam.yaw);
        const sc = Mat4.scale(Vec3.new(1, vscale, 1));

        var it = world.iterator();
        while (it.next()) |e| {
            if (e.sheet == 0 or e.sheet > self.sheets.items.len) continue;
            if (self.sprite_quads >= max_quads_per_batch) {
                if (!self.warned_sprites) {
                    self.warned_sprites = true;
                    debug.warning("iso: sprite quad budget ({d}) exceeded, remaining sprites skipped", .{max_quads_per_batch});
                }
                break;
            }
            const sheet = self.sheets.items[e.sheet - 1];
            const mat = self.materialFor(sheet.texture_handle) orelse continue;
            b.useMaterial(mat);
            b.setTransformMatrix(Mat4.translate(e.pos).mul(rot).mul(sc));
            const rect = Rect.new(Vec2.new(-e.size.x * 0.5, 0), e.size);
            self.sprite_quads += 1;
            b.addRectangle(rect, sheet.region(e.frame, e.flip_x), e.tint);
        }
        b.apply();
    }

    // ------------------------------------------------------------ 高亮

    fn rebuildHighlight(self: *WorldRenderer, map: *const TileMap) void {
        const b = &self.hl_batch;
        b.reset();
        self.hl_quads = 0;
        if (self.highlight) |t| {
            if (map.get(t.x, t.y)) |tile| {
                if (tile.kind != 0) {
                    b.useMaterial(self.hl_material);
                    const fx: f32 = @floatFromInt(t.x);
                    const fz: f32 = @floatFromInt(t.y);
                    const m = Mat4.translate(Vec3.new(fx, map.topY(t.x, t.y) + 0.01, fz + 1)).mul(Mat4.rotate(-90, Vec3.x_axis));
                    b.setTransformMatrix(m);
                    if (self.hl_quads < max_quads_per_batch) {
                        self.hl_quads += 1;
                        b.addRectangle(Rect.new(Vec2.zero, Vec2.new(1, 1)), TextureRegion.default(), self.highlight_color);
                    }
                }
            }
        }
        b.apply();
    }
};
