-- Suburb house location template (M2-PLAN §2.1, parsed by core/layout.lua).
return {
	id = "suburb_house",
	floor = "wood",
	wall = "brick",
	variants = {
		A = {
			grid = {
				"############",
				"#S...=..T..#",
				"#....=.....#",
				"#....+.....#",
				"#....=.....#",
				"#====#=====#",
				"#.B..=....C#",
				"#....w.....#",
				"#..........#",
				"####D##w####",
			},
			legend = {
				S = { prop = "fac_stove" },
				T = { prop = "furn_table" },
				B = { prop = "furn_bed" },
				C = { prop = "cont_crate" },
			},
			rooms = {
				living  = { x = 2, y = 2 },
				kitchen = { x = 7, y = 2 },
				bedroom = { x = 2, y = 7 },
			},
			lights = {
				{ x = 2, y = 2, radius = 6.5, color = { 1.0, 0.62, 0.28 } },
			},
		},
	},
}
