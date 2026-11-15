"""M5-FIX: patched-together repaired devices, window boards and the wall-hole board (docs/M5-FIX-PLAN.md).

Run:  blender5 -b assets_src/models/ranch_a/house.blend --python assets_src/models/ranch_a/fixed.py
Idempotent (deletes its own previous objects first), deterministic (fixed seed), saves house.blend,
re-exports house_full.glb (+ floor_*.glb when present) with dress.py's export parameters and renders previews.
Blender coords: x east, y = -(game z), z up. Meshes carry world coordinates (identity object matrix).
"""
import bpy, bmesh, math, os, random
from mathutils import Vector, Euler

random.seed(42)
HERE = os.path.dirname(os.path.abspath(bpy.data.filepath))
sc = bpy.context.scene
cols = {n: bpy.data.collections[n] for n in ('B1', 'F1', 'F2', 'ROOF', 'REF', 'DRESS_B1', 'DRESS_F1', 'DRESS_F2')}

WINDOWS = [  # level, x, y, axis of the wall, sign of the interior side
    ('B1', 3, 13, 'x', +1), ('B1', 12, 13, 'x', +1),
    ('F1', 0, 9, 'y', +1), ('F1', 19, 3, 'y', -1), ('F1', 19, 11, 'y', -1),
    ('F2', 0, 6, 'y', +1), ('F2', 19, 6, 'y', -1),
]
FIXED_NAMES = ['F1_electric_heater_fixed', 'F1_generator_fixed', 'F1_humidifier_fixed', 'F1_hole_board_17_0']
BOARD_NAMES = ['%s_window_board_%d_%d' % (l, x, y) for l, x, y, _, _ in WINDOWS]

# ---- idempotence: drop our own previous objects (and the two old F1 boards) ----
for name in FIXED_NAMES + BOARD_NAMES:
    ob = bpy.data.objects.get(name)
    if ob:
        me = ob.data
        bpy.data.objects.remove(ob, do_unlink=True)
        if me and me.users == 0:
            bpy.data.meshes.remove(me)


def P(mat):
    return bpy.data.materials[mat]


class Builder:
    """Boxes / hexagonal-ish cylinders, each with its own euler rotation (degrees) about its centre."""

    def __init__(self):
        self.verts, self.faces, self.mids, self.mats = [], [], [], []

    def _mi(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def _add(self, lv, lf, c, rot, mat):
        e = Euler([math.radians(a) for a in rot], 'XYZ').to_matrix()
        start = len(self.verts)
        for v in lv:
            self.verts.append(Vector(c) + e @ Vector(v))
        mi = self._mi(mat)
        for f in lf:
            self.faces.append(tuple(start + i for i in f))
            self.mids.append(mi)

    def box(self, c, s, mat, rot=(0, 0, 0)):
        a, b, d = s[0] / 2, s[1] / 2, s[2] / 2
        lv = [(-a, -b, -d), (-a, -b, d), (-a, b, -d), (-a, b, d), (a, -b, -d), (a, -b, d), (a, b, -d), (a, b, d)]
        lf = [(0, 2, 6, 4), (1, 5, 7, 3), (0, 4, 5, 1), (2, 3, 7, 6), (0, 1, 3, 2), (4, 6, 7, 5)]
        self._add(lv, lf, c, rot, mat)

    def cyl(self, c, r, h, mat, rot=(0, 0, 0), n=8):
        lv = []
        for z in (-h / 2, h / 2):
            for j in range(n):
                t = 2 * math.pi * j / n
                lv.append((r * math.cos(t), r * math.sin(t), z))
        lf = [tuple(reversed(range(n))), tuple(n + j for j in range(n))]
        for j in range(n):
            lf.append((j, (j + 1) % n, n + (j + 1) % n, n + j))
        self._add(lv, lf, c, rot, mat)

    def transform(self, fn):
        self.verts = [fn(v) for v in self.verts]

    def build(self, name, level, floor_to=None):
        if floor_to is not None:
            lo = min(v.z for v in self.verts)
            self.verts = [Vector((v.x, v.y, v.z - lo + floor_to)) for v in self.verts]
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(v) for v in self.verts], [], self.faces)
        me.update()
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(name, me)
        cols[level].objects.link(ob)
        for m in self.mats:
            me.materials.append(P(m))
        for p, i in zip(me.polygons, self.mids):
            p.material_index = i
        ob['repaired'] = True
        ob['collision'] = False
        ob['floor'] = level
        return ob


