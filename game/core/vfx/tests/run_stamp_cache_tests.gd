extends SceneTree
const STAMP := preload("res://game/core/vfx/public/surface_stamp.gd")
const CACHE := preload("res://game/core/vfx/public/surface_stamp_cache.gd")
var failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var cache := CACHE.new()
	var receiver := MeshInstance3D.new()
	receiver.mesh = _grid()
	var rng := RandomNumberGenerator.new()
	rng.seed = 72109
	for i in 80:
		var basis := Basis.from_euler(Vector3(rng.randf_range(-.4, .4), rng.randf_range(-.4, .4), rng.randf_range(-.4, .4)))
		basis = basis.scaled(Vector3(-1.3 if i % 2 else 1.3, .7, 2.1))
		receiver.transform = Transform3D(basis, Vector3(2, -3, 4))
		var point := Vector3(rng.randf_range(-14, 14), rng.randf_range(-14, 14), 0)
		var normal := (basis.inverse().transposed() * Vector3.BACK).normalized()
		var turned := Transform3D(Basis.looking_at(-normal, Vector3.UP).rotated(normal, rng.randf_range(-PI, PI)), receiver.transform * point)
		_compare(STAMP.build(receiver, turned, Vector2(1.4, 2.1), .3), cache.build(receiver, turned, Vector2(1.4, 2.1), .3), "Transformed projection %d" % i)
	receiver.transform = Transform3D.IDENTITY
	var projector := Transform3D.IDENTITY
	_compare(STAMP.build(receiver, projector, Vector2.ONE, .2), cache.build(receiver, projector, Vector2.ONE, .2), "Dense projection")
	print("Stamp candidate triangles: %d / 2048" % cache.last_triangle_candidates)
	_expect(cache.last_triangle_candidates < 128, "Local stain avoids a full surface scan")
	var material := StandardMaterial3D.new()
	material.resource_name = "glass"
	receiver.material_override = material
	_compare(STAMP.build(receiver, projector, Vector2.ONE, .2, true), cache.build(receiver, projector, Vector2.ONE, .2, true), "Live glass material")
	receiver.material_override = null
	var box := BoxMesh.new()
	receiver.mesh = box
	_compare(STAMP.build(receiver, projector, Vector2.ONE, .2), cache.build(receiver, projector, Vector2.ONE, .2), "Replacement Mesh")
	box.size = Vector3(2, 3, .2)
	_compare(STAMP.build(receiver, projector, Vector2.ONE, .2), cache.build(receiver, projector, Vector2.ONE, .2), "Mesh.changed rebuild")
	var other := CACHE.new()
	other.build(receiver, projector, Vector2.ONE, .2)
	var before := box.changed.get_connections().size()
	other = null
	_expect(box.changed.get_connections().size() == before - 1, "Independent cache cleanup disconnects its observer")
	for i in 132:
		receiver.mesh = BoxMesh.new()
		cache.build(receiver, projector, Vector2.ONE, 1.0)
	_expect(cache.get("_entries").size() == 128, "Snapshot budget remains bounded")
	receiver.scale = Vector3.ZERO
	_expect(cache.build(receiver, projector, Vector2.ONE, 1.0) == null, "Singular receiver skipped")
	receiver.free()
	cache = null
	print("Stamp cache tests: %d failure(s)." % failures)
	quit(1 if failures else 0)

func _compare(a: ArrayMesh, b: ArrayMesh, label: String) -> void:
	_expect((a == null) == (b == null), label + " presence")
	if a == null or b == null:
		return
	var aa := a.surface_get_arrays(0)
	var bb := b.surface_get_arrays(0)
	for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV]:
		_expect(aa[slot].size() == bb[slot].size(), label + " element count")
		if aa[slot].size() != bb[slot].size():
			continue
		for i in aa[slot].size():
			if aa[slot][i].distance_to(bb[slot][i]) > .000001:
				_expect(false, label + " ordered geometry/normal/UV")
				break

func _grid() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for y in 32:
		for x in 32:
			var a := Vector3(x - 16, y - 16, 0)
			vertices.append_array([a, a + Vector3.RIGHT, a + Vector3(1, 1, 0), a, a + Vector3(1, 1, 0), a + Vector3.UP])
	for i in vertices.size():
		normals.append(Vector3.BACK)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
