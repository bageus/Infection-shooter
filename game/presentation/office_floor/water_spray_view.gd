extends Node3D

const DURATION := 10.0
const COUNT := 40
const GRAVITY := Vector3(0.0, -9.8, 0.0)

var _host: Node3D
var _outlet: Vector3
var _reverse := false
var _elapsed := 0.0
var _positions: Array[Vector3] = []
var _velocities: Array[Vector3] = []
var _ages: Array[float] = []
var _renderer: MultiMeshInstance3D


func configure(host: Node3D, outlet: Vector3, reverse_direction: bool) -> void:
	_host = host
	_outlet = outlet
	_reverse = reverse_direction


func _ready() -> void:
	name = "BrokenPipeWater"
	global_position = _outlet
	var droplet := SphereMesh.new()
	droplet.radius = 0.5
	droplet.height = 1.0
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
void fragment() {
	float shimmer = 0.86 + 0.14 * sin(TIME * 23.0 + UV.y * 19.0);
	ALBEDO = vec3(0.28, 0.68, 0.92) * shimmer;
	EMISSION = vec3(0.06, 0.21, 0.32) * shimmer;
	ALPHA = 0.66;
}
"""
	material.shader = shader
	droplet.material = material
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
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
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			_ages[index] = -randf_range(0.0, 0.18)
			_hide_drop(index)
			continue
		_positions[index] = next
		_velocities[index] += GRAVITY * delta
		_ages[index] += delta
		_renderer.multimesh.set_instance_transform(index, Transform3D(Basis().scaled(Vector3.ONE * 0.05), next))


func _reset_drop(index: int) -> void:
	_positions[index] = Vector3.ZERO
	var forward := -1.0 if _reverse else 1.0
	_velocities[index] = Vector3(randf_range(-0.52, 0.52), randf_range(0.28, 0.9), forward * randf_range(0.55, 1.0)).normalized() * randf_range(1.8, 3.5)
	_ages[index] = 0.0


func _hide_drop(index: int) -> void:
	_renderer.multimesh.set_instance_transform(index, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
