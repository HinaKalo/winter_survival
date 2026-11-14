# 验收测试，编码代理不得修改（主代理编写；认为有误时停下报告）。docs/M5-3D-PLAN.md §2、§7。
# tools/model_bake.py：glb -> .wsm（WSM1）。用命令行调用（python3 tools/model_bake.py IN OUT）。
import json
import math
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "tools" / "model_bake.py"
ASSET = ROOT / "assets" / "models" / "ranch_a.wsm"
SOURCE = ROOT / "assets_src" / "models" / "ranch_a" / "house_full.glb"


# ---------------------------------------------------------------- reference reader (spec §2)
def read_wsm(data):
    assert data[:4] == b"WSM1", "magic"
    version, n_nodes, n_verts = struct.unpack_from("<III", data, 4)
    off = 16
    nodes = []
    for _ in range(n_nodes):
        (ln,) = struct.unpack_from("<H", data, off)
        off += 2
        name = data[off:off + ln].decode("utf-8")
        off += ln
        first, count = struct.unpack_from("<II", data, off)
        off += 8
        mn = struct.unpack_from("<3f", data, off)
        mx = struct.unpack_from("<3f", data, off + 12)
        off += 24
        nodes.append({"name": name, "first": first, "count": count, "min": mn, "max": mx})
    verts = []
    for _ in range(n_verts):
        x, y, z, nx, ny, nz, pad, r, g, b, a = struct.unpack_from("<3f3bB4B", data, off)
        off += 20
        verts.append({"p": (x, y, z), "n": (nx, ny, nz), "pad": pad, "c": (r, g, b, a)})
    assert off == len(data), "trailing bytes: %d != %d" % (off, len(data))
    return version, nodes, verts


# ---------------------------------------------------------------- tiny glb writer for synthetic inputs
def make_glb(nodes_spec, materials):
    """nodes_spec: list of dict(name, positions=[(x,y,z)...], indices=[...] or None, material=int|None,
    translation=None, scale=None, rotation=None)."""
    bin_chunks = bytearray()
    buffer_views, accessors, meshes, nodes = [], [], [], []

    def add_view(raw, target):
        while len(bin_chunks) % 4:
            bin_chunks.append(0)
        buffer_views.append({"buffer": 0, "byteOffset": len(bin_chunks), "byteLength": len(raw), "target": target})
        bin_chunks.extend(raw)
        return len(buffer_views) - 1

    for spec in nodes_spec:
        pos = spec["positions"]
        raw = b"".join(struct.pack("<3f", *p) for p in pos)
        bv = add_view(raw, 34962)
        mins = [min(p[i] for p in pos) for i in range(3)]
        maxs = [max(p[i] for p in pos) for i in range(3)]
        accessors.append({"bufferView": bv, "componentType": 5126, "count": len(pos), "type": "VEC3",
                          "min": mins, "max": maxs})
        prim = {"attributes": {"POSITION": len(accessors) - 1}}
        if spec.get("indices") is not None:
            idx = spec["indices"]
            bv2 = add_view(b"".join(struct.pack("<H", i) for i in idx), 34963)
            accessors.append({"bufferView": bv2, "componentType": 5123, "count": len(idx), "type": "SCALAR"})
            prim["indices"] = len(accessors) - 1
        if spec.get("material") is not None:
            prim["material"] = spec["material"]
        meshes.append({"name": spec["name"] + "_mesh", "primitives": [prim]})
        node = {"name": spec["name"], "mesh": len(meshes) - 1}
        for k in ("translation", "scale", "rotation"):
            if spec.get(k) is not None:
                node[k] = spec[k]
        nodes.append(node)
    nodes.append({"name": "an_empty"})  # no mesh: must be skipped

    gltf = {
        "asset": {"version": "2.0"},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(nodes)))}],
        "nodes": nodes,
        "meshes": meshes,
        "materials": materials,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(bin_chunks)}],
    }
    js = json.dumps(gltf).encode("utf-8")
    while len(js) % 4:
        js += b" "
    while len(bin_chunks) % 4:
        bin_chunks.append(0)
    total = 12 + 8 + len(js) + 8 + len(bin_chunks)
    out = struct.pack("<4sII", b"glTF", 2, total)
    out += struct.pack("<I4s", len(js), b"JSON") + js
    out += struct.pack("<I4s", len(bin_chunks), b"BIN\x00") + bytes(bin_chunks)
    return out


QUAD = [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)]
QUAD_IDX = [0, 2, 1, 0, 3, 2]  # two triangles, normal +Y
TRI = [(0, 0, 0), (0, 1, 0), (1, 0, 0)]  # non-indexed, normal -Z or +Z

MATS = [
    {"name": "wood_2", "pbrMetallicRoughness": {"baseColorFactor": [0.4, 0.27, 0.18, 1.0]}},
    {"name": "fire_3", "pbrMetallicRoughness": {"baseColorFactor": [0.1, 0.1, 0.1, 1.0]},
     "emissiveFactor": [1.0, 0.76, 0.32]},
]


def run_tool(in_bytes, suffix=".glb"):
    with tempfile.TemporaryDirectory() as d:
        src = Path(d) / ("in" + suffix)
        dst = Path(d) / "out.wsm"
        src.write_bytes(in_bytes)
        p = subprocess.run([sys.executable, str(TOOL), str(src), str(dst)], capture_output=True, text=True)
        data = dst.read_bytes() if dst.exists() else None
        return p.returncode, p.stdout + p.stderr, data


