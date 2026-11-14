#!/usr/bin/env python3
"""Bake a binary glTF 2.0 (.glb) into the WSM1 mesh format (docs/M5-3D-PLAN.md section 2).

Usage: python3 tools/model_bake.py IN.glb OUT.wsm
Python 3.10+, stdlib only. Output is deterministic.
"""
import json
import math
import os
import struct
import sys

COMPONENT = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
TYPE_COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}
DEFAULT_COLOR = (200, 200, 200, 255)
IDENTITY = [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]  # column-major


class BakeError(Exception):
    pass


def parse_glb(data):
    if len(data) < 20 or data[:4] != b"glTF":
        raise BakeError("not a binary glTF (.glb) file")
    version, length = struct.unpack_from("<II", data, 4)
    if version != 2:
        raise BakeError("unsupported glTF container version %d" % version)
    if length > len(data):
        raise BakeError("truncated glb (header says %d bytes, file has %d)" % (length, len(data)))
    pos, js, binc = 12, None, None
    while pos + 8 <= length:
        clen, ctype = struct.unpack_from("<I4s", data, pos)
        body = data[pos + 8:pos + 8 + clen]
        if len(body) != clen:
            raise BakeError("truncated glb chunk")
        if ctype == b"JSON" and js is None:
            js = body
        elif ctype == b"BIN\x00" and binc is None:
            binc = body
        pos += 8 + clen + (-clen % 4)
    if js is None:
        raise BakeError("glb has no JSON chunk")
    try:
        gltf = json.loads(js.decode("utf-8"))
    except ValueError as e:
        raise BakeError("invalid glTF JSON: %s" % e)
    if not isinstance(gltf, dict):
        raise BakeError("glTF JSON is not an object")
    return gltf, binc


def read_accessor(gltf, binc, index):
    try:
        acc = gltf["accessors"][index]
        ctype = acc["componentType"]
        count = acc["count"]
        ncomp = TYPE_COUNT[acc["type"]]
        fmt, csize = COMPONENT[ctype]
    except (KeyError, IndexError, TypeError):
        raise BakeError("invalid accessor %r" % (index,))
    if "bufferView" not in acc:
        return [(0,) * ncomp for _ in range(count)]
    try:
        bv = gltf["bufferViews"][acc["bufferView"]]
        buf = gltf["buffers"][bv.get("buffer", 0)]
    except (KeyError, IndexError, TypeError):
        raise BakeError("accessor %d: bad bufferView" % index)
    if bv.get("buffer", 0) != 0 or "uri" in buf:
        raise BakeError("accessor %d: only the embedded GLB buffer is supported" % index)
    if binc is None:
        raise BakeError("glb has no BIN chunk")
    elem = csize * ncomp
    stride = bv.get("byteStride") or elem
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    if count and base + stride * (count - 1) + elem > len(binc):
        raise BakeError("accessor %d reads past the end of the buffer" % index)
    st = struct.Struct("<" + fmt * ncomp)
    return [st.unpack_from(binc, base + i * stride) for i in range(count)]


def mat_mul(a, b):
    return [sum(a[k * 4 + r] * b[c * 4 + k] for k in range(4)) for c in range(4) for r in range(4)]


def node_local(node):
    if "matrix" in node:
        m = node["matrix"]
        if not isinstance(m, list) or len(m) != 16:
            raise BakeError("node %r: bad matrix" % node.get("name"))
        return [float(v) for v in m]
    tx, ty, tz = node.get("translation", [0, 0, 0])
    qx, qy, qz, qw = node.get("rotation", [0, 0, 0, 1])
    sx, sy, sz = node.get("scale", [1, 1, 1])
    n = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw) or 1.0
    qx, qy, qz, qw = qx / n, qy / n, qz / n, qw / n
    r00 = 1 - 2 * (qy * qy + qz * qz)
    r01 = 2 * (qx * qy - qz * qw)
    r02 = 2 * (qx * qz + qy * qw)
    r10 = 2 * (qx * qy + qz * qw)
    r11 = 1 - 2 * (qx * qx + qz * qz)
    r12 = 2 * (qy * qz - qx * qw)
    r20 = 2 * (qx * qz - qy * qw)
    r21 = 2 * (qy * qz + qx * qw)
    r22 = 1 - 2 * (qx * qx + qy * qy)
    return [r00 * sx, r10 * sx, r20 * sx, 0.0,
            r01 * sy, r11 * sy, r21 * sy, 0.0,
            r02 * sz, r12 * sz, r22 * sz, 0.0,
            tx, ty, tz, 1.0]


def transform(m, p):
    x, y, z = p
    return (m[0] * x + m[4] * y + m[8] * z + m[12],
            m[1] * x + m[5] * y + m[9] * z + m[13],
            m[2] * x + m[6] * y + m[10] * z + m[14])


def determinant3(m):
    return (m[0] * (m[5] * m[10] - m[9] * m[6])
            - m[4] * (m[1] * m[10] - m[9] * m[2])
            + m[8] * (m[1] * m[6] - m[5] * m[2]))


def clamp_byte(v):
    return max(0, min(255, int(v * 255 + 0.5)))


