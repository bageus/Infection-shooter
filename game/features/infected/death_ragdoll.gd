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
## A body dying this close to another corpse is pushed off it, so bodies lie beside
## each other instead of piling up.
const GROUP := &"ragdoll_corpse"
const SPREAD_RADIUS := 1.4
const SPREAD_SPEED := 3.0

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
	var fall := DEATH_FALL.velocity(momentum, push, size)
	fall += _spread(owner, fall)
	owner.add_to_group(GROUP)
	physics.call("launch", fall)
	physics.call("stagger", fall)
	_active += 1
	var id := physics.get_instance_id()
	_slots[id] = true
	simulator.tree_exited.connect(_released.bind(id))
	release_after(owner, physics, owner.get("death_linger_seconds"), Callable(owner, "_hide_corpse"))
	return physics


## Planar push away from the corpses lying within SPREAD_RADIUS.
static func _spread(owner: Node, fall: Vector3) -> Vector3:
	var origin := (owner as Node3D).global_position
	var away := Vector3.ZERO
	for other: Node in owner.get_tree().get_nodes_in_group(GROUP):
		var body := other as Node3D
		if body == null or body == owner or not body.is_inside_tree() or not body.get("body_visual").visible:
			continue
		var offset := origin - body.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance >= SPREAD_RADIUS:
			continue
		# Exactly on top of each other: any direction beats none.
		var direction := offset / distance if distance > 0.01 else Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)
		away += direction * (SPREAD_RADIUS - distance) * SPREAD_SPEED
	# Bodies falling the same way are long: slide them sideways, not along the fall.
	if fall.length() > 0.5:
		var along := fall.normalized()
		away -= along * away.dot(along)
	return away.limit_length(SPREAD_SPEED * SPREAD_RADIUS)


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
		physics.call("freeze_pose")
		physics.call("lower_legs")
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
		_released(physics.get_instance_id())
		gone.call()

