extends Node
## Plays a landing/knock sound when its parent rigid body is stopped hard
## (falls, topples, slams into a wall) (ADR-0018). Runs only while the body
## is awake, so resting props cost nothing.

const REST := preload("res://game/presentation/office_floor/prop_rest.gd")
const SFX := preload("res://game/core/audio/public/sound_events.gd")
const MIN_SPEED_LOSS := 1.4
const MATERIAL_EVENTS := {
	"wood": &"fall_wood", "metal": &"fall_metal", "light": &"fall_light", "tech": &"fall_tech",
	"glass": &"fall_light", "concrete": &"fall_debris",
}

var event: StringName = &"fall_wood"
var volume_db := 0.0
var _body: RigidBody3D
var _last_velocity := Vector3.ZERO
var _quiet := 0.4
var _owns_contacts := false
var _wake_bounds := AABB()
var _wake_shape: BoxShape3D


# Adds a watcher to `body`; the event follows the body's projectile material.
static func watch(body: RigidBody3D, volume_offset_db := 0.0, fixed_event: StringName = &"") -> void:
	var watcher := new()
	watcher.name = "ImpactSound"
	watcher.volume_db = volume_offset_db
	if not fixed_event.is_empty():
		watcher.event = fixed_event
	elif body.has_method("get_projectile_material"):
		watcher.event = MATERIAL_EVENTS.get(str(body.call("get_projectile_material", -1)), &"fall_wood")
	body.add_child(watcher)


func _ready() -> void:
	_body = get_parent() as RigidBody3D
	if _body == null:
		queue_free()
		return
	_body.sleeping_state_changed.connect(_on_sleeping_changed)
	_owns_contacts = not _body.contact_monitor
	_body.body_entered.connect(_on_contact)
	# Frozen (wall-mounted) props never report sleeping; they wait for wake().
	set_physics_process(not _body.sleeping and not _body.freeze)


## Resumes watching a body that was just unfrozen (a prop knocked off a wall).
static func wake(body: Node) -> void:
	var watcher := body.get_node_or_null("ImpactSound")
	if watcher != null:
		watcher.set_physics_process(true)


func _on_sleeping_changed() -> void:
	set_physics_process(not _body.sleeping and not _body.freeze)
	_last_velocity = _body.linear_velocity
	if _owns_contacts and _body.sleeping:
		call_deferred("_disable_owned_contacts")


func reset_fragment() -> void:
	_quiet = 0.4
	_last_velocity = Vector3.ZERO
	set_physics_process(not _body.sleeping and not _body.freeze)


func _physics_process(delta: float) -> void:
	if _body.freeze:
		set_physics_process(false)
		return
	_quiet -= delta
	var velocity := _body.linear_velocity
	if _owns_contacts and not _body.contact_monitor and velocity.length_squared() > .0025:
		_body.max_contacts_reported = maxi(_body.max_contacts_reported, 4)
		_body.contact_monitor = true
	if velocity.length_squared() > .04:
		_wake_ahead(velocity, delta)
	var loss := _last_velocity.length() - velocity.length()
	if loss > MIN_SPEED_LOSS and _quiet <= 0.0 and not _body.freeze:
		var weight := clampf(remap(_body.mass, 0.2, 30.0, -4.0, 3.0), -4.0, 3.0)
		var strength := clampf(remap(loss, MIN_SPEED_LOSS, 7.0, -9.0, 1.0), -9.0, 1.0)
		SFX.play(_body, event, _body.global_position, volume_db + weight + strength, clampf(1.15 - _body.mass * 0.01, 0.85, 1.15))
		_quiet = 0.25
	_last_velocity = velocity


func _on_contact(other: Node) -> void:
	if other is RigidBody3D and bool(other.get_meta(REST.FROZEN, false)) and not _body.freeze and maxf(_body.linear_velocity.length_squared(), _last_velocity.length_squared()) > .0025:
		REST.wake_later(other)


func _wake_ahead(velocity: Vector3, delta: float) -> void:
	# Only fast moving items query. Wake before contact so the solver sees two finite masses.
	if _wake_shape == null:
		_wake_shape = BoxShape3D.new()
		_wake_bounds = REST.body_bounds(_body)
	if _wake_bounds.size.length_squared() < .000001:
		return
	var current: AABB = _body.global_transform * _wake_bounds
	var future := current
	future.position += velocity * delta * 2.0
	var swept := current.merge(future).grow(.025)
	_wake_shape.size = swept.size.max(Vector3.ONE * .02)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _wake_shape
	query.transform.origin = swept.get_center()
	query.collision_mask = _body.collision_mask
	query.exclude = [_body.get_rid()]
	for hit in _body.get_world_3d().direct_space_state.intersect_shape(query, 64):
		var other := hit.get("collider") as RigidBody3D
		if other != null and bool(other.get_meta(REST.FROZEN, false)):
			REST.wake(other)


func _disable_owned_contacts() -> void:
	if is_instance_valid(_body) and (_body.sleeping or _body.freeze):
		if _body.contact_monitor:
			_body.contact_monitor = false
		if _body.max_contacts_reported != 0:
			_body.max_contacts_reported = 0