def material_color(gltf, index):
    if index is None:
        return DEFAULT_COLOR
    try:
        mat = gltf["materials"][index]
    except (KeyError, IndexError, TypeError):
        raise BakeError("invalid material index %r" % (index,))
    em = mat.get("emissiveFactor")
    if em and any(v != 0 for v in em[:3]):
        return (clamp_byte(em[0]), clamp_byte(em[1]), clamp_byte(em[2]), 128)
    base = mat.get("pbrMetallicRoughness", {}).get("baseColorFactor", [1, 1, 1, 1])
    return (clamp_byte(base[0]), clamp_byte(base[1]), clamp_byte(base[2]), 255)


def flat_normal(a, b, c):
    ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
    nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    ln = math.sqrt(nx * nx + ny * ny + nz * nz)
    if not ln > 1e-12:
        return (0, 127, 0)
    return (round(nx / ln * 127), round(ny / ln * 127), round(nz / ln * 127))


def f32(v):
    return struct.unpack("<f", struct.pack("<f", v))[0]


def bake(data):
    gltf, binc = parse_glb(data)
    nodes = gltf.get("nodes", [])
    meshes = gltf.get("meshes", [])
    if not isinstance(nodes, list):
        raise BakeError("glTF 'nodes' is not a list")

    world = [None] * len(nodes)

    def visit(i, parent, stack):
        if not isinstance(i, int) or not 0 <= i < len(nodes):
            raise BakeError("invalid node index %r" % (i,))
        if i in stack:
            raise BakeError("node hierarchy has a cycle")
        w = mat_mul(parent, node_local(nodes[i]))
        world[i] = w
        for c in nodes[i].get("children", []):
            visit(c, w, stack | {i})

    scenes = gltf.get("scenes")
    if scenes:
        roots = scenes[gltf.get("scene", 0)].get("nodes", [])
    else:
        child_set = {c for n in nodes for c in n.get("children", [])}
        roots = [i for i in range(len(nodes)) if i not in child_set]
    for r in roots:
        visit(r, IDENTITY, frozenset())

    records = []
    for i, node in enumerate(nodes):
        if "mesh" not in node or world[i] is None:
            continue
        try:
            mesh = meshes[node["mesh"]]
        except (IndexError, TypeError):
            raise BakeError("node %r: invalid mesh index" % node.get("name"))
        name = node.get("name") or "node_%d" % i
        m = world[i]
        flip = determinant3(m) < 0
        verts = []
        for prim in mesh.get("primitives", []):
            if prim.get("mode", 4) != 4:
                continue
            pos_idx = prim.get("attributes", {}).get("POSITION")
            if pos_idx is None:
                raise BakeError("node %r: primitive has no POSITION" % name)
            pos = read_accessor(gltf, binc, pos_idx)
            if prim.get("indices") is not None:
                idx = [t[0] for t in read_accessor(gltf, binc, prim["indices"])]
            else:
                idx = list(range(len(pos)))
            for k in idx:
                if k >= len(pos):
                    raise BakeError("node %r: index %d out of range (%d vertices)" % (name, k, len(pos)))
            if len(idx) % 3:
                raise BakeError("node %r: index count %d is not a multiple of 3" % (name, len(idx)))
            color = material_color(gltf, prim.get("material"))
            for t in range(0, len(idx), 3):
                tri = [transform(m, pos[idx[t + j]][:3]) for j in range(3)]
                if flip:
                    tri[1], tri[2] = tri[2], tri[1]
                tri = [tuple(f32(c) for c in p) for p in tri]
                nrm = flat_normal(*tri)
                for p in tri:
                    verts.append((p, nrm, color))
        if verts:
            records.append((name.encode("utf-8"), i, verts))
    records.sort(key=lambda r: (r[0], r[1]))

    nodes_blob = bytearray()
    verts_blob = bytearray()
    first = 0
    for name, _i, verts in records:
        mn = [min(v[0][a] for v in verts) for a in range(3)]
        mx = [max(v[0][a] for v in verts) for a in range(3)]
        nodes_blob += struct.pack("<H", len(name)) + name
        nodes_blob += struct.pack("<II3f3f", first, len(verts), *mn, *mx)
        for p, n, c in verts:
            verts_blob += struct.pack("<3f3bB4B", p[0], p[1], p[2], n[0], n[1], n[2], 0, *c)
        first += len(verts)
    return struct.pack("<4sIII", b"WSM1", 1, len(records), first) + bytes(nodes_blob) + bytes(verts_blob)


def main(argv):
    if len(argv) != 3:
        print("usage: model_bake.py IN.glb OUT.wsm", file=sys.stderr)
        return 2
    try:
        with open(argv[1], "rb") as f:
            data = f.read()
    except OSError as e:
        print("model_bake: cannot read %s: %s" % (argv[1], e), file=sys.stderr)
        return 1
    try:
        out = bake(data)
    except BakeError as e:
        print("model_bake: %s: %s" % (argv[1], e), file=sys.stderr)
        return 1
    except (struct.error, KeyError, IndexError, TypeError, ValueError, AttributeError) as e:
        print("model_bake: %s: malformed glTF (%s: %s)" % (argv[1], type(e).__name__, e), file=sys.stderr)
        return 1
    try:
        os.makedirs(os.path.dirname(os.path.abspath(argv[2])), exist_ok=True)
        with open(argv[2], "wb") as f:
            f.write(out)
    except OSError as e:
        print("model_bake: cannot write %s: %s" % (argv[2], e), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
