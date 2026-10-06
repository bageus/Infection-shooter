extends SceneTree
const BODY := preload("res://game/features/infected/body_part_mesh.gd")
const BASELINE := preload("res://game/features/infected/tests/fixtures/body_piece_baseline.gd")
const TOPOLOGY := preload("res://game/features/infected/body_part_topology.gd")
var failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var skeleton := Skeleton3D.new()
	root.add_child(skeleton)
	for i in 2:
		skeleton.add_bone("bone_%d" % i)
	var rng := RandomNumberGenerator.new()
	rng.seed = 85051
	for stride in [4, 8]:
		var data := _data(stride)
		for i in 40:
			skeleton.transform = Transform3D(Basis.from_euler(Vector3(.1, i * .02, .2)).scaled(Vector3(1.2, .8, 1.4)), Vector3(2, -3, 4))
			for bone in 2:
				skeleton.set_bone_pose_position(bone, Vector3(rng.randf(), rng.randf(), rng.randf()))
				skeleton.set_bone_pose_rotation(bone, Quaternion(Vector3.UP, rng.randf()))
			skeleton.force_update_all_bone_transforms()
			for chain in [PackedInt32Array([0]), PackedInt32Array([1]), PackedInt32Array([0, 1])]:
				_compare(BASELINE.build_piece(data, chain, skeleton, []), BODY.build_piece(data, chain, skeleton, []))
		var first := TOPOLOGY.for_surface(data, PackedInt32Array([0]), 0)
		var second := TOPOLOGY.for_surface(data, PackedInt32Array([0]), 0)
		_expect(is_same(first, second), "Repeated sever reuses immutable topology")
		_expect(first["vertices"] == PackedInt32Array([0, 1, 2, 3]), "Unique vertices preserve first source appearance")
		_expect(first["indices"] == PackedInt32Array([0, 1, 2, 2, 1, 3]), "Shared corners retain exact remapped triangle order")
		var a := BODY.build_piece(data, PackedInt32Array([0]), skeleton, [])
		skeleton.set_bone_pose_position(0, Vector3(8, 9, 10))
		skeleton.force_update_all_bone_transforms()
		var b := BODY.build_piece(data, PackedInt32Array([0]), skeleton, [])
		_expect(a["center"].distance_to(b["center"]) > 1, "Current pose remains live after topology reuse")
	skeleton.queue_free()
	await process_frame
	print("Body topology tests: %d failure(s)." % failures)
	quit(failures)

func _data(stride: int) -> Dictionary:
	var vertices := PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3(1, 1, 0), Vector3(2, 0, 0), Vector3(2, 1, 0)])
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i in vertices.size():
		for k in stride:
			bones.append((0 if i < 4 else 1) if k == 0 else (1 if i < 4 else 0))
			weights.append(.6 if k == 0 else (.4 if k == 1 else 0.0))
		normals.append(Vector3.BACK)
		uvs.append(Vector2(vertices[i].x, vertices[i].y))
	var surface := {"vertices": vertices, "normals": normals, "uvs": uvs, "bones": bones, "weights": weights, "indices": PackedInt32Array([0, 1, 2, 2, 1, 3, 3, 4, 5]), "stride": stride}
	return {"surfaces": [surface], "binds": {0: Transform3D.IDENTITY, 1: Transform3D.IDENTITY}}

func _compare(a: Dictionary, b: Dictionary) -> void:
	_expect(a.is_empty() == b.is_empty(), "Membership matches baseline")
	if a.is_empty() or b.is_empty():
		return
	_expect(a["center"].distance_to(b["center"]) < .000001, "Part center matches current-pose baseline")
	_expect(a["points"] == b["points"], "Collision hull matches baseline")
	var am: ArrayMesh = a["mesh"]
	var bm: ArrayMesh = b["mesh"]
	_expect(am.get_surface_count() == bm.get_surface_count(), "Surface count matches")
	for i in am.get_surface_count():
		var aa := am.surface_get_arrays(i)
		var bb := bm.surface_get_arrays(i)
		for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_INDEX]:
			_expect(aa[slot] == bb[slot], "Ordered vertex/normal/UV/rest/index arrays match")

func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
