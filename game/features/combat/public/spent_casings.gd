extends Node

const SFX := preload("res://game/core/audio/public/sound_events.gd")

const MAX_CASINGS := 40
const LIFETIME_MSEC := 60000
const CASING_SCALE := 3.0
# Resting casings keep a solver-driven spin (~2 rad/s) that never sleeps the body,
# so a casing that has landed and nearly stopped is frozen in place.
const SETTLE_LINEAR_SPEED := 0.15

var _casings: Array[RigidBody3D] = []
var _born_at: Array[int] = []
var _cleanup_accumulator := 0.0
var _surface: PhysicsMaterial
var _shapes: Dictionary = {}

var effects_root: Node3D
var impact_pool: Node


func _ready() -> void:
	set_process(false)


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
	body.contact_monitor = true
	body.max_contacts_reported = 1
	body.linear_damp = 0.4
	body.angular_damp = 1.1
	if _surface == null:
		_surface = PhysicsMaterial.new()
		_surface.bounce = 0.48
		_surface.friction = 0.65
	body.physics_material_override = _surface
	var collider := CollisionShape3D.new()
	var scaled_radius := radius * CASING_SCALE * size_multiplier
	if not _shapes.has(scaled_radius):
		var shape := SphereShape3D.new()
		shape.radius = scaled_radius
		shape.margin = .001
		_shapes[scaled_radius] = shape
	collider.shape = _shapes[scaled_radius]
	body.add_child(collider)
	var visual := model.instantiate() as Node3D
	if visual == null:
		body.queue_free()
		return
	visual.scale *= CASING_SCALE * size_multiplier
	body.add_child(visual)
	effects_root.add_child(body)
	body.global_transform = eject_transform
	if is_instance_valid(shooter):
		body.add_collision_exception_with(shooter)
	var basis := eject_transform.basis.orthonormalized()
	body.linear_velocity = basis.x * randf_range(1.5, 2.3) + Vector3.UP * randf_range(1.4, 2.2) + basis.z * randf_range(-0.5, 0.2)
	body.angular_velocity = Vector3(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0), randf_range(-10.0, 10.0))
	_casings.append(body)
	_born_at.append(Time.get_ticks_msec())
	_cleanup()
	set_process(true)
	if not sound_event.is_empty():
		_schedule_clink(body, sound_event)


# Casings land about a third of a second after ejection and bounce once.
func _schedule_clink(body: RigidBody3D, sound_event: StringName) -> void:
	var casing: WeakRef = weakref(body)
	var landing := randf_range(0.3, 0.46)
	# Bound methods, not lambdas: a timer outliving this pool (restart, back to
	# the menu) drops the call instead of touching the freed instance.
	get_tree().create_timer(landing).timeout.connect(_play_clink.bind(casing, sound_event, 0.0, 1.0))
	if randf() < 0.6:
		get_tree().create_timer(landing + randf_range(0.12, 0.22)).timeout.connect(_play_clink.bind(casing, sound_event, -8.0, 1.06))


func _play_clink(casing: WeakRef, sound_event: StringName, volume_db: float, pitch: float) -> void:
	var live := casing.get_ref() as Node3D
	if live != null and is_instance_valid(effects_root):
		SFX.play(effects_root, sound_event, live.global_position, volume_db, pitch)


func _process(delta: float) -> void:
	_cleanup_accumulator += delta
	if _cleanup_accumulator >= 0.5:
		_cleanup_accumulator = 0.0
		_cleanup()


func _freeze_if_settled(body: RigidBody3D) -> void:
	if body.freeze or body.linear_velocity.length() >= SETTLE_LINEAR_SPEED or body.get_colliding_bodies().is_empty():
		return
	body.angular_velocity = Vector3.ZERO
	body.freeze = true


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
		else:
			_freeze_if_settled(_casings[index])
	while _casings.size() > MAX_CASINGS:
		var oldest: RigidBody3D = _casings.pop_front()
		_born_at.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


	set_process(not _casings.is_empty())
