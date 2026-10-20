extends Node3D

const DURATION := 10.0
const COUNT := 70
const DROP_SHADER := preload("res://game/presentation/office_floor/water_spray.gdshader")
const SPLASH_SHADER := preload("res://game/presentation/office_floor/water_splash.gdshader")
const SPLASH_SECONDS := 0.35
## Share of the drops that leave a ripple where they land.
const SPLASH_CHANCE := 0.3
const GRAVITY := Vector3(0.0, -9.8, 0.0)

var _host: Node3D
var _outlet: Vector3
var _reverse := false
var _elapsed := 0.0
var _positions: Array[Vector3] = []
var _velocities: Array[Vector3] = []
var _ages: Array[float] = []
var _sizes: Array[float] = []
var _renderer: MultiMeshInstance3D


func configure(host: Node3D, outlet: Vector3, reverse_direction: bool) -> void:
	_host = host
	_outlet = outlet
	_reverse = reverse_direction


func _ready() -> void:
	name = "BrokenPipeWater"
	global_position = _outlet
	var droplet := _droplet_mesh()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	multi.mesh = droplet
	multi.instance_count = COUNT
	_renderer = MultiMeshInstance3D.new()
	_renderer.multimesh = multi
	_renderer.custom_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	add_child(_renderer)
	for index in COUNT:
		_positions.append(Vector3.ZERO)
		_velocities.append(Vector3.ZERO)
		_ages.append(-randf_range(0.0, 0.9))
		_sizes.append(randf_range(0.045, 0.09))
		_hide_drop(index)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION + 0.9:
		queue_free()
		return
	for index in COUNT:
		if _ages[index] < 0.0:
			_ages[index] += delta
			if _ages[index] < 0.0 or _elapsed >= DURATION:
				continue
			_reset_drop(index)
		if _ages[index] >= 0.9:
			_ages[index] = -randf_range(0.0, 0.18)
			_hide_drop(index)
			continue
		var next: Vector3 = _positions[index] + _velocities[index] * delta + GRAVITY * (0.5 * delta * delta)
		var query := PhysicsRayQueryParameters3D.create(to_global(_positions[index]), to_global(next))
		if is_instance_valid(_host) and _host is CollisionObject3D:
			query.exclude = [(_host as CollisionObject3D).get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			if randf() < SPLASH_CHANCE:
				_splash(hit.position, hit.normal)
			_ages[index] = -randf_range(0.0, 0.18)
			_hide_drop(index)
			continue
		_positions[index] = next
		_velocities[index] += GRAVITY * delta
		_ages[index] += delta
		var world_velocity: Vector3 = global_basis * _velocities[index]
		_renderer.multimesh.set_instance_transform(index, Transform3D(Basis(), next))
		_renderer.multimesh.set_instance_custom_data(index, Color(world_velocity.x, world_velocity.y, world_velocity.z, _sizes[index]))


func _reset_drop(index: int) -> void:
	_positions[index] = Vector3.ZERO
	var forward := -1.0 if _reverse else 1.0
	_velocities[index] = Vector3(randf_range(-0.52, 0.52), randf_range(0.28, 0.9), forward * randf_range(0.55, 1.0)).normalized() * randf_range(1.8, 3.5)
	_ages[index] = 0.0


func _hide_drop(index: int) -> void:
	# The shader sizes the quad from custom data alone, so size 0 hides the drop.
	_renderer.multimesh.set_instance_transform(index, Transform3D(Basis(), Vector3.ZERO))
	_renderer.multimesh.set_instance_custom_data(index, Color(0.0, 0.0, 0.0, 0.0))


# A ripple and a few flecks where a drop lands, lying on the surface it hit.
func _splash(point: Vector3, normal: Vector3) -> void:
	var splash := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * 0.5
	splash.mesh = quad
	splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	splash.material_override = _splash_material()
	splash.set_instance_shader_parameter(&"seed", randf())
	get_parent().add_child(splash)
	splash.global_position = point + normal * 0.01
	if absf(normal.dot(Vector3.UP)) < 0.99:
		splash.look_at(point + normal, Vector3.UP)
		splash.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	var tween := splash.create_tween()
	tween.tween_method(func(value: float) -> void: splash.set_instance_shader_parameter(&"progress", value), 0.0, 1.0, SPLASH_SECONDS)
	tween.tween_callback(splash.queue_free)


# One droplet mesh and material shared by every spraying fixture.
static var _droplet: QuadMesh
static var _splash_material_cache: ShaderMaterial


static func _splash_material() -> ShaderMaterial:
	if _splash_material_cache == null:
		_splash_material_cache = ShaderMaterial.new()
		_splash_material_cache.shader = SPLASH_SHADER
	return _splash_material_cache


static func _droplet_mesh() -> QuadMesh:
	if _droplet != null:
		return _droplet
	var material := ShaderMaterial.new()
	material.shader = DROP_SHADER
	_droplet = QuadMesh.new()
	_droplet.size = Vector2.ONE
	_droplet.material = material
	return _droplet
