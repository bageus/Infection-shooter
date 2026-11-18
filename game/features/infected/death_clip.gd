extends RefCounted
## Fallback death: the authored clip plays, then the corpse sinks away.

const DEATH_FALL := preload("res://game/features/infected/death_fall.gd")
const DEATH_OBSTACLE := preload("res://game/features/infected/death_obstacle.gd")
const CORPSE_BUDGET := preload("res://game/features/infected/public/corpse_budget.gd")
const YAW_JITTER := 0.5 # radians


# Returns the fall watcher to step while the body falls, or null.
static func play(owner: CharacterBody3D, parts: Node, animation: Node, fall: Dictionary, landing: Vector3) -> RefCounted:
	# A few degrees of random yaw so the corpses of one fall do not all point the same way.
	DEATH_FALL.throw(owner, float(fall["turn"]) + randf_range(-YAW_JITTER, YAW_JITTER), landing)
	var death_length: float = owner.call("_play_animation", fall["state"])
	var watch: RefCounted = DEATH_OBSTACLE.new()
	# A crawler is already on the floor: nothing to topple onto, so nothing to freeze on.
	if fall["state"] == DEATH_FALL.DEATH_CRAWL or not watch.call("start", owner, parts, animation, fall, death_length):
		watch = null
	var body_visual: Node3D = owner.get("body_visual")
	if death_length > 0.0:
		# The corpse stays visible while the clip plays, then sinks away.
		var tween := owner.create_tween()
		tween.tween_interval(death_length + float(owner.get("death_linger_seconds")))
		CORPSE_BUDGET.clip_tail(tween, owner, parts, body_visual, float(owner.get("death_sink_depth")), Callable(owner, "_hide_corpse"))
	else:
		body_visual.visible = false
	return watch
