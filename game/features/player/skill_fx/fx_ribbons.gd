extends RefCounted
## Camera-facing strips drawn into one ImmediateMesh: jagged lightning bolts
## re-rolled every few frames, or a fixed curved path (a claw slash). Points
## are in world space; each strip's opacity rides in the vertex alpha.

const SHADER := preload("res://game/features/player/skill_fx/fx_ribbon.gdshader")

var instance: MeshInstance3D
var _mesh := ImmediateMesh.new()
var _strips: Array[Dictionary] = []


func _init(parent: Node3D, material: Material) -> void:
	instance = MeshInstance3D.new()
	instance.mesh = _mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.top_level = true
	parent.add_child(instance)
	instance.global_transform = Transform3D.IDENTITY


func clear() -> void:
	_strips.clear()
	_mesh.clear_surfaces()


## A zigzag from `from` to `to`; `jitter` is the sideways throw as a share of
## the length (capped), ends pinned.
func add_bolt(from: Vector3, to: Vector3, width: float, jitter: float, alpha: float) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var along := (to - from) / length
	var side_a := along.cross(Vector3.UP)
	if side_a.length_squared() < 0.0001:
		side_a = Vector3.RIGHT
	side_a = side_a.normalized()
	var segments := clampi(int(length / 0.3), 4, 22)
	var throw := minf(length * jitter, 0.6) * 0.5
	var points: Array[Vector3] = []
	for i in segments + 1:
		var t := float(i) / segments
		var point := from.lerp(to, t)
		if i > 0 and i < segments:
			point += side_a * randf_range(-throw, throw) + Vector3.UP * randf_range(-throw, throw) * 0.5
		points.append(point)
	add_path(points, width, alpha, along)


## `axis` (optional) turns the whole strip by one direction instead of each
## point's tangent, so a sharp zigzag never folds the strip over itself.
func add_path(points: Array[Vector3], width: float, alpha: float, axis := Vector3.ZERO) -> void:
	if points.size() >= 2 and alpha > 0.001:
		_strips.append({"points": points, "width": width, "alpha": alpha, "axis": axis})


func commit() -> void:
	_mesh.clear_surfaces()
	if _strips.is_empty() or not instance.is_inside_tree():
		return
	var camera := instance.get_viewport().get_camera_3d()
	var eye := camera.global_position if camera != null else Vector3(0, 20, 20)
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for strip in _strips:
		var points: Array[Vector3] = strip["points"]
		var half := float(strip["width"]) * 0.5
		var tint := Color(1.0, 1.0, 1.0, float(strip["alpha"]))
		var axis: Vector3 = strip["axis"]
		var previous_left := Vector3.ZERO
		var previous_right := Vector3.ZERO
		for i in points.size():
			var tangent := axis if axis != Vector3.ZERO else (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
			var side := tangent.cross(eye - points[i])
			side = side.normalized() * half if side.length_squared() > 0.000001 else Vector3.UP * half
			var left := points[i] + side
			var right := points[i] - side
			if i > 0:
				var u0 := float(i - 1) / (points.size() - 1)
				var u1 := float(i) / (points.size() - 1)
				_vertex(previous_left, Vector2(u0, 0.0), tint)
				_vertex(left, Vector2(u1, 0.0), tint)
				_vertex(previous_right, Vector2(u0, 1.0), tint)
				_vertex(previous_right, Vector2(u0, 1.0), tint)
				_vertex(left, Vector2(u1, 0.0), tint)
				_vertex(right, Vector2(u1, 1.0), tint)
			previous_left = left
			previous_right = right
	_mesh.surface_end()


func _vertex(point: Vector3, uv: Vector2, tint: Color) -> void:
	_mesh.surface_set_color(tint)
	_mesh.surface_set_uv(uv)
	_mesh.surface_add_vertex(point)
