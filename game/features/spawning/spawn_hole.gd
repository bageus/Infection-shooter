extends RefCounted
## Procedural broken-floor hole: jagged concrete rim, a dark depth centre, loose
## chunks and bent rebar. Flat enough to walk over; purely visual.

const RIM_OUTER := 1.35
const HOLE_RADIUS := 0.8
const SEGMENTS := 28
const RIM_Y := 0.012
const DEPTH_Y := 0.022


static func build(root: Node3D, seed_value: int = 7) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var edge := _edge_radii(rng)
	_add(root, "Rim", _ring_mesh(edge), _concrete_material(rng), RIM_Y)
	_add(root, "Depth", _depth_mesh(edge), _depth_material(), DEPTH_Y)
	_add(root, "Chunks", _chunks_mesh(rng, edge), _chunk_material(), 0.0)
	_add(root, "Rebar", _rebar_mesh(rng, edge), _rebar_material(), 0.0)


static func _edge_radii(rng: RandomNumberGenerator) -> Array[float]:
	var radii: Array[float] = []
	for index in SEGMENTS:
		radii.append(HOLE_RADIUS * rng.randf_range(0.72, 1.12))
	return radii


static func _point(index: int, radius: float, y: float) -> Vector3:
	var angle := TAU * float(index % SEGMENTS) / float(SEGMENTS)
	return Vector3(cos(angle) * radius, y, sin(angle) * radius)


static func _ring_mesh(edge: Array[float]) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	for index in SEGMENTS:
		var outer_a := _point(index, RIM_OUTER * (0.92 + 0.08 * sin(index * 2.3)), 0.0)
		var outer_b := _point(index + 1, RIM_OUTER * (0.92 + 0.08 * sin((index + 1) * 2.3)), 0.0)
		var inner_a := _point(index, edge[index], 0.0)
		var inner_b := _point(index + 1, edge[(index + 1) % SEGMENTS], 0.0)
		for vertex: Vector3 in [outer_a, inner_a, inner_b, outer_a, inner_b, outer_b]:
			tool.set_uv(Vector2(vertex.x, vertex.z) * 0.35 + Vector2(0.5, 0.5))
			tool.add_vertex(vertex)
	return tool.commit()


static func _depth_mesh(edge: Array[float]) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	for index in SEGMENTS:
		var centre_color := Color(0.0, 0.0, 0.0, 1.0)
		var edge_color := Color(0.09, 0.075, 0.07, 1.0)
		tool.set_color(centre_color)
		tool.add_vertex(Vector3.ZERO)
		tool.set_color(edge_color)
		tool.add_vertex(_point(index + 1, edge[(index + 1) % SEGMENTS], 0.0))
		tool.set_color(edge_color)
		tool.add_vertex(_point(index, edge[index], 0.0))
	return tool.commit()


static func _chunks_mesh(rng: RandomNumberGenerator, edge: Array[float]) -> ArrayMesh:
	var combined := SurfaceTool.new()
	combined.begin(Mesh.PRIMITIVE_TRIANGLES)
	for chunk in 16:
		var box := BoxMesh.new()
		var width := rng.randf_range(0.14, 0.38)
		box.size = Vector3(width, rng.randf_range(0.06, 0.16), rng.randf_range(0.12, 0.3))
		var index := rng.randi_range(0, SEGMENTS - 1)
		var radius := edge[index] + rng.randf_range(0.02, RIM_OUTER - HOLE_RADIUS + 0.1)
		var basis := Basis.from_euler(Vector3(rng.randf_range(-0.35, 0.35), rng.randf_range(0.0, TAU), rng.randf_range(-0.35, 0.35)))
		var spot := _point(index, radius, box.size.y * 0.4)
		combined.append_from(box, 0, Transform3D(basis, spot))
	combined.generate_normals()
	return combined.commit()


static func _rebar_mesh(rng: RandomNumberGenerator, edge: Array[float]) -> ArrayMesh:
	var combined := SurfaceTool.new()
	combined.begin(Mesh.PRIMITIVE_TRIANGLES)
	for bar in 5:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.012
		cylinder.bottom_radius = 0.012
		cylinder.height = rng.randf_range(0.35, 0.7)
		cylinder.radial_segments = 5
		cylinder.rings = 1
		var index := rng.randi_range(0, SEGMENTS - 1)
		var lean := Basis.from_euler(Vector3(rng.randf_range(0.6, 1.1), rng.randf_range(0.0, TAU), 0.0))
		combined.append_from(cylinder, 0, Transform3D(lean, _point(index, edge[index] + 0.05, cylinder.height * 0.3)))
	combined.generate_normals()
	return combined.commit()


static func _add(root: Node3D, node_name: String, mesh: Mesh, material: Material, y: float) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position.y = y
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)


static func _concrete_material(rng: RandomNumberGenerator) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.09
	var image := noise.get_image(64, 64)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.66, 0.64, 0.6)
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.roughness = 0.95
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


static func _depth_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


static func _chunk_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.38, 0.37, 0.35)
	material.roughness = 1.0
	return material


static func _rebar_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.32, 0.17, 0.1)
	material.metallic = 0.5
	material.roughness = 0.7
	return material