def tilt_about(b, pivot, rx, ry, rz):
    e = Euler([math.radians(rx), math.radians(ry), math.radians(rz)], 'XYZ').to_matrix()
    pv = Vector(pivot)
    b.transform(lambda v: pv + e @ (v - pv))


def at(b, ox, oy):
    b.transform(lambda v: Vector((v.x + ox, v.y + oy, v.z)))


# ---------------------------------------------------------------- generator
def generator():
    b = Builder()
    # wood plank under the machine, shimmed up on odd blocks
    b.box((0, 0, 0.07), (0.95, 0.56, 0.04), 'wood_3', (0, 0, 3))
    for x, y, h, m in [(-0.38, -0.2, 0.05, 'wood_1'), (0.38, -0.2, 0.06, 'concrete_3'), (-0.38, 0.2, 0.07, 'wood_2'), (0.36, 0.21, 0.04, 'concrete_2')]:
        b.box((x, y, h / 2), (0.13, 0.12, h), m, (0, 0, x * 40))
    # rusty housing, one panel swapped for a lighter scrap sheet
    b.box((-0.05, 0, 0.28), (0.72, 0.44, 0.34), 'rust_2', (0, 0, -2))
    b.box((-0.05, 0.225, 0.28), (0.55, 0.03, 0.26), 'rust_1', (0, 0, -2))
    b.box((0.22, -0.23, 0.30), (0.26, 0.03, 0.28), 'rust_4', (0, 0, 6))  # mismatched scrap panel, crooked
    b.box((-0.05, 0, 0.47), (0.74, 0.46, 0.04), 'rust_1', (0, 0, -2))
    # replacement fuel drum (different colour) with taped seam
    b.cyl((-0.12, 0.02, 0.69), 0.17, 0.38, 'cloth_b_1', (0, 0, 0))
    b.cyl((-0.12, 0.02, 0.69), 0.18, 0.05, 'cloth_a_2', (0, 0, 0))  # tape band
    b.cyl((-0.12, 0.02, 0.89), 0.06, 0.04, 'rust_3')  # cap
    # pull cord with a taped handle
    b.box((0.36, 0.03, 0.36), (0.08, 0.06, 0.13), 'concrete_3', (0, 0, 0))
    b.box((0.40, 0.03, 0.38), (0.05, 0.05, 0.1), 'wood_4', (0, 15, 0))
    b.box((0.4, 0.03, 0.33), (0.07, 0.07, 0.03), 'cloth_a_2')  # tape on the handle
    # crooked chimney-pipe exhaust
    b.cyl((0.28, -0.1, 0.72), 0.06, 0.55, 'concrete_2', (14, -9, 0))
    b.cyl((0.35, -0.13, 1.0), 0.07, 0.12, 'concrete_3', (22, -9, 0))
    b.box((0.25, -0.08, 0.58), (0.12, 0.05, 0.04), 'cloth_a_2', (0, 0, 20))  # tape on the joint
    # exposed wire loop
    b.box((-0.3, -0.24, 0.3), (0.28, 0.02, 0.02), 'outline_1', (0, 0, 12))
    b.box((-0.45, -0.24, 0.22), (0.02, 0.02, 0.2), 'outline_1', (0, 0, 0))
    b.box((-0.45, -0.24, 0.12), (0.12, 0.02, 0.02), 'rust_4', (0, 0, -10))
    # rag stuffed into the vent
    b.box((-0.3, 0.24, 0.4), (0.18, 0.04, 0.05), 'cloth_a_1', (0, 0, 8))
    tilt_about(b, (0, 0, 0), 3, -4, 0)
    at(b, 12.52, -10.64)
    return b.build('F1_generator_fixed', 'F1', 0.0)