def synthetic():
    return make_glb([
        {"name": "zeta_floor", "positions": QUAD, "indices": QUAD_IDX, "material": 0, "translation": [10, 0, 5]},
        {"name": "alpha_fire", "positions": TRI, "indices": None, "material": 1, "scale": [2, 2, 2]},
        {"name": "mid_plain", "positions": TRI, "indices": None, "material": None,
         # 90 deg about +Y: (x, y, z) -> (z, y, -x)
         "rotation": [0, math.sin(math.pi / 4), 0, math.cos(math.pi / 4)]},
    ], MATS)


class BakeFormat(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rc, cls.log, cls.data = run_tool(synthetic())

    def test_tool_succeeds(self):
        self.assertEqual(self.rc, 0, self.log)
        self.assertIsNotNone(self.data)

    def test_header_and_nodes_sorted_mesh_only(self):
        version, nodes, verts = read_wsm(self.data)
        self.assertEqual(version, 1)
        self.assertEqual([n["name"] for n in nodes], ["alpha_fire", "mid_plain", "zeta_floor"])
        self.assertEqual(len(verts), 3 + 3 + 6)

    def test_vertex_ranges_contiguous(self):
        _, nodes, verts = read_wsm(self.data)
        nxt = 0
        for n in nodes:
            self.assertEqual(n["first"], nxt)
            self.assertEqual(n["count"] % 3, 0)
            nxt += n["count"]
        self.assertEqual(nxt, len(verts))

    def node(self, name):
        _, nodes, verts = read_wsm(self.data)
        n = [x for x in nodes if x["name"] == name][0]
        return n, verts[n["first"]:n["first"] + n["count"]]

    def test_translation_applied_and_bounds(self):
        n, vs = self.node("zeta_floor")
        xs = sorted({round(v["p"][0], 4) for v in vs})
        zs = sorted({round(v["p"][2], 4) for v in vs})
        self.assertEqual(xs, [10.0, 11.0])
        self.assertEqual(zs, [5.0, 6.0])
        self.assertAlmostEqual(n["min"][0], 10.0, places=4)
        self.assertAlmostEqual(n["max"][2], 6.0, places=4)
        for v in vs:
            self.assertEqual(v["pad"], 0)

    def test_scale_applied(self):
        n, vs = self.node("alpha_fire")
        self.assertAlmostEqual(n["max"][1], 2.0, places=4)
        self.assertAlmostEqual(n["max"][0], 2.0, places=4)

    def test_rotation_applied(self):
        n, vs = self.node("mid_plain")
        # TRI x in [0,1] rotates to z in [-1,0]
        self.assertAlmostEqual(n["min"][2], -1.0, places=3)
        self.assertAlmostEqual(n["max"][2], 0.0, places=3)
        self.assertAlmostEqual(n["max"][0], 0.0, places=3)

    def test_flat_normals(self):
        _, vs = self.node("zeta_floor")
        for v in vs:
            self.assertEqual(v["n"], (0, 127, 0))
        _, vs = self.node("alpha_fire")
        for v in vs:
            self.assertEqual(abs(v["n"][2]), 127)
            self.assertEqual(v["n"][0], 0)
            self.assertEqual(v["n"][1], 0)

    def test_colors(self):
        _, vs = self.node("zeta_floor")
        self.assertEqual(vs[0]["c"], (102, 69, 46, 255))
        _, vs = self.node("alpha_fire")
        self.assertEqual(vs[0]["c"], (255, 194, 82, 128))  # emissive
        _, vs = self.node("mid_plain")
        self.assertEqual(vs[0]["c"], (200, 200, 200, 255))  # no material

    def test_deterministic(self):
        _, _, again = run_tool(synthetic())
        self.assertEqual(self.data, again)


class BakeErrors(unittest.TestCase):
    def test_not_a_glb(self):
        rc, log, _ = run_tool(b"hello world, not a glb at all")
        self.assertNotEqual(rc, 0)
        self.assertTrue(log.strip())

    def test_index_out_of_range(self):
        bad = make_glb([{"name": "bad", "positions": TRI, "indices": [0, 1, 7], "material": None}], MATS)
        rc, log, _ = run_tool(bad)
        self.assertNotEqual(rc, 0)


REQUIRED = [
    "B1_floor", "B1_wall_low", "B1_wall_high", "B1_boiler_on", "B1_boiler_off",
    "F1_floor", "F1_wall_low", "F1_wall_high", "F1_woodstove_on", "F1_woodstove_off",
    "F1_hearth_on", "F1_hearth_off",
    "F1_rubble_01", "F1_rubble_02", "F1_rubble_03", "F1_rubble_04", "F1_rubble_05", "F1_rubble_06",
    "F2_floor", "F2_wall_low", "F2_wall_high", "stair_B1_1F", "stair_1F_2F",
]


class RealAsset(unittest.TestCase):
    def test_source_present(self):
        self.assertTrue(SOURCE.exists(), SOURCE)

    def test_asset_baked_and_current(self):
        self.assertTrue(ASSET.exists(), ASSET)
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "x.wsm"
            p = subprocess.run([sys.executable, str(TOOL), str(SOURCE), str(out)], capture_output=True, text=True)
            self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
            self.assertEqual(out.read_bytes(), ASSET.read_bytes(), "assets/models/ranch_a.wsm is stale; re-bake")

    def test_asset_contents(self):
        _, nodes, verts = read_wsm(ASSET.read_bytes())
        names = {n["name"] for n in nodes}
        for r in REQUIRED:
            self.assertIn(r, names)
        self.assertLessEqual(len(verts) // 3, 30000)
        for v in verts:
            x, y, z = v["p"]
            self.assertTrue(-4 <= x <= 24 and -4 <= z <= 18 and -4 <= y <= 8, v["p"])


if __name__ == "__main__":
    unittest.main()
