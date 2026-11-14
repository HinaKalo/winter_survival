//! 图形层：分块瓦片网格、覆盖层、精灵表、世界渲染器。
const std = @import("std");
const delve = @import("delve");
const math = delve.math;
const colors = delve.colors;
const debug = delve.debug;
const graphics = delve.platform.graphics;
const assets = delve.api.assets;
const images = delve.images;
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
const tilemesh = @import("tilemesh.zig");
const lightmap = @import("lightmap.zig");
const overlay = @import("overlay.zig");
const world_mod = @import("world.zig");
const coords = @import("coords.zig");
const IsoCamera = camera_mod.IsoCamera;
const TileMap = tilemap.TileMap;
const LightMap = lightmap.LightMap;
const Overlays = overlay.Overlays;
const World = world_mod.World;
pub const GridPos = coords.GridPos;

comptime {
    const V = graphics.PackedVertex;
    std.debug.assert(@hasField(V, "x") and @hasField(V, "y") and @hasField(V, "z") and
        @hasField(V, "color") and @hasField(V, "u") and @hasField(V, "v"));
}

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

pub const max_quads_per_batch: u32 = 10_000;

const AlphaMask = struct {
    w: u32,
    h: u32,
    alpha: []u8,
};

const ChunkBatch = struct {
    batch: ?batcher.Batcher = null,
    bounds: tilemesh.Aabb = .{ .min = Vec3.zero, .max = Vec3.zero },
    quads: u32 = 0,
};

