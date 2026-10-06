extends MeshInstance3D
## Predator Dash speed trail: streaks of displaced air left in the air behind
## the player's body (shoulders, chest, hips). Each streak follows the dash
## path, faces the camera and fades from the newest point back. The node
## records while the dash lasts, then fades out and frees itself.

const LEVELS := [Vector2(-0.22, 1.45), Vector2(0.24, 1.35), Vector2(0.0, 1.05), Vector2(-0.18, 0.75), Vector2(0.2, 0.6)]
const MAX_POINTS := 24
const POINT_SPACING := 0.12
const POINT_LIFE := 0.45
const WIDTH := 0.11

const HEAD := Color(0.95, 0.97, 1.0)
const TAIL := Color(0.85, 0.25, 0.2)

static var _material: StandardMaterial3D

var _target: Node3D
var _record_left := 0.0
var _points: Array[Vector3] = []
var _ages: Array[float] = []
var _direction := Vector3.FORWARD
var _immediate := ImmediateMesh.new()


static func start(parent: Node, target: Node3D, seconds: float) -> MeshInstance3D:
	if parent == null or not parent.is_inside_tree() or target == null:
		return null
	var trail: MeshInstance3D = load("res://game/features/player/dash_trail.gd").new()
	trail.name = "DashTrail"
	parent.add_child(trail)
	trail.call("_begin", target, seconds)
	return trail


func _begin(target: Node3D, seconds: float) -> void:
	_target = target
	_record_left = seconds
	mesh = _immediate
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_material.vertex_color_use_as_albedo = true
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_material.no_depth_test = false
	material_override = _material
	top_level = true
	global_transform = Transform3D.IDENTITY
	_record(true)


func is_recording() -> bool:
	return _record_left > 0.0


func _process(delta: float) -> void:
	for i in _ages.size():
		_ages[i] += delta
	if _record_left > 0.0:
		_record_left -= delta
		_record(false)
	while not _ages.is_empty() and _ages[0] > POINT_LIFE:
		_ages.pop_front()
		_points.pop_front()
	if _record_left <= 0.0 and (_points.is_empty() or _ages[_ages.size() - 1] > POINT_LIFE):
		queue_free()
		return
	_draw()


func _record(force: bool) -> void:
	if not is_instance_valid(_target):
		_record_left = 0.0
		return
	var point := _target.global_position
	if not _points.is_empty():
		var step := point - _points[_points.size() - 1]
		step.y = 0.0
		if step.length() < POINT_SPACING and not force:
			_ages[_ages.size() - 1] = 0.0
			return
		if step.length() > 0.001:
			_direction = step.normalized()
	_points.append(point)
	_ages.append(0.0)
	if _points.size() > MAX_POINTS:
		_points.pop_front()
		_ages.pop_front()


func _draw() -> void:
	_immediate.clear_surfaces()
	if _points.size() < 2:
		return
	var camera := get_viewport().get_camera_3d()
	var eye := camera.global_position if camera != null else Vector3(0, 20, 0)
	var side := Vector3(-_direction.z, 0.0, _direction.x)
	_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for level: Vector2 in LEVELS:
		var offset := side * level.x + Vector3.UP * level.y
		for i in _points.size() - 1:
			_segment(_points[i] + offset, _points[i + 1] + offset, _fade(i), _fade(i + 1), eye)
	_immediate.surface_end()


func _fade(index: int) -> float:
	var along := float(index) / float(maxi(_points.size() - 1, 1))
	return clampf(1.0 - _ages[index] / POINT_LIFE, 0.0, 1.0) * along


func _segment(a: Vector3, b: Vector3, fade_a: float, fade_b: float, eye: Vector3) -> void:
	var along := b - a
	if along.length_squared() < 0.000001:
		return
	var across := along.cross(eye - a).normalized() * WIDTH
	var color_a := TAIL.lerp(HEAD, fade_a)
	var color_b := TAIL.lerp(HEAD, fade_b)
	color_a.a = 0.85 * fade_a
	color_b.a = 0.85 * fade_b
	var points := [a - across * fade_a, a + across * fade_a, b + across * fade_b, b - across * fade_b]
	var colors := [color_a, color_a, color_b, color_b]
	for index in [0, 1, 2, 0, 2, 3]:
		_immediate.surface_set_color(colors[index])
		_immediate.surface_add_vertex(points[index])
