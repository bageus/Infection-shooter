extends SceneTree
const GEOMETRY := preload("res://game/features/combat/impact_surface_geometry.gd")
const RECEIVERS := preload("res://game/features/combat/impact_receiver_cache.gd")
var failures := 0
var stage: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	_equivalence_and_work()
	_receiver_lifecycle()
	_resource_lifecycle()
	stage.queue_free()
	await process_frame
	print("Impact geometry index tests: %d failures" % failures)
	quit(failures)


func _equivalence_and_work() -> void:
	var body := Node3D.new()
	stage.add_child(body)
	var mesh := MeshInstance3D.new()
	mesh.mesh = _grid(64)
	body.add_child(mesh)
	var geometry := GEOMETRY.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 41937
	for transform in [Transform3D.IDENTITY, Transform3D(Basis.from_euler(Vector3(.2, .5, -.3)).scaled(Vector3(-1.3, .7, 2.0)), Vector3(2, -1, 4))]:
		mesh.transform = transform
		for sample in 80:
			var local := Vector3(rng.randf_range(-2, 66), rng.randf_range(-2, 66), 0)
			var direction := (mesh.global_basis * Vector3.FORWARD).normalized()
			var point := mesh.global_transform * local
			var actual: Dictionary = geometry.resolve(body, point, direction)
			var expected := _brute(mesh, point, direction)
			_check(actual.is_empty() == expected.is_empty(), "Indexed hit/miss equals full triangle scan")
			if not expected.is_empty():
				_check(actual["anchor"] == mesh and actual["position"].is_equal_approx(expected["position"]) and actual["normal"].is_equal_approx(expected["normal"]), "Nearest position and transformed normal match original scan")
	mesh.transform = Transform3D.IDENTITY
	geometry.resolve(body, Vector3(30.25, 31.25, 0), Vector3.FORWARD)
	var tested: int = geometry.last_triangle_tests
	_check(tested > 0 and tested <= 32, "Local ray tests <=32 triangles instead of all 8192")
	print("Impact triangle work: %d / 8192 exact triangle tests" % tested)
	body.free()


func _brute(mesh: MeshInstance3D, point: Vector3, direction: Vector3) -> Dictionary:
	var from := point - direction * .12
	var to := point + direction * 3.0
	var inverse := mesh.global_transform.affine_inverse()
	var triangles := mesh.mesh.get_faces()
	var best := INF
	var result: Dictionary = {}
	for i in range(0, triangles.size() - 2, 3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(inverse * from, inverse * to, triangles[i], triangles[i + 1], triangles[i + 2])
		if hit == null:
			continue
		var world: Vector3 = mesh.global_transform * (hit as Vector3)
		var distance := from.distance_squared_to(world)
		if distance >= best:
			continue
		best = distance
		var normal := (mesh.global_basis.inverse().transposed() * (triangles[i + 1] - triangles[i]).cross(triangles[i + 2] - triangles[i]).normalized()).normalized()
		if normal.dot(direction) > 0:
			normal = -normal
		result = {"position": world, "normal": normal}
	return result


func _receiver_lifecycle() -> void:
	var body := Node3D.new()
	stage.add_child(body)
	var branch := Node3D.new()
	body.add_child(branch)
	var mesh := _box(branch)
	var cache := RECEIVERS.new()
	_check(cache.gather(body) == [mesh], "Initial composition discovers the receiver")
	var rebuilds: int = cache.rebuilds
	cache.gather(body)
	_check(cache.rebuilds == rebuilds, "Repeated lookup reuses tree composition")
	var overlapping := RECEIVERS.new()
	_check(overlapping.gather(body) == [mesh], "Independent pools can cache the same live branch")
	_check(cache.gather(branch) == [mesh], "Nested roots can be cached independently")
	overlapping = null
	cache = null
	cache = RECEIVERS.new()
	cache.gather(body)
	rebuilds = cache.rebuilds
	branch.hide()
	_check(cache.gather(body).is_empty(), "Hidden ancestor suppresses cached receiver")
	branch.show()
	mesh.scale = Vector3.ZERO
	_check(cache.gather(body).is_empty(), "Collapsed damage-stage mesh is excluded")
	mesh.scale = Vector3.ONE
	branch.set_meta("blood_effect", true)
	_check(cache.gather(body).is_empty(), "Effect metadata on ancestors is evaluated live")
	branch.remove_meta("blood_effect")
	_check(cache.gather(body) == [mesh] and cache.rebuilds == rebuilds, "Visibility, scale and metadata do not rebuild composition")
	var added := _box(branch)
	_check(cache.gather(body).size() == 2, "Adding a receiver invalidates composition")
	branch.remove_child(added)
	_check(cache.gather(body) == [mesh], "Removing a receiver invalidates composition")
	added.free()
	var other := Node3D.new()
	stage.add_child(other)
	mesh.reparent(other)
	_check(cache.gather(body).is_empty() and cache.gather(other) == [mesh], "Reparenting transfers receiver ownership")
	cache = null
	_check(other.child_order_changed.get_connections().is_empty(), "Cache destruction disconnects its weak callbacks")
	body.free()
	other.free()


func _resource_lifecycle() -> void:
	var body := Node3D.new()
	stage.add_child(body)
	var mesh := _box(body)
	var geometry := GEOMETRY.new()
	var point := Vector3(0, 0, .6)
	var hit: Dictionary = geometry.resolve(body, point, Vector3.FORWARD)
	_check(is_equal_approx(hit["position"].z, .5), "Initial box surface is found")
	var shared := mesh.mesh as BoxMesh
	var independent := GEOMETRY.new()
	independent.resolve(body, point, Vector3.FORWARD)
	shared.size = Vector3.ONE * .4
	hit = geometry.resolve(body, point, Vector3.FORWARD)
	_check(is_equal_approx(hit["position"].z, .2), "Resource.changed rebuilds triangle index")
	hit = independent.resolve(body, point, Vector3.FORWARD)
	_check(is_equal_approx(hit["position"].z, .2), "Shared resources invalidate independent geometry pools")
	independent = null
	mesh.mesh = BoxMesh.new()
	hit = geometry.resolve(body, point, Vector3.FORWARD)
	_check(is_equal_approx(hit["position"].z, .5), "Replacing the mesh uses its own index")
	mesh.position.z = -1.0
	hit = geometry.resolve(body, Vector3(0, 0, -.4), Vector3.FORWARD)
	_check(is_equal_approx(hit["position"].z, -.5), "Moving a receiver retains live hit transforms")
	mesh.hide()
	_check(geometry.resolve(body, point, Vector3.FORWARD).is_empty(), "A cached hidden mesh cannot receive a hit")
	mesh.show()
	for i in 132:
		mesh.mesh = BoxMesh.new()
		geometry.resolve(body, Vector3(0, 0, -.4), Vector3.FORWARD)
	_check((geometry.get("_indices") as Dictionary).size() == 128, "Index retention is bounded without whole-cache resets")
	var connections := mesh.mesh.changed.get_connections().size()
	geometry = null
	_check(shared.changed.get_connections().is_empty() and mesh.mesh.changed.get_connections().size() == connections - 1, "Index eviction and disposal disconnect resource callbacks")
	body.free()


func _box(parent: Node3D) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	parent.add_child(mesh)
	return mesh


func _grid(width: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	for y in width:
		for x in width:
			var a := Vector3(x, y, 0)
			vertices.append_array([a, a + Vector3.RIGHT, a + Vector3.UP, a + Vector3.RIGHT, a + Vector3(1, 1, 0), a + Vector3.UP])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
