-- 家园模板 ranch_a（GDD §1.5）。20×14 的独栋住宅，四个房间 + 室内门。
-- 网格行 = y，列 = x；' ' = 地图外。图例见 data/legend.lua。
-- damage 由 sim/home.lua 施加：broken_windows / wall_holes 是格子坐标。
return {
  id = "ranch_a",
  variants = {
    A = {
      grid = {
        "####################",
        "#........#.........#",
        "#........#.........#",
        "#........#.........w",
        "#........+.........#",
        "#........#.........#",
        "#........#.........#",
        "####+##########+####",
        "#........#.........#",
        "w........#.........#",
        "#........+.........#",
        "#........#.........w",
        "#........#.........#",
        "############D#######",
      },
      floor = "wood",
      wall = "siding",
      rooms = {
        bedroom = { x = 3, y = 3 },
        living = { x = 12, y = 3 },
        kitchen = { x = 3, y = 10 },
        workshop = { x = 12, y = 10 },
      },
      damage = {
        broken_windows = { { 19, 3 }, { 0, 9 } },
        wall_holes = { { 17, 0 } },
        door_open = {},
      },
      stations = {
        { id = "f_hearth", kind = "hearth", room = "kitchen", hp = 100, on = false },
        { id = "f_electric_heater", kind = "electric_heater", room = "living", hp = 0, on = false },
        { id = "f_generator", kind = "generator", room = "workshop", hp = 0, on = false },
        { id = "f_humidifier", kind = "humidifier", room = "living", hp = 0, on = false },
        { id = "f_bed", kind = "bed", room = "bedroom", hp = 100, on = true },
        { id = "f_woodstove", kind = "woodstove", room = "living", hp = 100, on = false, level = "low" },
      },
      storage = { room = "living", slots = 60 },
      rubble = 70,
      cold_cell_cells = 6,
    },
  },
}
