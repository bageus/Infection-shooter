extends Node

const SFX := preload("res://game/core/audio/public/sound_events.gd")

const MAX_CASINGS := 40
const LIFETIME_MSEC := 60000
const CASING_SCALE := 3.0

var _casings: Array[RigidBody3D] = []
var _born_at: Array[int] = []
var _cleanup_accumulator := 0.0

var effects_root: Node3D
var impact_pool: Node


# Public scene wiring v1; owned by the mission composition.
func configure_world(container: Node3D, impacts: Node) -> void:
	effects_root = container
	impact_pool = impacts


# Public v1 + sound_event (ADR-0018): the casing clinks when it lands.
func spawn_casing(model: PackedScene, eject_transform: Transform3D, radius: float, shooter: CollisionObject3D, sound_event: StringName = &"casing_brass", size_multiplier: float = 1.0) -> void:
	if model == null or not is_instance_valid(effects_root):
		return
	var body := RigidBody3D.new()
	body.name = "SpentCasing"
	body.collision_layer = 0
	body.collision_mask = 1
	body.mass = 0.012
	body.continuous_cd = true
	body.linear_damp = 0.4
	body.angular_damp = 1.1
	var material := PhysicsMaterial.new()
	material.bounce = 0.48
	material.friction = 0.65
	body.physics_material_override = material
	var collider := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius * CASING_SCALE * size_multiplier
	shape.margin = 0.001
	collider.shape = shape
	body.add_child(collider)
	var visual := model.instantiate() as Node3D
	if visual == null:
		body.queue_free()
		return
	visual.scale *= CASING_SCALE * size_multiplier
	body.add_child(visual)
	effects_root.add_child(body)
	body.global_transform = eject_transform
	if shooter != null:
		body.add_collision_exception_with(shooter)
	var basis := eject_transform.basis.orthonormalized()
	body.linear_velocity = basis.x * randf_range(1.5, 2.3) + Vector3.UP * randf_range(1.4, 2.2) + basis.z * randf_range(-0.5, 0.2)
	body.angular_velocity = Vector3(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0), randf_range(-10.0, 10.0))
	_casings.append(body)
	_born_at.append(Time.get_ticks_msec())
	_cleanup()
	if not sound_event.is_empty():
		_schedule_clink(body, sound_event)


# Casings land about a third of a second after ejection and bounce once.
func _schedule_clink(body: RigidBody3D, sound_event: StringName) -> void:
	var casing: WeakRef = weakref(body)
	var landing := randf_range(0.3, 0.46)
	get_tree().create_timer(landing).timeout.connect(func() -> void:
		var live := casing.get_ref() as Node3D
		if live != null and is_instance_valid(effects_root):
			SFX.play(effects_root, sound_event, live.global_position))
	if randf() < 0.6:
		get_tree().create_timer(landing + randf_range(0.12, 0.22)).timeout.connect(func() -> void:
			var live := casing.get_ref() as Node3D
			if live != null and is_instance_valid(effects_root):
				SFX.play(effects_root, sound_event, live.global_position, -8.0, 1.06))


func _process(delta: float) -> void:
	_cleanup_accumulator += delta
	if _cleanup_accumulator >= 0.5:
		_cleanup_accumulator = 0.0
		_cleanup()


func _cleanup() -> void:
	var now := Time.get_ticks_msec()
	for index in range(_casings.size() - 1, -1, -1):
		if not is_instance_valid(_casings[index]) or _casings[index].is_queued_for_deletion():
			_casings.remove_at(index)
			_born_at.remove_at(index)
		elif now - _born_at[index] >= LIFETIME_MSEC:
			_casings[index].queue_free()
			_casings.remove_at(index)
			_born_at.remove_at(index)
	while _casings.size() > MAX_CASINGS:
		var oldest: RigidBody3D = _casings.pop_front()
		_born_at.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
