extends RefCounted
## Player-owned orbit; weapon zoom and recoil remain independent.
## Alt+LMB: horizontal drag orbits yaw, vertical drag changes pitch (camera height above the floor).
## I / K: raise / lower the camera pitch by PITCH_STEP per key press (repeat while held).
## Stair room: the camera eases ROOM_PITCH_OFFSET below the pitch while the player is in such a room.
const SENSITIVITY := 0.008
const PITCH_STEP := 1.0
const PITCH := -44.81
const PITCH_MIN := -85.0
const PITCH_MAX := -5.0
const ROOM_PITCH_OFFSET := -14.0
const ROOM_PITCH_SPEED := 12.0

var _base_pitch := PITCH
var _room_offset := 0.0


func handle_input(actor: Node3D, event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and event.keycode in [KEY_I, KEY_K]:
		var keyed := snapshot(actor)
		keyed.pitch += PITCH_STEP if event.keycode == KEY_K else -PITCH_STEP
		_apply(actor, keyed)
		return true
	if not Input.is_key_pressed(KEY_ALT):
		return false
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var values := snapshot(actor)
		values.yaw -= rad_to_deg(event.relative.x * SENSITIVITY)
		values.pitch += rad_to_deg(event.relative.y * SENSITIVITY)
		_apply(actor, values)
		return true
	return event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT


func snapshot(actor: Node3D) -> Dictionary:
	return {"yaw": wrapf(rad_to_deg(actor.camera_rig.rotation.y + actor.camera.rotation.y), -180.0, 180.0),
		"pitch": _base_pitch, "distance": actor._camera_distance}


func restore(actor: Node3D, values: Dictionary) -> void:
	for key in ["yaw", "pitch", "distance"]:
		if not values.has(key) or not (values[key] is float or values[key] is int) or not is_finite(float(values[key])):
			return
	actor.camera_rig.rotation.y = deg_to_rad(wrapf(float(values.yaw), -180.0, 180.0))
	_base_pitch = clampf(float(values.pitch), PITCH_MIN, PITCH_MAX)
	_apply_pitch(actor)
	actor._camera_distance = clampf(float(values.distance), actor.camera_min_distance, actor.camera_max_distance)
	actor.camera.position = actor.camera.basis.z * actor._camera_distance


func tick(actor: Node3D, delta: float) -> void:
	_room_offset = move_toward(_room_offset, ROOM_PITCH_OFFSET if actor.camera_stair_room else 0.0, ROOM_PITCH_SPEED * delta)
	_apply_pitch(actor)


func _apply_pitch(actor: Node3D) -> void:
	actor.camera.rotation = Vector3(deg_to_rad(clampf(_base_pitch + _room_offset, PITCH_MIN, PITCH_MAX)), 0.0, 0.0)


func _apply(actor: Node3D, values: Dictionary) -> void:
	var distance: float = actor.camera.position.length()
	restore(actor, values)
	actor.camera.position = actor.camera.basis.z * distance
