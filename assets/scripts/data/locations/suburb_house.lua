-- Suburb house location template (M2-PLAN §2.1, parsed by core/layout.lua).
-- Variant A is copied verbatim from WORLD.md "suburb_house 布局 A（米勒家）".
return {
	id = "suburb_house",
	floor = "wood",
	wall = "brick",
	variants = {
		A = {
			grid = {
				"##########+###",
				"#K.K..#B..B..#",
				"#...T.#......#",
				"####+##...b..#",
				"#L...L+###+###",
				"#..S..#C.....#",
				"#..f..+...w..#",
				"####D#########",
			},
			-- K 厨房台面(food)  T 餐桌  B 床  b 婴儿床  L 客厅标记(地面)  S 沙发  f 壁炉  C 衣橱
			-- w 窗  D 前门  + 内门（外缘上的 + 是后门，由 mapbuild 按相邻外部判定）
			legend = {
				K = { prop = "counter", slot = "food" },
				T = { prop = "table" },
				B = { prop = "bed" },
				b = { prop = "crib" },
				L = { prop = "living_mark" },
				S = { prop = "sofa" },
				f = { prop = "fireplace" },
				C = { prop = "wardrobe" },
			},
			rooms = {
				kitchen = { x = 2, y = 1 },
				living  = { x = 2, y = 5 },
				bedroom = { x = 8, y = 2 },
			},
			-- source = key of data/lights.lua (ART-AUDIO §3.3); radius/colour come from that table.
			lights = {
				{ source = "lamp", x = 2, y = 2 },
			},
		},
	},
}
