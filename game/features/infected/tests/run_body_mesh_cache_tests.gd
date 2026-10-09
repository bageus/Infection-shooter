extends SceneTree
const BODY := preload("res://game/features/infected/body_part_mesh.gd")
const CACHE := preload("res://game/features/infected/body_mesh_cache.gd")
const ASSET := "res://models/objects/characters/enemy/game/Revenant_rig_mesh.res"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_reload_asset()
	_binding_identity()
	_limits_and_live_data()
	print("Body mesh cache tests: %d failures" % failures)
	quit(failures)


func _reload_asset() -> void:
	BODY._cache = CACHE.new()
	var skeleton := Skeleton3D.new()
	skeleton.add_bone("Root")
	var first: ArrayMesh
	var ids := {}
	for iteration in 8:
		var instance := MeshInstance3D.new()
		instance.mesh = load(ASSET) as ArrayMesh
		ids[instance.mesh.get_instance_id()] = true
		var data := BODY.prepare(instance, skeleton)
		if iteration == 0:
			first = data.mesh
		_expect(data.mesh == first, "Reloaded asset shares the converted resource")
		_expect(BODY._cache.size() == 1, "Reload does not accumulate asset entries")
		instance.free()
	_expect(ids.size() > 1, "Test exercises newly loaded source identities")
	skeleton.free()


func _binding_identity() -> void:
	BODY._cache = CACHE.new()
	var source := _mesh(0)
	var first := Skeleton3D.new()
	first.add_bone("Root")
	var second := Skeleton3D.new()
	second.add_bone("Other")
	second.add_bone("Root")
	var skin := Skin.new()
	skin.add_named_bind("Root", Transform3D.IDENTITY)
	var a := MeshInstance3D.new()
	a.mesh = source
	a.skin = skin
	var b := MeshInstance3D.new()
	b.mesh = source
	b.skin = skin
	var data_a := BODY.prepare(a, first)
	var data_b := BODY.prepare(b, second)
	_expect(data_a.mesh != data_b.mesh, "Different skeleton mapping must not alias")
	_expect(data_a.surfaces[0].bones[0] == 0 and data_b.surfaces[0].bones[0] == 1, "Bone remapping follows the actor skeleton")
	a.free()
	b.free()
	first.free()
	second.free()


func _limits_and_live_data() -> void:
	BODY._cache = CACHE.new()
	var skeleton := Skeleton3D.new()
	skeleton.add_bone("Root")
	var live: Dictionary
	for index in CACHE.MAX_ENTRIES + 4:
		var instance := MeshInstance3D.new()
		instance.mesh = _mesh(index)
		var data := BODY.prepare(instance, skeleton)
		if index == 0:
			live = data
		instance.free()
	_expect(BODY._cache.size() == CACHE.MAX_ENTRIES, "Generated meshes have a bounded entry count")
	_expect(is_instance_valid(live.mesh) and live.surfaces[0].vertices[0] == Vector3.ZERO, "Eviction preserves data held by live consumers")
	var local := CACHE.new(2)
	local.put("a", live)
	var bytes: int = local.stats().geometry_bytes
	local.put("b", live)
	local.get_data("a")
	local.put("c", live)
	_expect(local.get_data("b").is_empty() and not local.get_data("a").is_empty(), "LRU retains recently reused entries")
	local.put("a", live)
	_expect(local.stats().geometry_bytes == bytes * 2, "Replacing an entry does not double its budget")
	var budget := CACHE.new(CACHE.MAX_ENTRIES, bytes + 1)
	budget.put("a", live)
	budget.put("b", live)
	_expect(budget.size() == 1 and budget.stats().geometry_bytes <= bytes + 1, "Geometry byte budget evicts older entries")
	var oversized := CACHE.new(CACHE.MAX_ENTRIES, bytes - 1)
	oversized.put("a", live)
	_expect(oversized.size() == 0, "A single oversized result is usable without being retained")
	skeleton.free()


func _mesh(offset: int) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(offset, 0, 0), Vector3(offset + 1, 0, 0), Vector3(offset, 1, 0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_BONES] = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
