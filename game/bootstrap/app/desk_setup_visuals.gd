extends Node3D

# Guides are drawn in desk coordinates, so they follow the same pivot and rotation.
const FLOOR_RADIUS := 2.75
const FLOOR_STEP := 0.25
const SURFACE_STEP := 0.1

var desk: Node3D
var stations: Array = []
var surface_height := 0.89
var orbit_yaw := PI
var orbit_pitch := 0.58
var orbit_distance := 5.6


func configure(target: Node3D, profile: Dictionary) -> void:
	desk = target
	stations = []
	var footprint := _visible_footprint()
	var is_table := "table" in str(desk.get_meta("planning_scene_path", "")).get_file() and "desk" not in str(desk.get_meta("planning_scene_path", "")).get_file()
	for value in profile.get("stations", []):
		var station: Dictionary = (value as Dictionary).duplicate()
		if is_table and footprint.has_area():
			var old_center := Vector2(float(station.get("x", 0.0)), float(station.get("z", 0.0)))
			station["x"] = footprint.get_center().x + old_center.x
			station["z"] = footprint.get_center().y + old_center.y
			station["grid_x"] = station["x"]
			station["grid_z"] = station["z"]
		stations.append(station)
	surface_height = float(profile.get("height", 0.89))
	redraw([], -1, 0)


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	desk = null


func reset_view(camera: Camera3D) -> void:
	orbit_yaw = PI
	orbit_pitch = 0.58
	orbit_distance = 5.6
	_update_camera(camera)


func rotate_view(camera: Camera3D, movement: Vector2) -> void:
	orbit_yaw -= movement.x * 0.008
	orbit_pitch = clampf(orbit_pitch + movement.y * 0.008, 0.12, 1.35)
	_update_camera(camera)


func zoom_view(camera: Camera3D, distance: float) -> void:
	orbit_distance = clampf(orbit_distance + distance, 1.5, 10.0)
	_update_camera(camera)


func _update_camera(camera: Camera3D) -> void:
	if desk == null:
		return
	var target := desk.to_global(Vector3(0, surface_height * 0.5, 0))
	camera.global_position = target + desk.global_basis * Vector3(sin(orbit_yaw) * cos(orbit_pitch) * orbit_distance, sin(orbit_pitch) * orbit_distance, cos(orbit_yaw) * cos(orbit_pitch) * orbit_distance)
	camera.look_at(target, Vector3.UP)


func redraw(zones: Array[Dictionary], selected: int, front: int) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if desk == null:
		return
	var footprint := _visible_footprint()
	var left := minf(-FLOOR_RADIUS, footprint.position.x - 0.85)
	var right := maxf(FLOOR_RADIUS, footprint.end.x + 0.85)
	var back := minf(-FLOOR_RADIUS, footprint.position.y - 0.85)
	var forward := maxf(FLOOR_RADIUS, footprint.end.y + 0.85)
	_add_grid(left, right, back, forward, 0.025, FLOOR_STEP, Color(0.15, 0.66, 0.82, 0.16))
	for station_value in stations:
		var station: Dictionary = station_value
		var x := float(station.get("grid_x", station.get("x", 0.0)))
		var z := float(station.get("grid_z", station.get("z", 0.0)))
		var half_width := float(station.get("grid_width", 1.8)) * 0.5
		var half_depth := float(station.get("grid_depth", 1.1)) * 0.5
		_add_grid(x - half_width, x + half_width, z - half_depth, z + half_depth, float(station.get("grid_height", surface_height)) + 0.025, SURFACE_STEP, Color(0.85, 0.95, 1.0, 0.22))
	for i in zones.size():
		var zone: Dictionary = zones[i]
		var box := BoxMesh.new()
		box.size = Vector3(float(zone["width"]), 0.006, float(zone["depth"]))
		var color := Color(1.0, 0.52, 0.25, 0.12) if i == selected else Color(0.12, 0.8, 1.0, 0.055)
		box.material = _material(color, true)
		var region := MeshInstance3D.new()
		region.mesh = box
		add_child(region)
		region.global_transform = desk.global_transform * Transform3D(Basis(Vector3.UP, deg_to_rad(float(zone.get("angle", 0.0)))), Vector3(float(zone["x"]), float(zone["height"]) + 0.035, float(zone["z"])))
		_add_zone_arrow(zone, Color(1.0, 0.9, 0.3) if i == selected else Color(0.93, 0.96, 1.0))
	var direction := BoxMesh.new()
	direction.size = Vector3(0.3, 0.015, 0.08)
	direction.material = _material(Color(1.0, 0.08, 0.04), true)
	_add_mesh(direction, Vector3(0, surface_height + 0.06, 0.87 if front else -0.87))


func _add_zone_arrow(zone: Dictionary, color: Color) -> void:
	var arrow := ImmediateMesh.new()
	arrow.surface_begin(Mesh.PRIMITIVE_LINES, _material(color, true))
	for point in [Vector3(0, 0, -0.17), Vector3(0, 0, 0.17), Vector3(0, 0, 0.17), Vector3(-0.08, 0, 0.06), Vector3(0, 0, 0.17), Vector3(0.08, 0, 0.06)]:
		arrow.surface_add_vertex(point)
	arrow.surface_end()
	var indicator := MeshInstance3D.new()
	indicator.mesh = arrow
	add_child(indicator)
	var angle := deg_to_rad(float(zone.get("angle", 0.0)))
	indicator.global_transform = desk.global_transform * Transform3D(Basis(Vector3.UP, angle), Vector3(float(zone["x"]), float(zone["height"]) + 0.06, float(zone["z"])))


func _material(color: Color, overlay: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = overlay
	return material


func _add_mesh(source: Mesh, local_position: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = source
	add_child(instance)
	instance.global_transform = desk.global_transform * Transform3D(Basis.IDENTITY, local_position)


func _add_grid(left: float, right: float, back: float, front: float, height: float, step: float, color: Color) -> void:
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES, _material(color))
	var x_count := roundi((right - left) / step)
	var z_count := roundi((front - back) / step)
	for i in x_count + 1:
		var x := left + i * step
		lines.surface_add_vertex(Vector3(x, height, back))
		lines.surface_add_vertex(Vector3(x, height, front))
	for i in z_count + 1:
		var z := back + i * step
		lines.surface_add_vertex(Vector3(left, height, z))
		lines.surface_add_vertex(Vector3(right, height, z))
	lines.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh = lines
	add_child(instance)
	instance.global_transform = desk.global_transform


func _visible_footprint() -> Rect2:
	var area := Rect2()
	var found := false
	if desk == null:
		return area
	for descendant in desk.find_children("*", "MeshInstance3D", true, false):
		var mesh := descendant as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree() or absf(mesh.global_basis.determinant()) < 0.000001:
			continue
		var local := (desk.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		var region := Rect2(Vector2(local.position.x, local.position.z), Vector2(local.size.x, local.size.z))
		area = area.merge(region) if found else region
		found = true
	return area
