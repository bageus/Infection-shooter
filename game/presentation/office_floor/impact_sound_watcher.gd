extends Node3D
## Plays a landing/knock sound when its parent rigid body is stopped hard
## (falls, topples, slams into a wall) (ADR-0018). Runs only while the body
## is awake, so resting props cost nothing.

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
	# Scripted sleeping=false does not emit sleeping_state_changed. Inherit the
	# body's transform so its first movement wakes observation without idle polling.
	set_notify_transform(true)
	# Frozen (wall-mounted) props never report sleeping; they wait for wake().
	set_physics_process(not _body.sleeping and not _body.freeze)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_instance_valid(_body) and not is_physics_processing():
		_on_sleeping_changed()


## Resumes watching a body that was just unfrozen (a prop knocked off a wall).
static func wake(body: Node) -> void:
	var watcher := body.get_node_or_null("ImpactSound")
	if watcher != null:
		watcher.set_physics_process(true)


func _on_sleeping_changed() -> void:
	set_physics_process(not _body.sleeping and not _body.freeze)
	_last_velocity = _body.linear_velocity


func reset_fragment() -> void:
	_quiet = 0.4
	_last_velocity = Vector3.ZERO
	set_physics_process(not _body.sleeping and not _body.freeze)


func _physics_process(delta: float) -> void:
	# Prepared maps can assign sleep directly, bypassing the engine's signal.
	if _body.freeze or _body.sleeping:
		set_physics_process(false)
		return
	_quiet -= delta
	var velocity := _body.linear_velocity
	var loss := _last_velocity.length() - velocity.length()
	if loss > MIN_SPEED_LOSS and _quiet <= 0.0 and not _body.freeze:
		var weight := clampf(remap(_body.mass, 0.2, 30.0, -4.0, 3.0), -4.0, 3.0)
		var strength := clampf(remap(loss, MIN_SPEED_LOSS, 7.0, -9.0, 1.0), -9.0, 1.0)
		SFX.play(_body, event, _body.global_position, volume_db + weight + strength, clampf(1.15 - _body.mass * 0.01, 0.85, 1.15))
		_quiet = 0.25
	_last_velocity = velocity
