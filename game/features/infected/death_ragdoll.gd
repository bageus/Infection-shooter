extends RefCounted
## A killed infected is let go instead of playing a death clip (ADR-0041): its
## bones become a ragdoll that starts with the running momentum plus the push of
## the killing blow, so the body drops and tumbles with whatever carried it.
## Only a few ragdolls run at once; any further death uses the clips of ADR-0034.

const CORPSE_PHYSICS := preload("res://game/features/infected/corpse_physics.gd")
const DEATH_FALL := preload("res://game/features/infected/death_fall.gd")
const CORPSE_BUDGET := preload("res://game/features/infected/public/corpse_budget.gd")
const MAX_ACTIVE := 8
const SINK_SECONDS := 1.2

static var _active := 0
## Physics ids that still hold one of the MAX_ACTIVE slots.
static var _slots := {}


## Returns the running corpse physics, or null when the clips must play instead.
## The owner's death_linger_seconds and _hide_corpse() end it.
static func start(owner: Node, parts: Node, animation: Node, momentum: Vector3, push: Vector3, size: float) -> RefCounted:
	if parts == null or _active >= MAX_ACTIVE:
		return null
	var physics := CORPSE_PHYSICS.new()
	physics.call("setup", parts)
	var simulator := physics.get("simulator") as Node
	if simulator == null:
		return null
	if animation != null:
		animation.call("set_active", false)
	physics.call("set_enabled", true)
	physics.call("launch", DEATH_FALL.velocity(momentum, push, size))
	_active += 1
	var id := physics.get_instance_id()
	_slots[id] = true
	simulator.tree_exited.connect(_released.bind(id))
	release_after(owner, physics, owner.get("death_linger_seconds"), Callable(owner, "_hide_corpse"))
	return physics


static func _released(id: int) -> void:
	if _slots.erase(id):
		_active = maxi(0, _active - 1)


## After the linger time the body drops through the floor, then gone() hides it.
## With keep_corpses the body stays in its settled pose, frees its slot for the
## next death, and is hidden only when CORPSE_BUDGET pushes it out.
static func release_after(owner: Node, physics: RefCounted, linger: float, gone: Callable) -> void:
	await owner.get_tree().create_timer(linger).timeout
	if not is_instance_valid(owner):
		return
	if CORPSE_BUDGET.keep:
		_released(physics.get_instance_id())
		var evict := func() -> void:
			if is_instance_valid(owner):
				physics.call("set_enabled", false)
				gone.call()
		CORPSE_BUDGET.retain(owner, owner.get("_parts"), evict)
		return
	physics.call("sink")
	await owner.get_tree().create_timer(SINK_SECONDS).timeout
	if is_instance_valid(owner):
		physics.call("set_enabled", false)
		gone.call()