# ---------------------------------------------------------------- electric heater
def heater():
    b = Builder()
    # two wooden blocks shim the feet on the left side; right feet are plain stubs
    b.box((-0.36, 0.0, 0.05), (0.16, 0.24, 0.1), 'wood_3', (0, 0, 6))
    b.box((-0.36, 0.0, 0.13), (0.14, 0.22, 0.06), 'wood_1', (0, 0, -8))
    b.box((0.36, 0.0, 0.04), (0.12, 0.22, 0.08), 'concrete_2')
    # oil radiator: 9 thick fins packed together, one missing, two dented (shorter), one replacement in another colour
    for i in range(9):
        if i == 6:
            continue
        x = -0.42 + i * 0.105
        h = 0.62
        z0 = 0.2
        if i in (2, 7):
            h = 0.5
        m = 'concrete_3'
        if i == 4:
            m = 'rust_3'  # replacement fin
        b.box((x, 0.0, z0 + h / 2), (0.1, 0.22, h), m, (0, 0, 0 if i not in (2, 7) else 3))
    b.box((0, 0.0, 0.84), (0.98, 0.24, 0.05), 'concrete_2')  # top header
    b.box((0, 0.0, 0.17), (0.98, 0.24, 0.05), 'concrete_2')  # bottom header
    b.box((0.55 - 0.05, 0.0, 0.5), (0.04, 0.2, 0.5), 'rust_2', (0, 0, 0))  # side panel, different colour
    # thermostat knob on the top
    b.box((0.38, -0.02, 0.89), (0.12, 0.1, 0.06), 'rust_4', (0, 0, 15))
    b.cyl((0.38, -0.02, 0.94), 0.035, 0.05, 'wood_4', (0, 0, 0), 6)
    # tape bands wrapped round the body
    b.box((0, 0.0, 0.32), (1.0, 0.25, 0.05), 'wood_4')
    b.box((0, 0.0, 0.72), (1.0, 0.25, 0.045), 'cloth_a_2')
    # bare cord from the back down to the floor, taped splice
    b.box((-0.3, 0.13, 0.78), (0.03, 0.03, 0.2), 'outline_1', (0, 0, 0))
    b.box((-0.3, 0.2, 0.58), (0.03, 0.03, 0.5), 'outline_1', (8, 0, 0))
    b.box((-0.3, 0.22, 0.45), (0.06, 0.06, 0.12), 'wood_4')  # splice tape
    b.box((-0.2, 0.3, 0.02), (0.3, 0.03, 0.02), 'outline_1', (0, 0, -14))
    tilt_about(b, (0, 0, 0), -2, 4, 0)
    at(b, 15.57, -6.52)
    return b.build('F1_electric_heater_fixed', 'F1', 0.0)


# ---------------------------------------------------------------- humidifier
def humidifier():
    b = Builder()
    # bucket stood on bricks / wood shims
    for x, y, h, m in [(-0.2, -0.15, 0.08, 'concrete_3'), (0.22, -0.1, 0.06, 'wood_1'), (0.0, 0.2, 0.09, 'concrete_2')]:
        b.box((x, y, h / 2), (0.2, 0.14, h), m, (0, 0, x * 60))
    b.cyl((0, 0, 0.35), 0.25, 0.54, 'cloth_a_1', (0, 0, 0), 10)  # bucket body
    b.cyl((0, 0, 0.62), 0.27, 0.05, 'cloth_a_2', (0, 0, 0), 10)  # rim
    b.cyl((0, 0, 0.66), 0.28, 0.04, 'concrete_3', (4, -3, 0), 10)  # pot lid
    b.cyl((0.03, 0, 0.7), 0.04, 0.05, 'rust_1', (0, 0, 0), 6)  # lid knob
    # scavenged fan on a stick, strapped on with rag + tape
    b.box((0.18, 0.05, 0.93), (0.34, 0.1, 0.34), 'concrete_1', (-6, 5, 7))
    b.box((0.18, 0.0, 0.93), (0.28, 0.02, 0.05), 'concrete_4', (-6, 5, 30))  # blades
    b.box((0.18, 0.0, 0.93), (0.05, 0.02, 0.28), 'concrete_4', (-6, 5, 30))
    b.box((0.18, 0.06, 0.77), (0.06, 0.06, 0.18), 'concrete_2', (0, 0, 0))  # fan neck
    b.box((0.18, 0.05, 0.78), (0.16, 0.08, 0.06), 'cloth_b_2', (0, 0, 12))  # rag
    b.box((0.18, 0.05, 0.86), (0.1, 0.08, 0.04), 'wood_4', (0, 0, -15))  # tape
    # tape band around the bucket, rag strip hanging
    b.cyl((0, 0, 0.3), 0.26, 0.05, 'wood_4', (0, 0, 0), 10)
    b.box((-0.2, -0.22, 0.28), (0.06, 0.03, 0.3), 'cloth_b_1', (0, 0, 8))
    # hose stub and bare wire
    b.cyl((-0.27, 0.05, 0.22), 0.03, 0.3, 'rust_2', (0, 80, 0), 6)
    b.box((0.1, 0.12, 0.74), (0.03, 0.02, 0.1), 'outline_1', (10, 0, 0))
    b.box((0.35, 0.14, 0.35), (0.02, 0.02, 0.55), 'outline_1', (0, 0, 0))
    b.box((0.33, 0.0, 0.06), (0.15, 0.02, 0.02), 'rust_4', (0, 0, 20))
    tilt_about(b, (0, 0, 0), 4, 3, 0)
    at(b, 11.43, -1.49)
    return b.build('F1_humidifier_fixed', 'F1', 0.0)


