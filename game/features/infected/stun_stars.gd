extends MeshInstance3D
## One shared, texture-free mesh: three golden stars orbit the stunned head.
static var _mesh: ArrayMesh
var _age := 0.0
var _fade := -1.0

static func spawn(body: Node3D, height: float, size: float) -> MeshInstance3D:
	var orbit: MeshInstance3D = load("res://game/features/infected/stun_stars.gd").new()
	orbit.name = "StunStars"
	if _mesh == null:
		var vertices := PackedVector3Array()
		for star in 3:
			var center := Vector3(cos(star * TAU / 3.0), 0, sin(star * TAU / 3.0)) * 0.35
			for i in 10:
				vertices.append(center)
				for index: int in [i, i + 1]:
					var angle: float = index * TAU / 10.0
					vertices.append(center + Vector3(cos(angle), 0, sin(angle)) * (0.14 if index % 2 == 0 else 0.06))
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		_mesh = ArrayMesh.new()
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_color = Color(1.0, 0.8, 0.08)
		_mesh.surface_set_material(0, material)
	orbit.mesh = _mesh
	orbit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(orbit)
	orbit.position = Vector3.UP * height
	orbit.scale = Vector3.ONE * size
	orbit.rotation.x = 0.5
	return orbit

func stop(seconds: float) -> void:
	_fade = maxf(seconds, 0.001)

func _process(delta: float) -> void:
	_age += delta
	rotation.y = _age * 2.8
	if _fade >= 0.0:
		var previous := _fade
		_fade = maxf(0.0, _fade - delta)
		scale *= _fade / maxf(previous, 0.001)
		if _fade == 0.0:
			queue_free()
