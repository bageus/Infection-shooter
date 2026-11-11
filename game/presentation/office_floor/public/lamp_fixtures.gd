extends RefCounted
## Map-wide switch for lamp housings in play; the planner always draws them.
## Lamps read it when built and again when the planner calls refresh_fixture().

static var in_game := false
