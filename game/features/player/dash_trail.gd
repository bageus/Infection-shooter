extends MeshInstance3D
## Predator Dash speed trail: streaks of displaced air left in the air behind
## the player's body (shoulders, chest, hips). Each streak follows the dash
## path, faces the camera and fades from the newest point back. The node
## records while the dash lasts, then fades out and frees itself.

## Streaks as (side offset, height, half width, strength): a wide soft haze
## down the middle for the blur, thin speed lines behind and along the flanks.
const LEVELS := [
	Vector3(0.0, 1.0, 0.5), Vector3(0.0, 0.7, 0.3),
	Vector3(-0.1, 1.3, 0.035), Vector3(0.12, 1.15, 0.03), Vector3(0.0, 0.9, 0.03), Vector3(-0.08, 0.6, 0.03),
	Vector3(-0.5, 1.2, 0.025), Vector3(0.55, 1.0, 0.025), Vector3(-0.75, 0.8, 0.02), Vector3(0.8, 1.4, 0.02),
	Vector3(-0.95, 1.05, 0.018), Vector3(1.0, 0.7, 0.018),
]
const LEVEL_ALPHA := [0.1, 0.08, 0.7, 0.7, 0.6, 0.6, 0.55, 0.55, 0.45, 0.45, 0.35, 0.35]
const MAX_POINTS := 24
const POINT_SPACING := 0.12
const POINT_LIFE := 0.45

const STREAK_SHADER := preload("res://game/features/player/skill_fx/fx_dash_streak.gdshader")

static var _material: ShaderMaterial

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
		_material = ShaderMaterial.new()
		_material.shader = STREAK_SHADER
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
	for index in LEVELS.size():
		var level: Vector3 = LEVELS[index]
		var offset := side * level.x + Vector3.UP * level.y
		for i in _points.size() - 1:
			_segment(_points[i] + offset, _points[i + 1] + offset, _fade(i), _fade(i + 1), eye, level.z, LEVEL_ALPHA[index], i, index)
	_immediate.surface_end()


func _fade(index: int) -> float:
	var along := float(index) / float(maxi(_points.size() - 1, 1))
	return clampf(1.0 - _ages[index] / POINT_LIFE, 0.0, 1.0) * along


## A ribbon of three vertex rows: solid along the centre line, transparent at
## both edges, so the streak is soft instead of a hard bar. The colour only
## carries the strength; the streak shader paints and tears it.
func _segment(a: Vector3, b: Vector3, fade_a: float, fade_b: float, eye: Vector3, half_width: float, strength: float, step: int, streak: int) -> void:
	var along := b - a
	if along.length_squared() < 0.000001:
		return
	var across := along.cross(eye - a).normalized() * half_width
	var width_a := fade_a * 0.5 + 0.5
	var width_b := fade_b * 0.5 + 0.5
	var u_a := step * POINT_SPACING
	var u_b := (step + 1) * POINT_SPACING
	for half in [-1.0, 1.0]:
		var points := [a, a + across * half * width_a, b + across * half * width_b, b]
		var uvs := [Vector2(u_a, 0.0), Vector2(u_a, 1.0), Vector2(u_b, 1.0), Vector2(u_b, 0.0)]
		var alphas := [strength * fade_a, 0.0, 0.0, strength * fade_b]
		for index in [0, 1, 2, 0, 2, 3]:
			_immediate.surface_set_color(Color(1.0, 1.0, 1.0, alphas[index]))
			_immediate.surface_set_uv(uvs[index])
			_immediate.surface_set_uv2(Vector2(streak, 0.0))
			_immediate.surface_add_vertex(points[index])
