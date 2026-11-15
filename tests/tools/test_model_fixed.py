# 验收测试，编码代理不得修改（主代理编写；认为有误时停下报告）。docs/M5-FIX-PLAN.md §2、§5。
# 修复后家具 / 木板的模型资产约束：节点齐全、位置贴着原物、尺寸和面数在预算内、"勉强可用"的拼凑感（多种颜色）。
import struct
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ASSET = ROOT / "assets" / "models" / "ranch_a.wsm"

FIXED = ["F1_electric_heater", "F1_generator", "F1_humidifier"]
WINDOWS = {  # node -> (floor y of that level, window node it covers)
    "B1_window_board_3_13": "B1_window_3_13",
    "B1_window_board_12_13": "B1_window_12_13",
    "F1_window_board_0_9": "F1_window_0_9",
    "F1_window_board_19_3": "F1_window_19_3",
    "F1_window_board_19_11": "F1_window_19_11",
    "F2_window_board_0_6": "F2_window_0_6",
    "F2_window_board_19_6": "F2_window_19_6",
}
FLOOR_Y = {"B1": -3.0, "F1": 0.0, "F2": 3.0}


def read_wsm(data):
    assert data[:4] == b"WSM1"
    _, n_nodes, n_verts = struct.unpack_from("<III", data, 4)
    off, nodes = 16, {}
    for _ in range(n_nodes):
        (ln,) = struct.unpack_from("<H", data, off)
        off += 2
        name = data[off:off + ln].decode("utf-8")
        off += ln
        first, count = struct.unpack_from("<II", data, off)
        mn = struct.unpack_from("<3f", data, off + 8)
        mx = struct.unpack_from("<3f", data, off + 20)
        off += 32
        nodes[name] = {"first": first, "count": count, "min": mn, "max": mx}
    colors = []
    for _ in range(n_verts):
        r, g, b, a = struct.unpack_from("<4B", data, off + 16)
        colors.append((r, g, b, a))
        off += 20
    return nodes, colors


class FixedModelAssets(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.nodes, cls.colors = read_wsm(ASSET.read_bytes())

    def node(self, name):
        self.assertTrue(name in self.nodes, "missing node " + name)
        return self.nodes[name]

    def test_wrecks_are_kept(self):
        for base in FIXED:
            n = self.node(base)
            self.assertLess(n["max"][1] - n["min"][1], 0.2, base + " wreck stays a flat pile")

    def test_fixed_stations_stand_where_the_wreck_lies(self):
        for base in FIXED:
            w, f = self.node(base), self.node(base + "_fixed")
            wc = [(w["min"][i] + w["max"][i]) / 2 for i in (0, 2)]
            fc = [(f["min"][i] + f["max"][i]) / 2 for i in (0, 2)]
            self.assertLess(max(abs(wc[0] - fc[0]), abs(wc[1] - fc[1])), 0.6, base + "_fixed centred on its wreck")
            self.assertGreaterEqual(f["min"][1], -0.02, base + "_fixed sits on the 1F floor")
            self.assertLess(f["min"][1], 0.15, base + "_fixed touches the floor")
            h = f["max"][1] - f["min"][1]
            self.assertTrue(0.35 <= h <= 1.6, "%s_fixed is a standing object (h=%.2f)" % (base, h))
            for i in (0, 2):
                self.assertLessEqual(f["max"][i] - f["min"][i], 1.4, base + "_fixed footprint within ~1 cell")

    def test_fixed_stations_look_patched_together(self):
        for base in FIXED:
            f = self.node(base + "_fixed")
            tris = f["count"] // 3
            self.assertTrue(48 <= tris <= 900, "%s_fixed tris %d in [48, 900]" % (base, tris))
            cols = {c[:3] for c in self.colors[f["first"]:f["first"] + f["count"]]}
            self.assertGreaterEqual(len(cols), 3, base + "_fixed mixes at least 3 colours (patches, tape, scrap)")
            self.assertTrue(all(c[3] != 128 for c in self.colors[f["first"]:f["first"] + f["count"]]),
                            base + "_fixed is not emissive")

    def test_every_window_has_a_board(self):
        for board, win in WINDOWS.items():
            b, w = self.node(board), self.node(win)
            floor = board.split("_")[0]
            self.assertGreater(b["min"][1], FLOOR_Y[floor] - 0.1, board + " on its own level")
            for i in range(3):
                self.assertGreater(b["max"][i], w["min"][i] - 0.2, board + " overlaps its window")
                self.assertLess(b["min"][i], w["max"][i] + 0.2, board + " overlaps its window")
            # spans the opening: along the wall and vertically
            wall_axis = 2 if (w["max"][0] - w["min"][0]) < (w["max"][2] - w["min"][2]) else 0
            span = b["max"][wall_axis] - b["min"][wall_axis]
            self.assertGreaterEqual(span, 0.7 * (w["max"][wall_axis] - w["min"][wall_axis]), board + " spans the width")
            self.assertGreaterEqual(b["max"][1] - b["min"][1], 0.6 * (w["max"][1] - w["min"][1]),
                                    board + " spans the height")
            tris = b["count"] // 3
            self.assertTrue(24 <= tris <= 400, "%s tris %d: at least two planks, cheap" % (board, tris))

    def test_hole_board(self):
        b = self.node("F1_hole_board_17_0")
        self.assertLess(b["min"][0], 17.9)
        self.assertGreater(b["max"][0], 17.1)
        self.assertLess(b["min"][2], 0.8)
        self.assertGreater(b["max"][2], -0.3)
        self.assertGreaterEqual(b["min"][1], -0.05)
        self.assertGreaterEqual(b["max"][1] - b["min"][1], 1.0, "covers a person-sized hole")
        tris = b["count"] // 3
        self.assertTrue(36 <= tris <= 600, "hole board tris %d" % tris)

    def test_budget(self):
        total = sum(n["count"] for n in self.nodes.values()) // 3
        added = sum(self.nodes[n]["count"] for n in self.nodes
                    if n.endswith("_fixed") or "_window_board_" in n or n.startswith("F1_hole_board")) // 3
        self.assertLessEqual(added, 6000, "repair pass adds <= 6k triangles (got %d)" % added)
        self.assertLessEqual(total, 40000, "whole house stays <= 40k triangles (got %d)" % total)


if __name__ == "__main__":
    unittest.main()