# ---------------------------------------------------------------- window boards
def to_world(axis, sgn, cx, cy, wall):
    """local (u along wall, d into the room from the wall face, z) -> world."""
    if axis == 'x':
        return lambda u, d, z: (cx + u, wall + sgn * d, z)
    return lambda u, d, z: (wall + sgn * d, cy + u, z)


def window_board(level, wx, wy, axis, sgn):
    name = '%s_window_board_%d_%d' % (level, wx, wy)
    ob = bpy.data.objects['%s_window_%d_%d' % (level, wx, wy)]
    wb = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    lo = [min(v[i] for v in wb) for i in range(3)]
    hi = [max(v[i] for v in wb) for i in range(3)]
    cx, cy = (lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2
    if axis == 'x':
        wall = hi[1] if sgn > 0 else lo[1]
        width = hi[0] - lo[0]
        cu = cx
    else:
        wall = hi[0] if sgn > 0 else lo[0]
        width = hi[1] - lo[1]
        cu = cy
    z0, z1 = lo[2], hi[2]
    H = z1 - z0
    gap = 0.03 if H < 0.8 else 0.06
    ph = (H * 0.96 - 2 * gap) / 3
    # plank boxes in a local frame (u along wall, d depth, z), mapped to world afterwards
    lb = Builder()
    spec = [(0.92, 3, 0.02, 'wood_2'), (1.04, -5, -0.02, 'wood_1'), (0.86, 4, 0.03, 'wood_3')]
    for i, (frac, tilt, du, mat) in enumerate(spec):
        zc = z0 + H * 0.02 + ph / 2 + i * (ph + gap)
        lb.box((du, 0.04, zc), (width * frac, 0.04, ph), mat, (0, tilt, 0))
        for s in (-1, 1):
            lb.box((du + s * width * frac * 0.36, 0.015, zc + (0.01 if s > 0 else -0.01)), (0.035, 0.03, 0.035), 'outline_1', (0, 0, 0))
    # one slanting brace nailed across the planks, in a different wood
    lb.box((0.0, 0.075, z0 + H * 0.5), (0.07, 0.035, H * 0.78), 'wood_4', (0, -22 if wx % 2 else 18, 0))
    f = to_world(axis, sgn, 0.0, 0.0, wall)
    out = Builder()
    out.mats, out.mids, out.faces = lb.mats, lb.mids, lb.faces
    out.verts = [Vector(f(v.x, v.y, v.z)) for v in lb.verts]
    # shift along the wall to the window centre
    out.transform(lambda v: Vector((v.x + cu, v.y, v.z)) if axis == 'x' else Vector((v.x, v.y + cu, v.z)))
    # keep boards just inside the wall face
    nudge = 0.01 * sgn
    out.transform(lambda v: Vector((v.x, v.y + nudge, v.z)) if axis == 'x' else Vector((v.x + nudge, v.y, v.z)))
    return out.build(name, level)


# ---------------------------------------------------------------- hole board (F1 17,0)
def hole_board():
    b = Builder()
    x0, y0 = 17.5, -0.64  # interior face of the north wall, away from the DRESS patch outside it
    d = lambda dd: y0 - dd
    # thick horizontal planks, the hole is about 1.4 wide and person-high
    for i, (w, tilt, m) in enumerate([(1.45, 2, 'wood_2'), (1.5, -3, 'wood_1'), (1.4, 3, 'wood_3'), (1.5, -2, 'wood_2'), (1.35, 4, 'wood_1')]):
        b.box((x0 + 0.01 * i, d(0.05), 0.17 + i * 0.33), (w, 0.08, 0.27), m, (0, tilt, 0))
    # two cross-nailed uprights
    b.box((x0 - 0.42, d(0.13), 0.84), (0.16, 0.07, 1.75), 'wood_3', (0, 4, 0))
    b.box((x0 + 0.38, d(0.13), 0.84), (0.16, 0.07, 1.7), 'wood_4', (0, -5, 0))
    # a sheet of tin and a bit of door slapped on top
    b.box((x0 - 0.1, d(0.19), 0.7), (0.68, 0.03, 0.6), 'rust_2', (0, 8, 0))
    b.box((x0 + 0.05, d(0.21), 1.2), (0.5, 0.03, 0.42), 'concrete_2', (0, -6, 0))
    for dx, z in [(-0.42, 0.25), (-0.42, 0.9), (-0.42, 1.55), (0.38, 0.4), (0.38, 1.05), (0.38, 1.5), (-0.38, 0.7), (0.1, 0.7), (-0.3, 1.2)]:
        b.box((x0 + dx, d(0.22), z), (0.04, 0.04, 0.04), 'outline_1')
    b.box((x0 + 0.62, d(0.1), 0.3), (0.05, 0.03, 0.5), 'cloth_a_1', (0, 0, 12))  # rag stuffed in the gap
    return b.build('F1_hole_board_17_0', 'F1')


generator()
heater()
humidifier()
for spec in WINDOWS:
    window_board(*spec)
hole_board()

for name in FIXED_NAMES + BOARD_NAMES:
    o = bpy.data.objects[name]
    print('NODE', name, len(o.data.polygons), 'quads')

bpy.ops.wm.save_mainfile()


# ---------------------------------------------------------------- export (same parameters as dress.py)
def export(fname, groups):
    for ob in sc.objects:
        ob.hide_set(False)
        ob.select_set(False)
    for group in groups:
        for ob in cols[group].objects:
            if ob.type == 'MESH':
                ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(HERE, fname), export_format='GLB', use_selection=True, export_yup=True, export_cameras=False, export_lights=False, export_extras=True)