pub const WorldRenderer = struct {
    allocator: Allocator,
    sprite_batch: batcher.SpriteBatcher,
    ov_batch: batcher.SpriteBatcher,
    hl_batch: batcher.SpriteBatcher,
    chunks: std.ArrayList(ChunkBatch) = .empty,
    chunk_quad_scratch: std.ArrayList(tilemesh.Quad) = .empty,
    atlas: ?TileAtlas = null,
    sheets: std.ArrayList(SpriteSheet) = .empty,
    materials: std.AutoHashMap(u32, graphics.Material),
    ov_materials: std.AutoHashMap(u32, graphics.Material),
    alpha_masks: std.AutoHashMap(u32, AlphaMask),
    hl_material: graphics.Material,
    highlight: ?GridPos = null,
    highlight_color: Color = colors.white,
    tint: Color = colors.white,
    texture_cache: std.StringHashMap(u32),
    tile_quads: u32 = 0,
    sprite_quads: u32 = 0,
    hl_quads: u32 = 0,
    chunks_rebuilt_last: u32 = 0,
    chunks_drawn_last: u32 = 0,
    warned_tiles: bool = false,
    warned_sprites: bool = false,

    pub fn init(allocator: Allocator) !WorldRenderer {
        var sprite_batch = try batcher.SpriteBatcher.init(.{});
        errdefer sprite_batch.deinit();
        var ov_batch = try batcher.SpriteBatcher.init(.{});
        errdefer ov_batch.deinit();
        var hl_batch = try batcher.SpriteBatcher.init(.{});
        errdefer hl_batch.deinit();

        const hl_material = try graphics.Material.init(.{
            .texture_0 = graphics.tex_white,
            .cull_mode = .NONE,
            .blend_mode = .BLEND,
            .depth_write_enabled = false,
            .samplers = &[_]graphics.FilterMode{.NEAREST},
        });

        return .{
            .allocator = allocator,
            .sprite_batch = sprite_batch,
            .ov_batch = ov_batch,
            .hl_batch = hl_batch,
            .materials = std.AutoHashMap(u32, graphics.Material).init(allocator),
            .ov_materials = std.AutoHashMap(u32, graphics.Material).init(allocator),
            .alpha_masks = std.AutoHashMap(u32, AlphaMask).init(allocator),
            .hl_material = hl_material,
            .texture_cache = std.StringHashMap(u32).init(allocator),
        };
    }

    pub fn deinit(self: *WorldRenderer) void {
        self.dropChunks();
        self.chunks.deinit(self.allocator);
        self.chunk_quad_scratch.deinit(self.allocator);
        self.sprite_batch.deinit();
        self.ov_batch.deinit();
        self.hl_batch.deinit();
        var it = self.materials.valueIterator();
        while (it.next()) |m| m.deinit();
        self.materials.deinit();
        var oit = self.ov_materials.valueIterator();
        while (oit.next()) |m| m.deinit();
        self.ov_materials.deinit();
        var ait = self.alpha_masks.valueIterator();
        while (ait.next()) |am| self.allocator.free(am.alpha);
        self.alpha_masks.deinit();
        self.hl_material.deinit();
        self.sheets.deinit(self.allocator);
        var kit = self.texture_cache.keyIterator();
        while (kit.next()) |k| self.allocator.free(@as([:0]const u8, k.*.ptr[0..k.*.len :0]));
        self.texture_cache.deinit();
    }

    pub fn dropChunks(self: *WorldRenderer) void {
        for (self.chunks.items) |*c| {
            if (c.batch) |*b| b.deinit();
        }
        self.chunks.clearRetainingCapacity();
        self.tile_quads = 0;
    }

    pub fn resetResources(self: *WorldRenderer) void {
        self.atlas = null;
        self.sheets.clearRetainingCapacity();
        self.highlight = null;
        self.tint = colors.white;
        self.dropChunks();
    }

    pub fn setTint(self: *WorldRenderer, c: Color) void {
        self.tint = c;
    }

    pub fn loadTexture(self: *WorldRenderer, path: []const u8) u32 {
        if (self.texture_cache.get(path)) |h| return h;
        const owned = self.allocator.dupeZ(u8, path) catch return 0;
        const h = assets.get_texture(owned.ptr);
        if (h == 0) {
            self.allocator.free(owned);
            return 0;
        }
        if (!self.alpha_masks.contains(h)) {
            if (assets._getImageFromHandle(h)) |im| {
                const npx = @as(usize, im.width) * im.height;
                if (self.allocator.alloc(u8, npx)) |alpha| {
                    for (0..npx) |i| alpha[i] = im.data[i * 4 + 3];
                    self.alpha_masks.put(h, .{ .w = im.width, .h = im.height, .alpha = alpha }) catch {
                        self.allocator.free(alpha);
                    };
                } else |_| {}
            }
        }
        self.texture_cache.put(owned[0..path.len], h) catch {
            self.allocator.free(owned);
            return h;
        };
        return h;
    }

    pub fn alphaAt(self: *const WorldRenderer, sheet_id: u32, frame: u16, flip: bool, u_in: f32, v_in: f32) ?u8 {
        if (sheet_id == 0 or sheet_id > self.sheets.items.len) return null;
        if (!std.math.isFinite(u_in) or !std.math.isFinite(v_in)) return null;
        const sheet = self.sheets.items[sheet_id - 1];
        const mask = self.alpha_masks.get(sheet.texture_handle) orelse return null;
        if (sheet.frame_w == 0 or sheet.frame_h == 0 or mask.w == 0 or mask.h == 0) return null;

        const u = std.math.clamp(u_in, 0.0, 1.0);
        const v = std.math.clamp(v_in, 0.0, 1.0);
        const cols = @max(sheet.cols, 1);
        const col: u32 = frame % cols;
        const row: u32 = @min(frame / cols, if (sheet.rows > 0) sheet.rows - 1 else 0);
        const fu = if (flip) 1.0 - u else u;
        const lx: u32 = @min(sheet.frame_w - 1, @as(u32, @intFromFloat(fu * @as(f32, @floatFromInt(sheet.frame_w)))));
        const ly: u32 = @min(sheet.frame_h - 1, @as(u32, @intFromFloat(v * @as(f32, @floatFromInt(sheet.frame_h)))));
        const px = col * sheet.frame_w + lx;
        const py = row * sheet.frame_h + ly;
        if (px >= mask.w or py >= mask.h) return null;
        return mask.alpha[@as(usize, py) * mask.w + px];
    }

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

    fn overlayMaterialFor(self: *WorldRenderer, handle: u32) ?graphics.Material {
        if (self.ov_materials.get(handle)) |m| return m;
        const tex = assets._getTextureFromHandle(handle) orelse return null;
        const mat = graphics.Material.init(.{
            .texture_0 = tex,
            .cull_mode = .NONE,
            .blend_mode = .BLEND,
            .depth_write_enabled = false,
            .samplers = &[_]graphics.FilterMode{.NEAREST},
        }) catch return null;
        self.ov_materials.put(handle, mat) catch {
            var m = mat;
            m.deinit();
            return null;
        };
        return mat;
    }

    pub fn setTileAtlas(self: *WorldRenderer, atlas: TileAtlas) !void {
        self.atlas = atlas;
        _ = self.materialFor(atlas.texture_handle) orelse return error.TextureUnavailable;
        self.dropChunks();
    }

    pub fn addSheet(self: *WorldRenderer, sheet: SpriteSheet) !u32 {
        for (self.sheets.items, 0..) |s, i| {
            if (s.texture_handle == sheet.texture_handle and s.frame_w == sheet.frame_w and s.frame_h == sheet.frame_h) {
                return @intCast(i + 1);
            }
        }
        _ = self.materialFor(sheet.texture_handle) orelse return error.TextureUnavailable;
        try self.sheets.append(self.allocator, sheet);
        return @intCast(self.sheets.items.len);
    }

    pub fn setHighlight(self: *WorldRenderer, tile: ?GridPos, color: Color) void {
        self.highlight = tile;
        self.highlight_color = color;
    }

    pub fn draw(self: *WorldRenderer, map: *TileMap, world: *World, cam: *IsoCamera, lm: *const LightMap, ov: *Overlays) void {
        self.chunks_rebuilt_last = 0;
        self.chunks_drawn_last = 0;
        if (self.atlas != null) {
            self.ensureChunks(map, lm);
            map.dirty = false;
        }
        self.rebuildOverlays(map, ov);
        self.rebuildSprites(world, cam);
        self.rebuildHighlight(map);

        const mats = graphics.CameraMatrices{
            .view = cam.view,
            .proj = camera_mod.remapDepthToBackHalf(cam.proj),
        };
        for (self.chunks.items) |*c| {
            if (c.quads == 0) continue;
            if (!tilemesh.chunkVisible(cam, c.bounds)) continue;
            if (c.batch) |*b| {
                b.draw(mats, Mat4.identity);
                self.chunks_drawn_last += 1;
            }
        }
        self.ov_batch.draw(mats, Mat4.identity);
        self.sprite_batch.draw(mats, Mat4.identity);
        self.hl_batch.draw(mats, Mat4.identity);
    }

    fn ensureChunks(self: *WorldRenderer, map: *TileMap, lm: *const LightMap) void {
        const atlas = self.atlas orelse return;
        const mat = self.materialFor(atlas.texture_handle) orelse return;
        const need = @as(usize, map.chunks_w) * map.chunks_h;
        if (self.chunks.items.len != need) {
            self.dropChunks();
            self.chunks.resize(self.allocator, need) catch return;
            for (self.chunks.items) |*c| c.* = .{};
            map.markAllDirty();
        }

        const tint_a = self.tint.toArray();
        var cy: u32 = 0;
        while (cy < map.chunks_h) : (cy += 1) {
            var cx: u32 = 0;
            while (cx < map.chunks_w) : (cx += 1) {
                const ci = @as(usize, cy) * map.chunks_w + cx;
                const chunk = &self.chunks.items[ci];
                if (!map.chunk_dirty[ci] and chunk.batch != null) continue;

                tilemesh.buildChunk(self.allocator, map, lm.rgb, cx, cy, .{}, &self.chunk_quad_scratch) catch continue;
                chunk.bounds = tilemesh.chunkBounds(map, cx, cy);

                var n_quads: usize = self.chunk_quad_scratch.items.len;
                if (n_quads > max_quads_per_batch) {
                    if (!self.warned_tiles) {
                        self.warned_tiles = true;
                        debug.warning("iso: chunk quad budget ({d}) exceeded, remaining quads skipped", .{max_quads_per_batch});
                    }
                    n_quads = max_quads_per_batch;
                }
                chunk.quads = @intCast(n_quads);

                if (n_quads > 0) {
                    const need_v = n_quads * 4;
                    const need_i = n_quads * 6;
                    if (chunk.batch == null or chunk.batch.?.vertex_buffer.len < need_v or chunk.batch.?.index_buffer.len < need_i) {
                        if (chunk.batch) |*old| old.deinit();
                        chunk.batch = batcher.Batcher.init(.{
                            .material = mat,
                            .min_vertices = @max(@as(usize, 256), need_v),
                            .min_indices = @max(@as(usize, 384), need_i),
                        }) catch null;
                    }
                    if (chunk.batch) |*b| {
                        b.reset();
                        for (self.chunk_quad_scratch.items[0..n_quads], 0..) |q, qi| {
                            const reg = atlas.region(q.atlas);
                            const v0 = reg.v + (reg.v_2 - reg.v) * q.v_top;
                            const v1 = reg.v + (reg.v_2 - reg.v) * q.v_bot;
                            const uvs = [4][2]f32{
                                .{ reg.u, v1 },
                                .{ reg.u_2, v1 },
                                .{ reg.u_2, v0 },
                                .{ reg.u, v0 },
                            };
                            const v_base = qi * 4;
                            for (0..4) |vi| {
                                const col = [4]f32{
                                    (@as(f32, @floatFromInt(q.c[vi][0])) / 255.0) * tint_a[0],
                                    (@as(f32, @floatFromInt(q.c[vi][1])) / 255.0) * tint_a[1],
                                    (@as(f32, @floatFromInt(q.c[vi][2])) / 255.0) * tint_a[2],
                                    tint_a[3],
                                };
                                b.vertex_buffer[v_base + vi] = .{
                                    .x = q.p[vi][0],
                                    .y = q.p[vi][1],
                                    .z = q.p[vi][2],
                                    .color = col,
                                    .u = uvs[vi][0],
                                    .v = uvs[vi][1],
                                };
                            }
                            const i_base = qi * 6;
                            const vb: u32 = @intCast(v_base);
                            b.index_buffer[i_base + 0] = vb + 0;
                            b.index_buffer[i_base + 1] = vb + 1;
                            b.index_buffer[i_base + 2] = vb + 2;
                            b.index_buffer[i_base + 3] = vb + 0;
                            b.index_buffer[i_base + 4] = vb + 2;
                            b.index_buffer[i_base + 5] = vb + 3;
                        }
                        b.vertex_pos = need_v;
                        b.index_pos = need_i;
                        b.apply();
                    }
                } else if (chunk.batch) |*b| {
                    b.reset();
                    b.apply();
                }

                map.chunk_dirty[ci] = false;
                self.chunks_rebuilt_last += 1;
            }
        }

        var total: u32 = 0;
        for (self.chunks.items) |c| total += c.quads;
        self.tile_quads = total;
    }

    fn rebuildOverlays(self: *WorldRenderer, map: *const TileMap, ov: *Overlays) void {
        if (!ov.dirty) return;
        ov.dirty = false;
        const b = &self.ov_batch;
        b.reset();
        const ov_atlas_mat: ?graphics.Material = if (self.atlas) |a| self.overlayMaterialFor(a.texture_handle) else null;

        var quads: u32 = 0;
        for (ov.groups) |g| {
            for (g.items) |cell| {
                if (quads >= max_quads_per_batch) break;
                const gx: i32 = cell.x;
                const gy: i32 = cell.y;
                if (!map.inBounds(gx, gy)) continue;
                const y = map.topY(gx, gy) + 0.008;
                const col = Color.newBytes(cell.rgba[0], cell.rgba[1], cell.rgba[2], cell.rgba[3]);
                const m = Mat4.translate(Vec3.new(@floatFromInt(gx), y, @floatFromInt(gy + 1))).mul(Mat4.rotate(-90, Vec3.x_axis));
                b.setTransformMatrix(m);
                if (cell.atlas != 0xFFFF and self.atlas != null and ov_atlas_mat != null) {
                    b.useMaterial(ov_atlas_mat.?);
                    b.addRectangle(Rect.new(Vec2.zero, Vec2.new(1, 1)), self.atlas.?.region(cell.atlas), col);
                } else {
                    b.useMaterial(self.hl_material);
                    b.addRectangle(Rect.new(Vec2.zero, Vec2.new(1, 1)), TextureRegion.default(), col);
                }
                quads += 1;
            }
        }
        b.apply();
    }

    fn rebuildSprites(self: *WorldRenderer, world: *World, cam: *const IsoCamera) void {
        const b = &self.sprite_batch;
        b.reset();
        self.sprite_quads = 0;

        const pitch_rad = std.math.degreesToRadians(cam.pitch);
        const vscale = 1.0 / @cos(pitch_rad);
        const rot = camera_mod.billboardRotation(cam.yaw);
        const sc = Mat4.scale(Vec3.new(1, vscale, 1));
        const tint_a = self.tint.toArray();

        var it = world.iterator();
        while (it.next()) |e| {
            if (!e.visible) continue;
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
            const et = e.tint.toArray();
            const l = if (e.lit) e.light else [3]f32{ 1, 1, 1 };
            const col = Color.new(
                et[0] * l[0] * tint_a[0],
                et[1] * l[1] * tint_a[1],
                et[2] * l[2] * tint_a[2],
                et[3] * tint_a[3],
            );
            self.sprite_quads += 1;
            b.addRectangle(rect, sheet.region(e.frame, e.flip_x), col);
        }
        b.apply();
    }

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
                    const m = Mat4.translate(Vec3.new(fx, map.topY(t.x, t.y) + 0.012, fz + 1)).mul(Mat4.rotate(-90, Vec3.x_axis));
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
