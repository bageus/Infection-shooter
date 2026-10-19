extends RefCounted
## Player-owned orbit; weapon zoom and recoil remain independent.
const SENSITIVITY := 0.008


func handle_input(actor: Node3D, event: InputEvent) -> bool:
	if not Input.is_key_pressed(KEY_ALT):
		return false
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var values := snapshot(actor)
		values.yaw -= rad_to_deg(event.relative.x * SENSITIVITY)
		values.pitch = clampf(values.pitch - rad_to_deg(event.relative.y * SENSITIVITY), -80.0, 80.0)
		var distance: float = actor.camera.position.length()
		restore(actor, values)
		actor.camera.position = actor.camera.basis.z * distance
		return true
	return event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT


func snapshot(actor: Node3D) -> Dictionary:
	return {"yaw": wrapf(rad_to_deg(actor.camera_rig.rotation.y + actor.camera.rotation.y), -180.0, 180.0),
		"pitch": rad_to_deg(actor.camera.rotation.x), "distance": actor._camera_distance}


func restore(actor: Node3D, values: Dictionary) -> void:
	for key in ["yaw", "pitch", "distance"]:
		if not values.has(key) or not (values[key] is float or values[key] is int) or not is_finite(float(values[key])):
			return
	actor.camera_rig.rotation.y = deg_to_rad(wrapf(float(values.yaw), -180.0, 180.0))
	actor.camera.rotation = Vector3(deg_to_rad(clampf(float(values.pitch), -80.0, 80.0)), 0.0, 0.0)
	actor._camera_distance = clampf(float(values.distance), actor.camera_min_distance, actor.camera_max_distance)
	actor.camera.position = actor.camera.basis.z * actor._camera_distance