for lev in ('B1', 'F1', 'F2'):
    fn = 'floor_' + ('1F' if lev == 'F1' else '2F' if lev == 'F2' else 'B1') + '.glb'
    if os.path.exists(os.path.join(HERE, fn)):
        export(fn, [lev, 'DRESS_' + lev])
export('house_full.glb', ['B1', 'F1', 'F2', 'ROOF', 'DRESS_B1', 'DRESS_F1', 'DRESS_F2'])

# ---------------------------------------------------------------- previews (Workbench close-ups; not saved to the blend)
sc.render.engine = 'BLENDER_WORKBENCH'
sc.render.resolution_x, sc.render.resolution_y = 900, 700
sc.render.resolution_percentage = 100
cam_data = bpy.data.cameras.new('fixed_preview_cam')
cam = bpy.data.objects.new('fixed_preview_cam', cam_data)
sc.collection.objects.link(cam)
sc.camera = cam
cam_data.lens = 50


def preview(fname, show, target, offset):
    for ob in sc.objects:
        ob.hide_render = ob.type == 'MESH' and ob.name not in show
        ob.hide_set(False)
    tgt = Vector(target)
    cam.location = tgt + Vector(offset)
    cam.rotation_euler = (tgt - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = os.path.join(HERE, fname)
    bpy.ops.render.render(write_still=True)


ctr = lambda n: sum(((bpy.data.objects[n].matrix_world @ Vector(c)) for c in bpy.data.objects[n].bound_box), Vector()) / 8
for dev, key in (('electric_heater', 'F1_electric_heater_fixed'), ('generator', 'F1_generator_fixed'), ('humidifier', 'F1_humidifier_fixed')):
    c = ctr(key)
    preview('preview_fixed_%s.png' % dev, {key, key[:-6], 'F1_floor'}, (c.x, c.y, c.z * 0.9), (1.6, -2.4, 1.7))
c = ctr('F1_window_board_19_3')
preview('preview_fixed_window.png', {'F1_window_board_19_3', 'F1_window_19_3', 'F1_wall_low', 'F1_floor'}, (c.x, c.y, c.z), (-2.4, -1.2, 0.3))
