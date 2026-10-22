extends RefCounted
## Destruction quality chosen in Video settings. Static so floor decals and debris
## read one value without a scene reference.
##
## Low:    debris bakes into the floor textures and nothing stays physical.
## Medium: the same, but pieces near the player stay loose and baked pieces wake up
##         (can be pushed and shot) when the player walks up to them.
## High:   several times more floor decals; pieces of a broken object stay in the
##         scene and are only baked once the much larger piece budget is full.

const LOW := 0
const MEDIUM := 1
const HIGH := 2
const COUNT := 3
const DEFAULT := MEDIUM

# Per level: the floor decal queue length, decals applied per frame whatever they cost, decals
# per square metre, and the multiplier for scattered decals and flakes. A frame keeps applying
# queued decals until STAMP_BUDGET_USEC is spent, so a long queue drains fast without a hitch.
const QUEUE_MAX := [256, 512, 2048]
const STAMPS_PER_STEP := [2, 3, 4]
const STAMP_BUDGET_USEC := [0, 2500, 3500]
const DENSITY_CAP := [4, 8, 20]
const SCATTER_PASSES := [1, 1, 3]
const SPECK_SCALE := [1.0, 1.5, 3.0]
# Loose model pieces (a tabletop, a leg) alive at once before the oldest is baked.
const PIECE_BUDGET := [40, 60, 400]
const PIECE_BURST := [120, 160, 600]
# Pieces within this many metres of the player are not baked; 0 bakes every piece on schedule.
const KEEP_NEAR := [0.0, 7.0, 0.0]
# Baked pieces within this many metres of the player become loose bodies again.
const WAKE_NEAR := [0.0, 3.5, 0.0]
const WAKE_PER_CHECK := 3

static var level := DEFAULT


static func set_level(value: int) -> void:
	level = clampi(value, 0, COUNT - 1)


static func queue_max() -> int:
	return QUEUE_MAX[level]


static func stamps_per_step() -> int:
	return STAMPS_PER_STEP[level]


static func stamp_budget_usec() -> int:
	return STAMP_BUDGET_USEC[level]


static func density_cap() -> int:
	return DENSITY_CAP[level]


static func scatter_passes() -> int:
	return SCATTER_PASSES[level]


static func speck_scale() -> float:
	return SPECK_SCALE[level]


static func piece_budget() -> int:
	return PIECE_BUDGET[level]


static func piece_burst() -> int:
	return PIECE_BURST[level]


## High keeps every piece of a broken object until the piece budget is full.
static func pieces_persist() -> bool:
	return level == HIGH


static func keep_near() -> float:
	return KEEP_NEAR[level]


static func wake_near() -> float:
	return WAKE_NEAR[level]
