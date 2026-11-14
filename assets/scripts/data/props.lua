-- Prop table for view/mapbuild (M2-PLAN §5.1): every prop cell is blocked; `opaque` decides line of sight.
-- sprite = placeholder billboard of final size (w x h px, `cols` frames). `marker = true` entries are
-- room-label letters in templates (not real props): they become plain floor, no billboard, not blocked.
local P_TABLE = "assets/sprites/props/furn_table.png"
local P_BED = "assets/sprites/props/furn_bed.png"
local P_STOVE = "assets/sprites/props/fac_stove.png"
local P_CRATE = "assets/sprites/props/cont_crate.png"

return {
	-- indoor furniture (placeholder sprites reuse the closest pilot art)
	counter    = { opaque = false, sprite = P_TABLE, w = 64, h = 64, cols = 2, frame = 0 },
	table      = { opaque = false, sprite = P_TABLE, w = 64, h = 64, cols = 2, frame = 0 },
	bed        = { opaque = false, sprite = P_BED,   w = 64, h = 64, cols = 3, frame = 0 },
	crib       = { opaque = false, sprite = P_BED,   w = 64, h = 64, cols = 3, frame = 0 },
	sofa       = { opaque = false, sprite = P_BED,   w = 64, h = 64, cols = 3, frame = 0 },
	fireplace  = { opaque = true,  sprite = P_STOVE, w = 64, h = 64, cols = 3, frame = 1 },
	wardrobe   = { opaque = true,  sprite = P_CRATE, w = 32, h = 32, cols = 3, frame = 0 },
	bookshelf  = { opaque = true,  sprite = P_CRATE, w = 32, h = 32, cols = 3, frame = 0 },
	fridge     = { opaque = true,  sprite = P_STOVE, w = 64, h = 64, cols = 3, frame = 0 },
	living_mark = { marker = true },
	-- legacy ids
	fac_stove  = { opaque = false, sprite = P_STOVE, w = 64, h = 64, cols = 3, frame = 1 },
	furn_table = { opaque = false, sprite = P_TABLE, w = 64, h = 64, cols = 2, frame = 0 },
	furn_bed   = { opaque = false, sprite = P_BED,   w = 64, h = 64, cols = 3, frame = 0 },
	cont_crate = { opaque = false, sprite = P_CRATE, w = 32, h = 32, cols = 3, frame = 0 },
	-- outdoor (entity-only props listed in a template's `props`; they do not occupy a grid symbol)
	out_tree_dead   = { opaque = false, sprite = "assets/sprites/props/out_tree_dead.png",   w = 64, h = 96, cols = 2, frame = 1 },
	out_car         = { opaque = false, sprite = "assets/sprites/props/out_car.png",         w = 96, h = 64, cols = 3, frame = 1 },
	out_streetlight = { opaque = false, sprite = "assets/sprites/props/out_streetlight.png", w = 32, h = 96, cols = 2, frame = 1 },
}
